import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralised runtime permission management for MachineMake.
///
/// Call [requestDiscoveryPermissions] before starting any scan,
/// and [requestCameraPermission] before opening the QR scanner.
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  // ── Discovery (BLE + Location) ─────────────────────────────────────────

  /// Returns true if all permissions needed for Bluetooth and mDNS discovery
  /// are already granted; false otherwise (does NOT prompt).
  Future<bool> discoveryPermissionsGranted() async {
    if (!defaultTargetPlatform.isAndroid) return true; // iOS handles at Info.plist level
    final statuses = await _discoveryPermissions.map((p) => p.isGranted).wait;
    return statuses.every((g) => g);
  }

  /// Requests all discovery permissions and returns true if all are granted.
  Future<bool> requestDiscoveryPermissions() async {
    if (!defaultTargetPlatform.isAndroid) return true;

    final statuses = await _discoveryPermissions.request();
    return statuses.values.every(
      (s) => s == PermissionStatus.granted || s == PermissionStatus.limited,
    );
  }

  // ── Camera (QR scanner) ────────────────────────────────────────────────

  Future<bool> cameraPermissionGranted() async {
    return (await Permission.camera.isGranted);
  }

  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status == PermissionStatus.granted;
  }

  // ── Notifications (Android 13+ POST_NOTIFICATIONS) ──────────────────────

  Future<bool> notificationPermissionGranted() async {
    if (!defaultTargetPlatform.isAndroid) return true;
    return (await Permission.notification.isGranted);
  }

  Future<bool> requestNotificationPermission() async {
    if (!defaultTargetPlatform.isAndroid) return true;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static List<Permission> get _discoveryPermissions => [
        // Bluetooth — Android 12+ (API 31+)
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        // Location — required for BLE on Android ≤ 11; harmless on 12+
        Permission.locationWhenInUse,
      ];
}

extension on TargetPlatform {
  bool get isAndroid => this == TargetPlatform.android;
}
