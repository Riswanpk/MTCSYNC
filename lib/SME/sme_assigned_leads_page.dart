import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Navigation/user_cache_service.dart';
import '../Leads/leadsform.dart';
import 'sme_call_scanner_service.dart';
import 'sme_call_detected_remarks_dialog.dart';

/// Page for sales/manager/asst_manager users to screen SME-assigned leads.
/// Users tap a card -> detail page -> call button -> call detection -> promote/reject.
class SmeAssignedLeadsPage extends StatefulWidget {
  const SmeAssignedLeadsPage({super.key});

  @override
  State<SmeAssignedLeadsPage> createState() => _SmeAssignedLeadsPageState();
}

class _SmeAssignedLeadsPageState extends State<SmeAssignedLeadsPage>
    with WidgetsBindingObserver {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _brandAccent = Color(0xFF008BD6);

  String _selectedFilter = 'Pending';
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isLoading = false;

  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument;
  int _currentPage = 1;
  final int _leadsPerPage = 15;
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null};

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
    // Auto-detection on app resume disabled. Users can tap the reload button to check for calls.
  }

  Future<void> _scanCallLogAndShowMatches() async {
    if (_leads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No leads to check.'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    var status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone permission denied')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      List<Map<String, dynamic>> leadMaps = _leads.map((doc) {
        final map =
            Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        map['_docSnapshot'] = doc;
        map['_assignerName'] =
            _assignerNameCache[map['assigned_by'] ?? ''] ?? 'SME User';
        return map;
      }).toList();

      List<Map<String, dynamic>> matchedLeads =
          await SmeCallScannerService.scanTodayCallLog(leadMaps,
              currentUid: _currentUid);

      if (!mounted) return;
      Navigator.of(context).pop();

      if (matchedLeads.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No new calls detected for today.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => SmeCallDetectedRemarksDialog(
            leads: matchedLeads,
            currentUid: _currentUid ?? '',
            titleText: 'Calls Detected',
            onRefreshNeeded: () {
              _resetAndFetch();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Error scanning call log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error scanning call log: $e'),
              backgroundColor: Colors.red),
        );
      }
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
    _fetchLeadsPage();
  }

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

    if (_currentRole == 'sales') {
      query = query.where('assigned_to', isEqualTo: _currentUid);
    } else if (_currentRole == 'manager' || _currentRole == 'asst_manager') {
      if (_currentBranch != null && _currentBranch!.isNotEmpty) {
        query = query.where('branch', isEqualTo: _currentBranch);
      }
    }

    if (_selectedFilter != 'All' && _selectedFilter != 'Pending') {
      query = query.where('screening_status',
          isEqualTo: _selectedFilter.toLowerCase());
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
      if (cursor != null) query = query.startAfterDocument(cursor);
      snapshot = await query.limit(_leadsPerPage).get();
    }

    if (snapshot.docs.isNotEmpty && (!isSearch || _searchQuery.isEmpty)) {
      _lastDocument = snapshot.docs.last;
      _pageStartCursors[_currentPage + 1] = _lastDocument;
    } else {
      _lastDocument = null;
    }

    List<DocumentSnapshot> docs = snapshot.docs;
    if (_selectedFilter == 'Pending') {
      docs = docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status =
            (data['screening_status'] ?? 'pending').toString().toLowerCase();
        return status == 'pending';
      }).toList();
    }

    if (!mounted) return;
    setState(() {
      _leads = docs;
      _isLoading = false;
    });
    await _prefetchAssignerNames(docs);
  }

  Future<void> _prefetchAssignerNames(List<DocumentSnapshot> docs) async {
    final ids = docs
        .map(
            (d) => (d.data() as Map<String, dynamic>)['assigned_by'] as String?)
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
        map[doc.id] = (doc.data())['username'] as String? ?? 'Unknown';
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
                    fontWeight: FontWeight.w700, fontFamily: 'Montserrat'),
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan Call Log',
            onPressed: _scanCallLogAndShowMatches,
          ),
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
                    offset: const Offset(0, 4)),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: _filterOptions.map((filter) {
                  final isActive = _selectedFilter == filter;
                  final color = _getFilterColor(filter);
                  final icon = _getFilterIcon(filter);
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
                            Icon(icon,
                                size: 14,
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
                                      color:
                                          _brandPrimary.withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.inbox_rounded,
                                        size: 44,
                                        color: _brandPrimary.withValues(
                                            alpha: 0.45)),
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
                                  Text('SME-assigned leads will appear here',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500)),
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
                            final data = doc.data() as Map<String, dynamic>;
                            final name = data['name'] ?? 'No Name';
                            if (_searchQuery.isNotEmpty &&
                                !name.toLowerCase().contains(_searchQuery)) {
                              return const SizedBox.shrink();
                            }
                            return _buildLeadCard(doc, data, isDark);
                          },
                        ),
            ),
          ),
          if (!_isLoading && _searchQuery.isEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
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
                      isDark: isDark),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                    decoration: BoxDecoration(
                        color: _brandPrimary,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('Page $_currentPage',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  _paginationButton(
                      icon: Icons.chevron_right_rounded,
                      enabled: _lastDocument != null &&
                          _leads.length == _leadsPerPage,
                      onTap: () => _fetchLeadsPage(nextPage: true),
                      isDark: isDark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeadCard(
      DocumentSnapshot doc, Map<String, dynamic> data, bool isDark) {
    final name = data['name'] ?? 'No Name';
    final phone = data['phone'] ?? '';
    final priority = data['priority'] ?? 'High';
    final branch = data['branch'] ?? '';
    final screeningStatus = data['screening_status'] ?? 'pending';
    final assignedById = data['assigned_by'] ?? '';
    final assignerName = _assignerNameCache[assignedById] ?? 'SME User';

    String formattedDate = 'No Date';
    final date = data['date'];
    if (date is Timestamp) {
      formattedDate = DateFormat('dd-MM-yyyy').format(date.toDate());
    } else if (date is DateTime) {
      formattedDate = DateFormat('dd-MM-yyyy').format(date);
    }

    final statusColor = _getScreeningStatusColor(screeningStatus);
    final priorityColor = _getPriorityColor(priority);

    return GestureDetector(
      onTap: () async {
        final needRefresh = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => SmeLeadDetailPage(
              doc: doc,
              data: data,
              assignerName: assignerName,
              currentUid: _currentUid ?? '',
            ),
          ),
        );
        if (needRefresh == true && mounted) _resetAndFetch();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.07),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: statusColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF0D2B40),
                                      height: 1.3)),
                            ),
                            const SizedBox(width: 8),
                            if (data['pendingDeletion'] == true) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'PENDING DELETION',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                  _screeningStatusLabel(screeningStatus),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                      letterSpacing: 0.2)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (phone.isNotEmpty)
                          Row(children: [
                            Icon(Icons.phone_rounded,
                                size: 12, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(phone,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 11, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(formattedDate,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade500)),
                          const SizedBox(width: 12),
                          Icon(Icons.person_outline_rounded,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('by $assignerName',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                    fontStyle: FontStyle.italic),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (branch.isNotEmpty) ...[
                            _infoChip(
                                icon: Icons.business_rounded,
                                value: branch,
                                isDark: isDark),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                                color: priorityColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.flag_rounded,
                                  size: 12, color: priorityColor),
                              const SizedBox(width: 3),
                              Text(priority,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: priorityColor)),
                            ]),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: Colors.grey.shade400),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(
      {required IconData icon, required String value, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: _brandPrimary),
        const SizedBox(width: 4),
        Text(value,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
      ]),
    );
  }

  Widget _paginationButton(
      {required IconData icon,
      required bool enabled,
      required VoidCallback onTap,
      required bool isDark}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: enabled
                ? _brandPrimary.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(19)),
        child: Icon(icon,
            size: 22, color: enabled ? _brandPrimary : Colors.grey.shade400),
      ),
    );
  }

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

// ════════════════════════════════════════════════════════════════════════════
// Lead Detail Page From Doc ID (For Notification Deep-Linking)
// ════════════════════════════════════════════════════════════════════════════

class SmeLeadDetailPageFromId extends StatelessWidget {
  final String docId;
  const SmeLeadDetailPageFromId({super.key, required this.docId});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('follow_ups').doc(docId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Lead Not Found')),
            body: const Center(child: Text('Lead document does not exist.')),
          );
        }
        final data = doc.data() as Map<String, dynamic>;
        final assignedByUid = data['assigned_by'] as String? ?? '';

        return FutureBuilder<DocumentSnapshot>(
          future: assignedByUid.isNotEmpty
              ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(assignedByUid)
                  .get()
              : null,
          builder: (context, userSnap) {
            String assignerName = 'System';
            if (userSnap.hasData &&
                userSnap.data != null &&
                userSnap.data!.exists) {
              assignerName = (userSnap.data!.data()
                      as Map<String, dynamic>?)?['username'] ??
                  'Unknown';
            }
            return SmeLeadDetailPage(
              doc: doc,
              data: data,
              assignerName: assignerName,
              currentUid: currentUid,
            );
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Lead Detail Page
// ════════════════════════════════════════════════════════════════════════════

class SmeLeadDetailPage extends StatefulWidget {
  final DocumentSnapshot doc;
  final Map<String, dynamic> data;
  final String assignerName;
  final String currentUid;

  const SmeLeadDetailPage({
    super.key,
    required this.doc,
    required this.data,
    required this.assignerName,
    required this.currentUid,
  });

  @override
  State<SmeLeadDetailPage> createState() => _SmeLeadDetailPageState();
}

class _SmeLeadDetailPageState extends State<SmeLeadDetailPage> {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _brandAccent = Color(0xFF008BD6);
  static const Color _teal = Color(0xFF00897B);

  late Map<String, dynamic> _data;
  bool _needRefresh = false;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
    _refreshData();
  }

  Future<void> _refreshData() async {
    final snap = await FirebaseFirestore.instance
        .collection('follow_ups')
        .doc(widget.doc.id)
        .get();
    if (snap.exists && mounted)
      setState(() => _data = snap.data() as Map<String, dynamic>);
  }

  Future<void> _scanCurrentLeadCallLog() async {
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission denied')),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final map = Map<String, dynamic>.from(_data);
      map['docId'] = widget.doc.id;

      final matched = await SmeCallScannerService.scanTodayCallLog([map], currentUid: widget.currentUid);

      if (mounted) Navigator.of(context).pop();

      if (matched.isNotEmpty) {
        _needRefresh = true;
        await _refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call detected! Lead marked as Called.'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No call detected for today.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Error scanning lead call log: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning call log: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _addScreeningNotes() async {
    final existingNotes = _data['screening_notes'] ?? '';
    final controller = TextEditingController(text: existingNotes);
    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.edit_note_rounded, color: _brandPrimary, size: 24),
          SizedBox(width: 8),
          Text('Screening Notes',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Add your notes about this lead...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: _brandPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (notes != null && mounted) {
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.doc.id)
          .update({'screening_notes': notes});
      _needRefresh = true;
      await _refreshData();
    }
  }

  Future<void> _requestDeletion() async {
    if (_data['pendingDeletion'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deletion request is already pending approval.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Request Lead Deletion',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to request deletion of this lead? It will require approval from an SME team lead.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: reasonController,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter reason for deletion...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Reason is required'
                    : null,
              ),
            ],
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
                Navigator.of(ctx).pop(reasonController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Submit Request',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final cache = UserCacheService.instance;
      await cache.ensureLoaded();

      final leadRef = FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.doc.id);
      final reqRef =
          FirebaseFirestore.instance.collection('sme_deletion_requests').doc();

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        transaction.update(leadRef, {'pendingDeletion': true});
        transaction.set(reqRef, {
          'leadId': widget.doc.id,
          'leadData': _data,
          'reason': reason,
          'requestedBy': widget.currentUid,
          'userName': cache.username ?? '',
          'userBranch': cache.branch ?? '',
          'userEmail': FirebaseAuth.instance.currentUser?.email ?? '',
          'status': 'pending',
          'requestedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading indicator

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deletion request submitted for SME approval.'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // dismiss loading indicator
      debugPrint('Error requesting lead deletion: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error requesting deletion: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _onCallPressed() async {
    final phone = _data['phone'] ?? '';
    if (phone.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No phone number available')));
      return;
    }
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone permission denied')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch dialer')));
    }
  }

  Future<void> _promoteToLead() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowUpForm(
          docId: widget.doc.id,
          initialName: _data['name'] ?? '',
          initialPhone: _data['phone'] ?? '',
          initialAddress: _data['address'] ?? '',
          initialPlatform: _data['platform'] ?? '',
          initialPriority: _data['priority'] ?? 'High',
          initialAdName: _data['ad_name'] ?? '',
          source: 'SME',
        ),
      ),
    );
    if (result == true && mounted) {
      final updateMap = <String, dynamic>{
        'screening_status': 'promoted',
        'screened_by': widget.currentUid,
        'screened_at': FieldValue.serverTimestamp(),
      };
      if (_data['created_at'] == null) {
        updateMap['created_at'] = FieldValue.serverTimestamp();
      }
      if (_data['assigned_to'] != null && (_data['assigned_to_name'] == null || _data['assigned_to_name'] == 'Unknown' || _data['assigned_to_name'] == '')) {
        updateMap['assigned_to'] = _data['assigned_to'];
      }
      await FirebaseFirestore.instance
          .collection('follow_ups')
          .doc(widget.doc.id)
          .update(updateMap);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lead promoted successfully!'),
          backgroundColor: Color(0xFF4CAF50)));
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _rejectLead() async {
    final reason = await _showRejectDialog();
    if (reason == null || reason.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('follow_ups')
        .doc(widget.doc.id)
        .update({
      'screening_status': 'rejected',
      'rejection_reason': reason,
      'screened_by': widget.currentUid,
      'screened_at': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lead rejected'), backgroundColor: Color(0xFFF44336)));
      Navigator.of(context).popUntil((route) => route.isFirst);
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
        title: const Row(children: [
          Icon(Icons.cancel_rounded, color: Color(0xFFF44336), size: 24),
          SizedBox(width: 8),
          Text('Reject Lead',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter reason for rejection...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate())
                Navigator.of(ctx).pop(controller.text.trim());
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF44336),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _data['name'] ?? 'No Name';
    final phone = _data['phone'] ?? '';
    final comments = _data['comments'] ?? '';
    final priority = _data['priority'] ?? 'High';
    final platform = _data['platform'] ?? '';
    final branch = _data['branch'] ?? '';
    final address = _data['address'] ?? '';
    final screeningStatus = _data['screening_status'] ?? 'pending';
    final screeningNotes = _data['screening_notes'] ?? '';
    final rejectionReason = _data['rejection_reason'] ?? '';
    final callDuration = _data['screening_call_duration'] as int?;

    String formattedDate = 'No Date';
    final date = _data['date'];
    if (date is Timestamp) {
      formattedDate = DateFormat('dd MMM yyyy').format(date.toDate());
    } else if (date is DateTime) {
      formattedDate = DateFormat('dd MMM yyyy').format(date);
    }

    String? callTimeStr;
    final callTime = _data['screening_call_time'];
    if (callTime is Timestamp)
      callTimeStr =
          DateFormat('dd MMM yyyy, hh:mm a').format(callTime.toDate());

    final statusColor = _getScreeningStatusColor(screeningStatus);
    final priorityColor = _getPriorityColor(priority);
    final isFinalised =
        screeningStatus == 'promoted' || screeningStatus == 'rejected';

    final mustAct = screeningStatus == 'called';

    return PopScope(
      canPop: !mustAct,
      onPopInvokedWithResult: (didPop, result) {
        if (mustAct && !didPop) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Please select Promote or Reject for the called lead.'),
                  backgroundColor: Color(0xFFFFA500)),
            );
          }
        }
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F1C2A) : const Color(0xFFF2F6FA),
        appBar: AppBar(
          title: Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Montserrat',
                  fontSize: 17)),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_brandPrimary, _brandAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
          ),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: mustAct
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  onPressed: () => Navigator.of(context).pop(_needRefresh),
                ),
          actions: mustAct ? [] : [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check Call Log',
              onPressed: _scanCurrentLeadCallLog,
            ),
            IconButton(
              icon:
                  const Icon(Icons.delete_outline_rounded, color: Colors.white),
              tooltip: 'Delete Lead',
              onPressed: _requestDeletion,
            ),
            IconButton(
                icon: const Icon(Icons.edit_note_rounded),
                tooltip: 'Add Notes',
                onPressed: _addScreeningNotes),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Banner
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Icon(_getStatusIcon(screeningStatus),
                        color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_screeningStatusLabel(screeningStatus),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: statusColor)),
                        if (callTimeStr != null)
                          Text('Called on $callTimeStr',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor.withValues(alpha: 0.7))),
                        if (callDuration != null)
                          Text('Duration: ${callDuration}s',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor.withValues(alpha: 0.7))),
                      ]),
                ]),
              ),
              const SizedBox(height: 16),

              // Contact Card
              _sectionCard(
                  isDark: isDark,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Contact Information', isDark),
                        const SizedBox(height: 12),
                        _detailRow(Icons.person_rounded, 'Name', name, isDark),
                        if (phone.isNotEmpty)
                          _detailRow(
                              Icons.phone_rounded, 'Phone', phone, isDark),
                        if (address.isNotEmpty)
                          _detailRow(Icons.location_on_rounded, 'Address',
                              address, isDark),
                        if (branch.isNotEmpty)
                          _detailRow(
                              Icons.business_rounded, 'Branch', branch, isDark),
                      ])),
              const SizedBox(height: 12),

              // Lead Info Card
              _sectionCard(
                  isDark: isDark,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel('Lead Information', isDark),
                        const SizedBox(height: 12),
                        _detailRow(Icons.calendar_today_rounded, 'Date',
                            formattedDate, isDark),
                        _detailRow(Icons.person_outline_rounded, 'Assigned By',
                            widget.assignerName, isDark),
                        if (platform.isNotEmpty)
                          _detailRow(Icons.share_rounded, 'Platform', platform,
                              isDark),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Icon(Icons.flag_rounded,
                                size: 16, color: Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Text('Priority',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500)),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                  color: priorityColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(priority,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: priorityColor)),
                            ),
                          ]),
                        ),
                      ])),

              if (comments.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionCard(
                    isDark: isDark,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('SME Notes', isDark),
                          const SizedBox(height: 10),
                          Text(comments,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.5)),
                        ])),
              ],

              if (screeningNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionCard(
                    isDark: isDark,
                    accentColor: _brandPrimary,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Your Screening Notes', isDark,
                              color: _brandPrimary),
                          const SizedBox(height: 10),
                          Text(screeningNotes,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.5)),
                        ])),
              ],

              if (screeningStatus == 'rejected' &&
                  rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionCard(
                    isDark: isDark,
                    accentColor: const Color(0xFFF44336),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Rejection Reason', isDark,
                              color: const Color(0xFFF44336)),
                          const SizedBox(height: 10),
                          Text(rejectionReason,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.5)),
                        ])),
              ],
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4))
            ],
          ),
          child: Row(children: [
            if (!isFinalised && screeningStatus != 'called')
              Expanded(
                child: GestureDetector(
                  onTap: _onCallPressed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_teal, Color(0xFF00BCD4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: _teal.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Call Customer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
            if (screeningStatus == 'called') ...[
              Expanded(
                child: GestureDetector(
                  onTap: _promoteToLead,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFF4CAF50).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_up_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Promote',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _rejectLead,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color:
                                const Color(0xFFF44336).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_down_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('Reject',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
            ],
            if (isFinalised)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_getStatusIcon(screeningStatus),
                            color: statusColor, size: 20),
                        const SizedBox(width: 8),
                        Text('Lead ${_screeningStatusLabel(screeningStatus)}',
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionCard(
      {required Widget child, required bool isDark, Color? accentColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: accentColor != null
            ? Border.all(color: accentColor.withValues(alpha: 0.2))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String label, bool isDark, {Color? color}) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: color?.withValues(alpha: 0.7) ??
            (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0D2B40)))),
      ]),
    );
  }

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

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'called':
        return Icons.phone_callback_rounded;
      case 'promoted':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.circle;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Call Detection Page
// ════════════════════════════════════════════════════════════════════════════

enum _CallAction { promote, reject, none }

class _CallDetectionResult {
  final _CallAction action;
  const _CallDetectionResult(this.action);
}

enum _DetectionState { idle, detecting, detected }

class SmeCallDetectionPage extends StatefulWidget {
  final String phone;
  final String docId;
  final String currentUid;
  final String screeningStatus;

  const SmeCallDetectionPage({
    super.key,
    required this.phone,
    required this.docId,
    required this.currentUid,
    required this.screeningStatus,
  });

  @override
  State<SmeCallDetectionPage> createState() => _SmeCallDetectionPageState();
}

class _SmeCallDetectionPageState extends State<SmeCallDetectionPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _teal = Color(0xFF00897B);

  _DetectionState _state = _DetectionState.idle;
  DateTime? _callStartTime;
  int? _detectedDuration;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto call log checking on app resume disabled.
  }

  Future<void> _initiateCall() async {
    if (widget.phone.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No phone number available')));
      return;
    }
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone permission denied')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: widget.phone);
    if (await canLaunchUrl(uri)) {
      setState(() {
        _state = _DetectionState.detecting;
        _callStartTime = DateTime.now();
      });
      await _saveCallState();
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch dialer')));
    }
  }

  Future<void> _saveCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sme_pending_call_number', widget.phone);
    await prefs.setInt(
        'sme_pending_call_time', _callStartTime?.millisecondsSinceEpoch ?? 0);
    await prefs.setString('sme_pending_call_docid', widget.docId);
  }

  Future<void> _clearCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sme_pending_call_number');
    await prefs.remove('sme_pending_call_time');
    await prefs.remove('sme_pending_call_docid');
  }

  Future<void> _checkCallLog() async {
    if (_callStartTime == null) return;
    final permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) return;
    try {
      final now = DateTime.now();
      final Iterable<CallLogEntry> entries = await CallLog.query(
          dateFrom: _callStartTime!.millisecondsSinceEpoch,
          dateTo: now.millisecondsSinceEpoch);
      final normalizedPending = widget.phone.replaceAll(RegExp(r'\D'), '');
      CallLogEntry? matchedEntry;
      for (final entry in entries) {
        final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        final wasConnected = (entry.duration ?? 0) > 5;
        if (logNumber.endsWith(normalizedPending) && wasConnected) {
          matchedEntry = entry;
          break;
        }
      }
      if (matchedEntry != null && mounted) {
        await FirebaseFirestore.instance
            .collection('follow_ups')
            .doc(widget.docId)
            .update({
          'screening_status': 'called',
          'screening_call_time': FieldValue.serverTimestamp(),
          'screening_call_duration': matchedEntry.duration ?? 0,
          'screened_by': widget.currentUid,
        });
        await _clearCallState();
        if (mounted)
          setState(() {
            _state = _DetectionState.detected;
            _detectedDuration = matchedEntry!.duration;
          });
      }
    } catch (e) {
      debugPrint('Error checking call log: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1C2A) : const Color(0xFFF2F6FA),
      appBar: AppBar(
        title: const Text('Call Customer',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_brandPrimary, Color(0xFF008BD6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context)
              .pop(const _CallDetectionResult(_CallAction.none)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child:
                        const Icon(Icons.phone_rounded, color: _teal, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer Number',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        const SizedBox(height: 2),
                        Text(widget.phone,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0D2B40),
                                letterSpacing: 1)),
                      ]),
                ]),
              ),
              const SizedBox(height: 40),
              Expanded(child: _buildStateWidget(isDark)),
              const SizedBox(height: 24),
              _buildBottomActions(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateWidget(bool isDark) {
    switch (_state) {
      case _DetectionState.idle:
        return _buildIdleState(isDark);
      case _DetectionState.detecting:
        return _buildDetectingState(isDark);
      case _DetectionState.detected:
        return _buildDetectedState(isDark);
    }
  }

  Widget _pulseCircle({required Color color, required IconData icon}) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.0)
            ])),
        child: Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border:
                    Border.all(color: color.withValues(alpha: 0.4), width: 2)),
            child: Icon(icon, color: color, size: 44),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _pulseCircle(color: _teal, icon: Icons.phone_rounded),
      const SizedBox(height: 28),
      Text('Ready to Call',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0D2B40))),
      const SizedBox(height: 10),
      Text(
          'Tap the button below to call the customer.\nOnce the call ends, return to this app.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6)),
    ]);
  }

  Widget _buildDetectingState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _pulseCircle(color: Colors.orange, icon: Icons.phone_in_talk_rounded),
      const SizedBox(height: 28),
      Text('Detecting Call\u2026',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0D2B40))),
      const SizedBox(height: 10),
      Text('Return here after your call.\nWe\'ll detect it automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6)),
      const SizedBox(height: 20),
      const CircularProgressIndicator(strokeWidth: 2),
    ]);
  }

  Widget _buildDetectedState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _teal.withValues(alpha: 0.12),
            border: Border.all(color: _teal.withValues(alpha: 0.4), width: 2)),
        child: const Icon(Icons.check_circle_rounded, color: _teal, size: 60),
      ),
      const SizedBox(height: 28),
      const Text('Call Detected!',
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: _teal)),
      if (_detectedDuration != null) ...[
        const SizedBox(height: 6),
        Text('Duration: ${_detectedDuration}s',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
      ],
      const SizedBox(height: 12),
      Text(
          'Lead has been marked as Called.\nNow you can promote or reject this lead.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6)),
    ]);
  }

  Widget _buildBottomActions(bool isDark) {
    if (_state == _DetectionState.idle) {
      return SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: _initiateCall,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_teal, Color(0xFF00BCD4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: _teal.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 6))
              ],
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Start Call',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ]),
          ),
        ),
      );
    }

    if (_state == _DetectionState.detecting) {
      return SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: _checkCallLog,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _brandPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _brandPrimary.withValues(alpha: 0.3)),
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, color: _brandPrimary, size: 20),
                  SizedBox(width: 8),
                  Text('Check Now',
                      style: TextStyle(
                          color: _brandPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      );
    }

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => Navigator.of(context)
              .pop(const _CallDetectionResult(_CallAction.reject)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF44336).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFF44336).withValues(alpha: 0.3)),
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_rounded,
                      color: Color(0xFFF44336), size: 20),
                  SizedBox(width: 6),
                  Text('Reject',
                      style: TextStyle(
                          color: Color(0xFFF44336),
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GestureDetector(
          onTap: () => Navigator.of(context)
              .pop(const _CallDetectionResult(_CallAction.promote)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text('Promote',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      ),
    ]);
  }
}
