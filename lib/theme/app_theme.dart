import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Color Palette
  static const Color darkBackground = Color(0xFF161719);
  static const Color darkSurface = Color(0xFF202126);
  static const Color darkCard = Color(0xFF24252A);
  static const Color darkBorder = Color(0xFF33353D);
  static const Color modalBackground = Color(0xFF1F1F22);

  // Vibrant Accents
  static const Color primaryOrange = Color(0xFFF37032);
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color textDarkButton = Color(0xFF1E1F23); // Button text on filled orange
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xFF9E9EA3);
  static const Color borderOrange = Color(0xFFF37032);
  static const Color borderLavender = Color(0xFFD4CBE5);

  // Telemetry Colors
  static const Color cpuOrange = Color(0xFFF37032);
  static const Color ramPink = Color(0xFFE02484);
  static const Color gpuCyan = Color(0xFF00E5FF);
  static const Color tempBlue = Color(0xFF00A8FF);

  static ThemeData get darkTheme {
    final baseTheme = ThemeData.dark();
    final exo2TextTheme = GoogleFonts.exo2TextTheme(baseTheme.textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: primaryOrange,
      colorScheme: const ColorScheme.dark(
        primary: primaryOrange,
        surface: darkSurface,
        onSurface: textWhite,
      ),
      fontFamily: GoogleFonts.exo2().fontFamily,
      textTheme: exo2TextTheme.apply(
        bodyColor: textWhite,
        displayColor: textWhite,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.exo2(
          color: textWhite,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: textDarkButton,
          minimumSize: const Size(double.infinity, 50),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.exo2(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryOrange,
          side: const BorderSide(color: borderOrange, width: 1.8),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.exo2(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class GridBackgroundPainter extends CustomPainter {
  final Color gridColor;
  final double step;

  GridBackgroundPainter({
    this.gridColor = const Color(0x1AF37032),
    this.step = 40.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
