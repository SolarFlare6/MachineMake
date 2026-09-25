import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/dcp_models.dart';
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
                        if (!_deviceManager.devices.any((d) => d.id == device.id)) {
                          _deviceManager.devices.add(device);
                        }
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
    final devices = _deviceManager.nearbyDevices.isEmpty
        ? [
            DeviceItem(
              id: 'quad-001',
              name: 'Quadruped Bot',
              profile: 'quadruped',
              deviceType: 'Robot',
              availableTransports: ['WiFi', 'Bluetooth'],
              iconKey: 'quadruped',
            ),
            DeviceItem(
              id: 'rpi-001',
              name: 'Raspberry Pi',
              profile: 'raspberry_pi',
              deviceType: 'Raspberry Pi',
              availableTransports: ['WiFi', 'Bluetooth'],
              iconKey: 'rpi',
            ),
            DeviceItem(
              id: 'pico-001',
              name: 'Pi Pico',
              profile: 'pico',
              deviceType: 'Microcontroller',
              availableTransports: ['WiFi'],
              iconKey: 'pico',
            ),
          ]
        : _deviceManager.nearbyDevices;

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

              // Device List
              Expanded(
                child: ListView.builder(
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
                        final result = await Navigator.of(context).push<PairingRequest>(
                          MaterialPageRoute(
                            builder: (_) => const QrScannerScreen(),
                          ),
                        );
                        if (result != null && mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Pairing initiated with ${result.deviceName}'),
                              backgroundColor: AppTheme.primaryOrange,
                            ),
                          );
                          // Trigger scan refresh
                          _deviceManager.startScan();
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
