import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/connection/device_connection.dart';
import '../core/dcp/dcp_message.dart';
import '../core/models/device_event.dart';
import '../core/models/task_model.dart';
import '../models/dcp_models.dart';
import 'app_startup_service.dart';
import 'capability_manager.dart';
import 'device_registry.dart';
import 'discovery_manager.dart';
import 'event_manager.dart';
import 'notification_service.dart';
import 'pairing_manager.dart';
import 'task_manager.dart';
import 'tool_manager.dart';
import 'voice_command_service.dart';
import 'needle_ai_service.dart';
import '../core/needle/needle_models.dart';

/// Central facade orchestrating discovery, pairing, transports, DCP sessions,
/// and telemetry for the MachineMake application.
class DeviceManager extends ChangeNotifier {
  static final DeviceManager _instance = DeviceManager._internal();
  factory DeviceManager() => _instance;

  String _clientId = const Uuid().v4();

  void initFromStartup({required String clientId}) {
    _clientId = clientId;
    for (final known in registry.devices) {
      if (known.sshUsername != null && known.sshPassword != null) {
        _sshConfigs[known.deviceId] = SSHConfig(
          hostname: known.lastIp ?? '192.168.1.102',
          username: known.sshUsername!,
          password: known.sshPassword!,
          port: known.sshPort ?? 22,
        );
      }
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
  final Set<String> _intentionalDisconnects = {};

  DeviceConnection? getConnection(String deviceId) => _connections[deviceId];

  DeviceConnection _getOrCreateConnection(String deviceId) {
    return _connections.putIfAbsent(deviceId, () {
      final conn = DeviceConnection(deviceId: deviceId);
      conn.addListener(() => _handleConnectionChange(deviceId, conn));
      return conn;
    });
  }

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
    return _sshConfigs.putIfAbsent(deviceId, () {
      final known = registry.findById(deviceId);
      final dev = _devices.where((d) => d.id == deviceId).firstOrNull;
      final host = (known?.lastIp != null && known!.lastIp!.isNotEmpty)
          ? known.lastIp!
          : (dev?.ipAddress ?? '192.168.1.102');
      return SSHConfig(
        hostname: host,
        username: known?.sshUsername ?? 'pi',
        password: known?.sshPassword ?? '',
        port: known?.sshPort ?? 22,
      );
    });
  }

  bool hasSavedSshCredentials(String deviceId) {
    final known = registry.findById(deviceId);
    if (known != null &&
        known.sshUsername != null &&
        known.sshUsername!.isNotEmpty &&
        known.sshPassword != null &&
        known.sshPassword!.isNotEmpty) {
      return true;
    }
    final cfg = _sshConfigs[deviceId];
    return cfg != null && cfg.username.isNotEmpty && cfg.password.isNotEmpty;
  }

  Future<void> saveSshCredentials(
    String deviceId, {
    required String username,
    required String password,
    String? hostname,
    int port = 22,
  }) async {
    final known = registry.findById(deviceId);
    if (known != null) {
      final updated = known.copyWith(
        sshUsername: username,
        sshPassword: password,
        sshPort: port,
        lastIp: (hostname != null && hostname.isNotEmpty) ? hostname : known.lastIp,
      );
      await registry.addOrUpdate(updated);
    }

    final dev = _devices.where((d) => d.id == deviceId).firstOrNull;
    final host = (hostname != null && hostname.isNotEmpty)
        ? hostname
        : (known?.lastIp ?? dev?.ipAddress ?? '192.168.1.102');

    saveSSHConfig(
      deviceId,
      host,
      password,
      username: username,
      port: port,
    );
    notifyListeners();
  }

  Future<void> removeSshCredentials(String deviceId) async {
    final known = registry.findById(deviceId);
    if (known != null) {
      final updated = known.copyWith(clearSsh: true);
      await registry.addOrUpdate(updated);
    }
    _sshConfigs.remove(deviceId);
    notifyListeners();
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
      if (!connected) {
        _intentionalDisconnects.add(deviceId);
      } else {
        _intentionalDisconnects.remove(deviceId);
      }
      _devices[idx].isConnected = connected;

      if (connected) {
        _connectDevice(deviceId);
      } else {
        _disconnectDevice(deviceId);
      }
      notifyListeners();
    }
  }

  void _handleConnectionChange(String deviceId, DeviceConnection conn) {
    final idx = _devices.indexWhere((d) => d.id == deviceId);
    if (idx == -1) return;

    final dev = _devices[idx];
    final isConn = conn.isConnected;

    if (dev.isConnected && !isConn) {
      // Unexpected or transport-level disconnect
      dev.isConnected = false;
      notifyListeners();

      final wasIntentional = _intentionalDisconnects.remove(deviceId);
      if (!wasIntentional && alertOnDisconnect) {
        NotificationService.instance.showDeviceDisconnectedNotification(
          deviceName: dev.name,
          deviceId: dev.id,
        );

        event.emit(DeviceEvent(
          eventType: 'alert',
          deviceId: deviceId,
          data: {
            'title': 'Device Disconnected',
            'message': '${dev.name} disconnected unexpectedly',
            'level': 'warning',
            'timestamp': DateTime.now().toIso8601String(),
          },
        ));
      }
    } else if (!dev.isConnected && isConn) {
      dev.isConnected = true;
      _intentionalDisconnects.remove(deviceId);
      notifyListeners();

      NotificationService.instance.showDeviceConnectedNotification(
        deviceName: dev.name,
        deviceId: dev.id,
      );
    }
  }

  /// Actively checks whether a connected device is still reachable over the network/BLE.
  Future<bool> checkDeviceConnection(String deviceId) async {
    final conn = _connections[deviceId];
    if (conn == null) return false;
    final alive = await conn.checkConnection();
    final idx = _devices.indexWhere((d) => d.id == deviceId);
    if (idx != -1) {
      if (!alive && _devices[idx].isConnected) {
        _handleConnectionChange(deviceId, conn);
      }
    }
    return alive;
  }

  /// Actively checks connection health across all connected devices.
  Future<Map<String, bool>> checkAllDeviceConnections() async {
    final results = <String, bool>{};
    for (final dev in _devices) {
      if (dev.isConnected) {
        final alive = await checkDeviceConnection(dev.id);
        results[dev.id] = alive;
      }
    }
    return results;
  }

  Future<void> _connectDevice(String deviceId) async {
    final conn = _getOrCreateConnection(deviceId);

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
  /// If the tool is async and returns a task_id, the task is tracked in [TaskManager].
  Future<DcpExecuteResponse> executeTool(
    String deviceId,
    String toolName,
    Map<String, dynamic> params,
  ) async {
    final conn = _connections[deviceId];
    if (conn == null || conn.session == null) {
      throw Exception('Device $deviceId is not connected');
    }
    final response = await conn.session!.executeTool(toolName, params);

    // Track long-running tasks in TaskManager
    if (response.taskId != null) {
      task.addTask(DeviceTask(
        taskId: response.taskId!,
        deviceId: deviceId,
        toolName: toolName,
        params: params,
      ));
    }

    return response;
  }

  /// Parses natural language voice text and executes through Needle AI (dual on-device/local engine).
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

    final conn = _connections[deviceId];
    if (conn == null || !conn.isConnected || conn.session == null) {
      return VoiceExecutionResult(
        success: false,
        userPrompt: voiceText,
        message: '${dev.name} is not connected. Connect from the Devices tab first.',
      );
    }

    final needleResponse = await NeedleAiService.instance.processCommand(
      deviceId: deviceId,
      prompt: voiceText,
    );

    final locPrefix = needleResponse.executedWhere == NeedleExecutionMode.device
        ? '[On-Device AI]'
        : '[Local App AI]';

    return VoiceExecutionResult(
      success: needleResponse.success,
      toolName: needleResponse.plan?.toolName,
      params: needleResponse.plan?.parameters,
      userPrompt: voiceText,
      message: '$locPrefix ${needleResponse.message}',
      executedWhere: needleResponse.executedWhere,
    );
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
