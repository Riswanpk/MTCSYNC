import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Format a Firestore date value for display.
String formatLeadDisplayDate(dynamic value, {bool isReminder = false}) {
  if (value == null) return 'N/A';
  if (value is Timestamp) {
    final format = isReminder ? 'yyyy-MM-dd hh:mm a' : 'yyyy-MM-dd';
    return DateFormat(format).format(value.toDate());
  }
  return value.toString();
}

/// A reusable text form field for editing lead details.
Widget leadEditField(
  String label,
  TextEditingController controller,
  bool isDark, {
  bool enabled = true,
  int maxLines = 1,
  TextInputType keyboardType = TextInputType.text,
  bool readOnly = false,
  VoidCallback? onTap,
  Widget? suffixIcon,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? const Color(0xFF23262F) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      validator: (val) {
        if ((label == 'Name' || label == 'Phone') && (val == null || val.trim().isEmpty)) {
          return '$label is required';
        }
        return null;
      },
    ),
  );
}

/// A reusable dropdown field for editing lead details.
Widget leadEditDropdown(
  String label,
  List<String> options,
  String? value,
  ValueChanged<String?> onChanged,
  bool isDark,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? const Color(0xFF23262F) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF23262F) : Colors.white,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

/// A card showing an icon, label, and value for the detail view grid.
Widget leadInfoCard(IconData icon, String label, String? value, bool isDark) {
  return Container(
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF23262F) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 6),
      ],
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: const Color(0xFF005BAC)),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
        const SizedBox(height: 4),
        Text(value ?? 'N/A', textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
      ],
    ),
  );
}

/// A tile showing an icon, title, and value widget for the detail view.
Widget leadInfoTile(IconData icon, String title, Widget valueWidget, bool isDark) {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF23262F) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        if (!isDark) BoxShadow(color: Colors.black12, blurRadius: 4),
      ],
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF005BAC)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 4),
              valueWidget,
            ],
          ),
        ),
      ],
    ),
  );
}
