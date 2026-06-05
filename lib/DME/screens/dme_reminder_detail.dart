import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dme_reminder.dart';
import '../models/dme_sale.dart';
import '../services/dme_supabase_service.dart';
import '../services/dme_complaint_service.dart';
import '../../Leads/leadsform.dart';
import '../../Navigation/user_cache_service.dart';
import 'dme_create_complaint_page.dart';

class DmeReminderDetailPage extends StatefulWidget {
  final DmeReminder reminder;

  const DmeReminderDetailPage({
    super.key,
    required this.reminder,
  });

  @override
  State<DmeReminderDetailPage> createState() => _DmeReminderDetailPageState();
}

class _DmeReminderDetailPageState extends State<DmeReminderDetailPage> {
  final _svc = DmeSupabaseService.instance;

  late DmeReminder _currentReminder;
  bool _marking = false;
  // ignore: unused_field
  bool _rescheduling = false;
  // ignore: unused_field
  DateTime? _newReminderDate;
  List<DmeSaleItem> _saleItems = [];
  bool _loadingItems = false;

  @override
  void initState() {
    super.initState();
    _currentReminder = widget.reminder;
    _loadSaleItems();
  }

  Future<void> _loadSaleItems() async {
    setState(() => _loadingItems = true);
    try {
      final items = await _svc.getSaleItemsByCustomerDate(
        _currentReminder.customerId,
        _currentReminder.lastPurchaseDate,
      );
      if (mounted) setState(() { _saleItems = items; _loadingItems = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _markAsComplete() async {
    final remarksController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Call Remarks'),
        content: TextField(
          controller: remarksController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter call remarks / outcome...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save & Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _marking = true);
    try {
      if (_currentReminder.id != null) {
        await _svc.completeReminder(
          _currentReminder.id!,
          notes: remarksController.text.trim().isEmpty
              ? null
              : remarksController.text.trim(),
        );
        await _svc.deleteSaleItemsByCustomerDate(
          _currentReminder.customerId,
          _currentReminder.lastPurchaseDate,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Reminder marked as complete'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, 'completed');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _marking = false);
      }
    }
  }

  Future<void> _rescheduleReminder() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentReminder.reminderDate.add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && mounted) {
      setState(() => _newReminderDate = picked);
      
      // Here you can update the reminder date in Supabase
      // For now, just show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminder rescheduled to ${picked.toString().split(' ')[0]}'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _assignAsLead() {
    // Navigate to leads form with pre-filled data
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Assign as Lead'),
        content: const Text(
          'This will create a follow-up lead in the Leads system with the customer data pre-filled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005BAC),
            ),
            onPressed: () {
              Navigator.pop(context);
              _showLeadsForm();
            },
            child: const Text('Create Lead', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLeadsForm() {
    // Show leads form modal/dialog
    // This should auto-fill with customer name, phone, address
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FollowUpForm(
        initialName: _currentReminder.customerName,
        initialPhone: _currentReminder.customerPhone,
        initialAddress: _currentReminder.customerAddress,
        source: 'DME',
      ),
    );
  }

  Future<void> _raiseComplaint() async {
    try {
      // Get current user
      final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      if (firebaseUid == null) throw Exception('User not authenticated');
      
      // Get DME user from Supabase
      final dmeUser = await DmeSupabaseService.instance.getCurrentUser(firebaseUid);
      if (dmeUser == null) throw Exception('DME user not found');
      
      // Navigate to complaint creation page with pre-filled reminder data
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DmeCreateComplaintPage(
              dmeUser: dmeUser,
              onSubmitted: () {
                // Refresh reminder details after complaint is submitted
                setState(() {});
              },
              prefilledCustomerId: _currentReminder.customerId,
              prefilledCustomerName: _currentReminder.customerName,
              prefilledCustomerPhone: _currentReminder.customerPhone,
              prefilledBranchId: _currentReminder.purchasedForBranchId,
              prefilledBranchName: _currentReminder.purchasedForBranchName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Call Details'),
          backgroundColor: const Color(0xFF005BAC),
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // Customer Info Card
              _buildCustomerCard(),
              
              // Last Order Details (visible until call is completed)
              _buildLastOrderSection(),
              
              // Purchase History
              _buildPurchaseInfo(),
              
              // Reminder Info
              _buildReminderInfo(),
              
              // Action Buttons
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue[100]!),
        borderRadius: BorderRadius.circular(12),
        color: Colors.blue[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF005BAC),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentReminder.customerName ?? 'Unknown Customer',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Contact:',
                  _currentReminder.customerPhone ?? 'N/A',
                  Icons.phone,
                ),
                if (_currentReminder.salesman != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildInfoRow(
                      'Salesman:',
                      _currentReminder.salesman!,
                      Icons.person,
                    ),
                  ),
                if (_currentReminder.customerAddress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildInfoRow(
                      'Address:',
                      _currentReminder.customerAddress!,
                      Icons.location_on,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastOrderSection() {
    if (_loadingItems) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (_saleItems.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        border: Border.all(color: Colors.green[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.shopping_cart, size: 16, color: Colors.green[700]),
            const SizedBox(width: 8),
            const Text('Last Order',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          ..._saleItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.circle, size: 8, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(item.productName,
                          style: const TextStyle(fontSize: 13))),
                ]),
              )),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF005BAC)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPurchaseInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        border: Border.all(color: Colors.amber[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_bag, color: Colors.amber[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Last Purchase',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  _formatDate(_currentReminder.lastPurchaseDate),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(color: Colors.blue[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Color(0xFF005BAC)),
              SizedBox(width: 8),
              Text(
                'Reminder Due',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(_currentReminder.reminderDate),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF005BAC),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Status: ${_currentReminder.status}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentReminder.status.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF005BAC),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _marking ? null : _markAsComplete,
            icon: _marking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_marking ? 'Marking...' : 'Mark as Complete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _assignAsLead,
            icon: const Icon(Icons.assignment_ind),
            label: const Text('Assign as Lead'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF005BAC),
              side: const BorderSide(color: Color(0xFF005BAC)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _raiseComplaint,
            icon: const Icon(Icons.warning_amber),
            label: const Text('Raise Complaint'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _rescheduleReminder,
            icon: const Icon(Icons.update),
            label: const Text('Reschedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: const BorderSide(color: Colors.grey),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day} ${_getMonthName(date.month)} ${date.year}';
  }

  String _getMonthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }
}


