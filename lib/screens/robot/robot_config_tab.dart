import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Simplified configuration tab for quadruped robot:
/// Retains only IMU Active Stabilizer toggle and Autonomy switch.
/// Power profiles and dynamics sliders removed.
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
  bool _stabilizerEnabled = true;
  bool _autonomyEnabled = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Control & Safety Configuration',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // 1. IMU Active Stabilizer
          _buildSwitchCard(
            title: 'IMU Active Stabilizer',
            subtitle: 'Uses MPU6050 pitch & roll to dynamically level robot legs on uneven terrain',
            icon: Icons.screen_rotation,
            value: _stabilizerEnabled,
            onChanged: (val) {
              setState(() => _stabilizerEnabled = val);
              widget.onParamChanged('active_stabilizer', val);
            },
          ),

          const SizedBox(height: 14),

          // 2. Autonomy Switch
          _buildSwitchCard(
            title: 'Autonomy Switch',
            subtitle: 'Enable autonomous navigation, local Needle AI perception, and self-balancing',
            icon: Icons.smart_toy,
            value: _autonomyEnabled,
            onChanged: (val) {
              setState(() => _autonomyEnabled = val);
              widget.onParamChanged('autonomy_enabled', val);
            },
          ),
        ],
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
        borderRadius: BorderRadius.circular(18),
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
              size: 24,
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
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.exo2(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.3,
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
