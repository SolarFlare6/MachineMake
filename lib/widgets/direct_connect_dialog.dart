import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/models/known_device.dart';
import '../models/dcp_models.dart';
import '../services/app_startup_service.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';

/// Modal dialog allowing direct IP & port connection to a DCP device.
class DirectConnectDialog extends StatefulWidget {
  final VoidCallback? onConnected;

  const DirectConnectDialog({
    super.key,
    this.onConnected,
  });

  static Future<void> show(BuildContext context, {VoidCallback? onConnected}) {
    return showDialog(
      context: context,
      builder: (ctx) => DirectConnectDialog(onConnected: onConnected),
    );
  }

  @override
  State<DirectConnectDialog> createState() => _DirectConnectDialogState();
}

class _DirectConnectDialogState extends State<DirectConnectDialog> {
  final TextEditingController _hostCtrl = TextEditingController(text: '10.80.166.248');
  final TextEditingController _portCtrl = TextEditingController(text: '8765');
  String _selectedProfile = 'computer';

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Widget _buildProfileChoice(String id, String label, IconData icon) {
    final isSelected = id == _selectedProfile;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedProfile = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryOrange.withAlpha(30) : AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryOrange : AppTheme.darkBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? AppTheme.primaryOrange : AppTheme.textMuted),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.exo2(
                      color: isSelected ? Colors.white : AppTheme.textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleConnect() {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8765;
    if (host.isEmpty) return;

    final isMcu = _selectedProfile == 'microcontroller';
    final isQuad = _selectedProfile == 'quadruped';
    final devId = 'direct-${host.replaceAll('.', '-')}-$port';
    final devName = isMcu
        ? 'Raspberry Pi Pico W'
        : (isQuad ? 'Quadruped Robot' : 'Workstation PC');
    final devType = isMcu
        ? 'Microcontroller'
        : (isQuad ? 'Quadruped Robot' : 'Computer / PC');
    final icon = isMcu ? 'pico' : (isQuad ? 'quadruped' : 'computer');

    final dev = DeviceItem(
      id: devId,
      name: devName,
      profile: _selectedProfile,
      deviceType: devType,
      availableTransports: const ['wifi'],
      selectedTransport: 'wifi',
      isPaired: true,
      isConnected: true,
      iconKey: icon,
      ipAddress: host,
      port: port,
    );

    final dm = DeviceManager();
    dm.addDevice(dev);
    dm.setSelectedDevice(dev.id);

    // Save to registry so the profile is retained across restarts
    dm.registry.addOrUpdate(KnownDevice(
      deviceId: devId,
      name: devName,
      type: _selectedProfile == 'microcontroller'
          ? 'pico'
          : (_selectedProfile == 'quadruped' ? 'quadruped' : 'computer'),
      lastIp: host,
      lastPort: port,
      isTrusted: true,
    ));

    AppStartupService.setFirstSetupDone(true);
    Navigator.of(context).pop();

    if (widget.onConnected != null) {
      widget.onConnected!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.modalBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
      ),
      title: Row(
        children: [
          Icon(Icons.settings_ethernet, color: AppTheme.primaryOrange, size: 26),
          const SizedBox(width: 10),
          Text(
            'Direct IP Connect',
            style: GoogleFonts.exo2(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect directly to a DCP server via Wi-Fi/LAN (when mDNS is blocked by firewall):',
              style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostCtrl,
              style: GoogleFonts.exo2(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Host / IP Address',
                labelStyle: GoogleFonts.exo2(color: AppTheme.primaryOrange),
                hintText: 'e.g. 10.80.166.248',
                hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.darkSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.exo2(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: GoogleFonts.exo2(color: AppTheme.primaryOrange),
                hintText: '8765',
                hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.darkSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Device Profile:',
              style: GoogleFonts.exo2(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildProfileChoice('microcontroller', 'Pico / MCU', Icons.memory),
                const SizedBox(width: 5),
                _buildProfileChoice('computer', 'PC / SBC', Icons.computer),
                const SizedBox(width: 5),
                _buildProfileChoice('quadruped', 'Robot', Icons.smart_toy),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: GoogleFonts.exo2(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange,
            foregroundColor: AppTheme.textDarkButton,
          ),
          onPressed: _handleConnect,
          child: Text(
            'Connect',
            style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
