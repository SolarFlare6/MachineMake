import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/connection/device_connection.dart';
import '../models/dcp_models.dart';
import 'capability_manager.dart';
import 'device_registry.dart';
import 'discovery_manager.dart';
import 'event_manager.dart';
import 'pairing_manager.dart';
import 'task_manager.dart';
import 'tool_manager.dart';

/// Central facade orchestrating discovery, pairing, transports, DCP sessions,
/// and telemetry for the MachineMake application.
class DeviceManager extends ChangeNotifier {
  static final DeviceManager _instance = DeviceManager._internal();
  factory DeviceManager() => _instance;

  final String _clientId = const Uuid().v4();

  // Framework Subsystem Managers
  final DeviceRegistry registry = DeviceRegistry();
  final DiscoveryManager discovery = DiscoveryManager();
  final PairingManager pairing = PairingManager();
  final CapabilityManager capability = CapabilityManager();
  final ToolManager tool = ToolManager();
  final TaskManager task = TaskManager();
  final EventManager event = EventManager();

  // Active DeviceConnection instances per device ID
  final Map<String, DeviceConnection> _connections = {};

  DeviceManager._internal() {
    _initDefaultDevices();
    _startTelemetryLoop();
    _subscribeGlobalEvents();
  }

  // Registered Devices for UI
  final List<DeviceItem> _devices = [];
  List<DeviceItem> get devices => _devices;

  // Discovered Nearby Devices (for Discovery screen)
  List<DeviceItem> get nearbyDevices {
    if (discovery.discovered.isNotEmpty) {
      return discovery.discovered.map((d) {
        return DeviceItem(
          id: d.deviceId,
          name: d.name,
          profile: d.type == 'robot'
              ? 'quadruped'
              : (d.type == 'raspberry_pi' ? 'raspberry_pi' : 'pico'),
          deviceType: d.type == 'robot'
              ? 'Robot'
              : (d.type == 'raspberry_pi' ? 'Raspberry Pi' : 'Microcontroller'),
          availableTransports: d.transports.toList(),
          selectedTransport: d.primaryTransport,
          isPaired: false,
          isConnected: false,
          iconKey: d.type == 'robot'
              ? 'quadruped'
              : (d.type == 'raspberry_pi' ? 'rpi' : 'pico'),
          ipAddress: d.ipAddress,
          macAddress: d.bleAddress,
        );
      }).toList();
    }
    return _nearbyDevices;
  }

  final List<DeviceItem> _nearbyDevices = [];
  bool get isScanning => discovery.isScanning || _isScanning;
  bool _isScanning = false;

  // Currently Selected Device for Operations & Telemetry
  String _selectedDeviceId = 'quad-001';
  String get selectedDeviceId => _selectedDeviceId;

  DeviceItem? get selectedDevice {
    try {
      return _devices.firstWhere((d) => d.id == _selectedDeviceId);
    } catch (_) {
      return _devices.isNotEmpty ? _devices.first : null;
    }
  }

  // Telemetry map per device ID
  final Map<String, TelemetryData> _telemetryMap = {};

  TelemetryData getTelemetry(String deviceId) {
    return _telemetryMap[deviceId] ?? TelemetryData();
  }

  // SSH Configuration map per device ID
  final Map<String, SSHConfig> _sshConfigs = {};

  SSHConfig getSSHConfig(String deviceId) {
    return _sshConfigs.putIfAbsent(
        deviceId, () => SSHConfig(hostname: '192.168.1.102'));
  }

  void saveSSHConfig(String deviceId, String hostname, String password) {
    final cfg = getSSHConfig(deviceId);
    cfg.hostname = hostname;
    cfg.password = password;
    notifyListeners();
  }

  // Settings Toggles
  bool alertOnDisconnect = true;
  bool autoEnableBTOnStart = true;
  bool autoEnableWifiOnStart = true;

  void toggleAlertOnDisconnect(bool val) {
    alertOnDisconnect = val;
    notifyListeners();
  }

  void toggleAutoEnableBT(bool val) {
    autoEnableBTOnStart = val;
    notifyListeners();
  }

  void toggleAutoEnableWifi(bool val) {
    autoEnableWifiOnStart = val;
    notifyListeners();
  }

  void setSelectedDevice(String deviceId) {
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  /// Toggles connection to a device using the UDCF DeviceConnection lifecycle.
  void toggleDeviceConnection(String deviceId, bool connected) {
    final idx = _devices.indexWhere((d) => d.id == deviceId);
    if (idx != -1) {
      _devices[idx].isConnected = connected;

      if (connected) {
        _connectDevice(deviceId);
      } else {
        _disconnectDevice(deviceId);
      }
      notifyListeners();
    }
  }

  Future<void> _connectDevice(String deviceId) async {
    final conn = _connections.putIfAbsent(
      deviceId,
      () => DeviceConnection(deviceId: deviceId),
    );

    final dev = _devices.firstWhere((d) => d.id == deviceId);
    final transportType = dev.selectedTransport.toLowerCase();

    if (transportType == 'bluetooth' && dev.macAddress != null && dev.macAddress!.isNotEmpty) {
      await conn.connectBluetooth(
        bleAddress: dev.macAddress!,
        clientId: _clientId,
      );
    } else if (transportType == 'wifi' && dev.ipAddress != null && dev.ipAddress!.isNotEmpty) {
      await conn.connectWifi(
        host: dev.ipAddress!,
        port: 8765,
        clientId: _clientId,
      );
    } else {
      // Mock fallback if no physical address is known
      final mockType = dev.profile == 'quadruped'
          ? 'robot'
          : (dev.profile == 'raspberry_pi' ? 'raspberry_pi' : 'pico');
      await conn.connectMock(
        mockDeviceType: mockType,
        clientId: _clientId,
      );
    }

    if (conn.manifest != null) {
      capability.updateCapabilities(deviceId, conn.manifest!.capabilities);
      tool.updateTools(deviceId, conn.manifest!.tools);
    }
  }

  Future<void> _disconnectDevice(String deviceId) async {
    final conn = _connections[deviceId];
    if (conn != null) {
      await conn.disconnect();
    }
  }

  void startScan() {
    _isScanning = true;
    _nearbyDevices.clear();
    discovery.startScan();
    notifyListeners();

    Timer(const Duration(milliseconds: 1500), () {
      _nearbyDevices.addAll([
        DeviceItem(
          id: 'nearby-quad-001',
          name: 'Quadruped Bot',
          profile: 'quadruped',
          deviceType: 'Robot',
          availableTransports: ['WiFi', 'Bluetooth'],
          isPaired: false,
          isConnected: false,
          iconKey: 'quadruped',
        ),
        DeviceItem(
          id: 'nearby-rpi-001',
          name: 'Raspberry Pi',
          profile: 'raspberry_pi',
          deviceType: 'Raspberry Pi',
          availableTransports: ['WiFi', 'Bluetooth'],
          isPaired: false,
          isConnected: false,
          iconKey: 'rpi',
        ),
        DeviceItem(
          id: 'nearby-pico-001',
          name: 'Pi Pico',
          profile: 'pico',
          deviceType: 'Microcontroller',
          availableTransports: ['WiFi'],
          isPaired: false,
          isConnected: false,
          iconKey: 'pico',
        ),
      ]);
      _isScanning = false;
      notifyListeners();
    });
  }

  void _subscribeGlobalEvents() {
    event.events.listen((e) {
      if (e.eventType == 'telemetry') {
        final d = e.data;
        final cpu = (d['cpu'] as num?)?.toDouble() ?? 0.0;
        final ram = (d['ram'] as num?)?.toDouble() ?? 0.0;
        final gpu = (d['gpu'] as num?)?.toDouble() ?? 0.0;
        final tmp = (d['temp'] as num?)?.toDouble() ?? 0.0;

        _telemetryMap[e.deviceId] = TelemetryData(
          cpuUsage: cpu,
          ramUsage: ram,
          gpuUsage: gpu,
          temperature: tmp,
        );
        notifyListeners();
      }
    });
  }

  void _initDefaultDevices() {
    _devices.addAll([
      DeviceItem(
        id: 'quad-001',
        name: 'Quadruped Bot',
        profile: 'quadruped',
        deviceType: 'Robot',
        availableTransports: ['wifi', 'bluetooth'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'quadruped',
        ipAddress: '192.168.1.101',
      ),
      DeviceItem(
        id: 'rpi-001',
        name: 'Raspberry Pi',
        profile: 'raspberry_pi',
        deviceType: 'Raspberry Pi',
        availableTransports: ['wifi', 'bluetooth'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'rpi',
        ipAddress: '192.168.1.102',
      ),
      DeviceItem(
        id: 'pico-001',
        name: 'Pi Pico',
        profile: 'pico',
        deviceType: 'Microcontroller',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: false,
        iconKey: 'pico',
      ),
      DeviceItem(
        id: 'dev-001',
        name: 'Device name',
        profile: 'generic',
        deviceType: 'Device Type',
        availableTransports: ['wifi', 'bluetooth'],
        selectedTransport: 'bluetooth',
        isPaired: true,
        isConnected: false,
        iconKey: 'generic',
      ),
    ]);

    _telemetryMap['quad-001'] = TelemetryData(
      cpuUsage: 75.0,
      ramUsage: 75.0,
      gpuUsage: 75.0,
      temperature: 30.0,
    );

    _telemetryMap['rpi-001'] = TelemetryData(
      cpuUsage: 42.0,
      ramUsage: 58.0,
      gpuUsage: 30.0,
      temperature: 45.0,
    );
  }

  Timer? _telemetryTimer;
  void _startTelemetryLoop() {
    _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final quad = _telemetryMap['quad-001'];
      if (quad != null) {
        _telemetryMap['quad-001'] = quad.copyWith(
          cpuUsage: (73.0 + (timer.tick % 5) * 0.8).clamp(0, 100),
          ramUsage: (74.5 + (timer.tick % 3) * 0.4).clamp(0, 100),
        );
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
    super.dispose();
  }
}
