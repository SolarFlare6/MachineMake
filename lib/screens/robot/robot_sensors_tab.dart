import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_event.dart';
import '../../services/event_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_imu_display.dart';

/// Telemetry tab for the quadruped robot:
/// - MPU6050 Gyro & Accel attitude telemetry cards
/// - Real-time pitch, roll, and yaw visualization streamed from the robot server
class RobotSensorsTab extends StatefulWidget {
  final DeviceConnection? conn;
  final double pitch;
  final double roll;
  final double yaw;

  const RobotSensorsTab({
    super.key,
    this.conn,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.yaw = 0.0,
  });

  @override
  State<RobotSensorsTab> createState() => _RobotSensorsTabState();
}

class _RobotSensorsTabState extends State<RobotSensorsTab> {
  // ── MPU6050 Telemetry State ───────────────────────────────────────
  late double _pitch;
  late double _roll;
  late double _yaw;

  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 1.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;

  StreamSubscription<DeviceEvent>? _telemetrySub;

  @override
  void initState() {
    super.initState();
    _pitch = widget.pitch;
    _roll = widget.roll;
    _yaw = widget.yaw;

    // Seed with the most recent cached IMU packet if available
    final cachedImu = EventManager().latestImuData(widget.conn?.deviceId);
    if (cachedImu != null) {
      _applyImuMap(cachedImu, notify: false);
    }

    // Listen to live 2 Hz telemetry events from the robot server
    _telemetrySub = EventManager().eventsOfType('telemetry').listen((event) {
      final targetId = widget.conn?.deviceId;
      if (targetId != null &&
          targetId.isNotEmpty &&
          event.deviceId.isNotEmpty &&
          event.deviceId != targetId) {
        return;
      }
      final imu = event.data['imu'];
      if (imu is Map) {
        _applyImuMap(Map<String, dynamic>.from(imu));
      }
    });

    // Fetch an initial snapshot on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSensorsSilent();
    });
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    super.dispose();
  }

  void _applyImuMap(Map<String, dynamic> imu, {bool notify = true}) {
    void updateFields() {
      if (imu['pitch'] is num) _pitch = (imu['pitch'] as num).toDouble();
      if (imu['roll'] is num) _roll = (imu['roll'] as num).toDouble();
      if (imu['yaw'] is num) _yaw = (imu['yaw'] as num).toDouble();

      final accel = imu['accel'];
      if (accel is Map) {
        if (accel['x'] is num) _accelX = (accel['x'] as num).toDouble();
        if (accel['y'] is num) _accelY = (accel['y'] as num).toDouble();
        if (accel['z'] is num) _accelZ = (accel['z'] as num).toDouble();
      }

      final gyro = imu['gyro'];
      if (gyro is Map) {
        if (gyro['x'] is num) _gyroX = (gyro['x'] as num).toDouble();
        if (gyro['y'] is num) _gyroY = (gyro['y'] as num).toDouble();
        if (gyro['z'] is num) _gyroZ = (gyro['z'] as num).toDouble();
      }
    }

    if (notify && mounted) {
      setState(updateFields);
    } else {
      updateFields();
    }
  }

  Map<String, dynamic>? _extractResultMap(dynamic resp) {
    if (resp == null) return null;
    final dynamic raw = resp is Map ? resp : resp.result;
    if (raw is Map) {
      if (raw['result'] is Map) {
        return Map<String, dynamic>.from(raw['result'] as Map);
      }
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  Future<void> _fetchSensorsSilent() async {
    final session = widget.conn?.session;
    if (session == null) return;

    try {
      final results = await Future.wait([
        session.executeTool('get_pitch_roll', {}),
        session.executeTool('get_sensor_accel', {}),
        session.executeTool('get_sensor_gyro', {}),
      ]);

      if (!mounted) return;
      final pr = _extractResultMap(results[0]);
      final accel = _extractResultMap(results[1]);
      final gyro = _extractResultMap(results[2]);

      setState(() {
        if (pr != null) {
          if (pr['pitch'] is num) _pitch = (pr['pitch'] as num).toDouble();
          if (pr['roll'] is num) _roll = (pr['roll'] as num).toDouble();
          if (pr['yaw'] is num) _yaw = (pr['yaw'] as num).toDouble();
        }
        if (accel != null) {
          if (accel['x'] is num) _accelX = (accel['x'] as num).toDouble();
          if (accel['y'] is num) _accelY = (accel['y'] as num).toDouble();
          if (accel['z'] is num) _accelZ = (accel['z'] as num).toDouble();
        }
        if (gyro != null) {
          if (gyro['x'] is num) _gyroX = (gyro['x'] as num).toDouble();
          if (gyro['y'] is num) _gyroY = (gyro['y'] as num).toDouble();
          if (gyro['z'] is num) _gyroZ = (gyro['z'] as num).toDouble();
        }
      });
    } catch (_) {}
  }

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.exo2()),
      backgroundColor: bg,
      duration: const Duration(seconds: 1),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Sensors DCP ───────────────────────────────────────────────────
  Future<void> _refreshSensors() async {
    await _fetchSensorsSilent();
    _snack('MPU6050 telemetry refreshed', AppTheme.primaryOrange);
  }

  @override
  Widget build(BuildContext context) {
    // Automatically scale bar range whether driver reports m/s² (~9.81) or g (~1.0)
    final bool isMetersPerSecSq =
        _accelX.abs() > 2.5 || _accelY.abs() > 2.5 || _accelZ.abs() > 2.5;
    final double accelMax = isMetersPerSecSq ? 15.0 : 2.0;
    final String accelUnit = isMetersPerSecSq ? 'm/s²' : 'g (9.81 m/s²)';

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
                  icon: Icon(Icons.refresh, color: AppTheme.primaryOrange, size: 20),
                  onPressed: _refreshSensors,
                  tooltip: 'Refresh MPU6050',
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── IMU Attitude Visualizer (Pitch, Roll & Yaw) ────────────
          RobotImuDisplay(pitch: _pitch, roll: _roll, yaw: _yaw),

          const SizedBox(height: 14),

          // ── Accelerometer 3-Axis Readout ──────────────────────────
          _buildAxisCard(
            icon: Icons.speed,
            title: 'MPU6050 Accelerometer',
            unit: accelUnit,
            axes: [
              ('Accel X', _accelX, const Color(0xFF4FC3F7), accelMax),
              ('Accel Y', _accelY, const Color(0xFF81D4FA), accelMax),
              ('Accel Z', _accelZ, const Color(0xFF00E676), accelMax),
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
