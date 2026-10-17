import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../Navigation/user_cache_service.dart';
import '../Customer Calling/customer_list_target_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DeletedCustomerEntry {
  final String branch;
  final String userEmail;
  final String customerName;
  final String contact1;
  final String contact2;
  final String address;
  final String remarks;
  final bool isCalled;

  DeletedCustomerEntry({
    required this.branch,
    required this.userEmail,
    required this.customerName,
    required this.contact1,
    required this.contact2,
    required this.address,
    required this.remarks,
    required this.isCalled,
  });
}

class DeletedUserCustomerGroup {
  final String userEmail;
  final String branch;
  final List<DeletedCustomerEntry> customers;

  DeletedUserCustomerGroup({
    required this.userEmail,
    required this.branch,
    required this.customers,
  });
}

class SyncHeadDeletedCustomerListPage extends StatefulWidget {
  const SyncHeadDeletedCustomerListPage({super.key});

  @override
  State<SyncHeadDeletedCustomerListPage> createState() =>
      _SyncHeadDeletedCustomerListPageState();
}

class _SyncHeadDeletedCustomerListPageState
    extends State<SyncHeadDeletedCustomerListPage> {
  late List<String> _monthYears;
  late String _selectedMonthYear;

  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  List<DeletedUserCustomerGroup> _groups = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initMonthYears();
    _fetchDeletedUserCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initMonthYears() {
    final now = DateTime.now();
    _monthYears = List.generate(24, (i) {
      final date = DateTime(now.year, now.month - i, 1);
      return "${CustomerListTargetService.monthName(date.month)} ${date.year}";
    });
    _selectedMonthYear = _monthYears.first;
  }

  Future<void> _fetchDeletedUserCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final activeUsers =
          await UserCacheService.instance.getAllUsers(forceRefresh: true);
      final Set<String> activeEmails = activeUsers
          .map((u) => (u['email'] as String? ?? '').toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toSet();

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('customer_target')
          .doc(_selectedMonthYear)
          .collection('users')
          .get();

      final List<DeletedUserCustomerGroup> groups = [];

      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        final rawEmail = (data['user'] ?? doc.id).toString().toLowerCase().trim();

        if (activeEmails.contains(rawEmail)) {
          continue;
        }

        final branch = (data['branch'] ?? 'Unknown').toString().trim();
        final rawCustomers = data['customers'];
        final List<DeletedCustomerEntry> customerEntries = [];

        if (rawCustomers is List) {
          for (final item in rawCustomers) {
            if (item is Map) {
              final cMap = Map<String, dynamic>.from(item);
              final name = (cMap['name'] ?? '').toString().trim();
              final c1 = (cMap['contact1'] ?? cMap['contact'] ?? '').toString().trim();
              final c2 = (cMap['contact2'] ?? '').toString().trim();
              final address = (cMap['address'] ?? '').toString().trim();
              final remarks = (cMap['remarks'] ?? '').toString().trim();
              final isCalled = cMap['callMade'] == true;

              if (name.isNotEmpty || c1.isNotEmpty || c2.isNotEmpty) {
                customerEntries.add(
                  DeletedCustomerEntry(
                    branch: branch,
                    userEmail: rawEmail,
                    customerName: name.isNotEmpty ? name : 'Unnamed Customer',
                    contact1: c1,
                    contact2: c2,
                    address: address,
                    remarks: remarks,
                    isCalled: isCalled,
                  ),
                );
              }
            }
          }
        }

        if (customerEntries.isNotEmpty) {
          groups.add(
            DeletedUserCustomerGroup(
              userEmail: rawEmail,
              branch: branch,
              customers: customerEntries,
            ),
          );
        }
      }

      groups.sort((a, b) => a.branch.compareTo(b.branch));

      if (mounted) {
        setState(() {
          _groups = groups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load data: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportToExcel() async {
    if (_groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No deleted user customer records to export.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Deleted Users Customers';

      final titleRange = sheet.getRangeByName('A1:G1');
      titleRange.merge();
      titleRange.setText('Deleted Users Customer List - $_selectedMonthYear');
      titleRange.cellStyle.bold = true;
      titleRange.cellStyle.fontSize = 14;
      titleRange.cellStyle.backColor = '#005BAC';
      titleRange.cellStyle.fontColor = '#FFFFFF';
      titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
      titleRange.cellStyle.vAlign = xlsio.VAlignType.center;

      final headers = [
        'Branch',
        'Deleted User Email',
        'Customer Name',
        'Contact 1',
        'Contact 2',
        'Address',
        'Remarks',
      ];

      for (int i = 0; i < headers.length; i++) {
        final colLetter = String.fromCharCode(65 + i);
        final cell = sheet.getRangeByName('${colLetter}2');
        cell.setText(headers[i]);
        cell.cellStyle.bold = true;
        cell.cellStyle.fontSize = 11;
        cell.cellStyle.backColor = '#37474F';
        cell.cellStyle.fontColor = '#FFFFFF';
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CCCCCC';
      }

      int rowIndex = 3;
      for (final group in _groups) {
        for (final c in group.customers) {
          sheet.getRangeByName('A$rowIndex').setText(c.branch);
          sheet.getRangeByName('B$rowIndex').setText(c.userEmail);
          sheet.getRangeByName('C$rowIndex').setText(c.customerName);
          sheet.getRangeByName('D$rowIndex').setText(c.contact1);
          sheet.getRangeByName('E$rowIndex').setText(c.contact2);
          sheet.getRangeByName('F$rowIndex').setText(c.address);
          sheet.getRangeByName('G$rowIndex').setText(c.remarks);

          for (int i = 0; i < headers.length; i++) {
            final colLetter = String.fromCharCode(65 + i);
            final cell = sheet.getRangeByName('$colLetter$rowIndex');
            cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
            cell.cellStyle.borders.all.color = '#E0E0E0';
          }
          rowIndex++;
        }
      }

      for (int i = 1; i <= headers.length; i++) {
        sheet.autoFitColumn(i);
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getTemporaryDirectory();
      final sanitizedMonth = _selectedMonthYear.replaceAll(' ', '_');
      final fileName = 'Deleted_Users_Customer_List_$sanitizedMonth.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Deleted Users Customer List - $_selectedMonthYear',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  void _showMonthPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primaryBlue, Color(0xFF0288D1)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Select Month',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _monthYears.length,
                  itemBuilder: (context, index) {
                    final month = _monthYears[index];
                    final isSelected = month == _selectedMonthYear;
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _primaryBlue.withValues(alpha: isDark ? 0.25 : 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? _primaryBlue.withValues(alpha: 0.6)
                              : Colors.grey.withValues(alpha: 0.12),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _primaryBlue
                                : Colors.grey.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: isSelected ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                        title: Text(
                          month,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? _primaryBlue
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: _primaryBlue, size: 20)
                            : null,
                        onTap: () {
                          Navigator.pop(ctx, month);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((selected) {
      if (selected != null && selected != _selectedMonthYear) {
        setState(() {
          _selectedMonthYear = selected;
        });
        _fetchDeletedUserCustomers();
      }
    });
  }

  int get _totalCustomerCount {
    return _groups.fold<int>(0, (prev, g) => prev + g.customers.length);
  }

  List<DeletedUserCustomerGroup> get _filteredGroups {
    if (_searchQuery.trim().isEmpty) return _groups;
    final q = _searchQuery.toLowerCase().trim();

    final List<DeletedUserCustomerGroup> filtered = [];
    for (final group in _groups) {
      final matchesGroup = group.userEmail.toLowerCase().contains(q) ||
          group.branch.toLowerCase().contains(q);

      final matchingCustomers = group.customers.where((c) {
        return c.customerName.toLowerCase().contains(q) ||
            c.contact1.toLowerCase().contains(q) ||
            c.contact2.toLowerCase().contains(q) ||
            c.address.toLowerCase().contains(q) ||
            c.remarks.toLowerCase().contains(q);
      }).toList();

      if (matchesGroup) {
        filtered.add(group);
      } else if (matchingCustomers.isNotEmpty) {
        filtered.add(
          DeletedUserCustomerGroup(
            userEmail: group.userEmail,
            branch: group.branch,
            customers: matchingCustomers,
          ),
        );
      }
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF121418) : const Color(0xFFF4F6F9);
    final cardBg = isDark ? const Color(0xFF1E222A) : Colors.white;

    final displayedGroups = _filteredGroups;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'Deleted User Lists',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 19,
            color: Colors.white,
          ),
        ),
        backgroundColor: _primaryBlue,
        elevation: 0,
        centerTitle: false,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF004987), _primaryBlue, Color(0xFF0277BD)],
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchDeletedUserCustomers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Month Selector Card & Summary
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black26
                      : const Color(0xFF90A4AE).withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _showMonthPicker,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF242A36)
                                : const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _primaryBlue.withValues(alpha: 0.4),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                color: _primaryBlue,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedMonthYear,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down_rounded,
                                color: _primaryBlue,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: (_isLoading || _isExporting || _groups.isEmpty)
                          ? null
                          : _exportToExcel,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 18),
                      label: Text(_isExporting ? 'Exporting...' : 'Excel List'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatPill(
                      label: 'Inactive Users',
                      count: _groups.length,
                      color: Colors.orange,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _buildStatPill(
                      label: 'Customers Total',
                      count: _totalCustomerCount,
                      color: _primaryBlue,
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search customer, phone, or email...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: cardBg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Error banner
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.red, size: 18),
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

          // Customer List View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayedGroups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_off_rounded,
                              size: 56,
                              color: isDark ? Colors.white24 : Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No matching results found.'
                                  : 'No customer lists found for deleted/inactive users.',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        itemCount: displayedGroups.length,
                        itemBuilder: (context, index) {
                          final group = displayedGroups[index];
                          return _buildUserGroupCard(
                            group: group,
                            isDark: isDark,
                            cardBg: cardBg,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill({
    required String label,
    required int count,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserGroupCard({
    required DeletedUserCustomerGroup group,
    required bool isDark,
    required Color cardBg,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : const Color(0xFF90A4AE).withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
            child: const Icon(
              Icons.no_accounts_rounded,
              color: Colors.orange,
              size: 20,
            ),
          ),
          title: Text(
            group.userEmail,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          subtitle: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Branch: ${group.branch}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${group.customers.length} customer(s)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(10),
              itemCount: group.customers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, cIdx) {
                final customer = group.customers[cIdx];
                return _buildCustomerItemTile(
                  customer: customer,
                  isDark: isDark,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerItemTile({
    required DeletedCustomerEntry customer,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242A36) : const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customer.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: customer.isCalled
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  customer.isCalled ? 'Called' : 'Not Called',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: customer.isCalled ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (customer.contact1.isNotEmpty || customer.contact2.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  [customer.contact1, customer.contact2]
                      .where((c) => c.isNotEmpty)
                      .join(' / '),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          if (customer.address.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customer.address,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (customer.remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E222A)
                    : Colors.amber.shade50.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amber.shade200.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'Remark: ${customer.remarks}',
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
    );
  }
}
