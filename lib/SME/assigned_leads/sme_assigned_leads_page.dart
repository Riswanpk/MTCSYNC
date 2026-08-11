import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../Navigation/user_cache_service.dart';
import '../sme_call_scanner_service.dart';
import '../sme_call_detected_remarks_dialog.dart';
import 'sme_lead_helpers.dart';
import 'sme_lead_card.dart';

export 'sme_lead_detail_page.dart' show SmeLeadDetailPageFromId, SmeLeadDetailPage;
export 'sme_call_detection_page.dart' show SmeCallDetectionPage;

/// Page for sales/manager/asst_manager users to screen SME-assigned leads.
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
  void didChangeAppLifecycleState(AppLifecycleState state) {}

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
                  final color = getFilterColor(filter, _brandPrimary);
                  final icon = getFilterIcon(filter);
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
                            final assignerName =
                                _assignerNameCache[data['assigned_by'] ?? ''] ??
                                    'SME User';
                            return SmeLeadCard(
                              doc: doc,
                              data: data,
                              isDark: isDark,
                              assignerName: assignerName,
                              currentUid: _currentUid ?? '',
                              onRefreshNeeded: _resetAndFetch,
                            );
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
}
