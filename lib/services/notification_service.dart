import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Models an in-app visual notification banner
class InAppNotification {
  final String title;
  final String message;
  final String? deviceId;
  final String type; // 'disconnected', 'connected', 'alert', 'info'
  final DateTime timestamp;

  InAppNotification({
    required this.title,
    required this.message,
    this.deviceId,
    this.type = 'info',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Service managing system push notifications and in-app alert streams.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<InAppNotification> _inAppController =
      StreamController<InAppNotification>.broadcast();

  Stream<InAppNotification> get inAppNotifications => _inAppController.stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static const String _statusChannelId = 'device_status_channel';
  static const String _statusChannelName = 'Device Connection Status';
  static const String _statusChannelDesc =
      'Alerts when devices connect or disconnect unexpectedly';

  static const String _alertChannelId = 'device_alerts_channel';
  static const String _alertChannelName = 'Device Safety & Alerts';
  static const String _alertChannelDesc =
      'Safety stops, battery warnings, and critical hardware notices';

  /// Initializes the local notifications plugin for Android, iOS and desktop.
  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Can navigate or handle click if payload provided
          if (kDebugMode) {
            print('[NotificationService] Clicked payload: ${response.payload}');
          }
        },
      );

      // Create Android Notification Channels
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _statusChannelId,
            _statusChannelName,
            description: _statusChannelDesc,
            importance: Importance.high,
            enableVibration: true,
          ),
        );

        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _alertChannelId,
            _alertChannelName,
            description: _alertChannelDesc,
            importance: Importance.max,
            enableVibration: true,
          ),
        );
      }

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('[NotificationService] Init error: $e');
      }
    }
  }

  /// Checks if notification permission is currently granted.
  Future<bool> hasPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return await Permission.notification.isGranted;
    }
    return true;
  }

  /// Requests notification permissions from the OS.
  Future<bool> requestPermission() async {
    // Try requesting via Android implementation first for Android 13+
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted =
          await androidPlugin.requestNotificationsPermission() ?? false;
      if (granted) return true;
    }

    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Displays a system notification and emits an in-app notification event.
  Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
    String channelId = _statusChannelId,
    String channelName = _statusChannelName,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
    String type = 'info',
  }) async {
    // Emit in-app banner for active screens
    _inAppController.add(InAppNotification(
      title: title,
      message: body,
      deviceId: payload,
      type: type,
    ));

    if (!_isInitialized) {
      await init();
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: importance,
      priority: priority,
      icon: '@mipmap/ic_launcher',
      showWhen: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        print('[NotificationService] showNotification error: $e');
      }
    }
  }

  /// Triggers a notification when a device unexpectedly disconnects.
  Future<void> showDeviceDisconnectedNotification({
    required String deviceName,
    String? deviceId,
  }) async {
    final title = 'Device Disconnected';
    final body =
        '$deviceName lost connection. Check device power and wireless link.';

    await showNotification(
      id: (deviceId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
          0x7FFFFFFF,
      title: title,
      body: body,
      payload: deviceId,
      channelId: _statusChannelId,
      channelName: _statusChannelName,
      importance: Importance.high,
      priority: Priority.high,
      type: 'disconnected',
    );
  }

  /// Triggers a notification when a device connects.
  Future<void> showDeviceConnectedNotification({
    required String deviceName,
    String? deviceId,
  }) async {
    final title = 'Device Connected';
    final body = '$deviceName is now connected and operational.';

    await showNotification(
      id: (deviceId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
          0x7FFFFFFF,
      title: title,
      body: body,
      payload: deviceId,
      channelId: _statusChannelId,
      channelName: _statusChannelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      type: 'connected',
    );
  }

  /// Triggers a high-priority safety alert notification (e.g. emergency stop, motor overload).
  Future<void> showSafetyAlertNotification({
    required String deviceName,
    required String alertMessage,
    String? deviceId,
  }) async {
    final title = '⚠️ $deviceName Safety Alert';

    await showNotification(
      id: ((deviceId?.hashCode ?? 100) + 1) & 0x7FFFFFFF,
      title: title,
      body: alertMessage,
      payload: deviceId,
      channelId: _alertChannelId,
      channelName: _alertChannelName,
      importance: Importance.max,
      priority: Priority.max,
      type: 'alert',
    );
  }

  void dispose() {
    _inAppController.close();
  }
}
