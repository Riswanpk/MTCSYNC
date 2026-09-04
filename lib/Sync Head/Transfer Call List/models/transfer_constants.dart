import 'package:flutter/material.dart';

const Color kTransferPrimaryBlue = Color(0xFF005BAC);
const Color kTransferPrimaryGreen = Color(0xFF8CC63F);
const Color kTransferSourceAccent = Color(0xFFFF5722);
const Color kTransferDestAccent = Color(0xFF2E7D32);

Color getCustomerAvatarColor(String name) {
  final colors = [
    const Color(0xFF005BAC),
    const Color(0xFF8CC63F),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF673AB7),
    const Color(0xFF3F51B5),
    const Color(0xFF009688),
    const Color(0xFFFF5722),
    const Color(0xFF795548),
    const Color(0xFF607D8B),
  ];
  if (name.isEmpty) return colors[0];
  final hash = name.codeUnits.fold(0, (prev, elem) => prev + elem);
  return colors[hash % colors.length];
}
