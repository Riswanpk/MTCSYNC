import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../Misc/dme_constants.dart';
import 'dme_admin_customer_detail_page.dart';
import 'dme_customer_merge_service.dart';

const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class DmeCustomerMergePage extends StatefulWidget {
  final Map<String, dynamic>? initialCustomer1;
  final Map<String, dynamic>? initialCustomer2;

  const DmeCustomerMergePage({
    super.key,
    this.initialCustomer1,
    this.initialCustomer2,
  });

  @override
  State<DmeCustomerMergePage> createState() => _DmeCustomerMergePageState();
}

class _DmeCustomerMergePageState extends State<DmeCustomerMergePage> {
  Map<String, dynamic>? _cust1;
  Map<String, dynamic>? _cust2;

  CustomerMergeStats? _stats1;
  CustomerMergeStats? _stats2;
  bool _isLoadingStats1 = false;
  bool _isLoadingStats2 = false;

  // Master customer choice: 1 => Customer 1 kept unchanged, 2 => Customer 2 kept unchanged
  int _masterCustomerIndex = 1;

  // Name choice: 'cust1', 'cust2', 'custom'
  String _nameChoice = 'cust1';
  final TextEditingController _customNameCtrl = TextEditingController();

  // Phone choice: 'cust1', 'cust2', 'custom'
  String _phoneChoice = 'cust1';
  final TextEditingController _customPhoneCtrl = TextEditingController();

  // Field choices: 'cust1' or 'cust2'
  String _addressChoice = 'cust1';
  String _salesmanChoice = 'cust1';
  String _preferenceChoice = 'cust1';
  String _primaryBranchChoice = 'cust1';

  // Active reminder strategy when both have pending reminders: 'keep_target', 'keep_source', 'keep_both'
  String _activeReminderStrategy = 'keep_target';

  bool _isMerging = false;
  String _mergeProgressMessage = 'Processing merge...';

  @override
  void initState() {
    super.initState();
    if (widget.initialCustomer1 != null) {
      _selectCustomer1(widget.initialCustomer1!);
    }
    if (widget.initialCustomer2 != null) {
      _selectCustomer2(widget.initialCustomer2!);
    }
  }

  @override
  void dispose() {
    _customNameCtrl.dispose();
    _customPhoneCtrl.dispose();
    super.dispose();
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) return DateFormat('dd-MM-yyyy').format(date);
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) return DateFormat('dd-MM-yyyy').format(parsed);
    return str;
  }

  Future<void> _selectCustomer1(Map<String, dynamic> cust) async {
    setState(() {
      _cust1 = cust;
      _stats1 = null;
      _isLoadingStats1 = true;
      _applyDefaults();
    });

    final id = int.tryParse(cust['id']?.toString() ?? '');
    if (id != null) {
      final stats = await DmeCustomerMergeService.fetchCustomerStats(id);
      if (mounted) {
        setState(() {
          _stats1 = stats;
          _isLoadingStats1 = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingStats1 = false);
    }
  }

  Future<void> _selectCustomer2(Map<String, dynamic> cust) async {
    setState(() {
      _cust2 = cust;
      _stats2 = null;
      _isLoadingStats2 = true;
      _applyDefaults();
    });

    final id = int.tryParse(cust['id']?.toString() ?? '');
    if (id != null) {
      final stats = await DmeCustomerMergeService.fetchCustomerStats(id);
      if (mounted) {
        setState(() {
          _stats2 = stats;
          _isLoadingStats2 = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingStats2 = false);
    }
  }

  void _applyDefaults() {
    if (_cust1 == null && _cust2 == null) return;

    if (_masterCustomerIndex == 1 && _cust1 != null) {
      _nameChoice = 'cust1';
      _phoneChoice = 'cust1';
      _customNameCtrl.text = _cust1!['name']?.toString() ?? '';
      _customPhoneCtrl.text = _cust1!['phone']?.toString() ?? '';
      _addressChoice = (_cust1!['address']?.toString().isNotEmpty == true) ? 'cust1' : 'cust2';
      _salesmanChoice = (_cust1!['salesman']?.toString().isNotEmpty == true) ? 'cust1' : 'cust2';
      _preferenceChoice = 'cust1';
      _primaryBranchChoice = 'cust1';
    } else if (_masterCustomerIndex == 2 && _cust2 != null) {
      _nameChoice = 'cust2';
      _phoneChoice = 'cust2';
      _customNameCtrl.text = _cust2!['name']?.toString() ?? '';
      _customPhoneCtrl.text = _cust2!['phone']?.toString() ?? '';
      _addressChoice = (_cust2!['address']?.toString().isNotEmpty == true) ? 'cust2' : 'cust1';
      _salesmanChoice = (_cust2!['salesman']?.toString().isNotEmpty == true) ? 'cust2' : 'cust1';
      _preferenceChoice = 'cust2';
      _primaryBranchChoice = 'cust2';
    }
  }

  void _swapCustomers() {
    if (_cust1 == null && _cust2 == null) return;
    setState(() {
      final tempCust = _cust1;
      final tempStats = _stats1;
      final tempLoading = _isLoadingStats1;

      _cust1 = _cust2;
      _stats1 = _stats2;
      _isLoadingStats1 = _isLoadingStats2;

      _cust2 = tempCust;
      _stats2 = tempStats;
      _isLoadingStats2 = tempLoading;

      _applyDefaults();
    });
  }

  String _getResolvedName() {
    if (_nameChoice == 'cust1' && _cust1 != null) {
      return (_cust1!['name'] ?? '').toString().trim();
    } else if (_nameChoice == 'cust2' && _cust2 != null) {
      return (_cust2!['name'] ?? '').toString().trim();
    } else {
      return _customNameCtrl.text.trim();
    }
  }

  String _getResolvedPhone() {
    if (_phoneChoice == 'cust1' && _cust1 != null) {
      return (_cust1!['phone'] ?? '').toString().trim();
    } else if (_phoneChoice == 'cust2' && _cust2 != null) {
      return (_cust2!['phone'] ?? '').toString().trim();
    } else {
      return _customPhoneCtrl.text.trim();
    }
  }

  String? _getResolvedAddress() {
    if (_addressChoice == 'cust1') {
      final val = _cust1?['address']?.toString().trim();
      return (val != null && val.isNotEmpty) ? val : _cust2?['address']?.toString().trim();
    } else {
      final val = _cust2?['address']?.toString().trim();
      return (val != null && val.isNotEmpty) ? val : _cust1?['address']?.toString().trim();
    }
  }

  String? _getResolvedSalesman() {
    if (_salesmanChoice == 'cust1') {
      final val = _cust1?['salesman']?.toString().trim();
      return (val != null && val.isNotEmpty) ? val : _cust2?['salesman']?.toString().trim();
    } else {
      final val = _cust2?['salesman']?.toString().trim();
      return (val != null && val.isNotEmpty) ? val : _cust1?['salesman']?.toString().trim();
    }
  }

  String? _getResolvedPreference() {
    if (_preferenceChoice == 'cust1') {
      return _cust1?['preference']?.toString().trim() ?? 'Call';
    } else {
      return _cust2?['preference']?.toString().trim() ?? 'Call';
    }
  }

  int? _getResolvedPrimaryBranch() {
    final b1 = int.tryParse(_cust1?['primary_branch']?.toString() ?? '');
    final b2 = int.tryParse(_cust2?['primary_branch']?.toString() ?? '');
    if (_primaryBranchChoice == 'cust1') {
      return b1 ?? b2;
    } else {
      return b2 ?? b1;
    }
  }

  DateTime? _getResolvedLastPurchaseDate() {
    final d1Str = _cust1?['last_purchase_date']?.toString();
    final d2Str = _cust2?['last_purchase_date']?.toString();
    final d1 = d1Str != null ? DateTime.tryParse(d1Str) : null;
    final d2 = d2Str != null ? DateTime.tryParse(d2Str) : null;

    if (d1 == null) return d2;
    if (d2 == null) return d1;
    return d1.isAfter(d2) ? d1 : d2;
  }

  Future<void> _openCustomerSearchModal({required int customerSlot}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CustomerSearchModal(
        slotNumber: customerSlot,
        excludeCustomerId: customerSlot == 1
            ? int.tryParse(_cust2?['id']?.toString() ?? '')
            : int.tryParse(_cust1?['id']?.toString() ?? ''),
      ),
    );

    if (result != null) {
      if (customerSlot == 1) {
        _selectCustomer1(result);
      } else {
        _selectCustomer2(result);
      }
    }
  }

  void _confirmAndExecuteMerge() {
    if (_cust1 == null || _cust2 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select two customers to merge.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final targetCust = _masterCustomerIndex == 1 ? _cust1! : _cust2!;
    final sourceCust = _masterCustomerIndex == 1 ? _cust2! : _cust1!;

    final targetId = int.tryParse(targetCust['id']?.toString() ?? '');
    final sourceId = int.tryParse(sourceCust['id']?.toString() ?? '');

    if (targetId == null || sourceId == null || targetId == sourceId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid customer selection for merge.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final resolvedName = _getResolvedName();
    final resolvedPhone = _getResolvedPhone();

    if (resolvedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer name cannot be empty.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (resolvedPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer phone cannot be empty.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Confirm Customer Merge', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You are about to merge two customer records into one:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Master Profile Kept (ID: #$targetId)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('• Final Name: $resolvedName', style: const TextStyle(fontSize: 12)),
                    Text('• Final Phone: $resolvedPhone', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.merge_type_rounded, color: Colors.orange, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Merged Customer (ID: #$sourceId)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• All reminders & call history will be transferred to Master ID.\n'
                      '• All sales transactions & branch connections will be consolidated.\n'
                      '• Customer #$sourceId profile will be permanently removed.',
                      style: const TextStyle(fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This action cannot be undone. Are you sure you want to proceed?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _performMerge(
                targetId: targetId,
                sourceId: sourceId,
                resolvedName: resolvedName,
                resolvedPhone: resolvedPhone,
              );
            },
            child: const Text('Confirm & Merge'),
          ),
        ],
      ),
    );
  }

  Future<void> _performMerge({
    required int targetId,
    required int sourceId,
    required String resolvedName,
    required String resolvedPhone,
  }) async {
    setState(() {
      _isMerging = true;
      _mergeProgressMessage = 'Starting customer merge...';
    });

    final result = await DmeCustomerMergeService.mergeCustomers(
      targetCustomerId: targetId,
      sourceCustomerId: sourceId,
      resolvedName: resolvedName,
      resolvedPhone: resolvedPhone,
      resolvedAddress: _getResolvedAddress(),
      resolvedSalesman: _getResolvedSalesman(),
      resolvedPreference: _getResolvedPreference(),
      resolvedPrimaryBranch: _getResolvedPrimaryBranch(),
      resolvedLastPurchaseDate: _getResolvedLastPurchaseDate(),
      activeReminderStrategy: _activeReminderStrategy,
      onProgress: (msg) {
        if (mounted) setState(() => _mergeProgressMessage = msg);
      },
    );

    if (!mounted) return;
    setState(() => _isMerging = false);

    if (result.success) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Merge Completed!', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Reminders Transferred: ${result.remindersTransferred}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('• Sales Transferred: ${result.salesTransferred}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('• Branches Added: ${result.branchesTransferred}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'All reminder and call history is now linked to this customer and can be easily viewed.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _cust1 = null;
                  _cust2 = null;
                  _stats1 = null;
                  _stats2 = null;
                });
              },
              child: const Text('Merge Another'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                // Navigate to customer detail page
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeAdminCustomerDetailPage(
                      customer: {
                        'id': result.targetCustomerId,
                        'name': result.targetCustomerName,
                        'phone': resolvedPhone,
                        'address': _getResolvedAddress(),
                        'salesman': _getResolvedSalesman(),
                        'preference': _getResolvedPreference(),
                        'primary_branch': _getResolvedPrimaryBranch(),
                        'last_purchase_date': _getResolvedLastPurchaseDate()?.toIso8601String(),
                      },
                    ),
                  ),
                );
              },
              child: const Text('View Customer Profile'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Merge Failed', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(result.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bothSelected = _cust1 != null && _cust2 != null;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Customer Merge', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: _primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              if (bothSelected)
                IconButton(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  tooltip: 'Swap Customer 1 and Customer 2',
                  onPressed: _swapCustomers,
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info Banner
                _buildInfoBanner(isDark),
                const SizedBox(height: 16),

                // Step 1: Customer Selection
                _buildSectionHeader('Step 1: Select Customers to Merge', Icons.people_outline_rounded),
                const SizedBox(height: 10),
                _buildCustomerPickers(isDark),
                const SizedBox(height: 20),

                // Step 2 & 3: Configuration (Only shown when both selected)
                if (bothSelected) ...[
                  // Preserved History Choice
                  _buildSectionHeader('Step 2: Choose Customer Kept Without Change', Icons.verified_user_rounded),
                  const SizedBox(height: 4),
                  Text(
                    'Select which customer profile and ID remains unchanged. The other customer\'s reminders in history, sales, and branches will be moved into this profile.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                  const SizedBox(height: 10),
                  _buildMasterSelection(isDark),
                  const SizedBox(height: 20),

                  // Name & Phone Resolution
                  _buildSectionHeader('Step 3: Resolve Name & Phone Number', Icons.contact_phone_rounded),
                  const SizedBox(height: 4),
                  Text(
                    'Choose which name and phone number to keep for the final merged customer profile.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                  const SizedBox(height: 10),
                  _buildNameResolutionCard(isDark),
                  const SizedBox(height: 12),
                  _buildPhoneResolutionCard(isDark),
                  const SizedBox(height: 20),

                  // Additional Details Resolution
                  _buildSectionHeader('Step 4: Additional Customer Details', Icons.tune_rounded),
                  const SizedBox(height: 10),
                  _buildAdditionalDetailsCard(isDark),
                  const SizedBox(height: 20),

                  // Reminder & History Preview
                  _buildSectionHeader('Step 5: Reminders & History Consolidation', Icons.history_rounded),
                  const SizedBox(height: 10),
                  _buildRemindersConsolidationCard(isDark),
                  const SizedBox(height: 24),

                  // Merge Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.merge_type_rounded, size: 24),
                    label: const Text(
                      'Merge Customers Now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _confirmAndExecuteMerge,
                  ),
                  const SizedBox(height: 30),
                ] else ...[
                  // Placeholder when not both selected
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.call_merge_rounded, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'Select both Customer 1 and Customer 2 above to configure merge settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Merge Loading Overlay
        if (_isMerging)
          Container(
            color: Colors.black.withValues(alpha: 0.65),
            child: Center(
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: _primaryBlue),
                      const SizedBox(height: 18),
                      Text(
                        _mergeProgressMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Please wait, consolidating customer records...',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _primaryBlue, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Merge duplicate customer records into a single unified profile. All reminders, call history, and sales from both customers are retained under the chosen master profile so full history is preserved.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  Widget _buildCustomerPickers(bool isDark) {
    return Column(
      children: [
        _buildCustomerCard(
          slotNumber: 1,
          customer: _cust1,
          stats: _stats1,
          isLoadingStats: _isLoadingStats1,
          isDark: isDark,
          isMaster: _masterCustomerIndex == 1,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _primaryBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.swap_vert_rounded, color: _primaryBlue, size: 24),
            ),
            const SizedBox(width: 8),
            Text(
              'MERGING INTO ONE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCustomerCard(
          slotNumber: 2,
          customer: _cust2,
          stats: _stats2,
          isLoadingStats: _isLoadingStats2,
          isDark: isDark,
          isMaster: _masterCustomerIndex == 2,
        ),
      ],
    );
  }

  Widget _buildCustomerCard({
    required int slotNumber,
    required Map<String, dynamic>? customer,
    required CustomerMergeStats? stats,
    required bool isLoadingStats,
    required bool isDark,
    required bool isMaster,
  }) {
    if (customer == null) {
      return InkWell(
        onTap: () => _openCustomerSearchModal(customerSlot: slotNumber),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              style: BorderStyle.solid,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _primaryBlue.withValues(alpha: 0.1),
                child: Text('$slotNumber', style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Customer $slotNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to search by name, phone, address...',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.search_rounded, color: _primaryBlue),
            ],
          ),
        ),
      );
    }

    final name = customer['name'] ?? 'Unnamed';
    final phone = customer['phone'] ?? 'N/A';
    final id = customer['id'];
    final salesman = customer['salesman'] ?? '';
    final address = customer['address'] ?? '';
    final primaryBranch = int.tryParse(customer['primary_branch']?.toString() ?? '');
    final lastPurchase = customer['last_purchase_date'];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isMaster ? _primaryGreen : Colors.grey.withValues(alpha: 0.3),
          width: isMaster ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isMaster
                      ? _primaryGreen.withValues(alpha: 0.2)
                      : _primaryBlue.withValues(alpha: 0.1),
                  child: Text(
                    'C$slotNumber',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isMaster ? Colors.green[800] : _primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('ID: #$id', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone_iphone_rounded, size: 14, color: _primaryBlue),
                          const SizedBox(width: 4),
                          Text(phone, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (primaryBranch != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Primary Branch: ${DmeConstants.getBranchName(primaryBranch)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                      if (salesman.isNotEmpty) ...[
                        Text(
                          'Salesman: $salesman',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                      if (address.isNotEmpty) ...[
                        Text(
                          'Address: $address',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (lastPurchase != null) ...[
                        Text(
                          'Last Purchase: ${_formatDate(lastPurchase)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Change Customer $slotNumber',
                  onPressed: () => _openCustomerSearchModal(customerSlot: slotNumber),
                ),
              ],
            ),
            const Divider(height: 18),
            // Stats Row
            if (isLoadingStats)
              const LinearProgressIndicator(minHeight: 2)
            else if (stats != null)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildStatBadge(
                    icon: Icons.alarm_rounded,
                    label: '${stats.totalReminders} Reminders (${stats.completedReminders} call history)',
                    color: Colors.orange,
                  ),
                  _buildStatBadge(
                    icon: Icons.receipt_long_rounded,
                    label: '${stats.totalSales} Sales',
                    color: _primaryGreen,
                  ),
                  _buildStatBadge(
                    icon: Icons.storefront_rounded,
                    label: '${stats.branchIds.length} Branches',
                    color: _primaryBlue,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBadge({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterSelection(bool isDark) {
    final name1 = _cust1?['name'] ?? 'Customer 1';
    final id1 = _cust1?['id'] ?? '';
    final name2 = _cust2?['name'] ?? 'Customer 2';
    final id2 = _cust2?['id'] ?? '';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          RadioListTile<int>(
            value: 1,
            groupValue: _masterCustomerIndex,
            activeColor: _primaryBlue,
            title: Text(
              'Keep Customer 1 (#$id1 - $name1) unchanged',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              'Customer 1 will be the surviving master profile. Customer 2 (#$id2)\'s reminders, calls, sales & branches will be merged into Customer 1.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _masterCustomerIndex = val;
                  _applyDefaults();
                });
              }
            },
          ),
          const Divider(height: 1),
          RadioListTile<int>(
            value: 2,
            groupValue: _masterCustomerIndex,
            activeColor: _primaryBlue,
            title: Text(
              'Keep Customer 2 (#$id2 - $name2) unchanged',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              'Customer 2 will be the surviving master profile. Customer 1 (#$id1)\'s reminders, calls, sales & branches will be merged into Customer 2.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
            ),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _masterCustomerIndex = val;
                  _applyDefaults();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNameResolutionCard(bool isDark) {
    final name1 = (_cust1?['name'] ?? '').toString().trim();
    final name2 = (_cust2?['name'] ?? '').toString().trim();
    final namesMatch = name1.toLowerCase() == name2.toLowerCase();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_rounded, size: 18, color: _primaryBlue),
                const SizedBox(width: 8),
                const Text('Customer Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (namesMatch)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check, size: 12, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Names Match', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'cust1',
              groupValue: _nameChoice,
              dense: true,
              activeColor: _primaryBlue,
              title: Text('Customer 1: "$name1"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (val) => setState(() => _nameChoice = val!),
            ),
            RadioListTile<String>(
              value: 'cust2',
              groupValue: _nameChoice,
              dense: true,
              activeColor: _primaryBlue,
              title: Text('Customer 2: "$name2"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (val) => setState(() => _nameChoice = val!),
            ),
            RadioListTile<String>(
              value: 'custom',
              groupValue: _nameChoice,
              dense: true,
              activeColor: _primaryBlue,
              title: const Text('Custom Name (Edit manually)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (val) => setState(() => _nameChoice = val!),
            ),
            if (_nameChoice == 'custom') ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  controller: _customNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Enter Final Customer Name',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneResolutionCard(bool isDark) {
    final phone1 = (_cust1?['phone'] ?? '').toString().trim();
    final phone2 = (_cust2?['phone'] ?? '').toString().trim();
    final phonesMatch = phone1 == phone2;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_rounded, size: 18, color: _primaryBlue),
                const SizedBox(width: 8),
                const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (phonesMatch)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check, size: 12, color: Colors.green),
                        SizedBox(width: 4),
                        Text('Phones Match', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'cust1',
              groupValue: _phoneChoice,
              dense: true,
              activeColor: _primaryBlue,
              title: Text('Customer 1: "$phone1"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (val) => setState(() => _phoneChoice = val!),
            ),
            RadioListTile<String>(
              value: 'cust2',
              groupValue: _phoneChoice,
              dense: true,
              activeColor: _primaryBlue,
              title: Text('Customer 2: "$phone2"', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (val) => setState(() => _phoneChoice = val!),
            ),
            RadioListTile<String>(
              value: 'custom',
              groupValue: _phoneChoice,
              dense: true,
              activeColor: _primaryBlue,
              title: const Text('Custom Phone (Edit manually)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              onChanged: (val) => setState(() => _phoneChoice = val!),
            ),
            if (_phoneChoice == 'custom') ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  controller: _customPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Enter Final Phone Number',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalDetailsCard(bool isDark) {
    final addr1 = (_cust1?['address'] ?? '').toString().trim();
    final addr2 = (_cust2?['address'] ?? '').toString().trim();
    final sales1 = (_cust1?['salesman'] ?? '').toString().trim();
    final sales2 = (_cust2?['salesman'] ?? '').toString().trim();
    final pref1 = (_cust1?['preference'] ?? 'Call').toString().trim();
    final pref2 = (_cust2?['preference'] ?? 'Call').toString().trim();
    final b1 = int.tryParse(_cust1?['primary_branch']?.toString() ?? '');
    final b2 = int.tryParse(_cust2?['primary_branch']?.toString() ?? '');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Address
            const Text('Keep Address From:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust1',
                    groupValue: _addressChoice,
                    dense: true,
                    title: Text(addr1.isEmpty ? 'Customer 1 (Empty)' : 'C1: $addr1',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _addressChoice = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust2',
                    groupValue: _addressChoice,
                    dense: true,
                    title: Text(addr2.isEmpty ? 'Customer 2 (Empty)' : 'C2: $addr2',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _addressChoice = val!),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),

            // Salesman
            const Text('Keep Salesman From:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust1',
                    groupValue: _salesmanChoice,
                    dense: true,
                    title: Text(sales1.isEmpty ? 'Customer 1 (None)' : 'C1: $sales1',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _salesmanChoice = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust2',
                    groupValue: _salesmanChoice,
                    dense: true,
                    title: Text(sales2.isEmpty ? 'Customer 2 (None)' : 'C2: $sales2',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _salesmanChoice = val!),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),

            // Primary Branch
            const Text('Keep Primary Branch From:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust1',
                    groupValue: _primaryBranchChoice,
                    dense: true,
                    title: Text(b1 == null ? 'Customer 1 (None)' : 'C1: ${DmeConstants.getBranchName(b1)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _primaryBranchChoice = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust2',
                    groupValue: _primaryBranchChoice,
                    dense: true,
                    title: Text(b2 == null ? 'Customer 2 (None)' : 'C2: ${DmeConstants.getBranchName(b2)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _primaryBranchChoice = val!),
                  ),
                ),
              ],
            ),
            const Divider(height: 12),

            // Call Preference
            const Text('Keep Preference From:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust1',
                    groupValue: _preferenceChoice,
                    dense: true,
                    title: Text('C1: $pref1', style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _preferenceChoice = val!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    value: 'cust2',
                    groupValue: _preferenceChoice,
                    dense: true,
                    title: Text('C2: $pref2', style: const TextStyle(fontSize: 12)),
                    onChanged: (val) => setState(() => _preferenceChoice = val!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemindersConsolidationCard(bool isDark) {
    final r1Count = _stats1?.totalReminders ?? 0;
    final r2Count = _stats2?.totalReminders ?? 0;
    final totalRemindersAfter = r1Count + r2Count;

    final s1Count = _stats1?.totalSales ?? 0;
    final s2Count = _stats2?.totalSales ?? 0;
    final totalSalesAfter = s1Count + s2Count;

    final bothHaveActiveReminders =
        (_stats1?.pendingReminders ?? 0) > 0 && (_stats2?.pendingReminders ?? 0) > 0;

    final targetCust = _masterCustomerIndex == 1 ? _cust1 : _cust2;
    final targetId = targetCust?['id'];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.sync_alt_rounded, size: 20, color: _primaryGreen),
                SizedBox(width: 8),
                Text('Unified History Impact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Combined Reminders:', style: TextStyle(fontSize: 13)),
                      Text(
                        '$totalRemindersAfter reminders',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryBlue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Combined Invoices/Sales:', style: TextStyle(fontSize: 13)),
                      Text(
                        '$totalSalesAfter sales',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _primaryGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All completed reminder calls and pending tasks will be unified under Customer ID #$targetId. Any future reminder checks, call history logs, or reports will instantly access the consolidated history.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ],
              ),
            ),

            if (bothHaveActiveReminders) ...[
              const SizedBox(height: 14),
              Row(
                children: const [
                  Icon(Icons.warning_rounded, color: Colors.orange, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Active Reminder Conflict Resolution:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Both customers have active/pending reminders. Choose how to handle the active task:',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              RadioListTile<String>(
                value: 'keep_target',
                groupValue: _activeReminderStrategy,
                dense: true,
                title: Text('Keep Master Customer active reminder & complete other with audit note',
                    style: const TextStyle(fontSize: 12)),
                onChanged: (val) => setState(() => _activeReminderStrategy = val!),
              ),
              RadioListTile<String>(
                value: 'keep_source',
                groupValue: _activeReminderStrategy,
                dense: true,
                title: Text('Keep Merged Customer active reminder & complete other',
                    style: const TextStyle(fontSize: 12)),
                onChanged: (val) => setState(() => _activeReminderStrategy = val!),
              ),
              RadioListTile<String>(
                value: 'keep_both',
                groupValue: _activeReminderStrategy,
                dense: true,
                title: const Text('Keep both active reminders under master profile', style: TextStyle(fontSize: 12)),
                onChanged: (val) => setState(() => _activeReminderStrategy = val!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Modal bottom sheet for searching and selecting a customer
class _CustomerSearchModal extends StatefulWidget {
  final int slotNumber;
  final int? excludeCustomerId;

  const _CustomerSearchModal({
    required this.slotNumber,
    this.excludeCustomerId,
  });

  @override
  State<_CustomerSearchModal> createState() => _CustomerSearchModalState();
}

class _CustomerSearchModalState extends State<_CustomerSearchModal> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debouncer;
  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _debouncer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debouncer?.cancel();
    final q = val.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    _debouncer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _isLoading = true);

      final list = await DmeCustomerMergeService.searchCustomers(q);
      if (!mounted) return;

      setState(() {
        _results = list;
        _isLoading = false;
      });
    });
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) return DateFormat('dd-MM-yyyy').format(date);
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) return DateFormat('dd-MM-yyyy').format(parsed);
    return str;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _primaryBlue.withValues(alpha: 0.1),
                    child: Text('${widget.slotNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: _primaryBlue)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Select Customer ${widget.slotNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Search Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search by customer name, phone, address...',
                  prefixIcon: const Icon(Icons.search_rounded, color: _primaryBlue),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const Divider(height: 16),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_rounded, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text(
                                _searchCtrl.text.isEmpty
                                    ? 'Type in the box above to find customers'
                                    : 'No customers found matching "${_searchCtrl.text.trim()}"',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final cust = _results[index];
                            final custId = int.tryParse(cust['id']?.toString() ?? '');
                            final isExcluded = widget.excludeCustomerId != null &&
                                custId != null &&
                                custId == widget.excludeCustomerId;

                            final name = cust['name'] ?? 'Unnamed';
                            final phone = cust['phone'] ?? 'N/A';
                            final address = cust['address'] ?? '';
                            final salesman = cust['salesman'] ?? '';
                            final primaryBranch = int.tryParse(cust['primary_branch']?.toString() ?? '');
                            final lastPurchase = cust['last_purchase_date'];

                            return ListTile(
                              enabled: !isExcluded,
                              leading: CircleAvatar(
                                backgroundColor: isExcluded
                                    ? Colors.grey.withValues(alpha: 0.2)
                                    : _primaryBlue.withValues(alpha: 0.1),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isExcluded ? Colors.grey : _primaryBlue,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isExcluded ? Colors.grey : null,
                                      ),
                                    ),
                                  ),
                                  if (custId != null)
                                    Text(
                                      '#$custId',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.bold),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.phone_iphone_rounded, size: 12, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(phone, style: TextStyle(fontSize: 12, color: isExcluded ? Colors.grey : null)),
                                      if (primaryBranch != null) ...[
                                        const SizedBox(width: 8),
                                        Text('• ${DmeConstants.getBranchName(primaryBranch)}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                      ],
                                    ],
                                  ),
                                  if (address.isNotEmpty || salesman.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      [
                                        if (salesman.isNotEmpty) 'Salesman: $salesman',
                                        if (address.isNotEmpty) address,
                                      ].join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                  if (lastPurchase != null) ...[
                                    Text('Last Purchase: ${_formatDate(lastPurchase)}',
                                        style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                                  ],
                                  if (isExcluded) ...[
                                    const SizedBox(height: 2),
                                    const Text('Already selected for the other slot',
                                        style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                              onTap: isExcluded ? null : () => Navigator.pop(context, cust),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
