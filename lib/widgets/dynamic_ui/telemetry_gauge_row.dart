import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../core/models/device_event.dart';
import '../../services/event_manager.dart';
import '../../theme/app_theme.dart';

/// Live telemetry gauge row that subscribes to EventManager for real-time updates.
class TelemetryGaugeRow extends StatefulWidget {
  final DeviceCapability capability;
  final DeviceConnection? conn;

  const TelemetryGaugeRow({super.key, required this.capability, this.conn});

  @override
  State<TelemetryGaugeRow> createState() => _TelemetryGaugeRowState();
}

class _TelemetryGaugeRowState extends State<TelemetryGaugeRow> {
  double _cpu = 0;
  double _ram = 0;
  double _temp = 0;

  late final Stream<DeviceEvent> _stream;
  late final _sub = _stream.listen(_onEvent);

  @override
  void initState() {
    super.initState();
    _stream = widget.conn != null
        ? EventManager().eventsForDevice(widget.conn!.deviceId)
        : const Stream.empty();
  }

  void _onEvent(DeviceEvent event) {
    if (event.eventType == 'telemetry' && mounted) {
      setState(() {
        _cpu = (event.data['cpu'] as num?)?.toDouble() ?? _cpu;
        _ram = (event.data['ram'] as num?)?.toDouble() ?? _ram;
        _temp = (event.data['temp'] as num?)?.toDouble() ?? _temp;
      });
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.ramPink.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: AppTheme.ramPink, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.capability.name,
                style: GoogleFonts.exo2(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              _LiveDot(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _GaugeItem(value: _cpu, label: 'CPU', unit: '%', color: AppTheme.cpuOrange),
              _GaugeItem(value: _ram, label: 'RAM', unit: '%', color: AppTheme.ramPink),
              _GaugeItem(value: _temp, label: 'Temp', unit: '°C', color: AppTheme.tempBlue),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugeItem extends StatelessWidget {
  final double value;
  final String label;
  final String unit;
  final Color color;

  const _GaugeItem({
    required this.value,
    required this.label,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '${value.toStringAsFixed(0)}$unit',
          style: GoogleFonts.exo2(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        SizedBox(
          width: 72,
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            backgroundColor: AppTheme.darkBorder,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.ramPink.withAlpha((_ctrl.value * 255).round()),
        ),
      ),
    );
  }
}
