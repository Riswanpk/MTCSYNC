// splash_screen.dart
import 'package:flutter/material.dart';
import 'home.dart'; // Import your home.dart file

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()), // Navigate to HomePage
      );
    });

    return Scaffold(
      body: Center(
        child: Image.asset(
          'assets/images/logo.png', // Ensure the path matches your assets folder
          width: 200,
        ),
      ),
    );
  }
}
