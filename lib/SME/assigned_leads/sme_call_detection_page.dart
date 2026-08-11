import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:call_log/call_log.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum CallAction { promote, reject, none }

class CallDetectionResult {
  final CallAction action;
  const CallDetectionResult(this.action);
}

enum DetectionState { idle, detecting, detected }

class SmeCallDetectionPage extends StatefulWidget {
  final String phone;
  final String docId;
  final String currentUid;
  final String screeningStatus;

  const SmeCallDetectionPage({
    super.key,
    required this.phone,
    required this.docId,
    required this.currentUid,
    required this.screeningStatus,
  });

  @override
  State<SmeCallDetectionPage> createState() => _SmeCallDetectionPageState();
}

class _SmeCallDetectionPageState extends State<SmeCallDetectionPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _brandPrimary = Color(0xFF005BAC);
  static const Color _teal = Color(0xFF00897B);

  DetectionState _state = DetectionState.idle;
  DateTime? _callStartTime;
  int? _detectedDuration;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  Future<void> _initiateCall() async {
    if (widget.phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No phone number available')));
      }
      return;
    }
    var status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone permission denied')));
      }
      return;
    }
    final uri = Uri(scheme: 'tel', path: widget.phone);
    if (await canLaunchUrl(uri)) {
      setState(() {
        _state = DetectionState.detecting;
        _callStartTime = DateTime.now();
      });
      await _saveCallState();
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch dialer')));
      }
    }
  }

  Future<void> _saveCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sme_pending_call_number', widget.phone);
    await prefs.setInt(
        'sme_pending_call_time', _callStartTime?.millisecondsSinceEpoch ?? 0);
    await prefs.setString('sme_pending_call_docid', widget.docId);
  }

  Future<void> _clearCallState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sme_pending_call_number');
    await prefs.remove('sme_pending_call_time');
    await prefs.remove('sme_pending_call_docid');
  }

  Future<void> _checkCallLog() async {
    if (_callStartTime == null) return;
    final permStatus = await Permission.phone.status;
    if (!permStatus.isGranted) return;
    try {
      final now = DateTime.now();
      final Iterable<CallLogEntry> entries = await CallLog.query(
          dateFrom: _callStartTime!.millisecondsSinceEpoch,
          dateTo: now.millisecondsSinceEpoch);
      final normalizedPending = widget.phone.replaceAll(RegExp(r'\D'), '');
      CallLogEntry? matchedEntry;
      for (final entry in entries) {
        final logNumber = entry.number?.replaceAll(RegExp(r'\D'), '') ?? '';
        final wasConnected = (entry.duration ?? 0) > 5;
        if (logNumber.endsWith(normalizedPending) && wasConnected) {
          matchedEntry = entry;
          break;
        }
      }
      if (matchedEntry != null && mounted) {
        await FirebaseFirestore.instance
            .collection('follow_ups')
            .doc(widget.docId)
            .update({
          'screening_status': 'called',
          'screening_call_time': FieldValue.serverTimestamp(),
          'screening_call_duration': matchedEntry.duration ?? 0,
          'screened_by': widget.currentUid,
        });
        await _clearCallState();
        if (mounted) {
          setState(() {
            _state = DetectionState.detected;
            _detectedDuration = matchedEntry!.duration;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking call log: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1C2A) : const Color(0xFFF2F6FA),
      appBar: AppBar(
        title: const Text('Call Customer',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontFamily: 'Montserrat')),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_brandPrimary, Color(0xFF008BD6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context)
              .pop(const CallDetectionResult(CallAction.none)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C2C3C) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child:
                        const Icon(Icons.phone_rounded, color: _teal, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer Number',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                        const SizedBox(height: 2),
                        Text(widget.phone,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF0D2B40),
                                letterSpacing: 1)),
                      ]),
                ]),
              ),
              const SizedBox(height: 40),
              Expanded(child: _buildStateWidget(isDark)),
              const SizedBox(height: 24),
              _buildBottomActions(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateWidget(bool isDark) {
    switch (_state) {
      case DetectionState.idle:
        return _buildIdleState(isDark);
      case DetectionState.detecting:
        return _buildDetectingState(isDark);
      case DetectionState.detected:
        return _buildDetectedState(isDark);
    }
  }

  Widget _pulseCircle({required Color color, required IconData icon}) {
    return ScaleTransition(
      scale: _pulseAnimation,
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.0)
            ])),
        child: Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border:
                    Border.all(color: color.withValues(alpha: 0.4), width: 2)),
            child: Icon(icon, color: color, size: 44),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _pulseCircle(color: _teal, icon: Icons.phone_rounded),
      const SizedBox(height: 28),
      Text('Ready to Call',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0D2B40))),
      const SizedBox(height: 10),
      Text(
          'Tap the button below to call the customer.\nOnce the call ends, return to this app.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6)),
    ]);
  }

  Widget _buildDetectingState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _pulseCircle(color: Colors.orange, icon: Icons.phone_in_talk_rounded),
      const SizedBox(height: 28),
      Text('Detecting Call\u2026',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0D2B40))),
      const SizedBox(height: 10),
      Text('Return here after your call.\nWe\'ll detect it automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6)),
      const SizedBox(height: 20),
      const CircularProgressIndicator(strokeWidth: 2),
    ]);
  }

  Widget _buildDetectedState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _teal.withValues(alpha: 0.12),
            border: Border.all(color: _teal.withValues(alpha: 0.4), width: 2)),
        child: const Icon(Icons.check_circle_rounded, color: _teal, size: 60),
      ),
      const SizedBox(height: 28),
      const Text('Call Detected!',
          style: TextStyle(
              fontSize: 24, fontWeight: FontWeight.w800, color: _teal)),
      if (_detectedDuration != null) ...[
        const SizedBox(height: 6),
        Text('Duration: ${_detectedDuration}s',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
      ],
      const SizedBox(height: 12),
      Text(
          'Lead has been marked as Called.\nNow you can promote or reject this lead.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey.shade500, height: 1.6)),
    ]);
  }

  Widget _buildBottomActions(bool isDark) {
    if (_state == DetectionState.idle) {
      return SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: _initiateCall,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_teal, Color(0xFF00BCD4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: _teal.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 6))
              ],
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.phone_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text('Start Call',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ]),
          ),
        ),
      );
    }

    if (_state == DetectionState.detecting) {
      return SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: _checkCallLog,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _brandPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _brandPrimary.withValues(alpha: 0.3)),
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, color: _brandPrimary, size: 20),
                  SizedBox(width: 8),
                  Text('Check Now',
                      style: TextStyle(
                          color: _brandPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      );
    }

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => Navigator.of(context)
              .pop(const CallDetectionResult(CallAction.reject)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF44336).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFF44336).withValues(alpha: 0.3)),
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_rounded,
                      color: Color(0xFFF44336), size: 20),
                  SizedBox(width: 6),
                  Text('Reject',
                      style: TextStyle(
                          color: Color(0xFFF44336),
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GestureDetector(
          onTap: () => Navigator.of(context)
              .pop(const CallDetectionResult(CallAction.promote)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text('Promote',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      ),
    ]);
  }
}
