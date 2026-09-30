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
              const Icon(Icons.shield, color: AppTheme.primaryOrange, size: 18),
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
              const Icon(Icons.speaker, color: AppTheme.primaryOrange, size: 18),
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
          const SizedBox(height: 12,),

          // audio widgets here


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
