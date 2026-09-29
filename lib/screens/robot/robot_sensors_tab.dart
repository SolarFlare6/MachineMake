import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_imu_display.dart';
import '../../widgets/robot/robot_battery_bar.dart';

/// Sensor telemetry tab for quadruped robot: IMU, foot contact sensors, proximity, and battery.
class RobotSensorsTab extends StatelessWidget {
  final double pitch;
  final double roll;
  final double yaw;
  final int? batteryLevel;
  final double? batteryVoltage;

  const RobotSensorsTab({
    super.key,
    this.pitch = 1.2,
    this.roll = -0.4,
    this.yaw = 42.8,
    this.batteryLevel,
    this.batteryVoltage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Power / Battery Indicator
          if (batteryLevel != null) ...[
            RobotBatteryBar(
              percentage: batteryLevel!,
              voltage: batteryVoltage ?? 12.0,
            ),
            const SizedBox(height: 16),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.power,
                      color: Color(0xFF00E676),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Power: DC / External Supply',
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Direct external power; no battery telemetry circuit',
                          style: GoogleFonts.exo2(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // IMU Orientation
          RobotImuDisplay(
            pitch: pitch,
            roll: roll,
            yaw: yaw,
          ),
          const SizedBox(height: 16),

          // Foot Contact Pressure (Quadruped 4 feet)
          Container(
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
                    const Icon(Icons.touch_app, color: AppTheme.primaryOrange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Foot Contact & Ground Force',
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
                    Expanded(child: _buildFootSensor('Front Left', true, 14.2)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildFootSensor('Front Right', true, 13.8)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildFootSensor('Rear Left', true, 16.1)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildFootSensor('Rear Right', true, 15.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Ultrasonic Proximity Grid
          Container(
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
                    const Icon(Icons.radar, color: AppTheme.primaryOrange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Obstacle Proximity',
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
                    Expanded(child: _buildProxCard('Front Range', '142 cm', Colors.greenAccent)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildProxCard('Left Flank', '85 cm', Colors.greenAccent)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildProxCard('Right Flank', '92 cm', Colors.greenAccent)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootSensor(String name, bool inContact, double loadN) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: inContact ? const Color(0xFF00E676).withAlpha(120) : AppTheme.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: GoogleFonts.exo2(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: inContact ? const Color(0xFF00E676) : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${loadN.toStringAsFixed(1)} N',
            style: GoogleFonts.exo2(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProxCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.exo2(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.exo2(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
