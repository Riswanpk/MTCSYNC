import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Navigation/user_cache_service.dart';
import 'leadsform.dart';

/// Page for sales/manager/asst_manager users to screen SME-assigned leads.
/// Users call the customer, then promote (add to leads) or reject the lead.
class SmeAssignedLeadsPage extends StatefulWidget {
  const SmeAssignedLeadsPage({super.key});

  @override
  State<SmeAssignedLeadsPage> createState() => _SmeAssignedLeadsPageState();
}

class _SmeAssignedLeadsPageState extends State<SmeAssignedLeadsPage>
    with WidgetsBindingObserver {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _brandAccent = Color(0xFF008BD6);
  static const Color _teal = Color(0xFF00897B);

  String _selectedFilter = 'Pending';
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isLoading = false;

  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument;
  int _currentPage = 1;
  final int _leadsPerPage = 15;
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null};

  // Call detection state
  String? _pendingCallNumber;
  DateTime? _callStartTime;
  String? _pendingCallDocId;

  // User info
  String? _currentUid;
  String? _currentRole;
  String? _currentBranch;
  final Map<String, String> _assignerNameCache = {};

  final List<String> _filterOptions = [
    'Pending',
    'Called',
    'Promoted',
    'Rejected',
    'All',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCallNumber != null) {
      _checkIfCallWasMade().then((_) {
        if (_pendingCallNumber != null && mounted) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && _pendingCallNumber != null) _checkIfCallWasMade();
          });
        }
      });
    }
  }

  Future<void> _initialize() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final cache = UserCacheService.instance;
    await cache.ensureLoaded();

    setState(() {
      _currentUid = uid;
      _currentRole = cache.role;
      _currentBranch = cache.branch;
    });

    await _restorePendingCallState();
    _fetchLeadsPage();
  }

  // ── Firestore Fetch ──────────────────────────────────────────────────

  Future<void> _fetchLeadsPage({
    bool nextPage = false,
    bool prevPage = false,
    bool isSearch = false,
  }) async {
    if (_isLoading || _currentUid == null) return;
    setState(() => _isLoading = true);

    Query query = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('source', whereIn: ['sme', 'SME']);

    // Role-based filtering
    if (_currentRole == 'sales') {
      query = query.where('assigned_to', isEqualTo: _currentUid);
    } else if (_currentRole == 'manager' || _currentRole == 'asst_manager') {
      if (_currentBranch != null && _currentBranch!.isNotEmpty) {
        query = query.where('branch', isEqualTo: _currentBranch);
      }
    }

    // Status filter
    if (_selectedFilter != 'All') {
      final filterValue = _selectedFilter.toLowerCase();
      query = query.where('screening_status', isEqualTo: filterValue);
    }

    query = query.orderBy('created_at', descending: true);

    QuerySnapshot snapshot;

    if (isSearch && _searchQuery.isNotEmpty) {
      snapshot = await query.get();
    } else {
      DocumentSnapshot? cursor;
      if (nextPage) {
        cursor = _lastDocument;
        _currentPage++;
      } else if (prevPage && _currentPage > 1) {
        _currentPage--;
        cursor = _pageStartCursors[_currentPage];
      }

      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      snapshot = await query.limit(_leadsPerPage).get();
    }

    if (snapshot.docs.isNotEmpty && (!isSearch || _searchQuery.isEmpty)) {
      _lastDocument = snapshot.docs.last;
      _pageStartCursors[_currentPage + 1] = _lastDocument;
    } else {
      _lastDocument = null;
    }

    if (!mounted) return;
    setState(() {
      _leads = snapshot.docs;
      _isLoading = false;
    });

    // Prefetch assigner names
    await _prefetchAssignerNames(snapshot.docs);
  }

  Future<void> _prefetchAssignerNames(List<DocumentSnapshot> docs) async {
    final ids = docs
        .map((d) => (d.data() as Map<String, dynamic>)['assigned_by'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_assignerNameCache.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    for (var i = 0; i < ids.length; i += 30) {
      final batch = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        map[doc.id] =
            (doc.data())['username'] as String? ?? 'Unknown';
      }
      if (mounted) setState(() => _assignerNameCache.addAll(map));
    }
  }

  void _resetAndFetch() {
    _pageStartCursors.clear();
    _pageStartCursors[1] = null;
    _currentPage = 1;
    _lastDocument = null;
    _fetchLeadsPage();
  }

  // ── Call Detection ───────────────────────────────────────────────────

  Future<void> _makeCall(String phone, String docId) async {
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number available')),
        );
      }
      return;
    }

    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission denied')),
        );
      }
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      _pendingCallNumber = phone;
      _callStartTime = DateTime.now();
      _pendingCallDocId = docId;
      await _savePendingCallState();
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer')),
        );
      }
    }
  }

  Future<void> _checkIfCallWasMade() async {
    if (_pendingCallNumber == null || _callStartTime == null) return;

    final permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) return;

    try {
      final now = DateTime.now();
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: _callStartTime!.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      final normalizedPending =
          _pendingCallNumber!.replaceAll(RegExp(r'\D'), '');

      CallLogEntry? matchedEntry;
      for (final entry in entries) {
        final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        final wasConnected = (entry.duration ?? 0) > 15;
        if (logNumber.endsWith(normalizedPending) && wasConnected) {
          matchedEntry = entry;
          break;
        }
      }

      if (matchedEntry != null && _pendingCallDocId != null) {
        // Update Firestore
        await FirebaseFirestore.instance
            .collection('follow_ups')
            .doc(_pendingCallDocId!)
            .update({
          'screening_status': 'called',
          'screening_call_time': FieldValue.serverTimestamp(),
          'screening_call_duration': matchedEntry.duration ?? 0,
          'screened_by': _currentUid,
        });

        _pendingCallNumber = null;
        _callStartTime = null;
        _pendingCallDocId = null;
        await _clearPendingCallState();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Call detected (${matchedEntry.duration}s) — Lead marked as Called'),
              backgroundColor: _teal,
            ),
          );
          // Refresh the list to show updated status
          _resetAndFetch();
        }
      }
    } catch (e) {
      debugPrint('Error checking call log: $e');
    }
  }

  Future<void> _savePendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sme_pending_call_number', _pendingCallNumber ?? '');
    await prefs.setInt(
        'sme_pending_call_time',
        _callStartTime?.millisecondsSinceEpoch ?? 0);
    await prefs.setString('sme_pending_call_docid', _pendingCallDocId ?? '');
  }

  Future<void> _clearPendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sme_pending_call_number');
    await prefs.remove('sme_pending_call_time');
    await prefs.remove('sme_pending_call_docid');
  }

  Future<void> _restorePendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNumber = prefs.getString('sme_pending_call_number');
    final savedTime = prefs.getInt('sme_pending_call_time');
    final savedDocId = prefs.getString('sme_pending_call_docid');
    if (savedNumber != null &&
        savedNumber.isNotEmpty &&
        savedTime != null &&
        savedTime > 0) {
      _pendingCallNumber = savedNumber;
      _callStartTime = DateTime.fromMillisecondsSinceEpoch(savedTime);
      _pendingCallDocId = savedDocId;
      _checkIfCallWasMade();
    }
  }

  // ── WhatsApp ─────────────────────────────────────────────────────────

  Future<void> _openWhatsApp(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    String number = cleaned;
    if (!number.startsWith('+')) {
      // Default to India country code
      number = '+91$number';
    }
    final uri = Uri.parse('https://wa.me/$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Screening Actions ──────────────────────────────────────────────

  Future<void> _promoteToLead(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;

    // Navigate to leads form pre-filled with SME lead data
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowUpForm(
          initialName: data['name'] ?? '',
          initialPhone: data['phone'] ?? '',
          initialAddress: data['address'] ?? '',
          source: 'SME',
        ),
      ),
    );

    if (result == true && mounted) {
      // Mark the SME lead as promoted
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(doc.id)
          .update({
        'screening_status': 'promoted',
        'screened_by': _currentUid,
        'screened_at': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lead promoted successfully!'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      _resetAndFetch();
    }
  }

  Future<void> _rejectLead(DocumentSnapshot doc) async {
    final reason = await _showRejectDialog();
    if (reason == null || reason.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('follow_ups')
        .doc(doc.id)
        .update({
      'screening_status': 'rejected',
      'rejection_reason': reason,
      'screened_by': _currentUid,
      'screened_at': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lead rejected'),
          backgroundColor: Color(0xFFF44336),
        ),
      );
      _resetAndFetch();
    }
  }

  Future<String?> _showRejectDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Color(0xFFF44336), size: 24),
            SizedBox(width: 8),
            Text('Reject Lead', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter reason for rejection...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF44336),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reject',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _addScreeningNotes(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final existingNotes = data['screening_notes'] ?? '';
    final controller = TextEditingController(text: existingNotes);

    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: _brandPrimary, size: 24),
            SizedBox(width: 8),
            Text('Screening Notes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Add your notes about this lead...',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child:
                const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (notes != null && mounted) {
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(doc.id)
          .update({'screening_notes': notes});
      _resetAndFetch();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.toLowerCase().trim());
                  _fetchLeadsPage(isSearch: true);
                },
              )
            : const Text(
                'SME Leads',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                ),
              ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_brandPrimary, _brandAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _resetAndFetch();
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: _filterOptions.map((filter) {
                  final isActive = _selectedFilter == filter;
                  final color = _getFilterColor(filter);
                  final count = filter == 'All' ? null : _getFilterIcon(filter);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedFilter = filter);
                        _resetAndFetch();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? color.withValues(alpha: 0.15)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.grey.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isActive
                                ? color.withValues(alpha: 0.6)
                                : Colors.grey.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(count, size: 14,
                                color: isActive ? color : Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              filter,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isActive
                                    ? color
                                    : (isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Leads list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _resetAndFetch(),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _leads.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      color: _brandPrimary
                                          .withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.inbox_rounded,
                                      size: 44,
                                      color: _brandPrimary
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No $_selectedFilter leads',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : const Color(0xFF143A52),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'SME-assigned leads will appear here',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                          itemCount: _leads.length,
                          itemBuilder: (context, index) {
                            final doc = _leads[index];
                            final data =
                                doc.data() as Map<String, dynamic>;
                            final name = data['name'] ?? 'No Name';

                            if (_searchQuery.isNotEmpty &&
                                !name
                                    .toLowerCase()
                                    .contains(_searchQuery)) {
                              return const SizedBox.shrink();
                            }

                            return _buildLeadCard(doc, data, isDark);
                          },
                        ),
            ),
          ),
          // Pagination
          if (!_isLoading && _searchQuery.isEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paginationButton(
                    icon: Icons.chevron_left_rounded,
                    enabled: _currentPage > 1,
                    onTap: () => _fetchLeadsPage(prevPage: true),
                    isDark: isDark,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                      color: _brandPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Page $_currentPage',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  _paginationButton(
                    icon: Icons.chevron_right_rounded,
                    enabled: _lastDocument != null &&
                        _leads.length == _leadsPerPage,
                    onTap: () => _fetchLeadsPage(nextPage: true),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Lead Card ────────────────────────────────────────────────────────

  Widget _buildLeadCard(
      DocumentSnapshot doc, Map<String, dynamic> data, bool isDark) {
    final name = data['name'] ?? 'No Name';
    final phone = data['phone'] ?? '';
    final comments = data['comments'] ?? '';
    final priority = data['priority'] ?? 'High';
    final platform = data['platform'] ?? '';
    final branch = data['branch'] ?? '';
    final screeningStatus = data['screening_status'] ?? 'pending';
    final screeningNotes = data['screening_notes'] ?? '';
    final rejectionReason = data['rejection_reason'] ?? '';
    final assignedById = data['assigned_by'] ?? '';
    final assignerName = _assignerNameCache[assignedById] ?? 'SME User';
    final callDuration = data['screening_call_duration'] as int?;

    // Parse date
    String formattedDate = 'No Date';
    final date = data['date'];
    if (date is Timestamp) {
      formattedDate = DateFormat('dd-MM-yyyy').format(date.toDate());
    } else if (date is DateTime) {
      formattedDate = DateFormat('dd-MM-yyyy').format(date);
    }

    final statusColor = _getScreeningStatusColor(screeningStatus);
    final priorityColor = _getPriorityColor(priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // Header with status accent
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: statusColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name + Status badge row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF0D2B40),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _screeningStatusLabel(screeningStatus),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Phone row
                          if (phone.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.phone_rounded,
                                    size: 12, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    phone,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 4),
                          // Date + Assigner row
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 11, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text(
                                formattedDate,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.person_outline_rounded,
                                  size: 12, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'by $assignerName',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Info chips row
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _infoChip(
                                icon: Icons.business_rounded,
                                value: branch,
                                isDark: isDark,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: priorityColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.flag_rounded,
                                        size: 12, color: priorityColor),
                                    const SizedBox(width: 3),
                                    Text(
                                      priority,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: priorityColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (platform.isNotEmpty)
                                _infoChip(
                                  icon: Icons.share_rounded,
                                  value: platform,
                                  isDark: isDark,
                                ),
                              if (callDuration != null)
                                _infoChip(
                                  icon: Icons.timer_rounded,
                                  value: '${callDuration}s call',
                                  isDark: isDark,
                                ),
                            ],
                          ),
                          // SME Comments
                          if (comments.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : const Color(0xFFF5F8FA),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SME Notes',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    comments,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Screening notes
                          if (screeningNotes.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _brandPrimary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _brandPrimary.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your Notes',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _brandPrimary.withValues(alpha: 0.6),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    screeningNotes,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      height: 1.3,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          // Rejection reason
                          if (screeningStatus == 'rejected' &&
                              rejectionReason.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF44336)
                                    .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFF44336)
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rejection Reason',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFF44336)
                                          .withValues(alpha: 0.7),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    rejectionReason,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons bar
            Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.15),
                  ),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Call button
                  _actionButton(
                    icon: Icons.phone_rounded,
                    label: 'Call',
                    color: _teal,
                    onTap: () => _makeCall(phone, doc.id),
                  ),
                  const SizedBox(width: 6),
                  // WhatsApp button
                  _actionButton(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => _openWhatsApp(phone),
                  ),
                  const SizedBox(width: 6),
                  // Notes button
                  _actionButton(
                    icon: Icons.edit_note_rounded,
                    label: 'Notes',
                    color: _brandPrimary,
                    onTap: () => _addScreeningNotes(doc),
                  ),
                  const Spacer(),
                  // Promote / Reject buttons (only for non-final states)
                  if (screeningStatus == 'pending' ||
                      screeningStatus == 'called') ...[
                    _actionButton(
                      icon: Icons.check_circle_rounded,
                      label: 'Promote',
                      color: const Color(0xFF4CAF50),
                      filled: true,
                      onTap: () => _promoteToLead(doc),
                    ),
                    const SizedBox(width: 6),
                    _actionButton(
                      icon: Icons.cancel_rounded,
                      label: 'Reject',
                      color: const Color(0xFFF44336),
                      onTap: () => _rejectLead(doc),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border:
              filled ? null : Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _brandPrimary),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paginationButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: enabled
              ? _brandPrimary.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? _brandPrimary : Colors.grey.shade400,
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String _screeningStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'called':
        return 'Called';
      case 'promoted':
        return 'Promoted';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  Color _getScreeningStatusColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFFC107);
      case 'called':
        return const Color(0xFF2196F3);
      case 'promoted':
        return const Color(0xFF4CAF50);
      case 'rejected':
        return const Color(0xFFF44336);
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return const Color(0xFFF44336);
      case 'Medium':
        return const Color(0xFFFFA500);
      case 'Low':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  Color _getFilterColor(String filter) {
    switch (filter) {
      case 'Pending':
        return const Color(0xFFFFC107);
      case 'Called':
        return const Color(0xFF2196F3);
      case 'Promoted':
        return const Color(0xFF4CAF50);
      case 'Rejected':
        return const Color(0xFFF44336);
      case 'All':
        return _brandPrimary;
      default:
        return Colors.grey;
    }
  }

  IconData _getFilterIcon(String filter) {
    switch (filter) {
      case 'Pending':
        return Icons.hourglass_empty_rounded;
      case 'Called':
        return Icons.phone_callback_rounded;
      case 'Promoted':
        return Icons.check_circle_rounded;
      case 'Rejected':
        return Icons.cancel_rounded;
      case 'All':
        return Icons.all_inclusive_rounded;
      default:
        return Icons.circle;
    }
  }
}
