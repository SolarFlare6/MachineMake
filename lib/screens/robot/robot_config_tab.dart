import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Configuration tab for robot parameters: step height, gait frequency, servo trims, and power mode.
class RobotConfigTab extends StatefulWidget {
  final Function(String param, dynamic value) onParamChanged;

  const RobotConfigTab({
    super.key,
    required this.onParamChanged,
  });

  @override
  State<RobotConfigTab> createState() => _RobotConfigTabState();
}

class _RobotConfigTabState extends State<RobotConfigTab> {
  double _stepHeight = 3.5; // cm
  double _gaitFrequency = 1.8; // Hz
  bool _stabilizerEnabled = true;
  bool _obstacleAvoidance = true;
  String _powerMode = 'balanced'; // eco, balanced, sport

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Locomotion Dynamics',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Step Height
          _buildParamCard(
            title: 'Clearance Step Height',
            subtitle: '${_stepHeight.toStringAsFixed(1)} cm',
            slider: Slider(
              value: _stepHeight,
              min: 1.5,
              max: 6.0,
              activeColor: AppTheme.primaryOrange,
              inactiveColor: AppTheme.darkBorder,
              onChanged: (val) {
                setState(() => _stepHeight = val);
                widget.onParamChanged('step_height', val);
              },
            ),
          ),
          const SizedBox(height: 12),

          // Gait Cycle Frequency
          _buildParamCard(
            title: 'Gait Cycle Frequency',
            subtitle: '${_gaitFrequency.toStringAsFixed(1)} Hz',
            slider: Slider(
              value: _gaitFrequency,
              min: 0.8,
              max: 3.2,
              activeColor: AppTheme.primaryOrange,
              inactiveColor: AppTheme.darkBorder,
              onChanged: (val) {
                setState(() => _gaitFrequency = val);
                widget.onParamChanged('gait_frequency', val);
              },
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Safety & Autonomy',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Active Stabilizer Switch
          _buildSwitchCard(
            title: 'IMU Active Stabilizer',
            subtitle: 'Compensate body pitch and roll on uneven terrain',
            value: _stabilizerEnabled,
            onChanged: (val) {
              setState(() => _stabilizerEnabled = val);
              widget.onParamChanged('active_stabilizer', val);
            },
          ),
          const SizedBox(height: 12),

          // Proximity Obstacle Avoidance
          _buildSwitchCard(
            title: 'Auto-Braking & Obstacle Avoidance',
            subtitle: 'Halt forward motion if obstacle < 30 cm detected',
            value: _obstacleAvoidance,
            onChanged: (val) {
              setState(() => _obstacleAvoidance = val);
              widget.onParamChanged('obstacle_avoidance', val);
            },
          ),

          const SizedBox(height: 24),
          Text(
            'Power Profile',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Power Mode Picker
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                _buildPowerOption('eco', 'Eco', Icons.energy_savings_leaf),
                _buildPowerOption('balanced', 'Balanced', Icons.tune),
                _buildPowerOption('sport', 'Sport', Icons.speed),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamCard({
    required String title,
    required String subtitle,
    required Widget slider,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.exo2(
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          slider,
        ],
      ),
    );
  }

  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.exo2(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildPowerOption(String key, String label, IconData icon) {
    final isSelected = _powerMode == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _powerMode = key);
          widget.onParamChanged('power_mode', key);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppTheme.textDarkButton : Colors.white70,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.exo2(
                  color: isSelected ? AppTheme.textDarkButton : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
