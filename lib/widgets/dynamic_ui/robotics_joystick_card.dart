import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../theme/app_theme.dart';

/// Simplified robotics joystick card for devices with a robotics capability.
/// Shows a D-pad for directional commands.
class RoboticsJoystickCard extends StatelessWidget {
  final DeviceCapability capability;
  final DeviceConnection? conn;

  const RoboticsJoystickCard({super.key, required this.capability, this.conn});

  void _sendMove(String direction) {
    conn?.session?.executeTool('walk', {'direction': direction, 'speed': 0.6});
  }

  void _sendStop() {
    conn?.session?.executeTool('stop', {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                capability.name,
                style: GoogleFonts.exo2(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _DpadButton(icon: Icons.arrow_upward, onTap: () => _sendMove('forward')),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _DpadButton(icon: Icons.arrow_back, onTap: () => _sendMove('left')),
                      const SizedBox(width: 8),
                      // Center stop button
                      GestureDetector(
                        onTap: _sendStop,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent.withAlpha(120)),
                          ),
                          child: const Icon(Icons.stop, color: Colors.redAccent, size: 22),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DpadButton(icon: Icons.arrow_forward, onTap: () => _sendMove('right')),
                    ],
                  ),
                  _DpadButton(icon: Icons.arrow_downward, onTap: () => _sendMove('backward')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DpadButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _DpadButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withAlpha(100)),
        ),
        child: Icon(icon, color: Colors.greenAccent, size: 22),
      ),
    );
  }
}
