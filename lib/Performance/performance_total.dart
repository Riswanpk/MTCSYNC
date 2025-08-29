import 'package:flutter/material.dart';
import 'dart:math';

class TotalScoreGauge extends StatelessWidget {
  final int totalScore;
  final bool lateReduced;
  final bool notApprovedReduced;
  final List<String> dressReasons;
  final List<String> attitudeReasons;
  final bool meetingReduced;

  const TotalScoreGauge({
    super.key,
    required this.totalScore,
    required this.lateReduced,
    required this.notApprovedReduced,
    required this.dressReasons,
    required this.attitudeReasons,
    required this.meetingReduced,
  });

  @override
  Widget build(BuildContext context) {
    final double percent = totalScore / 70.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        Text(
          'Total Score',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                fontFamily: 'PTSans',
              ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: 250,
          height: 140,
          child: CustomPaint(
            painter: _GaugePainter(
              percent: percent,
              score: totalScore,
            ),
          ),
        ),
        const SizedBox(height: 8), // Small space after gauge
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percent;
  final int score;

  _GaugePainter({required this.percent, required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 16;
    final startAngle = pi;
    final sweepAngle = pi;

    // Segments colors
    final segments = [
      {'color': Colors.red, 'range': 0.25},     // Poor
      {'color': Colors.orange, 'range': 0.25},  // Fair
      {'color': Colors.yellow[700]!, 'range': 0.25}, // Good
      {'color': Colors.green, 'range': 0.25},   // Excellent
    ];

    double currentStart = startAngle;
    for (var seg in segments) {
      final paint = Paint()
        ..color = seg['color'] as Color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 20
        ..strokeCap = StrokeCap.butt;

      final segSweep = sweepAngle * (seg['range'] as double);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          currentStart, segSweep, false, paint);

      currentStart += segSweep;
    }

    // Labels
    final labels = ['POOR', 'FAIR', 'GOOD', 'EXCELLENT'];
    final labelAngles = [pi, 3 * pi / 4, pi / 2, pi / 4];
    final labelStyle = const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87);

    for (int i = 0; i < labels.length; i++) {
      final angle = labelAngles[i];
      final labelOffset = Offset(
        center.dx + (radius + 22) * cos(angle),
        center.dy + (radius + 22) * sin(angle) - 10,
      );
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, labelOffset - Offset(tp.width / 2, 0));
    }

    // Score number
    final scoreStyle = const TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    );
    final scoreTp = TextPainter(
      text: TextSpan(text: '$score', style: scoreStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    scoreTp.paint(canvas, center - Offset(scoreTp.width / 2, 70));

    // Pointer
    final pointerAngle = pi * percent;
    final pointerLength = radius - 12;
    final pointerPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final pointerEnd = Offset(
      center.dx + pointerLength * cos(pointerAngle + pi),
      center.dy + pointerLength * sin(pointerAngle + pi),
    );
    canvas.drawLine(center, pointerEnd, pointerPaint);

    // Pointer circle
    final circlePaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 18, circlePaint);
    final dotPaint = Paint()..color = Colors.black;
    canvas.drawCircle(center, 7, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
