import 'package:flutter/services.dart';

/// Utilities and formatters for phone numbers in Supersale.
class SupersalePhoneUtils {
  /// Extracts digits, strips leading 91 country code if present, and takes up to 10 digits from left to right.
  static String extract10Digits(String input) {
    String digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('91') && digits.length > 10) {
      digits = digits.substring(2);
    }
    if (digits.length <= 10) return digits;
    return digits.substring(0, 10);
  }

  /// Formats raw digits to the 10-digit phone string format.
  static String formatTo10Digits(String input) {
    return extract10Digits(input);
  }
}

/// A [TextInputFormatter] that extracts up to 10 digits, stripping any leading country code '91' if pasted.
class TenDigitPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final formatted = SupersalePhoneUtils.extract10Digits(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
