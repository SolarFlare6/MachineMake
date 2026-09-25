import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

class DeviceProfileIcon extends StatelessWidget {
  final String iconKey; // 'quadruped', 'rpi', 'pico', 'generic'
  final double size;
  final Color color;
  final Color backgroundColor;

  const DeviceProfileIcon({
    super.key,
    required this.iconKey,
    this.size = 28,
    this.color = AppTheme.primaryOrange,
    this.backgroundColor = const Color(0x26F37032),
  });

  @override
  Widget build(BuildContext context) {
    Widget child;

    switch (iconKey.toLowerCase()) {
      case 'rpi':
      case 'raspberry_pi':
        child = SvgPicture.asset(
          'assets/Rpi icon.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        );
        break;

      case 'pico':
      case 'microchip':
      case 'microcontroller':
        child = SvgPicture.asset(
          'assets/microchip.svg',
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        );
        break;

      case 'quadruped':
      case 'robot':
        child = CustomPaint(
          size: Size(size, size),
          painter: QuadrupedIconPainter(color: color),
        );
        break;

      default:
        child = Icon(
          Icons.developer_board,
          size: size,
          color: color,
        );
        break;
    }

    return Container(
      width: size * 1.6,
      height: size * 1.6,
      padding: EdgeInsets.all(size * 0.25),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class QuadrupedIconPainter extends CustomPainter {
  final Color color;

  QuadrupedIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Body curve
    final bodyPath = Path();
    bodyPath.moveTo(w * 0.25, h * 0.45);
    bodyPath.quadraticBezierTo(w * 0.5, h * 0.35, w * 0.75, h * 0.45);
    canvas.drawPath(bodyPath, paint);

    // Head
    final headPath = Path();
    headPath.moveTo(w * 0.25, h * 0.45);
    headPath.cubicTo(w * 0.2, h * 0.3, w * 0.35, h * 0.2, w * 0.4, h * 0.3);
    canvas.drawPath(headPath, paint);

    // Front Left Leg
    final legFL = Path();
    legFL.moveTo(w * 0.3, h * 0.45);
    legFL.quadraticBezierTo(w * 0.2, h * 0.65, w * 0.25, h * 0.85);
    canvas.drawPath(legFL, paint);

    // Front Right Leg
    final legFR = Path();
    legFR.moveTo(w * 0.4, h * 0.45);
    legFR.quadraticBezierTo(w * 0.35, h * 0.65, w * 0.4, h * 0.85);
    canvas.drawPath(legFR, paint);

    // Back Left Leg
    final legBL = Path();
    legBL.moveTo(w * 0.65, h * 0.45);
    legBL.quadraticBezierTo(w * 0.6, h * 0.65, w * 0.65, h * 0.85);
    canvas.drawPath(legBL, paint);

    // Back Right Leg
    final legBR = Path();
    legBR.moveTo(w * 0.75, h * 0.45);
    legBR.quadraticBezierTo(w * 0.8, h * 0.65, w * 0.75, h * 0.85);
    canvas.drawPath(legBR, paint);
  }

  @override
  bool shouldRepaint(covariant QuadrupedIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
