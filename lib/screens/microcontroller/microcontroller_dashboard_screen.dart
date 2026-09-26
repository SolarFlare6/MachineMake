import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../models/dcp_models.dart';
import '../../theme/app_theme.dart';

/// Specialized dashboard for microcontroller profiles (Pico, ESP32, Arduino).
class MicrocontrollerDashboardScreen extends StatefulWidget {
  final DeviceItem device;
  final DeviceConnection? conn;
  final DeviceManifest? manifest;

  const MicrocontrollerDashboardScreen({
    super.key,
    required this.device,
    this.conn,
    this.manifest,
  });

  @override
  State<MicrocontrollerDashboardScreen> createState() => _MicrocontrollerDashboardScreenState();
}

class _MicrocontrollerDashboardScreenState extends State<MicrocontrollerDashboardScreen> {
  final Map<int, bool> _gpioStates = {
    0: false, 1: true, 2: false, 3: false,
    4: true, 5: false, 14: true, 15: false,
  };

  double _pwmDuty = 0.5;
  int _pwmFrequency = 1000; // Hz

  void _togglePin(int pin) {
    final current = _gpioStates[pin] ?? false;
    final newState = !current;
    setState(() => _gpioStates[pin] = newState);
    widget.conn?.session?.executeTool('gpio_write', {'pin': pin, 'state': newState});
  }

  void _setDuty(double val) {
    setState(() => _pwmDuty = val);
    widget.conn?.session?.executeTool('pwm_set', {'channel': 0, 'duty': val, 'frequency': _pwmFrequency});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          widget.device.name,
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withAlpha(35),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.memory, color: AppTheme.primaryOrange, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.device.deviceType, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13)),
                        Text('Hardware Bus Controller', style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Text('Digital GPIO Pins', style: GoogleFonts.exo2(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),

            // GPIO Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _gpioStates.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final pin = _gpioStates.keys.elementAt(index);
                final isOn = _gpioStates[pin] ?? false;

                return InkWell(
                  onTap: () => _togglePin(pin),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isOn ? AppTheme.primaryOrange.withAlpha(35) : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isOn ? AppTheme.primaryOrange : AppTheme.darkBorder,
                        width: isOn ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('GP$pin', style: GoogleFonts.exo2(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          isOn ? 'HIGH' : 'LOW',
                          style: GoogleFonts.exo2(
                            color: isOn ? AppTheme.primaryOrange : AppTheme.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
            Text('Hardware PWM Channel 0', style: GoogleFonts.exo2(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),

            // PWM Slider Card
            Container(
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
                      Text('Duty Cycle', style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      Text('${(_pwmDuty * 100).toInt()}%', style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Slider(
                    value: _pwmDuty,
                    min: 0.0,
                    max: 1.0,
                    activeColor: AppTheme.primaryOrange,
                    inactiveColor: AppTheme.darkBorder,
                    onChanged: _setDuty,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
