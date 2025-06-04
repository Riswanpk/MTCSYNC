import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  bool _isDarkMode = false;

  ThemeNotifier() {
    _loadTheme();
  }

  bool get isDarkMode => _isDarkMode;

  ThemeData get currentTheme => _isDarkMode
      ? ThemeData.dark().copyWith(
          colorScheme: ThemeData.dark().colorScheme.copyWith(
                primary: const Color(0xFF005BAC),
                secondary: const Color(0xFF8CC63F),
              ),
          scaffoldBackgroundColor: const Color(0xFF181A20),
        )
      : ThemeData.light().copyWith(
          colorScheme: ThemeData.light().colorScheme.copyWith(
                primary: const Color(0xFF005BAC),
                secondary: const Color(0xFF8CC63F),
              ),
          scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        );

  void toggleTheme(bool isDark) async {
    _isDarkMode = isDark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    notifyListeners();
  }
}

final ThemeData lightTheme = ThemeData.light();
final ThemeData darkTheme = ThemeData.dark().copyWith(
      colorScheme: ColorScheme.dark(
        background: Color(0xFF181A20),
        onBackground: Colors.white,
      ),
    );
final ThemeMode themeMode = ThemeMode.system;