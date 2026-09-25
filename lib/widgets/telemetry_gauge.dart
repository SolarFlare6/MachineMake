import 'dart:math';
import 'package:flutter/material.dart';

class TelemetryGauge extends StatelessWidget {
  final double value; // 0.0 to 100.0 (or temp value)
  final String label; // "CPU", "RAM", "GPU", "TMP"
  final String displayValue; // "75%", "30°C"
  final Color color;
  final double size;

  const TelemetryGauge({
    super.key,
    required this.value,
    required this.label,
    required this.displayValue,
    required this.color,
    this.size = 62.0,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (value / 100.0).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: GaugeRingPainter(
              percent: percent,
              color: color,
              trackColor: color.withOpacity(0.15),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                displayValue,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GaugeRingPainter extends CustomPainter {
  final double percent;
  final Color color;
  final Color trackColor;

  GaugeRingPainter({
    required this.percent,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.085;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    // Active ring arc (starts from top -pi/2)
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * pi * percent;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant GaugeRingPainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.color != color;
  }
}
