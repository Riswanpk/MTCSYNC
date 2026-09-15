import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../dme_constants.dart';
import '../dme_config.dart';
import 'dme_whatsapp_proof_page.dart';
// ignore: unused_import
import 'dme_assignment_service.dart';
import 'dme_call_scanner_service.dart';
import '../Complaints/Dme/dme_register_complaint_page.dart';
import 'dme_raise_request_page.dart';

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
  bool _isCheckingCall = false;

  List<Map<String, dynamic>> _salesHistory = [];
  bool _isLoadingHistory = false;
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

    _loadUserNames();
    _fetchCustomerDetails();
    _fetchCustomerBranches();
    _fetchCustomerSalesHistory();
    _fetchCustomerCallHistory();
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
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remarksController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callInitiatedTime != null) {
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

  Future<void> _updateCallAttemptsInDb(int attempts) async {
    try {
      final client = await DmeConfig.getClient();
      final reminderId = _reminder['id'];
      if (client != null && reminderId != null) {
        try {
          await client.from('dme_reminders').update({
            'call_attempts': attempts,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', reminderId);
          widget.onUpdated?.call();
        } catch (_) {
          // Column might not exist yet, fallback gracefully
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
      final contact = _reminder['customer_phone']?.toString() ?? '';
      final entry = await DmeCallScannerService.fetchLatestCallForContact(
        contact,
        sinceTime: _callInitiatedTime,
      );

      final wasInitiated = _callInitiatedTime != null;
      _callInitiatedTime = null; // Clear so it only checks once per call initiation

      final now = DateTime.now();
      int duration = 0;
      DateTime calledTime = now;

      if (entry != null) {
        duration = entry.duration ?? 0;
        if (entry.timestamp != null && entry.timestamp! > 0) {
          calledTime = DateTime.fromMillisecondsSinceEpoch(entry.timestamp!);
        }

        // Count attempts from device call log
        final actualAttempts = await DmeCallScannerService.getTodayOutgoingAttemptCount(contact);
        _callAttempts = actualAttempts > 0 ? actualAttempts : (_callAttempts + 1);
        _reminder['call_attempts'] = _callAttempts;
        _updateCallAttemptsInDb(_callAttempts);

        // Attended call strictly requires duration > 10 seconds to allow remarks
        final bool isAttended = duration > 10;
        if (mounted) {
          setState(() {
            _callDuration = duration;
            _calledTimestamp = calledTime;
            _callMade = isAttended;
            _reminder['call_duration'] = duration;
            _reminder['called_timestamp'] = calledTime.toIso8601String();
            if (isAttended) {
              _reminder['status'] = 'called';
            }
            _isCheckingCall = false;
          });

          // If call attended (>10s), update Supabase with status 'called' and caller email
          if (isAttended) {
            final userEmail = FirebaseAuth.instance.currentUser?.email;
            final client = await DmeConfig.getClient();
            final remId = _reminder['id'];
            if (client != null && remId != null) {
              final payload = <String, dynamic>{
                'call_duration': duration,
                'called_timestamp': calledTime.toIso8601String(),
                'call_attempts': _callAttempts,
                'status': 'called',
                'updated_at': now.toIso8601String(),
              };
              if (userEmail != null && userEmail.isNotEmpty) {
                payload['called_by'] = userEmail;
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

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Call attended ($duration sec)! Please add remarks below.'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  duration == 0
                      ? 'Customer did not pick up (0s). Call attempt #$_callAttempts recorded. Remarks require a call over 10s.'
                      : 'Call was under 10s (${duration}s). Call attempt #$_callAttempts recorded. Remarks require a call over 10s.',
                ),
                backgroundColor: Colors.orange[900],
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() => _isCheckingCall = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                wasInitiated
                    ? 'No call was detected in your call log. Call attempt was not recorded.'
                    : 'No outgoing call log found for this customer.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
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
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Check Call Logs / Reload',
            onPressed: () {
              _checkCallLogAfterCall();
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
                          Text(
                            _callMade
                                ? 'Calls attempted today: $_callAttempts (Connected)'
                                : 'Calls attempted today: $_callAttempts (Unanswered)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _callMade ? Colors.green[800] : Colors.orange[900],
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
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _salesHistory.length,
                          separatorBuilder: (_, __) => const Divider(height: 14),
                          itemBuilder: (context, idx) {
                            final s = _salesHistory[idx];
                            final details = s['dme_sales_detail'] as List?;
                            // Extract products from details
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
                          },
                        ),
                    ],
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
            if (_callAttempts > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _callMade ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _callMade ? Colors.green.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _callMade ? Icons.check_circle_outline_rounded : Icons.phone_missed_rounded,
                      size: 20,
                      color: _callMade ? Colors.green[800] : Colors.orange[900],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _callMade
                            ? 'Call connected (${_callDuration ?? 0}s) on attempt #$_callAttempts today'
                            : '$_callAttempts call attempt${_callAttempts > 1 ? 's' : ''} made today — customer hasn\'t picked up yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _callMade ? Colors.green[900] : Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (!_callMade && status != 'called' && status != 'completed') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _makePhoneCall,
                  icon: const Icon(Icons.call, size: 22),
                  label: Text(_callAttempts > 0 ? 'Call Customer Again ($customerPhone)' : 'Call $customerPhone'),
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
                    if (!_callMade) ...[
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
                      enabled: _callMade,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: _callMade
                            ? 'Enter discussion summary, customer feedback, etc...'
                            : 'Remarks disabled (call must exceed 10s)...',
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  }
}
