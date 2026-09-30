import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_imu_display.dart';

/// Telemetry tab for the quadruped robot:
/// - MPU6050 Gyro & Accel attitude telemetry cards
/// - Real-time pitch, roll, and yaw visualization
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
  // ── MPU6050 Telemetry State ───────────────────────────────────────
  late double _pitch;
  late double _roll;

  final double _accelX = 0.02;
  final double _accelY = -0.05;
  final double _accelZ = 0.98;
  final double _gyroX = 0.8;
  final double _gyroY = -1.2;
  final double _gyroZ = 0.3;

  @override
  void initState() {
    super.initState();
    _pitch = widget.pitch;
    _roll = widget.roll;
  }

  // ── DCP Helper ────────────────────────────────────────────────────
  void _exec(String tool, Map<String, dynamic> params) {
    widget.conn?.session?.executeTool(tool, params);
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.exo2()),
      backgroundColor: bg,
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Sensors DCP ───────────────────────────────────────────────────
  void _refreshSensors() {
    _exec('get_pitch_roll', {});
    _exec('get_sensor_accel', {});
    _exec('get_sensor_gyro', {});
    _snack('MPU6050 telemetry requested', AppTheme.primaryOrange);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Power Supply Notice ───────────────────────────────────
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

          // ── IMU Attitude Visualizer (Pitch & Roll) ─────────────────
          RobotImuDisplay(pitch: _pitch, roll: _roll, yaw: widget.yaw),

          const SizedBox(height: 14),

          // ── Accelerometer 3-Axis Readout ──────────────────────────
          _buildAxisCard(
            icon: Icons.speed,
            title: 'MPU6050 Accelerometer',
            unit: 'g (9.81 m/s²)',
            axes: [
              ('Accel X', _accelX, const Color(0xFF4FC3F7), 2.0),
              ('Accel Y', _accelY, const Color(0xFF81D4FA), 2.0),
              ('Accel Z', _accelZ, const Color(0xFF00E676),  2.0),
            ],
          ),

          const SizedBox(height: 14),

          // ── Gyroscope 3-Axis Readout ──────────────────────────────
          _buildAxisCard(
            icon: Icons.rotate_right,
            title: 'MPU6050 Gyroscope',
            unit: '°/s',
            axes: [
              ('Gyro X (Pitch Rate)', _gyroX, const Color(0xFFFFB74D), 50.0),
              ('Gyro Y (Roll Rate)',  _gyroY, const Color(0xFFFF8A65), 50.0),
              ('Gyro Z (Yaw Rate)',   _gyroZ, const Color(0xFFE57373), 50.0),
            ],
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── Axis Bar & Card Helpers ──────────────────────────────────────
  Widget _buildAxisCard({
    required IconData icon,
    required String title,
    required String unit,
    required List<(String, double, Color, double)> axes,
  }) {
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
            children: [
              Icon(icon, color: AppTheme.primaryOrange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...axes.map((a) {
            final (lbl, val, col, maxVal) = a;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _axisBar(lbl, val, col, maxVal),
            );
          }),
        ],
      ),
    );
  }

  Widget _axisBar(String label, double value, Color color, double maxVal) {
    final progress = (value.abs() / maxVal).clamp(0.0, 1.0);
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
