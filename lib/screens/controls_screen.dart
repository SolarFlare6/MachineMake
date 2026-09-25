import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ControlsScreen extends StatefulWidget {
  final String deviceName;

  const ControlsScreen({
    super.key,
    required this.deviceName,
  });

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  double _speed = 0.5;
  String _currentAction = 'Standing';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text('${widget.deviceName} Controls'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryOrange),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'State: $_currentAction',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'READY',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // D-PAD Controller
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  // Forward
                  Align(
                    alignment: Alignment.topCenter,
                    child: _buildDPadButton(
                      icon: Icons.keyboard_arrow_up,
                      label: 'FORWARD',
                      onPressed: () => setState(() => _currentAction = 'Walking Forward'),
                    ),
                  ),
                  // Left
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildDPadButton(
                      icon: Icons.keyboard_arrow_left,
                      label: 'LEFT',
                      onPressed: () => setState(() => _currentAction = 'Turning Left'),
                    ),
                  ),
                  // Center / Stop
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () => setState(() => _currentAction = 'Standing'),
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryOrange,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryOrange.withOpacity(0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'STOP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Right
                  Align(
                    alignment: Alignment.centerRight,
                    child: _buildDPadButton(
                      icon: Icons.keyboard_arrow_right,
                      label: 'RIGHT',
                      onPressed: () => setState(() => _currentAction = 'Turning Right'),
                    ),
                  ),
                  // Backward
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildDPadButton(
                      icon: Icons.keyboard_arrow_down,
                      label: 'BACK',
                      onPressed: () => setState(() => _currentAction = 'Walking Backward'),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Speed Slider
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Gait Speed',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(_speed * 100).toInt()}%',
                      style: const TextStyle(
                        color: AppTheme.primaryOrange,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _speed,
                  activeColor: AppTheme.primaryOrange,
                  inactiveColor: AppTheme.darkCard,
                  onChanged: (val) => setState(() => _speed = val),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Quick Pose Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _currentAction = 'Sitting'),
                    child: const Text('Sit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _currentAction = 'Standing'),
                    child: const Text('Stand'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _currentAction = 'Bow'),
                    child: const Text('Bow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDPadButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.darkBorder, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primaryOrange, size: 28),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
