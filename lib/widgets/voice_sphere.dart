import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/app_theme.dart';

class VoiceSphere extends StatefulWidget {
  const VoiceSphere({
    super.key,
    this.size = 220,
    this.audioLevel = 0.0,
    this.isListening = false,
  });

  final double size;

  /// Normalized audio input level from microphone (0.0 to 1.0).
  final double audioLevel;

  /// Whether voice recognition / listening is currently active.
  final bool isListening;

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
        painter: _SpherePainter(
          _elapsed,
          audioLevel: widget.audioLevel,
          isListening: widget.isListening,
        ),
      ),
    );
  }
}

class _SpherePainter extends CustomPainter {
  _SpherePainter(
    this.t, {
    this.audioLevel = 0.0,
    this.isListening = false,
  });

  final double t;
  final double audioLevel;
  final bool isListening;

  static final List<List<double>> _pts = _buildSphere(500);

  static List<List<double>> _buildSphere(int n) {
    final phi = (1 + sqrt(5)) / 2;
    return List.generate(n, (i) {
      final theta = acos(1 - (2 * (i + 0.5)) / n);
      final a = 2 * pi * i / phi;
      return [sin(theta) * cos(a), sin(theta) * sin(a), cos(theta)];
    });
  }

  // Voice reactivity bands based on microphone audio level + ambient breathing
  Map<String, double> _voice() {
    final s = t / 1000;
    final breath = 0.25 + 0.15 * sin(s * 0.5);

    final mic = audioLevel.clamp(0.0, 1.0);
    final hasVoice = isListening && mic > 0.03;

    // React strongly to real voice volume, fall back to organic idle pulse
    final overall = hasVoice
        ? (mic * 1.35 + 0.08).clamp(0.0, 1.0)
        : (isListening ? (breath * 0.45).clamp(0.0, 1.0) : 0.15);

    final bass = hasVoice
        ? (mic * 1.5).clamp(0.0, 1.0)
        : (isListening ? breath * 0.35 : 0.1);

    final mid = hasVoice
        ? (mic * 1.15).clamp(0.0, 1.0)
        : (isListening ? breath * 0.3 : 0.1);

    final treble = hasVoice
        ? (mic * 0.95).clamp(0.0, 1.0)
        : (isListening ? breath * 0.25 : 0.08);

    return {
      'bass': bass,
      'mid': mid,
      'treble': treble,
      'overall': overall,
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

    final baseR = size.width * 0.30;
    final breathe = sin(t * 0.0015) * 5;
    // Sphere expands when the user speaks!
    final radius = baseR + breathe + bass * baseR * 0.45;
    final ry = t * 0.0003 + (mid + overall) * t * 0.00015;
    final rx = 0.28 + sin(t * 0.0003) * 0.1;

    // Background glow radial
    final bgPaint = Paint()
      ..shader = RadialGradient(colors: [
        Color.fromRGBO(243, 112, 50, (0.12 + overall * 0.38).clamp(0.0, 1.0)),
        const Color(0x00000000),
      ]).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius * 1.65));
    canvas.drawCircle(Offset(cx, cy), radius * 1.65, bgPaint);

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
      final dot = (0.7 + p['persp']! * 0.9) + overall * 2.8;

      final r = (200 + dt * 55 + bass * 25).clamp(0, 255).toInt();
      final g = (70 + dt * 80 + treble * 50).clamp(0, 255).toInt();
      final b = (20 + dt * 30).clamp(0, 255).toInt();
      final a = (0.2 + dt * 0.7 + (bass + treble) * 0.15).clamp(0.0, 1.0);

      if (depth > 0.5 && overall > 0.02) {
        final ha = (depth - 0.5) * overall * 0.4;
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
        Color.fromRGBO(255, 200, 150, (0.12 + overall * 0.45).clamp(0.0, 1.0)),
        const Color(0x00000000),
      ]).createShader(Rect.fromCircle(
          center: Offset(cx, cy), radius: radius * 0.45 + overall * 24));
    canvas.drawCircle(
        Offset(cx, cy), radius * 0.45 + overall * 24, corePaint);

    // Outer contour line (smooth pulsating organic border reacting to audio)
    final borderPath = Path();
    const steps = 60;
    for (int i = 0; i <= steps; i++) {
      final angle = (i / steps) * 2 * pi;
      final n = sin(angle * 7 + t * 0.003) * (3 + bass * 8) +
          cos(angle * 5 - t * 0.002) * (2 + bass * 6);
      final r = radius * 1.12 + n + bass * 12;
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
      ..color = AppTheme.primaryOrange
          .withValues(alpha: (0.7 + overall * 0.3).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + overall * 1.2;

    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(_SpherePainter old) => true;
}
