import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Navigation/user_cache_service.dart';
import '../Customer Calling/customer_list_target_service.dart';

/// Represents a customer entry associated with a specific user in a month
class DuplicateCustomerEntry {
  final String id; // Unique ID to distinguish entries (even for same user)
  final String userDocId;
  final String userEmail;
  final String username;
  final String branch;
  final Map<String, dynamic> rawCustomer;
  final String name;
  final String address;
  final String contact1;
  final String contact2;
  final bool callMade;
  final String remarks;
  final int remarksCount;

  DuplicateCustomerEntry({
    required this.id,
    required this.userDocId,
    required this.userEmail,
    required this.username,
    required this.branch,
    required this.rawCustomer,
    required this.name,
    required this.address,
    required this.contact1,
    required this.contact2,
    required this.callMade,
    required this.remarks,
    this.remarksCount = 0,
  });
}

/// Represents a group of duplicate entries sharing the same normalized phone number
class DuplicateGroup {
  final String phone;
  final List<DuplicateCustomerEntry> entries;
  String? selectedEntryId; // ID of the specific entry to retain

  DuplicateGroup({
    required this.phone,
    required this.entries,
    this.selectedEntryId,
  });
}

class CustomerCallingDuplicatesPage extends StatefulWidget {
  const CustomerCallingDuplicatesPage({super.key});

  @override
  State<CustomerCallingDuplicatesPage> createState() =>
      _CustomerCallingDuplicatesPageState();
}

class _CustomerCallingDuplicatesPageState
    extends State<CustomerCallingDuplicatesPage> {
  bool _loading = true;
  String? _error;
  String? _selectedMonthYear;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<DuplicateGroup> _duplicateGroups = [];
  final Set<String> _resolvingPhones = {};

  final List<String> _monthYears = List.generate(12, (i) {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month - i, 1);
    return "${CustomerListTargetService.monthName(date.month)} ${date.year}";
  });

  @override
  void initState() {
    super.initState();
    _selectedMonthYear = _monthYears.first;
    _fetchDuplicates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizePhone(String? phone) {
    if (phone == null) return '';
    final digits =
        RegExp(r'\d').allMatches(phone).map((m) => m.group(0)).join();
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  Future<void> _fetchDuplicates() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final monthYear = _selectedMonthYear!;

      // 1. Fetch all active users from users collection
      final allUsers =
          await UserCacheService.instance.getAllUsers(forceRefresh: false);
      final Map<String, Map<String, String>> userInfoMap = {};
      final Set<String> activeUserEmails = {};

      for (final u in allUsers) {
        final email = (u['email'] as String? ?? '').toLowerCase().trim();
        final username = (u['username'] as String? ?? '').trim();
        final branch = (u['branch'] as String? ?? '').trim();
        if (email.isNotEmpty) {
          activeUserEmails.add(email);
          userInfoMap[email] = {
            'username': username.isNotEmpty ? username : email,
            'branch': branch.isNotEmpty ? branch : 'Unknown',
          };
        }
      }

      // 2. Fetch all user documents under customer_target/{monthYear}/users
      final snapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .get();

      // Map from normalized 10-digit phone number -> list of entries
      final Map<String, List<DuplicateCustomerEntry>> phoneMap = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final userDocId = doc.id;
        final email = (data['user'] ?? doc.id).toString().toLowerCase().trim();

        // Filter out users who are not active (must exist in the users collection)
        if (!activeUserEmails.contains(email)) continue;

        final fallbackBranch = (data['branch'] ?? 'Unknown').toString().trim();
        final username = userInfoMap[email]?['username'] ?? email;
        final branch = userInfoMap[email]?['branch'] ?? fallbackBranch;

        final rawList = data['customers'] as List<dynamic>? ?? [];

        for (int i = 0; i < rawList.length; i++) {
          final item = rawList[i];
          if (item is! Map) continue;
          final customerMap = Map<String, dynamic>.from(item);
          final c1 = (customerMap['contact1'] ?? customerMap['contact'] ?? '')
              .toString()
              .trim();
          final c2 = (customerMap['contact2'] ?? '').toString().trim();

          final norm1 = _normalizePhone(c1);
          final norm2 = _normalizePhone(c2);

          final entry = DuplicateCustomerEntry(
            id: '${userDocId}_${i}_${customerMap['name'] ?? ''}',
            userDocId: userDocId,
            userEmail: email,
            username: username,
            branch: branch,
            rawCustomer: customerMap,
            name: (customerMap['name'] ?? 'Unnamed').toString().trim(),
            address: (customerMap['address'] ?? '').toString().trim(),
            contact1: c1,
            contact2: c2,
            callMade: customerMap['callMade'] == true,
            remarks: (customerMap['remarks'] ?? '').toString().trim(),
          );

          if (norm1.length == 10) {
            phoneMap.putIfAbsent(norm1, () => []).add(entry);
          }
          if (norm2.length == 10 && norm2 != norm1) {
            phoneMap.putIfAbsent(norm2, () => []).add(entry);
          }
        }
      }

      // Filter to only phones with duplicates (count > 1)
      final List<DuplicateGroup> duplicates = [];
      phoneMap.forEach((phone, entries) {
        if (entries.length > 1) {
          duplicates.add(DuplicateGroup(
            phone: phone,
            entries: entries,
          ));
        }
      });

      // Fetch remarks count for each user & phone number across past months
      // Check current month and up to 5 preceding months
      if (duplicates.isNotEmpty) {
        final List<String> monthsToScan = _monthYears.take(6).toList();
        // Map of userEmail -> Map of normalizedPhone -> count of remarks across months
        final Map<String, Map<String, int>> userPhoneRemarksCount = {};

        // 1) Initialize with current month remarks
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final email = (data['user'] ?? doc.id).toString().toLowerCase().trim();
          if (!activeUserEmails.contains(email)) continue;
          final rawList = data['customers'] as List<dynamic>? ?? [];
          final userMap = userPhoneRemarksCount.putIfAbsent(email, () => {});

          for (final item in rawList) {
            if (item is! Map) continue;
            final rem = (item['remarks'] ?? '').toString().trim();
            if (rem.isEmpty) continue;
            final p1 = _normalizePhone(item['contact1'] ?? item['contact']);
            final p2 = _normalizePhone(item['contact2']);
            if (p1.length == 10) userMap[p1] = (userMap[p1] ?? 0) + 1;
            if (p2.length == 10 && p2 != p1) userMap[p2] = (userMap[p2] ?? 0) + 1;
          }
        }

        // 2) Scan other months in monthsToScan
        final otherMonths = monthsToScan.where((m) => m != monthYear).toList();
        if (otherMonths.isNotEmpty) {
          try {
            final monthSnapshots = await Future.wait(
              otherMonths.map(
                (m) => FirebaseFirestore.instance
                    .collection('customer_target')
                    .doc(m)
                    .collection('users')
                    .get(),
              ),
            );

            for (final monthSnap in monthSnapshots) {
              for (final doc in monthSnap.docs) {
                final data = doc.data();
                final email = (data['user'] ?? doc.id).toString().toLowerCase().trim();
                if (!activeUserEmails.contains(email)) continue;
                final rawList = data['customers'] as List<dynamic>? ?? [];
                final userMap = userPhoneRemarksCount.putIfAbsent(email, () => {});

                for (final item in rawList) {
                  if (item is! Map) continue;
                  final rem = (item['remarks'] ?? '').toString().trim();
                  if (rem.isEmpty) continue;
                  final p1 = _normalizePhone(item['contact1'] ?? item['contact']);
                  final p2 = _normalizePhone(item['contact2']);
                  if (p1.length == 10) userMap[p1] = (userMap[p1] ?? 0) + 1;
                  if (p2.length == 10 && p2 != p1) userMap[p2] = (userMap[p2] ?? 0) + 1;
                }
              }
            }
          } catch (_) {
            // If historical months fail to load, proceed with current month remarks count
          }
        }

        // Update each DuplicateCustomerEntry with its computed remarksCount
        for (final group in duplicates) {
          final updatedEntries = <DuplicateCustomerEntry>[];
          for (final entry in group.entries) {
            final count = userPhoneRemarksCount[entry.userEmail]?[group.phone] ??
                (entry.remarks.isNotEmpty ? 1 : 0);
            updatedEntries.add(DuplicateCustomerEntry(
              id: entry.id,
              userDocId: entry.userDocId,
              userEmail: entry.userEmail,
              username: entry.username,
              branch: entry.branch,
              rawCustomer: entry.rawCustomer,
              name: entry.name,
              address: entry.address,
              contact1: entry.contact1,
              contact2: entry.contact2,
              callMade: entry.callMade,
              remarks: entry.remarks,
              remarksCount: count,
            ));
          }
          group.entries.clear();
          group.entries.addAll(updatedEntries);

          // Preselect the option with the highest remarksCount (fallback to first)
          DuplicateCustomerEntry bestEntry = group.entries.first;
          for (final e in group.entries) {
            if (e.remarksCount > bestEntry.remarksCount) {
              bestEntry = e;
            }
          }
          group.selectedEntryId = bestEntry.id;
        }
      }

      // Sort by phone number
      duplicates.sort((a, b) => a.phone.compareTo(b.phone));

      if (mounted) {
        setState(() {
          _duplicateGroups = duplicates;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Error fetching duplicates: $e";
          _loading = false;
        });
      }
    }
  }

  /// Resolves a duplicate phone group by keeping the customer on the selected user's list
  /// and removing all other duplicate customer entries for this phone.
  Future<void> _resolveDuplicate(DuplicateGroup group) async {
    final selectedEntryId = group.selectedEntryId;
    if (selectedEntryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an entry to keep.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedEntry = group.entries.firstWhere(
      (e) => e.id == selectedEntryId,
      orElse: () => group.entries.first,
    );

    final selectedDocId = selectedEntry.userDocId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Duplicate Resolution'),
        content: Text(
          'Keep customer "${selectedEntry.name}" for "${selectedEntry.username}" (${selectedEntry.branch}) '
          'and remove duplicate records with phone ${group.phone} from all other places?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005BAC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm & Remove Duplicates'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _resolvingPhones.add(group.phone);
    });

    try {
      final monthYear = _selectedMonthYear!;

      // 1. Remove duplicate customer records from all OTHER users
      final otherDocIds = group.entries
          .map((e) => e.userDocId)
          .where((docId) => docId != selectedDocId)
          .toSet();

      for (final otherUserDocId in otherDocIds) {
        final docRef = FirebaseFirestore.instance
            .collection('customer_target')
            .doc(monthYear)
            .collection('users')
            .doc(otherUserDocId);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(docRef);
          if (snapshot.exists && snapshot.data() != null) {
            final List<dynamic> customers =
                List<dynamic>.from(snapshot.data()!['customers'] ?? []);

            customers.removeWhere((c) {
              if (c is! Map) return false;
              final c1 = _normalizePhone(c['contact1'] ?? c['contact']);
              final c2 = _normalizePhone(c['contact2']);
              return c1 == group.phone || c2 == group.phone;
            });

            transaction.update(docRef, {
              'customers': customers,
              'updated': FieldValue.serverTimestamp(),
            });
          }
        });
      }

      // 2. In the selected user's document, retain the chosen entry and remove any other duplicates for this phone
      final selectedDocRef = FirebaseFirestore.instance
          .collection('customer_target')
          .doc(monthYear)
          .collection('users')
          .doc(selectedDocId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(selectedDocRef);
        if (snapshot.exists && snapshot.data() != null) {
          final List<dynamic> customers =
              List<dynamic>.from(snapshot.data()!['customers'] ?? []);

          final selectedName = selectedEntry.name.trim();
          bool keptChosen = false;

          customers.removeWhere((c) {
            if (c is! Map) return false;
            final c1 = _normalizePhone(c['contact1'] ?? c['contact']);
            final c2 = _normalizePhone(c['contact2']);

            if (c1 == group.phone || c2 == group.phone) {
              final cName = (c['name'] ?? '').toString().trim();
              // Retain the specific chosen customer record
              if (!keptChosen && cName == selectedName) {
                keptChosen = true;
                return false; // Keep
              }
              // If none matched exact name yet (e.g. slight discrepancy), keep first occurrence
              if (!keptChosen) {
                keptChosen = true;
                return false; // Keep
              }
              return true; // Remove duplicate entry within same user
            }
            return false;
          });

          transaction.update(selectedDocRef, {
            'customers': customers,
            'updated': FieldValue.serverTimestamp(),
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully resolved duplicate for ${group.phone}. Assigned to ${selectedEntry.username}.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        setState(() {
          _duplicateGroups.removeWhere((g) => g.phone == group.phone);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resolve duplicate: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _resolvingPhones.remove(group.phone);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = _duplicateGroups.where((group) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      if (group.phone.contains(query)) return true;
      return group.entries.any((e) =>
          e.name.toLowerCase().contains(query) ||
          e.username.toLowerCase().contains(query) ||
          e.branch.toLowerCase().contains(query));
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Customer Duplicates',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF005BAC),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _fetchDuplicates,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter / Month selector header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month,
                        color: Color(0xFF005BAC), size: 22),
                    const SizedBox(width: 10),
                    const Text(
                      'Month: ',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedMonthYear,
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _monthYears.map((m) {
                          return DropdownMenuItem<String>(
                            value: m,
                            child: Text(m),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && val != _selectedMonthYear) {
                            setState(() {
                              _selectedMonthYear = val;
                            });
                            _fetchDuplicates();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by phone, customer, or user...',
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                ),
              ],
            ),
          ),

          // Status & Count Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Text(
                  'Duplicate Phone Clusters: ${filteredGroups.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (_duplicateGroups.isNotEmpty)
                  Text(
                    'Select user to retain customer',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),

          // Main body content
          Expanded(
            child: _buildBody(filteredGroups),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<DuplicateGroup> groups) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF005BAC)),
            SizedBox(height: 16),
            Text('Scanning all customer lists across branches...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchDuplicates,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005BAC),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.green.shade600, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No Duplicate Numbers Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'All customer numbers in $_selectedMonthYear are unique across all branches.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final isResolving = _resolvingPhones.contains(group.phone);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header of group
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_rounded,
                              size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 6),
                          Text(
                            group.phone,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${group.entries.length} Occurrences',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select the user who will keep this customer:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),

                // List of users/entries
                ...group.entries.asMap().entries.map((item) {
                  final entry = item.value;
                  final isSelected = group.selectedEntryId == entry.id;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF005BAC).withOpacity(0.06)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF005BAC)
                            : Colors.grey.shade300,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: RadioListTile<String>(
                      value: entry.id,
                      groupValue: group.selectedEntryId,
                      activeColor: const Color(0xFF005BAC),
                      onChanged: isResolving
                          ? null
                          : (val) {
                              setState(() {
                                group.selectedEntryId = val;
                              });
                            },
                      title: Builder(
                        builder: (context) {
                          // Find max remarks in this group
                          final maxRemarks = group.entries
                              .map((e) => e.remarksCount)
                              .fold<int>(0, (prev, elem) => elem > prev ? elem : prev);
                          final isHighest =
                              entry.remarksCount > 0 && entry.remarksCount == maxRemarks;

                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.username,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              // Remarks Count badge (showing only number)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isHighest
                                      ? Colors.amber.shade700
                                      : (entry.remarksCount > 0
                                          ? const Color(0xFF005BAC).withOpacity(0.12)
                                          : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isHighest
                                      ? Border.all(color: Colors.amber.shade900, width: 1)
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.comment_rounded,
                                      size: 11,
                                      color: isHighest
                                          ? Colors.white
                                          : (entry.remarksCount > 0
                                              ? const Color(0xFF005BAC)
                                              : Colors.grey.shade600),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${entry.remarksCount}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isHighest
                                          ? Colors.white
                                          : (entry.remarksCount > 0
                                              ? const Color(0xFF005BAC)
                                              : Colors.grey.shade700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8CC63F).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  entry.branch,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customer: ${entry.name}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                            if (entry.address.isNotEmpty)
                              Text(
                                'Address: ${entry.address}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            Row(
                              children: [
                                Text(
                                  entry.callMade
                                      ? 'Status: Call Made'
                                      : 'Status: Not Called',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: entry.callMade
                                        ? Colors.green.shade700
                                        : Colors.grey.shade600,
                                    fontWeight: entry.callMade
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                if (entry.remarks.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '• ${entry.remarks}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 8),

                // Action button
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed:
                        isResolving ? null : () => _resolveDuplicate(group),
                    icon: isResolving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(isResolving
                        ? 'Resolving...'
                        : 'Keep Selected & Remove Others'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF005BAC),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
