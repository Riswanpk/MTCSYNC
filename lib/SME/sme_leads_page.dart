import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:getwidget/getwidget.dart';
import '../Leads/presentfollowup.dart';
import 'sme_lead_form.dart';
import '../Navigation/user_cache_service.dart';

class SmeLeadsPage extends StatefulWidget {
  const SmeLeadsPage({super.key});

  @override
  State<SmeLeadsPage> createState() => _SmeLeadsPageState();
}

class _SmeLeadsPageState extends State<SmeLeadsPage> {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _brandAccent = Color(0xFF008BD6);
  static const Color _successGreen = Color(0xFF8CC63F);

  String selectedStatus = 'All';
  String selectedPriority = 'All';
  String? selectedBranch;
  String searchQuery = '';
  bool sortAscending = false;
  bool _isSearching = false;
  bool _isLoading = false;

  List<DocumentSnapshot> _leads = [];
  DocumentSnapshot? _lastDocument;
  int _currentPage = 1;
  final int _leadsPerPage = 15;
  final Map<int, DocumentSnapshot?> _pageStartCursors = {1: null};

  final List<String> statusOptions = [
    'All',
    'In Progress',
    'Sold',
    'Cancelled'
  ];
  final List<String> priorityOptions = ['All', 'High', 'Medium', 'Low'];
  List<String> branchOptions = [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final branches = await UserCacheService.instance.getBranches();
    setState(() {
      branchOptions = ['All', ...branches];
      selectedBranch = null;
      _leads = [];
    });
  }

  Future<void> _fetchLeadsPage(
      {bool nextPage = false,
      bool prevPage = false,
      bool isSearch = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (selectedBranch == null) {
      setState(() {
        _leads = [];
        _isLoading = false;
      });
      return;
    }
    Query query = FirebaseFirestore.instance
        .collection('follow_ups')
        .where('assigned_by', isEqualTo: uid);
    if (selectedBranch != 'All') {
      query = query.where('branch', isEqualTo: selectedBranch);
    }

    if (!isSearch || searchQuery.isEmpty) {
      if (selectedStatus != 'All') {
        final statusValue = selectedStatus == 'Sold' ? 'Sale' : selectedStatus;
        query = query.where('status', isEqualTo: statusValue);
      }
      if (selectedPriority != 'All') {
        query = query.where('priority', isEqualTo: selectedPriority);
      }
    }

    query = query.orderBy('created_at', descending: !sortAscending);

    QuerySnapshot snapshot;

    if (isSearch && searchQuery.isNotEmpty) {
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

    if (snapshot.docs.isNotEmpty && (!isSearch || searchQuery.isEmpty)) {
      _lastDocument = snapshot.docs.last;
      _pageStartCursors[_currentPage + 1] = _lastDocument;
    } else {
      _lastDocument = null;
    }

    setState(() {
      _leads = snapshot.docs;
      _isLoading = false;
    });
  }

  void _resetAndFetch() {
    _pageStartCursors.clear();
    _pageStartCursors[1] = null;
    _currentPage = 1;
    _lastDocument = null;
    _fetchLeadsPage();
  }

  Future<void> _playClickSound() async {
    final player = AudioPlayer();
    await player.play(AssetSource('sounds/click.mp3'), volume: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: GFAppBar(
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
                  setState(() => searchQuery = val.toLowerCase().trim());
                  _fetchLeadsPage(isSearch: true);
                },
              )
            : const Text('SME Leads'),
        iconTheme: const IconThemeData(color: Colors.white),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: Colors.white, fontSize: 20),
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
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  searchQuery = '';
                  _fetchLeadsPage(isSearch: true);
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _buildFilterChip(
                    label: 'Branch',
                    value: selectedBranch ?? 'All',
                    icon: Icons.business_rounded,
                    color: _brandPrimary,
                    onTap: () => _showFilterSheet(
                      'Select Branch',
                      branchOptions,
                      selectedBranch ?? 'All',
                      (val) {
                        setState(() => selectedBranch = val == 'All' ? null : val);
                        _resetAndFetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Status',
                    value: selectedStatus,
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFFFF8F00),
                    onTap: () => _showFilterSheet(
                      'Select Status',
                      statusOptions,
                      selectedStatus,
                      (val) {
                        setState(() => selectedStatus = val);
                        _resetAndFetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Priority',
                    value: selectedPriority,
                    icon: Icons.flag_rounded,
                    color: const Color(0xFFE53935),
                    onTap: () => _showFilterSheet(
                      'Select Priority',
                      priorityOptions,
                      selectedPriority,
                      (val) {
                        setState(() => selectedPriority = val);
                        _resetAndFetch();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSortChip(),
                ],
              ),
            ),
          ),
          // Leads list
          Expanded(
            child: _isLoading
                ? Center(
                    child: GFLoader(
                      type: GFLoaderType.android,
                      androidLoaderColor:
                          const AlwaysStoppedAnimation<Color>(_brandPrimary),
                    ),
                  )
                : _leads.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: _brandPrimary.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.folder_open_rounded,
                                size: 44,
                                color: _brandPrimary.withOpacity(0.45),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No leads found',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color(0xFF143A52),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              selectedBranch == null
                                  ? 'Select a branch to view leads'
                                  : 'Try adjusting your filters',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                        itemCount: _leads.length,
                        itemBuilder: (context, index) {
                          final doc = _leads[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'No Name';
                          final status = data['status'] ?? 'Unknown';
                          final priority = data['priority'] ?? 'High';
                          final assignedToName =
                              data['assigned_to_name'] ?? 'Unknown';
                          final branch = data['branch'] ?? '';

                          if (searchQuery.isNotEmpty &&
                              !name.toLowerCase().contains(searchQuery)) {
                            return const SizedBox.shrink();
                          }

                          // Parse date
                          String formattedDate = 'No Date';
                          final date = data['date'];
                          DateTime? parsedDate;
                          if (date is Timestamp) {
                            parsedDate = date.toDate();
                          } else if (date is DateTime) {
                            parsedDate = date;
                          }
                          if (parsedDate != null) {
                            formattedDate =
                                DateFormat('dd-MM-yyyy').format(parsedDate);
                          }

                          final statusColor = _getStatusColor(status);
                          final priorityColor = _getPriorityColor(priority);

                          return GestureDetector(
                            onTap: () async {
                              await _playClickSound();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PresentFollowUp(docId: doc.id),
                                ),
                              ).then((_) => _fetchLeadsPage());
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1C2C3C)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(
                                        isDark ? 0.25 : 0.07),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Status accent bar
                                      Container(
                                        width: 5,
                                        color: statusColor,
                                      ),
                                      // Content
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              14, 14, 14, 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Name + Status badge row
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: isDark
                                                            ? Colors.white
                                                            : const Color(
                                                                0xFF0D2B40),
                                                        height: 1.3,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(0.14),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                    ),
                                                    child: Text(
                                                      status,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: statusColor,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.calendar_today_rounded,
                                                    size: 11,
                                                    color: Colors.grey.shade400,
                                                  ),
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
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              // Bottom info row
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: _infoChip(
                                                      icon: Icons
                                                          .person_rounded,
                                                      label: 'Assigned',
                                                      value: assignedToName,
                                                      isDark: isDark,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: _infoChip(
                                                      icon: Icons
                                                          .business_rounded,
                                                      label: 'Branch',
                                                      value: branch,
                                                      isDark: isDark,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 7),
                                                    decoration: BoxDecoration(
                                                      color: priorityColor
                                                          .withOpacity(0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.flag_rounded,
                                                          size: 13,
                                                          color: priorityColor,
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Text(
                                                          priority,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color:
                                                                priorityColor,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
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
                        },
                      ),
          ),
          // Pagination
          if (!_isLoading && searchQuery.isEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
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
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  _paginationButton(
                    icon: Icons.chevron_right_rounded,
                    enabled:
                        _lastDocument != null && _leads.length == _leadsPerPage,
                    onTap: () => _fetchLeadsPage(nextPage: true),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _successGreen,
        elevation: 2,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SmeLeadForm()),
          );
          if (result == true) _resetAndFetch();
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Sale':
        return const Color(0xFF4CAF50);
      case 'In Progress':
        return const Color(0xFFFFC107);
      case 'Cancelled':
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

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: _brandPrimary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = value != 'All' && value.isNotEmpty;
    final displayText = isActive ? value : label;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? color.withOpacity(0.13)
              : (isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                isActive ? color.withOpacity(0.6) : Colors.grey.withOpacity(0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: isActive ? color : Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              displayText,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? color
                    : (isDark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: isActive ? color : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(
    String title,
    List<String> options,
    String current,
    void Function(String) onSelect,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color:
                              isDark ? Colors.white : const Color(0xFF0D2B40),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: options.length,
                      itemBuilder: (_, i) {
                        final opt = options[i];
                        final selected = opt == current;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 24),
                          title: Text(
                            opt,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: selected
                                  ? _brandPrimary
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_rounded,
                                  color: _brandPrimary, size: 20)
                              : null,
                          onTap: () {
                            Navigator.pop(context);
                            onSelect(opt);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSortChip() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const color = Color(0xFF43A047);
    return GestureDetector(
      onTap: () {
        setState(() => sortAscending = !sortAscending);
        _resetAndFetch();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              sortAscending ? 'Oldest' : 'Newest',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
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
              ? _brandPrimary.withOpacity(0.1)
              : Colors.grey.withOpacity(0.07),
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
}
