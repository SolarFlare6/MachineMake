import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_body_sim.dart';

/// Full interactive tab combining the 3D quadruped wireframe simulator
/// with 16-channel servo controls, pose presets, and live hardware synchronization.
class RobotServoSimTab extends StatefulWidget {
  final DeviceConnection? conn;
  final Function(int index, double angle)? onServoChanged;

  const RobotServoSimTab({
    super.key,
    this.conn,
    this.onServoChanged,
  });

  @override
  State<RobotServoSimTab> createState() => _RobotServoSimTabState();
}

class _RobotServoSimTabState extends State<RobotServoSimTab> {
  bool _syncWithRobot = true;

  void _onServoMoved(int index, double angle) {
    if (_syncWithRobot) {
      widget.onServoChanged?.call(index, angle);
      widget.conn?.session?.executeTool('driver_set_servo_angle_with_index', {
        'index': index,
        'angle': angle.round(),
      });
    }
  }

  void _cleanupServos() {
    widget.conn?.session?.executeTool('cleanup_servos', {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Released all servos (power cut / free movement)', style: GoogleFonts.exo2()),
        backgroundColor: Colors.amber[800],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF16161A),
          child: Row(
            children: [
              const Icon(Icons.view_in_ar, color: AppTheme.primaryOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                '3D Kinematic Dog Sim',
                style: GoogleFonts.exo2(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sync HW',
                    style: GoogleFonts.exo2(
                      fontSize: 12,
                      color: _syncWithRobot ? const Color(0xFF4FC3F7) : AppTheme.textMuted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _syncWithRobot,
                    activeThumbColor: const Color(0xFF4FC3F7),
                    activeTrackColor: const Color(0xFF4FC3F7).withAlpha(80),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _syncWithRobot = v),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.power_off, color: Colors.amberAccent, size: 20),
                tooltip: 'Release Servos / Cleanup',
                onPressed: _cleanupServos,
              ),
            ],
          ),
        ),

        // 3D Simulator + Sliders Widget
        Expanded(
          child: RobotSimulator(
            showControls: true,
            onSingleServoChanged: _onServoMoved,
          ),
        ),
      ],
    );
  }
}
