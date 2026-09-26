import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Live battery gauge widget with voltage and health indicators.
class RobotBatteryBar extends StatelessWidget {
  final int percentage; // 0 - 100
  final double voltage; // e.g. 11.8 V
  final bool isCharging;

  const RobotBatteryBar({
    super.key,
    required this.percentage,
    this.voltage = 12.2,
    this.isCharging = false,
  });

  @override
  Widget build(BuildContext context) {
    Color barColor = const Color(0xFF00E676);
    if (percentage <= 20) {
      barColor = Colors.redAccent;
    } else if (percentage <= 50) {
      barColor = AppTheme.primaryOrange;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isCharging ? Icons.battery_charging_full : Icons.battery_full,
                    color: barColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Power System',
                    style: GoogleFonts.exo2(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Text(
                '${voltage.toStringAsFixed(1)} V · $percentage%',
                style: GoogleFonts.exo2(
                  color: barColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (percentage / 100.0).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppTheme.darkSurface,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}
