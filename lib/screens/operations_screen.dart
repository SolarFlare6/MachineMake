import 'package:flutter/material.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/machine_make_logo.dart';
import '../widgets/ssh_dialog.dart';
import '../widgets/voice_cmd_dialog.dart';
import 'controls_screen.dart';
import 'hardware_control_screen.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
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

  void _openPowerOptionsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: AppTheme.modalBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Power Options',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                _buildPowerOptionTile(
                  icon: Icons.restart_alt,
                  title: 'Reboot Device',
                  color: AppTheme.primaryOrange,
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Reboot command sent to device'),
                        backgroundColor: AppTheme.primaryOrange,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildPowerOptionTile(
                  icon: Icons.power_settings_new,
                  title: 'Shutdown Device',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Shutdown command sent to device'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _buildPowerOptionTile(
                  icon: Icons.bedtime,
                  title: 'Sleep / Low Power',
                  color: Colors.blueAccent,
                  onTap: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Low power mode enabled'),
                        backgroundColor: Colors.blueAccent,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPowerOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _deviceManager.devices;
    final selectedId = _deviceManager.selectedDeviceId;

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
            const Text(
              'Device',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryOrange,
              ),
            ),
            const SizedBox(height: 8),

            // Device Selector Dropdown or Empty Placeholder
            devices.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.darkBorder,
                        width: 1.5,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.device_unknown, color: AppTheme.textMuted, size: 22),
                        SizedBox(width: 12),
                        Text(
                          'No device connected',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primaryOrange,
                        width: 2,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: devices.any((d) => d.id == selectedId)
                            ? selectedId
                            : devices.first.id,
                        isExpanded: true,
                        dropdownColor: AppTheme.darkCard,
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: AppTheme.primaryOrange,
                          size: 32,
                        ),
                        items: devices.map((device) {
                          return DropdownMenuItem<String>(
                            value: device.id,
                            child: Text(
                              device.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            _deviceManager.setSelectedDevice(val);
                          }
                        },
                      ),
                    ),
                  ),

            const SizedBox(height: 24),
            const Text(
              'Available operations',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            // Available Operations List
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
                                Icons.settings_remote,
                                color: AppTheme.textMuted,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No active device',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Connect a device from the Devices tab to access controls and operations.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                children: [
                  _buildOpCard(
                    icon: Icons.gamepad,
                    title: 'Controls',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ControlsScreen(
                            deviceName:
                                _deviceManager.selectedDevice?.name ?? 'Robot',
                          ),
                        ),
                      );
                    },
                  ),
                  _buildOpCard(
                    icon: Icons.article_outlined,
                    title: 'Log/Voice',
                    onTap: () {
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
                    },
                  ),
                  _buildOpCard(
                    icon: Icons.terminal,
                    title: 'SSH session',
                    onTap: () {
                      final selectedDev = _deviceManager.selectedDevice;
                      final cfg = _deviceManager.getSSHConfig(
                          selectedDev?.id ?? 'quad-001');

                      showDialog(
                        context: context,
                        builder: (_) => SSHDialog(
                          initialHostname: cfg.hostname,
                          initialPassword: cfg.password,
                          onConnect: (hostname, password) {
                            _deviceManager.saveSSHConfig(
                              selectedDev?.id ?? 'quad-001',
                              hostname,
                              password,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('SSH Terminal connected to $hostname'),
                                backgroundColor: AppTheme.primaryOrange,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  _buildOpCard(
                    icon: Icons.build_outlined,
                    title: 'Hardware control',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HardwareControlScreen(
                            deviceName:
                                _deviceManager.selectedDevice?.name ?? 'Device',
                          ),
                        ),
                      );
                    },
                  ),
                  _buildOpCard(
                    icon: Icons.power_settings_new,
                    title: 'Power options',
                    onTap: () => _openPowerOptionsModal(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.darkBorder,
          width: 1.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0x26F37032),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: AppTheme.primaryOrange,
            size: 26,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppTheme.textMuted,
          size: 28,
        ),
        onTap: onTap,
      ),
    );
  }
}
