import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../theme/app_theme.dart';
import 'device_manager.dart';
import 'device_registry.dart';
import 'notification_service.dart';

/// Runs once at app startup and wires up the auto-enable BT/Wi-Fi settings.
///
/// Called from [main()] before [runApp()].  Safe to call multiple times (idempotent).
class AppStartupService {
  AppStartupService._();

  static bool _hasRun = false;

  // ── SharedPreferences keys ────────────────────────────────────────────────
  static const String _keyAlertOnDisconnect    = 'setting_alert_disconnect';
  static const String _keyAutoEnableBT         = 'setting_auto_enable_bt';
  static const String _keyAutoEnableWifi       = 'setting_auto_enable_wifi';
  static const String _keyFirstSetupDone       = 'first_setup_done';
  static const String _keyClientId             = 'dcp_client_id';

  /// Whether the user has completed initial setup/onboarding.
  static bool isFirstSetupDone = false;

  /// Stable unique client ID for DCP authentication.
  static String clientId = '';

  /// Loads persisted settings into [DeviceManager] then honours the auto-enable
  /// flags.  Must be awaited from `main()`.
  static Future<void> run() async {
    if (_hasRun) return;
    _hasRun = true;

    final prefs = await SharedPreferences.getInstance();
    final dm    = DeviceManager();

    // ── Restore or generate stable client ID ──────────────────────────────
    clientId = prefs.getString(_keyClientId) ?? '';
    if (clientId.isEmpty) {
      clientId = const Uuid().v4();
      await prefs.setString(_keyClientId, clientId);
    }

    // ── Restore saved device registry ─────────────────────────────────────
    await DeviceRegistry().load();
    dm.initFromStartup(clientId: clientId);

    // ── Initialize Notifications & Theme ─────────────────────────────────
    await NotificationService.instance.init();
    await AppTheme.init();

    // ── Restore setup state ───────────────────────────────────────────────
    isFirstSetupDone = prefs.getBool(_keyFirstSetupDone) ?? false;

    // ── Restore persisted settings ────────────────────────────────────────
    dm.alertOnDisconnect    = prefs.getBool(_keyAlertOnDisconnect) ?? true;
    dm.autoEnableBTOnStart  = prefs.getBool(_keyAutoEnableBT)      ?? true;
    dm.autoEnableWifiOnStart = prefs.getBool(_keyAutoEnableWifi)   ?? true;

    // ── Auto-enable Bluetooth ─────────────────────────────────────────────
    if (dm.autoEnableBTOnStart && Platform.isAndroid) {
      await _tryEnableBluetooth();
    }

    // ── Auto-enable Wi-Fi ─────────────────────────────────────────────────
    // Android 10+ (API 29+) forbids apps from enabling Wi-Fi directly.
    // We open the Wi-Fi system panel so the user can toggle it with one tap.
    if (dm.autoEnableWifiOnStart && Platform.isAndroid) {
      await _tryEnableWifi();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> _tryEnableBluetooth() async {
    try {
      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));

      if (state != BluetoothAdapterState.on) {
        // FlutterBluePlus.turnOn() is Android-only and requests BT enable.
        await FlutterBluePlus.turnOn();
      }
    } on TimeoutException {
      // ignore — adapter state unavailable
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[AppStartupService] BT enable failed: $e');
    } catch (e) {
      // ignore: avoid_print
      print('[AppStartupService] BT enable error: $e');
    }
  }

  static Future<void> _tryEnableWifi() async {
    // On Android 10+ apps cannot programmatically enable Wi-Fi.
    // We use the Settings.ACTION_WIFI_SETTINGS intent to open the Wi-Fi panel
    // so the user can enable it with a single tap.
    try {
      const channel = MethodChannel('com.machinemake/wifi');
      await channel.invokeMethod<void>('openWifiSettings');
    } on MissingPluginException {
      // Channel not registered on this version — ignore silently.
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[AppStartupService] Wi-Fi settings open failed: $e');
    }
  }

  // ── Persistence helpers called by DeviceManager ───────────────────────────

  static Future<void> saveSettings({
    required bool alertOnDisconnect,
    required bool autoEnableBT,
    required bool autoEnableWifi,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAlertOnDisconnect, alertOnDisconnect);
    await prefs.setBool(_keyAutoEnableBT,      autoEnableBT);
    await prefs.setBool(_keyAutoEnableWifi,    autoEnableWifi);
  }

  /// Sets whether the first-time setup has completed and persists it.
  static Future<void> setFirstSetupDone(bool done) async {
    isFirstSetupDone = done;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFirstSetupDone, done);
  }

  /// Clears all stored app data, paired devices, and resets to initial state.
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    isFirstSetupDone = false;
    clientId = const Uuid().v4();
    await prefs.setString(_keyClientId, clientId);
    DeviceManager().clearAllDevices();
  }
}
