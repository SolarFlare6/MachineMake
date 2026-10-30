import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../services/event_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_body_sim.dart';

/// Redesigned Main Quadruped Control Tab matching mockup:
/// - Top "Cam feed & Sim" dual cards (live camera preview & 3D wireframe sim preview)
/// - "Hardware modules" expandable accordions:
///   1. Robot movement (direct directional D-pad & speed slider)
///   2. Servo control (quick PCA9685 index, angle slider, snap & pan actions)
///   3. RGB led plate (WS281x 8-LED strip colors, animations & buzzer tone)
class RobotMoveTab extends StatefulWidget {
  final DeviceConnection? conn;
  final Function(String direction)? onMove;
  final Function(double speed)? onSpeedChanged;
  final VoidCallback? onExpandCamera;
  final VoidCallback? onExpandSim;

  const RobotMoveTab({
    super.key,
    this.conn,
    this.onMove,
    this.onSpeedChanged,
    this.onExpandCamera,
    this.onExpandSim,
  });

  @override
  State<RobotMoveTab> createState() => _RobotMoveTabState();
}

class _RobotMoveTabState extends State<RobotMoveTab> {
  // Speed
  double _speed = 0.65;

  // Accordion expansion states
  bool _isMovementExpanded = true;
  bool _isServoExpanded = false;
  bool _isRgbExpanded = false;

  // Servo Control State
  int _selectedServo = 3;
  double _servoAngle = 70.0;

  // RGB LED strip state
  Color _currentLedColor = const Color(0xFF00E676);
  Color _lastActiveLedColor = const Color(0xFF00E676);

  void _sendMove(String direction) {
    widget.onMove?.call(direction);
    widget.conn?.session?.executeTool('walk', {
      'direction': direction,
      'distance': (_speed * 1.5).clamp(0.2, 5.0),
    });
  }

  void _stopMove() {
    widget.conn?.session?.executeTool('stand', {});
  }

  void _sendServoAngle(int index, double angle) {
    widget.conn?.session?.executeTool('driver_set_servo_angle_with_index', {
      'index': index,
      'angle': angle.round(),
    });
  }

  void _snapServo(String direction) {
    final tool = direction == 'left' ? 'snap_servo_left' : 'snap_servo_right';
    widget.conn?.session?.executeTool(tool, {'index': _selectedServo});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Snapped servo $_selectedServo $direction', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(milliseconds: 700),
      ),
    );
  }

  void _panServo(String direction) {
    final tool = direction == 'left' ? 'pan_to_left' : 'pan_to_right';
    widget.conn?.session?.executeTool(tool, {'index': _selectedServo});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Panning servo $_selectedServo $direction', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(milliseconds: 700),
      ),
    );
  }

  void _cleanupServos() {
    widget.conn?.session?.executeTool('cleanup_servos', {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Released all servos (power cut)', style: GoogleFonts.exo2()),
        backgroundColor: Colors.amber[800],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // RGB Strip actions
  void _setStripColor(int r, int g, int b) {
    final color = Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    widget.conn?.session?.executeTool('turn_on_strip_with_color', {
      'r': r.clamp(0, 255),
      'g': g.clamp(0, 255),
      'b': b.clamp(0, 255),
    });
    setState(() {
      _currentLedColor = color;
      _lastActiveLedColor = color;
    });
  }

  void _turnOffStrip() {
    widget.conn?.session?.executeTool('turn_off_strip', {});
    setState(() => _currentLedColor = Colors.transparent);
  }

  void _runLedAnimation(String animTool) {
    widget.conn?.session?.executeTool(animTool, {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Triggered $animTool animation', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _runLedAnimationWithColor() {
    final activeColor = _currentLedColor.a == 0 ? _lastActiveLedColor : _currentLedColor;
    final int r = (activeColor.r * 255.0).round().clamp(0, 255);
    final int g = (activeColor.g * 255.0).round().clamp(0, 255);
    final int b = (activeColor.b * 255.0).round().clamp(0, 255);

    widget.conn?.session?.executeTool('animate_running_process', {
      'r': r,
      'g': g,
      'b': b,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Animating LED strip with RGB($r, $g, $b)',
          style: GoogleFonts.exo2(),
        ),
        backgroundColor: activeColor.computeLuminance() > 0.15 ? activeColor : AppTheme.primaryOrange,
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  Future<void> _showLedColorPickerDialog() async {
    final initialColor = _currentLedColor.a == 0 ? _lastActiveLedColor : _currentLedColor;
    final Color? picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _LedColorPickerDialog(initialColor: initialColor),
    );
    if (picked != null && mounted) {
      final int r = (picked.r * 255.0).round().clamp(0, 255);
      final int g = (picked.g * 255.0).round().clamp(0, 255);
      final int b = (picked.b * 255.0).round().clamp(0, 255);
      _setStripColor(r, g, b);
    }
  }

  void _playBuzzer() {
    widget.conn?.session?.executeTool('play_tone', {'tone': 'C4'});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Played buzzer tone C4', style: GoogleFonts.exo2()),
        backgroundColor: AppTheme.primaryOrange,
        duration: const Duration(milliseconds: 600),
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
          // ── Section 1: Cam feed & Sim Header ────────────────────
          _buildCamAndSimHeader(),

          const SizedBox(height: 20),

          // ── Section 2: Hardware modules Title ───────────────────
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Hardware modules',
              style: GoogleFonts.exo2(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),

          // ── Accordion 1: Robot Movement ─────────────────────────
          _buildAccordionCard(
            title: 'Robot movement',
            isExpanded: _isMovementExpanded,
            onToggle: () => setState(() => _isMovementExpanded = !_isMovementExpanded),
            child: _buildMovementContent(),
          ),

          const SizedBox(height: 12),

          // ── Accordion 2: Servo Control ──────────────────────────
          _buildAccordionCard(
            title: 'Servo control',
            isExpanded: _isServoExpanded,
            onToggle: () => setState(() => _isServoExpanded = !_isServoExpanded),
            child: _buildServoControlContent(),
          ),

          const SizedBox(height: 12),

          // ── Accordion 3: RGB LED Plate ──────────────────────────
          _buildAccordionCard(
            title: 'RGB led plate',
            isExpanded: _isRgbExpanded,
            onToggle: () => setState(() => _isRgbExpanded = !_isRgbExpanded),
            child: _buildRgbLedPlateContent(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Cam feed & Sim Preview Row ────────────────────────────────────
  Widget _buildCamAndSimHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Cam feed & Sim',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Row(
          children: [
            // Camera Feed Preview Card
            Expanded(
              child: GestureDetector(
                onTap: widget.onExpandCamera,
                child: ListenableBuilder(
                  listenable: EventManager(),
                  builder: (context, _) {
                    final frameBytes = EventManager().latestCameraFrame(widget.conn?.deviceId);
                    return Container(
                      height: 130,
                      decoration: BoxDecoration(
                        color: const Color(0xFF131418),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: frameBytes != null ? AppTheme.primaryOrange : AppTheme.darkBorder,
                          width: 1.2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (frameBytes != null)
                              Image.memory(
                                frameBytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            else
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppTheme.darkCard,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.videocam,
                                        color: AppTheme.textMuted,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'camera feed here',
                                      style: GoogleFonts.exo2(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.fullscreen,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Robot Sim Wireframe Card (with orange border)
            Expanded(
              child: GestureDetector(
                onTap: widget.onExpandSim,
                child: Container(
                  height: 130,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryOrange, width: 1.5),
                  ),
                  child: Stack(
                    children: [
                      // Mini Wireframe 3D Renderer
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: const RobotSimulator(
                          height: 130,
                          showControls: false,
                          isMiniPreview: true,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryOrange.withAlpha(200),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'robot sim',
                            style: GoogleFonts.exo2(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.fullscreen,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Accordion Helper ──────────────────────────────────────────────
  Widget _buildAccordionCard({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? AppTheme.primaryOrange.withAlpha(120) : AppTheme.darkBorder,
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.exo2(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: isExpanded ? AppTheme.primaryOrange : AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(color: AppTheme.darkBorder, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ],
        ],
      ),
    );
  }

  // ── Movement Content (D-Pad + Speed Slider) ───────────────────────
  Widget _buildMovementContent() {
    return Column(
      children: [
        // Directional Navigation Pad
        Center(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.primaryOrange.withAlpha(70),
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 10,
                  child: _buildDirectionBtn(Icons.keyboard_arrow_up, 'forward'),
                ),
                Positioned(
                  bottom: 10,
                  child: _buildDirectionBtn(Icons.keyboard_arrow_down, 'backward'),
                ),
                Positioned(
                  left: 10,
                  child: _buildDirectionBtn(Icons.keyboard_arrow_left, 'left'),
                ),
                Positioned(
                  right: 10,
                  child: _buildDirectionBtn(Icons.keyboard_arrow_right, 'right'),
                ),
                // Center Stop
                GestureDetector(
                  onTap: _stopMove,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryOrange.withAlpha(60),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'STOP',
                      style: GoogleFonts.exo2(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        // Speed Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Speed',
              style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              '${(_speed * 100).toInt()}%',
              style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.primaryOrange,
            inactiveTrackColor: AppTheme.darkBorder,
            thumbColor: AppTheme.primaryOrange,
            overlayColor: AppTheme.primaryOrange.withAlpha(40),
          ),
          child: Slider(
            value: _speed,
            min: 0.1,
            max: 1.0,
            onChanged: (val) {
              setState(() => _speed = val);
              widget.onSpeedChanged?.call(val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionBtn(IconData icon, String direction) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _sendMove(direction),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  // ── Servo Control Content ─────────────────────────────────────────
  Widget _buildServoControlContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Servo channel selector
        Row(
          children: [
            Text(
              'Channel:',
              style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedServo,
                    isExpanded: true,
                    dropdownColor: AppTheme.modalBackground,
                    icon: Icon(Icons.arrow_drop_down, color: AppTheme.primaryOrange),
                    items: List.generate(16, (i) {
                      String label = 'Servo $i';
                      if (i == 2) label = 'Servo 2 (FL Hip)';
                      if (i == 3) label = 'Servo 3 (FL Middle)';
                      if (i == 4) label = 'Servo 4 (FL Lower)';
                      if (i == 5) label = 'Servo 5 (FR Hip)';
                      if (i == 6) label = 'Servo 6 (FR Middle)';
                      if (i == 7) label = 'Servo 7 (FR Lower)';
                      if (i == 8) label = 'Servo 8 (BL Hip)';
                      if (i == 9) label = 'Servo 9 (BL Middle)';
                      if (i == 10) label = 'Servo 10 (BL Lower)';
                      if (i == 11) label = 'Servo 11 (BR Hip)';
                      if (i == 12) label = 'Servo 12 (BR Middle)';
                      if (i == 13) label = 'Servo 13 (BR Lower)';
                      return DropdownMenuItem(
                        value: i,
                        child: Text(
                          label,
                          style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                        ),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedServo = val);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Angle Slider
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Angle', style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13)),
            Text('${_servoAngle.round()}°', style: GoogleFonts.exo2(color: const Color(0xFF4FC3F7), fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        Slider(
          value: _servoAngle,
          min: 0,
          max: 180,
          activeColor: const Color(0xFF4FC3F7),
          inactiveColor: AppTheme.darkBorder,
          onChanged: (v) {
            setState(() => _servoAngle = v);
            _sendServoAngle(_selectedServo, v);
          },
        ),

        const SizedBox(height: 10),

        // Quick action buttons
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickActionBtn('Snap Left', () => _snapServo('left')),
            _buildQuickActionBtn('Center 90°', () {
              setState(() => _servoAngle = 90);
              _sendServoAngle(_selectedServo, 90);
            }),
            _buildQuickActionBtn('Snap Right', () => _snapServo('right')),
            _buildQuickActionBtn('Pan Left', () => _panServo('left')),
            _buildQuickActionBtn('Pan Right', () => _panServo('right')),
            _buildQuickActionBtn(
              'Release (Halt)',
              _cleanupServos,
              color: Colors.amberAccent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionBtn(String label, VoidCallback onTap, {Color? color}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color ?? Colors.white,
        side: BorderSide(color: color?.withAlpha(150) ?? AppTheme.darkBorder),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: GoogleFonts.exo2(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── RGB LED Plate Content ─────────────────────────────────────────
  Widget _buildRgbLedPlateContent() {
    final previewColor = _currentLedColor.a == 0 ? _lastActiveLedColor : _currentLedColor;
    final int r = (previewColor.r * 255.0).round().clamp(0, 255);
    final int g = (previewColor.g * 255.0).round().clamp(0, 255);
    final int b = (previewColor.b * 255.0).round().clamp(0, 255);
    final String hexLabel =
        '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 8 LED Strip preview indicator (tappable to open color picker popup)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('WS281x (8-LED Strip):', style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13)),
            InkWell(
              onTap: _showLedColorPickerDialog,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _currentLedColor.a == 0
                        ? AppTheme.darkBorder
                        : _currentLedColor.withAlpha(160),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentLedColor.a == 0 ? 'OFF ($hexLabel)' : hexLabel,
                      style: GoogleFonts.exo2(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentLedColor.a == 0 ? Colors.transparent : _currentLedColor,
                        border: Border.all(
                          color: _currentLedColor.a == 0 ? Colors.white38 : Colors.white70,
                          width: 1.2,
                        ),
                        boxShadow: _currentLedColor.a == 0
                            ? null
                            : [
                                BoxShadow(
                                  color: _currentLedColor.withAlpha(150),
                                  blurRadius: 8,
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Color Presets
        Row(
          children: [
            Expanded(child: _buildColorBtn('Red', const Color(0xFFFF3333), () => _setStripColor(255, 0, 0))),
            const SizedBox(width: 8),
            Expanded(child: _buildColorBtn('Green', const Color(0xFF00E676), () => _setStripColor(0, 255, 0))),
            const SizedBox(width: 8),
            Expanded(child: _buildColorBtn('Blue', const Color(0xFF2979FF), () => _setStripColor(0, 0, 255))),
            const SizedBox(width: 8),
            Expanded(child: _buildColorBtn('Off', Colors.grey, _turnOffStrip)),
          ],
        ),

        const SizedBox(height: 14),

        // Animation Presets
        Text('Animations & Feedback:', style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildQuickActionBtn('Process Run', () => _runLedAnimation('animate_running_process'), color: Colors.cyan),
            _buildQuickActionBtn(
              'Animate with color',
              _runLedAnimationWithColor,
              color: Colors.purpleAccent,
            ),
            _buildQuickActionBtn('Alert Flash', () => _runLedAnimation('flash_alert'), color: Colors.redAccent),
            _buildQuickActionBtn('OK Blink', () => _runLedAnimation('blink_oke'), color: Colors.greenAccent),
            _buildQuickActionBtn('Warning Blink', () => _runLedAnimation('blink_warning'), color: Colors.amberAccent),
            //_buildQuickActionBtn('Beep Buzzer', _playBuzzer, color: AppTheme.primaryOrange),
          ],
        ),
      ],
    );
  }

  Widget _buildColorBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.exo2(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Interactive LED Color Picker Dialog featuring:
/// 1. 2D HSV Color Wheel + Brightness Slider
/// 2. Hex Color Text Field (#RRGGBB)
/// 3. R, G, B Numeric Text Fields (0-255)
/// 4. Cancel & Set Color buttons
class _LedColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _LedColorPickerDialog({required this.initialColor});

  @override
  State<_LedColorPickerDialog> createState() => _LedColorPickerDialogState();
}

class _LedColorPickerDialogState extends State<_LedColorPickerDialog> {
  late HSVColor _hsvColor;
  late TextEditingController _hexController;
  late TextEditingController _rController;
  late TextEditingController _gController;
  late TextEditingController _bController;
  bool _isUpdatingText = false;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController();
    _rController = TextEditingController();
    _gController = TextEditingController();
    _bController = TextEditingController();
    _syncControllersFromColor(_hsvColor.toColor());
  }

  @override
  void dispose() {
    _hexController.dispose();
    _rController.dispose();
    _gController.dispose();
    _bController.dispose();
    super.dispose();
  }

  void _syncControllersFromColor(Color color, {bool skipHex = false, bool skipRgb = false}) {
    _isUpdatingText = true;
    final int r = (color.r * 255.0).round().clamp(0, 255);
    final int g = (color.g * 255.0).round().clamp(0, 255);
    final int b = (color.b * 255.0).round().clamp(0, 255);

    if (!skipHex) {
      final hex =
          '${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
              .toUpperCase();
      _hexController.text = hex;
    }
    if (!skipRgb) {
      _rController.text = r.toString();
      _gController.text = g.toString();
      _bController.text = b.toString();
    }
    _isUpdatingText = false;
  }

  void _onWheelChanged(HSVColor newHsv) {
    setState(() {
      _hsvColor = newHsv;
      _syncControllersFromColor(_hsvColor.toColor());
    });
  }

  void _onHexChanged(String value) {
    if (_isUpdatingText) return;
    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final parsed = int.tryParse(cleaned, radix: 16);
      if (parsed != null) {
        final color = Color(0xFF000000 | parsed);
        setState(() {
          _hsvColor = HSVColor.fromColor(color);
          _syncControllersFromColor(color, skipHex: true);
        });
      }
    }
  }

  void _onRgbChanged() {
    if (_isUpdatingText) return;
    final r = (int.tryParse(_rController.text) ?? 0).clamp(0, 255);
    final g = (int.tryParse(_gController.text) ?? 0).clamp(0, 255);
    final b = (int.tryParse(_bController.text) ?? 0).clamp(0, 255);
    final color = Color.fromARGB(255, r, g, b);
    setState(() {
      _hsvColor = HSVColor.fromColor(color);
      _syncControllersFromColor(color, skipRgb: true);
    });
  }

  void _handleWheelInteraction(Offset localPosition, double wheelSize) {
    final double radius = wheelSize / 2;
    final Offset center = Offset(radius, radius);
    final double dx = localPosition.dx - center.dx;
    final double dy = localPosition.dy - center.dy;
    final double dist = math.sqrt(dx * dx + dy * dy);
    final double saturation = (dist / radius).clamp(0.0, 1.0);
    double angleDeg = (math.atan2(dy, dx) * 180.0 / math.pi) % 360.0;
    if (angleDeg < 0) angleDeg += 360.0;

    _onWheelChanged(_hsvColor.withHue(angleDeg).withSaturation(saturation));
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _hsvColor.toColor();
    const double wheelSize = 190.0;

    return Dialog(
      backgroundColor: AppTheme.modalBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select LED Color',
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: currentColor,
                    border: Border.all(color: Colors.white70, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: currentColor.withAlpha(150),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // 1. Interactive Color Wheel
            Center(
              child: GestureDetector(
                onPanStart: (details) => _handleWheelInteraction(details.localPosition, wheelSize),
                onPanUpdate: (details) => _handleWheelInteraction(details.localPosition, wheelSize),
                onTapDown: (details) => _handleWheelInteraction(details.localPosition, wheelSize),
                child: SizedBox(
                  width: wheelSize,
                  height: wheelSize,
                  child: CustomPaint(
                    painter: _ColorWheelPainter(hsvColor: _hsvColor),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Brightness / Value Slider
            Row(
              children: [
                const Icon(Icons.brightness_6, color: Colors.white70, size: 18),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: currentColor,
                      inactiveTrackColor: AppTheme.darkBorder,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _hsvColor.value,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) => _onWheelChanged(_hsvColor.withValue(val)),
                    ),
                  ),
                ),
                Text(
                  '${(_hsvColor.value * 100).round()}%',
                  style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 2. Hex Color Input Field
            TextField(
              controller: _hexController,
              onChanged: _onHexChanged,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              ],
              style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              decoration: InputDecoration(
                counterText: '',
                labelText: 'HEX Color',
                labelStyle: GoogleFonts.exo2(color: Colors.white60, fontSize: 12),
                prefixText: '# ',
                prefixStyle: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: AppTheme.darkSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.darkBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.primaryOrange),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 3. R, G, B Numeric Input Fields
            Row(
              children: [
                Expanded(
                  child: _buildRgbField('R', _rController, const Color(0xFFFF5252)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRgbField('G', _gController, const Color(0xFF00E676)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRgbField('B', _bController, const Color(0xFF448AFF)),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 4. Cancel & Set Color Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: AppTheme.darkBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(currentColor),
                    child: Text(
                      'Set color',
                      style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRgbField(String label, TextEditingController controller, Color accent) {
    return TextField(
      controller: controller,
      onChanged: (_) => _onRgbChanged(),
      keyboardType: TextInputType.number,
      maxLength: 3,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        labelStyle: GoogleFonts.exo2(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
        filled: true,
        fillColor: AppTheme.darkSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withAlpha(100)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final HSVColor hsvColor;

  _ColorWheelPainter({required this.hsvColor});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Hue Sweep Gradient
    const SweepGradient hueGradient = SweepGradient(
      colors: [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );
    canvas.drawCircle(center, radius, Paint()..shader = hueGradient.createShader(rect));

    // 2. Saturation Radial Gradient (White center -> transparent edge)
    const RadialGradient satGradient = RadialGradient(
      colors: [Colors.white, Color(0x00FFFFFF)],
    );
    canvas.drawCircle(center, radius, Paint()..shader = satGradient.createShader(rect));

    // 3. Brightness (Value) overlay
    if (hsvColor.value < 1.0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: (1.0 - hsvColor.value).clamp(0.0, 1.0)),
      );
    }

    // 4. Outer border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 5. Selected thumb marker
    final double angleRad = hsvColor.hue * math.pi / 180.0;
    final double dist = hsvColor.saturation * radius;
    final Offset thumbCenter = Offset(
      center.dx + dist * math.cos(angleRad),
      center.dy + dist * math.sin(angleRad),
    );

    canvas.drawCircle(
      thumbCenter,
      10,
      Paint()..color = hsvColor.toColor(),
    );
    canvas.drawCircle(
      thumbCenter,
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.hsvColor != hsvColor;
  }
}
