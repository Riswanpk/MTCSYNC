import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home.dart';

import 'Misc/register.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _rememberMe = false;

  late AnimationController _controller;
  late Animation<double> _animationTop;
  late Animation<double> _animationBottom;

  static const String _kRememberMeKey = 'remember_me_key';
  static const String _kEmailKey = 'email_key';
  static const String _kPasswordKey = 'password_key';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _animationTop = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _animationBottom = Tween<double>(begin: 10, end: -10).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _loadCredentials();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_kRememberMeKey) ?? false;
      if (!mounted) return;
      setState(() {
        _rememberMe = rememberMe;
        if (_rememberMe) {
          _emailController.text = prefs.getString(_kEmailKey) ?? '';
          _passwordController.text = prefs.getString(_kPasswordKey) ?? '';
        }
      });
    } catch (e) {
      debugPrint("Error loading credentials: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Save credentials if "Remember Me" is checked
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kRememberMeKey, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_kEmailKey, _emailController.text.trim());
        await prefs.setString(_kPasswordKey, _passwordController.text.trim());
      } else {
        await prefs.remove(_kEmailKey);
        await prefs.remove(_kPasswordKey);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() {
        _errorMessage = 'Unexpected error occurred';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    String? dialogError;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Enter your email',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        dialogError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final email = emailController.text.trim();
                    if (email.isEmpty) {
                      setState(() {
                        dialogError = 'Please enter your email';
                      });
                      return;
                    }
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password reset email sent!')),
                      );
                    } on FirebaseAuthException catch (e) {
                      setState(() {
                        dialogError = e.message ?? 'Failed to send reset email';
                      });
                    } catch (_) {
                      setState(() {
                        dialogError = 'Unexpected error occurred';
                      });
                    }
                  },
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFF005BAC)),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black), // Ensure label text is black
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF8CC63F), width: 2),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Top-right animated bubble
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Positioned(
                top: -120 + _animationTop.value,
                right: -120 + _animationTop.value,
                child: child!,
              );
            },
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

          // Bottom-left animated bubble
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Positioned(
                bottom: -120 + _animationBottom.value,
                left: -120 + _animationBottom.value,
                child: child!,
              );
            },
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

          // Login form
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  color: Colors.white.withOpacity(0.85),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/logo.png', height: 90),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration('Email', Icons.email),
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.black),
                        validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _passwordController,
                        decoration: _inputDecoration('Password', Icons.lock),
                        style: const TextStyle(color: Colors.black),
                        obscureText: true,
                        validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      CheckboxListTile(
                        title: const Text("Remember Me", style: TextStyle(color: Colors.black)),
                        value: _rememberMe,
                        onChanged: (newValue) {
                          setState(() {
                            _rememberMe = newValue!;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF005BAC),
                      ),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF005BAC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 5,
                          ),
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'LOGIN',
                                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 16),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _showForgotPasswordDialog,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: Color(0xFF8CC63F),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterPage()),
                          );
                        },
                        child: const Text(
                          'Don\'t have an account? Register',
                          style: TextStyle(color: Color(0xFF005BAC), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
