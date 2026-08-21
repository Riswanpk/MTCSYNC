import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/dme_reminder_model.dart';
import '../services/dme_reminder_service.dart';
import '../../models/dme_user.dart';

class DmeReminderDetailScreen extends StatefulWidget {
  final DmeReminderModel reminder;
  final DmeUser dmeUser;

  const DmeReminderDetailScreen({
    super.key,
    required this.reminder,
    required this.dmeUser,
  });

  @override
  State<DmeReminderDetailScreen> createState() => _DmeReminderDetailScreenState();
}

class _DmeReminderDetailScreenState extends State<DmeReminderDetailScreen> {
  late DmeReminderModel _reminder;
  final _notesController = TextEditingController();
  bool _updating = false;

  static const _blue = Color(0xFF005BAC);
  static const _green = Color(0xFF8CC63F);

  @override
  void initState() {
    super.initState();
    _reminder = widget.reminder;
    _notesController.text = _reminder.notes ?? '';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _makeCall() async {
    final phone = _reminder.customerPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _updating = true);
    final success = await DmeReminderService.instance.updateStatus(
      _reminder.id!,
      status,
      notes: _notesController.text,
    );
    if (mounted) {
      setState(() {
        _updating = false;
        if (success) {
          _reminder = _reminder.copyWith(
            status: status,
            notes: _notesController.text,
          );
        }
      });
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${status.toUpperCase()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder Detail'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2332) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isDark
                    ? null
                    : [
                        const BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _reminder.customerName ?? 'Unknown Customer',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(_reminder.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _reminder.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _getStatusColor(_reminder.status),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.phone_rounded, size: 18, color: _blue),
                      const SizedBox(width: 8),
                      Text(
                        _reminder.customerPhone ?? 'No Phone',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _makeCall,
                        icon: const Icon(Icons.call, size: 16),
                        label: const Text('Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_reminder.customerAddress != null &&
                      _reminder.customerAddress!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _reminder.customerAddress!,
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Date & Branch Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2332) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _infoRow('Last Purchase Date',
                      _formatDate(_reminder.lastPurchaseDate)),
                  const Divider(height: 24),
                  _infoRow('Reminder Date (28 days)',
                      _formatDate(_reminder.reminderDate)),
                  const Divider(height: 24),
                  _infoRow('Branch', _reminder.purchasedForBranchName),
                  if (_reminder.salesman != null) ...[
                    const Divider(height: 24),
                    _infoRow('Salesman', _reminder.salesman!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Notes Section
            Text(
              'Call Notes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter notes about the customer call...',
                filled: true,
                fillColor: isDark ? const Color(0xFF1A2332) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status Actions
            Text(
              'Update Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            if (_updating)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      'Call Again',
                      Colors.orange,
                      () => _updateStatus('call_again'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      'Completed',
                      _green,
                      () => _updateStatus('completed'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      'Dismiss',
                      Colors.grey,
                      () => _updateStatus('dismissed'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return _green;
      case 'call_again':
        return Colors.orange;
      case 'dismissed':
        return Colors.grey;
      default:
        return _blue;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
