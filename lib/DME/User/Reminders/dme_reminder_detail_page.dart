import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../dme_constants.dart';
import '../../dme_config.dart';
import 'dme_whatsapp_proof_page.dart';
// ignore: unused_import
import '../dme_assignment_service.dart';
import 'dme_call_scanner_service.dart';
import '../../Complaints/Dme/dme_register_complaint_page.dart';
import '../Requests/dme_raise_request_page.dart';

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
  int _callAttempts = 0;
  int _todayCallAttempts = 0;
  DateTime? _lastCallAttemptTimestamp;
  Timer? _cooldownTimer;
  bool _isCheckingCall = false;

  bool _hasShortAttendedCall = false;

  bool _hasPendingRequest = false;
  String? _pendingRequestType;

  List<Map<String, dynamic>> _salesHistory = [];
  bool _isLoadingHistory = false;
  List<Map<String, dynamic>> _reminderCallLogs = [];
  bool _isLoadingReminderLogs = false;
  List<Map<String, dynamic>> _callHistory = [];
  bool _isLoadingCallHistory = false;
  List<Map<String, dynamic>> _customerBranches = [];
  bool _isPurchaseHistoryExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminder = Map<String, dynamic>.from(widget.reminder);
    _remarksController = TextEditingController(text: _reminder['remarks'] ?? '');
    final status = (_reminder['status'] ?? '').toString().toLowerCase();
    _callDuration = int.tryParse(_reminder['call_duration']?.toString() ?? '');
    final cTs = _reminder['called_timestamp']?.toString();
    _calledTimestamp = cTs != null ? DateTime.tryParse(cTs) : null;
    final isAlreadyCompleted = (status == 'completed');
    _callMade = isAlreadyCompleted || (_callDuration != null && _callDuration! > 10);
    _callAttempts = int.tryParse(_reminder['call_attempts']?.toString() ?? '') ?? 0;
    _hasShortAttendedCall = (_callDuration != null && _callDuration! > 0 && _callDuration! <= 10);

    // Daily call attempts & last attempt timestamp
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastCallDay = _reminder['last_call_day']?.toString();
    if (lastCallDay != null && lastCallDay == todayStr) {
      _todayCallAttempts = int.tryParse(_reminder['today_call_attempts']?.toString() ?? '') ?? 0;
    } else {
      _todayCallAttempts = 0;
    }
    final lTs = _reminder['last_call_attempt_timestamp']?.toString();
    _lastCallAttemptTimestamp = lTs != null ? DateTime.tryParse(lTs)?.toLocal() : null;

    // Ticking timer so the 1-hour countdown updates every 10 seconds
    _cooldownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });

    _loadUserNames();
    _fetchCustomerDetails();
    _fetchCustomerBranches();
    _fetchCustomerSalesHistory();
    _fetchCustomerCallHistory();
    _fetchReminderCallLogs();
    _checkCallLogHistoryAndCooldown();
    _checkIfShortAttendedCallExists();
    _checkPendingRequests();
  }

  Future<void> _fetchReminderCallLogs() async {
    final client = await DmeConfig.getClient();
    final remId = _reminder['id'];
    if (client == null || remId == null) return;
    setState(() => _isLoadingReminderLogs = true);
    try {
      final res = await client
          .from('dme_call_logs')
          .select('*')
          .eq('reminder_id', remId)
          .order('attempt_timestamp', ascending: false);
      if (mounted) {
        final list = List<Map<String, dynamic>>.from(res);
        DateTime? latestTs;
        for (final log in list) {
          final tStr = log['attempt_timestamp']?.toString();
          if (tStr != null) {
            final dt = DateTime.tryParse(tStr)?.toLocal();
            if (dt != null && (latestTs == null || dt.isAfter(latestTs))) {
              latestTs = dt;
            }
          }
        }
        setState(() {
          _reminderCallLogs = list;
          _isLoadingReminderLogs = false;
          if (latestTs != null) {
            if (_lastCallAttemptTimestamp == null || latestTs.isAfter(_lastCallAttemptTimestamp!)) {
              _lastCallAttemptTimestamp = latestTs;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching reminder call logs: $e');
      if (mounted) setState(() => _isLoadingReminderLogs = false);
    }
  }

  /// Checks call log history from both device and database, and verifies if 60 minutes have passed.
  Future<void> _checkCallLogHistoryAndCooldown() async {
    final contact = _reminder['customer_phone']?.toString().trim() ?? '';
    if (contact.isEmpty) return;

    try {
      final userEmail = FirebaseAuth.instance.currentUser?.email;
      final userUid = FirebaseAuth.instance.currentUser?.uid;

      final syncResult = await DmeCallScannerService.syncCallLogsForReminder(
        reminderId: _reminder['id'],
        customerId: _reminder['customer_id'],
        contactPhone: contact,
        callerEmail: userEmail,
        callerUid: userUid,
      );

      final now = DateTime.now();
      DateTime? latestCallTime;

      // 1. Check qualifying or latest entry from device call log
      final entry = syncResult.qualifyingEntry ?? syncResult.latestEntry;
      if (entry != null) {
        final entryTs = DmeCallScannerService.normalizeTimestamp(entry.timestamp);
        if (entryTs > 0) {
          latestCallTime = DateTime.fromMillisecondsSinceEpoch(entryTs);
        }
      }

      // 2. Check recorded logs from DB
      for (final log in syncResult.recordedLogs) {
        final tsStr = log['attempt_timestamp']?.toString();
        if (tsStr == null) continue;
        final dt = DateTime.tryParse(tsStr)?.toLocal();
        if (dt != null && (latestCallTime == null || dt.isAfter(latestCallTime))) {
          latestCallTime = dt;
        }
      }

      // 3. Compare with current _lastCallAttemptTimestamp
      if (_lastCallAttemptTimestamp != null) {
        final lTs = _lastCallAttemptTimestamp!.toLocal();
        if (latestCallTime == null || lTs.isAfter(latestCallTime)) {
          latestCallTime = lTs;
        }
      }

      if (latestCallTime != null && mounted) {
        final elapsed = now.difference(latestCallTime);
        final bool has60MinsPassed = elapsed.inSeconds >= 3600;

        setState(() {
          _lastCallAttemptTimestamp = latestCallTime;
          _reminderCallLogs = syncResult.recordedLogs;
          if (syncResult.totalTodayAttempts > 0) {
            _todayCallAttempts = syncResult.totalTodayAttempts;
          }
          final currentStatus = (_reminder['status'] ?? '').toString().toLowerCase();
          final bool isAlreadyCompleted = currentStatus == 'completed';
          if (!isAlreadyCompleted && (syncResult.hasAttendedCall || (entry?.duration ?? 0) > 10)) {
            _callMade = true;
            _reminder['status'] = 'called';
            _callDuration = entry?.duration;
          }
        });

        debugPrint('[Cooldown] Checked call log history. Latest call: $latestCallTime, elapsed: ${elapsed.inMinutes}m, 60m passed: $has60MinsPassed');
      }
    } catch (e) {
      debugPrint('[Cooldown] Error checking call log history: $e');
    }
  }

  Future<void> _checkIfShortAttendedCallExists() async {
    try {
      final client = await DmeConfig.getClient();
      final remId = _reminder['id'];
      if (client != null && remId != null) {
        final res = await client
            .from('dme_call_logs')
            .select('id')
            .eq('reminder_id', remId)
            .gt('ring_duration', 0)
            .lte('ring_duration', 10)
            .limit(1);
        if ((res as List).isNotEmpty && mounted) {
          setState(() {
            _hasShortAttendedCall = true;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkPendingRequests() async {
    try {
      final client = await DmeConfig.getClient();
      final remId = _reminder['id'];
      final custId = _reminder['customer_id'];
      if (client != null && (remId != null || custId != null)) {
        var query = client
            .from('dme_change_requests')
            .select('id, request_type, status, created_at')
            .eq('status', 'pending');

        if (remId != null && custId != null) {
          query = query.or('reminder_id.eq.$remId,customer_id.eq.$custId');
        } else if (remId != null) {
          query = query.eq('reminder_id', remId);
        } else if (custId != null) {
          query = query.eq('customer_id', custId);
        }

        final res = await query.order('created_at', ascending: false).limit(1);

        if (mounted) {
          if ((res as List).isNotEmpty) {
            final first = res.first;
            setState(() {
              _hasPendingRequest = true;
              _pendingRequestType = first['request_type']?.toString();
            });
          } else {
            setState(() {
              _hasPendingRequest = false;
              _pendingRequestType = null;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[DmeReminderDetail] Error checking pending requests: $e');
    }
  }

  final Map<String, String> _userNames = {};

  Future<void> _loadUserNames() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      for (var doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        final email = data['email']?.toString() ?? '';
        final username = data['username']?.toString() ??
            data['name']?.toString() ??
            (email.isNotEmpty ? email.split('@').first : 'User');
        _userNames[uid] = username;
        if (email.isNotEmpty) {
          _userNames[email] = username;
          _userNames[email.toLowerCase()] = username;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _fetchCustomerDetails() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    if (client == null || customerId == null) return;
    try {
      final res = await client
          .from('dme_customers')
          .select('phone, preference')
          .eq('id', customerId)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          if (res['phone'] != null) _reminder['customer_phone'] = res['phone'];
          _reminder['customer_preference'] = res['preference'] ?? 'Call';
        });
      }
    } catch (_) {}
  }

  Future<void> _openRaiseRequestPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmeRaiseRequestPage(reminder: _reminder),
      ),
    );

    if (result != null && result is Map && result['success'] == true) {
      final requestType = result['type'];
      setState(() {
        _hasPendingRequest = true;
        _pendingRequestType = requestType?.toString();
      });
      _checkPendingRequests();
      if (requestType == 'phone_number_change') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phone change request submitted! Reminder is locked until approved by Admin.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          widget.onUpdated?.call();
          Navigator.pop(context, true);
        }
      } else if (requestType == 'preference_change') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Preference change request submitted to DME Admin (New: ${result['new_value']})'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          _fetchCustomerDetails();
          widget.onUpdated?.call();
        }
      } else if (requestType == 'call_completion') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Call completion request submitted to Admin for approval!'),
              backgroundColor: Colors.purple,
              duration: Duration(seconds: 4),
            ),
          );
          widget.onUpdated?.call();
        }
      } else if (requestType == 'edit_customer_details') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Customer details update request submitted to Admin for approval!'),
              backgroundColor: Color(0xFF007A87),
              duration: Duration(seconds: 4),
            ),
          );
          _fetchCustomerDetails();
          _fetchCustomerBranches();
          widget.onUpdated?.call();
        }
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_callInitiatedTime != null) {
        _checkCallLogAfterCall();
      }
      _checkPendingRequests();
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

  String _formatDateTime(dynamic date) {
    if (date == null) return 'N/A';
    if (date is DateTime) {
      return DateFormat('dd-MM-yyyy hh:mm a').format(date);
    }
    final str = date.toString().trim();
    if (str.isEmpty) return 'N/A';
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd-MM-yyyy hh:mm a').format(parsed);
    }
    return str;
  }

  String _getUserDisplayName(dynamic userIdentifier) {
    if (userIdentifier == null) return '';
    final raw = userIdentifier.toString().trim();
    if (raw.isEmpty) return '';
    if (_userNames.containsKey(raw)) return _userNames[raw]!;
    if (_userNames.containsKey(raw.toLowerCase())) return _userNames[raw.toLowerCase()]!;
    if (raw.contains('@')) {
      final prefix = raw.split('@').first;
      if (prefix.isNotEmpty) {
        return prefix[0].toUpperCase() + prefix.substring(1);
      }
      return prefix;
    }
    return raw;
  }

  Future<void> _fetchCustomerBranches() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    if (client == null || customerId == null) return;

    try {
      final res = await client
          .from('dme_customer_branches')
          .select('branch_id, category_id, customer_type_id, created_at')
          .eq('customer_id', customerId);
      if (mounted) {
        setState(() {
          _customerBranches = List<Map<String, dynamic>>.from(res as List);
        });
      }
    } catch (e) {
      debugPrint('Error fetching customer branches: $e');
    }
  }

  Future<void> _fetchCustomerSalesHistory() async {
    final client = await DmeConfig.getClient();
    final customerId = _reminder['customer_id'];
    if (client == null || customerId == null) return;

    setState(() => _isLoadingHistory = true);
    try {
      List<Map<String, dynamic>> salesList = [];
      try {
        final res = await client
            .from('dme_sales')
            .select('id, date, purchased_branch, salesman, category_id, customer_type_id, dme_sales_detail(products)')
            .eq('customer_id', customerId)
            .order('date', ascending: false)
            .limit(10);
        salesList = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        // Fallback without relation join if foreign key not named
        final resFallback = await client
            .from('dme_sales')
            .select('id, date, purchased_branch, salesman, category_id, customer_type_id')
            .eq('customer_id', customerId)
            .order('date', ascending: false)
            .limit(10);
        salesList = List<Map<String, dynamic>>.from(resFallback);
      }

      // Check if any sale is missing dme_sales_detail or needs explicit detail fetch
      final saleIdsNeedingDetails = salesList.where((s) {
        final dt = s['dme_sales_detail'];
        if (dt == null) return true;
        if (dt is List && dt.isEmpty) return true;
        return false;
      }).map((s) => s['id']).where((id) => id != null).toList();

      if (saleIdsNeedingDetails.isNotEmpty) {
        try {
          final detailRows = await client
              .from('dme_sales_detail')
              .select('sale_id, products')
              .inFilter('sale_id', saleIdsNeedingDetails);

          final Map<dynamic, dynamic> detailMap = {};
          for (var r in (detailRows as List)) {
            final sId = r['sale_id'];
            if (sId != null) {
              detailMap[sId] = r['products'];
            }
          }

          for (var s in salesList) {
            final sId = s['id'];
            if (detailMap.containsKey(sId)) {
              s['dme_sales_detail'] = [
                {'products': detailMap[sId]}
              ];
            }
          }
        } catch (detailErr) {
          debugPrint('Error fetching dme_sales_detail fallback: $detailErr');
        }
      }

      if (mounted) {
        setState(() {
          _salesHistory = salesList;
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
    if (client == null || customerId == null) return;

    setState(() => _isLoadingCallHistory = true);
    try {
      final currentReminderId = _reminder['id'];
      final res = await client
          .from('dme_reminders')
          .select('id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, called_by, updated_at')
          .inFilter('status', ['completed', 'called'])
          .eq('customer_id', customerId)
          .neq('id', currentReminderId)
          .order('called_timestamp', ascending: false)
          .limit(10);

      final list = List<Map<String, dynamic>>.from(res);
      if (mounted) {
        setState(() {
          _callHistory = list;
          _isLoadingCallHistory = false;
        });
      }
    } catch (e) {
      try {
        // Fallback if called_by column not in DB yet
        final currentReminderId = _reminder['id'];
        final resFallback = await client
            .from('dme_reminders')
            .select('id, reminder_date, last_purchase_branch, status, remarks, call_duration, called_timestamp, updated_at')
            .inFilter('status', ['completed', 'called'])
            .eq('customer_id', customerId)
            .neq('id', currentReminderId)
            .order('called_timestamp', ascending: false)
            .limit(10);
        final list = List<Map<String, dynamic>>.from(resFallback);
        if (mounted) {
          setState(() {
            _callHistory = list;
            _isLoadingCallHistory = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingCallHistory = false);
      }
      debugPrint('Error fetching call history: $e');
      if (mounted) setState(() => _isLoadingCallHistory = false);
    }
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
      _callInitiatedTime = DateTime.now();
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer')),
        );
      }
    }
  }

  Future<void> _updateCallAttemptsInDb({
    required int totalAttempts,
    required int todayAttempts,
    required DateTime lastAttemptTimestamp,
  }) async {
    try {
      final client = await DmeConfig.getClient();
      final reminderId = _reminder['id'];
      final todayStr = DateFormat('yyyy-MM-dd').format(lastAttemptTimestamp);
      final userEmail = FirebaseAuth.instance.currentUser?.email;
      if (client != null && reminderId != null) {
        final updatePayload = <String, dynamic>{
          'call_attempts': totalAttempts,
          'today_call_attempts': todayAttempts,
          'last_call_attempt_timestamp': lastAttemptTimestamp.toUtc().toIso8601String(),
          'last_call_day': todayStr,
          if (userEmail != null && userEmail.isNotEmpty) 'called_by': userEmail,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
        try {
          await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
          widget.onUpdated?.call();
        } catch (_) {
          // Fallback if newer columns are not migrated yet
          try {
            updatePayload.remove('today_call_attempts');
            updatePayload.remove('last_call_attempt_timestamp');
            updatePayload.remove('last_call_day');
            await client.from('dme_reminders').update(updatePayload).eq('id', reminderId);
            widget.onUpdated?.call();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error updating call_attempts: $e');
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
    if (_isCheckingCall) return;
    setState(() => _isCheckingCall = true);

    try {
      // Small delay allows the Android dialer system service to flush call log
      await Future.delayed(const Duration(milliseconds: 1200));

      final contact = _reminder['customer_phone']?.toString() ?? '';
      final userEmail = FirebaseAuth.instance.currentUser?.email;
      final userUid = FirebaseAuth.instance.currentUser?.uid;

      final syncResult = await DmeCallScannerService.syncCallLogsForReminder(
        reminderId: _reminder['id'],
        customerId: _reminder['customer_id'],
        contactPhone: contact,
        callerEmail: userEmail,
        callerUid: userUid,
      );

      final wasInitiated = _callInitiatedTime != null;
      if (syncResult.latestEntry != null || syncResult.totalTodayAttempts > 0) {
        _callInitiatedTime = null; // Clear now that we matched
      }

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final lastCallDay = _reminder['last_call_day']?.toString();

      final bool hasCallsToday = syncResult.totalTodayAttempts > 0 || syncResult.recordedLogs.isNotEmpty;

      if (hasCallsToday) {
        // Calculate previous days' attempts vs today's attempts accurately
        final int previousDaysAttempts = (lastCallDay == todayStr)
            ? (_callAttempts - _todayCallAttempts).clamp(0, 9999)
            : _callAttempts;

        final int newTodayAttempts = syncResult.totalTodayAttempts;
        final bool isNewAttempt = syncResult.newAttemptsLogged > 0;

        _todayCallAttempts = newTodayAttempts;
        _callAttempts = previousDaysAttempts + _todayCallAttempts;

        final entry = syncResult.qualifyingEntry ?? syncResult.latestEntry;
        int duration = entry?.duration ?? _callDuration ?? 0;
        DateTime calledTime = now;
        final entryTs = DmeCallScannerService.normalizeTimestamp(entry?.timestamp);
        if (entryTs > 0) {
          calledTime = DateTime.fromMillisecondsSinceEpoch(entryTs);
        } else if (_lastCallAttemptTimestamp != null) {
          calledTime = _lastCallAttemptTimestamp!;
        }

        _lastCallAttemptTimestamp = calledTime;
        _reminder['call_attempts'] = _callAttempts;
        _reminder['today_call_attempts'] = _todayCallAttempts;
        _reminder['last_call_attempt_timestamp'] = calledTime.toIso8601String();
        _reminder['last_call_day'] = todayStr;
        if (userEmail != null && userEmail.isNotEmpty) {
          _reminder['called_by'] = userEmail;
        }

        _updateCallAttemptsInDb(
          totalAttempts: _callAttempts,
          todayAttempts: _todayCallAttempts,
          lastAttemptTimestamp: calledTime,
        );

        final bool isAlreadyCompleted = (_reminder['status'] ?? '').toString().toLowerCase() == 'completed';
        final bool isAttended = syncResult.hasAttendedCall || duration > 10;
        final bool isShortAttended = syncResult.hasShortCall || (duration > 0 && duration <= 10);

        if (mounted) {
          setState(() {
            _reminderCallLogs = syncResult.recordedLogs;
            _callDuration = duration;
            _calledTimestamp = calledTime;
            if (!isAlreadyCompleted) {
              _callMade = isAttended;
              _reminder['call_duration'] = duration;
              _reminder['called_timestamp'] = calledTime.toIso8601String();
              if (isShortAttended) {
                _hasShortAttendedCall = true;
              }
              if (isAttended) {
                _reminder['status'] = 'called';
              }
            }
            _isCheckingCall = false;
          });

          // Update Supabase with attempt count, duration, called_by, and status (skip status if completed)
          final client = await DmeConfig.getClient();
          final remId = _reminder['id'];
          if (client != null && remId != null && !isAlreadyCompleted) {
            final payload = <String, dynamic>{
              'call_attempts': _callAttempts,
              'today_call_attempts': _todayCallAttempts,
              'last_call_attempt_timestamp': calledTime.toUtc().toIso8601String(),
              'last_call_day': todayStr,
              if (userEmail != null && userEmail.isNotEmpty) 'called_by': userEmail,
              'updated_at': now.toUtc().toIso8601String(),
            };
            if (isAttended) {
              payload['call_duration'] = duration;
              payload['called_timestamp'] = calledTime.toIso8601String();
              payload['status'] = 'called';
            } else if (duration > 0) {
              payload['call_duration'] = duration;
              payload['called_timestamp'] = calledTime.toIso8601String();
            }

            try {
              await client.from('dme_reminders').update(payload).eq('id', remId);
              widget.onUpdated?.call();
            } catch (err) {
              if (err.toString().contains('called_by')) {
                payload.remove('called_by');
                await client.from('dme_reminders').update(payload).eq('id', remId);
                widget.onUpdated?.call();
              }
            }
          }

          // SnackBar feedback
          if (isNewAttempt) {
            if (isAttended) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Call attended ($duration sec)! Please add remarks below.'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else if (isShortAttended) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Call was under 10s (${duration}s). Customer attended briefly — WhatsApp messaging is now enabled!',
                  ),
                  backgroundColor: const Color(0xFF25D366),
                  duration: const Duration(seconds: 4),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Customer did not pick up (0s). Attempt $_todayCallAttempts/2 recorded for today.',
                  ),
                  backgroundColor: Colors.orange[900],
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          } else {
            // Already synced, no new attempt made
            if (isAttended) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Call log up to date. Call attended ($duration sec) — remarks enabled.'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Call log is already up to date ($_todayCallAttempts/2 attempt(s) recorded for today).'),
                  backgroundColor: const Color(0xFF005BAC),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          setState(() => _isCheckingCall = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                wasInitiated
                    ? 'Call not detected yet in Android call log. Tap "Check Call Log" if dialer finished writing.'
                    : 'No outgoing call log found for this customer today.',
              ),
              backgroundColor: Colors.orange[800],
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Recheck',
                textColor: Colors.white,
                onPressed: () {
                  _checkCallLogAfterCall();
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking call log: $e');
      if (mounted) {
        setState(() => _isCheckingCall = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking call log: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveAndMarkCompleted() async {
    final client = await DmeConfig.getClient();
    if (client == null) return;

    if (!_callMade || _callDuration == null || _callDuration! <= 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _callDuration == null || _callDuration == 0
                ? 'Cannot complete reminder: Call was not attended. Please call customer first.'
                : 'Cannot complete reminder: Call must be above 10 seconds to enter remarks (${_callDuration}s recorded).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
    final status = (_reminder['status'] ?? '').toString().toLowerCase();
    final bool isCompleted = (status == 'completed');
    final bool isCalledWithoutRemarks = (status == 'called' || _callMade) && !isCompleted;

    // Resolve Customer Type and Category:
    // 1. Try from reminder's branch in _customerBranches
    // 2. Or first record in _customerBranches
    // 3. Or from most recent sales record
    // 4. Or direct reminder attributes if available
    int? resolvedTypeId;
    int? resolvedCatId;

    final currentBranchId = _reminder['last_purchase_branch'] != null
        ? int.tryParse(_reminder['last_purchase_branch'].toString())
        : (_reminder['branch_id'] != null ? int.tryParse(_reminder['branch_id'].toString()) : null);

    if (_customerBranches.isNotEmpty) {
      final match = _customerBranches.firstWhere(
        (b) => currentBranchId != null && int.tryParse(b['branch_id']?.toString() ?? '') == currentBranchId,
        orElse: () => _customerBranches.first,
      );
      resolvedTypeId = int.tryParse(match['customer_type_id']?.toString() ?? '');
      resolvedCatId = int.tryParse(match['category_id']?.toString() ?? '');
    }

    if (resolvedTypeId == null && _salesHistory.isNotEmpty) {
      final saleMatch = _salesHistory.firstWhere(
        (s) => s['customer_type_id'] != null,
        orElse: () => _salesHistory.first,
      );
      resolvedTypeId = int.tryParse(saleMatch['customer_type_id']?.toString() ?? '');
    }

    if (resolvedCatId == null && _salesHistory.isNotEmpty) {
      final saleMatch = _salesHistory.firstWhere(
        (s) => s['category_id'] != null,
        orElse: () => _salesHistory.first,
      );
      resolvedCatId = int.tryParse(saleMatch['category_id']?.toString() ?? '');
    }

    resolvedTypeId ??= int.tryParse(_reminder['customer_type_id']?.toString() ?? '');
    resolvedCatId ??= int.tryParse(_reminder['category_id']?.toString() ?? '');

    // Check if customer is marked PREMIUM across any branch or sales
    final bool hasPremiumBranch = _customerBranches.any((b) => int.tryParse(b['customer_type_id']?.toString() ?? '') == 1);
    final bool hasPremiumSale = _salesHistory.any((s) => int.tryParse(s['customer_type_id']?.toString() ?? '') == 1);
    final bool isPremiumCustomer = resolvedTypeId == 1 || hasPremiumBranch || hasPremiumSale;

    final String customerTypeName = isPremiumCustomer ? 'PREMIUM' : DmeConstants.getCustomerTypeName(resolvedTypeId);
    final String categoryName = DmeConstants.getCategoryName(resolvedCatId);

    return PopScope(
      canPop: !isCalledWithoutRemarks,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter remarks and tap "Save Remarks & Mark Completed" before leaving.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (isCalledWithoutRemarks) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter remarks and tap "Save Remarks & Mark Completed" before leaving.'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: const Text('Reminder Details', style: TextStyle(fontSize: 18)),
          backgroundColor: const Color(0xFF005BAC),
          foregroundColor: Colors.white,
          actions: [
          if (isCompleted || isCalledWithoutRemarks || _callMade)
            IconButton(
              icon: const Icon(Icons.report_problem_rounded, color: Colors.amber),
              tooltip: 'Raise Complaint',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DmeRegisterComplaintPage(
                      reminder: _reminder,
                      initialSalesHistory: _salesHistory,
                    ),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.rate_review_outlined, size: 14),
              label: const Text('Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF005BAC),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 1,
              ),
              onPressed: _openRaiseRequestPage,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isCompleted)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This reminder is completed. Actions are locked. You can still raise a Complaint or Request using the top bar buttons.',
                        style: TextStyle(fontSize: 12, color: Colors.green[900], fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
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
                                  if (salesman.isNotEmpty)
                                    Text('Salesman: $salesman', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call').toString().toLowerCase() == 'whatsapp'
                              ? Icons.chat_bubble_outline_rounded
                              : Icons.phone_in_talk_rounded,
                          size: 18,
                          color: (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call').toString().toLowerCase() == 'whatsapp'
                              ? Colors.green
                              : const Color(0xFF005BAC),
                        ),
                        const SizedBox(width: 8),
                        Text('Preference: ', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call').toString().toLowerCase() == 'whatsapp'
                                ? Colors.green.withValues(alpha: 0.1)
                                : const Color(0xFF005BAC).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call').toString().toLowerCase() == 'whatsapp'
                                  ? Colors.green.withValues(alpha: 0.5)
                                  : const Color(0xFF005BAC).withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call').toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call').toString().toLowerCase() == 'whatsapp'
                                  ? Colors.green[800]
                                  : const Color(0xFF005BAC),
                            ),
                          ),
                        ),
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
                    // Customer Type & Category
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.category_outlined, size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Type: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    customerTypeName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isPremiumCustomer
                                          ? const Color(0xFFD97706) // Premium vibrant amber/gold color
                                          : (isDark ? Colors.white : Colors.black87),
                                    ),
                                  ),
                                  if (isPremiumCustomer) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.workspace_premium,
                                      size: 16,
                                      color: Color(0xFFD97706),
                                    ),
                                  ],
                                ],
                              ),
                              Text('•', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Category: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    categoryName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white70 : Colors.grey[800],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 4,
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
                            'Called by: ${_getUserDisplayName(_reminder['called_by'])}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                          ),
                        ],
                      ),
                    ],
                    if (_callAttempts > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _callMade ? Icons.phone_callback_rounded : Icons.phone_missed_rounded,
                            size: 16,
                            color: _callMade ? Colors.green : Colors.orange[800],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _callMade
                                  ? 'Connected today ($_todayCallAttempts/2 today, $_callAttempts total)'
                                  : 'Attempted today: $_todayCallAttempts/2 ($_callAttempts total attempted across days)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _callMade ? Colors.green[800] : Colors.orange[900],
                              ),
                            ),
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
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _isPurchaseHistoryExpanded = !_isPurchaseHistoryExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shopping_bag_outlined, size: 20, color: Color(0xFF005BAC)),
                                const SizedBox(width: 8),
                                Text(
                                  'Purchase History (${_salesHistory.length})',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            AnimatedRotation(
                              turns: _isPurchaseHistoryExpanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 24,
                                color: Color(0xFF005BAC),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isPurchaseHistoryExpanded) ...[
                      const SizedBox(height: 12),
                      if (_isLoadingHistory)
                        const Center(child: Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator()))
                      else if (_salesHistory.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Center(child: Text('No previous sales found.', style: TextStyle(color: Colors.grey[600], fontSize: 13))),
                        )
                      else
                        Builder(
                          builder: (context) {
                            // Identify the current reminder's purchase vs older/previous purchases.
                            // The current reminder corresponds to last_purchase_date.
                            final remDateStr = _reminder['last_purchase_date']?.toString().trim();
                            final remDate = remDateStr != null && remDateStr.isNotEmpty
                                ? DateTime.tryParse(remDateStr)?.toLocal()
                                : null;
                            final remDateFormatted = remDate != null ? DateFormat('yyyy-MM-dd').format(remDate) : remDateStr;

                            int currentSaleIndex = -1;
                            if (remDateFormatted != null && remDateFormatted.isNotEmpty) {
                              currentSaleIndex = _salesHistory.indexWhere((s) {
                                final sDateStr = s['date']?.toString().trim();
                                if (sDateStr == null || sDateStr.isEmpty) return false;
                                final sDate = DateTime.tryParse(sDateStr)?.toLocal();
                                final sDateFormatted = sDate != null ? DateFormat('yyyy-MM-dd').format(sDate) : sDateStr;
                                return sDateFormatted == remDateFormatted;
                              });
                            }

                            // If not found by date, default to the first sale (most recent)
                            if (currentSaleIndex == -1 && _salesHistory.isNotEmpty) {
                              currentSaleIndex = 0;
                            }

                            final Map<String, dynamic>? currentSale = currentSaleIndex >= 0 ? _salesHistory[currentSaleIndex] : null;
                            final List<Map<String, dynamic>> previousSales = [];
                            for (int i = 0; i < _salesHistory.length; i++) {
                              if (i != currentSaleIndex) {
                                previousSales.add(_salesHistory[i]);
                              }
                            }

                            Widget buildProductsWrap(Map<String, dynamic> s) {
                              final details = s['dme_sales_detail'] as List?;
                              dynamic rawProducts;
                              if (details != null && details.isNotEmpty) {
                                rawProducts = details[0]['products'];
                              } else if (s['dme_sales_detail'] is Map) {
                                rawProducts = (s['dme_sales_detail'] as Map)['products'];
                              }

                              List<dynamic> productsList = [];
                              if (rawProducts is List) {
                                productsList = rawProducts;
                              } else if (rawProducts is Map) {
                                productsList = [rawProducts];
                              }

                              if (productsList.isEmpty) {
                                return Text(
                                  'No item details recorded',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
                                );
                              }

                              return Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: productsList.map((p) {
                                  String itemName = '';
                                  String qty = '';
                                  if (p is Map) {
                                    itemName = p['item_name']?.toString() ?? '';
                                    qty = p['qty']?.toString() ?? '';
                                  } else {
                                    itemName = p.toString();
                                  }
                                  final label = qty.isNotEmpty ? '$itemName : $qty' : itemName;
                                  return Chip(
                                    label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: isDark ? Colors.grey[800] : const Color(0xFF8CC63F).withValues(alpha: 0.15),
                                    side: BorderSide(color: isDark ? Colors.grey[700]! : Colors.green.withValues(alpha: 0.2)),
                                  );
                                }).toList(),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Current Reminder's Purchase
                                if (currentSale != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF005BAC).withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFF005BAC)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Current Purchase (${_formatDate(currentSale['date'] ?? _reminder['last_purchase_date'])})',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF005BAC),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  buildProductsWrap(currentSale),
                                ],

                                // Previous Purchases (if customer has any older purchases)
                                if (previousSales.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const Icon(Icons.history_rounded, size: 16, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Previous Purchases (${previousSales.length})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.grey[300] : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: previousSales.length,
                                    separatorBuilder: (_, __) => const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8.0),
                                      child: Divider(height: 1),
                                    ),
                                    itemBuilder: (context, idx) {
                                      final s = previousSales[idx];
                                      final saleDate = _formatDate(s['date']);
                                      final catId = int.tryParse(s['category_id']?.toString() ?? '');
                                      final typeId = int.tryParse(s['customer_type_id']?.toString() ?? '');
                                      final catName = DmeConstants.getCategoryName(catId);
                                      final typeName = DmeConstants.getCustomerTypeName(typeId);

                                      return Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.grey[900] : Colors.grey[50],
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Header with Date, Category, and Type
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                // Date
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey[600]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      saleDate,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text('•', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                                                // Category
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Cat: $catName',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF005BAC),
                                                    ),
                                                  ),
                                                ),
                                                // Type
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: (typeName == 'PREMIUM')
                                                        ? Colors.amber.withValues(alpha: 0.15)
                                                        : Colors.grey.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Type: $typeName',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: (typeName == 'PREMIUM')
                                                          ? (isDark ? Colors.amber[300] : Colors.amber[900])
                                                          : (isDark ? Colors.grey[300] : Colors.grey[700]),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            // Items purchased on this date
                                            buildProductsWrap(s),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2.3 Current Reminder's Call Logs & Attempts
            if (_isLoadingReminderLogs)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            else if (_reminderCallLogs.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.phone_in_talk_rounded, size: 20, color: Color(0xFF005BAC)),
                              const SizedBox(width: 8),
                              Text(
                                'Call Attempts & Logs (${_reminderCallLogs.length})',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF005BAC).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_todayCallAttempts/2 today',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF005BAC)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _reminderCallLogs.length,
                        separatorBuilder: (_, __) => const Divider(height: 14),
                        itemBuilder: (context, idx) {
                          final log = _reminderCallLogs[idx];
                          final ts = log['attempt_timestamp']?.toString();
                          final dur = int.tryParse(log['ring_duration']?.toString() ?? '') ?? 0;
                          final type = (log['call_type'] ?? 'outgoing').toString();
                          final caller = _getUserDisplayName(log['caller_email'] ?? log['caller_uid']);
                          final isAnswered = dur > 0;
                          final isLong = dur > 10;

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: isLong
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : isAnswered
                                          ? Colors.teal.withValues(alpha: 0.12)
                                          : Colors.orange.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  type == 'incoming'
                                      ? Icons.call_received_rounded
                                      : isAnswered
                                          ? Icons.call_made_rounded
                                          : Icons.call_missed_rounded,
                                  size: 16,
                                  color: isLong
                                      ? Colors.green[800]
                                      : isAnswered
                                          ? Colors.teal[800]
                                          : Colors.orange[900],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDateTime(ts),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isLong
                                                ? Colors.green.withValues(alpha: 0.15)
                                                : isAnswered
                                                    ? Colors.teal.withValues(alpha: 0.15)
                                                    : Colors.orange.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            dur > 0 ? '${dur}s Connected' : '0s Unanswered',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isLong
                                                  ? Colors.green[800]
                                                  : isAnswered
                                                      ? Colors.teal[800]
                                                      : Colors.orange[900],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${type.toUpperCase()} • Attempt #${_reminderCallLogs.length - idx}${caller.isNotEmpty ? " • by $caller" : ""}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
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
                                      'Called by: ${_getUserDisplayName(h['called_by'])}',
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

            // 3. Call and WhatsApp Action Buttons (hidden if called or completed)
            if (!_callMade && status != 'called' && status != 'completed') ...[
              Builder(
                builder: (context) {
                  final now = DateTime.now();
                  final bool hasReachedDailyLimit = _todayCallAttempts >= 2;

                  // 1-hour gap logic between attempts:
                  // Check call log history for the latest call attempt timestamp
                  DateTime? effectiveLastCall = _lastCallAttemptTimestamp?.toLocal();
                  if (_reminderCallLogs.isNotEmpty) {
                    for (final log in _reminderCallLogs) {
                      final tsStr = log['attempt_timestamp']?.toString();
                      if (tsStr == null) continue;
                      final dt = DateTime.tryParse(tsStr)?.toLocal();
                      if (dt != null && (effectiveLastCall == null || dt.isAfter(effectiveLastCall))) {
                        effectiveLastCall = dt;
                      }
                    }
                  }

                  int remainingCooldownSeconds = 0;
                  bool has60MinsPassed = true;

                  if (_todayCallAttempts > 0 && effectiveLastCall != null) {
                    final elapsed = now.difference(effectiveLastCall);
                    if (elapsed.inSeconds < 3600) {
                      remainingCooldownSeconds = 3600 - elapsed.inSeconds;
                      has60MinsPassed = false;
                    } else {
                      has60MinsPassed = true;
                      remainingCooldownSeconds = 0;
                    }
                  }

                  final bool isCooldownActive = !has60MinsPassed && remainingCooldownSeconds > 0;
                  final bool canMakeCall = !hasReachedDailyLimit && !isCooldownActive;

                  // Format cooldown message
                  final int minutesLeft = (remainingCooldownSeconds / 60).ceil();

                  // WhatsApp unlock logic:
                  // 1. If preference is 'whatsapp', enabled immediately
                  // 2. If a call attempt had customer attend the call but didn't last > 10s, enabled immediately
                  // 3. Otherwise enabled only after 3 total attempts across days
                  final pref = (widget.reminder['customer_preference'] ?? _reminder['customer_preference'] ?? 'Call')
                      .toString()
                      .trim()
                      .toLowerCase();
                  final bool isWhatsAppPreference = pref == 'whatsapp';
                  final bool hasShortCall = _hasShortAttendedCall || (_callDuration != null && _callDuration! > 0 && _callDuration! <= 10);
                  final bool isWhatsAppUnlocked = isWhatsAppPreference || hasShortCall || _callAttempts >= 3;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Notice Card for Attempts / Cooldown (hidden if customer preference is whatsapp)
                      if (!isWhatsAppPreference && _callAttempts > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: hasReachedDailyLimit
                                ? Colors.red.withValues(alpha: 0.1)
                                : isCooldownActive
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: hasReachedDailyLimit
                                  ? Colors.red.withValues(alpha: 0.4)
                                  : isCooldownActive
                                      ? Colors.amber.withValues(alpha: 0.5)
                                      : Colors.orange.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                hasReachedDailyLimit
                                    ? Icons.block_rounded
                                    : isCooldownActive
                                        ? Icons.hourglass_top_rounded
                                        : Icons.phone_missed_rounded,
                                size: 20,
                                color: hasReachedDailyLimit
                                    ? Colors.red[800]
                                    : isCooldownActive
                                        ? Colors.amber[900]
                                        : Colors.orange[900],
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasReachedDailyLimit
                                      ? 'Daily limit reached (2 calls today). If customer does not answer, this will be marked OVERDUE tomorrow for another 2 attempts.'
                                      : isCooldownActive
                                          ? '1-hour gap required between calls. Next attempt available in ~$minutesLeft minute${minutesLeft == 1 ? '' : 's'}.'
                                          : _todayCallAttempts > 0
                                              ? 'Attempt #$_todayCallAttempts made today. 60+ minutes have passed since last attempt — you can call again now.'
                                              : 'Attempt #$_todayCallAttempts made today ($_callAttempts total lifetime attempts). Customer hasn\'t answered yet.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: hasReachedDailyLimit
                                        ? Colors.red[900]
                                        : isCooldownActive
                                            ? Colors.amber[900]
                                            : Colors.orange[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Call Customer Button (hidden if preference is whatsapp)
                      if (!isWhatsAppPreference) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: canMakeCall ? _makePhoneCall : null,
                            icon: const Icon(Icons.call, size: 22),
                            label: Text(
                              hasReachedDailyLimit
                                  ? 'Daily Call Limit Reached (2/2 Calls Today)'
                                  : isCooldownActive
                                      ? 'Call Again in $minutesLeft min (1-Hr Gap)'
                                      : _todayCallAttempts > 0
                                          ? 'Call Customer Again (Attempt 2/2 Today)'
                                          : 'Call Customer (Attempt 1/2 Today)',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canMakeCall ? const Color(0xFF8CC63F) : Colors.grey[400],
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[300],
                              disabledForegroundColor: Colors.grey[600],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: canMakeCall ? 2 : 0,
                            ),
                          ),
                        ),
                        if (_isCheckingCall)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text('Checking Android call log...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          )
                        else
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: _checkCallLogAfterCall,
                              icon: const Icon(Icons.sync_rounded, size: 16),
                              label: const Text('Check Call Log', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF005BAC),
                              ),
                            ),
                          ),
                        const SizedBox(height: 6),
                      ],

                      // WhatsApp Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isWhatsAppUnlocked ? _sendWhatsAppMessage : null,
                          icon: Icon(
                            isWhatsAppUnlocked ? Icons.chat_rounded : Icons.lock_outline_rounded,
                            size: 22,
                          ),
                          label: Text(
                            isWhatsAppUnlocked
                                ? (isWhatsAppPreference
                                    ? 'Send WhatsApp Message (Customer Preference)'
                                    : hasShortCall
                                        ? 'Send WhatsApp Message (Call under 10s)'
                                        : 'Send WhatsApp Message & Upload Proof')
                                : 'WhatsApp unlocks after 3 call attempts ($_callAttempts/3 made)',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isWhatsAppUnlocked ? const Color(0xFF25D366) : Colors.grey[300],
                            foregroundColor: isWhatsAppUnlocked ? Colors.white : Colors.grey[600],
                            disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                            disabledForegroundColor: isDark ? Colors.grey[500] : Colors.grey[600],
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: isWhatsAppUnlocked ? 2 : 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ],

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
                    if (_hasPendingRequest) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.pending_actions_rounded,
                              color: Colors.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pendingRequestType == 'phone_number_change'
                                    ? 'A phone number change request is pending Admin approval. Completion and remarks are locked.'
                                    : (_pendingRequestType == 'call_completion'
                                        ? 'A call completion request is pending Admin approval. Completion and remarks are locked.'
                                        : (_pendingRequestType == 'preference_change'
                                            ? 'A preference change request is pending Admin approval. Completion and remarks are locked.'
                                            : (_pendingRequestType == 'edit_customer_details'
                                                ? 'A customer details change request is pending Admin approval. Completion and remarks are locked.'
                                                : 'A change request is pending Admin approval. Completion and remarks are locked until approved or rejected.'))),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.amber[200] : Colors.amber[900],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (!_callMade) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_callDuration != null && _callDuration! <= 10)
                              ? Colors.orange.withValues(alpha: 0.12)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_callDuration != null && _callDuration! <= 10)
                                ? Colors.orange.withValues(alpha: 0.3)
                                : Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (_callDuration != null && _callDuration! <= 10)
                                  ? Icons.phone_missed_rounded
                                  : Icons.info_outline,
                              color: (_callDuration != null && _callDuration! <= 10)
                                  ? Colors.orange[800]
                                  : Colors.grey[700],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (_callDuration != null && _callDuration! <= 10)
                                    ? (_callDuration == 0
                                        ? 'Call was not answered (0s). Remarks are only allowed for calls lasting more than 10 seconds. Please try calling again.'
                                        : 'Call was under 10 seconds (${_callDuration}s). Remarks are only allowed for calls lasting more than 10 seconds. Please try calling again.')
                                    : 'Please make a call to the customer first. Remarks are enabled once an attended call lasting more than 10 seconds is verified.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (_callDuration != null && _callDuration! <= 10)
                                      ? Colors.orange[900]
                                      : Colors.grey[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: _remarksController,
                      enabled: _callMade && !isCompleted && !_hasPendingRequest,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: isCompleted
                            ? 'Reminder is completed. Remarks are locked.'
                            : (_hasPendingRequest
                                ? 'Remarks are locked while a request is pending Admin approval.'
                                : (_callMade
                                    ? 'Enter discussion summary, customer feedback, etc...'
                                    : 'Remarks disabled (call must exceed 10s)...')),
                        filled: true,
                        fillColor: (!_callMade || isCompleted || _hasPendingRequest)
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
                        onPressed: (_isSaving || !_callMade || isCompleted || _hasPendingRequest) ? null : _saveAndMarkCompleted,
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
                            : Text(
                                _hasPendingRequest
                                    ? 'Request Pending Approval'
                                    : (isCompleted ? 'Reminder Completed' : 'Save Remarks & Mark Completed'),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  }
}
