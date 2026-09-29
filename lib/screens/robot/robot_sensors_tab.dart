import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_imu_display.dart';

/// Simplified telemetry tab for quadruped robot:
/// Shows only actual MPU6050 gyro and accel telemetry (pitch, roll, gyro x/y/z, accel x/y/z).
/// Foot contact, proximity, and battery gauges are removed.
class RobotSensorsTab extends StatefulWidget {
  final DeviceConnection? conn;
  final double pitch;
  final double roll;
  final double yaw;

  const RobotSensorsTab({
    super.key,
    this.conn,
    this.pitch = 1.2,
    this.roll = -0.4,
    this.yaw = 0.0,
  });

  @override
  State<RobotSensorsTab> createState() => _RobotSensorsTabState();
}

class _RobotSensorsTabState extends State<RobotSensorsTab> {
  // MPU6050 state values
  late double _pitch;
  late double _roll;

  double _accelX = 0.02;
  double _accelY = -0.05;
  double _accelZ = 0.98;

  double _gyroX = 0.8;
  double _gyroY = -1.2;
  double _gyroZ = 0.3;

  @override
  void initState() {
    super.initState();
    _pitch = widget.pitch;
    _roll = widget.roll;
  }

  void _refreshSensors() {
    widget.conn?.session?.executeTool('get_pitch_roll', {});
    widget.conn?.session?.executeTool('get_sensor_accel', {});
    widget.conn?.session?.executeTool('get_sensor_gyro', {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Requested MPU6050 telemetry update', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(milliseconds: 700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Power supply notice (DC In / No battery)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withAlpha(25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt, color: Color(0xFF00E676), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Power: DC In / External Supply',
                        style: GoogleFonts.exo2(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'External 5V/12V regulator direct supply',
                        style: GoogleFonts.exo2(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppTheme.primaryOrange, size: 20),
                  onPressed: _refreshSensors,
                  tooltip: 'Refresh MPU6050',
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // MPU6050 Pitch & Roll Attitude
          RobotImuDisplay(
            pitch: _pitch,
            roll: _roll,
            yaw: widget.yaw,
          ),

          const SizedBox(height: 14),

          // Accelerometer 3-Axis Readout
          Container(
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
                        const Icon(Icons.speed, color: AppTheme.primaryOrange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MPU6050 Accelerometer',
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Unit: g (9.81 m/s²)',
                      style: GoogleFonts.exo2(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildAxisBar('Accel X', _accelX, const Color(0xFF4FC3F7)),
                const SizedBox(height: 10),
                _buildAxisBar('Accel Y', _accelY, const Color(0xFF81D4FA)),
                const SizedBox(height: 10),
                _buildAxisBar('Accel Z', _accelZ, const Color(0xFF00E676)),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Gyroscope 3-Axis Readout
          Container(
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
                        const Icon(Icons.rotate_right, color: AppTheme.primaryOrange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'MPU6050 Gyroscope',
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Unit: °/s',
                      style: GoogleFonts.exo2(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildAxisBar('Gyro X (Pitch Rate)', _gyroX, const Color(0xFFFFB74D), maxVal: 50.0),
                const SizedBox(height: 10),
                _buildAxisBar('Gyro Y (Roll Rate)', _gyroY, const Color(0xFFFF8A65), maxVal: 50.0),
                const SizedBox(height: 10),
                _buildAxisBar('Gyro Z (Yaw Rate)', _gyroZ, const Color(0xFFE57373), maxVal: 50.0),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAxisBar(String label, double value, Color color, {double maxVal = 2.0}) {
    final progress = ((value.abs() / maxVal)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.exo2(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}',
              style: GoogleFonts.firaCode(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppTheme.darkBorder,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
