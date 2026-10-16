import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/connection/connection_state_enum.dart';
import '../core/connection/device_connection.dart';
import '../core/dcp/dcp_message.dart';
import '../core/models/device_event.dart';
import '../core/models/device_notification_model.dart';
import '../core/models/device_profile.dart';
import '../core/models/task_model.dart';
import '../models/dcp_models.dart';
import 'app_startup_service.dart';
import 'capability_manager.dart';
import 'device_registry.dart';
import 'discovery_manager.dart';
import 'event_manager.dart';
import 'keep_alive_service.dart';
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
  String get clientId => _clientId;

  Future<void> reloadFromStartup({String? clientId}) async {
    _devices.clear();
    _sshConfigs.clear();
    await registry.load();
    initFromStartup(clientId: clientId ?? _clientId);
  }

  void initFromStartup({required String clientId}) {
    _clientId = clientId;
    for (final known in registry.devices) {
      final p = DeviceProfile.fromString(known.type);
      final isMcu = p == DeviceProfile.microcontroller;
      if (!isMcu && known.sshUsername != null && known.sshPassword != null) {
        _sshConfigs[known.deviceId] = SSHConfig(
          hostname: known.lastIp ?? '192.168.1.102',
          username: known.sshUsername!,
          password: known.sshPassword!,
          port: known.sshPort ?? 22,
        );
      }
      if (!_devices.any((d) => d.id == known.deviceId)) {
        final p = DeviceProfile.fromString(known.type);
        final t = known.type.toLowerCase();
        final isRpi = t.contains('raspberry');
        final profileKey = p.isRobot
            ? 'quadruped'
            : (p.isComputer
                ? (isRpi ? 'raspberry_pi' : 'computer')
                : (p == DeviceProfile.microcontroller ? 'pico' : 'generic'));
        final typeLabel = p.isRobot
            ? (p == DeviceProfile.quadruped ? 'Quadruped Robot' : 'Robot')
            : (p.isComputer
                ? (isRpi ? 'Raspberry Pi' : 'Computer / PC')
                : (p == DeviceProfile.microcontroller ? 'Microcontroller' : 'Generic Device'));
        final icon = p.isRobot
            ? 'quadruped'
            : (p.isComputer ? (isRpi ? 'rpi' : 'computer') : (p == DeviceProfile.microcontroller ? 'pico' : 'generic'));

        _devices.add(DeviceItem(
          id: known.deviceId,
          name: known.name,
          profile: profileKey,
          deviceType: typeLabel,
          availableTransports: [known.lastBleAddress != null ? 'bluetooth' : 'wifi'],
          selectedTransport: known.lastBleAddress != null ? 'bluetooth' : 'wifi',
          isPaired: known.isTrusted,
          isConnected: false,
          iconKey: icon,
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
    discovery.addListener(_onDiscoveryUpdated);
    _startTelemetryLoop();
    _subscribeGlobalEvents();
  }

  void _onDiscoveryUpdated() {
    _syncSavedDevicesWithDiscovery();
    notifyListeners();
  }

  /// Cross-references saved devices from [DeviceRegistry] with actively discovered
  /// network candidates. If a saved device appears on the network, update its IP/port/status
  /// and automatically establish connection if appropriate.
  void _syncSavedDevicesWithDiscovery() {
    bool changed = false;
    for (final disc in discovery.discovered) {
      // Find matching saved device by ID or IP
      final known = registry.findById(disc.deviceId) ??
          (disc.ipAddress != null ? registry.findByIp(disc.ipAddress!) : null);
      if (known != null) {
        final targetId = known.deviceId;
        final idx = _devices.indexWhere((d) => d.id == targetId);
        if (idx >= 0) {
          final dev = _devices[idx];
          if (disc.ipAddress != null && dev.ipAddress != disc.ipAddress) {
            dev.ipAddress = disc.ipAddress;
            changed = true;
          }
          if (disc.port != null && dev.port != disc.port) {
            dev.port = disc.port!;
            changed = true;
          }
          final conn = _connections[targetId];
          final isConn = conn?.isConnected ?? false;
          if (isConn != dev.isConnected) {
            dev.isConnected = isConn;
            changed = true;
          }
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
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
    syncKeepAliveNotifications();
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
    KeepAliveService.instance.stop();
    notifyListeners();
  }

  // Discovered Nearby Devices (for Discovery screen — only real detected devices)
  List<DeviceItem> get nearbyDevices {
    return discovery.discovered.map((d) {
      final p = DeviceProfile.fromString(d.type);
      final t = d.type.toLowerCase();
      final isRpi = t.contains('raspberry');

      final profileKey = p.isRobot
          ? 'quadruped'
          : (p.isComputer
              ? (isRpi ? 'raspberry_pi' : 'computer')
              : (p == DeviceProfile.microcontroller ? 'pico' : 'generic'));

      final typeLabel = p.isRobot
          ? (p == DeviceProfile.quadruped ? 'Quadruped Robot' : 'Robot')
          : (p.isComputer
              ? (isRpi ? 'Raspberry Pi' : 'Computer / PC')
              : (p == DeviceProfile.microcontroller ? 'Microcontroller' : 'Generic Device'));

      final icon = p.isRobot
          ? 'quadruped'
          : (p.isComputer ? (isRpi ? 'rpi' : 'computer') : (p == DeviceProfile.microcontroller ? 'pico' : 'generic'));

      return DeviceItem(
        id: d.deviceId,
        name: d.name,
        profile: profileKey,
        deviceType: typeLabel,
        availableTransports: d.transports.toList(),
        selectedTransport: d.primaryTransport,
        isPaired: false,
        isConnected: false,
        iconKey: icon,
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
    final dev = _devices.where((d) => d.id == deviceId).firstOrNull;
    final profile = DeviceProfile.fromString(dev?.profile ?? known?.type);
    if (profile == DeviceProfile.microcontroller) {
      return;
    }

    if (known != null) {
      final updated = known.copyWith(
        sshUsername: username,
        sshPassword: password,
        sshPort: port,
        lastIp: (hostname != null && hostname.isNotEmpty) ? hostname : known.lastIp,
      );
      await registry.addOrUpdate(updated);
    }

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
  bool keepAliveInBackground = true;
  bool showQuickActionsOnLockScreen = true;
  bool showLiveTelemetryInNotification = true;

  // Per-device notification feedback & telemetry throttling
  final Map<String, String> _notificationFeedbackMap = {};
  final Map<String, DateTime> _notificationFeedbackExpiry = {};
  final Map<String, DateTime> _lastNotifTelemetrySync = {};
  final Map<String, Timer> _reconnectTimeoutTimers = {};

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

  void toggleKeepAliveInBackground(bool val) {
    keepAliveInBackground = val;
    DeviceConnection.keepAliveEnabled = val;
    _persistSettings();
    syncKeepAliveNotifications();
    notifyListeners();
  }

  void toggleShowQuickActionsOnLockScreen(bool val) {
    showQuickActionsOnLockScreen = val;
    _persistSettings();
    syncKeepAliveNotifications();
    notifyListeners();
  }

  void toggleShowLiveTelemetryInNotification(bool val) {
    showLiveTelemetryInNotification = val;
    _persistSettings();
    syncKeepAliveNotifications();
    notifyListeners();
  }

  void _persistSettings() {
    AppStartupService.saveSettings(
      alertOnDisconnect: alertOnDisconnect,
      autoEnableBT: autoEnableBTOnStart,
      autoEnableWifi: autoEnableWifiOnStart,
      keepAliveInBackground: keepAliveInBackground,
      showQuickActionsOnLockScreen: showQuickActionsOnLockScreen,
      showLiveTelemetryInNotification: showLiveTelemetryInNotification,
    );
  }

  /// Notifies all active connections when the app enters/exits background so
  /// heartbeat intervals and timeout tolerances adapt automatically.
  void setAppInBackground(bool inBackground) {
    if (DeviceConnection.isInBackground == inBackground) return;
    DeviceConnection.isInBackground = inBackground;
    for (final conn in _connections.values) {
      conn.refreshHeartbeatSchedule();
    }
    syncKeepAliveNotifications();
  }

  /// Sets a temporary status message on a device's ongoing notification card
  /// (e.g., after a quick action button press like "Temp: 26.8°C").
  void setNotificationFeedback(
    String deviceId,
    String feedback, {
    Duration duration = const Duration(seconds: 12),
  }) {
    _notificationFeedbackMap[deviceId] = feedback;
    _notificationFeedbackExpiry[deviceId] = DateTime.now().add(duration);
  }

  /// Resolves the up to 3 notification quick actions for [deviceId].
  List<DeviceNotificationAction> getDeviceNotificationActions(
    String deviceId,
    String profile,
  ) {
    final known = registry.findById(deviceId);
    return DeviceNotificationModel.resolveActions(
      profile: DeviceProfile.fromString(profile),
      customActionKeys: known?.notificationActions,
      availableTools: tool.getTools(deviceId),
    );
  }

  /// Customizes the notification quick action keys for a paired device.
  Future<void> setDeviceNotificationActions(
    String deviceId,
    List<String>? actionKeys,
  ) async {
    final known = registry.findById(deviceId);
    if (known != null) {
      final updated = known.copyWith(
        notificationActions: actionKeys,
        clearNotificationActions: actionKeys == null || actionKeys.isEmpty,
      );
      await registry.addOrUpdate(updated);
    }
    await syncKeepAliveNotifications();
    notifyListeners();
  }

  /// Synchronizes the native Android Foreground Service & ongoing notification
  /// cards with the currently connected (or reconnecting) devices.
  Future<void> syncKeepAliveNotifications() async {
    if (!keepAliveInBackground) {
      await KeepAliveService.instance.stop();
      return;
    }

    final now = DateTime.now();
    final activeModels = <DeviceNotificationModel>[];

    for (final d in _devices) {
      final conn = _connections[d.id];
      final isReconnecting = conn?.state == DeviceConnectionState.reconnecting;
      if (!d.isConnected && !isReconnecting) continue;

      String statusLine;
      final feedbackExpiry = _notificationFeedbackExpiry[d.id];
      final activeFeedback =
          (feedbackExpiry != null && now.isBefore(feedbackExpiry))
              ? _notificationFeedbackMap[d.id]
              : null;

      if (isReconnecting) {
        final target = d.ipAddress ?? d.selectedTransport.toUpperCase();
        statusLine = 'Reconnecting ($target)...';
      } else if (activeFeedback != null && activeFeedback.isNotEmpty) {
        statusLine = 'Connected · $activeFeedback';
      } else if (showLiveTelemetryInNotification) {
        final t = getTelemetry(d.id);
        final p = d.profile.toLowerCase();
        if (p == 'computer' || p == 'raspberry_pi' || p == 'laptop') {
          statusLine =
              'Connected · CPU ${t.cpuUsage.toStringAsFixed(0)}% · RAM ${t.ramUsage.toStringAsFixed(0)}% · ${t.temperature.toStringAsFixed(0)}°C';
        } else if (p == 'pico' || p == 'microcontroller' || p == 'esp32') {
          final tempPart = t.temperature > 0
              ? ' · Temp ${t.temperature.toStringAsFixed(1)}°C'
              : '';
          statusLine = 'Connected · ${d.ipAddress ?? "Wi-Fi"}$tempPart';
        } else if (p == 'quadruped' || p == 'robot') {
          final tempPart = t.temperature > 0
              ? ' · ${t.temperature.toStringAsFixed(0)}°C'
              : '';
          statusLine = 'Connected · Locomotion Ready$tempPart';
        } else {
          statusLine =
              'Connected · ${d.ipAddress ?? d.selectedTransport.toUpperCase()}';
        }
      } else {
        statusLine =
            'Connected · ${d.ipAddress ?? d.selectedTransport.toUpperCase()}';
      }

      activeModels.add(
        DeviceNotificationModel(
          deviceId: d.id,
          name: d.name,
          profile: d.profile,
          statusLine: statusLine,
          isReconnecting: isReconnecting,
          actions: getDeviceNotificationActions(d.id, d.profile),
        ),
      );
    }

    await KeepAliveService.instance.sync(
      activeModels,
      showOnLockScreen: showQuickActionsOnLockScreen,
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
        _reconnectTimeoutTimers.remove(deviceId)?.cancel();
      } else {
        _intentionalDisconnects.remove(deviceId);
      }
      _devices[idx].isConnected = connected;

      if (connected) {
        _connectDevice(deviceId);
      } else {
        _disconnectDevice(deviceId);
      }
      syncKeepAliveNotifications();
      notifyListeners();
    }
  }

  void _handleConnectionChange(String deviceId, DeviceConnection conn) {
    final idx = _devices.indexWhere((d) => d.id == deviceId);
    if (idx == -1) return;

    final dev = _devices[idx];
    final isConn = conn.isConnected;
    final state = conn.state;

    // While in silent background reconnection, keep the ongoing notification up
    // ("Reconnecting...") and suppress premature disconnect alerts unless
    // reconnection fails continuously for 60 seconds.
    if (state == DeviceConnectionState.reconnecting) {
      _reconnectTimeoutTimers[deviceId] ??= Timer(
        const Duration(seconds: 60),
        () {
          _reconnectTimeoutTimers.remove(deviceId);
          if (conn.state != DeviceConnectionState.connected && dev.isConnected) {
            dev.isConnected = false;
            notifyListeners();
            syncKeepAliveNotifications();
            if (alertOnDisconnect) {
              NotificationService.instance.showDeviceDisconnectedNotification(
                deviceName: dev.name,
                deviceId: dev.id,
              );
            }
          }
        },
      );
      syncKeepAliveNotifications();
      notifyListeners();
      return;
    }

    if (dev.isConnected && !isConn) {
      _reconnectTimeoutTimers.remove(deviceId)?.cancel();
      // Unexpected or transport-level disconnect
      dev.isConnected = false;
      syncKeepAliveNotifications();
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
    } else if (isConn) {
      final wasOffline = !dev.isConnected;
      _reconnectTimeoutTimers.remove(deviceId)?.cancel();
      dev.isConnected = true;
      _intentionalDisconnects.remove(deviceId);
      syncKeepAliveNotifications();
      notifyListeners();

      if (wasOffline) {
        NotificationService.instance.showDeviceConnectedNotification(
          deviceName: dev.name,
          deviceId: dev.id,
        );
      }
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

      final manifestType = conn.manifest!.type.toLowerCase();
      final p = DeviceProfile.fromString(manifestType);
      final devIdx = _devices.indexWhere((d) => d.id == deviceId);
      if (devIdx != -1) {
        final currentDev = _devices[devIdx];
        final isRpi = manifestType.contains('raspberry') || manifestType.contains('rpi');
        final profileKey = p.isRobot
            ? (p == DeviceProfile.quadruped ? 'quadruped' : 'robot')
            : (p.isComputer
                ? (isRpi ? 'raspberry_pi' : 'computer')
                : (p == DeviceProfile.microcontroller ? 'pico' : 'generic'));

        final typeLabel = p.isRobot
            ? (p == DeviceProfile.quadruped ? 'Quadruped Robot' : 'Robot')
            : (p.isComputer
                ? (isRpi ? 'Raspberry Pi' : 'Computer / PC')
                : (p == DeviceProfile.microcontroller ? 'Microcontroller' : 'Generic Device'));

        final icon = p.isRobot
            ? 'quadruped'
            : (p.isComputer ? (isRpi ? 'rpi' : 'computer') : (p == DeviceProfile.microcontroller ? 'pico' : 'generic'));

        final manifestName = conn.manifest!.name;
        final updatedName = (manifestName.isNotEmpty && manifestName != 'Device')
            ? manifestName
            : currentDev.name;

        if (currentDev.profile != profileKey || currentDev.name != updatedName) {
          _devices[devIdx] = DeviceItem(
            id: currentDev.id,
            name: updatedName,
            profile: profileKey,
            deviceType: typeLabel,
            availableTransports: currentDev.availableTransports,
            selectedTransport: currentDev.selectedTransport,
            isPaired: currentDev.isPaired,
            isConnected: currentDev.isConnected,
            ipAddress: currentDev.ipAddress,
            port: currentDev.port,
            macAddress: currentDev.macAddress,
            iconKey: icon,
          );

          // Update persisted registry device type and name as well
          final known = registry.findById(deviceId);
          if (known != null) {
            registry.addOrUpdate(known.copyWith(
              name: updatedName,
              type: profileKey,
            ));
          }

          notifyListeners();
        }
      }
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
      if (e.eventType == 'telemetry' || e.eventType == 'sensor_update') {
        updateTelemetryFromMap(e.deviceId, e.data);
      }
    });
  }

  /// Parses and applies telemetry key-values directly into the device's TelemetryData.
  void updateTelemetryFromMap(String deviceId, Map<String, dynamic> d) {
    // Check if values might be nested inside 'telemetry', 'data', or 'system'
    final map = (d['telemetry'] is Map)
        ? Map<String, dynamic>.from(d['telemetry'] as Map)
        : ((d['data'] is Map)
            ? Map<String, dynamic>.from(d['data'] as Map)
            : ((d['system'] is Map) ? Map<String, dynamic>.from(d['system'] as Map) : d));

    // CPU: cpu, cpu_usage, cpu_percent, cpuUsage, processor, cpu_load
    final rawCpu = map['cpu'] ?? map['cpu_usage'] ?? map['cpu_percent'] ?? map['cpuUsage'] ??
        map['processor'] ?? map['cpu_load'];
    final cpu = (rawCpu as num?)?.toDouble() ?? 0.0;

    // RAM: ram, ram_usage, ram_percent, memory, memory_percent, ramUsage, mem
    final rawRam = map['ram'] ?? map['ram_usage'] ?? map['ram_percent'] ?? map['ramUsage'] ??
        map['memory'] ?? map['memory_percent'] ?? map['mem'];
    final ram = (rawRam as num?)?.toDouble() ?? 0.0;

    // GPU: gpu, gpu_usage, gpu_percent, gpuUsage
    final rawGpu = map['gpu'] ?? map['gpu_usage'] ?? map['gpu_percent'] ?? map['gpuUsage'];
    final gpu = (rawGpu as num?)?.toDouble();

    // Temperature: temp, temperature, cpu_temp, cpu_temperature, thermal, core_temp
    final rawTmp = map['temp'] ?? map['temperature'] ?? map['cpu_temp'] ?? map['cpu_temperature'] ??
        map['thermal'] ?? map['core_temp'];
    final tmp = (rawTmp as num?)?.toDouble() ?? 0.0;

    _telemetryMap[deviceId] = TelemetryData(
      cpuUsage: cpu,
      ramUsage: ram,
      gpuUsage: gpu,
      temperature: tmp,
    );
    notifyListeners();

    if (keepAliveInBackground && showLiveTelemetryInNotification) {
      final now = DateTime.now();
      final lastSync = _lastNotifTelemetrySync[deviceId];
      if (lastSync == null || now.difference(lastSync).inSeconds >= 5) {
        _lastNotifTelemetrySync[deviceId] = now;
        syncKeepAliveNotifications();
      }
    }
  }

  /// Explicitly query the device for telemetry via executeTool fallback if needed
  Future<void> pollTelemetry(String deviceId) async {
    final conn = _connections[deviceId];
    if (conn == null || !conn.isConnected || conn.session == null) return;

    try {
      final res = await conn.session!.executeTool('get_telemetry', {});
      if (res.result is Map) {
        final resultMap = Map<String, dynamic>.from(res.result as Map);
        updateTelemetryFromMap(deviceId, resultMap);
      }
    } catch (_) {
      // In case the tool is named 'system_telemetry' or 'system_status'
      try {
        final res = await conn.session!.executeTool('system_status', {});
        if (res.result is Map) {
          final resultMap = Map<String, dynamic>.from(res.result as Map);
          updateTelemetryFromMap(deviceId, resultMap);
        }
      } catch (_) {}
    }
  }


  Timer? _telemetryTimer;
  Timer? _savedDevicesCheckTimer;

  void _startTelemetryLoop() {
    _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      for (final device in devices) {
        final conn = _connections[device.id];
        // Only synthesize jitter if there is no real hardware session or if running in mock mode
        final isMock = conn?.session?.transport.transportType == 'mock';
        if (isMock) {
          final existing = _telemetryMap[device.id];
          if (existing != null) {
            _telemetryMap[device.id] = existing.copyWith(
              cpuUsage: (existing.cpuUsage + ((timer.tick % 5) - 2) * 0.5).clamp(1.0, 100.0),
              ramUsage: (existing.ramUsage + ((timer.tick % 3) - 1) * 0.3).clamp(1.0, 100.0),
            );
          }
        }
      }
      if (devices.isNotEmpty) {
        notifyListeners();
      }
    });

    // Check reachability for saved devices every 15 seconds
    _savedDevicesCheckTimer?.cancel();
    _savedDevicesCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkSavedDevicesReachability();
    });
    // Trigger initial check promptly
    Future.delayed(const Duration(milliseconds: 500), _checkSavedDevicesReachability);
  }

  /// Probes network reachability for saved devices that are not currently connected
  Future<void> _checkSavedDevicesReachability() async {
    for (final dev in _devices) {
      if (dev.isConnected) continue;
      final ip = dev.ipAddress;
      final port = dev.port;
      if (ip != null && ip.isNotEmpty) {
        discovery.probeHost(ip, port: port);
      }
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _savedDevicesCheckTimer?.cancel();
    for (final t in _reconnectTimeoutTimers.values) {
      t.cancel();
    }
    _reconnectTimeoutTimers.clear();
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
    super.dispose();
  }
}
