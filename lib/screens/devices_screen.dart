import 'package:flutter/material.dart';
import '../core/connection/connection_state_enum.dart';
import '../core/routing/profile_router.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/device_icons.dart';
import '../widgets/machine_make_logo.dart';
import '../widgets/ssh_dialog.dart';
import '../widgets/voice_cmd_dialog.dart';
import 'discovery_screen.dart';
import 'ssh_terminal_screen.dart';

class DevicesScreen extends StatefulWidget {
  final Function(int tabIndex) onNavigateTab;

  const DevicesScreen({
    super.key,
    required this.onNavigateTab,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final DeviceManager _deviceManager = DeviceManager();

  @override
  void initState() {
    super.initState();
    _deviceManager.addListener(_onManagerChange);
  }

  @override
  void dispose() {
    _deviceManager.removeListener(_onManagerChange);
    super.dispose();
  }

  void _onManagerChange() {
    if (mounted) setState(() {});
  }

  void _openShell() {
    final selectedDev = _deviceManager.selectedDevice;
    final deviceId = selectedDev?.id ??
        (_deviceManager.devices.isNotEmpty
            ? _deviceManager.devices.first.id
            : 'device-01');
    final cfg = _deviceManager.getSSHConfig(deviceId);
    final defaultHost = cfg.hostname.isNotEmpty
        ? cfg.hostname
        : (selectedDev?.ipAddress ?? '');

    showDialog(
      context: context,
      builder: (_) => SSHDialog(
        initialHostname: defaultHost,
        initialUsername: cfg.username.isNotEmpty ? cfg.username : 'pi',
        initialPassword: cfg.password,
        initialPort: cfg.port,
        onConnectDetailed: (hostname, username, password, port) {
          _deviceManager.saveSSHConfig(
            deviceId,
            hostname,
            password,
            username: username,
            port: port,
          );

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SshTerminalScreen(
                host: hostname,
                port: port,
                username: username,
                password: password,
                deviceName: selectedDev?.name,
              ),
            ),
          );
        },
      ),
    );
  }

  void _openVoiceCmd() {
    showDialog(
      context: context,
      builder: (_) => VoiceCmdDialog(
        devices: _deviceManager.devices,
        selectedDeviceId: _deviceManager.selectedDeviceId,
        onCommandExecuted: (deviceId, cmd) {
          _deviceManager.setSelectedDevice(deviceId);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _deviceManager.devices;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const MachineMakeLogo(logoHeight: 28),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Row with '+'
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Devices',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.add,
                    color: AppTheme.primaryOrange,
                    size: 32,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiscoveryScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Devices Grid or Empty State
            Expanded(
              child: devices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppTheme.darkSurface,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.darkBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.link_off,
                                color: AppTheme.textMuted,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No connected devices',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Devices only appear here once an active connection is established. Tap + to scan and connect.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const DiscoveryScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryOrange,
                                foregroundColor: AppTheme.textDarkButton,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.radar, size: 20),
                              label: const Text(
                                'Scan Devices',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      itemCount: devices.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.15,
                      ),
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isSelected = device.id == _deviceManager.selectedDeviceId;
                        final conn = _deviceManager.getConnection(device.id);
                        final connState = conn?.state;
                        final stateColor = _connectionStateColor(connState);
                        final stateLabel = _connectionStateLabel(connState);

                        return GestureDetector(
                          onTap: () {
                            _deviceManager.setSelectedDevice(device.id);
                            ProfileRouter.openDeviceDashboard(
                              context,
                              device,
                              conn: conn,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryOrange
                                    : AppTheme.darkBorder,
                                width: isSelected ? 2.0 : 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top Row: Icon + Connection State Badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    DeviceProfileIcon(
                                      iconKey: device.iconKey,
                                      size: 24,
                                    ),
                                    // Connection state dot
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: stateColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Transform.scale(
                                          scale: 0.85,
                                          child: Switch(
                                            value: device.isConnected,
                                            activeColor: AppTheme.primaryOrange,
                                            activeTrackColor: AppTheme.primaryOrange.withAlpha(76),
                                            inactiveThumbColor: Colors.white,
                                            inactiveTrackColor: AppTheme.darkBorder,
                                            onChanged: (val) {
                                              _deviceManager.toggleDeviceConnection(
                                                device.id,
                                                val,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // Transport badges
                                if (device.availableTransports.isNotEmpty)
                                  Wrap(
                                    spacing: 4,
                                    children: device.availableTransports.map((t) =>
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.darkSurface,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: AppTheme.darkBorder),
                                        ),
                                        child: Text(
                                          t.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: AppTheme.textMuted,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ).toList(),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  stateLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: stateColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  device.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 12),
            const Text(
              'Quick actions',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            // Quick actions side-by-side buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openShell,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryOrange,
                      side: BorderSide(
                        color: AppTheme.primaryOrange,
                        width: 1.8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Open shell',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.terminal,
                          size: 22,
                          color: AppTheme.primaryOrange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openVoiceCmd,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryOrange,
                      side: BorderSide(
                        color: AppTheme.primaryOrange,
                        width: 1.8,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Voice cmd',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.mic_none,
                          size: 22,
                          color: AppTheme.primaryOrange,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Color _connectionStateColor(DeviceConnectionState? state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return Colors.greenAccent;
      case DeviceConnectionState.pairing:
      case DeviceConnectionState.authenticating:
      case DeviceConnectionState.negotiating:
        return Colors.amberAccent;
      case DeviceConnectionState.discovered:
      case DeviceConnectionState.paired:
        return Colors.blueAccent;
      case DeviceConnectionState.error:
        return Colors.redAccent;
      case DeviceConnectionState.disconnecting:
      case DeviceConnectionState.offline:
      case null:
        return AppTheme.textMuted;
      default:
        return AppTheme.textMuted;
    }
  }

  String _connectionStateLabel(DeviceConnectionState? state) {
    switch (state) {
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.pairing:
        return 'Pairing…';
      case DeviceConnectionState.authenticating:
        return 'Authenticating…';
      case DeviceConnectionState.negotiating:
        return 'Negotiating…';
      case DeviceConnectionState.discovered:
        return 'Discovered';
      case DeviceConnectionState.paired:
        return 'Paired';
      case DeviceConnectionState.error:
        return 'Error';
      case DeviceConnectionState.disconnecting:
        return 'Disconnecting…';
      case DeviceConnectionState.offline:
      case null:
        return 'Offline';
      default:
        return 'Unknown';
    }
  }
}
