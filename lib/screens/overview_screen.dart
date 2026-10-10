import 'package:flutter/material.dart';
import '../core/models/device_capability.dart';
import '../core/models/device_profile.dart';
import '../core/routing/profile_router.dart';
import '../models/dcp_models.dart';
import '../services/capability_manager.dart';
import '../services/device_manager.dart';
import '../services/task_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/device_icons.dart';
import '../widgets/event_log_widget.dart';
import '../widgets/machine_make_logo.dart';
import '../widgets/telemetry_gauge.dart';
import 'camera_feed_screen.dart';
import 'hardware_control_screen.dart';
import 'task_list_screen.dart';

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
  final Set<String> _expandedDeviceIds = {};

  @override
  void initState() {
    super.initState();
    _deviceManager.addListener(_onManagerChange);
    AppTheme.accentColorNotifier.addListener(_onManagerChange);
  }

  @override
  void dispose() {
    AppTheme.accentColorNotifier.removeListener(_onManagerChange);
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
              child: connectedDevices.isEmpty
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
                                Icons.sensors_off,
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
                              'Telemetry and status metrics will appear here once a device connects.',
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
                  : ListView.builder(
                      itemCount: connectedDevices.length,
                      itemBuilder: (context, index) {
                        final device = connectedDevices[index];
                        final isExpanded = _expandedDeviceIds.contains(device.id);
                        final telemetry = _deviceManager.getTelemetry(device.id);
                        final profile = DeviceProfile.fromString(device.profile);
                        final conn = _deviceManager.getConnection(device.id);
                        final hasCamera = _deviceHasCamera(device);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppTheme.darkSurface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isExpanded
                                  ? AppTheme.darkBorder
                                  : AppTheme.darkBorder.withValues(alpha: 0.6),
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
                                              displayValue: telemetry.gpuUsage != null
                                                  ? '${telemetry.gpuUsage!.toInt()}%'
                                                  : 'N/A',
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
                                      if (hasCamera) ...[
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
                                      ],

                                      if (profile.isGenericOrMcu) ...[
                                        _buildQuickOpButton(
                                          'Open device',
                                          () {
                                            _deviceManager.setSelectedDevice(device.id);
                                            ProfileRouter.openDeviceDashboard(
                                              context,
                                              device,
                                              conn: conn,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        _buildQuickOpButton(
                                          'Hardware control',
                                          () {
                                            _deviceManager.setSelectedDevice(device.id);
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => HardwareControlScreen(
                                                  deviceName: device.name,
                                                  deviceId: device.id,
                                                  conn: conn,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                      ] else if (profile.isComputer) ...[
                                         // PCs / Laptops / macOS open specialized computer dashboard
                                        _buildQuickOpButton(
                                          'Open device',
                                          () {
                                            _deviceManager.setSelectedDevice(device.id);
                                            ProfileRouter.openDeviceDashboard(
                                              context,
                                              device,
                                              conn: conn,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                      ] else ...[
                                        // Robots have both hardware control and robot dashboard
                                        _buildQuickOpButton(
                                          'Hardware control',
                                          () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => HardwareControlScreen(
                                                  deviceName: device.name,
                                                  deviceId: device.id,
                                                  conn: conn,
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
                                            ProfileRouter.openDeviceDashboard(
                                              context,
                                              device,
                                              conn: conn,
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                      ],

                                      // Active Tasks
                                      ListenableBuilder(
                                        listenable: TaskManager(),
                                        builder: (context, _) {
                                          final count = TaskManager().activeTasks(device.id).length;
                                          return _buildQuickOpButton(
                                            count > 0 ? 'Active Tasks ($count)' : 'Task History',
                                            () {
                                              Navigator.of(context).push(
                                                MaterialPageRoute(builder: (_) => const TaskListScreen()),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      const Text(
                                        'Recent Events',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      EventLogWidget(deviceId: device.id, maxEntries: 10),
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
        side: BorderSide(
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

  bool _deviceHasCamera(DeviceItem device) {
    final conn = _deviceManager.getConnection(device.id);
    final caps = [
      ...CapabilityManager().getCapabilities(device.id),
      ...?conn?.manifest?.capabilities,
    ];

    // 1. Check system_hardware scan results (for PCs, Macs, and host machines)
    for (final c in caps) {
      if (c.id == 'system_hardware' ||
          (c.type == CapabilityType.custom && c.id.contains('hardware'))) {
        final count = (c.params['cameras_count'] as num?)?.toInt();
        final camerasList = c.params['cameras'] as List?;
        final available = c.params['camera_available'] as bool?;

        if (count != null && count > 0) return true;
        if (camerasList != null && camerasList.isNotEmpty) return true;
        if (available == true) return true;
        if (count != null && count == 0) return false;
      }
    }

    // 2. Check dedicated camera capability detected by the hardware scan
    final hasDedicatedCamera = caps.any((c) {
      if (c.type == CapabilityType.camera ||
          c.id.toLowerCase() == 'camera' ||
          c.id.toLowerCase() == 'cameras') {
        if (c.params.containsKey('available') && c.params['available'] == false) {
          return false;
        }
        if (c.params.containsKey('cameras_count') &&
            (c.params['cameras_count'] as num?)?.toInt() == 0) {
          return false;
        }
        return c.enabled;
      }
      return false;
    });

    if (hasDedicatedCamera) {
      return true;
    }

    return false;
  }
}
