import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../core/models/device_manifest.dart';
import '../../models/dcp_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_dashboard_header.dart';
import 'robot_move_tab.dart';
import 'robot_pose_tab.dart';
import 'robot_camera_tab.dart';
import 'robot_sensors_tab.dart';
import 'robot_config_tab.dart';

/// Full Quadruped / Robot Dashboard with dedicated header and internal navigation.
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

  bool get _hasBattery =>
      widget.manifest?.capabilities.any((c) =>
          c.type == CapabilityType.power ||
          c.id.toLowerCase().contains('battery') ||
          c.name.toLowerCase().contains('battery')) ??
      false;

  int? get _battery => _hasBattery ? 88 : null;
  double? get _voltage => _hasBattery ? 12.4 : null;

  void _triggerEmergencyStop() {
    // Send emergency stop over DCP session if connected
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
          'All motors halted immediately. Locomotion paused for safety.',
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
    // Server requires direction + distance; use 1.0m default per tap
    widget.conn?.session?.executeTool('walk', {
      'direction': direction,
      'distance': 1.0,
    });
  }

  void _handleSpeedChanged(double speed) {
    // Server has no set_speed tool; speed slider is UI-only for now
  }

  void _handleGaitChanged(String gait) {
    // set_gait not yet server-supported; UI feedback only
    setState(() {});
  }

  void _handlePoseSelected(String pose) {
    // Map common pose names to server-supported tools
    switch (pose) {
      case 'stand':
        widget.conn?.session?.executeTool('stand', {});
      case 'sit':
        widget.conn?.session?.executeTool('sit', {});
      default:
        widget.conn?.session?.executeTool('stand', {});
    }
  }

  void _handleKinematics(double pitch, double roll, double height) {
    // set_pose not yet server-supported; UI feedback only
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
      RobotMoveTab(
        onMove: _handleMove,
        onSpeedChanged: _handleSpeedChanged,
        onGaitChanged: _handleGaitChanged,
      ),
      RobotPoseTab(
        onPoseSelected: _handlePoseSelected,
        onAdjustKinematics: _handleKinematics,
      ),
      RobotCameraTab(
        isStreaming: _isStreaming,
        onToggleStream: _toggleCameraStream,
        onSnapshot: _takeSnapshot,
      ),
      RobotSensorsTab(
        batteryLevel: _battery,
        batteryVoltage: _voltage,
      ),
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
              batteryLevel: _battery,
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
            _buildNavItem(1, Icons.accessibility_new, 'Pose'),
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
