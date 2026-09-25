import 'package:flutter/material.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/device_icons.dart';
import '../widgets/machine_make_logo.dart';
import '../widgets/telemetry_gauge.dart';
import 'camera_feed_screen.dart';
import 'hardware_control_screen.dart';

class OverviewScreen extends StatefulWidget {
  final Function(int tabIndex) onNavigateTab;

  const OverviewScreen({
    super.key,
    required this.onNavigateTab,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final DeviceManager _deviceManager = DeviceManager();
  final Set<String> _expandedDeviceIds = {'quad-001'};

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

  void _toggleExpanded(String deviceId) {
    setState(() {
      if (_expandedDeviceIds.contains(deviceId)) {
        _expandedDeviceIds.remove(deviceId);
      } else {
        _expandedDeviceIds.add(deviceId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectedDevices = _deviceManager.devices;

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
              'Connected Devices',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: connectedDevices.length,
                itemBuilder: (context, index) {
                  final device = connectedDevices[index];
                  final isExpanded = _expandedDeviceIds.contains(device.id);
                  final telemetry = _deviceManager.getTelemetry(device.id);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isExpanded
                            ? AppTheme.darkBorder
                            : AppTheme.darkBorder.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card Header Row
                        InkWell(
                          onTap: () => _toggleExpanded(device.id),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                DeviceProfileIcon(
                                  iconKey: device.iconKey,
                                  size: 28,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    device.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: AppTheme.textMuted,
                                  size: 30,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Card Expanded Section
                        if (isExpanded) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Overview',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Telemetry Gauges Container
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.darkCard,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppTheme.darkBorder,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      TelemetryGauge(
                                        value: telemetry.cpuUsage,
                                        label: 'CPU',
                                        displayValue:
                                            '${telemetry.cpuUsage.toInt()}%',
                                        color: AppTheme.cpuOrange,
                                      ),
                                      TelemetryGauge(
                                        value: telemetry.ramUsage,
                                        label: 'RAM',
                                        displayValue:
                                            '${telemetry.ramUsage.toInt()}%',
                                        color: AppTheme.ramPink,
                                      ),
                                      TelemetryGauge(
                                        value: telemetry.gpuUsage,
                                        label: 'GPU',
                                        displayValue:
                                            '${telemetry.gpuUsage.toInt()}%',
                                        color: AppTheme.gpuCyan,
                                      ),
                                      TelemetryGauge(
                                        value: telemetry.temperature,
                                        label: 'TMP',
                                        displayValue:
                                            '${telemetry.temperature.toInt()}°C',
                                        color: AppTheme.tempBlue,
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 18),
                                const Text(
                                  'Quick operations',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Operation Buttons
                                _buildQuickOpButton(
                                  'Camera feed',
                                  () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => CameraFeedScreen(
                                          deviceName: device.name,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                _buildQuickOpButton(
                                  'Hardware control',
                                  () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => HardwareControlScreen(
                                          deviceName: device.name,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                _buildQuickOpButton(
                                  'Open device',
                                  () {
                                    _deviceManager.setSelectedDevice(device.id);
                                    widget.onNavigateTab(2); // Go to Operations tab
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickOpButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryOrange,
        side: const BorderSide(
          color: AppTheme.primaryOrange,
          width: 1.8,
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
