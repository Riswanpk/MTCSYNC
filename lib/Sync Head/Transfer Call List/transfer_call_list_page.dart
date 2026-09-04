import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../Navigation/user_cache_service.dart';
import '../../Customer Calling/customer_list_target_service.dart';
import 'models/transfer_constants.dart';
import 'services/transfer_call_list_service.dart';
import 'components/transfer_user_selector_card.dart';
import 'components/transfer_customer_header.dart';
import 'components/transfer_customer_card.dart';
import 'components/transfer_bottom_action_bar.dart';
import 'dialogs/transfer_confirmation_dialog.dart';

class TransferCallListPage extends StatefulWidget {
  const TransferCallListPage({super.key});

  @override
  State<TransferCallListPage> createState() => _TransferCallListPageState();
}

class _TransferCallListPageState extends State<TransferCallListPage> {
  bool _loadingInitial = true;
  bool _loadingCustomers = false;
  bool _isTransferring = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _allUsers = [];
  List<String> _branches = [];

  // Source User (User A)
  String? _selectedSourceBranch;
  Map<String, dynamic>? _selectedSourceUser;

  // Destination User (User B)
  String? _selectedDestBranch;
  Map<String, dynamic>? _selectedDestUser;

  // Selected Month
  late String _selectedMonthYear;
  late List<String> _monthYears;

  // Customers of User A
  List<Map<String, dynamic>> _sourceCustomers = [];
  final Set<int> _selectedCustomerIndices = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initMonthYears();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initMonthYears() {
    final now = DateTime.now();
    _monthYears = List.generate(12, (i) {
      final date = DateTime(now.year, now.month - i, 1);
      return "${CustomerListTargetService.monthName(date.month)} ${date.year}";
    });
    _selectedMonthYear = _monthYears.first;
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingInitial = true;
      _errorMessage = null;
    });

    try {
      final cache = UserCacheService.instance;
      await cache.ensureLoaded();
      final users = await cache.getAllUsers();
      final branches = await cache.getBranches();

      final validUsers = users.where((u) {
        final email = (u['email'] as String? ?? '').trim();
        return email.isNotEmpty;
      }).toList();

      validUsers.sort((a, b) => (a['username'] ?? a['email'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['username'] ?? b['email'] ?? '').toString().toLowerCase()));

      if (mounted) {
        setState(() {
          _allUsers = validUsers;
          _branches = branches;
          _loadingInitial = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load users: $e";
          _loadingInitial = false;
        });
      }
    }
  }

  Future<void> _fetchSourceCustomers() async {
    if (_selectedSourceUser == null) {
      setState(() {
        _sourceCustomers = [];
        _selectedCustomerIndices.clear();
      });
      return;
    }

    final email = (_selectedSourceUser!['email'] as String? ?? '').toLowerCase().trim();
    if (email.isEmpty) return;

    setState(() {
      _loadingCustomers = true;
      _selectedCustomerIndices.clear();
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .doc(email)
          .get();

      List<Map<String, dynamic>> customers = [];
      if (doc.exists && doc.data() != null && doc.data()!['customers'] is List) {
        final rawList = doc.data()!['customers'] as List;
        customers = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      if (mounted) {
        setState(() {
          _sourceCustomers = customers;
          _loadingCustomers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCustomers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load customers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<int> _getFilteredIndices() {
    final List<int> indices = [];
    for (int i = 0; i < _sourceCustomers.length; i++) {
      final c = _sourceCustomers[i];
      final name = (c['name'] ?? '').toString().toLowerCase();
      final contact1 = (c['contact1'] ?? c['contact'] ?? '').toString().toLowerCase();
      final contact2 = (c['contact2'] ?? '').toString().toLowerCase();

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final match = name.contains(q) ||
            contact1.contains(q) ||
            contact2.contains(q);
        if (!match) continue;
      }

      indices.add(i);
    }
    return indices;
  }

  Future<void> _executeTransfer() async {
    if (_selectedSourceUser == null || _selectedDestUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both Source User and Destination User.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final sourceEmail = (_selectedSourceUser!['email'] as String? ?? '').toLowerCase().trim();
    final destEmail = (_selectedDestUser!['email'] as String? ?? '').toLowerCase().trim();
    final destBranch = (_selectedDestUser!['branch'] as String? ?? '').trim();
    final destName = (_selectedDestUser!['username'] ?? destEmail).toString();

    if (sourceEmail == destEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source and Destination user cannot be the same.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedCustomerIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one customer to transfer.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedCustomersToTransfer = _selectedCustomerIndices
        .where((i) => i >= 0 && i < _sourceCustomers.length)
        .map((i) => _sourceCustomers[i])
        .toList();

    // Confirmation dialog with safe non-intrinsic layout
    final confirmed = await TransferConfirmationDialog.show(
      context: context,
      sourceUser: _selectedSourceUser!,
      destUser: _selectedDestUser!,
      customersToTransfer: selectedCustomersToTransfer,
    );

    if (confirmed != true) return;

    setState(() {
      _isTransferring = true;
    });

    final result = await TransferCallListService.executeTransfer(
      sourceEmail: sourceEmail,
      destEmail: destEmail,
      destBranch: destBranch,
      customersToTransfer: selectedCustomersToTransfer,
      monthYears: _monthYears,
    );

    if (!mounted) return;

    setState(() {
      _isTransferring = false;
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Successfully transferred ${result.totalTransferredRecords} customer record(s) across ${result.monthsAffected} month(s) to $destName!',
                ),
              ),
            ],
          ),
          backgroundColor: kTransferDestAccent,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // Refresh customers for source user
      _fetchSourceCustomers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transfer failed: ${result.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF14171F) : const Color(0xFFF4F6F9);
    final cardBg = isDark ? const Color(0xFF1E222A) : Colors.white;

    final filteredIndices = _getFilteredIndices();
    final allFilteredSelected = filteredIndices.isNotEmpty &&
        filteredIndices.every((i) => _selectedCustomerIndices.contains(i));

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'Transfer Call List',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.white),
        ),
        backgroundColor: kTransferPrimaryBlue,
        elevation: 0,
        centerTitle: false,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF004987), kTransferPrimaryBlue, Color(0xFF0277BD)],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh',
            onPressed: () {
              _loadInitialData();
              if (_selectedSourceUser != null) {
                _fetchSourceCustomers();
              }
            },
          ),
        ],
      ),
      body: _loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        color: Colors.red.shade100,
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Top Card: Month & User A -> User B Pickers
                    TransferUserSelectorCard(
                      selectedMonthYear: _selectedMonthYear,
                      monthYears: _monthYears,
                      branches: _branches,
                      allUsers: _allUsers,
                      selectedSourceBranch: _selectedSourceBranch,
                      selectedSourceUser: _selectedSourceUser,
                      selectedDestBranch: _selectedDestBranch,
                      selectedDestUser: _selectedDestUser,
                      isDark: isDark,
                      onMonthChanged: (month) {
                        setState(() {
                          _selectedMonthYear = month;
                        });
                        _fetchSourceCustomers();
                      },
                      onSourceBranchChanged: (branch) {
                        setState(() {
                          _selectedSourceBranch = branch;
                          _selectedSourceUser = null;
                          _sourceCustomers = [];
                          _selectedCustomerIndices.clear();
                        });
                      },
                      onSourceUserChanged: (user) {
                        setState(() {
                          _selectedSourceUser = user;
                        });
                        _fetchSourceCustomers();
                      },
                      onDestBranchChanged: (branch) {
                        setState(() {
                          _selectedDestBranch = branch;
                          _selectedDestUser = null;
                        });
                      },
                      onDestUserChanged: (user) {
                        setState(() {
                          _selectedDestUser = user;
                        });
                      },
                    ),

                    // Customer Filter & Search Header
                    if (_selectedSourceUser != null)
                      TransferCustomerHeader(
                        searchController: _searchController,
                        searchQuery: _searchQuery,
                        onSearchChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        onClearSearch: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        totalCount: _sourceCustomers.length,
                        selectedCount: _selectedCustomerIndices.length,
                        allFilteredSelected: allFilteredSelected,
                        filteredCount: filteredIndices.length,
                        onSelectAllToggle: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedCustomerIndices.addAll(filteredIndices);
                            } else {
                              _selectedCustomerIndices.removeAll(filteredIndices);
                            }
                          });
                        },
                        isDark: isDark,
                      ),

                    // Customers List View
                    Expanded(
                      child: _selectedSourceUser == null
                          ? _buildEmptyState(
                              icon: Icons.person_search_rounded,
                              iconColor: kTransferSourceAccent,
                              title: 'Select Source User (User A)',
                              subtitle: 'Select a branch and user to view their customer call list and select customers to transfer.',
                            )
                          : _loadingCustomers
                              ? const Center(child: CircularProgressIndicator())
                              : _sourceCustomers.isEmpty
                                  ? _buildEmptyState(
                                      icon: Icons.assignment_late_outlined,
                                      iconColor: Colors.orange,
                                      title: 'No Customers in $_selectedMonthYear',
                                      subtitle: 'This user has no customers registered for this month.',
                                    )
                                  : filteredIndices.isEmpty
                                      ? _buildEmptyState(
                                          icon: Icons.search_off_rounded,
                                          iconColor: Colors.grey,
                                          title: 'No Matching Customers',
                                          subtitle: 'Try changing your search terms.',
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.only(
                                            left: 12,
                                            right: 12,
                                            top: 6,
                                            bottom: 96,
                                          ),
                                          itemCount: filteredIndices.length,
                                          itemBuilder: (context, i) {
                                            final customerIndex = filteredIndices[i];
                                            final customer = _sourceCustomers[customerIndex];
                                            final isSelected =
                                                _selectedCustomerIndices.contains(customerIndex);

                                            return TransferCustomerCard(
                                              customer: customer,
                                              isSelected: isSelected,
                                              isDark: isDark,
                                              onToggle: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedCustomerIndices.add(customerIndex);
                                                  } else {
                                                    _selectedCustomerIndices.remove(customerIndex);
                                                  }
                                                });
                                              },
                                            );
                                          },
                                        ),
                    ),
                  ],
                ),

                // Bottom Transfer Action Bar
                if (_selectedSourceUser != null && _sourceCustomers.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: TransferBottomActionBar(
                      selectedCount: _selectedCustomerIndices.length,
                      selectedDestUser: _selectedDestUser,
                      isReady: _selectedCustomerIndices.isNotEmpty &&
                          _selectedSourceUser != null &&
                          _selectedDestUser != null &&
                          _selectedSourceUser!['email'] != _selectedDestUser!['email'],
                      onTransferPressed: _executeTransfer,
                      isDark: isDark,
                    ),
                  ),

                // Fullscreen Loading Overlay during Transfer
                if (_isTransferring)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 18),
                            Text(
                              'Transferring Call List...',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Moving customer history across all months...',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
