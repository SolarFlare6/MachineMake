import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';

/// Full-featured Controls screen with:
/// - Live camera feed view at top
/// - Dual controllers:
///   - Left pad: Robot locomotion (Forward, Backward, Left, Right, Stop)
///   - Right pad: Camera Pan / Tilt (Tilt Up, Tilt Down, Pan Left, Pan Right, Center)
/// - Gait speed slider and quick actions
class ControlsScreen extends StatefulWidget {
  final String deviceName;
  final String? deviceId;

  const ControlsScreen({
    super.key,
    required this.deviceName,
    this.deviceId,
  });

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  double _speed = 0.5;
  String _currentAction = 'Standing';
  bool _isCameraStreaming = false;

  // Camera angles
  double _camPan = 90.0;
  double _camTilt = 90.0;

  String get _targetId => widget.deviceId ?? DeviceManager().selectedDeviceId;

  Future<void> _sendTool(String tool, Map<String, dynamic> params, String actionLabel) async {
    setState(() => _currentAction = actionLabel);
    try {
      await DeviceManager().executeTool(_targetId, tool, params);
    } catch (_) {}
  }

  void _panCam(double delta) {
    setState(() {
      _camPan = (_camPan + delta).clamp(0.0, 180.0);
    });
    _sendTool(delta < 0 ? 'pan_to_left' : 'pan_to_right', {'angle': _camPan.round()}, 'Camera Pan: ${_camPan.round()}°');
  }

  void _tiltCam(double delta) {
    setState(() {
      _camTilt = (_camTilt + delta).clamp(20.0, 160.0);
    });
    _sendTool('driver_set_servo_angle_with_index', {'index': 14, 'angle': _camTilt.round()}, 'Camera Tilt: ${_camTilt.round()}°');
  }

  void _centerCamera() {
    setState(() {
      _camPan = 90.0;
      _camTilt = 90.0;
    });
    _sendTool('driver_set_servo_angle_with_index', {'index': 14, 'angle': 90}, 'Camera Centered');
  }

  void _toggleCamera() {
    setState(() => _isCameraStreaming = !_isCameraStreaming);
    if (_isCameraStreaming) {
      _sendTool('start_camera', {}, 'Camera Streaming');
    } else {
      _sendTool('stop_camera', {}, 'Camera Stopped');
    }
  }

  void _captureSnapshot() {
    _sendTool('camera_snapshot', {}, 'Snapshot Taken');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Camera snapshot saved', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(
          '${widget.deviceName} Controls',
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.primaryOrange),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isCameraStreaming ? Icons.videocam : Icons.videocam_off,
              color: _isCameraStreaming ? const Color(0xFF00E676) : AppTheme.textMuted,
            ),
            tooltip: 'Toggle Camera Stream',
            onPressed: _toggleCamera,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white70),
            tooltip: 'Capture Snapshot',
            onPressed: _captureSnapshot,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Live Camera Feed Card ──────────────────────────
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color: const Color(0xFF131418),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _isCameraStreaming ? AppTheme.primaryOrange.withAlpha(150) : AppTheme.darkBorder,
                    width: 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCameraStreaming ? Icons.connected_tv : Icons.videocam_off_outlined,
                            size: 42,
                            color: _isCameraStreaming ? AppTheme.primaryOrange : AppTheme.textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isCameraStreaming ? 'Live RTSP / WebRTC Camera Feed' : 'Camera Feed Paused',
                            style: GoogleFonts.exo2(
                              color: _isCameraStreaming ? Colors.white : AppTheme.textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'State: $_currentAction',
                            style: GoogleFonts.exo2(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Live badge
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isCameraStreaming ? const Color(0xFF00E676).withAlpha(40) : Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _isCameraStreaming ? const Color(0xFF00E676) : AppTheme.darkBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isCameraStreaming ? const Color(0xFF00E676) : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isCameraStreaming ? 'LIVE' : 'STANDBY',
                              style: GoogleFonts.exo2(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _isCameraStreaming ? const Color(0xFF00E676) : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── 2. Dual Controller Pads (Locomotion + Pan/Tilt) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Robot Locomotion Pad
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Locomotion',
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildLocomotionPad(),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Right: Camera Pan / Tilt Pad
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Camera Pan / Tilt',
                          style: GoogleFonts.exo2(
                            color: const Color(0xFF4FC3F7),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildCameraPad(),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── 3. Speed Slider ───────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Gait Speed',
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(_speed * 100).toInt()}%',
                          style: GoogleFonts.exo2(
                            color: AppTheme.primaryOrange,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.primaryOrange,
                        inactiveTrackColor: AppTheme.darkBorder,
                        thumbColor: AppTheme.primaryOrange,
                      ),
                      child: Slider(
                        value: _speed,
                        min: 0.1,
                        max: 1.0,
                        onChanged: (val) => setState(() => _speed = val),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 4. Quick Actions ──────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.darkBorder),
                      ),
                      onPressed: () => _sendTool('sit', {}, 'Sitting'),
                      child: Text('Sit', style: GoogleFonts.exo2()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryOrange,
                        side: BorderSide(color: AppTheme.primaryOrange),
                      ),
                      onPressed: () => _sendTool('stand', {}, 'Standing'),
                      child: Text('Stand', style: GoogleFonts.exo2(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amberAccent,
                        side: const BorderSide(color: Colors.amberAccent),
                      ),
                      onPressed: () {
                        _sendTool('cleanup_servos', {}, 'Servos Released');
                        _sendTool('emergency_stop', {}, 'Halted');
                      },
                      child: Text('Halt', style: GoogleFonts.exo2(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Locomotion Pad Widget ─────────────────────────────────────────
  Widget _buildLocomotionPad() {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.primaryOrange.withAlpha(80), width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Forward
          Positioned(
            top: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_up,
              onTap: () => _sendTool(
                'walk',
                {'direction': 'forward', 'distance': (_speed * 2.0).clamp(0.2, 5.0)},
                'Walking Forward',
              ),
            ),
          ),
          // Backward
          Positioned(
            bottom: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_down,
              onTap: () => _sendTool(
                'walk',
                {'direction': 'backward', 'distance': (_speed * 2.0).clamp(0.2, 5.0)},
                'Walking Backward',
              ),
            ),
          ),
          // Left
          Positioned(
            left: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_left,
              onTap: () => _sendTool(
                'turn',
                {'direction': 'left', 'angle': 45.0},
                'Turning Left',
              ),
            ),
          ),
          // Right
          Positioned(
            right: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_right,
              onTap: () => _sendTool(
                'turn',
                {'direction': 'right', 'angle': 45.0},
                'Turning Right',
              ),
            ),
          ),
          // Center Stop
          GestureDetector(
            onTap: () => _sendTool('stand', {}, 'Stopped'),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                'STOP',
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Camera Pan/Tilt Pad Widget ────────────────────────────────────
  Widget _buildCameraPad() {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF4FC3F7).withAlpha(80), width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Tilt Up
          Positioned(
            top: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_up,
              color: const Color(0xFF4FC3F7),
              onTap: () => _tiltCam(15.0),
            ),
          ),
          // Tilt Down
          Positioned(
            bottom: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_down,
              color: const Color(0xFF4FC3F7),
              onTap: () => _tiltCam(-15.0),
            ),
          ),
          // Pan Left
          Positioned(
            left: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_left,
              color: const Color(0xFF4FC3F7),
              onTap: () => _panCam(-15.0),
            ),
          ),
          // Pan Right
          Positioned(
            right: 6,
            child: _buildMiniBtn(
              icon: Icons.keyboard_arrow_right,
              color: const Color(0xFF4FC3F7),
              onTap: () => _panCam(15.0),
            ),
          ),
          // Center Cam
          GestureDetector(
            onTap: _centerCamera,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF1E2832),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.center_focus_strong,
                color: Color(0xFF4FC3F7),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBtn({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}
