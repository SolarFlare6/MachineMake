import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Movement control tab for quadruped robot:
/// D-Pad joystick, speed slider, gait mode selection, and direction locks.
class RobotMoveTab extends StatefulWidget {
  final Function(String direction) onMove;
  final Function(double speed) onSpeedChanged;
  final Function(String gait) onGaitChanged;

  const RobotMoveTab({
    super.key,
    required this.onMove,
    required this.onSpeedChanged,
    required this.onGaitChanged,
  });

  @override
  State<RobotMoveTab> createState() => _RobotMoveTabState();
}

class _RobotMoveTabState extends State<RobotMoveTab> {
  double _speed = 0.65;
  String _selectedGait = 'walk'; // walk, trot, bound

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gait Selector Segmented Control
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                _buildGaitOption('walk', 'Walk', Icons.directions_walk),
                _buildGaitOption('trot', 'Trot', Icons.pets),
                _buildGaitOption('bound', 'Bound', Icons.bolt),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Central D-Pad Joystick Area
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryOrange.withAlpha(80),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryOrange.withAlpha(20),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Up Button
                  Positioned(
                    top: 14,
                    child: _buildDirectionButton(
                      icon: Icons.keyboard_arrow_up,
                      direction: 'forward',
                    ),
                  ),
                  // Down Button
                  Positioned(
                    bottom: 14,
                    child: _buildDirectionButton(
                      icon: Icons.keyboard_arrow_down,
                      direction: 'backward',
                    ),
                  ),
                  // Left Button
                  Positioned(
                    left: 14,
                    child: _buildDirectionButton(
                      icon: Icons.keyboard_arrow_left,
                      direction: 'left',
                    ),
                  ),
                  // Right Button
                  Positioned(
                    right: 14,
                    child: _buildDirectionButton(
                      icon: Icons.keyboard_arrow_right,
                      direction: 'right',
                    ),
                  ),
                  // Center Stop / Balance Dot
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primaryOrange, width: 2),
                    ),
                    child: const Icon(
                      Icons.navigation,
                      color: AppTheme.primaryOrange,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Speed Slider Control Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Locomotion Speed',
                      style: GoogleFonts.exo2(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${(_speed * 100).toInt()}%',
                      style: GoogleFonts.exo2(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                      widget.onSpeedChanged(val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGaitOption(String key, String label, IconData icon) {
    final isSelected = _selectedGait == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedGait = key);
          widget.onGaitChanged(key);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppTheme.textDarkButton : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.exo2(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppTheme.textDarkButton : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionButton({
    required IconData icon,
    required String direction,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onMove(direction),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
