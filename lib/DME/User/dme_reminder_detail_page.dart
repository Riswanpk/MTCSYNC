import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_whatsapp_proof_page.dart';
import 'dme_assignment_service.dart';

class DmeReminderDetailPage extends StatefulWidget {
  final Map<String, dynamic> reminder;
  final VoidCallback? onUpdated;

  const DmeReminderDetailPage({
    super.key,
    required this.reminder,
    this.onUpdated,
  });

  @override
  State<DmeReminderDetailPage> createState() => _DmeReminderDetailPageState();
}

class _DmeReminderDetailPageState extends State<DmeReminderDetailPage> with WidgetsBindingObserver {
  late Map<String, dynamic> _reminder;
  late TextEditingController _remarksController;
  bool _isSaving = false;
  bool _callMade = false;
  DateTime? _callInitiatedTime;

  int? _callDuration;
  DateTime? _calledTimestamp;
  bool _canReschedule = false;

  List<Map<String, dynamic>> _salesHistory = [];
  bool _isLoadingHistory = false;
  List<Map<String, dynamic>> _callHistory = [];
  bool _isLoadingCallHistory = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminder = Map<String, dynamic>.from(widget.reminder);
    _remarksController = TextEditingController(text: _reminder['remarks'] ?? '');
    final status = (_reminder['status'] ?? '').toString().toLowerCase();
    _callMade = (status == 'completed' || status == 'called');

    _callDuration = int.tryParse(_reminder['call_duration']?.toString() ?? '');
    final cTs = _reminder['called_timestamp']?.toString();
    _calledTimestamp = cTs != null ? DateTime.tryParse(cTs) : null;
    if (_callDuration != null && _callDuration! <= 10) {
      _canReschedule = true;
    }

    _fetchCustomerSalesHistory();
    _fetchCustomerCallHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callInitiatedTime != null && !_callMade) {
      _checkCallLogAfterCall();
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('dd-MM-yyyy').format(date);
    }
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd-MM-yyyy').format(parsed);
    }
    return str;
  }

  Future<void> _fetchCustomerSalesHistory() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    if (client == null || customerId == null) return;

    setState(() => _isLoadingHistory = true);
    try {
      final res = await client
          .from('dme_sales')
          .select('id, date, purchased_branch, salesman, category_id, customer_type_id, dme_sales_detail(products)')
          .eq('customer_id', customerId)
          .order('date', ascending: false)
          .limit(10);

      if (mounted) {
        setState(() {
          _salesHistory = List<Map<String, dynamic>>.from(res);
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sales history: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _fetchCustomerCallHistory() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    final currentReminderId = _reminder['id'];
    if (client == null || customerId == null) return;

    setState(() => _isLoadingCallHistory = true);
    try {
      dynamic res;
      try {
        res = await client
            .from('dme_reminders')
            .select('id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, called_by, updated_at')
            .eq('customer_id', customerId)
            .inFilter('status', ['completed', 'called'])
            .order('updated_at', ascending: false)
            .limit(10);
      } catch (_) {
        // Fallback if called_by column not in DB yet
        res = await client
            .from('dme_reminders')
            .select('id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, updated_at')
            .eq('customer_id', customerId)
            .inFilter('status', ['completed', 'called'])
            .order('updated_at', ascending: false)
            .limit(10);
      }

      final List<Map<String, dynamic>> list = [];
      for (var item in (res as List)) {
        if (item['id'] != currentReminderId) {
          list.add(Map<String, dynamic>.from(item));
        }
      }

      if (mounted) {
        setState(() {
          _callHistory = list;
          _isLoadingCallHistory = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching call history: $e');
      if (mounted) setState(() => _isLoadingCallHistory = false);
    }
  }

  bool _numberMatches(String logNumber, String? contact) {
    if (contact == null || contact.isEmpty) return false;
    String clean = contact.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty) return false;
    return logNumber.endsWith(clean) || clean.endsWith(logNumber);
  }

  Future<void> _makePhoneCall() async {
    final phone = _reminder['customer_phone']?.toString().trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available for this customer')),
      );
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      _callInitiatedTime = DateTime.now().subtract(const Duration(seconds: 10));
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer')),
        );
      }
    }
  }

  Future<void> _sendWhatsAppMessage() async {
    final phone = _reminder['customer_phone']?.toString().trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available for this customer')),
      );
      return;
    }

    // Clean phone number: remove non-digits
    String cleanDigits = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanDigits.length == 10) {
      cleanDigits = '91$cleanDigits'; // Default country code if 10 digits
    }

    final whatsappUri = Uri.parse('https://wa.me/$cleanDigits');
    if (await canLaunchUrl(whatsappUri)) {
      await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
    }

    if (!mounted) return;

    // Navigate to WhatsApp Proof Upload Page
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeWhatsAppProofPage(
          reminder: _reminder,
          onVerified: widget.onUpdated,
        ),
      ),
    );

    if (res == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _checkCallLogAfterCall() async {
    final permStatus = await Permission.phone.request();
    if (!permStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call log permission is required to verify calls.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );

      final contact = _reminder['customer_phone']?.toString() ?? '';

      final matchingEntries = entries.where((entry) {
        String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (logNumber.isEmpty) return false;
        return _numberMatches(logNumber, contact);
      }).toList()
        ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

      int duration = 0;
      DateTime calledTime = now;
      bool callFound = false;

      if (matchingEntries.isNotEmpty) {
        final entry = matchingEntries.first;
        callFound = true;
        duration = entry.duration ?? 0;
        if (entry.timestamp != null && entry.timestamp! > 0) {
          calledTime = DateTime.fromMillisecondsSinceEpoch(entry.timestamp!);
        }
      } else if (_callInitiatedTime != null) {
        // Dialer opened but no logged outgoing call found or instantaneous disconnect
        callFound = true;
        duration = 0;
        calledTime = _callInitiatedTime!;
      }

      if (callFound) {
        if (mounted) {
          setState(() {
            _callDuration = duration;
            _calledTimestamp = calledTime;
            _callMade = true;
            _canReschedule = duration <= 10;
          });

          if (duration <= 10) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  duration == 0
                      ? 'Call not picked up. "Schedule for Tomorrow/Monday" is now enabled.'
                      : 'Call lasted $duration sec (<= 10s). You can reschedule or complete with remarks.',
                ),
                backgroundColor: Colors.orange[800],
                duration: const Duration(seconds: 4),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Call detected ($duration sec)! Please add remarks.'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No outgoing call found today for this contact.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error reloading call status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking call log: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rescheduleForTomorrow() async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    setState(() => _isSaving = true);
    try {
      final reminderId = _reminder['id'];
      final targetDate = DmeAssignmentService.getNextWorkingDate();
      final targetDateStr = DateFormat('yyyy-MM-dd').format(targetDate);
      final formattedDisplay = DateFormat('dd-MM-yyyy (EEE)').format(targetDate);

      final userRemarks = _remarksController.text.trim();
      final dur = _callDuration ?? 0;
      final defaultRemark = dur == 0
          ? 'Call not picked up - Rescheduled for $formattedDisplay'
          : 'Call under 10s (${dur}s) - Rescheduled for $formattedDisplay';
      final finalRemarks = userRemarks.isNotEmpty ? userRemarks : defaultRemark;
      final userEmail = FirebaseAuth.instance.currentUser?.email;

      final updatePayload = <String, dynamic>{
        'reminder_date': targetDateStr,
        'status': 'pending',
        'remarks': finalRemarks,
        'call_duration': dur,
        'called_timestamp': (_calledTimestamp ?? DateTime.now()).toIso8601String(),
        'assigned_to': null,
        'assigned_date': null,
        'is_overdue_leftover': false,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (userEmail != null && userEmail.isNotEmpty) {
        updatePayload['called_by'] = userEmail;
      }

      try {
        await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
      } catch (err) {
        // Fallback if called_by column has not been added to Supabase table yet
        if (err.toString().contains('called_by')) {
          updatePayload.remove('called_by');
          await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
        } else {
          rethrow;
        }
      }

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Call rescheduled for $formattedDisplay'),
            backgroundColor: Colors.blue[700],
          ),
        );
        widget.onUpdated?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rescheduling reminder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveAndMarkCompleted() async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    final remarks = _remarksController.text.trim();
    if (remarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter call remarks before saving.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final reminderId = _reminder['id'];
      final userEmail = FirebaseAuth.instance.currentUser?.email;

      // Mark current reminder as completed with call duration, timestamp, and called_by email
      final updatePayload = <String, dynamic>{
        'status': 'completed',
        'remarks': remarks,
        'call_duration': _callDuration,
        'called_timestamp': (_calledTimestamp ?? DateTime.now()).toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (userEmail != null && userEmail.isNotEmpty) {
        updatePayload['called_by'] = userEmail;
      }

      try {
        await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
      } catch (err) {
        // Fallback if called_by column has not been added to Supabase table yet
        if (err.toString().contains('called_by')) {
          updatePayload.remove('called_by');
          await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
        } else {
          rethrow;
        }
      }

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call remarks saved and reminder marked completed!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onUpdated?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving reminder: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final customerName = _reminder['customer_name'] ?? 'Unnamed Customer';
    final customerPhone = _reminder['customer_phone'] ?? 'N/A';
    final customerAddress = _reminder['customer_address'] ?? '';
    final salesman = _reminder['customer_salesman'] ?? '';
    final branchName = _reminder['branch_name'] ?? 'Branch';
    final reminderDateStr = _reminder['reminder_date']?.toString();
    final lastPurchaseDateStr = _reminder['last_purchase_date']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder Details'),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Check Call Logs / Reload',
            onPressed: () {
              _checkCallLogAfterCall();
            },
          ),
          if (_callDuration != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_callDuration}s',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _callMade
                  ? (_canReschedule ? Colors.orange[800] : Colors.green)
                  : Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _callMade
                  ? (_canReschedule ? 'CALL <= 10S' : 'CALL VERIFIED')
                  : 'CALL PENDING',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Customer Information Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF005BAC).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF005BAC),
                          child: const Icon(Icons.person, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customerName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      branchName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF005BAC),
                                      ),
                                    ),
                                  ),
                                  if (salesman.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text('Salesman: $salesman', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text('Phone: $customerPhone', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    if (customerAddress.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(customerAddress, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Due Date: ${_formatDate(reminderDateStr)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF005BAC))),
                        Text('Last Purchase: ${_formatDate(lastPurchaseDateStr)}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      ],
                    ),
                    if (_reminder['called_by'] != null && _reminder['called_by'].toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person_pin_rounded, size: 16, color: Colors.green),
                          const SizedBox(width: 6),
                          Text(
                            'Called by: ${_reminder['called_by']}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Recent Purchase History (PLACED ABOVE CALL BUTTON)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 20, color: Color(0xFF005BAC)),
                        const SizedBox(width: 8),
                        Text('Purchase History', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_isLoadingHistory)
                      const Center(child: Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator()))
                    else if (_salesHistory.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Center(child: Text('No previous sales found.', style: TextStyle(color: Colors.grey[600], fontSize: 13))),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _salesHistory.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (context, idx) {
                          final s = _salesHistory[idx];
                          final dateStr = s['date']?.toString();
                          final bName = DmeConstants.getBranchName(s['purchased_branch'] as int?);
                          final catName = DmeConstants.getCategoryName(s['category_id'] as int?);
                          final details = s['dme_sales_detail'] as List?;
                          final products = (details != null && details.isNotEmpty) ? details[0]['products'] as List? : null;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDate(dateStr),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    '$bName • $catName',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              if (products != null && products.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: products.map((p) {
                                    final item = p['item_name'] ?? '';
                                    final qty = p['qty'] ?? '';
                                    return Chip(
                                      label: Text('$item ($qty)', style: const TextStyle(fontSize: 11)),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2.5 Previous Call History (if any)
            if (_isLoadingCallHistory)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            else if (_callHistory.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.history_edu_rounded, size: 20, color: Color(0xFF005BAC)),
                          const SizedBox(width: 8),
                          Text('Previous Call History (${_callHistory.length})',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _callHistory.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (context, idx) {
                          final h = _callHistory[idx];
                          final calledTs = h['called_timestamp'] ?? h['updated_at'];
                          final dur = h['call_duration'] as int?;
                          final remRemarks = h['remarks']?.toString() ?? '';
                          final bId = h['last_purchase_branch'] as int?;
                          final bName = DmeConstants.getBranchName(bId);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDate(calledTs),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Row(
                                    children: [
                                      if (dur != null && dur > 0) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${dur}s',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          bName,
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (remRemarks.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  remRemarks,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: isDark ? Colors.white70 : Colors.grey[800],
                                  ),
                                ),
                              ],
                              if (h['called_by'] != null && h['called_by'].toString().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline_rounded, size: 12, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Called by: ${h['called_by']}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 3. Call and WhatsApp Action Buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _makePhoneCall,
                icon: const Icon(Icons.call, size: 22),
                label: Text('Call $customerPhone'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8CC63F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Send WhatsApp Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sendWhatsAppMessage,
                icon: const Icon(Icons.chat_rounded, size: 22),
                label: const Text('Send WhatsApp Message & Upload Proof'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 4. Call Remarks Section (Only accessible when _callMade is true)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _callMade ? Icons.check_circle : Icons.lock_outline_rounded,
                          size: 20,
                          color: _callMade ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Call Remarks',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _callMade ? null : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!_callMade) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Make a call first using the Call button above to enter call remarks.',
                                style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _remarksController,
                      enabled: _callMade,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: _callMade
                            ? 'Enter discussion summary, customer feedback, etc...'
                            : 'Disabled until call is made...',
                        filled: true,
                        fillColor: !_callMade
                            ? (isDark ? Colors.grey[850] : Colors.grey[200])
                            : (isDark ? Colors.grey[900] : Colors.grey[100]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_canReschedule) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded, color: Colors.orange, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _callDuration == 0 ? 'Call Not Picked Up' : 'Short Call Detected (${_callDuration}s)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Call was under 10 seconds. You can reschedule for tomorrow (or Monday if tomorrow is Sunday).',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey[800]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _rescheduleForTomorrow,
                          icon: const Icon(Icons.event_repeat_rounded, size: 20),
                          label: Text(
                            'Schedule for ${DateFormat('EEE, dd MMM').format(DmeAssignmentService.getNextWorkingDate())}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_isSaving || !_callMade) ? null : _saveAndMarkCompleted,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF005BAC),
                          disabledBackgroundColor: Colors.grey[400],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Save Remarks & Mark Completed', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
