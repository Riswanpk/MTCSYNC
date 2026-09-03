import 'package:flutter/material.dart';
import 'yupulse_mark_model.dart';
import 'yupulse_ui_helpers.dart';

class YupulseUserCard extends StatelessWidget {
  final YupulseUserCardItem item;
  final String selectedBranch;
  final bool isDark;
  final Color cardColor;
  final VoidCallback onToggleSelected;
  final void Function(bool useAuto) onToggleAutoTodo;
  final void Function(bool useAuto) onToggleAutoCalling;
  final VoidCallback onReasonChanged;

  const YupulseUserCard({
    super.key,
    required this.item,
    required this.selectedBranch,
    required this.isDark,
    required this.cardColor,
    required this.onToggleSelected,
    required this.onToggleAutoTodo,
    required this.onToggleAutoCalling,
    required this.onReasonChanged,
  });

  @override
  Widget build(BuildContext context) {
    const primaryGreen = YupulseUiHelpers.primaryGreen;
    final username = item.username;
    final yupulseId = item.yupulseId;
    final autoTodoDone = item.autoTodoDoneCount;
    final autoCallTarget = item.autoCallTargetCount;
    final autoCallDone = item.autoCallDoneCount;
    final bool useAutoTodo = item.useAutoTodo;
    final bool useAutoCalling = item.useAutoCalling;
    final bool isSubmitted = item.isSubmitted;
    final bool isSelected = item.isSelected && !isSubmitted;

    final todoCtrl = item.todoController;
    final callTargetCtrl = item.callTargetController;
    final callDoneCtrl = item.callDoneController;
    final reasonCtrl = item.reasonController;

    final hasYupulseId = yupulseId.isNotEmpty;
    final isManualOverrideActive = !useAutoTodo || !useAutoCalling;

    final submittedBgColor = isDark ? const Color(0xFF0D2818) : const Color(0xFFF0FDF4);
    final submittedBorderColor = primaryGreen.withValues(alpha: isDark ? 0.7 : 0.5);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSubmitted ? 1.0 : (isSelected ? 1.0 : 0.55),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isSubmitted ? submittedBgColor : cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: isSubmitted
                  ? primaryGreen.withValues(alpha: isDark ? 0.2 : 0.08)
                  : Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isSubmitted
                ? submittedBorderColor
                : isSelected
                    ? (hasYupulseId
                        ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
                        : Colors.red.shade400)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
            width: isSubmitted ? 1.5 : (isSelected && !hasYupulseId ? 1.5 : 1),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Round selection indicator
                  if (isSubmitted)
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(right: 10, top: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                        border: Border.all(
                          color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                          width: 1.5,
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: onToggleSelected,
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 10, top: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? primaryGreen
                              : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                          border: Border.all(
                            color: isSelected
                                ? primaryGreen
                                : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Center(
                                child: Icon(Icons.check, size: 14, color: Colors.white),
                              )
                            : null,
                      ),
                    ),
                  // User Avatar
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isSubmitted || isSelected
                            ? [
                                primaryGreen,
                                primaryGreen.withValues(alpha: 0.75),
                              ]
                            : [
                                Colors.grey.shade500,
                                Colors.grey.shade400,
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // User Info + Badges
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: Username
                        Text(
                          username,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected || isSubmitted
                                ? (isDark ? Colors.white : Colors.grey.shade900)
                                : (isDark ? Colors.white60 : Colors.grey.shade600),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Second row: Branch and Badges (Wrap to avoid squishing)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Branch: $selectedBranch',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white54 : Colors.grey.shade600,
                              ),
                            ),
                            if (isSubmitted)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: primaryGreen.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: primaryGreen.withValues(alpha: 0.7)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 12, color: primaryGreen),
                                    SizedBox(width: 3),
                                    Text(
                                      'Submitted (Locked)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: primaryGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: hasYupulseId
                                    ? primaryGreen.withValues(alpha: 0.12)
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: hasYupulseId
                                      ? primaryGreen.withValues(alpha: 0.3)
                                      : Colors.red.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    hasYupulseId ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                                    size: 12,
                                    color: hasYupulseId ? primaryGreen : Colors.red.shade700,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    hasYupulseId ? 'ID: $yupulseId' : 'Missing Yupulse ID',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: hasYupulseId ? primaryGreen : Colors.red.shade700,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
              const SizedBox(height: 16),
              // Marks Control Grid
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Todo Column (reduced width)
                  Expanded(
                    flex: 4,
                    child: YupulseUiHelpers.buildMarkSection(
                      title: 'Todo Mark',
                      icon: Icons.checklist_rounded,
                      autoPillText: '$autoTodoDone days',
                      useAuto: useAutoTodo,
                      isDark: isDark,
                      onCheckboxChanged: isSubmitted ? null : (val) => onToggleAutoTodo(val ?? true),
                      child: TextField(
                        controller: todoCtrl,
                        enabled: !useAutoTodo && isSelected && !isSubmitted,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: useAutoTodo || !isSelected || isSubmitted
                              ? (isDark ? Colors.white38 : Colors.grey.shade500)
                              : (isDark ? Colors.white : Colors.grey.shade900),
                        ),
                        decoration: YupulseUiHelpers.inputDecoration(
                          labelText: useAutoTodo ? 'Auto Days' : 'Days Done',
                          useAuto: useAutoTodo || !isSelected || isSubmitted,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Customer Calling Column
                  Expanded(
                    flex: 7,
                    child: YupulseUiHelpers.buildMarkSection(
                      title: 'Customer Calling',
                      icon: Icons.phone_in_talk_rounded,
                      autoPillText: 'Total: $autoCallTarget | Called: $autoCallDone',
                      useAuto: useAutoCalling,
                      isDark: isDark,
                      onCheckboxChanged: isSubmitted ? null : (val) => onToggleAutoCalling(val ?? true),
                      child: useAutoCalling
                          ? TextField(
                              controller: TextEditingController(
                                text: 'Total: $autoCallTarget | Called: $autoCallDone',
                              ),
                              enabled: false,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white38 : Colors.grey.shade500,
                              ),
                              decoration: YupulseUiHelpers.inputDecoration(
                                labelText: 'Auto Target & Done',
                                useAuto: true,
                                isDark: isDark,
                              ),
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: callTargetCtrl,
                                    enabled: isSelected && !isSubmitted,
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) {
                                      final enteredTarget = int.tryParse(val.trim()) ?? 0;
                                      final currentDone = int.tryParse(callDoneCtrl.text.trim()) ?? 0;
                                      if (enteredTarget >= 0 && currentDone > enteredTarget) {
                                        callDoneCtrl.text = enteredTarget.toString();
                                      }
                                    },
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: !isSelected || isSubmitted
                                          ? (isDark ? Colors.white38 : Colors.grey.shade500)
                                          : (isDark ? Colors.white : Colors.grey.shade900),
                                    ),
                                    decoration: YupulseUiHelpers.inputDecoration(
                                      labelText: 'Total Target',
                                      useAuto: !isSelected || isSubmitted,
                                      isDark: isDark,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: callDoneCtrl,
                                    enabled: isSelected && !isSubmitted,
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) {
                                      final enteredDone = int.tryParse(val.trim()) ?? 0;
                                      final target = int.tryParse(callTargetCtrl.text.trim()) ?? 0;
                                      if (enteredDone > target) {
                                        callDoneCtrl.text = target.toString();
                                        callDoneCtrl.selection = TextSelection.fromPosition(
                                          TextPosition(offset: callDoneCtrl.text.length),
                                        );
                                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Called count cannot exceed Total Target ($target)',
                                            ),
                                            duration: const Duration(seconds: 2),
                                            backgroundColor: Colors.orange.shade800,
                                          ),
                                        );
                                      }
                                    },
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: !isSelected || isSubmitted
                                          ? (isDark ? Colors.white38 : Colors.grey.shade500)
                                          : (isDark ? Colors.white : Colors.grey.shade900),
                                    ),
                                    decoration: YupulseUiHelpers.inputDecoration(
                                      labelText: 'Called Count',
                                      useAuto: !isSelected || isSubmitted,
                                      isDark: isDark,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              // Reason field if manual override is active
              if (isManualOverrideActive) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: reasonCtrl.text.trim().length >= 15
                          ? primaryGreen.withValues(alpha: 0.5)
                          : (isDark ? Colors.amber.shade900.withValues(alpha: 0.5) : Colors.amber.shade300),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.edit_note_rounded, size: 18, color: Colors.amber.shade800),
                              const SizedBox(width: 6),
                              Text(
                                'Reason for Manual Override',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${reasonCtrl.text.trim().length}/15 min',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: reasonCtrl.text.trim().length >= 15
                                  ? primaryGreen
                                  : Colors.amber.shade800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonCtrl,
                        enabled: isSelected && !isSubmitted,
                        maxLines: 2,
                        onChanged: (_) => onReasonChanged(),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.grey.shade900,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter reason for editing auto values (min 15 characters)...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.grey.shade500,
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: reasonCtrl.text.trim().isNotEmpty && reasonCtrl.text.trim().length < 15
                                  ? Colors.amber.shade600
                                  : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: primaryGreen, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
