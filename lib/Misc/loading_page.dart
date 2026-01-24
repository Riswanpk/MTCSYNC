import 'package:flutter/material.dart';
import '../widgets/home_widgets.dart';

/// Loading page displayed during navigation transitions.
/// Uses the shared RotatingLogo widget for consistent animation.
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF181A20) : Colors.white,
      body: const Center(
        child: RotatingLogo(),
      ),
    );
  }
}

/// A wrapper that shows a loading overlay on top while the child page loads.
/// This allows the actual page to start building in the background.
class LoadingOverlayPage extends StatefulWidget {
  final Widget child;
  final Duration minLoadTime;

  const LoadingOverlayPage({
    super.key,
    required this.child,
    this.minLoadTime =
        const Duration(milliseconds: 500), // loading overlay 500ms
  });

  @override
  State<LoadingOverlayPage> createState() => _LoadingOverlayPageState();
}

class _LoadingOverlayPageState extends State<LoadingOverlayPage> {
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _hideOverlayAfterDelay();
  }

  Future<void> _hideOverlayAfterDelay() async {
    await Future.delayed(widget.minLoadTime);
    if (mounted) {
      setState(() => _showOverlay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // The actual page loads underneath
        widget.child,
        // Loading overlay on top
        if (_showOverlay)
          AnimatedOpacity(
            opacity: _showOverlay ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              color: isDark ? const Color(0xFF181A20) : Colors.white,
              child: const Center(
                child: RotatingLogo(),
              ),
            ),
          ),
      ],
    );
  }
}
