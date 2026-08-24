import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:call_log/call_log.dart';
import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_whatsapp_proof_page.dart';

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

  List<Map<String, dynamic>> _salesHistory = [];
  bool _isLoadingHistory = false;

  SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminder = Map<String, dynamic>.from(widget.reminder);
    _remarksController = TextEditingController(text: _reminder['remarks'] ?? '');
    final status = (_reminder['status'] ?? '').toString().toLowerCase();
    _callMade = (status == 'completed' || status == 'called');

    _fetchCustomerSalesHistory();
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
    final client = _supabaseClient;
    final customerId = _reminder['customer_id'];
    if (client == null || !DmeConfig.isConfigured || customerId == null) return;

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
    if (_callMade) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call already marked & verified.'), backgroundColor: Colors.green),
      );
      return;
    }

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

      bool hasOutgoingLongCall = entries.any((entry) {
        if (entry.callType != CallType.outgoing) return false;
        String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (logNumber.isEmpty) return false;
        bool longEnough = (entry.duration ?? 0) > 10;
        return _numberMatches(logNumber, contact) && longEnough;
      });

      // Also check if any call exists to this number today
      bool hasAnyCall = entries.any((entry) {
        String logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (logNumber.isEmpty) return false;
        return _numberMatches(logNumber, contact);
      });

      if (hasOutgoingLongCall || hasAnyCall || _callInitiatedTime != null) {
        if (mounted) {
          setState(() {
            _callMade = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call detected! Please add remarks.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
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

  Future<void> _saveAndMarkCompleted() async {
    final client = _supabaseClient;
    if (client == null || !DmeConfig.isConfigured) return;

    final remarks = _remarksController.text.trim();
    if (remarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter call remarks before saving.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final reminderId = _reminder['id'];

      // 1. Mark current reminder as completed with remarks (No recurring reminder created)
      await client.from('dme_reminders').update({
        'status': 'completed',
        'remarks': remarks,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', reminderId);

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
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _callMade ? Colors.green : Colors.orange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _callMade ? 'CALL ACTIVE' : 'CALL PENDING',
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
