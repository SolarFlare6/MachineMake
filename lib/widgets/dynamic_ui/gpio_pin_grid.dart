import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../theme/app_theme.dart';

/// Interactive GPIO pin grid widget.
/// Renders a toggle grid for each pin listed in [capability.params['pins']].
class GpioPinGrid extends StatefulWidget {
  final DeviceCapability capability;
  final DeviceConnection? conn;

  const GpioPinGrid({super.key, required this.capability, this.conn});

  @override
  State<GpioPinGrid> createState() => _GpioPinGridState();
}

class _GpioPinGridState extends State<GpioPinGrid> {
  late Map<int, bool> _pinStates;

  @override
  void initState() {
    super.initState();
    final pins = (widget.capability.params['pins'] as List<dynamic>?)
            ?.map((p) => p as int)
            .toList() ??
        List.generate(8, (i) => i);
    _pinStates = {for (final p in pins) p: false};
  }

  void _toggle(int pin) {
    final newVal = !(_pinStates[pin] ?? false);
    setState(() => _pinStates[pin] = newVal);
    widget.conn?.session?.executeTool('gpio_write', {'pin': pin, 'state': newVal});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryOrange.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.developer_board, color: AppTheme.primaryOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.capability.name,
                style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              Text(
                '${_pinStates.values.where((v) => v).length}/${_pinStates.length} HIGH',
                style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _pinStates.entries.map((entry) {
              final pin = entry.key;
              final isHigh = entry.value;
              return GestureDetector(
                onTap: () => _toggle(pin),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 54,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isHigh
                        ? AppTheme.primaryOrange.withAlpha(40)
                        : AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isHigh ? AppTheme.primaryOrange : AppTheme.darkBorder,
                      width: isHigh ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'GP$pin',
                        style: GoogleFonts.exo2(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isHigh ? AppTheme.primaryOrange : AppTheme.textMuted,
                        ),
                      ),
                      Text(
                        isHigh ? 'HIGH' : 'LOW',
                        style: GoogleFonts.exo2(
                          fontSize: 9,
                          color: isHigh ? AppTheme.primaryOrange : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
