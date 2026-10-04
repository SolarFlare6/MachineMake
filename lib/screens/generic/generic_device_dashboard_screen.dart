import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../models/dcp_models.dart';
import '../../services/capability_manager.dart';
import '../../services/device_manager.dart';
import '../../services/tool_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dynamic_ui/capability_widget_factory.dart';
import '../../widgets/dynamic_ui/tool_invoke_card.dart';

/// Fallback dashboard for generic or non-robot device profiles.
/// Auto-generates capability widgets and tool invocation cards from the device manifest,
/// falling back to live CapabilityManager and ToolManager registries.
class GenericDeviceDashboardScreen extends StatelessWidget {
  final DeviceItem device;
  final DeviceConnection? conn;
  final DeviceManifest? manifest;

  const GenericDeviceDashboardScreen({
    super.key,
    required this.device,
    this.conn,
    this.manifest,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveConn = conn ?? DeviceManager().getConnection(device.id);

    return ListenableBuilder(
      listenable: Listenable.merge([
        CapabilityManager(),
        ToolManager(),
        if (effectiveConn != null) effectiveConn,
      ]),
      builder: (context, _) {
        final manifestCaps = manifest?.capabilities ?? [];
        final capabilities = manifestCaps.isNotEmpty
            ? manifestCaps
            : CapabilityManager().getCapabilities(device.id);

        final manifestTools = manifest?.tools ?? [];
        final tools = manifestTools.isNotEmpty
            ? manifestTools
            : ToolManager().getTools(device.id);

        final activeManifest = manifest ?? effectiveConn?.manifest;

        return Scaffold(
          backgroundColor: AppTheme.darkBackground,
          appBar: AppBar(
            backgroundColor: AppTheme.darkSurface,
            title: Text(
              device.name,
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              if (activeManifest != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withAlpha(100)),
                      ),
                      child: Text(
                        activeManifest.type.toUpperCase(),
                        style: GoogleFonts.exo2(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Connection Status Card
                _StatusCard(device: device, conn: effectiveConn, manifest: activeManifest),
                const SizedBox(height: 24),

                // Capabilities Section
                Text(
                  'Capabilities',
                  style: GoogleFonts.exo2(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  capabilities.isEmpty
                      ? 'No capabilities reported'
                      : '${capabilities.length} discovered',
                  style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),

                if (capabilities.isEmpty)
                  const _EmptyCard(message: 'No capabilities reported. Connect to the device to load capabilities.')
                else
                  ...capabilities.map(
                    (cap) => CapabilityWidgetFactory.buildForCapability(cap, effectiveConn),
                  ),

                const SizedBox(height: 24),

                // Tools Section
                Text(
                  'Callable Tools',
                  style: GoogleFonts.exo2(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  tools.isEmpty
                      ? 'No tools registered'
                      : '${tools.length} tools available — tap to expand',
                  style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),

                if (tools.isEmpty)
                  const _EmptyCard(message: 'No tools registered for this device.')
                else
                  ...tools.map(
                    (tool) => ToolInvokeCard(tool: tool, conn: effectiveConn),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  final DeviceItem device;
  final DeviceConnection? conn;
  final DeviceManifest? manifest;

  const _StatusCard({required this.device, this.conn, this.manifest});

  @override
  Widget build(BuildContext context) {
    final isConnected = conn?.isConnected ?? false;
    final firmware = manifest?.firmwareVersion ?? '—';

    return Container(
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
            child: Icon(Icons.devices, color: AppTheme.primaryOrange, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  'Type: ${device.deviceType}  •  FW: $firmware',
                  style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                ),
                if (device.ipAddress != null)
                  Text(
                    'IP: ${device.ipAddress}',
                    style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isConnected
                  ? Colors.greenAccent.withAlpha(30)
                  : Colors.redAccent.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isConnected
                    ? Colors.greenAccent.withAlpha(120)
                    : Colors.redAccent.withAlpha(120),
              ),
            ),
            child: Text(
              isConnected ? 'Online' : 'Offline',
              style: GoogleFonts.exo2(
                color: isConnected ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Text(message, style: GoogleFonts.exo2(color: AppTheme.textMuted)),
    );
  }
}
