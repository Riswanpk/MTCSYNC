import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Form component for requesting Admin approval to mark a reminder call as completed.
class DmeRequestsMarkCallAsCompletedForm extends StatefulWidget {
  final TextEditingController callDurationController;
  final TextEditingController completionRemarksController;
  final TextEditingController completionReasonController;

  const DmeRequestsMarkCallAsCompletedForm({
    super.key,
    required this.callDurationController,
    required this.completionRemarksController,
    required this.completionReasonController,
  });

  @override
  State<DmeRequestsMarkCallAsCompletedForm> createState() =>
      _DmeRequestsMarkCallAsCompletedFormState();
}

class _DmeRequestsMarkCallAsCompletedFormState
    extends State<DmeRequestsMarkCallAsCompletedForm> {
  late final TextEditingController _m1Controller;
  late final TextEditingController _m2Controller;
  late final TextEditingController _s1Controller;
  late final TextEditingController _s2Controller;

  late final FocusNode _m1Focus;
  late final FocusNode _m2Focus;
  late final FocusNode _s1Focus;
  late final FocusNode _s2Focus;

  @override
  void initState() {
    super.initState();
    _m1Controller = TextEditingController();
    _m2Controller = TextEditingController();
    _s1Controller = TextEditingController();
    _s2Controller = TextEditingController();

    _m1Focus = FocusNode();
    _m2Focus = FocusNode();
    _s1Focus = FocusNode();
    _s2Focus = FocusNode();

    // If callDurationController already had a value (e.g. from previous state), populate boxes
    final initialSec = int.tryParse(widget.callDurationController.text.trim()) ?? 0;
    if (initialSec > 0) {
      final mins = (initialSec ~/ 60).clamp(0, 99);
      final secs = (initialSec % 60).clamp(0, 59);
      final minStr = mins.toString().padLeft(2, '0');
      final secStr = secs.toString().padLeft(2, '0');
      _m1Controller.text = minStr[0];
      _m2Controller.text = minStr[1];
      _s1Controller.text = secStr[0];
      _s2Controller.text = secStr[1];
    }
  }

  @override
  void dispose() {
    _m1Controller.dispose();
    _m2Controller.dispose();
    _s1Controller.dispose();
    _s2Controller.dispose();

    _m1Focus.dispose();
    _m2Focus.dispose();
    _s1Focus.dispose();
    _s2Focus.dispose();
    super.dispose();
  }

  void _syncDurationToController() {
    final m1 = _m1Controller.text.trim();
    final m2 = _m2Controller.text.trim();
    final s1 = _s1Controller.text.trim();
    final s2 = _s2Controller.text.trim();

    if (m1.isEmpty && m2.isEmpty && s1.isEmpty && s2.isEmpty) {
      widget.callDurationController.text = '';
      return;
    }

    final mins = int.tryParse('$m1$m2') ?? 0;
    final secs = int.tryParse('$s1$s2') ?? 0;
    final totalSeconds = (mins * 60) + secs;
    widget.callDurationController.text = totalSeconds.toString();
  }

  Widget _buildDigitBox({
    required TextEditingController controller,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    FocusNode? prevFocus,
    bool isSecondTens = false,
  }) {
    return SizedBox(
      width: 52,
      height: 56,
      child: KeyboardListener(
        focusNode: FocusNode(), // auxiliary node for key listener wrapper if needed
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty &&
              prevFocus != null) {
            prevFocus.requestFocus();
          }
        },
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF005BAC),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
            if (isSecondTens)
              FilteringTextInputFormatter.allow(RegExp(r'[0-5]')),
          ],
          decoration: InputDecoration(
            counterText: '',
            hintText: '0',
            hintStyle: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF005BAC), width: 2),
            ),
          ),
          onChanged: (val) {
            if (val.isNotEmpty && nextFocus != null) {
              nextFocus.requestFocus();
            }
            _syncDurationToController();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Notice banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.purple.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Enter call duration and remarks. This request submission time is recorded as the call timestamp. Upon Admin approval, this reminder will be marked as Completed and attributed to your user stats.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.purple.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Call Duration MM:SS 4-box Form Field with validator
        FormField<String>(
          validator: (_) {
            final m1 = _m1Controller.text.trim();
            final m2 = _m2Controller.text.trim();
            final s1 = _s1Controller.text.trim();
            final s2 = _s2Controller.text.trim();

            if (m1.isEmpty && m2.isEmpty && s1.isEmpty && s2.isEmpty) {
              return 'Please enter call duration (MM:SS)';
            }

            final secs = int.tryParse('$s1$s2') ?? 0;
            if (secs > 59) {
              return 'Seconds (SS) cannot be greater than 59';
            }

            final mins = int.tryParse('$m1$m2') ?? 0;
            final totalSec = (mins * 60) + secs;
            if (totalSec <= 0) {
              return 'Call duration must be greater than 00:00';
            }

            return null;
          },
          builder: (fieldState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18, color: Color(0xFF005BAC)),
                    const SizedBox(width: 6),
                    const Text(
                      'Call Duration (MM : SS) *',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // MM Box 1
                    _buildDigitBox(
                      controller: _m1Controller,
                      focusNode: _m1Focus,
                      nextFocus: _m2Focus,
                    ),
                    const SizedBox(width: 8),
                    // MM Box 2
                    _buildDigitBox(
                      controller: _m2Controller,
                      focusNode: _m2Focus,
                      nextFocus: _s1Focus,
                      prevFocus: _m1Focus,
                    ),
                    // Colon separator
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        ':',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF005BAC),
                        ),
                      ),
                    ),
                    // SS Box 1 (Tens digit: only 0-5 allowed so SS cannot exceed 59)
                    _buildDigitBox(
                      controller: _s1Controller,
                      focusNode: _s1Focus,
                      nextFocus: _s2Focus,
                      prevFocus: _m2Focus,
                      isSecondTens: true,
                    ),
                    const SizedBox(width: 8),
                    // SS Box 2 (Units digit: 0-9)
                    _buildDigitBox(
                      controller: _s2Controller,
                      focusNode: _s2Focus,
                      prevFocus: _s1Focus,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Helper labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 112,
                      child: Text(
                        'Minutes',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 112,
                      child: Text(
                        'Seconds (max 59)',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                if (fieldState.hasError) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      fieldState.errorText ?? '',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // Remarks field
        TextFormField(
          controller: widget.completionRemarksController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Call Remarks *',
            hintText: 'Enter discussion points, customer feedback, next purchase plan...',
            prefixIcon: const Icon(Icons.rate_review_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter the call remarks';
            }
            if (val.trim().length < 3) {
              return 'Please provide more details in remarks';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // Reason / Note field (Optional)
        TextFormField(
          controller: widget.completionReasonController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Reason for Approval Request (Optional)',
            hintText: 'e.g. Called from alternate device / landline, or call log was not detected',
            prefixIcon: const Icon(Icons.notes_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}
