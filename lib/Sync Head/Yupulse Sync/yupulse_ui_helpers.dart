import 'package:flutter/material.dart';

class YupulseUiHelpers {
  static const Color primaryGreen = Color(0xFF8CC63F);

  static InputDecoration inputDecoration({
    required String labelText,
    required bool useAuto,
    required bool isDark,
    EdgeInsetsGeometry? contentPadding,
  }) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(
        fontSize: 11,
        color: useAuto ? (isDark ? Colors.white38 : Colors.grey.shade500) : primaryGreen,
      ),
      filled: true,
      fillColor: useAuto
          ? (isDark ? const Color(0xFF1E293B) : Colors.grey.shade200)
          : (isDark ? const Color(0xFF1E293B) : Colors.white),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: primaryGreen, width: 1.5),
      ),
      contentPadding: contentPadding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  static Widget buildMarkSection({
    required String title,
    required IconData icon,
    required String autoPillText,
    required bool useAuto,
    required bool isDark,
    required ValueChanged<bool?>? onCheckboxChanged,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: primaryGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Auto Value Pill Display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: primaryGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: primaryGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 11, color: primaryGreen),
                const SizedBox(width: 3),
                const Text(
                  'Auto:',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: primaryGreen,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    autoPillText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Checkbox toggle
          InkWell(
            onTap: onCheckboxChanged != null ? () => onCheckboxChanged(!useAuto) : null,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: useAuto,
                    activeColor: primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: onCheckboxChanged,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Use Auto Value',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Child widget (Input Box / Fields)
          child,
        ],
      ),
    );
  }
}
