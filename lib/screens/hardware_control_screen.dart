import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HardwareControlScreen extends StatefulWidget {
  final String deviceName;

  const HardwareControlScreen({
    super.key,
    required this.deviceName,
  });

  @override
  State<HardwareControlScreen> createState() => _HardwareControlScreenState();
}

class _HardwareControlScreenState extends State<HardwareControlScreen> {
  final Map<int, bool> _gpioStates = {
    4: true,
    17: false,
    27: true,
    22: false,
  };

  final Map<int, double> _servoAngles = {
    0: 90.0,
    1: 45.0,
    2: 120.0,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text('${widget.deviceName} Hardware'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryOrange),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPIO Digital Pins',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            ..._gpioStates.entries.map((entry) {
              final pin = entry.key;
              final state = entry.value;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: ListTile(
                  title: Text(
                    'GPIO $pin',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    state ? 'HIGH (3.3V)' : 'LOW (0V)',
                    style: TextStyle(
                      color: state ? Colors.green : AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Switch(
                    value: state,
                    activeColor: AppTheme.primaryOrange,
                    onChanged: (val) {
                      setState(() => _gpioStates[pin] = val);
                    },
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),
            const Text(
              'PWM Servo Motors (PCA9685)',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),

            ..._servoAngles.entries.map((entry) {
              final ch = entry.key;
              final angle = entry.value;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Servo Channel $ch',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${angle.toInt()}°',
                          style: const TextStyle(
                            color: AppTheme.primaryOrange,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: angle,
                      min: 0.0,
                      max: 180.0,
                      activeColor: AppTheme.primaryOrange,
                      inactiveColor: AppTheme.darkBackground,
                      onChanged: (val) {
                        setState(() => _servoAngles[ch] = val);
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
