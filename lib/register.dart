import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'constant.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedBranch;

  bool _isLoading = false;
  String? _errorMessage;

  late AnimationController _controller;
  late Animation<double> _animationTop;
  late Animation<double> _animationBottom;
  late Animation<double> _swingAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _animationTop = Tween<double>(begin: -10, end: 10).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _animationBottom = Tween<double>(begin: 10, end: -10).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _swingAnimation = Tween<double>(begin: -0.15, end: 0.15).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await FirebaseFirestore.instance.collection(firebaseUsersCollection).doc(userCredential.user!.uid).set({
        'email': _emailController.text.trim(),
        'username': _usernameController.text.trim(),
        'role': 'sales',
        'branch': _selectedBranch,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = "Unexpected error occurred");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFF005BAC)),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black),
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
          // Top bubble
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
          // Bottom bubble
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
          // Form
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
                      AnimatedBuilder(
                        animation: _swingAnimation,
                        builder: (context, child) {
                          return Transform.rotate(
                            angle: _swingAnimation.value,
                            alignment: Alignment.topCenter,
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 90,
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration('Email', Icons.email),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter email';
                          if (!RegExp(r'\S+@\S+\.\S+').hasMatch(v)) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _usernameController,
                        decoration: _inputDecoration('Username', Icons.person),
                        validator: (v) => (v == null || v.isEmpty) ? 'Please enter username' : null,
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        value: _selectedBranch,
                        decoration: _inputDecoration('Branch', Icons.business),
                        items: ['KSD','TLY','VDK','CLT','WYND','PKTR','TRR','PMNA','PKD','TSR','EKM','PALA','KKM','TVM','CBE','UDP','BGR']
                            .map((branch) => DropdownMenuItem(value: branch, child: Text(branch)))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedBranch = value;
                          });
                        },
                        validator: (value) => value == null ? 'Please select a branch' : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _passwordController,
                        decoration: _inputDecoration('Password', Icons.lock),
                        obscureText: true,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter password';
                          if (v.length < 6) return 'Password must be at least 6 characters';
                          return null;
                        },
                      ),

                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 15),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 25),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF005BAC),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 5,
                          ),
                          onPressed: _isLoading ? null : _register,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'REGISTER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Already have an account? Login',
                          style: TextStyle(
                            color: Color(0xFF005BAC),
                            fontWeight: FontWeight.w600,
                          ),
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
