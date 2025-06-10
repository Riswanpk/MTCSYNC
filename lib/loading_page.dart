import 'package:flutter/material.dart';

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: const Center(
        child: _RotatingLogo(),
      ),
    );
  }
}

class _RotatingLogo extends StatefulWidget {
  const _RotatingLogo();

  @override
  State<_RotatingLogo> createState() => _RotatingLogoState();
}

class _RotatingLogoState extends State<_RotatingLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_controller.value * 2 * 3.1415926535),
          child: child,
        );
      },
      child: Image.asset(
        'assets/images/logo.png',
        width: 200,
        height: 200,
      ),
    );
  }
}