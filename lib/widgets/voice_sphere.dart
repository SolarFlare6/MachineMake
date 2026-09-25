import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';

class VoiceSphere extends StatefulWidget {
  const VoiceSphere({super.key, this.size = 220});
  final double size;

  @override
  State<VoiceSphere> createState() => _VoiceSphereState();
}

class _VoiceSphereState extends State<VoiceSphere>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      if (mounted) {
        setState(() => _elapsed = d.inMilliseconds.toDouble());
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _SpherePainter(_elapsed),
      ),
    );
  }
}

class _SpherePainter extends CustomPainter {
  _SpherePainter(this.t);
  final double t;

  static final List<List<double>> _pts = _buildSphere(500);

  static List<List<double>> _buildSphere(int n) {
    final phi = (1 + sqrt(5)) / 2;
    return List.generate(n, (i) {
      final theta = acos(1 - (2 * (i + 0.5)) / n);
      final a = 2 * pi * i / phi;
      return [sin(theta) * cos(a), sin(theta) * sin(a), cos(theta)];
    });
  }

  // Simulated voice reactivity bands
  Map<String, double> _voice() {
    final s = t / 1000;
    final breath = 0.3 + 0.25 * sin(s * 0.5);
    final syllable = pow(max(0.0, sin(s * 3.8 * pi * 2)), 2).toDouble();
    final phrase = pow(max(0.0, sin(s * 0.36) * sin(s * 0.19)), 0.6).toDouble();
    final pop = pow(max(0.0, sin(s * 7.3)), 14).toDouble();
    return {
      'bass': (breath * phrase * 0.8 + pop * 0.2).clamp(0, 1),
      'mid': (phrase * syllable * 0.8 + pop * 0.5).clamp(0, 1),
      'treble': (syllable * 0.6 * phrase + pop * 0.9).clamp(0, 1),
      'overall': (breath * phrase * syllable + pop * 0.35).clamp(0, 1),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final v = _voice();
    final bass = v['bass']!;
    final mid = v['mid']!;
    final treble = v['treble']!;
    final overall = v['overall']!;

    final baseR = size.width * 0.32;
    final breathe = sin(t * 0.0015) * 6;
    final radius = baseR + breathe + bass * baseR * 0.35;
    final ry = t * 0.0003 + mid * t * 0.0001;
    final rx = 0.28 + sin(t * 0.0003) * 0.1;

    // Background glow radial
    final bgPaint = Paint()
      ..shader = RadialGradient(colors: [
        Color.fromRGBO(243, 112, 50, 0.15 + overall * 0.25),
        const Color(0x00000000),
      ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius * 1.6));
    canvas.drawCircle(Offset(cx, cy), radius * 1.6, bgPaint);

    // Project 3D particles onto 2D viewport
    final projected = <Map<String, double>>[];
    for (final p in _pts) {
      // rotateY
      var x = p[0] * cos(ry) + p[2] * sin(ry);
      var y = p[1];
      var z = -p[0] * sin(ry) + p[2] * cos(ry);
      // rotateX
      final y2 = y * cos(rx) - z * sin(rx);
      final z2 = y * sin(rx) + z * cos(rx);
      y = y2;
      z = z2;

      final fov = 400.0;
      final persp = fov / (fov + z * radius);
      projected.add({
        'sx': cx + x * radius * persp,
        'sy': cy + y * radius * persp,
        'depth': z,
        'persp': persp,
      });
    }

    projected.sort((a, b) => a['depth']!.compareTo(b['depth']!));

    for (final p in projected) {
      final depth = p['depth']!;
      final dt = (depth + 1) / 2;
      final dot = (0.7 + p['persp']! * 0.9) + overall * 2.0;

      final r = (200 + dt * 55 + bass * 20).clamp(0, 255).toInt();
      final g = (70 + dt * 80 + treble * 40).clamp(0, 255).toInt();
      final b = (20 + dt * 30).clamp(0, 255).toInt();
      final a = (0.2 + dt * 0.7 + (bass + treble) * 0.1).clamp(0.0, 1.0);

      if (depth > 0.5 && overall > 0.02) {
        final ha = (depth - 0.5) * overall * 0.35;
        canvas.drawCircle(
          Offset(p['sx']!, p['sy']!),
          dot * 2.5,
          Paint()..color = Color.fromRGBO(243, 112, 50, ha),
        );
      }

      canvas.drawCircle(
        Offset(p['sx']!, p['sy']!),
        dot,
        Paint()..color = Color.fromRGBO(r, g, b, a),
      );
    }

    // Core glow center
    final corePaint = Paint()
      ..shader = RadialGradient(colors: [
        Color.fromRGBO(255, 200, 150, (0.12 + overall * 0.35).clamp(0, 1)),
        const Color(0x00000000),
      ]).createShader(Rect.fromCircle(
          center: Offset(cx, cy), radius: radius * 0.45 + overall * 20));
    canvas.drawCircle(Offset(cx, cy), radius * 0.45 + overall * 20, corePaint);

    // Outer contour line (smooth pulsating organic border matching image)
    final borderPath = Path();
    const steps = 60;
    for (int i = 0; i <= steps; i++) {
      final angle = (i / steps) * 2 * pi;
      final n = sin(angle * 7 + t * 0.003) * 3 + cos(angle * 5 - t * 0.002) * 2;
      final r = radius * 1.12 + n + bass * 5;
      final px = cx + cos(angle) * r;
      final py = cy + sin(angle) * r;
      if (i == 0) {
        borderPath.moveTo(px, py);
      } else {
        borderPath.lineTo(px, py);
      }
    }
    borderPath.close();

    final borderPaint = Paint()
      ..color = AppTheme.primaryOrange.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(_SpherePainter old) => true;
}
