import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/connection/device_connection.dart';
import '../core/dcp/dcp_message.dart';
import '../models/dcp_models.dart';
import 'app_startup_service.dart';
import 'capability_manager.dart';
import 'device_registry.dart';
import 'discovery_manager.dart';
import 'event_manager.dart';
import 'pairing_manager.dart';
import 'task_manager.dart';
import 'tool_manager.dart';
import 'voice_command_service.dart';

/// Central facade orchestrating discovery, pairing, transports, DCP sessions,
/// and telemetry for the MachineMake application.
class DeviceManager extends ChangeNotifier {
  static final DeviceManager _instance = DeviceManager._internal();
  factory DeviceManager() => _instance;

  String _clientId = const Uuid().v4();

  void initFromStartup({required String clientId}) {
    _clientId = clientId;
    for (final known in registry.devices) {
      if (!_devices.any((d) => d.id == known.deviceId)) {
        final t = known.type.toLowerCase();
        final isQuad = t.contains('quad') || t.contains('robot');
        final isRpi = t.contains('raspberry');
        _devices.add(DeviceItem(
          id: known.deviceId,
          name: known.name,
          profile: isQuad ? 'quadruped' : (isRpi ? 'raspberry_pi' : 'pico'),
          deviceType: isQuad ? 'Quadruped Robot' : (isRpi ? 'Raspberry Pi' : 'Microcontroller'),
          availableTransports: [known.lastBleAddress != null ? 'bluetooth' : 'wifi'],
          selectedTransport: known.lastBleAddress != null ? 'bluetooth' : 'wifi',
          isPaired: known.isTrusted,
          isConnected: false,
          iconKey: isQuad ? 'quadruped' : (isRpi ? 'rpi' : 'pico'),
          ipAddress: known.lastIp,
          port: known.lastPort ?? 8765,
          macAddress: known.lastBleAddress,
        ));
      }
    }
    notifyListeners();
  }

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
  DeviceConnection? getConnection(String deviceId) => _connections[deviceId];

  DeviceManager._internal() {
    discovery.addListener(notifyListeners);
    _startTelemetryLoop();
    _subscribeGlobalEvents();
  }

  // Registered / Connected Devices for UI
  final List<DeviceItem> _devices = [];

  /// Only returns devices where the app has established connection.
  List<DeviceItem> get devices =>
      _devices.where((d) => d.isConnected).toList();

  /// All paired devices (including currently disconnected ones).
  List<DeviceItem> get allPairedDevices => List.unmodifiable(_devices);

  void addDevice(DeviceItem device) {
    final idx = _devices.indexWhere((d) => d.id == device.id);
    if (idx >= 0) {
      _devices[idx] = device;
    } else {
      _devices.add(device);
    }
    if (device.isConnected) {
      _connectDevice(device.id);
    }
    notifyListeners();
  }

  void removeDevice(String deviceId) {
    final conn = _connections.remove(deviceId);
    if (conn != null) {
      try {
        conn.disconnect();
        conn.dispose();
      } catch (_) {}
    }
    _devices.removeWhere((d) => d.id == deviceId);
    if (_selectedDeviceId == deviceId) {
      _selectedDeviceId = _devices.isNotEmpty ? _devices.first.id : '';
    }
    registry.removeDevice(deviceId);
    notifyListeners();
  }

  void clearAllDevices() {
    for (final conn in _connections.values) {
      try {
        conn.disconnect();
        conn.dispose();
      } catch (_) {}
    }
    _connections.clear();
    _devices.clear();
    _selectedDeviceId = '';
    registry.clearAll();
    notifyListeners();
  }

  // Discovered Nearby Devices (for Discovery screen — only real detected devices)
  List<DeviceItem> get nearbyDevices {
    return discovery.discovered.map((d) {
      final t = d.type.toLowerCase();
      final isQuad = t.contains('quad');
      final isRobot = t.contains('robot') || isQuad;
      final isRpi = t.contains('raspberry') || t == 'computer' || t == 'sbc';

      return DeviceItem(
        id: d.deviceId,
        name: d.name,
        profile: isQuad ? 'quadruped' : (isRobot ? 'quadruped' : (isRpi ? 'raspberry_pi' : 'pico')),
        deviceType: isQuad ? 'Quadruped Robot' : (isRobot ? 'Robot' : (isRpi ? 'Raspberry Pi' : 'Microcontroller')),
        availableTransports: d.transports.toList(),
        selectedTransport: d.primaryTransport,
        isPaired: false,
        isConnected: false,
        iconKey: (isQuad || isRobot) ? 'quadruped' : (isRpi ? 'rpi' : 'pico'),
        ipAddress: d.ipAddress,
        port: d.port ?? 8765,
        macAddress: d.bleAddress,
      );
    }).toList();
  }

  bool get isScanning => discovery.isScanning;

  // Currently Selected Device for Operations & Telemetry
  String _selectedDeviceId = '';
  String get selectedDeviceId {
    if (devices.any((d) => d.id == _selectedDeviceId)) {
      return _selectedDeviceId;
    }
    return devices.isNotEmpty ? devices.first.id : '';
  }

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

  void saveSSHConfig(
    String deviceId,
    String hostname,
    String password, {
    String? username,
    int? port,
  }) {
    final cfg = getSSHConfig(deviceId);
    cfg.hostname = hostname;
    cfg.password = password;
    if (username != null) cfg.username = username;
    if (port != null) cfg.port = port;
    notifyListeners();
  }

  // Settings Toggles
  bool alertOnDisconnect = true;
  bool autoEnableBTOnStart = true;
  bool autoEnableWifiOnStart = true;

  void toggleAlertOnDisconnect(bool val) {
    alertOnDisconnect = val;
    _persistSettings();
    notifyListeners();
  }

  void toggleAutoEnableBT(bool val) {
    autoEnableBTOnStart = val;
    _persistSettings();
    notifyListeners();
  }

  void toggleAutoEnableWifi(bool val) {
    autoEnableWifiOnStart = val;
    _persistSettings();
    notifyListeners();
  }

  void _persistSettings() {
    AppStartupService.saveSettings(
      alertOnDisconnect: alertOnDisconnect,
      autoEnableBT: autoEnableBTOnStart,
      autoEnableWifi: autoEnableWifiOnStart,
    );
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
    final known = registry.findById(deviceId);
    final psk = known?.psk;

    if (transportType == 'bluetooth' && dev.macAddress != null && dev.macAddress!.isNotEmpty) {
      await conn.connectBluetooth(
        bleAddress: dev.macAddress!,
        psk: psk,
        clientId: _clientId,
      );
    } else if (transportType == 'wifi' && dev.ipAddress != null && dev.ipAddress!.isNotEmpty) {
      await conn.connectWifi(
        host: dev.ipAddress!,
        port: dev.port,
        psk: psk,
        clientId: _clientId,
      );
    } else {
      // Mock fallback if no physical address is known
      final mockType = dev.profile == 'quadruped'
          ? 'robot'
          : (dev.profile == 'raspberry_pi' ? 'raspberry_pi' : 'pico');
      await conn.connectMock(
        mockDeviceType: mockType,
        psk: psk,
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

  /// Executes an arbitrary registered tool on the connected device.
  Future<DcpExecuteResponse> executeTool(
    String deviceId,
    String toolName,
    Map<String, dynamic> params,
  ) async {
    final conn = _connections[deviceId];
    if (conn == null || conn.session == null) {
      throw Exception('Device $deviceId is not connected');
    }
    return await conn.session!.executeTool(toolName, params);
  }

  /// Parses natural language voice text and executes the matching tool on the device.
  Future<VoiceExecutionResult> executeVoiceCommand(
    String deviceId,
    String voiceText,
  ) async {
    final dev = _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => DeviceItem(
        id: deviceId,
        name: 'Device',
        profile: 'quadruped',
        deviceType: 'Quadruped Robot',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: false,
        iconKey: 'quadruped',
      ),
    );

    final knownTools = tool.getTools(deviceId).map((t) => t.name).toList();
    final cmd = VoiceCommandService.parse(voiceText, availableTools: knownTools);

    if (cmd == null) {
      return VoiceExecutionResult(
        success: false,
        userPrompt: voiceText,
        message: 'Command not recognized. Try "walk forward", "turn left", "stand", "sit", or "light on".',
      );
    }

    final conn = _connections[deviceId];
    if (conn == null || !conn.isConnected || conn.session == null) {
      return VoiceExecutionResult(
        success: false,
        toolName: cmd.toolName,
        params: cmd.parameters,
        userPrompt: voiceText,
        message: '${dev.name} is not connected. Connect from the Devices tab first.',
      );
    }

    try {
      final response = await conn.session!.executeTool(cmd.toolName, cmd.parameters);
      if (response.success) {
        return VoiceExecutionResult(
          success: true,
          toolName: cmd.toolName,
          params: cmd.parameters,
          userPrompt: voiceText,
          message: '${cmd.description} executed',
          response: response,
        );
      } else {
        return VoiceExecutionResult(
          success: false,
          toolName: cmd.toolName,
          params: cmd.parameters,
          userPrompt: voiceText,
          message: response.error ?? 'Execution rejected by device',
          response: response,
        );
      }
    } catch (e) {
      return VoiceExecutionResult(
        success: false,
        toolName: cmd.toolName,
        params: cmd.parameters,
        userPrompt: voiceText,
        message: 'Communication error: $e',
      );
    }
  }

  void startScan() {
    discovery.startScan();
    notifyListeners();
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

  Timer? _telemetryTimer;
  void _startTelemetryLoop() {
    _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      for (final device in devices) {
        final existing = _telemetryMap[device.id];
        if (existing != null) {
          _telemetryMap[device.id] = existing.copyWith(
            cpuUsage: (existing.cpuUsage + ((timer.tick % 5) - 2) * 0.5).clamp(1.0, 100.0),
            ramUsage: (existing.ramUsage + ((timer.tick % 3) - 1) * 0.3).clamp(1.0, 100.0),
          );
        }
      }
      if (devices.isNotEmpty) {
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
