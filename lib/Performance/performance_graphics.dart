import 'package:flutter/material.dart';
import 'dart:math';

class PerformanceRadarChart extends StatelessWidget {
  final int attendance;
  final int dress;
  final int attitude;
  final int meeting;

  const PerformanceRadarChart({
    super.key,
    required this.attendance,
    required this.dress,
    required this.attitude,
    required this.meeting,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = [
      {'label': 'Attendance', 'value': attendance.toDouble(), 'max': 20.0},
      {'label': 'Dress Code', 'value': dress.toDouble(), 'max': 20.0},
      {'label': 'Attitude', 'value': attitude.toDouble(), 'max': 20.0},
      {'label': 'Meeting', 'value': meeting.toDouble(), 'max': 10.0},
    ];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Performance Breakdown',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 280, 
            height: 260, 
            child: CustomPaint(
              painter: RadarChartPainter(metrics: metrics),
            ),
          ),
        ],
      ),
    );
  }

  Color _metricColor(String label) {
    switch (label) {
      case 'Attendance':
        return const Color.fromARGB(255, 0, 0, 0);
      case 'Dress Code':
        return const Color.fromARGB(255, 0, 0, 0);
      case 'Attitude':
        return const Color.fromARGB(255, 0, 0, 0);
      case 'Meeting':
        return const Color.fromARGB(255, 0, 0, 0);
      default:
        return Colors.grey;
    }
  }
}

class RadarChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> metrics;
  RadarChartPainter({required this.metrics});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = const Color.fromARGB(255, 255, 255, 255).withOpacity(0.25)
      ..style = PaintingStyle.stroke;
    final Paint outlinePaint = Paint()
      ..color = Colors.grey.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Paint fillPaint = Paint()
      ..color = const Color.fromARGB(255, 247, 40, 40).withOpacity(0.18)
      ..style = PaintingStyle.fill;
    final Paint linePaint = Paint()
      ..color = const Color.fromARGB(255, 0, 0, 0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final int count = metrics.length;
    final double angle = 2 * pi / count;
    final double radius = size.width / 2 * 0.82;
    final Offset center = Offset(size.width / 2, size.height / 2);

    // Draw grid
    for (int i = 1; i <= 4; i++) {
      final double r = radius * (i / 4);
      final path = Path();
      for (int j = 0; j < count; j++) {
        final x = center.dx + r * cos(angle * j - pi / 2);
        final y = center.dy + r * sin(angle * j - pi / 2);
        if (j == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Draw outline
    final outlinePath = Path();
    for (int j = 0; j < count; j++) {
      final x = center.dx + radius * cos(angle * j - pi / 2);
      final y = center.dy + radius * sin(angle * j - pi / 2);
      if (j == 0) {
        outlinePath.moveTo(x, y);
      } else {
        outlinePath.lineTo(x, y);
      }
    }
    outlinePath.close();
    canvas.drawPath(outlinePath, outlinePaint);

    // Draw data
    final dataPath = Path();
    for (int j = 0; j < count; j++) {
      final value = metrics[j]['value'] as double;
      final max = metrics[j]['max'] as double;
      final percent = value / max;
      final r = radius * percent;
      final x = center.dx + r * cos(angle * j - pi / 2);
      final y = center.dy + r * sin(angle * j - pi / 2);
      if (j == 0) {
        dataPath.moveTo(x, y);
      } else {
        dataPath.lineTo(x, y);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, linePaint);

    // Draw axis lines and labels
    final textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87);
    for (int j = 0; j < count; j++) {
      final x = center.dx + radius * cos(angle * j - pi / 2);
      final y = center.dy + radius * sin(angle * j - pi / 2);
      canvas.drawLine(center, Offset(x, y), gridPaint);

      // Draw label
      final label = metrics[j]['label'] as String;
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      final labelOffset = Offset(
        x + (x - center.dx) * 0.12 - tp.width / 2,
        y + (y - center.dy) * 0.12 - tp.height / 2,
      );
      tp.paint(canvas, labelOffset);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}