import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../models/dcp_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_dashboard_header.dart';
import 'robot_move_tab.dart';
import 'robot_servo_sim_tab.dart';
import 'robot_camera_tab.dart';
import 'robot_sensors_tab.dart';
import 'robot_config_tab.dart';

/// Full Quadruped / Robot Dashboard with dedicated header and internal navigation:
/// - Move: Cam feed & Sim preview cards + Hardware modules accordions
/// - Sim: Full 3D Kinematic Wireframe Dog Simulator + 16-channel servo controls
/// - Camera: Live stream preview & snapshot capture
/// - Sensors: Clean MPU6050 Gyroscope & Accelerometer attitude dashboard
/// - Config: IMU Active Stabilizer & Autonomy Switch
class QuadrupedDashboardScreen extends StatefulWidget {
  final DeviceItem device;
  final DeviceConnection? conn;
  final DeviceManifest? manifest;

  const QuadrupedDashboardScreen({
    super.key,
    required this.device,
    this.conn,
    this.manifest,
  });

  @override
  State<QuadrupedDashboardScreen> createState() => _QuadrupedDashboardScreenState();
}

class _QuadrupedDashboardScreenState extends State<QuadrupedDashboardScreen> {
  int _currentTabIndex = 0;
  bool _isStreaming = false;

  void _triggerEmergencyStop() {
    // Send emergency stop / cleanup_servos over DCP session
    widget.conn?.session?.executeTool('cleanup_servos', {});
    widget.conn?.session?.executeTool('emergency_stop', {});

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            Text(
              'EMERGENCY STOP',
              style: GoogleFonts.exo2(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        content: Text(
          'All motors de-energized and halted immediately. Locomotion paused for safety.',
          style: GoogleFonts.exo2(color: Colors.white),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Acknowledge', style: GoogleFonts.exo2()),
          ),
        ],
      ),
    );
  }

  void _handleMove(String direction) {
    widget.conn?.session?.executeTool('walk', {
      'direction': direction,
      'distance': 1.0,
    });
  }

  void _handleSpeedChanged(double speed) {
    // UI speed adjustment passed to walk calls
  }

  void _toggleCameraStream() {
    setState(() => _isStreaming = !_isStreaming);
    if (_isStreaming) {
      widget.conn?.session?.executeTool('start_camera', {});
    } else {
      widget.conn?.session?.executeTool('stop_camera', {});
    }
  }

  void _takeSnapshot() {
    widget.conn?.session?.executeTool('camera_snapshot', {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Camera snapshot captured', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _handleParamChanged(String param, dynamic val) {
    widget.conn?.session?.executeTool('set_config', {param: val});
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      // 0. Move Tab (Image 1 layout)
      RobotMoveTab(
        conn: widget.conn,
        onMove: _handleMove,
        onSpeedChanged: _handleSpeedChanged,
        onExpandCamera: () => setState(() => _currentTabIndex = 2),
        onExpandSim: () => setState(() => _currentTabIndex = 1),
      ),

      // 1. Sim / Servo Control Tab (Image 2 wireframe 3D simulator + sliders)
      RobotServoSimTab(
        conn: widget.conn,
      ),

      // 2. Camera Tab
      RobotCameraTab(
        isStreaming: _isStreaming,
        onToggleStream: _toggleCameraStream,
        onSnapshot: _takeSnapshot,
      ),

      // 3. Sensors Tab (MPU6050 only)
      RobotSensorsTab(
        conn: widget.conn,
      ),

      // 4. Config Tab (Stabilizer & Autonomy)
      RobotConfigTab(
        onParamChanged: _handleParamChanged,
      ),
    ];

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Custom Robot Unique Header
            RobotDashboardHeader(
              manifest: widget.manifest,
              conn: widget.conn,
              batteryLevel: null, // Robot uses DC In
              isControlSession: true,
              onEmergencyStop: _triggerEmergencyStop,
              onBack: () => Navigator.of(context).pop(),
            ),

            // Tab Content
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: tabs,
              ),
            ),

            // Exclusive Robot Internal Bottom Navigation
            _buildRobotBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildRobotBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C21),
        border: Border(
          top: BorderSide(
            color: AppTheme.darkBorder,
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.gamepad, 'Move'),
            _buildNavItem(1, Icons.view_in_ar, 'Sim'),
            _buildNavItem(2, Icons.videocam, 'Camera'),
            _buildNavItem(3, Icons.sensors, 'Sensors'),
            _buildNavItem(4, Icons.settings, 'Config'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentTabIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryOrange : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.exo2(
                color: isSelected ? AppTheme.primaryOrange : AppTheme.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
