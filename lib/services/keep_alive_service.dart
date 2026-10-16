import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/models/device_notification_model.dart';
import 'quick_action_dispatcher.dart';

/// Bridges Dart connection state & telemetry to the native Android
/// `ConnectionKeepAliveService` foreground service and handles incoming
/// notification quick action broadcasts.
class KeepAliveService {
  KeepAliveService._();
  static final KeepAliveService instance = KeepAliveService._();

  static const MethodChannel _channel = MethodChannel('machinemake/keepalive');

  /// Allows unit tests on desktop hosts to exercise the MethodChannel.
  @visibleForTesting
  static bool debugForceEnableForTest = false;

  bool _isRunning = false;
  bool _initialized = false;

  final StreamController<String> _openDeviceController =
      StreamController<String>.broadcast();

  /// Emits a `deviceId` whenever the user taps a per-device notification card.
  Stream<String> get openDeviceStream => _openDeviceController.stream;

  bool get isRunning => _isRunning;

  bool get _isSupported =>
      debugForceEnableForTest || (!kIsWeb && Platform.isAndroid);

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onQuickAction':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final deviceId = args['deviceId'] as String? ?? '';
        final action = args['action'] as String? ?? '';
        if (action.isNotEmpty) {
          await QuickActionDispatcher.dispatch(deviceId, action);
        }
        break;
      case 'onOpenDevice':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final deviceId = args['deviceId'] as String? ?? '';
        if (deviceId.isNotEmpty) {
          _openDeviceController.add(deviceId);
        }
        break;
    }
  }

  /// Starts or updates the Android foreground service with the current list of
  /// connected (or reconnecting) devices. Stops the service automatically if
  /// [devices] is empty.
  Future<void> sync(
    List<DeviceNotificationModel> devices, {
    required bool showOnLockScreen,
  }) async {
    if (!_isSupported) return;
    init();

    if (devices.isEmpty) {
      await stop();
      return;
    }

    final mapped = devices.map((d) => d.toMap()).toList();
    final payload = {
      'devices': mapped,
      'devicesJson': jsonEncode(mapped),
      'showOnLockScreen': showOnLockScreen,
    };

    try {
      if (!_isRunning) {
        await _channel.invokeMethod('start', payload);
        _isRunning = true;
      } else {
        await _channel.invokeMethod('updateDevices', payload);
      }
    } on MissingPluginException {
      // Safe fallback if native channel is unavailable
    } on PlatformException {
      // Safe fallback
    }
  }

  /// Stops the foreground service and dismisses all ongoing notifications.
  Future<void> stop() async {
    if (!_isSupported) return;
    if (!_isRunning) return;
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      // Ignore
    } on PlatformException {
      // Ignore
    } finally {
      _isRunning = false;
    }
  }

  /// Checks whether the app is currently exempt from Android Doze / App Standby
  /// battery optimizations.
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isSupported) return true;
    try {
      final res =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the Android system dialog requesting `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
  Future<void> requestBatteryExemption() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod('requestBatteryExemption');
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    _isRunning = false;
  }
}
