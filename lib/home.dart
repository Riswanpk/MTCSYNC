import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'todo.dart';
import 'leads.dart';
import 'login.dart';
import 'settings.dart'; // Import the settings page
import 'feedback.dart'; // Add this import
import 'feedback_admin.dart'; // Add this import

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF005BAC);
    const Color primaryGreen = Color(0xFF8CC63F);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async => false, // Disable back button
      child: Scaffold(
        // Remove the appBar entirely
        endDrawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(
                  color: Color(0xFF005BAC),
                ),
                child: Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context); // Close the drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.feedback),
                title: const Text('Feedback'),
                onTap: () async {
                  Navigator.pop(context); // Close the drawer

                  // Get current user role
                  final user = FirebaseAuth.instance.currentUser;
                  String? role;
                  if (user != null) {
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                    role = userDoc.data()?['role'];
                  }

                  if (role == 'admin') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FeedbackAdminPage()),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FeedbackPage()),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log Out'),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (Route<dynamic> route) => false,
                  );
                },
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            // Animated top-right bubble
            Positioned(
              top: -120,
              right: -120,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF8CC63F), Color(0xFFB2E85F)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),

            // Animated bottom-left bubble
            Positioned(
              bottom: -120,
              left: -120,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF005BAC), Color(0xFF3383C7)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                ),
              ),
            ),

            // Burger button (top right)
            Positioned(
              top: 24,
              right: 16,
              child: Builder(
                builder: (context) => IconButton(
                  icon: Icon(Icons.menu, color: primaryBlue, size: 32),
                  onPressed: () {
                    Scaffold.of(context).openEndDrawer();
                  },
                  tooltip: 'Menu',
                ),
              ),
            ),

            // Main content (unchanged)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Replace Welcome! text with logo
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Image.asset(
                        'assets/images/logo.png', // Update path if needed
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 40),
                    NeumorphicButton(
                      onTap: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          final userDoc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .get();
                          final branch = userDoc.data()?['branch'];
                          if (branch != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LeadsPage(branch: branch),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Branch not found for user')),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User not logged in')),
                          );
                        }
                      },
                      text: 'Leads Follow Up',
                      color: primaryBlue, // Blue box
                      textColor: Colors.white, // White text
                      icon: Icons.people_alt_rounded,
                      textStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.normal, // Not bold
                        fontSize: 19,
                        letterSpacing: 1.1,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 25),
                    NeumorphicButton(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TodoPage()),
                        );
                      },
                      text: 'ToDo List',
                      color: primaryGreen, // Green box
                      textColor: Colors.white, // White text
                      icon: Icons.check_circle_outline_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Add this widget in your file (above your _HomePageState class or in a separate file)
class NeumorphicButton extends StatelessWidget {
  final VoidCallback onTap;
  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final TextStyle? textStyle;

  const NeumorphicButton({
    super.key,
    required this.onTap,
    required this.text,
    required this.color,
    required this.textColor,
    this.icon,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              offset: const Offset(4, 4),
              blurRadius: 14,
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.10),
              offset: const Offset(-4, -4),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor, size: 22),
              const SizedBox(width: 10),
            ],
            Text(
              text,
              style: textStyle ??
                  TextStyle(
                    fontWeight: FontWeight.normal, // Not bold
                    fontSize: 18,
                    letterSpacing: 1.1,
                    color: textColor,
                    fontFamily: 'Montserrat',
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
