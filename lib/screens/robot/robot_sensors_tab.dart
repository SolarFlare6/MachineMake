import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_imu_display.dart';

/// Telemetry & Audio tab for the quadruped robot:
/// - MPU6050 Gyro & Accel attitude telemetry cards
/// - Audio & Buzzer expandable accordion:
///     1. Pygame Mixer Speaker (volume slider, sound presets, custom file playback)
///     2. GPIO 23 Tonal Buzzer (piano keys C4-C5, custom note, melody sequences, silence)
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

  double _accelX = 0.02;
  double _accelY = -0.05;
  double _accelZ = 0.98;
  double _gyroX = 0.8;
  double _gyroY = -1.2;
  double _gyroZ = 0.3;

  // ── Accordion Expansion State ─────────────────────────────────────
  bool _isAudioExpanded = false;

  // ── Speaker State (pygame.mixer) ──────────────────────────────────
  double _volume = 0.8;
  String? _currentlyPlaying;
  final TextEditingController _filePathCtrl =
      TextEditingController(text: '/home/pi/audio/bark.wav');

  // ── Buzzer State (GPIO 23 TonalBuzzer) ─────────────────────────────
  String? _activeNote;
  final TextEditingController _customNoteCtrl =
      TextEditingController(text: 'C4');

  static const List<String> _kbNotes = [
    'C4', 'D4', 'E4', 'F4', 'G4', 'A4', 'B4', 'C5',
  ];

  static const List<Map<String, dynamic>> _kPresets = [
    {'title': 'Dog Bark',     'icon': Icons.pets,             'file': '/home/pi/audio/bark.wav',        'color': Color(0xFF4FC3F7)},
    {'title': 'Alert Siren',  'icon': Icons.warning_amber,    'file': '/home/pi/audio/alert.wav',       'color': Colors.redAccent},
    {'title': 'Greeting',     'icon': Icons.waving_hand,      'file': '/home/pi/audio/hello.wav',       'color': Color(0xFF00E676)},
    {'title': 'Robot Beep',   'icon': Icons.smart_toy,        'file': '/home/pi/audio/r2d2.wav',        'color': Colors.amberAccent},
    {'title': 'Warning Tone', 'icon': Icons.shield_outlined,  'file': '/home/pi/audio/warning.wav',     'color': Colors.orangeAccent},
    {'title': 'Low Power',    'icon': Icons.battery_alert,    'file': '/home/pi/audio/low_battery.wav', 'color': Colors.deepOrangeAccent},
  ];

  static const List<Map<String, dynamic>> _kMelodies = [
    {'label': 'C Scale ↑',  'icon': Icons.trending_up,                  'notes': ['C4','D4','E4','F4','G4','A4','B4','C5'], 'color': null},
    {'label': 'C Scale ↓',  'icon': Icons.trending_down,                'notes': ['C5','B4','A4','G4','F4','E4','D4','C4'], 'color': null},
    {'label': 'Success',    'icon': Icons.check_circle_outline,          'notes': ['C4','E4','G4','C5'],                     'color': Color(0xFF00E676)},
    {'label': 'Warning',    'icon': Icons.notifications_active_outlined, 'notes': ['A4','F4','A4','F4'],                     'color': Colors.amberAccent},
    {'label': 'Alert ×3',  'icon': Icons.error_outline,                 'notes': ['E5','E5','E5'],                          'color': Colors.redAccent},
  ];

  @override
  void initState() {
    super.initState();
    _pitch = widget.pitch;
    _roll = widget.roll;
  }

  @override
  void dispose() {
    _filePathCtrl.dispose();
    _customNoteCtrl.dispose();
    super.dispose();
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

  // ── Speaker DCP (pygame.mixer) ────────────────────────────────────
  void _playAudio(String path, {String? label}) {
    setState(() => _currentlyPlaying = label ?? path);
    _exec('play_audio', {'file_path': path});
    _snack('Playing: ${label ?? path}', const Color(0xFF4FC3F7));
  }

  void _stopAudio() {
    setState(() => _currentlyPlaying = null);
    _exec('stop_audio', {});
    _snack('Audio playback stopped', AppTheme.textMuted);
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    _exec('set_volume', {'volume': v});
  }

  // ── Buzzer DCP (GPIO 23 TonalBuzzer) ──────────────────────────────
  void _playTone(String tone) {
    setState(() => _activeNote = tone);
    _exec('play_tone', {'tone': tone});
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _activeNote == tone) {
        setState(() => _activeNote = null);
      }
    });
  }

  void _playNoteList(String label, List<String> notes) {
    _exec('play_list_of_notes', {'notes': notes});
    _snack('Melody: $label', AppTheme.primaryOrange);
  }

  void _stopTone() {
    setState(() => _activeNote = null);
    _exec('stop_tone', {});
    _snack('Buzzer silenced', Colors.amberAccent);
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

          // ── Audio & Buzzer Accordion (Clean, no overlap) ──────────
          _buildAccordionCard(
            title: 'Audio & Buzzer',
            icon: Icons.volume_up,
            isExpanded: _isAudioExpanded,
            onToggle: () => setState(() => _isAudioExpanded = !_isAudioExpanded),
            child: _buildAudioBuzzerContent(),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Accordion Card Builder ───────────────────────────────────────
  Widget _buildAccordionCard({
    required String title,
    required IconData icon,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: isExpanded ? AppTheme.primaryOrange : AppTheme.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.exo2(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
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

  // ─── Audio & Buzzer Content ───────────────────────────────────────
  Widget _buildAudioBuzzerContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Speaker Section (pygame.mixer) ───────────────────────
        _sectionHeader(
          icon: Icons.speaker,
          color: const Color(0xFF4FC3F7),
          title: 'Speaker  —  pygame.mixer',
        ),
        const SizedBox(height: 10),
        _buildSpeakerControls(),

        const SizedBox(height: 20),
        Container(height: 1, color: AppTheme.darkBorder),
        const SizedBox(height: 18),

        // ── 2. Buzzer Section (GPIO 23 TonalBuzzer) ─────────────────
        _sectionHeader(
          icon: Icons.piano,
          color: AppTheme.primaryOrange,
          title: 'Tonal Buzzer  —  GPIO 23',
        ),
        const SizedBox(height: 10),
        _buildBuzzerControls(),
      ],
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required Color color,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
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
      ],
    );
  }

  // ─── Speaker Controls (Volume, Presets, Custom Path) ──────────────
  Widget _buildSpeakerControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Volume Slider & Stop Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Row(
            children: [
              Icon(
                _volume == 0 ? Icons.volume_off : Icons.volume_down,
                color: AppTheme.textMuted,
                size: 16,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF4FC3F7),
                    inactiveTrackColor: AppTheme.darkBorder,
                    thumbColor: const Color(0xFF4FC3F7),
                    overlayColor: const Color(0xFF4FC3F7).withAlpha(25),
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0,
                    max: 1,
                    onChanged: _setVolume,
                  ),
                ),
              ),
              Text(
                '${(_volume * 100).toInt()}%',
                style: GoogleFonts.firaCode(
                  color: const Color(0xFF4FC3F7),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (_currentlyPlaying != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _stopAudio,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stop, color: Colors.redAccent, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          'Stop',
                          style: GoogleFonts.exo2(color: Colors.redAccent, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),
        Text(
          'Soundboard Presets (play_audio)',
          style: GoogleFonts.exo2(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        // Presets Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _kPresets.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.8,
          ),
          itemBuilder: (context, i) {
            final p = _kPresets[i];
            final isPlaying = _currentlyPlaying == p['title'];
            final col = p['color'] as Color;
            return InkWell(
              onTap: () => _playAudio(p['file'] as String, label: p['title'] as String),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isPlaying ? col.withAlpha(40) : AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPlaying ? col : AppTheme.darkBorder,
                    width: isPlaying ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(p['icon'] as IconData, color: col, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p['title'] as String,
                        style: GoogleFonts.exo2(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      isPlaying ? Icons.graphic_eq : Icons.play_arrow,
                      color: col,
                      size: 14,
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 12),
        Text(
          'Custom Audio File Path',
          style: GoogleFonts.exo2(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _filePathCtrl,
                style: GoogleFonts.firaCode(color: Colors.white, fontSize: 11),
                decoration: InputDecoration(
                  hintText: '/home/pi/audio/sound.wav',
                  hintStyle: GoogleFonts.firaCode(color: AppTheme.textMuted, fontSize: 10),
                  filled: true,
                  fillColor: AppTheme.darkSurface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF4FC3F7)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final path = _filePathCtrl.text.trim();
                if (path.isNotEmpty) _playAudio(path);
              },
              icon: const Icon(Icons.play_arrow, size: 16),
              label: Text(
                'Play',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _stopAudio,
              child: Text(
                'Stop',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Buzzer Controls (Piano Keyboard, Custom Note, Melodies) ──────
  Widget _buildBuzzerControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Note Keyboard
        Text(
          'Note Keyboard (play_tone)',
          style: GoogleFonts.exo2(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        Row(
          children: _kbNotes.map((note) {
            final pressed = _activeNote == note;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: GestureDetector(
                  onTapDown: (_) => _playTone(note),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 58,
                    decoration: BoxDecoration(
                      color: pressed ? AppTheme.primaryOrange : const Color(0xFF1E222B),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: pressed ? AppTheme.primaryOrange : AppTheme.darkBorder,
                        width: 1.2,
                      ),
                      boxShadow: pressed
                          ? [
                              BoxShadow(
                                color: AppTheme.primaryOrange.withAlpha(100),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      note,
                      style: GoogleFonts.firaCode(
                        color: pressed ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 10),

        // Custom Note + Silence Row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customNoteCtrl,
                style: GoogleFonts.firaCode(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Custom note (e.g. D5, F#4)',
                  labelStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
                  filled: true,
                  fillColor: AppTheme.darkSurface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.primaryOrange),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final n = _customNoteCtrl.text.trim();
                if (n.isNotEmpty) _playTone(n);
              },
              icon: const Icon(Icons.music_note, size: 15),
              label: Text(
                'Play',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amberAccent,
                side: const BorderSide(color: Colors.amberAccent),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _stopTone,
              child: Text(
                'Silence',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Melody Sequences (play_list_of_notes)
        Text(
          'Melody Sequences (play_list_of_notes)',
          style: GoogleFonts.exo2(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kMelodies.map((m) {
            final col = (m['color'] as Color?) ?? AppTheme.primaryOrange;
            return OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: col,
                side: BorderSide(color: col.withAlpha(130)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _playNoteList(
                m['label'] as String,
                List<String>.from(m['notes'] as List),
              ),
              icon: Icon(m['icon'] as IconData, size: 13),
              label: Text(
                m['label'] as String,
                style: GoogleFonts.exo2(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            );
          }).toList(),
        ),
      ],
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
