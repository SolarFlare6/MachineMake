import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/robot/robot_pose_button.dart';

/// Pose tab for robot/quadruped kinematics and posture presets.
class RobotPoseTab extends StatefulWidget {
  final Function(String pose) onPoseSelected;
  final Function(double pitch, double roll, double height) onAdjustKinematics;

  const RobotPoseTab({
    super.key,
    required this.onPoseSelected,
    required this.onAdjustKinematics,
  });

  @override
  State<RobotPoseTab> createState() => _RobotPoseTabState();
}

class _RobotPoseTabState extends State<RobotPoseTab> {
  String _activePose = 'stand';
  double _pitch = 0.0; // -20 to +20
  double _roll = 0.0;  // -20 to +20
  double _bodyHeight = 0.65; // 0.2 to 1.0

  void _selectPose(String pose) {
    setState(() => _activePose = pose);
    widget.onPoseSelected(pose);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Posture Presets',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Grid of pose buttons
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              RobotPoseButton(
                label: 'Stand Up',
                icon: Icons.accessibility_new,
                isActive: _activePose == 'stand',
                onTap: () => _selectPose('stand'),
              ),
              RobotPoseButton(
                label: 'Sit Down',
                icon: Icons.airline_seat_recline_normal,
                isActive: _activePose == 'sit',
                onTap: () => _selectPose('sit'),
              ),
              RobotPoseButton(
                label: 'Balance',
                icon: Icons.balance,
                isActive: _activePose == 'balance',
                onTap: () => _selectPose('balance'),
              ),
              RobotPoseButton(
                label: 'Stretch',
                icon: Icons.fitness_center,
                isActive: _activePose == 'stretch',
                onTap: () => _selectPose('stretch'),
              ),
              RobotPoseButton(
                label: 'Lean Left',
                icon: Icons.turn_left,
                isActive: _activePose == 'lean_left',
                onTap: () => _selectPose('lean_left'),
              ),
              RobotPoseButton(
                label: 'Lean Right',
                icon: Icons.turn_right,
                isActive: _activePose == 'lean_right',
                onTap: () => _selectPose('lean_right'),
              ),
            ],
          ),

          const SizedBox(height: 28),

          Text(
            'Attitude & Height Fine-Tuning',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Height Slider
          _buildSliderCard(
            label: 'Body Height',
            value: _bodyHeight,
            min: 0.2,
            max: 1.0,
            displayValue: '${(_bodyHeight * 100).toInt()}%',
            onChanged: (val) {
              setState(() => _bodyHeight = val);
              widget.onAdjustKinematics(_pitch, _roll, _bodyHeight);
            },
          ),
          const SizedBox(height: 12),

          // Pitch Slider
          _buildSliderCard(
            label: 'Pitch Tilt',
            value: _pitch,
            min: -20.0,
            max: 20.0,
            displayValue: '${_pitch.toStringAsFixed(1)}°',
            onChanged: (val) {
              setState(() => _pitch = val);
              widget.onAdjustKinematics(_pitch, _roll, _bodyHeight);
            },
          ),
          const SizedBox(height: 12),

          // Roll Slider
          _buildSliderCard(
            label: 'Roll Tilt',
            value: _roll,
            min: -20.0,
            max: 20.0,
            displayValue: '${_roll.toStringAsFixed(1)}°',
            onChanged: (val) {
              setState(() => _roll = val);
              widget.onAdjustKinematics(_pitch, _roll, _bodyHeight);
            },
          ),

          const SizedBox(height: 20),

          // Reset Button
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _pitch = 0.0;
                _roll = 0.0;
                _bodyHeight = 0.65;
                _activePose = 'stand';
              });
              widget.onAdjustKinematics(0.0, 0.0, 0.65);
              widget.onPoseSelected('stand');
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.primaryOrange),
              foregroundColor: AppTheme.primaryOrange,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.refresh),
            label: Text(
              'Reset Neutral Attitude',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCard({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                label,
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                displayValue,
                style: GoogleFonts.exo2(
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            activeColor: AppTheme.primaryOrange,
            inactiveColor: AppTheme.darkBorder,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
