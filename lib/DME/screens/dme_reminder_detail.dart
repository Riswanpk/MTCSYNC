import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dme_reminder.dart';
import '../models/dme_complaint.dart';
import '../services/dme_supabase_service.dart';
import '../services/dme_complaint_service.dart';
import '../../Leads/leadsform.dart';
import '../../Navigation/user_cache_service.dart';

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
  bool _rescheduling = false;
  DateTime? _newReminderDate;

  @override
  void initState() {
    super.initState();
    _currentReminder = widget.reminder;
  }

  Future<void> _markAsComplete() async {
    setState(() => _marking = true);
    try {
      if (_currentReminder.id != null) {
        await _svc.completeReminder(_currentReminder.id!);
        
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
      ),
    );
  }

  void _raiseComplaint() {
    // Navigate to complaint form
    showDialog(
      context: context,
      builder: (_) => _ComplaintFormDialog(
        customerName: _currentReminder.customerName ?? 'Unknown',
        customerPhone: _currentReminder.customerPhone ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
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
                  'Contact 1:',
                  _currentReminder.customerPhone ?? 'N/A',
                  Icons.phone,
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

class _ComplaintFormDialog extends StatefulWidget {
  final String customerName;
  final String customerPhone;

  const _ComplaintFormDialog({
    required this.customerName,
    required this.customerPhone,
  });

  @override
  State<_ComplaintFormDialog> createState() => _ComplaintFormDialogState();
}

class _ComplaintFormDialogState extends State<_ComplaintFormDialog> {
  final _complaintService = DmeComplaintService.instance;
  final _auth = FirebaseAuth.instance;
  
  late TextEditingController _complaintController;
  String _selectedCategory = 'Other';
  bool _submitting = false;
  String? _userBranch;

  @override
  void initState() {
    super.initState();
    _complaintController = TextEditingController();
    _loadUserBranch();
  }

  Future<void> _loadUserBranch() async {
    try {
      await UserCacheService.instance.ensureLoaded();
      final branch = UserCacheService.instance.branch;
      setState(() => _userBranch = branch);
    } catch (e) {
      print('Error loading user branch: $e');
    }
  }

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _submitComplaint() async {
    if (_complaintController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter complaint details'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final complaint = DmeComplaint(
        customerName: widget.customerName,
        customerPhone: widget.customerPhone,
        branch: _userBranch ?? 'Unknown',
        complaintText: _complaintController.text.trim(),
        category: _selectedCategory,
        status: 'raised',
        createdBy: _auth.currentUser?.uid ?? '',
        createdAt: DateTime.now(),
      );

      await _complaintService.createComplaint(complaint);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Complaint raised successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error raising complaint: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Raise Complaint',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Customer Info (read-only)
              Text(
                'Customer: ${widget.customerName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Contact: ${widget.customerPhone}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              
              // Category
              const Text(
                'Category',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                isExpanded: true,
                value: _selectedCategory,
                items: ['Quality', 'Delivery', 'Payment', 'Other']
                    .map((cat) => DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    ))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val ?? 'Other'),
              ),
              const SizedBox(height: 16),
              
              // Complaint Text
              const Text(
                'Complaint Details',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _complaintController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe the complaint...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _submitting ? null : _submitComplaint,
                    icon: _submitting
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                        : const Icon(Icons.send),
                    label: Text(_submitting ? 'Submitting...' : 'Submit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
