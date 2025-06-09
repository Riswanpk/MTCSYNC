import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'todo.dart';
import 'leads.dart';
import 'login.dart';
import 'settings.dart'; // Import the settings page
import 'feedback.dart'; // Add this import
import 'feedback_admin.dart'; // Add this import
import 'dashboard.dart'; // Import the dashboard page
import 'manageusers.dart'; // Add this import
import 'customer_list.dart'; // Import the customer list page
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  File? _profileImage;
  String? _profileImagePath;

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

    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_image_path');
    if (path != null && File(path).existsSync()) {
      setState(() {
        _profileImagePath = path;
        _profileImage = File(path);
      });
    } else if (path != null) {
      // If file doesn't exist, remove the path from prefs
      await prefs.remove('profile_image_path');
      setState(() {
        _profileImagePath = null;
        _profileImage = null;
      });
    }
  }

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
        _profileImagePath = pickedFile.path;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_path', pickedFile.path);
    }
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

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).get(),
      builder: (context, snapshot) {
        String? role;
        String? username;
        String? branch;
        if (snapshot.hasData) {
          role = snapshot.data?.get('role');
          username = snapshot.data?.get('username') ?? snapshot.data?.get('email') ?? 'User';
          branch = snapshot.data?.get('branch');
        }
        return WillPopScope(
          onWillPop: () async => false, // Disable back button
          child: Scaffold(
            // Remove the appBar entirely
            endDrawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF005BAC), Color(0xFF3383C7)], // Profile blue gradient
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _pickProfileImage,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: Colors.white,
                                backgroundImage: (_profileImage != null)
                                    ? FileImage(_profileImage!)
                                    : null,
                                child: (_profileImage == null)
                                    ? const Icon(Icons.account_circle, size: 38, color: Color(0xFF005BAC))
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      branch ?? '',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings, color: Color(0xFF005BAC)), // Blue for Settings
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
                    leading: const Icon(Icons.feedback, color: Color(0xFF8CC63F)), // Green for Feedback
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
                  // Add Manage Users option for admin
                  if (role == 'admin')
                    ListTile(
                      leading: const Icon(Icons.manage_accounts, color: Colors.deepPurple), // Purple for Manage Users
                      title: const Text('Manage Users'),
                      onTap: () {
                        Navigator.pop(context); // Close the drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ManageUsersPage()),
                        );
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red), // Red for Log Out
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 160,
                            height: 160,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Responsive grid of buttons
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.center,
                          children: [
                            SizedBox(
                              width: 140,
                              height: 56, // Set a fixed height for all cards
                              child: NeumorphicButton(
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
                                text: 'Leads',
                                color: primaryBlue,
                                textColor: Colors.white,
                                icon: Icons.people_alt_rounded,
                                textStyle: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.normal,
                                  fontSize: 17,
                                  letterSpacing: 1.1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              height: 56, // Set a fixed height for all cards
                              child: NeumorphicButton(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const TodoPage()),
                                  );
                                },
                                text: 'ToDo List',
                                color: primaryGreen,
                                textColor: Colors.white,
                                icon: Icons.check_circle_outline_rounded,
                                textStyle: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.normal,
                                  fontSize: 17, // Match Leads button font size
                                  letterSpacing: 1.1,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            // Only show Dashboard button for admin or manager, not for sales
                            if (role == 'admin' || role == 'manager')
                              SizedBox(
                                width: 80,
                                height: 56, // Set a fixed height for all cards
                                child: NeumorphicButton(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const DashboardPage()),
                                    );
                                  },
                                  text: '',
                                  color: Colors.deepPurple,
                                  textColor: Colors.white,
                                  icon: Icons.dashboard_rounded,
                                ),
                              ),
                            // For sales, make the Customer List button take the full row
                            if (role == 'sales')
                              SizedBox(
                                width: 290,
                                height: 56,
                                child: NeumorphicButton(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const CustomerListPage()),
                                    );
                                  },
                                  text: 'Customer List',
                                  color: Colors.teal,
                                  textColor: Colors.white,
                                  icon: Icons.people_outline,
                                  textStyle: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontWeight: FontWeight.normal,
                                    fontSize: 17, // Match Leads button font size
                                    letterSpacing: 1.1,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            // For admin/manager, keep the original width
                            if (role == 'admin' || role == 'manager')
                              SizedBox(
                                width: 200,
                                height: 56,
                                child: NeumorphicButton(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const CustomerListPage()),
                                    );
                                  },
                                  text: 'Customer List',
                                  color: Colors.teal,
                                  textColor: Colors.white,
                                  icon: Icons.people_outline,
                                  textStyle: const TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontWeight: FontWeight.normal,
                                    fontSize: 17, // Match Leads button font size
                                    letterSpacing: 1.1,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
        padding: const EdgeInsets.symmetric(vertical: 14), // Slightly reduced padding
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
              Icon(icon, color: textColor, size: 20), // Slightly smaller icon
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: textStyle ??
                    TextStyle(
                      fontWeight: FontWeight.normal,
                      fontSize: 15, // Reduced font size
                      letterSpacing: 1.1,
                      color: textColor,
                      fontFamily: 'Montserrat',
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
