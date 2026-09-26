import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Interactive button chip for robot pose presets (stand, sit, balance, etc.)
class RobotPoseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const RobotPoseButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primaryOrange.withAlpha(35)
                : AppTheme.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? AppTheme.primaryOrange : AppTheme.darkBorder,
              width: isActive ? 2 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? AppTheme.primaryOrange : Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.exo2(
                  color: isActive ? AppTheme.primaryOrange : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
