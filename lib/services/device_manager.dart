import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/dcp_models.dart';

class DeviceManager extends ChangeNotifier {
  static final DeviceManager _instance = DeviceManager._internal();
  factory DeviceManager() => _instance;

  DeviceManager._internal() {
    _initDefaultDevices();
    _startTelemetryLoop();
  }

  // Registered Paired Devices
  final List<DeviceItem> _devices = [];
  List<DeviceItem> get devices => _devices;

  // Discovered Nearby Devices (for Discovery screen)
  final List<DeviceItem> _nearbyDevices = [];
  List<DeviceItem> get nearbyDevices => _nearbyDevices;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

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
    return _sshConfigs.putIfAbsent(deviceId, () => SSHConfig(hostname: '192.168.1.102'));
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

  void toggleDeviceConnection(String deviceId, bool connected) {
    final idx = _devices.indexWhere((d) => d.id == deviceId);
    if (idx != -1) {
      _devices[idx].isConnected = connected;
      notifyListeners();
    }
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

  void startScan() {
    _isScanning = true;
    _nearbyDevices.clear();
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
    super.dispose();
  }
}
