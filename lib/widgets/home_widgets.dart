import 'package:flutter/material.dart';

/// A stylized button with neumorphic design, bounce animation, and responsive feedback.
class NeumorphicButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final TextStyle? textStyle;

  const NeumorphicButton({
    super.key,
    required this.onTap,
    this.onLongPress,
    required this.text,
    required this.color,
    required this.textColor,
    this.icon,
    this.textStyle,
  });

  @override
  State<NeumorphicButton> createState() => _NeumorphicButtonState();
}

class _NeumorphicButtonState extends State<NeumorphicButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
    _elevationAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _bounceController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _bounceController.reverse().then((_) => widget.onTap());
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _bounceController.reverse();
  }

  void _onLongPress() {
    setState(() => _isPressed = false);
    _bounceController.reverse().then((_) {
      if (widget.onLongPress != null) widget.onLongPress!();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
            child: GestureDetector(
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              onLongPress: widget.onLongPress != null ? _onLongPress : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(widget.color, Colors.white, 0.1)!,
                    widget.color,
                    Color.lerp(widget.color, Colors.black, 0.12)!,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  // Main colored shadow
                  BoxShadow(
                    color: widget.color
                        .withOpacity(0.5 * _elevationAnimation.value),
                    offset: Offset(0, 10 * _elevationAnimation.value),
                    blurRadius: 24 * _elevationAnimation.value,
                    spreadRadius: -2,
                  ),
                  // Soft dark shadow
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(0.25 * _elevationAnimation.value),
                    offset: Offset(0, 6 * _elevationAnimation.value),
                    blurRadius: 16 * _elevationAnimation.value,
                  ),
                  // Inner glow when pressed
                  if (_isPressed)
                    BoxShadow(
                      color: widget.color.withOpacity(0.3),
                      blurRadius: 4,
                      spreadRadius: -2,
                    ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(_isPressed ? 0.4 : 0.25),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: EdgeInsets.all(_isPressed ? 8 : 7),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withOpacity(_isPressed ? 0.25 : 0.18),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _isPressed
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.textColor,
                        size: _isPressed ? 19 : 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Flexible(
                    child: Text(
                      widget.text,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: widget.textStyle ??
                          TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: 0.6,
                            color: widget.textColor,
                            fontFamily: 'Montserrat',
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.25),
                                offset: const Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shows a loading dialog with a rotating logo.
Future<void> showLoadingDialog(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return const RotatingLogoDialog();
    },
  );
  await Future.delayed(const Duration(milliseconds: 200));
  Navigator.of(context, rootNavigator: true).pop();
}

/// Dialog widget displaying a rotating logo.
class RotatingLogoDialog extends StatelessWidget {
  const RotatingLogoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF181A20) : Colors.white,
      child: const Center(
        child: RotatingLogo(),
      ),
    );
  }
}

/// An animated rotating logo widget.
class RotatingLogo extends StatefulWidget {
  const RotatingLogo({super.key});

  @override
  State<RotatingLogo> createState() => _RotatingLogoState();
}

class _RotatingLogoState extends State<RotatingLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600), // slower rotation
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

/// Creates a fade transition route for page navigation.
Route fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 500),
  );
}

/// Decorative bubble widget used for background effects.
class DecorativeBubble extends StatelessWidget {
  final double size;
  final List<Color> colors;
  final List<double>? stops;

  const DecorativeBubble({
    super.key,
    required this.size,
    required this.colors,
    this.stops,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: colors,
          stops: stops,
        ),
      ),
    );
  }
}
