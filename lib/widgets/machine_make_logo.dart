import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class MachineMakeLogo extends StatelessWidget {
  final double logoHeight;
  final double fontSize;
  final bool isHorizontal;
  final bool showText;

  const MachineMakeLogo({
    super.key,
    this.logoHeight = 28,
    this.fontSize = 24,
    this.isHorizontal = true,
    this.showText = true,
  });

  @override
  Widget build(BuildContext context) {
    final logoSvg = SvgPicture.asset(
      'assets/Machine_Make_logo.svg',
      height: logoHeight,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => SizedBox(
        height: logoHeight,
        width: logoHeight * 1.2,
      ),
    );

    final textWidget = RichText(
      text: TextSpan(
        style: GoogleFonts.exo2(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        children: [
          const TextSpan(
            text: 'Machine',
            style: TextStyle(color: AppTheme.textWhite),
          ),
          TextSpan(
            text: 'Make',
            style: TextStyle(color: AppTheme.primaryOrange),
          ),
        ],
      ),
    );

    if (!showText) return logoSvg;

    if (isHorizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logoSvg,
          const SizedBox(width: 10),
          textWidget,
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logoSvg,
          const SizedBox(width: 0, height: 12),
          textWidget,
        ],
      );
    }
  }
}
