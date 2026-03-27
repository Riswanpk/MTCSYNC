import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dme_reminder.dart';
import '../models/dme_user.dart';
import '../services/dme_supabase_service.dart';

class DmeCustomerTileViewer extends StatefulWidget {
  final DmeReminder reminder;
  final DmeUser dmeUser;

  const DmeCustomerTileViewer({
    super.key,
    required this.reminder,
    required this.dmeUser,
  });

  @override
  State<DmeCustomerTileViewer> createState() => _DmeCustomerTileViewerState();
}

class _DmeCustomerTileViewerState extends State<DmeCustomerTileViewer>
    with WidgetsBindingObserver {
  final _svc = DmeSupabaseService.instance;
  final _remarksCtrl = TextEditingController();

  bool _called = false;
  bool _remarksSaved = false;
  bool _saving = false;
  String? _pendingCallPhone;
  DateTime? _callStartTime;
  int? _detectedDuration;
  List<Map<String, dynamic>> _callHistory = [];
  bool _loadingHistory = true;

  // colours
  static const _blue = Color(0xFF005BAC);
  static const _green = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remarksCtrl.addListener(() => setState(() => _remarksSaved = false));
    _restorePendingCallState();
    _checkForAnyRecentCall();
    _loadCallHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingCallPhone != null) {
        _checkIfCallWasMade().then((_) {
          if (!_called && _pendingCallPhone != null && mounted) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && !_called) _checkIfCallWasMade();
            });
          }
        });
      } else if (!_called) {
        _checkForAnyRecentCall();
      }
    }
  }

  // ── SharedPreferences helpers ─────────────────────────────────

  String get _prefKey =>
      'dme_tv_${widget.reminder.customerId}_${widget.reminder.id}';

  Future<void> _savePendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefKey}_phone', _pendingCallPhone ?? '');
    await prefs.setInt(
        '${_prefKey}_time', _callStartTime?.millisecondsSinceEpoch ?? 0);
  }

  Future<void> _clearPendingCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_prefKey}_phone');
    await prefs.remove('${_prefKey}_time');
    _pendingCallPhone = null;
    _callStartTime = null;
  }

  Future<void> _restorePendingCallState() async {
    if (_called) return;
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('${_prefKey}_phone');
    final time = prefs.getInt('${_prefKey}_time');
    if (phone != null && phone.isNotEmpty && time != null && time > 0) {
      _pendingCallPhone = phone;
      _callStartTime = DateTime.fromMillisecondsSinceEpoch(time);
      _checkIfCallWasMade();
    }
  }

  // ── Call helpers ──────────────────────────────────────────────

  bool _numberMatches(String logNumber, String contact) {
    final clean = contact.replaceAll(RegExp(r'\D'), '');
    final logClean = logNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.isEmpty || logClean.isEmpty) return false;
    return logClean.endsWith(clean) || clean.endsWith(logClean);
  }

  Future<void> _makeCall() async {
    final phone = widget.reminder.customerPhone;
    if (phone == null || phone.isEmpty) return;

    final status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone permission denied')),
        );
      }
      return;
    }

    _pendingCallPhone = phone;
    _callStartTime = DateTime.now();
    await _savePendingCallState();

    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _checkIfCallWasMade() async {
    if (_callStartTime == null || _pendingCallPhone == null) return;
    try {
      final entries = await CallLog.query(
        dateFrom: _callStartTime!.millisecondsSinceEpoch,
        dateTo: DateTime.now().millisecondsSinceEpoch,
      );

      for (final entry in entries) {
        if ((entry.duration ?? 0) > 15 &&
            _numberMatches(entry.number ?? '', _pendingCallPhone!)) {
          if (mounted) setState(() {
            _called = true;
            _detectedDuration = entry.duration;
          });
          await _clearPendingCallState();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Call detected! Please add remarks.'),
              backgroundColor: Colors.green,
            ));
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('checkIfCallWasMade error: $e');
    }
  }

  /// On page open, scan today's log: requires an outgoing call + any >15s call
  /// after it (mirrors SalesCustomerTileViewer logic).
  Future<void> _checkForAnyRecentCall() async {
    if (_called) return;
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final entries = await CallLog.query(
        dateFrom: startOfDay.millisecondsSinceEpoch,
        dateTo: now.millisecondsSinceEpoch,
      );
      final phone = widget.reminder.customerPhone;
      if (phone == null || phone.isEmpty) return;

      // Step 1: latest outgoing call to this customer today
      int latestOutgoingTime = -1;
      int? latestDuration;
      for (final entry in entries) {
        if (entry.callType != CallType.outgoing) continue;
        final num = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        if (num.isEmpty) continue;
        if (_numberMatches(num, phone)) {
          if (entry.timestamp != null && entry.timestamp! > latestOutgoingTime) {
            latestOutgoingTime = entry.timestamp!;
            latestDuration = entry.duration;
          }
        }
      }
      if (latestOutgoingTime == -1) return;

      // Step 2: any call (in or out) > 15s after that outgoing call
      bool hasLongCall = entries.any((entry) {
        if (entry.timestamp == null || entry.timestamp! <= latestOutgoingTime) {
          return false;
        }
        final num = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        return _numberMatches(num, phone) && (entry.duration ?? 0) > 15;
      });

      // Also accept if the outgoing call itself was >15s
      if (!hasLongCall && (latestDuration ?? 0) > 15) hasLongCall = true;

      if (hasLongCall && mounted) {
        setState(() { _called = true; _detectedDuration = latestDuration; });
        await _clearPendingCallState();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Call detected! Please add remarks.'),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      debugPrint('checkForAnyRecentCall error: $e');
    }
  }

  Future<void> _reloadCallStatus() async {
    if (_called) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call already marked.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning call log…')),
      );
    }
    await _checkForAnyRecentCall();
    if (!_called && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No qualifying call found yet.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ── Supabase ──────────────────────────────────────────────────

  Future<void> _loadCallHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final logs = await _svc.getCallLogs(widget.reminder.customerId);
      if (mounted) setState(() { _callHistory = logs; _loadingHistory = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _saveRemarks() async {
    final remarks = _remarksCtrl.text.trim();
    if (remarks.isEmpty || !_called) return;
    setState(() => _saving = true);
    try {
      await _svc.logCall(
        customerId: widget.reminder.customerId,
        calledBy: widget.dmeUser.id,
        callDate: DateTime.now(),
        durationSeconds: _detectedDuration,
        remarks: remarks,
      );
      if (widget.reminder.id != null) {
        await _svc.updateReminderStatus(
          widget.reminder.id!,
          'completed',
          notes: remarks,
        );
      }
      await _loadCallHistory();
      if (mounted) {
        setState(() { _remarksSaved = true; _saving = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Remarks saved & reminder marked complete ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── UI helpers ────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (_called && _remarksCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add remarks before leaving.'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
    return true;
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _blue.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      letterSpacing: 0.4,
                    )),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final primaryColor = _called ? _green : _blue;
    final dateFmt = DateFormat('dd MMM yyyy');
    final callFmt = DateFormat('dd-MMM-yy');
    final remarksEntered = _remarksCtrl.text.trim().isNotEmpty;

    return PopScope(
      canPop: !(_called && _remarksCtrl.text.trim().isEmpty),
      onPopInvoked: (didPop) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer Details',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload Call Status',
              onPressed: _reloadCallStatus,
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header gradient ──────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [primaryColor, primaryColor.withOpacity(0.8)],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _called ? Icons.check_circle : Icons.person,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      r.customerName ?? 'Customer #${r.customerId}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (r.customerPhone != null && r.customerPhone!.isNotEmpty)
                      _called
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.phone, color: primaryColor),
                                  const SizedBox(width: 8),
                                  Text('Call Completed',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      )),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTap: _makeCall,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.phone, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text('Make Call',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15)),
                                  ],
                                ),
                              ),
                            ),
                  ],
                ),
              ),

              // ── Status card ──────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _called
                      ? _green.withOpacity(0.08)
                      : Colors.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _called ? _green : Colors.orange,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _called ? Icons.check_circle : Icons.pending,
                      color: _called ? _green : Colors.orange,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _called ? 'Call Completed' : 'Call Pending',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _called ? _green : Colors.orange[700],
                            ),
                          ),
                          Text(
                            _called
                                ? 'Add remarks and save below'
                                : 'Tap the button above to call',
                            style: TextStyle(
                              fontSize: 13,
                              color: _called ? _green : Colors.orange[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Customer details ─────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Customer Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )),
              ),
              _detailRow(Icons.phone, 'Phone', r.customerPhone),
              _detailRow(Icons.location_on, 'Address', r.customerAddress),
              _detailRow(
                Icons.calendar_today,
                'Reminder Date',
                dateFmt.format(r.reminderDate),
              ),
              _detailRow(
                Icons.shopping_cart,
                'Last Purchase',
                dateFmt.format(r.lastPurchaseDate),
              ),

              // ── Past call remarks ────────────────────────────────
              const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Call History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )),
              ),
              if (_loadingHistory)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else if (_callHistory.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text('No previous calls recorded.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                )
              else
                ..._callHistory.map((log) {
                  final callDate = log['call_date'] != null
                      ? callFmt.format(
                          DateTime.tryParse(log['call_date'].toString()) ??
                              DateTime.now())
                      : '—';
                  final remarks =
                      (log['remarks'] as String?)?.trim() ?? '';
                  return Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 5),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _blue.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.call_made,
                                size: 14, color: Color(0xFF005BAC)),
                            const SizedBox(width: 6),
                            Text(callDate,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Color(0xFF005BAC))),
                          ],
                        ),
                        if (remarks.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(remarks,
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ],
                    ),
                  );
                }),

              // ── Remarks input ────────────────────────────────────
              const SizedBox(height: 8),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Remarks',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    )),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _remarksCtrl,
                  enabled: _called,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: _called
                        ? 'Enter call remarks…'
                        : 'Complete the call first to add remarks',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),

              // ── Save button ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: ElevatedButton.icon(
                  onPressed: (_called && remarksEntered && !_saving)
                      ? _saveRemarks
                      : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: const Text('Save Remarks',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[400],
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
