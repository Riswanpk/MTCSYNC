import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dme_whatsapp_proof_page.dart';
import 'dme_call_scanner_service.dart';
import '../Requests/dme_raise_request_page.dart';
import 'Reminder Detail Page/customer_info_card.dart';
import 'Reminder Detail Page/purchase_history_card.dart';
import 'Reminder Detail Page/call_attempts_card.dart';
import 'Reminder Detail Page/previous_call_history_card.dart';
import 'Reminder Detail Page/contact_person_card.dart';
import 'Reminder Detail Page/call_action_buttons.dart';
import 'Reminder Detail Page/call_remarks_card.dart';
import 'Reminder Detail Page/dme_reminder_detail_helpers.dart';
import 'Reminder Detail Page/dme_reminder_data_service.dart';
import 'Reminder Detail Page/dme_reminder_app_bar.dart';

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

class _DmeReminderDetailPageState extends State<DmeReminderDetailPage>
    with WidgetsBindingObserver {
  late Map<String, dynamic> _reminder;
  late TextEditingController _remarksController;
  late TextEditingController _contactPersonController;
  bool _isSaving = false;
  bool _isSavingContactPerson = false;
  bool _callMade = false;
  DateTime? _callInitiatedTime;

  int? _callDuration;
  DateTime? _calledTimestamp;
  int _callAttempts = 0;
  int _todayCallAttempts = 0;
  DateTime? _lastCallAttemptTimestamp;
  Timer? _cooldownTimer;
  bool _isCheckingCall = false;
  String? _callNoticeMessage;
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
  Map<String, String> _userNames = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reminder = Map<String, dynamic>.from(widget.reminder);
    _remarksController = TextEditingController(text: _reminder['remarks'] ?? '');
    _contactPersonController = TextEditingController(
      text: _reminder['Contact_Person'] ?? _reminder['contact_person'] ?? '',
    );
    final status = (_reminder['status'] ?? '').toString().toLowerCase();
    _callDuration = int.tryParse(_reminder['call_duration']?.toString() ?? '');
    final cTs = _reminder['called_timestamp']?.toString();
    _calledTimestamp = cTs != null ? DateTime.tryParse(cTs) : null;
    final isAlreadyCompleted = (status == 'completed');
    _callMade = isAlreadyCompleted || (_callDuration != null && _callDuration! > 10);
    _callAttempts = int.tryParse(_reminder['call_attempts']?.toString() ?? '') ?? 0;
    _hasShortAttendedCall = (_callDuration != null && _callDuration! > 0 && _callDuration! <= 10);

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final lastCallDay = _reminder['last_call_day']?.toString();
    _todayCallAttempts = (lastCallDay == todayStr)
        ? (int.tryParse(_reminder['today_call_attempts']?.toString() ?? '') ?? 0)
        : 0;

    final lTs = _reminder['last_call_attempt_timestamp']?.toString();
    _lastCallAttemptTimestamp = lTs != null ? DateTime.tryParse(lTs)?.toLocal() : null;

    _cooldownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final custId = _reminder['customer_id'];
    final remId = _reminder['id'];
    setState(() {
      _isLoadingHistory = true;
      _isLoadingCallHistory = true;
      _isLoadingReminderLogs = true;
    });

    try {
      final bundle = await DmeReminderDataService.loadInitialBundle(
        customerId: custId,
        reminderId: remId,
      );

      if (!mounted) return;

      final latestTs = DmeReminderDetailHelpers.extractLatestCallTime(
        recordedLogs: bundle.reminderLogs,
        fallbackTimestamp: _lastCallAttemptTimestamp,
      );

      setState(() {
        _userNames = bundle.userNames;
        _customerBranches = bundle.branches;
        _salesHistory = bundle.salesHistory;
        _callHistory = bundle.callHistory;
        _reminderCallLogs = bundle.reminderLogs;
        if (latestTs != null) _lastCallAttemptTimestamp = latestTs;
        if (bundle.hasShortAttendedCall) _hasShortAttendedCall = true;
        _hasPendingRequest = bundle.pendingRequest != null;
        _pendingRequestType = bundle.pendingRequest?['request_type']?.toString();

        final details = bundle.customerDetails;
        if (details != null) {
          if (details['phone'] != null) _reminder['customer_phone'] = details['phone'];
          _reminder['customer_preference'] = details['preference'] ?? 'Call';
          final cp = details['Contact_Person'] ?? details['contact_person'];
          if (cp != null && _contactPersonController.text.isEmpty) {
            _contactPersonController.text = cp.toString();
          }
        }

        _isLoadingHistory = false;
        _isLoadingCallHistory = false;
        _isLoadingReminderLogs = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          _isLoadingCallHistory = false;
          _isLoadingReminderLogs = false;
        });
      }
    }

    _checkCallLogHistoryAndCooldown();
  }

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

      final entry = syncResult.qualifyingEntry ?? syncResult.latestEntry;
      final latestCallTime = DmeReminderDetailHelpers.extractLatestCallTime(
        qualifyingEntry: syncResult.qualifyingEntry,
        latestEntry: syncResult.latestEntry,
        recordedLogs: syncResult.recordedLogs,
        fallbackTimestamp: _lastCallAttemptTimestamp,
      );

      if (latestCallTime != null && mounted) {
        setState(() {
          _lastCallAttemptTimestamp = latestCallTime;
          _reminderCallLogs = syncResult.recordedLogs;
          if (syncResult.totalTodayAttempts > 0) _todayCallAttempts = syncResult.totalTodayAttempts;
          final isAlreadyCompleted = (_reminder['status'] ?? '').toString().toLowerCase() == 'completed';
          if (!isAlreadyCompleted && (syncResult.hasAttendedCall || (entry?.duration ?? 0) > 10)) {
            _callMade = true;
            _reminder['status'] = 'called';
            _callDuration = entry?.duration;
          }
        });
      }
    } catch (e) {
      debugPrint('[Cooldown] Error checking call log history: $e');
    }
  }

  Future<void> _saveContactPerson({bool showFeedback = true}) async {
    final customerId = _reminder['customer_id'];
    if (customerId == null) return;
    final text = _contactPersonController.text.trim();
    setState(() => _isSavingContactPerson = true);
    try {
      await DmeReminderDataService.saveContactPerson(customerId: customerId, text: text);
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact Person saved successfully!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save Contact Person: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSavingContactPerson = false);
    }
  }

  Future<void> _openRaiseRequestPage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DmeRaiseRequestPage(reminder: _reminder)),
    );

    if (result != null && result is Map && result['success'] == true) {
      final requestType = result['type'];
      setState(() {
        _hasPendingRequest = true;
        _pendingRequestType = requestType?.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(requestType == 'phone_number_change'
                ? 'Phone change request submitted! Reminder is locked until approved by Admin.'
                : 'Change request submitted! Pending Admin review.'),
            backgroundColor: requestType == 'phone_number_change' ? Colors.orange : Colors.blue,
            duration: const Duration(seconds: 4),
          ),
        );
        widget.onUpdated?.call();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksController.dispose();
    _contactPersonController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callInitiatedTime != null) {
      _checkCallLogAfterCall();
    }
  }

  Future<void> _makePhoneCall() async {
    final phone = _reminder['customer_phone']?.toString();
    _callInitiatedTime = DateTime.now();
    final ok = await DmeReminderDetailHelpers.openCustomerDialer(phone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone dialer or phone is missing.')),
      );
    }
  }

  Future<void> _sendWhatsAppMessage() async {
    final phone = _reminder['customer_phone']?.toString();
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer phone number is missing.')));
      return;
    }

    await DmeReminderDetailHelpers.launchWhatsAppChat(phone);

    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DmeWhatsAppProofPage(reminder: _reminder)),
    );

    if (result == true) {
      _reminder['status'] = 'completed';
      _reminder['call_duration'] = 0;
      _reminder['remarks'] = 'WhatsApp Follow-up (Proof uploaded)';
      _remarksController.text = 'WhatsApp Follow-up (Proof uploaded)';
      setState(() => _callMade = true);
      widget.onUpdated?.call();
    }
  }

  Future<void> _checkCallLogAfterCall() async {
    if (!mounted || _isCheckingCall) return;
    setState(() => _isCheckingCall = true);

    try {
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
        _callInitiatedTime = null;
      }

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final lastCallDay = _reminder['last_call_day']?.toString();
      final bool hasCallsToday = syncResult.totalTodayAttempts > 0 || syncResult.recordedLogs.isNotEmpty;

      if (hasCallsToday) {
        final (newTotal, newToday) = DmeReminderDetailHelpers.calculateAttempts(
          currentCallAttempts: _callAttempts,
          currentTodayAttempts: _todayCallAttempts,
          lastCallDay: lastCallDay,
          todayStr: todayStr,
          totalTodayAttempts: syncResult.totalTodayAttempts,
        );
        _todayCallAttempts = newToday;
        _callAttempts = newTotal;

        final entry = syncResult.qualifyingEntry ?? syncResult.latestEntry;
        final int duration = entry?.duration ?? _callDuration ?? 0;
        final DateTime calledTime = DmeReminderDetailHelpers.extractLatestCallTime(
              qualifyingEntry: syncResult.qualifyingEntry,
              latestEntry: syncResult.latestEntry,
              recordedLogs: syncResult.recordedLogs,
              fallbackTimestamp: _lastCallAttemptTimestamp,
            ) ?? now;

        _lastCallAttemptTimestamp = calledTime;
        _reminder['call_attempts'] = _callAttempts;
        _reminder['today_call_attempts'] = _todayCallAttempts;
        _reminder['last_call_attempt_timestamp'] = calledTime.toIso8601String();
        _reminder['last_call_day'] = todayStr;
        if (userEmail != null && userEmail.isNotEmpty) _reminder['called_by'] = userEmail;

        final bool isAlreadyCompleted = (_reminder['status'] ?? '').toString().toLowerCase() == 'completed';
        final bool isAttended = syncResult.hasAttendedCall || duration > 10;
        final bool isShortAttended = syncResult.hasShortCall || (duration > 0 && duration <= 10);

        if (mounted) {
          setState(() {
            _callNoticeMessage = null; // Clear any pending notice
            _reminderCallLogs = syncResult.recordedLogs;
            _callDuration = duration;
            _calledTimestamp = calledTime;
            if (!isAlreadyCompleted) {
              _callMade = isAttended;
              _reminder['call_duration'] = duration;
              _reminder['called_timestamp'] = calledTime.toIso8601String();
              if (isShortAttended) _hasShortAttendedCall = true;
              if (isAttended) _reminder['status'] = 'called';
            }
            _isCheckingCall = false;
          });

          await DmeReminderDataService.updateReminderAfterCall(
            reminderId: _reminder['id'],
            callAttempts: _callAttempts,
            todayCallAttempts: _todayCallAttempts,
            calledTime: calledTime,
            todayStr: todayStr,
            userEmail: userEmail,
            isAttended: isAttended,
            duration: duration,
            isAlreadyCompleted: isAlreadyCompleted,
          );
          widget.onUpdated?.call();

          if (syncResult.newAttemptsLogged > 0) {
            DmeReminderDetailHelpers.showCallFeedbackSnackBar(
              context,
              isAttended: isAttended,
              isShortAttended: isShortAttended,
              duration: duration,
              todayCallAttempts: _todayCallAttempts,
            );
          }
        }
      } else if (mounted) {
        setState(() {
          _isCheckingCall = false;
          _callNoticeMessage = wasInitiated
              ? 'Call not detected in Android call log yet.'
              : 'No outgoing call log found for today.';
        });
      }
    } catch (e) {
      debugPrint('Error inspecting call log: $e');
    } finally {
      if (mounted) setState(() => _isCheckingCall = false);
    }
  }

  Future<void> _saveAndMarkCompleted() async {
    if (!_callMade || _callDuration == null || _callDuration! <= 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_callDuration == null || _callDuration == 0
              ? 'Cannot complete reminder: Call was not attended. Please call customer first.'
              : 'Cannot complete reminder: Call must be above 10 seconds to enter remarks (${_callDuration}s recorded).'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final remarks = _remarksController.text.trim();
    if (remarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter call remarks before saving.')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _saveContactPerson(showFeedback: false);
      await DmeReminderDataService.markReminderCompleted(
        reminderId: _reminder['id'],
        remarks: remarks,
        callDuration: _callDuration,
        calledTimestamp: _calledTimestamp,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call remarks saved and reminder marked completed!'), backgroundColor: Colors.green),
        );
        widget.onUpdated?.call();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving reminder: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminderDateStr = _reminder['reminder_date']?.toString();
    final lastPurchaseDateStr = _reminder['last_purchase_date']?.toString();
    final status = (_reminder['status'] ?? '').toString().toLowerCase();
    final bool isCompleted = (status == 'completed');
    final bool isCalledWithoutRemarks = (status == 'called' || _callMade) && !isCompleted;
    final bool isContactPersonEnabled = (status == 'called' || status == 'completed' || _callMade);

    final resolved = DmeReminderDetailHelpers.resolveTypeAndCategory(
      reminder: _reminder,
      customerBranches: _customerBranches,
      salesHistory: _salesHistory,
    );

    return PopScope(
      canPop: !isCalledWithoutRemarks,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter remarks and tap "Save Remarks & Mark Completed" before leaving.'), backgroundColor: Colors.orange, duration: Duration(seconds: 3)),
          );
        }
      },
      child: Scaffold(
        appBar: DmeReminderAppBar(
          reminder: _reminder,
          salesHistory: _salesHistory,
          isCompleted: isCompleted,
          isCalledWithoutRemarks: isCalledWithoutRemarks,
          callMade: _callMade,
          onOpenRaiseRequest: _openRaiseRequestPage,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCompleted) DmeReminderDetailHelpers.buildCompletedBanner(),

              // In-Page Call Notice Banner (shown locally, automatically destroyed if user leaves the page)
              if (_callNoticeMessage != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFFE65100), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _callNoticeMessage!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFBF360C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _checkCallLogAfterCall,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Recheck', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Color(0xFF8D6E63)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Dismiss',
                        onPressed: () {
                          if (mounted) setState(() => _callNoticeMessage = null);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              CustomerInfoCard(
                reminder: _reminder,
                customerName: _reminder['customer_name'] ?? 'Unnamed Customer',
                customerPhone: _reminder['customer_phone'] ?? 'N/A',
                customerAddress: _reminder['customer_address'] ?? '',
                salesman: _reminder['customer_salesman'] ?? '',
                branchName: _reminder['branch_name'] ?? 'Branch',
                preference: (_reminder['customer_preference'] ?? 'Call').toString(),
                customerTypeName: resolved.customerTypeName,
                isPremiumCustomer: resolved.isPremiumCustomer,
                categoryName: resolved.categoryName,
                reminderDateStr: reminderDateStr,
                lastPurchaseDateStr: lastPurchaseDateStr,
                callAttempts: _callAttempts,
                todayCallAttempts: _todayCallAttempts,
                callMade: _callMade,
                formatDate: DmeReminderDetailHelpers.formatDate,
                getUserDisplayName: (uid) => DmeReminderDetailHelpers.getUserDisplayName(uid, _userNames),
              ),
              const SizedBox(height: 16),

              // 2. Recent Purchase History
              PurchaseHistoryCard(
                salesHistory: _salesHistory,
                isLoadingHistory: _isLoadingHistory,
                isPurchaseHistoryExpanded: _isPurchaseHistoryExpanded,
                onToggleExpanded: () => setState(() => _isPurchaseHistoryExpanded = !_isPurchaseHistoryExpanded),
                reminder: _reminder,
                formatDate: DmeReminderDetailHelpers.formatDate,
              ),
              const SizedBox(height: 16),

              // 2.3 Current Reminder's Call Logs & Attempts
              CallAttemptsCard(
                reminderCallLogs: _reminderCallLogs,
                isLoadingReminderLogs: _isLoadingReminderLogs,
                todayCallAttempts: _todayCallAttempts,
                formatDateTime: DmeReminderDetailHelpers.formatDateTime,
                getUserDisplayName: (uid) => DmeReminderDetailHelpers.getUserDisplayName(uid, _userNames),
              ),
              if (_reminderCallLogs.isNotEmpty) const SizedBox(height: 16),

              // 2.5 Previous Call History
              PreviousCallHistoryCard(
                callHistory: _callHistory,
                isLoadingCallHistory: _isLoadingCallHistory,
                formatDate: DmeReminderDetailHelpers.formatDate,
                getUserDisplayName: (uid) => DmeReminderDetailHelpers.getUserDisplayName(uid, _userNames),
              ),
              if (_callHistory.isNotEmpty) const SizedBox(height: 16),

              // Contact Person Card (Enabled after call status is 'called' or 'completed')
              ContactPersonCard(
                controller: _contactPersonController,
                isEnabled: isContactPersonEnabled,
                isSaving: _isSavingContactPerson,
                onSave: _saveContactPerson,
              ),
              const SizedBox(height: 16),

              // 3. Call and WhatsApp Action Buttons
              if (!_callMade && status != 'called' && status != 'completed') ...[
                CallActionButtons(
                  todayCallAttempts: _todayCallAttempts,
                  callAttempts: _callAttempts,
                  callDuration: _callDuration,
                  lastCallAttemptTimestamp: _lastCallAttemptTimestamp,
                  reminderCallLogs: _reminderCallLogs,
                  parseAttemptTimestamp: DmeReminderDetailHelpers.parseAttemptTimestamp,
                  preference: (_reminder['customer_preference'] ?? 'Call').toString(),
                  hasShortAttendedCall: _hasShortAttendedCall,
                  isCheckingCall: _isCheckingCall,
                  onMakeCall: _makePhoneCall,
                  onCheckCallLog: _checkCallLogAfterCall,
                  onSendWhatsApp: _sendWhatsAppMessage,
                ),
              ],

              // 4. Call Remarks Section
              CallRemarksCard(
                remarksController: _remarksController,
                callMade: _callMade,
                callDuration: _callDuration,
                isCompleted: isCompleted,
                hasPendingRequest: _hasPendingRequest,
                pendingRequestType: _pendingRequestType,
                isSaving: _isSaving,
                onSaveAndComplete: _saveAndMarkCompleted,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
