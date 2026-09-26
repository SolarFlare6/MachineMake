import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/models/device_event.dart';
import '../services/event_manager.dart';
import '../theme/app_theme.dart';

/// Scrollable log of recent events from one or all devices.
/// Pass [deviceId] to filter events for a specific device,
/// or leave null to show all events from the bus.
class EventLogWidget extends StatefulWidget {
  final String? deviceId;
  final int maxEntries;

  const EventLogWidget({
    super.key,
    this.deviceId,
    this.maxEntries = 50,
  });

  @override
  State<EventLogWidget> createState() => _EventLogWidgetState();
}

class _EventLogWidgetState extends State<EventLogWidget> {
  final List<DeviceEvent> _events = [];
  late final _sub = (widget.deviceId != null
          ? EventManager().eventsForDevice(widget.deviceId!)
          : EventManager().events)
      .listen(_onEvent);

  void _onEvent(DeviceEvent event) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, event);
      if (_events.length > widget.maxEntries) {
        _events.removeRange(widget.maxEntries, _events.length);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'telemetry':
        return AppTheme.ramPink;
      case 'alert':
        return Colors.redAccent;
      case 'gpio_change':
        return AppTheme.primaryOrange;
      case 'status_change':
        return Colors.amberAccent;
      case 'camera_frame':
        return AppTheme.gpuCyan;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'telemetry':
        return Icons.analytics;
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'gpio_change':
        return Icons.developer_board;
      case 'status_change':
        return Icons.info_outline;
      case 'camera_frame':
        return Icons.videocam;
      default:
        return Icons.circle_notifications_outlined;
    }
  }

  String _summarize(DeviceEvent event) {
    final d = event.data;
    switch (event.eventType) {
      case 'telemetry':
        final cpu = d['cpu'];
        final ram = d['ram'];
        final temp = d['temp'];
        return [
          if (cpu != null) 'CPU ${cpu.toStringAsFixed(0)}%',
          if (ram != null) 'RAM ${ram.toStringAsFixed(0)}%',
          if (temp != null) 'Temp ${temp.toStringAsFixed(0)}°C',
        ].join('  •  ');
      case 'gpio_change':
        return 'Pin ${d['pin']} → ${d['state'] == true ? 'HIGH' : 'LOW'}';
      case 'alert':
        return d['message']?.toString() ?? 'Alert received';
      default:
        return d.entries.take(3).map((e) => '${e.key}: ${e.value}').join(', ');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.darkBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.circle_notifications_outlined, color: AppTheme.textMuted, size: 20),
            const SizedBox(width: 10),
            Text('Waiting for events...', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      clipBehavior: Clip.hardEdge,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
          color: AppTheme.darkBorder,
          indent: 16,
          endIndent: 16,
        ),
        itemBuilder: (context, index) {
          final event = _events[index];
          final color = _colorFor(event.eventType);
          final icon = _iconFor(event.eventType);
          final timeStr = _formatTime(event.receivedAt);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              event.eventType.toUpperCase(),
                              style: GoogleFonts.exo2(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(event.deviceId, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10)),
                          const Spacer(),
                          Text(timeStr, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _summarize(event),
                        style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
