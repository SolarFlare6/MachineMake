import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_startup_service.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/machine_make_logo.dart';
import 'discovery_screen.dart';
import 'welcome_screen.dart';

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

  Future<void> _launchGitHubRepo() async {
    final uri = Uri.parse('https://github.com/SolarFlare6/MachineMake');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        final fallback = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );
        if (!fallback && mounted) {
          _showLaunchError();
        }
      }
    } catch (_) {
      try {
        final fallback = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );
        if (!fallback && mounted) {
          _showLaunchError();
        }
      } catch (_) {
        if (mounted) {
          _showLaunchError();
        }
      }
    }
  }

  void _showLaunchError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open https://github.com/SolarFlare6/MachineMake in browser'),
        backgroundColor: AppTheme.primaryOrange,
      ),
    );
  }

  void _showClearDataConfirmationDialog() {
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
                'Clear App Data',
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
          'This will remove all paired devices, saved credentials, and settings. The app will reset back to the initial start screen.\n\nAre you sure you want to proceed?',
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
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AppStartupService.clearAllData();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('App data cleared. Reset to initial setup.'),
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
              'Clear & Reset',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const MachineMakeLogo(logoHeight: 28),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: 100, // Space for floating bottom navigation bar
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notifications Section
            Text(
              'Notifications',
              style: GoogleFonts.exo2(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            _buildSettingCard(
              title: 'Grant notification permission',
              trailing: const SizedBox.shrink(),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Notification permission granted'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            _buildSettingCard(
              title: 'Alert when device disconnects',
              trailing: Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _deviceManager.alertOnDisconnect,
                  activeColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withAlpha(80),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.darkBorder,
                  onChanged: (val) {
                    _deviceManager.toggleAlertOnDisconnect(val);
                  },
                ),
              ),
            ),

            // Control Section
            const SizedBox(height: 28),
            Text(
              'Control',
              style: GoogleFonts.exo2(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            _buildSettingCard(
              title: 'Auto enable BT on start',
              subtitle: 'Automatically turns on Bluetooth when the app launches',
              trailing: Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _deviceManager.autoEnableBTOnStart,
                  activeColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withAlpha(80),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.darkBorder,
                  onChanged: (val) {
                    _deviceManager.toggleAutoEnableBT(val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            _buildSettingCard(
              title: 'Auto enable Wifi on start',
              subtitle: 'Opens Wi-Fi settings on launch so you can enable it quickly',
              trailing: Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _deviceManager.autoEnableWifiOnStart,
                  activeColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withAlpha(80),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppTheme.darkBorder,
                  onChanged: (val) {
                    _deviceManager.toggleAutoEnableWifi(val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

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
            const SizedBox(height: 12),

            _buildSettingCard(
              title: 'Clear app data',
              subtitle: 'Resets all settings, paired devices, and returns to initial setup',
              trailing: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
                size: 22,
              ),
              onTap: _showClearDataConfirmationDialog,
            ),

            // Backup Section
            const SizedBox(height: 28),
            Text(
              'Backup',
              style: GoogleFonts.exo2(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            _buildSettingCard(
              title: 'Create backup of the data',
              trailing: const SizedBox.shrink(),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Backup created successfully'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            _buildSettingCard(
              title: 'Restore backup',
              trailing: const SizedBox.shrink(),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Backup restored'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              },
            ),

            // About Section
            const SizedBox(height: 28),
            Text(
              'About',
              style: GoogleFonts.exo2(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),

            // About Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.darkBorder,
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MachineMakeLogo(logoHeight: 26, fontSize: 20),
                  const SizedBox(height: 8),
                  Text(
                    'Version 1.0.0+1',
                    style: GoogleFonts.exo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Universal Device-Control Framework to discover, pair with, and control Raspberry Pi, Pico, ESP32, Robotics platforms & custom hardware.',
                    style: GoogleFonts.exo2(
                      fontSize: 14,
                      color: AppTheme.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // GitHub Repository Tile
            Container(
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
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.code,
                    color: AppTheme.primaryOrange,
                    size: 24,
                  ),
                ),
                title: Text(
                  'GitHub Repository',
                  style: GoogleFonts.exo2(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  'https://github.com/SolarFlare6/MachineMake',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.exo2(
                    fontSize: 12,
                    color: AppTheme.primaryOrange,
                  ),
                ),
                trailing: const Icon(
                  Icons.open_in_new,
                  color: AppTheme.textMuted,
                  size: 22,
                ),
                onTap: _launchGitHubRepo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    String? subtitle,
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
          style: GoogleFonts.exo2(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subtitle,
                  style: GoogleFonts.exo2(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                    height: 1.3,
                  ),
                ),
              )
            : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
