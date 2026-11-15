import 'package:flutter/material.dart';

/// Minimal placeholder loading page without animation overhead.
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.shrink(),
    );
  }
}

/// Zero-overhead pass-through wrapper kept for API compatibility.
/// Returns [child] directly without blocking overlays or animations.
class LoadingOverlayPage extends StatelessWidget {
  final Widget child;
  final Duration minLoadTime;

  const LoadingOverlayPage({
    super.key,
    required this.child,
    this.minLoadTime = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
