import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/device_manager.dart';
import '../services/device_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/device_icons.dart';
import 'discovery_screen.dart';

/// Screen where users can view paired devices and delete saved credentials.
class DeviceManagerScreen extends StatefulWidget {
  const DeviceManagerScreen({super.key});

  @override
  State<DeviceManagerScreen> createState() => _DeviceManagerScreenState();
}

class _DeviceManagerScreenState extends State<DeviceManagerScreen> {
  final DeviceManager _deviceManager = DeviceManager();
  final DeviceRegistry _registry = DeviceRegistry();

  @override
  void initState() {
    super.initState();
    _deviceManager.addListener(_onStateChange);
    _registry.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _deviceManager.removeListener(_onStateChange);
    _registry.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _confirmDeleteDevice(String deviceId, String deviceName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Credentials',
                style: GoogleFonts.exo2(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete saved pairing credentials for "$deviceName" ($deviceId)?\n\nThis will disconnect the device and remove its authentication keys.',
          style: GoogleFonts.exo2(
            fontSize: 14,
            color: AppTheme.textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.exo2(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deviceManager.removeDevice(deviceId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Credentials for $deviceName deleted.'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllCredentials() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete All Credentials',
                style: GoogleFonts.exo2(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'This will remove saved pairing credentials for ALL devices. You will need to pair again to control them.\n\nContinue?',
          style: GoogleFonts.exo2(
            fontSize: 14,
            color: AppTheme.textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.exo2(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deviceManager.clearAllDevices();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All device credentials removed.'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Clear All',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final knownDevices = _registry.devices;
    final liveDevices = _deviceManager.allPairedDevices;

    // Collect all unique device IDs
    final allIds = <String>{
      ...knownDevices.map((d) => d.deviceId),
      ...liveDevices.map((d) => d.id),
    }.toList();

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          'Device Manager',
          style: GoogleFonts.exo2(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: allIds.isEmpty ? _buildEmptyState() : _buildDeviceList(allIds),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.devices_other,
                size: 40,
                color: AppTheme.primaryOrange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Saved Credentials',
              style: GoogleFonts.exo2(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have no paired devices or saved credentials.\nScan a QR code or search the network to pair.',
              textAlign: TextAlign.center,
              style: GoogleFonts.exo2(
                fontSize: 14,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                'Scan & Pair Device',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: AppTheme.textDarkButton,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(List<String> deviceIds) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Devices (${deviceIds.length})',
              style: GoogleFonts.exo2(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryOrange,
              ),
            ),
            TextButton.icon(
              onPressed: _confirmClearAllCredentials,
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
              label: Text(
                'Clear All',
                style: GoogleFonts.exo2(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...deviceIds.map((id) {
          final known = _registry.findById(id);
          final live = _deviceManager.allPairedDevices
              .where((d) => d.id == id)
              .firstOrNull;

          final name = live?.name ?? known?.name ?? id;
          final profile = live?.profile ?? known?.type ?? 'quadruped';
          final address = live?.ipAddress ?? known?.lastIp ?? 'Direct';
          final port = live?.port ?? known?.lastPort ?? 8765;
          final isConnected = live?.isConnected ?? false;
          final hasPsk = known?.psk != null && known!.psk!.isNotEmpty;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF00E676).withAlpha(100)
                    : AppTheme.darkBorder,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                DeviceProfileIcon(
                  iconKey: profile,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.exo2(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? const Color(0xFF00E676).withAlpha(30)
                                  : Colors.white.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isConnected ? 'Connected' : 'Saved',
                              style: GoogleFonts.exo2(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isConnected
                                    ? const Color(0xFF00E676)
                                    : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: $id',
                        style: GoogleFonts.exo2(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.wifi,
                            size: 13,
                            color: AppTheme.primaryOrange.withAlpha(180),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$address:$port',
                            style: GoogleFonts.exo2(
                              fontSize: 12,
                              color: AppTheme.primaryOrange,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (hasPsk)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withAlpha(25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.key,
                                    size: 10,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'PSK Saved',
                                    style: GoogleFonts.exo2(
                                      fontSize: 10,
                                      color: Colors.amber,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Delete credentials',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _confirmDeleteDevice(id, name),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
