import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'constant.dart';

/// App brand colors (matching home page)
const Color _primaryBlue = Color(0xFF005BAC);
const Color _primaryGreen = Color(0xFF8CC63F);

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  String? _selectedBranch;

  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch the current code from Firestore
      final codeSnap = await FirebaseFirestore.instance
          .collection('registration_codes')
          .doc('active')
          .get();
      final currentCode = codeSnap.data()?['code'];

      if (_codeController.text.trim() != currentCode) {
        setState(() {
          _errorMessage = "Invalid registration code.";
          _isLoading = false;
        });
        return;
      }

      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection(firebaseUsersCollection)
          .doc(userCredential.user!.uid)
          .set({
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

  InputDecoration _inputDecoration(String label, IconData icon,
      {Widget? suffixIcon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      prefixIcon: Icon(icon, color: _primaryBlue.withOpacity(0.7), size: 22),
      suffixIcon: suffixIcon,
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? Colors.white60 : Colors.black54,
        fontFamily: 'Montserrat',
        fontSize: 14,
      ),
      filled: true,
      fillColor: isDark
          ? Colors.white.withOpacity(0.08)
          : _primaryBlue.withOpacity(0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: (isDark ? Colors.white : _primaryBlue).withOpacity(0.12),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primaryGreen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Gradient background matching home page
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF0A1628),
                        const Color(0xFF0D2137),
                        const Color(0xFF0A1628),
                      ]
                    : [
                        _primaryBlue.withOpacity(0.08),
                        Colors.white,
                        _primaryGreen.withOpacity(0.10),
                      ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Decorative top-right bubble
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _primaryGreen.withOpacity(isDark ? 0.15 : 0.25),
                    _primaryGreen.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // Decorative bottom-left bubble
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _primaryBlue.withOpacity(isDark ? 0.2 : 0.2),
                    _primaryBlue.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo container (glass style matching home/login)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withOpacity(isDark ? 0.05 : 0.7),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryBlue
                                    .withOpacity(isDark ? 0.2 : 0.08),
                                blurRadius: 40,
                                offset: const Offset(0, 16),
                              ),
                              BoxShadow(
                                color: _primaryGreen
                                    .withOpacity(isDark ? 0.1 : 0.05),
                                blurRadius: 30,
                                offset: const Offset(-10, -10),
                              ),
                            ],
                            border: Border.all(
                              color: (isDark ? Colors.white : _primaryBlue)
                                  .withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Form card (glass-morphism style)
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withOpacity(isDark ? 0.06 : 0.85),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryBlue
                                    .withOpacity(isDark ? 0.15 : 0.06),
                                blurRadius: 30,
                                offset: const Offset(0, 12),
                              ),
                              BoxShadow(
                                color: Colors.black
                                    .withOpacity(isDark ? 0.3 : 0.04),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                            border: Border.all(
                              color: (isDark ? Colors.white : _primaryBlue)
                                  .withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Montserrat',
                                    color: isDark ? Colors.white : _primaryBlue,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Register to get started',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                    fontFamily: 'Montserrat',
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Email
                                TextFormField(
                                  controller: _emailController,
                                  decoration: _inputDecoration(
                                      'Email', Icons.email_outlined),
                                  keyboardType: TextInputType.emailAddress,
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    fontFamily: 'Montserrat',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Please enter email';
                                    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(v))
                                      return 'Enter a valid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Username
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: _inputDecoration(
                                      'Username', Icons.person_outline_rounded),
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    fontFamily: 'Montserrat',
                                  ),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Please enter username'
                                      : null,
                                ),
                                const SizedBox(height: 14),

                                // Branch dropdown
                                DropdownButtonFormField<String>(
                                  value: _selectedBranch,
                                  decoration: _inputDecoration(
                                      'Branch', Icons.business_outlined),
                                  dropdownColor: isDark
                                      ? const Color(0xFF1A2332)
                                      : Colors.white,
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    fontFamily: 'Montserrat',
                                    fontSize: 14,
                                  ),
                                  items: [
                                    'BGR',
                                    'CBE',
                                    'CHN',
                                    'CLT',
                                    'EKM',
                                    'JBL',
                                    'KKM',
                                    'KSD',
                                    'KTM',
                                    'PKD',
                                    'PKTR',
                                    'PMNA',
                                    'TRR',
                                    'TSR',
                                    'TLY',
                                    'TVM',
                                    'UDP',
                                    'VDK',
                                    'WYND',
                                  ]
                                      .map((branch) => DropdownMenuItem(
                                          value: branch, child: Text(branch)))
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedBranch = value;
                                    });
                                  },
                                  validator: (value) => value == null
                                      ? 'Please select a branch'
                                      : null,
                                ),
                                const SizedBox(height: 14),

                                // Password
                                TextFormField(
                                  controller: _passwordController,
                                  decoration: _inputDecoration(
                                    'Password',
                                    Icons.lock_outline_rounded,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: _primaryBlue.withOpacity(0.5),
                                        size: 22,
                                      ),
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    fontFamily: 'Montserrat',
                                  ),
                                  obscureText: _obscurePassword,
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Please enter password';
                                    if (v.length < 6)
                                      return 'Password must be at least 6 characters';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Registration code
                                TextFormField(
                                  controller: _codeController,
                                  decoration: _inputDecoration(
                                      'Registration Code',
                                      Icons.vpn_key_outlined),
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    fontFamily: 'Montserrat',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Enter registration code';
                                    if (v.length != 4)
                                      return 'Code must be 4 digits';
                                    return null;
                                  },
                                ),

                                // Error message
                                if (_errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 12, bottom: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.redAccent.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline,
                                              color: Colors.redAccent,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 22),

                                // Register button (neumorphic style)
                                SizedBox(
                                  width: double.infinity,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.lerp(_primaryGreen,
                                              Colors.white, 0.1)!,
                                          _primaryGreen,
                                          Color.lerp(_primaryGreen,
                                              Colors.black, 0.12)!,
                                        ],
                                        stops: const [0.0, 0.5, 1.0],
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _primaryGreen.withOpacity(0.4),
                                          offset: const Offset(0, 8),
                                          blurRadius: 20,
                                          spreadRadius: -2,
                                        ),
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          offset: const Offset(0, 4),
                                          blurRadius: 12,
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.25),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(22),
                                        onTap: _isLoading ? null : _register,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 18),
                                          child: Center(
                                            child: _isLoading
                                                ? const SizedBox(
                                                    height: 22,
                                                    width: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(7),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(
                                                                  0.18),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                      0.1),
                                                              blurRadius: 4,
                                                              offset:
                                                                  const Offset(
                                                                      0, 2),
                                                            ),
                                                          ],
                                                        ),
                                                        child: const Icon(
                                                          Icons
                                                              .person_add_alt_1_rounded,
                                                          color: Colors.white,
                                                          size: 20,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        'REGISTER',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 16,
                                                          letterSpacing: 1.2,
                                                          color: Colors.white,
                                                          fontFamily:
                                                              'Montserrat',
                                                          shadows: [
                                                            Shadow(
                                                              color: Colors
                                                                  .black
                                                                  .withOpacity(
                                                                      0.25),
                                                              offset:
                                                                  const Offset(
                                                                      0, 1),
                                                              blurRadius: 3,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // Back to login link
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontFamily: 'Montserrat',
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                      children: const [
                                        TextSpan(
                                            text: 'Already have an account? '),
                                        TextSpan(
                                          text: 'Login',
                                          style: TextStyle(
                                            color: _primaryBlue,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
