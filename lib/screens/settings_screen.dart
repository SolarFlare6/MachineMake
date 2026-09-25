import 'package:flutter/material.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/machine_make_logo.dart';
import 'discovery_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
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
              'Notifications',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            // Contact us item
            _buildSettingCard(
              title: 'Contact us',
              trailing: const SizedBox.shrink(),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Support email: support@machinemake.io'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Alert when device disconnects item
            _buildSettingCard(
              title: 'Alert when device disconnects',
              trailing: Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _deviceManager.alertOnDisconnect,
                  activeColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withOpacity(0.3),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.darkBorder,
                  onChanged: (val) {
                    _deviceManager.toggleAlertOnDisconnect(val);
                  },
                ),
              ),
            ),

            const SizedBox(height: 28),
            const Text(
              'Control',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            // Auto enable BT on start
            _buildSettingCard(
              title: 'Auto enable BT on start',
              trailing: Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _deviceManager.autoEnableBTOnStart,
                  activeColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withOpacity(0.3),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.darkBorder,
                  onChanged: (val) {
                    _deviceManager.toggleAutoEnableBT(val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Auto enable Wifi on start
            _buildSettingCard(
              title: 'Auto enable Wifi on start',
              trailing: Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _deviceManager.autoEnableWifiOnStart,
                  activeColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withOpacity(0.3),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.darkBorder,
                  onChanged: (val) {
                    _deviceManager.toggleAutoEnableWifi(val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Device manager item
            _buildSettingCard(
              title: 'Device manager',
              trailing: const SizedBox.shrink(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DiscoveryScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.darkBorder,
          width: 1.2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 6,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
