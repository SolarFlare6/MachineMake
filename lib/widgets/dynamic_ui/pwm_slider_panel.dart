import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../theme/app_theme.dart';

/// PWM channel slider panel.
/// Shows one slider per channel with duty-cycle and frequency controls.
class PwmSliderPanel extends StatefulWidget {
  final DeviceCapability capability;
  final DeviceConnection? conn;

  const PwmSliderPanel({super.key, required this.capability, this.conn});

  @override
  State<PwmSliderPanel> createState() => _PwmSliderPanelState();
}

class _PwmSliderPanelState extends State<PwmSliderPanel> {
  late List<double> _duties;
  final int _frequency = 1000;

  @override
  void initState() {
    super.initState();
    final channelCount =
        (widget.capability.params['channels'] as int?) ?? 4;
    _duties = List.filled(channelCount, 0.0);
  }

  void _setDuty(int channel, double duty) {
    setState(() => _duties[channel] = duty);
    widget.conn?.session?.executeTool('pwm_set', {
      'channel': channel,
      'duty': duty,
      'frequency': _frequency,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.amberAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.capability.name,
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                '$_frequency Hz',
                style: GoogleFonts.exo2(
                  color: Colors.amberAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_duties.length, (ch) {
            return Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        'CH$ch',
                        style: GoogleFonts.exo2(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.amberAccent,
                          thumbColor: Colors.amberAccent,
                          inactiveTrackColor: AppTheme.darkBorder,
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: _duties[ch],
                          onChanged: (v) => _setDuty(ch, v),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${(_duties[ch] * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: GoogleFonts.exo2(
                          color: Colors.amberAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (ch < _duties.length - 1) const SizedBox(height: 4),
              ],
            );
          }),
        ],
      ),
    );
  }
}
