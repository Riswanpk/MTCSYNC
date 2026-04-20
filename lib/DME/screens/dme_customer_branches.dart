import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';

class DmeCustomerBranchesPage extends StatefulWidget {
  final DmeCustomer customer;
  final DmeUser dmeUser;

  const DmeCustomerBranchesPage({
    super.key,
    required this.customer,
    required this.dmeUser,
  });

  @override
  State<DmeCustomerBranchesPage> createState() =>
      _DmeCustomerBranchesPageState();
}

class _DmeCustomerBranchesPageState extends State<DmeCustomerBranchesPage> {
  final _svc = DmeSupabaseService.instance;
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      setState(() => _loading = true);
      final branches =
          await _svc.getCustomerBranchesWithPurchases(widget.customer.id!);
      setState(() => _branches = branches);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading branches: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.customer.name} - Branches'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _branches.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.business_rounded,
                            size: 48, color: Color(0xFF005BAC)),
                      ),
                      const SizedBox(height: 16),
                      const Text('No branches found',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('This customer has no purchase history',
                          style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final branch = _branches[index];
                    final branchName =
                        branch['branch_name'] as String? ?? 'Unknown';
                    final salesman =
                        branch['salesman'] as String? ?? 'Not Assigned';
                    final purchaseCount =
                        branch['purchase_count'] as int? ?? 0;
                    final lastPurchaseDate =
                        branch['last_purchase_date'] as String?;
                    final isPrimary = branch['is_primary'] as bool? ?? false;

                    return _BranchCard(
                      branchName: branchName,
                      salesman: salesman,
                      purchaseCount: purchaseCount,
                      lastPurchaseDate: lastPurchaseDate,
                      isPrimary: isPrimary,
                      isDark: isDark,
                      dateFmt: dateFmt,
                    );
                  },
                ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final String branchName;
  final String salesman;
  final int purchaseCount;
  final String? lastPurchaseDate;
  final bool isPrimary;
  final bool isDark;
  final DateFormat dateFmt;

  const _BranchCard({
    required this.branchName,
    required this.salesman,
    required this.purchaseCount,
    this.lastPurchaseDate,
    required this.isPrimary,
    required this.isDark,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with branch name and primary badge
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.business,
                      size: 20, color: Color(0xFF005BAC)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    branchName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isPrimary)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF005BAC),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PRIMARY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Salesman
            Row(
              children: [
                Icon(Icons.person,
                    size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Salesman: $salesman',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Purchase info
            Row(
              children: [
                Icon(Icons.shopping_bag,
                    size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Purchases: $purchaseCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            // Last purchase date (if available)
            if (lastPurchaseDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Last Purchase: ${dateFmt.format(DateTime.parse(lastPurchaseDate!))}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
