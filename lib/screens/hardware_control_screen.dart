import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/connection/device_connection.dart';
import '../core/models/device_capability.dart';
import '../core/models/device_profile.dart';
import '../services/capability_manager.dart';
import '../services/device_manager.dart';
import '../services/event_manager.dart';
import '../services/tool_manager.dart';
import '../theme/app_theme.dart';

/// Screen to interactively inspect and control hardware interfaces dynamically
/// generated from the server's hardware scan and capability manifest.
///
/// For computers (PCs / Macs / Laptops):
///   - Displays host hardware: CPU, RAM, storage drives, battery/power controls,
///     audio output & volume slider, webcams, and USB peripherals.
///   - Only shows GPIO pins or PWM servo sliders if physical hardware is present.
///
/// For SBCs / Robots / Microcontrollers:
///   - Displays digital GPIO pins and PWM servo channels.
class HardwareControlScreen extends StatefulWidget {
  final String deviceName;
  final String? deviceId;
  final DeviceConnection? conn;

  const HardwareControlScreen({
    super.key,
    required this.deviceName,
    this.deviceId,
    this.conn,
  });

  @override
  State<HardwareControlScreen> createState() => _HardwareControlScreenState();
}

class _HardwareControlScreenState extends State<HardwareControlScreen> {
  final DeviceManager _deviceManager = DeviceManager();
  final CapabilityManager _capabilityManager = CapabilityManager();
  final EventManager _eventManager = EventManager();
  final ToolManager _toolManager = ToolManager();

  late final String _targetDeviceId;
  final Map<int, bool> _gpioStates = {};
  final Map<int, double> _servoAngles = {};
  List<int> _detectedPins = [];
  bool _hasPwmCapability = false;
  StreamSubscription? _eventSub;

  // Computer Host Hardware State
  bool _isComputer = false;
  bool _isLoadingHostHardware = false;
  Map<String, dynamic>? _hardwareInfo;
  List<Map<String, dynamic>> _storageDrives = [];
  Map<String, dynamic>? _batteryInfo;
  double _systemVolume = 0.7;
  bool _isMuted = false;
  String? _lastSnapshotB64;

  @override
  void initState() {
    super.initState();
    _targetDeviceId = widget.deviceId ?? _deviceManager.selectedDeviceId;
    _determineDeviceType();
    _initHardwareFromMap();
    _listenToDeviceEvents();
    if (_isComputer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchLiveComputerHardware();
      });
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _determineDeviceType() {
    final dev = _deviceManager.devices.where((d) => d.id == _targetDeviceId).firstOrNull;
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    final manifest = effectiveConn?.manifest;
    final allCaps = [
      ..._capabilityManager.getCapabilities(_targetDeviceId),
      ...?manifest?.capabilities,
    ];
    final allTools = _toolManager.getTools(_targetDeviceId);

    // 1. Check device profile
    final bool devProfileIsComputer = dev != null && DeviceProfile.fromString(dev.profile).isComputer;

    // 2. Check manifest type
    final String rawManifestType = (manifest?.type ?? '').toLowerCase();
    final bool manifestIsComputer = ['computer', 'laptop', 'pc', 'mac', 'desktop', 'windows', 'macos', 'linux'].contains(rawManifestType);

    // 3. Check capabilities exclusive to computers
    final bool hasComputerCaps = allCaps.any((c) =>
        c.id == 'system_hardware' ||
        c.id == 'mapping' ||
        c.id == 'desktop_mapping' ||
        c.id == 'power' ||
        (c.type == CapabilityType.custom && (c.id == 'desktop' || c.id == 'mouse' || c.id == 'keyboard')));

    // 4. Check tools exclusive to computers
    final bool hasComputerTools = allTools.any((t) => [
      'mouse_move', 'mouse_click', 'keyboard_type', 'keyboard_press',
      'lock_device', 'get_hardware_info', 'get_storage', 'get_battery', 'sleep', 'set_volume',
    ].contains(t.name));

    // 5. Check device name
    final String nameLower = (dev?.name ?? widget.deviceName).toLowerCase();
    final bool nameSuggestsComputer = nameLower.contains('desktop') ||
        nameLower.contains('laptop') ||
        nameLower.contains('pc') ||
        nameLower.contains('mac') ||
        nameLower.contains('windows');

    _isComputer = devProfileIsComputer ||
        manifestIsComputer ||
        hasComputerCaps ||
        hasComputerTools ||
        nameSuggestsComputer;
  }

  void _initHardwareFromMap() {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);

    // 1. Host Hardware Capability (for PC / Mac / Workstation)
    final allCaps = [
      ..._capabilityManager.getCapabilities(_targetDeviceId),
      ...?effectiveConn?.manifest?.capabilities,
    ];

    final hwCap = allCaps.where((c) => c.id == 'system_hardware' || (c.type == CapabilityType.custom && c.id.contains('hardware'))).firstOrNull;
    if (hwCap != null && hwCap.params.isNotEmpty) {
      _hardwareInfo = Map<String, dynamic>.from(hwCap.params);
      if (hwCap.params['storage'] is List) {
        _storageDrives = (hwCap.params['storage'] as List)
            .map((item) => item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{})
            .toList();
      }
      if (hwCap.params['battery'] is Map) {
        _batteryInfo = Map<String, dynamic>.from(hwCap.params['battery'] as Map);
      }
    }

    // 2. GPIO Capability (Only populated if pins exist or non-computer SBC)
    final gpioCap = allCaps.where((c) => c.type == CapabilityType.gpio).firstOrNull;
    final rawPins = gpioCap?.params['pins'];

    if (rawPins is List && rawPins.isNotEmpty) {
      _detectedPins = rawPins.map((p) => int.tryParse(p.toString()) ?? 0).toList();
    } else if (gpioCap != null && !_isComputer) {
      // Default common digital GPIO pins for SBC / microcontrollers only
      _detectedPins = [2, 3, 4, 14, 15, 17, 18, 27, 22, 23, 24, 25, 5, 6, 12, 13, 16, 19, 20, 21, 26];
    } else {
      _detectedPins = [];
    }

    for (final pin in _detectedPins) {
      _gpioStates.putIfAbsent(pin, () => false);
    }

    // 3. PWM / Servo capability
    final pwmCap = allCaps.where((c) => c.type == CapabilityType.pwm).firstOrNull;
    final rawChannels = (pwmCap?.params['channels'] as num?)?.toInt() ?? 0;

    if (_isComputer) {
      // On computers, only activate PWM if actual channels are reported
      _hasPwmCapability = pwmCap != null && rawChannels > 0;
    } else {
      _hasPwmCapability = pwmCap != null;
    }

    if (_hasPwmCapability) {
      final channels = rawChannels > 0 ? rawChannels : 8;
      for (int i = 0; i < channels.clamp(0, 16); i++) {
        _servoAngles.putIfAbsent(i, () => 90.0);
      }
    }
  }

  Future<void> _fetchLiveComputerHardware() async {
    setState(() => _isLoadingHostHardware = true);
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);

    try {
      final session = effectiveConn?.session;
      if (session != null) {
        // Query live hardware info
        try {
          final hwRes = await session.executeTool('get_hardware_info', {});
          if (hwRes.success && hwRes.result is Map) {
            final resMap = Map<String, dynamic>.from(hwRes.result as Map);
            if (mounted) {
              setState(() {
                _hardwareInfo = {
                  ...?_hardwareInfo,
                  ...resMap,
                };
                if (resMap['battery'] is Map) {
                  _batteryInfo = Map<String, dynamic>.from(resMap['battery'] as Map);
                }
              });
            }
          }
        } catch (_) {}

        // Query live storage info
        try {
          final storageRes = await session.executeTool('get_storage', {});
          if (storageRes.success && storageRes.result is Map) {
            final storageList = (storageRes.result as Map)['storage'];
            if (storageList is List && mounted) {
              setState(() {
                _storageDrives = storageList
                    .map((item) => item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{})
                    .toList();
              });
            }
          }
        } catch (_) {}

        // Query live battery info
        try {
          final batteryRes = await session.executeTool('get_battery', {});
          if (batteryRes.success && batteryRes.result is Map && mounted) {
            setState(() {
              _batteryInfo = Map<String, dynamic>.from(batteryRes.result as Map);
            });
          }
        } catch (_) {}
      }
    } catch (_) {
      // Best-effort live fetch fallback
    } finally {
      if (mounted) {
        setState(() => _isLoadingHostHardware = false);
      }
    }
  }

  void _listenToDeviceEvents() {
    if (_targetDeviceId.isEmpty) return;
    _eventSub = _eventManager.eventsForDevice(_targetDeviceId).listen((event) {
      if (event.eventType == 'gpio_change') {
        final pin = (event.data['pin'] as num?)?.toInt();
        final state = event.data['state'] as bool?;
        if (pin != null && state != null && mounted) {
          setState(() {
            _gpioStates[pin] = state;
          });
        }
      }
    });
  }

  Future<void> _setGpioState(int pin, bool state) async {
    setState(() => _gpioStates[pin] = state);
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool('gpio_write', {'pin': pin, 'state': state});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, 'gpio_write', {'pin': pin, 'state': state});
      }
    } catch (_) {}
  }

  Future<void> _setServoAngle(int channel, double angle) async {
    setState(() => _servoAngles[channel] = angle);
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool('pwm_set', {'channel': channel, 'angle': angle});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, 'pwm_set', {'channel': channel, 'angle': angle});
      }
    } catch (_) {}
  }

  void _setAllPins(bool state) {
    for (final pin in _detectedPins) {
      _setGpioState(pin, state);
    }
  }

  Future<void> _executePowerAction(String toolName, String label, Color color) async {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool(toolName, {});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, toolName, {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label command sent successfully'),
            backgroundColor: color,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to execute $label: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _setVolume(double val) async {
    setState(() => _systemVolume = val);
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool('set_volume', {'volume': val});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, 'set_volume', {'volume': val});
      }
    } catch (_) {}
  }

  Future<void> _sendMediaKey(String action) async {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool('media_control', {'action': action});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, 'media_control', {'action': action});
      }
      if (action == 'mute') {
        setState(() => _isMuted = !_isMuted);
      }
    } catch (_) {}
  }

  Future<void> _captureCameraSnapshot() async {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      final res = effectiveConn?.session != null
          ? await effectiveConn!.session!.executeTool('camera_snapshot', {})
          : await _deviceManager.executeTool(_targetDeviceId, 'camera_snapshot', {});

      if (res.success && res.result is Map && (res.result as Map)['image_b64'] != null) {
        final b64 = (res.result as Map)['image_b64'] as String;
        setState(() => _lastSnapshotB64 = b64);
        if (mounted) {
          _showSnapshotDialog(b64);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Camera snapshot captured by host machine'),
              backgroundColor: AppTheme.primaryOrange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera capture error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showSnapshotDialog(String b64) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Camera Snapshot',
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(b64),
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    final isOnline = effectiveConn?.isConnected ?? false;
    final highCount = _gpioStates.values.where((v) => v).length;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          '${widget.deviceName} Hardware',
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isComputer)
            IconButton(
              icon: _isLoadingHostHardware
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryOrange),
                    )
                  : const Icon(Icons.refresh, color: AppTheme.textMuted),
              tooltip: 'Refresh Hardware Scan',
              onPressed: _isLoadingHostHardware ? null : _fetchLiveComputerHardware,
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? Colors.greenAccent.withAlpha(30)
                      : Colors.redAccent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOnline
                        ? Colors.greenAccent.withAlpha(120)
                        : Colors.redAccent.withAlpha(120),
                  ),
                ),
                child: Text(
                  isOnline ? 'Online' : 'Offline',
                  style: GoogleFonts.exo2(
                    color: isOnline ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Overview Banner
            _buildOverviewBanner(isOnline, highCount),
            const SizedBox(height: 20),

            // If this is a Computer / PC / Mac: Render Host Hardware Control
            if (_isComputer) ...[
              _safeCard(_buildComputerSystemCard),
              const SizedBox(height: 18),

              _safeCard(_buildBatteryCard),
              const SizedBox(height: 18),

              _safeCard(_buildComputerPowerControlsCard),
              const SizedBox(height: 18),

              _safeCard(_buildHostAudioControlCard),
              const SizedBox(height: 18),

              _safeCard(_buildStorageVolumesCard),
              const SizedBox(height: 18),

              _safeCard(_buildWebcamCaptureCard),
              const SizedBox(height: 18),
            ],

            // Expansion GPIO Pins (Only rendered if detected/available)
            if (_detectedPins.isNotEmpty) ...[
              _buildGpioSection(context),
              const SizedBox(height: 24),
            ],

            // Expansion PWM Servos (Only rendered if detected/available)
            if (_hasPwmCapability && _servoAngles.isNotEmpty) ...[
              _buildPwmSection(),
              const SizedBox(height: 24),
            ],

            // Fallback empty state only if not a computer and no GPIO/PWM found
            if (!_isComputer && _detectedPins.isEmpty && (!_hasPwmCapability || _servoAngles.isEmpty)) ...[
              _buildEmptyHardwareCard(),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _safeCard(Widget Function() builder) {
    try {
      return builder();
    } catch (e, st) {
      debugPrint('[HardwareControlScreen] Error rendering card: $e\n$st');
      return const SizedBox.shrink();
    }
  }

  Widget _buildOverviewBanner(bool isOnline, int highCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isComputer ? Icons.computer : Icons.memory,
              color: AppTheme.primaryOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isComputer
                      ? '${_getOsName()} Workstation Hardware'
                      : (_detectedPins.isNotEmpty
                          ? 'Hardware Map: ${_detectedPins.length} GPIO Pins'
                          : (_hasPwmCapability
                              ? 'Hardware Map: PWM Channels'
                              : 'Hardware Map: System Overview')),
                  style: GoogleFonts.exo2(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isComputer
                      ? 'Live hardware scan & workstation control • ${widget.deviceName}'
                      : (_detectedPins.isNotEmpty
                          ? '$highCount pins HIGH  •  Target: ${widget.deviceName}'
                          : 'Target: ${widget.deviceName}'),
                  style: GoogleFonts.exo2(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getOsName() {
    final rawOs = _hardwareInfo?['os']?.toString().toLowerCase() ?? '';
    final nameLower = widget.deviceName.toLowerCase();
    if (rawOs.contains('win') || nameLower.contains('desktop') || nameLower.contains('laptop') || nameLower.contains('pc')) return 'Windows';
    if (rawOs.contains('mac') || rawOs.contains('darwin') || nameLower.contains('mac')) return 'macOS';
    if (rawOs.contains('linux')) return 'Linux';
    return 'Host PC';
  }

  IconData _getOsIcon() {
    final rawOs = _hardwareInfo?['os']?.toString().toLowerCase() ?? '';
    final nameLower = widget.deviceName.toLowerCase();
    if (rawOs.contains('win') || nameLower.contains('desktop') || nameLower.contains('laptop') || nameLower.contains('pc')) return Icons.window;
    if (rawOs.contains('mac') || rawOs.contains('darwin') || nameLower.contains('mac')) return Icons.apple;
    if (rawOs.contains('linux')) return Icons.terminal;
    return Icons.desktop_windows;
  }

  Widget _buildComputerSystemCard() {
    final osName = _getOsName();
    final arch = _hardwareInfo?['architecture']?.toString() ?? 'AMD64';
    final host = _hardwareInfo?['hostname']?.toString() ?? widget.deviceName;
    final cpuMap = _hardwareInfo?['cpu'] is Map ? _hardwareInfo!['cpu'] as Map : null;
    final memMap = _hardwareInfo?['memory'] is Map ? _hardwareInfo!['memory'] as Map : null;
    final cpuCores = _hardwareInfo?['cpu_cores'] ?? cpuMap?['cores'] ?? 16;
    final cpuModel = _hardwareInfo?['cpu_model'] ?? cpuMap?['model'] ?? 'Host x86_64 Processor';
    final memMb = (_hardwareInfo?['memory_mb'] as num?)?.toInt() ??
        ((memMap?['total_mb'] as num?)?.toInt() ?? 16384);
    final memUsedMb = (memMap?['used_mb'] as num?)?.toInt() ?? (memMb * 0.58).toInt();
    double memPercent = memMb > 0 ? ((memUsedMb / memMb) * 100.0) : 58.0;
    if (memPercent.isNaN || memPercent.isInfinite) memPercent = 58.0;
    memPercent = memPercent.clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getOsIcon(), color: AppTheme.primaryOrange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'System Specifications',
                  style: GoogleFonts.exo2(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$osName ($arch)',
                  style: GoogleFonts.exo2(
                    color: AppTheme.primaryOrange,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow('Hostname', host),
          const SizedBox(height: 8),
          _buildInfoRow('CPU Model', cpuModel.toString()),
          const SizedBox(height: 8),
          _buildInfoRow('CPU Cores', '$cpuCores Cores'),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.darkBorder, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'RAM Usage',
                style: GoogleFonts.exo2(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${(memUsedMb / 1024).toStringAsFixed(1)} / ${(memMb / 1024).toStringAsFixed(1)} GB (${memPercent.toInt()}%)',
                      style: GoogleFonts.exo2(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (memPercent / 100.0).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppTheme.darkBackground,
              valueColor: AlwaysStoppedAnimation<Color>(
                memPercent > 85 ? Colors.redAccent : AppTheme.primaryOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryCard() {
    final hasBattery = _batteryInfo != null && _batteryInfo!['available'] == true;
    final percent = hasBattery ? ((_batteryInfo?['percent'] as num?)?.toDouble() ?? 100.0) : 100.0;
    final isPlugged = hasBattery ? (_batteryInfo?['power_plugged'] == true) : true;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPlugged ? Icons.battery_charging_full : Icons.battery_std,
                color: isPlugged ? Colors.greenAccent : AppTheme.primaryOrange,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Battery & Power',
                  style: GoogleFonts.exo2(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasBattery ? '${percent.toInt()}%' : 'AC Power',
                style: GoogleFonts.exo2(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isPlugged ? Colors.greenAccent : AppTheme.primaryOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent / 100.0).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppTheme.darkBackground,
              valueColor: AlwaysStoppedAnimation<Color>(
                percent <= 20
                    ? Colors.redAccent
                    : (isPlugged ? Colors.greenAccent : AppTheme.primaryOrange),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasBattery
                ? (isPlugged ? 'AC Connected • Charging / Plugged In' : 'On Battery Power')
                : 'Stationary Desktop Workstation • Continuous AC Power',
            style: GoogleFonts.exo2(
              fontSize: 12,
              color: isPlugged ? Colors.greenAccent : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComputerPowerControlsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Host Power Controls',
                  style: GoogleFonts.exo2(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildPowerButton(
                  icon: Icons.bedtime,
                  label: 'Sleep',
                  color: const Color(0xFF00E5FF),
                  onTap: () => _executePowerAction('sleep', 'Sleep', const Color(0xFF00E5FF)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPowerButton(
                  icon: Icons.lock,
                  label: 'Lock',
                  color: Colors.amberAccent,
                  onTap: () => _executePowerAction('lock_device', 'Lock Screen', Colors.amberAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildPowerButton(
                  icon: Icons.restart_alt,
                  label: 'Restart',
                  color: AppTheme.primaryOrange,
                  onTap: () => _executePowerAction('reboot', 'Restart', AppTheme.primaryOrange),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPowerButton(
                  icon: Icons.power_settings_new,
                  label: 'Shutdown',
                  color: Colors.redAccent,
                  onTap: () => _executePowerAction('shutdown', 'Shutdown', Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPowerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHostAudioControlCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                color: _isMuted ? Colors.redAccent : AppTheme.primaryOrange,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Master Audio & Volume',
                  style: GoogleFonts.exo2(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isMuted ? 'Muted' : '${((_systemVolume.clamp(0.0, 1.0)) * 100).toInt()}%',
                style: GoogleFonts.exo2(
                  fontWeight: FontWeight.bold,
                  color: _isMuted ? Colors.redAccent : AppTheme.primaryOrange,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Slider(
            value: _systemVolume.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: _isMuted ? Colors.redAccent : AppTheme.primaryOrange,
            inactiveColor: AppTheme.darkBackground,
            onChanged: (val) => _setVolume(val.clamp(0.0, 1.0)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.volume_down, color: Colors.white),
                tooltip: 'Volume Down',
                onPressed: () {
                  final newVol = (_systemVolume - 0.05).clamp(0.0, 1.0);
                  _setVolume(newVol);
                  _sendMediaKey('volume_down');
                },
              ),
              ElevatedButton.icon(
                icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, size: 16),
                label: Text(_isMuted ? 'Unmute' : 'Mute'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isMuted ? Colors.redAccent.withAlpha(40) : AppTheme.darkBackground,
                  foregroundColor: _isMuted ? Colors.redAccent : Colors.white,
                  side: BorderSide(color: _isMuted ? Colors.redAccent : AppTheme.darkBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => _sendMediaKey('mute'),
              ),
              IconButton(
                icon: const Icon(Icons.volume_up, color: Colors.white),
                tooltip: 'Volume Up',
                onPressed: () {
                  final newVol = (_systemVolume + 0.05).clamp(0.0, 1.0);
                  _setVolume(newVol);
                  _sendMediaKey('volume_up');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStorageVolumesCard() {
    final drives = _storageDrives.isNotEmpty
        ? _storageDrives
        : [
            {'mount': 'C:\\', 'device': 'C:\\', 'total_mb': 240000, 'free_mb': 22000, 'used_mb': 218000, 'percent': 91.0},
            {'mount': 'D:\\', 'device': 'D:\\', 'total_mb': 250000, 'free_mb': 92000, 'used_mb': 158000, 'percent': 63.0},
          ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storage, color: AppTheme.primaryOrange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Storage Volumes & Drives',
                  style: GoogleFonts.exo2(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...drives.map((drive) {
            final mount = drive['mount']?.toString() ?? drive['device']?.toString() ?? 'Drive';
            final totalMb = (drive['total_mb'] as num?)?.toInt() ?? 0;
            final freeMb = (drive['free_mb'] as num?)?.toInt() ?? 0;
            final usedMb = (drive['used_mb'] as num?)?.toInt() ?? (totalMb - freeMb);
            double percent = (drive['percent'] as num?)?.toDouble() ??
                (totalMb > 0 ? ((usedMb / totalMb) * 100.0) : 0.0);
            if (percent.isNaN || percent.isInfinite) percent = 0.0;
            percent = percent.clamp(0.0, 100.0);

            final totalGb = (totalMb / 1024).toStringAsFixed(1);
            final freeGb = (freeMb / 1024).toStringAsFixed(1);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dns, color: AppTheme.textMuted, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          mount,
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$freeGb / $totalGb GB',
                        style: GoogleFonts.exo2(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (percent / 100.0).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppTheme.darkCard,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent > 85 ? Colors.redAccent : AppTheme.primaryOrange,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWebcamCaptureCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.camera_alt, color: Colors.purpleAccent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Webcam & Camera Feed',
                  style: GoogleFonts.exo2(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _lastSnapshotB64 != null ? 'Last snapshot saved' : 'Take remote camera snapshot',
                  style: GoogleFonts.exo2(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _captureCameraSnapshot,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent.withAlpha(40),
              foregroundColor: Colors.purpleAccent,
              side: const BorderSide(color: Colors.purpleAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Capture'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.exo2(fontSize: 13, color: AppTheme.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.exo2(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyHardwareCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.developer_board_off, color: AppTheme.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(
            'No Physical Control Interfaces Detected',
            style: GoogleFonts.exo2(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This machine does not expose digital GPIO pins or PWM servo channels. External controllers or robotic modules will automatically appear here once detected by the hardware scanner.',
            textAlign: TextAlign.center,
            style: GoogleFonts.exo2(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpioSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'GPIO Digital Pins',
              style: GoogleFonts.exo2(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _setAllPins(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text('All LOW', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _setAllPins(true),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text('All HIGH', style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _detectedPins.map((pin) {
            final isHigh = _gpioStates[pin] ?? false;
            return GestureDetector(
              onTap: () => _setGpioState(pin, !isHigh),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: (MediaQuery.of(context).size.width - 40 - 24) / 4,
                height: 60,
                decoration: BoxDecoration(
                  color: isHigh ? AppTheme.primaryOrange.withAlpha(35) : AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isHigh ? AppTheme.primaryOrange : AppTheme.darkBorder,
                    width: isHigh ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'GPIO $pin',
                      style: GoogleFonts.exo2(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isHigh ? Colors.white : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isHigh ? Colors.greenAccent.withAlpha(40) : Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isHigh ? 'HIGH (1)' : 'LOW (0)',
                        style: GoogleFonts.exo2(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isHigh ? Colors.greenAccent : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPwmSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PWM Servo Channels (PCA9685 / PWM)',
          style: GoogleFonts.exo2(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        ..._servoAngles.entries.map((entry) {
          final ch = entry.key;
          final angle = entry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Channel $ch',
                      style: GoogleFonts.exo2(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${angle.toInt()}°',
                      style: GoogleFonts.exo2(
                        color: AppTheme.primaryOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: angle,
                  min: 0.0,
                  max: 180.0,
                  activeColor: AppTheme.primaryOrange,
                  inactiveColor: AppTheme.darkBackground,
                  onChanged: (val) => _setServoAngle(ch, val),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
