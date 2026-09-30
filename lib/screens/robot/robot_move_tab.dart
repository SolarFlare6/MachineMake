import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
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
    widget.conn?.session?.executeTool('turn_on_strip_with_color', {
      'r': r,
      'g': g,
      'b': b,
    });
    setState(() => _currentLedColor = Color.fromARGB(255, r, g, b));
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
                child: Container(
                  height: 130,
                  decoration: BoxDecoration(
                    color: const Color(0xFF131418),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.darkBorder, width: 1.2),
                  ),
                  child: Stack(
                    children: [
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
                    icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryOrange),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 8 LED Strip preview indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('WS281x (8-LED Strip):', style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13)),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentLedColor,
                boxShadow: [
                  BoxShadow(
                    color: _currentLedColor.withAlpha(120),
                    blurRadius: 6,
                  ),
                ],
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
            _buildQuickActionBtn('Process Run', () => _runLedAnimation('animate_running_process')),
            _buildQuickActionBtn('Alert Flash', () => _runLedAnimation('flash_alert'), color: Colors.redAccent),
            _buildQuickActionBtn('OK Blink', () => _runLedAnimation('blink_oke'), color: Colors.greenAccent),
            _buildQuickActionBtn('Warning Blink', () => _runLedAnimation('blink_warning'), color: Colors.amberAccent),
            _buildQuickActionBtn('Beep Buzzer', _playBuzzer, color: AppTheme.primaryOrange),
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
