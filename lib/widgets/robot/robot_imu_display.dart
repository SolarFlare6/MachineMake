import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Pitch, roll, and yaw orientation display gauges for robot IMU telemetry.
class RobotImuDisplay extends StatelessWidget {
  final double pitch; // degrees
  final double roll;  // degrees
  final double yaw;   // degrees

  const RobotImuDisplay({
    super.key,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.yaw = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.explore, color: AppTheme.primaryOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                'IMU Orientation',
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildAxisCard('Pitch', pitch, const Color(0xFF00E5FF))),
              const SizedBox(width: 10),
              Expanded(child: _buildAxisCard('Roll', roll, const Color(0xFFE02484))),
              const SizedBox(width: 10),
              Expanded(child: _buildAxisCard('Yaw', yaw, AppTheme.primaryOrange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAxisCard(String axis, double val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        children: [
          Text(
            axis,
            style: GoogleFonts.exo2(
              color: AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${val.toStringAsFixed(1)}°',
            style: GoogleFonts.exo2(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
