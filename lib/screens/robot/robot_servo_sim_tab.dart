import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../services/event_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_body_sim.dart';

/// Full interactive tab combining the 3D quadruped wireframe simulator
/// with 16-channel servo controls, pose presets, and realtime hardware mirroring.
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
  // Realtime mirroring switch:
  // When ON: sim values reflect real robot servo angles; sliders are read-only.
  // When OFF: user can change sliders to command robot servos.
  bool _realtimeMirroring = false;

  final Map<int, double> _liveRobotAngles = Map.from(kStandAngles);

  Timer? _mirrorTimer;
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _subscribeToTelemetryEvents();
  }

  @override
  void dispose() {
    _mirrorTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  void _subscribeToTelemetryEvents() {
    _eventSub = EventManager().events.listen((event) {
      if (!_realtimeMirroring) return;
      if (event.eventType == 'telemetry' || event.eventType == 'servo_telemetry') {
        if (event.data['servos'] != null) {
          _processIncomingServoData(event.data['servos']);
        }
      }
    });
  }

  void _toggleRealtimeMirroring(bool enabled) {
    setState(() => _realtimeMirroring = enabled);
    _mirrorTimer?.cancel();

    if (enabled) {
      // Immediately request current servo angles
      _fetchServoAngles();
      // Poll every 350ms to keep simulation in sync with physical robot
      _mirrorTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        _fetchServoAngles();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Realtime Mirroring ON: Sim angles are locked to live robot servos',
            style: GoogleFonts.exo2(),
          ),
          backgroundColor: const Color(0xFF00E676),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Realtime Mirroring OFF: Manual slider control enabled',
            style: GoogleFonts.exo2(),
          ),
          backgroundColor: AppTheme.primaryOrange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchServoAngles() async {
    if (!_realtimeMirroring) return;
    try {
      final response = await widget.conn?.session?.execute(
        'get_servo_angles',
        {},
      );
      if (response != null && response.success && response.result != null) {
        final dynamic res = response.result;
        if (res is Map && res['servos'] != null) {
          _processIncomingServoData(res['servos']);
        } else if (res is Map) {
          _processIncomingServoData(res);
        }
      }
    } catch (_) {}
  }

  void _processIncomingServoData(dynamic data) {
    if (data is Map) {
      final updated = <int, double>{};
      data.forEach((k, v) {
        final channel = int.tryParse(k.toString());
        final angle = double.tryParse(v.toString());
        if (channel != null && angle != null) {
          updated[channel] = angle;
        }
      });
      if (updated.isNotEmpty && mounted) {
        setState(() {
          _liveRobotAngles.addAll(updated);
        });
      }
    }
  }

  void _onServoMoved(int index, double angle) {
    // Only send commands if realtime mirroring is OFF (manual mode)
    if (!_realtimeMirroring) {
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF16161A),
          child: Row(
            children: [
              const Icon(Icons.view_in_ar, color: AppTheme.primaryOrange, size: 18),
              const SizedBox(width: 6),
              Text(
                '3D Sim',
                style: GoogleFonts.exo2(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              const Spacer(),

              // "Realtime mirroring" Switch
              Text(
                'Mirroring',
                style: GoogleFonts.exo2(
                  fontSize: 11,
                  color: _realtimeMirroring ? const Color(0xFF00E676) : AppTheme.textMuted,
                  fontWeight: _realtimeMirroring ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _realtimeMirroring,
                  activeThumbColor: const Color(0xFF00E676),
                  activeTrackColor: const Color(0xFF00E676).withAlpha(80),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: _toggleRealtimeMirroring,
                ),
              ),
              const SizedBox(width: 2),

              // Halt / Release Servos Button
              IconButton(
                icon: const Icon(Icons.power_off, color: Colors.amberAccent, size: 18),
                tooltip: 'Release Servos / Cleanup',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: _cleanupServos,
              ),
            ],
          ),
        ),

        // 3D Simulator + Sliders Widget
        Expanded(
          child: RobotSimulator(
            showControls: true,
            isMirroring: _realtimeMirroring,
            externalAngles: _realtimeMirroring ? _liveRobotAngles : null,
            onSingleServoChanged: _onServoMoved,
          ),
        ),
      ],
    );
  }
}
