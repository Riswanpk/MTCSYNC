import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Navigation/user_cache_service.dart';
import '../Customer Calling/customer_list_target_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

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
      _errorMessage = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .doc(email)
          .get();

      List<Map<String, dynamic>> customers = [];
      if (doc.exists && doc.data() != null && doc.data()!['customers'] != null) {
        final List<dynamic> raw = doc.data()!['customers'];
        customers = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
          _errorMessage = "Failed to fetch customer list: $e";
          _loadingCustomers = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredUsers(String? branch) {
    if (branch == null || branch.isEmpty || branch == 'All Branches') {
      return _allUsers;
    }
    return _allUsers.where((u) => (u['branch'] ?? '') == branch).toList();
  }

  List<int> _getFilteredCustomerIndices() {
    final query = _searchQuery.trim().toLowerCase();
    final List<int> filtered = [];
    for (int i = 0; i < _sourceCustomers.length; i++) {
      if (query.isEmpty) {
        filtered.add(i);
        continue;
      }
      final c = _sourceCustomers[i];
      final name = (c['name'] ?? '').toString().toLowerCase();
      final contact1 = (c['contact1'] ?? c['contact'] ?? '').toString().toLowerCase();
      final contact2 = (c['contact2'] ?? '').toString().toLowerCase();
      final address = (c['address'] ?? '').toString().toLowerCase();
      final remarks = (c['remarks'] ?? '').toString().toLowerCase();

      if (name.contains(query) ||
          contact1.contains(query) ||
          contact2.contains(query) ||
          address.contains(query) ||
          remarks.contains(query)) {
        filtered.add(i);
      }
    }
    return filtered;
  }

  bool _isCustomerMatching(Map<String, dynamic> candidate, Map<String, dynamic> target) {
    final tName = (target['name'] ?? '').toString().trim().toLowerCase();
    final tContact1 = (target['contact1'] ?? target['contact'] ?? '').toString().trim();
    final tContact2 = (target['contact2'] ?? '').toString().trim();

    final cName = (candidate['name'] ?? '').toString().trim().toLowerCase();
    final cContact1 = (candidate['contact1'] ?? candidate['contact'] ?? '').toString().trim();
    final cContact2 = (candidate['contact2'] ?? '').toString().trim();

    if (tContact1.isNotEmpty) {
      if (cContact1 == tContact1 || (cContact2.isNotEmpty && cContact2 == tContact1)) {
        return true;
      }
    }
    if (tContact2.isNotEmpty) {
      if (cContact1 == tContact2 || (cContact2.isNotEmpty && cContact2 == tContact2)) {
        return true;
      }
    }
    if (tName.isNotEmpty && cName == tName) {
      return true;
    }

    return false;
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
    final sourceName = (_selectedSourceUser!['username'] ?? sourceEmail).toString();
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

    // Confirmation dialog with safe, non-intrinsic layout
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.swap_horiz_rounded, color: _primaryBlue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Confirm Transfer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Are you sure you want to transfer ${selectedCustomersToTransfer.length} customer(s)?',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            const Text('From: ', style: TextStyle(fontWeight: FontWeight.w500)),
                            Expanded(
                              child: Text(
                                '$sourceName (${_selectedSourceUser!['branch'] ?? 'No Branch'})',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 18, color: _primaryGreen),
                            const SizedBox(width: 8),
                            const Text('To: ', style: TextStyle(fontWeight: FontWeight.w500)),
                            Expanded(
                              child: Text(
                                '$destName ($destBranch)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Note: This will move the selected customer(s) and all their past remarks & call history across ALL months from User A to User B without overwriting any existing customers.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Selected Customers (${selectedCustomersToTransfer.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: selectedCustomersToTransfer.map((c) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 14, color: _primaryGreen),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${c['name'] ?? 'Unknown'} (${c['contact1'] ?? c['contact'] ?? 'No contact'})',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Transfer Now'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isTransferring = true;
    });

    try {
      // 1. Fetch all month documents in customer_target collection
      final monthDocsSnapshot =
          await FirebaseFirestore.instance.collection('customer_target').get();

      final Set<String> allMonthIds = monthDocsSnapshot.docs.map((d) => d.id).toSet();
      for (final m in _monthYears) {
        allMonthIds.add(m);
      }

      int totalTransferredRecords = 0;
      int monthsAffected = 0;

      for (final monthId in allMonthIds) {
        final sourceUserDocRef = FirebaseFirestore.instance
            .collection('customer_target')
            .doc(monthId)
            .collection('users')
            .doc(sourceEmail);

        final sourceDocSnap = await sourceUserDocRef.get();
        if (!sourceDocSnap.exists || sourceDocSnap.data() == null) {
          continue;
        }

        final sourceData = sourceDocSnap.data()!;
        final rawSourceCustomers = sourceData['customers'];
        if (rawSourceCustomers is! List || rawSourceCustomers.isEmpty) {
          continue;
        }

        final List<Map<String, dynamic>> sourceList =
            rawSourceCustomers.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        final List<Map<String, dynamic>> matchedToMove = [];
        final List<Map<String, dynamic>> remainingForSource = [];

        for (final item in sourceList) {
          bool matchFound = false;
          for (final target in selectedCustomersToTransfer) {
            if (_isCustomerMatching(item, target)) {
              matchFound = true;
              break;
            }
          }
          if (matchFound) {
            matchedToMove.add(item);
          } else {
            remainingForSource.add(item);
          }
        }

        if (matchedToMove.isNotEmpty) {
          final destUserDocRef = FirebaseFirestore.instance
              .collection('customer_target')
              .doc(monthId)
              .collection('users')
              .doc(destEmail);

          final destDocSnap = await destUserDocRef.get();
          List<Map<String, dynamic>> destList = [];
          if (destDocSnap.exists &&
              destDocSnap.data() != null &&
              destDocSnap.data()!['customers'] is List) {
            destList = (destDocSnap.data()!['customers'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }

          // Append transferred customers directly to User B's list without overwriting any existing customers
          for (final toMove in matchedToMove) {
            destList.add(Map<String, dynamic>.from(toMove));
          }

          final batch = FirebaseFirestore.instance.batch();

          batch.set(
            destUserDocRef,
            {
              'user': destEmail,
              'branch': destBranch,
              'customers': destList,
              'updated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          batch.update(sourceUserDocRef, {
            'customers': remainingForSource,
            'updated': FieldValue.serverTimestamp(),
          });

          await batch.commit();

          totalTransferredRecords += matchedToMove.length;
          monthsAffected++;
        }
      }

      if (mounted) {
        setState(() {
          _isTransferring = false;
        });

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: _primaryGreen, size: 28),
                SizedBox(width: 10),
                Text('Transfer Complete'),
              ],
            ),
            content: Text(
              'Successfully transferred ${selectedCustomersToTransfer.length} customer(s) ($totalTransferredRecords records across $monthsAffected month(s)) from $sourceName to $destName.\n\nAll call history and remarks are now visible under $destName.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        await _fetchSourceCustomers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showRemarksHistory(Map<String, dynamic> customer) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _CustomerRemarksHistorySheet(
          customer: customer,
          userEmail: (_selectedSourceUser?['email'] ?? '').toString().toLowerCase(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF23262B) : Colors.white;
    final scaffoldBg = isDark ? const Color(0xFF181A20) : const Color(0xFFF4F6F9);

    final filteredIndices = _getFilteredCustomerIndices();
    final allFilteredSelected = filteredIndices.isNotEmpty &&
        filteredIndices.every((idx) => _selectedCustomerIndices.contains(idx));

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Transfer Call List', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: _primaryBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.red.shade100,
                        child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
                      ),
                    _buildUserSelectionCard(cardBg, isDark),
                    if (_selectedSourceUser != null) _buildCustomerHeaderCard(cardBg, isDark, filteredIndices, allFilteredSelected),
                    Expanded(
                      child: _selectedSourceUser == null
                          ? _buildEmptyState(
                              icon: Icons.person_search_rounded,
                              title: 'Select Source User (User A)',
                              subtitle: 'Choose a user whose customer call list you want to transfer.',
                            )
                          : _loadingCustomers
                              ? const Center(child: CircularProgressIndicator())
                              : _sourceCustomers.isEmpty
                                  ? _buildEmptyState(
                                      icon: Icons.assignment_late_outlined,
                                      title: 'No Customers Found',
                                      subtitle: 'This user has no customers in $_selectedMonthYear.',
                                    )
                                  : filteredIndices.isEmpty
                                      ? _buildEmptyState(
                                          icon: Icons.search_off_rounded,
                                          title: 'No Matching Customers',
                                          subtitle: 'Try adjusting your search query.',
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 90),
                                          itemCount: filteredIndices.length,
                                          itemBuilder: (context, i) {
                                            final customerIndex = filteredIndices[i];
                                            final customer = _sourceCustomers[customerIndex];
                                            final isSelected = _selectedCustomerIndices.contains(customerIndex);

                                            return _buildCustomerItemCard(
                                              customer: customer,
                                              isSelected: isSelected,
                                              cardBg: cardBg,
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
                if (_selectedSourceUser != null && _sourceCustomers.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomActionBar(cardBg, isDark),
                  ),
                if (_isTransferring)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
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
                              'Migrating customer history & remarks across all months...',
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

  Widget _buildUserSelectionCard(Color cardBg, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, size: 18, color: _primaryBlue),
              const SizedBox(width: 8),
              const Text('Viewing Month:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMonthYear,
                    isDense: true,
                    items: _monthYears.map((m) {
                      return DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null && val != _selectedMonthYear) {
                        setState(() {
                          _selectedMonthYear = val;
                        });
                        _fetchSourceCustomers();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_remove_rounded, size: 16, color: Colors.redAccent),
                        SizedBox(width: 6),
                        Text('Transfer From (User A)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildUserDropdown(
                      selectedBranch: _selectedSourceBranch,
                      selectedUser: _selectedSourceUser,
                      hint: 'Select User A',
                      onBranchChanged: (b) {
                        setState(() {
                          _selectedSourceBranch = b;
                          _selectedSourceUser = null;
                          _sourceCustomers = [];
                          _selectedCustomerIndices.clear();
                        });
                      },
                      onUserChanged: (u) {
                        setState(() {
                          _selectedSourceUser = u;
                        });
                        _fetchSourceCustomers();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_add_alt_1_rounded, size: 16, color: _primaryGreen),
                        SizedBox(width: 6),
                        Text('Transfer To (User B)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildUserDropdown(
                      selectedBranch: _selectedDestBranch,
                      selectedUser: _selectedDestUser,
                      excludeEmail: _selectedSourceUser?['email'],
                      hint: 'Select User B',
                      onBranchChanged: (b) {
                        setState(() {
                          _selectedDestBranch = b;
                          _selectedDestUser = null;
                        });
                      },
                      onUserChanged: (u) {
                        setState(() {
                          _selectedDestUser = u;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserDropdown({
    required String? selectedBranch,
    required Map<String, dynamic>? selectedUser,
    required String hint,
    String? excludeEmail,
    required ValueChanged<String?> onBranchChanged,
    required ValueChanged<Map<String, dynamic>?> onUserChanged,
  }) {
    final availableUsers = _getFilteredUsers(selectedBranch).where((u) {
      if (excludeEmail != null && excludeEmail.isNotEmpty) {
        return (u['email'] ?? '').toString().toLowerCase() != excludeEmail.toLowerCase();
      }
      return true;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedBranch ?? 'All Branches',
              isExpanded: true,
              isDense: true,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              items: ['All Branches', ..._branches].map((b) {
                return DropdownMenuItem(
                  value: b,
                  child: Text(
                    b,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) {
                onBranchChanged(val == 'All Branches' ? null : val);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Map<String, dynamic>>(
              value: selectedUser,
              isExpanded: true,
              isDense: true,
              hint: Text(hint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              items: availableUsers.map((u) {
                final name = (u['username'] ?? u['email'] ?? 'User').toString();
                final branch = (u['branch'] ?? '').toString();
                return DropdownMenuItem(
                  value: u,
                  child: Text(
                    branch.isNotEmpty ? '$name ($branch)' : name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: onUserChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerHeaderCard(
    Color cardBg,
    bool isDark,
    List<int> filteredIndices,
    bool allFilteredSelected,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search customer name, contact or remarks...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: allFilteredSelected,
                activeColor: _primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedCustomerIndices.addAll(filteredIndices);
                    } else {
                      _selectedCustomerIndices.removeAll(filteredIndices);
                    }
                  });
                },
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (allFilteredSelected) {
                      _selectedCustomerIndices.removeAll(filteredIndices);
                    } else {
                      _selectedCustomerIndices.addAll(filteredIndices);
                    }
                  });
                },
                child: Text(
                  allFilteredSelected ? 'Deselect All' : 'Select All (${filteredIndices.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_selectedCustomerIndices.length} / ${_sourceCustomers.length} selected',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _primaryBlue,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerItemCard({
    required Map<String, dynamic> customer,
    required bool isSelected,
    required Color cardBg,
    required bool isDark,
    required ValueChanged<bool?> onToggle,
  }) {
    final name = (customer['name'] ?? 'Unnamed Customer').toString();
    final contact1 = (customer['contact1'] ?? customer['contact'] ?? '').toString();
    final contact2 = (customer['contact2'] ?? '').toString();
    final address = (customer['address'] ?? '').toString();
    final remarks = (customer['remarks'] ?? '').toString().trim();
    final callMade = customer['callMade'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? _primaryBlue.withValues(alpha: isDark ? 0.2 : 0.08) : cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? _primaryBlue : Colors.grey.withValues(alpha: 0.15),
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onToggle(!isSelected),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: isSelected,
                activeColor: _primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: onToggle,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: callMade ? _primaryGreen.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            callMade ? 'Called' : 'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: callMade ? _primaryGreen : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (contact1.isNotEmpty) ...[
                          const Icon(Icons.phone, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(contact1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                        if (contact2.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.phone_iphone, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(contact2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ],
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (remarks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Remarks: $remarks',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.history_rounded, size: 20, color: _primaryBlue),
                tooltip: 'View Past Remarks',
                onPressed: () => _showRemarksHistory(customer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(Color cardBg, bool isDark) {
    final count = _selectedCustomerIndices.length;
    final isReady = count > 0 &&
        _selectedSourceUser != null &&
        _selectedDestUser != null &&
        _selectedSourceUser!['email'] != _selectedDestUser!['email'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count Selected',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  _selectedDestUser != null
                      ? 'To: ${_selectedDestUser!['username'] ?? 'User B'}'
                      : 'Select Destination User',
                  style: TextStyle(
                    fontSize: 12,
                    color: _selectedDestUser != null ? _primaryGreen : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: isReady ? _executeTransfer : null,
              icon: const Icon(Icons.move_up_rounded, size: 18),
              label: const Text('Transfer Call List', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRemarksHistorySheet extends StatefulWidget {
  final Map<String, dynamic> customer;
  final String userEmail;

  const _CustomerRemarksHistorySheet({
    required this.customer,
    required this.userEmail,
  });

  @override
  State<_CustomerRemarksHistorySheet> createState() => _CustomerRemarksHistorySheetState();
}

class _CustomerRemarksHistorySheetState extends State<_CustomerRemarksHistorySheet> {
  bool _loading = true;
  List<Map<String, String>> _history = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final contact1 = widget.customer['contact1'] ?? widget.customer['contact'];
      final contact2 = widget.customer['contact2'];
      final custName = (widget.customer['name'] ?? '').toString().trim().toLowerCase();

      final now = DateTime.now();
      final List<Map<String, String>> list = [];

      for (int i = 0; i <= 6; i++) {
        final date = DateTime(now.year, now.month - i, 1);
        final monthYear = "${CustomerListTargetService.monthName(date.month)} ${date.year}";

        final doc = await FirebaseFirestore.instance
            .collection('customer_target')
            .doc(monthYear)
            .collection('users')
            .doc(widget.userEmail)
            .get();

        if (doc.exists && doc.data() != null && doc.data()!['customers'] is List) {
          final List customers = doc.data()!['customers'];
          for (final c in customers) {
            if (c is Map) {
              final cContact1 = (c['contact1'] ?? c['contact'] ?? '').toString();
              final cContact2 = (c['contact2'] ?? '').toString();
              final cName = (c['name'] ?? '').toString().trim().toLowerCase();

              final match = (contact1 != null && contact1.toString().isNotEmpty && (cContact1 == contact1 || cContact2 == contact1)) ||
                  (contact2 != null && contact2.toString().isNotEmpty && (cContact1 == contact2 || cContact2 == contact2)) ||
                  (custName.isNotEmpty && cName == custName);

              if (match) {
                final remarks = (c['remarks'] ?? '').toString().trim();
                final callMade = c['callMade'] == true;
                list.add({
                  'monthYear': monthYear,
                  'remarks': remarks.isNotEmpty ? remarks : (callMade ? 'Called (No remarks)' : 'Not called'),
                  'callMade': callMade ? 'true' : 'false',
                });
                break;
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _history = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final custName = widget.customer['name'] ?? 'Customer';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF23262B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.history_rounded, color: _primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Past Remarks: $custName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                    ? const Center(child: Text('No past history found for this customer.'))
                    : ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (context, i) {
                          final item = _history[i];
                          final month = item['monthYear'] ?? '';
                          final remarks = item['remarks'] ?? '';
                          final callMade = item['callMade'] == 'true';

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black26 : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _primaryBlue.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    month,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _primaryBlue),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        remarks,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  callMade ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: callMade ? _primaryGreen : Colors.grey,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
