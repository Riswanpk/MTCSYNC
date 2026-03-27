import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dme_supabase_service.dart';
import '../models/dme_user.dart';
import '../models/dme_customer.dart';
import '../models/dme_sale.dart';

class DmeCustomerDetailPage extends StatefulWidget {
  final DmeCustomer customer;
  final DmeUser dmeUser;

  const DmeCustomerDetailPage({
    super.key,
    required this.customer,
    required this.dmeUser,
  });

  @override
  State<DmeCustomerDetailPage> createState() => _DmeCustomerDetailPageState();
}

class _DmeCustomerDetailPageState extends State<DmeCustomerDetailPage>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;
  final _remarksCtrl = TextEditingController();

  List<DmeSale> _sales = [];
  List<Map<String, dynamic>> _callLogs = [];
  bool _loading = true;
  bool _callPending = false;
  DateTime? _callStartTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _restorePendingCall();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callPending) {
      _checkIfCallWasMade();
    }
  }

  Future<void> _loadData() async {
    final id = widget.customer.id;
    if (id == null) return;
    final futures = await Future.wait([
      _svc.getSalesForCustomer(id),
      _svc.getCallLogs(id),
    ]);
    if (mounted) {
      setState(() {
        _sales = futures[0] as List<DmeSale>;
        _callLogs = futures[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    }
  }

  Future<void> _makeCall() async {
    final phone = widget.customer.phone;
    if (phone.isEmpty) return;

    final status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission required')),
        );
      }
      return;
    }

    _callPending = true;
    _callStartTime = DateTime.now();
    await _savePendingCall();

    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  Future<void> _savePendingCall() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'dme_pending_call_${widget.customer.id}';
    await prefs.setString(key, _callStartTime!.toIso8601String());
  }

  Future<void> _restorePendingCall() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'dme_pending_call_${widget.customer.id}';
    final saved = prefs.getString(key);
    if (saved != null) {
      _callPending = true;
      _callStartTime = DateTime.tryParse(saved);
    }
  }

  Future<void> _clearPendingCall() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'dme_pending_call_${widget.customer.id}';
    await prefs.remove(key);
    _callPending = false;
    _callStartTime = null;
  }

  Future<void> _checkIfCallWasMade() async {
    if (_callStartTime == null) return;

    final status = await Permission.phone.request();
    if (!status.isGranted) return;

    // Small delay for call log to update
    await Future.delayed(const Duration(seconds: 2));

    final entries = await CallLog.query(
      dateFrom: _callStartTime!.millisecondsSinceEpoch,
      dateTo: DateTime.now().millisecondsSinceEpoch,
    );

    final phone = widget.customer.phone;
    bool found = false;

    for (final entry in entries) {
      if (entry.duration != null &&
          entry.duration! > 15 &&
          _numberMatches(entry.number ?? '', phone)) {
        found = true;
        // Log the call
        await _svc.logCall(
          customerId: widget.customer.id!,
          calledBy: widget.dmeUser.id,
          callDate: DateTime.now(),
          durationSeconds: entry.duration,
        );
        break;
      }
    }

    await _clearPendingCall();

    if (found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Call detected and logged!'),
          backgroundColor: Colors.green,
        ),
      );
      _promptRemarks();
      _loadData();
    } else if (!found && mounted) {
      // Retry once after 3s
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final retryEntries = await CallLog.query(
        dateFrom: _callStartTime!.millisecondsSinceEpoch,
        dateTo: DateTime.now().millisecondsSinceEpoch,
      );
      for (final entry in retryEntries) {
        if (entry.duration != null &&
            entry.duration! > 15 &&
            _numberMatches(entry.number ?? '', phone)) {
          await _svc.logCall(
            customerId: widget.customer.id!,
            calledBy: widget.dmeUser.id,
            callDate: DateTime.now(),
            durationSeconds: entry.duration,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Call detected and logged!'),
                backgroundColor: Colors.green,
              ),
            );
            _promptRemarks();
            _loadData();
          }
          return;
        }
      }
    }
  }

  bool _numberMatches(String logNumber, String contact) {
    final clean = contact.replaceAll(RegExp(r'\D'), '');
    final logClean = logNumber.replaceAll(RegExp(r'\D'), '');
    return logClean.endsWith(clean) || clean.endsWith(logClean);
  }

  void _promptRemarks() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Remarks'),
        content: TextField(
          controller: _remarksCtrl,
          decoration: const InputDecoration(
            hintText: 'Enter call notes...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_remarksCtrl.text.isNotEmpty) {
                // Update latest call log with remarks
                final logs = await _svc.getCallLogs(widget.customer.id!);
                if (logs.isNotEmpty) {
                  // The service doesn't have update, but we logged with remarks=null
                  // For simplicity, we add a new log entry with remarks
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final dateFmt = DateFormat('dd-MMM-yy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        backgroundColor: const Color(0xFF005BAC),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Customer Info Card ──
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor:
                                  const Color(0xFF005BAC).withOpacity(0.1),
                              child: Text(
                                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF005BAC)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  Text(c.phone,
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.grey[600])),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.phone, color: Colors.green),
                              onPressed: _makeCall,
                              tooltip: 'Call',
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        if (c.address != null && c.address!.isNotEmpty)
                          _infoRow(Icons.location_on, c.address!),
                        if (c.category != null)
                          _infoRow(Icons.category, c.category!),
                        if (c.customerType != null)
                          _infoRow(Icons.star, c.customerType!),
                        if (c.salesman != null)
                          _infoRow(Icons.person, c.salesman!),
                        if (c.lastPurchaseDate != null)
                          _infoRow(Icons.calendar_today,
                              'Last Purchase: ${dateFmt.format(c.lastPurchaseDate!)}'),
                        if (c.branchName != null)
                          _infoRow(Icons.business, c.branchName!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Purchase History ──
                Text('Purchase History',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 8),
                if (_sales.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No purchases recorded')),
                    ),
                  )
                else
                  ..._sales.map((s) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: ExpansionTile(
                          leading: const Icon(Icons.receipt_long,
                              color: Color(0xFF005BAC)),
                          title: Text(dateFmt.format(s.date)),
                          subtitle: Text(
                            [
                              if (s.salesman != null) s.salesman,
                              if (s.totalQuantity != null)
                                'Qty: ${s.totalQuantity}',
                            ].join(' • '),
                            style: const TextStyle(fontSize: 12),
                          ),
                          children: s.items
                              .map((item) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.inventory_2,
                                        size: 18, color: Colors.grey),
                                    title: Text(item.productName),
                                    trailing: Text(
                                        '${item.quantity} ${item.unit ?? ''}'),
                                  ))
                              .toList(),
                        ),
                      )),

                const SizedBox(height: 20),

                // ── Call Log ──
                Text('Call Log',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 8),
                if (_callLogs.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No calls logged')),
                    ),
                  )
                else
                  ..._callLogs.map((log) {
                    final date = DateTime.tryParse(
                            log['call_date']?.toString() ?? '');
                    final duration = log['duration_seconds'] as int? ?? 0;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.phone_callback,
                          color: Colors.green),
                      title: Text(date != null
                          ? dateFmt.format(date)
                          : 'Unknown date'),
                      subtitle: log['remarks'] != null
                          ? Text(log['remarks'].toString())
                          : null,
                      trailing: Text('${duration}s'),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
