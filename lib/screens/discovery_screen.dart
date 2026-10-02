import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/dcp_models.dart';
import '../services/app_startup_service.dart';
import '../services/device_manager.dart';
import '../services/pairing_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/device_icons.dart';
import '../widgets/machine_make_logo.dart';
import 'main_layout.dart';
import 'qr_scanner_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final DeviceManager _deviceManager = DeviceManager();

  @override
  void initState() {
    super.initState();
    _deviceManager.addListener(_onDeviceManagerChange);
    _deviceManager.startScan();
  }

  @override
  void dispose() {
    _deviceManager.removeListener(_onDeviceManagerChange);
    super.dispose();
  }

  void _onDeviceManagerChange() {
    if (mounted) setState(() {});
  }

  void _showDirectConnectDialog() {
    final hostCtrl = TextEditingController(text: '10.80.166.248');
    final portCtrl = TextEditingController(text: '8765');
    String selectedProfile = 'computer';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.modalBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.settings_ethernet, color: AppTheme.primaryOrange, size: 26),
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
                  controller: hostCtrl,
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
                  controller: portCtrl,
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
                    _buildProfileChoice('computer', 'PC / Laptop', Icons.computer, selectedProfile, (p) {
                      setDialogState(() => selectedProfile = p);
                    }),
                    const SizedBox(width: 8),
                    _buildProfileChoice('quadruped', 'Robot', Icons.smart_toy, selectedProfile, (p) {
                      setDialogState(() => selectedProfile = p);
                    }),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.exo2(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: AppTheme.textDarkButton,
              ),
              onPressed: () {
                final host = hostCtrl.text.trim();
                final port = int.tryParse(portCtrl.text.trim()) ?? 8765;
                if (host.isEmpty) return;

                final isQuad = selectedProfile == 'quadruped';
                final isComp = selectedProfile == 'computer';
                final devId = 'direct-${host.replaceAll('.', '-')}-$port';
                final devName = isQuad ? 'Quadruped Robot' : (isComp ? 'Workstation PC' : 'Microcontroller');
                final devType = isQuad ? 'Quadruped Robot' : (isComp ? 'Computer / PC' : 'Microcontroller');
                final icon = isQuad ? 'quadruped' : (isComp ? 'computer' : 'pico');

                final dev = DeviceItem(
                  id: devId,
                  name: devName,
                  profile: selectedProfile,
                  deviceType: devType,
                  availableTransports: const ['wifi'],
                  selectedTransport: 'wifi',
                  isPaired: true,
                  isConnected: true,
                  iconKey: icon,
                  ipAddress: host,
                  port: port,
                );

                _deviceManager.addDevice(dev);
                _deviceManager.setSelectedDevice(dev.id);

                AppStartupService.setFirstSetupDone(true);
                Navigator.of(ctx).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainLayout()),
                );
              },
              child: Text(
                'Connect',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileChoice(String id, String label, IconData icon, String current, Function(String) onSelect) {
    final isSelected = id == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
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
            children: [
              Icon(icon, size: 16, color: isSelected ? AppTheme.primaryOrange : AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.exo2(
                  color: isSelected ? Colors.white : AppTheme.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPairingDialog(DeviceItem device) {
    showDialog(
      context: context,
      builder: (context) {
        String selectedTransport = device.availableTransports.first.toLowerCase();
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                    Text(
                      'Pair with ${device.name}',
                      style: GoogleFonts.exo2(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select communication transport protocol:',
                      style: GoogleFonts.exo2(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...device.availableTransports.map((t) {
                      final tKey = t.toLowerCase();
                      final isSelected = selectedTransport == tKey;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primaryOrange
                                : AppTheme.darkBorder,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: RadioListTile<String>(
                          value: tKey,
                          groupValue: selectedTransport,
                          activeColor: AppTheme.primaryOrange,
                          title: Text(
                            t.toUpperCase(),
                            style: GoogleFonts.exo2(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedTransport = val);
                            }
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        device.selectedTransport = selectedTransport;
                        device.isPaired = true;
                        device.isConnected = true;
                        _deviceManager.addDevice(device);
                        AppStartupService.setFirstSetupDone(true);
                        Navigator.of(context).pop();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const MainLayout(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: AppTheme.textDarkButton,
                      ),
                      child: Text(
                        'Pair & Connect',
                        style: GoogleFonts.exo2(
                          color: AppTheme.textDarkButton,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = _deviceManager.nearbyDevices;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const MachineMakeLogo(logoHeight: 28),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                'Nearby Devices',
                style: GoogleFonts.exo2(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Device List or Empty State
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
                                    color: _deviceManager.isScanning
                                        ? AppTheme.primaryOrange
                                        : AppTheme.darkBorder,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  _deviceManager.isScanning
                                      ? Icons.radar
                                      : Icons.devices_other,
                                  color: _deviceManager.isScanning
                                      ? AppTheme.primaryOrange
                                      : AppTheme.textMuted,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _deviceManager.isScanning
                                    ? 'Scanning for devices...'
                                    : 'No devices found',
                                style: GoogleFonts.exo2(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _deviceManager.isScanning
                                    ? 'Searching your local Wi-Fi and Bluetooth network'
                                    : 'Make sure your device is powered on, advertising, or connected to the same Wi-Fi.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.exo2(
                                  fontSize: 14,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              if (!_deviceManager.isScanning) ...[
                                const SizedBox(height: 18),
                                OutlinedButton.icon(
                                  onPressed: _showDirectConnectDialog,
                                  icon: const Icon(Icons.settings_ethernet, color: AppTheme.primaryOrange, size: 20),
                                  label: Text(
                                    'Direct IP Connect',
                                    style: GoogleFonts.exo2(
                                      color: AppTheme.primaryOrange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final item = devices[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppTheme.darkBorder,
                                width: 1.5,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              leading: DeviceProfileIcon(
                                iconKey: item.iconKey,
                                size: 32,
                              ),
                              title: Text(
                                item.name,
                                style: GoogleFonts.exo2(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 8,
                                  children: item.availableTransports.map((t) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.darkCard,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppTheme.primaryOrange.withAlpha(128),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        t,
                                        style: GoogleFonts.exo2(
                                          color: AppTheme.primaryOrange,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: AppTheme.textMuted,
                                size: 30,
                              ),
                              onTap: () => _showPairingDialog(item),
                            ),
                          );
                        },
                      ),
              ),

              // Bottom Actions
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _deviceManager.startScan();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOrange,
                        foregroundColor: AppTheme.textDarkButton,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _deviceManager.isScanning
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: AppTheme.textDarkButton,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Scan',
                              style: GoogleFonts.exo2(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDarkButton,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.darkBorder,
                        width: 1.5,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: AppTheme.primaryOrange,
                        size: 28,
                      ),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final result = await Navigator.of(context).push<dynamic>(
                          MaterialPageRoute(
                            builder: (_) => const QrScannerScreen(),
                          ),
                        );
                        if (result != null && mounted) {
                          if (result is Map && result['success'] == true) {
                            final deviceId = result['device_id'] as String;
                            final name = (result['name'] as String?) ?? 'Device';
                            final profile = (result['profile'] as String?) ?? 'quadruped';
                            final host = result['host'] as String?;
                            final port = (result['port'] as int?) ?? 8765;

                            final dev = DeviceItem(
                              id: deviceId,
                              name: name,
                              profile: profile,
                              deviceType: profile == 'quadruped'
                                  ? 'Quadruped Robot'
                                  : 'Device',
                              availableTransports: const ['wifi'],
                              selectedTransport: 'wifi',
                              isPaired: true,
                              isConnected: true,
                              iconKey: profile,
                              ipAddress: host,
                              port: port,
                            );

                            _deviceManager.addDevice(dev);
                            _deviceManager.setSelectedDevice(dev.id);
                            AppStartupService.setFirstSetupDone(true);

                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Successfully paired & connected to $name!'),
                                backgroundColor: const Color(0xFF00E676),
                              ),
                            );

                            if (!mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const MainLayout(),
                              ),
                            );
                          } else if (result is PairingRequest) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Pairing initiated with ${result.deviceName}'),
                                backgroundColor: AppTheme.primaryOrange,
                              ),
                            );
                            _deviceManager.startScan();
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () {
                    AppStartupService.setFirstSetupDone(true);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const MainLayout(),
                      ),
                    );
                  },
                  child: Text(
                    'skip scan',
                    style: GoogleFonts.exo2(
                      color: AppTheme.primaryOrange,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: AppTheme.primaryOrange,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
