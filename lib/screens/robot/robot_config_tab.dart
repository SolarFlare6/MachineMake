import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../theme/app_theme.dart';

/// Configuration tab for the quadruped robot:
/// Control & Safety switches (IMU Active Stabilizer, Autonomy Switch).
class RobotConfigTab extends StatefulWidget {
  final Function(String param, dynamic value) onParamChanged;
  final DeviceConnection? conn;

  const RobotConfigTab({
    super.key,
    required this.onParamChanged,
    this.conn,
  });

  @override
  State<RobotConfigTab> createState() => _RobotConfigTabState();
}

class _RobotConfigTabState extends State<RobotConfigTab> {
  bool _stabilizerEnabled = true;
  bool _autonomyEnabled = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          Row(
            children: [
              Icon(Icons.shield, color: AppTheme.primaryOrange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Control & Safety',
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildSwitchCard(
            title: 'IMU Active Stabilizer',
            subtitle: 'Uses MPU6050 pitch & roll to dynamically level legs on uneven terrain',
            icon: Icons.screen_rotation,
            value: _stabilizerEnabled,
            onChanged: (val) {
              setState(() => _stabilizerEnabled = val);
              widget.onParamChanged('active_stabilizer', val);
            },
          ),

          const SizedBox(height: 12),

          _buildSwitchCard(
            title: 'Autonomy Switch',
            subtitle: 'Enable autonomous navigation, Needle AI perception and self-balancing',
            icon: Icons.smart_toy,
            value: _autonomyEnabled,
            onChanged: (val) {
              setState(() => _autonomyEnabled = val);
              widget.onParamChanged('autonomy_enabled', val);
            },
          ),

          const SizedBox(height: 20),

          // audio section title
          Row(
            children: [
              Icon(Icons.speaker, color: AppTheme.primaryOrange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Audio control',
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // spacer
          const SizedBox(height: 12),

          // audio widgets here
          _AudioControlSection(conn: widget.conn),

          // this is the end of the audio widgets section

        ], // end of the children in the screen
      ),
    );
  }

  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? AppTheme.primaryOrange.withAlpha(120) : AppTheme.darkBorder,
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: value ? AppTheme.primaryOrange.withAlpha(30) : AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: value ? AppTheme.primaryOrange : AppTheme.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.exo2(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: AppTheme.primaryOrange,
            activeTrackColor: AppTheme.primaryOrange.withAlpha(80),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Audio Control Section ─────────────────────────────────────────────────────
// Extracted into its own StatefulWidget so slider state doesn't rebuild the
// entire Config tab on every change.
class _AudioControlSection extends StatefulWidget {
  final DeviceConnection? conn;
  const _AudioControlSection({this.conn});

  @override
  State<_AudioControlSection> createState() => _AudioControlSectionState();
}

class _AudioControlSectionState extends State<_AudioControlSection> {
  // ── Buzzer state ──────────────────────────────────────────────────
  double _frequency = 440.0; // Hz  (A4 = 440 Hz)
  double _duration  = 0.5;   // seconds
  String? _activeTone;

  static const List<Map<String, dynamic>> _kTones = [
    {'label': 'Short Beep',  'icon': Icons.notifications_outlined,  'action': 'single', 'color': Color(0xFF4FC3F7)},
    {'label': 'Double Beep', 'icon': Icons.notifications_active,    'action': 'double', 'color': Color(0xFF81D4FA)},
    {'label': 'Success',     'icon': Icons.check_circle_outline,    'action': 'success','color': Color(0xFF00E676)},
    {'label': 'Warning',     'icon': Icons.warning_amber_rounded,   'action': 'warning','color': Colors.amberAccent},
    {'label': 'Alert ×3',   'icon': Icons.error_outline,           'action': 'alert',  'color': Colors.redAccent},
    {'label': 'Low Power',   'icon': Icons.battery_alert,           'action': 'low',    'color': Colors.orangeAccent},
  ];

  // ── Audio file state ──────────────────────────────────────────────
  double _volume = 0.8;
  String? _playingFile;
  String _selectedFile = '/home/pi/audio/bark.wav';

  static const List<Map<String, dynamic>> _kFiles = [
    {'name': 'Dog Bark',     'file': '/home/pi/audio/bark.wav',        'icon': Icons.pets,            'color': Color(0xFF4FC3F7)},
    {'name': 'Alert Siren',  'file': '/home/pi/audio/alert.wav',       'icon': Icons.warning_amber,   'color': Colors.redAccent},
    {'name': 'Greeting',     'file': '/home/pi/audio/hello.wav',       'icon': Icons.waving_hand,     'color': Color(0xFF00E676)},
    {'name': 'Robot Beep',   'file': '/home/pi/audio/r2d2.wav',        'icon': Icons.smart_toy,       'color': Colors.amberAccent},
    {'name': 'Warning Tone', 'file': '/home/pi/audio/warning.wav',     'icon': Icons.shield_outlined, 'color': Colors.orangeAccent},
    {'name': 'Low Battery',  'file': '/home/pi/audio/low_battery.wav', 'icon': Icons.battery_alert,   'color': Colors.deepOrangeAccent},
  ];

  // ── DCP helpers ───────────────────────────────────────────────────
  void _exec(String tool, Map<String, dynamic> params) =>
      widget.conn?.session?.executeTool(tool, params);

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.exo2()),
        backgroundColor: bg,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Buzzer DCP (mini_speaker_imp.py) ──────────────────────────────
  void _handleToneBtn(Map<String, dynamic> t) {
    final label = t['label'] as String;
    setState(() => _activeTone = label);
    switch (t['action'] as String) {
      case 'single':
        _exec('play_tone', {'tone': 'C5'});
      case 'double':
        _exec('play_list_of_notes', {'notes': ['C5', 'C5']});
      case 'success':
        _exec('play_list_of_notes', {'notes': ['C4', 'E4', 'G4', 'C5']});
      case 'warning':
        _exec('play_list_of_notes', {'notes': ['A4', 'F4', 'A4', 'F4']});
      case 'alert':
        _exec('play_list_of_notes', {'notes': ['E5', 'E5', 'E5']});
      case 'low':
        _exec('play_tone', {'tone': 'A3'});
    }
    Future.delayed(const Duration(milliseconds: 700),
        () { if (mounted && _activeTone == label) setState(() => _activeTone = null); });
  }

  void _playCustomFrequency() {
    _exec('play_freq', {'frequency': _frequency.round(), 'duration': _duration});
    _snack('Buzzer: ${_frequency.round()} Hz · ${_duration.toStringAsFixed(1)} s',
        AppTheme.primaryOrange);
  }

  void _stopTone() {
    setState(() => _activeTone = null);
    _exec('stop_tone', {});
    _snack('Buzzer silenced', Colors.amberAccent);
  }

  // ── Speaker DCP (speaker_audio_imp.py) ────────────────────────────
  void _playFile(String file, String name) {
    setState(() { _playingFile = file; _selectedFile = file; });
    _exec('play_audio', {'file_path': file});
    _snack('Playing: $name', const Color(0xFF4FC3F7));
  }

  void _stopAudio() {
    setState(() => _playingFile = null);
    _exec('stop_audio', {});
    _snack('Audio stopped', Colors.white24);
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    _exec('set_volume', {'volume': v});
  }

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBuzzerCard(),
        const SizedBox(height: 16),
        _buildAudioFileCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Buzzer Card ───────────────────────────────────────────────────
  Widget _buildBuzzerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(children: [
            Icon(Icons.piano, color: AppTheme.primaryOrange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tonal Buzzer  —  GPIO 23',
                    style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('play_tone · play_list_of_notes · play_freq',
                    style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10)),
              ]),
            ),
            GestureDetector(
              onTap: _stopTone,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.volume_off, color: Colors.amberAccent, size: 13),
                  const SizedBox(width: 4),
                  Text('Silence',
                      style: GoogleFonts.exo2(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ]),

          const SizedBox(height: 14),

          // Quick tone buttons
          Text('Quick Tones',
              style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kTones.map((t) {
              final col = t['color'] as Color;
              final isActive = _activeTone == t['label'];
              return GestureDetector(
                onTap: () => _handleToneBtn(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? col.withAlpha(50) : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isActive ? col : AppTheme.darkBorder,
                        width: isActive ? 1.5 : 1.0),
                    boxShadow: isActive
                        ? [BoxShadow(color: col.withAlpha(60), blurRadius: 8)]
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t['icon'] as IconData, color: col, size: 15),
                    const SizedBox(width: 6),
                    Text(t['label'] as String,
                        style: GoogleFonts.exo2(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // Frequency slider
          Row(children: [
            Icon(Icons.waves, color: AppTheme.primaryOrange, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Frequency',
                  style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text('${_frequency.round()} Hz',
                style: GoogleFonts.firaCode(
                    color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.primaryOrange,
              inactiveTrackColor: AppTheme.darkBorder,
              thumbColor: AppTheme.primaryOrange,
              overlayColor: AppTheme.primaryOrange.withAlpha(25),
            ),
            child: Slider(
              value: _frequency,
              min: 100,
              max: 4000,
              divisions: 78,
              onChanged: (v) => setState(() => _frequency = v),
            ),
          ),

          // Duration slider
          Row(children: [
            Icon(Icons.timer_outlined, color: AppTheme.primaryOrange, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Duration',
                  style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text('${_duration.toStringAsFixed(1)} s',
                style: GoogleFonts.firaCode(
                    color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.primaryOrange,
              inactiveTrackColor: AppTheme.darkBorder,
              thumbColor: AppTheme.primaryOrange,
              overlayColor: AppTheme.primaryOrange.withAlpha(25),
            ),
            child: Slider(
              value: _duration,
              min: 0.1,
              max: 3.0,
              divisions: 29,
              onChanged: (v) => setState(() => _duration = v),
            ),
          ),

          const SizedBox(height: 6),

          // Play custom frequency button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _playCustomFrequency,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(
                'Play ${_frequency.round()} Hz · ${_duration.toStringAsFixed(1)} s',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Audio File Card ───────────────────────────────────────────────
  Widget _buildAudioFileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.volume_up, color: Color(0xFF4FC3F7), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Speaker  —  pygame.mixer',
                    style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('play_audio · stop_audio · set_volume',
                    style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10)),
              ]),
            ),
            if (_playingFile != null)
              GestureDetector(
                onTap: _stopAudio,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent.withAlpha(80)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.stop, color: Colors.redAccent, size: 13),
                    const SizedBox(width: 4),
                    Text('Stop',
                        style: GoogleFonts.exo2(
                            color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
          ]),

          const SizedBox(height: 12),

          // Volume slider
          Row(children: [
            Icon(_volume == 0 ? Icons.volume_off : Icons.volume_down,
                color: AppTheme.textMuted, size: 16),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF4FC3F7),
                  inactiveTrackColor: AppTheme.darkBorder,
                  thumbColor: const Color(0xFF4FC3F7),
                  overlayColor: const Color(0xFF4FC3F7).withAlpha(25),
                ),
                child: Slider(value: _volume, min: 0, max: 1, onChanged: _setVolume),
              ),
            ),
            Text('${(_volume * 100).toInt()}%',
                style: GoogleFonts.firaCode(
                    color: const Color(0xFF4FC3F7), fontSize: 12, fontWeight: FontWeight.bold)),
          ]),

          const SizedBox(height: 10),

          // File selection label
          Text('Select file to play',
              style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          // Files grid – tap to select, double-tap plays immediately
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _kFiles.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.7,
            ),
            itemBuilder: (context, i) {
              final f = _kFiles[i];
              final path = f['file'] as String;
              final col = f['color'] as Color;
              final isPlaying = _playingFile == path;
              final isSelected = _selectedFile == path && !isPlaying;

              return InkWell(
                onTap: () {
                  // single tap = select; if already selected, play
                  if (isSelected) {
                    _playFile(path, f['name'] as String);
                  } else {
                    setState(() => _selectedFile = path);
                  }
                },
                onDoubleTap: () => _playFile(path, f['name'] as String),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? col.withAlpha(40)
                        : (isSelected ? AppTheme.primaryOrange.withAlpha(20) : AppTheme.darkSurface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isPlaying
                          ? col
                          : (isSelected ? AppTheme.primaryOrange : AppTheme.darkBorder),
                      width: (isPlaying || isSelected) ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(children: [
                    Icon(f['icon'] as IconData, color: col, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f['name'] as String,
                          style: GoogleFonts.exo2(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Icon(
                      isPlaying
                          ? Icons.graphic_eq
                          : (isSelected ? Icons.check_circle : Icons.play_arrow),
                      color: isSelected ? AppTheme.primaryOrange : col,
                      size: 14,
                    ),
                  ]),
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // Play selected button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4FC3F7),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final match = _kFiles.where((f) => f['file'] == _selectedFile);
                final name = match.isNotEmpty ? match.first['name'] as String : _selectedFile;
                _playFile(_selectedFile, name);
              },
              icon: Icon(_playingFile != null ? Icons.graphic_eq : Icons.play_arrow, size: 18),
              label: Text(
                _playingFile != null ? 'Now playing…' : 'Play selected file',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
