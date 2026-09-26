import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/device_capability.dart';
import '../../theme/app_theme.dart';
import '../dynamic_ui/capability_widget_factory.dart';

/// Fallback card for capabilities that don't have a dedicated widget.
/// Shows name, description, type badge, and key params from the manifest.
class GenericCapabilityCard extends StatelessWidget {
  final DeviceCapability capability;

  const GenericCapabilityCard({super.key, required this.capability});

  @override
  Widget build(BuildContext context) {
    final color = CapabilityWidgetFactory.colorFor(capability.type);
    final icon = CapabilityWidgetFactory.iconFor(capability.type);
    final paramEntries = capability.params.entries.toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capability.name,
                      style: GoogleFonts.exo2(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (capability.description.isNotEmpty)
                      Text(
                        capability.description,
                        style: GoogleFonts.exo2(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withAlpha(80)),
                ),
                child: Text(
                  capability.type.rawValue.toUpperCase(),
                  style: GoogleFonts.exo2(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          if (paramEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: paramEntries.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: GoogleFonts.exo2(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
