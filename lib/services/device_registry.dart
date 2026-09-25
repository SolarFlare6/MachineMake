import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/known_device.dart';

/// Persists and manages known (paired and trusted) devices across app restarts.
class DeviceRegistry extends ChangeNotifier {
  static final DeviceRegistry _instance = DeviceRegistry._();
  factory DeviceRegistry() => _instance;
  DeviceRegistry._();

  static const String _storageKey = 'udcf_known_devices';

  final List<KnownDevice> _devices = [];
  bool _isLoaded = false;

  List<KnownDevice> get devices => List.unmodifiable(_devices);
  bool get isLoaded => _isLoaded;

  /// Loads trusted devices from SharedPreferences.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];
      _devices.clear();
      for (final raw in rawList) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          _devices.add(KnownDevice.fromJson(json));
        } catch (_) {}
      }
      _isLoaded = true;
      notifyListeners();
    } catch (_) {}
  }

  /// Saves the current list to SharedPreferences.
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = _devices.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_storageKey, rawList);
    } catch (_) {}
  }

  Future<void> addOrUpdate(KnownDevice device) async {
    final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (idx >= 0) {
      _devices[idx] = device;
    } else {
      _devices.add(device);
    }
    notifyListeners();
    await save();
  }

  Future<void> removeDevice(String deviceId) async {
    _devices.removeWhere((d) => d.deviceId == deviceId);
    notifyListeners();
    await save();
  }

  KnownDevice? findById(String deviceId) {
    try {
      return _devices.firstWhere((d) => d.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  KnownDevice? findByIp(String ip) {
    try {
      return _devices.firstWhere((d) => d.lastIp == ip);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateLastSeen(String deviceId) async {
    final dev = findById(deviceId);
    if (dev != null) {
      dev.lastSeenAt = DateTime.now();
      notifyListeners();
      await save();
    }
  }
}
