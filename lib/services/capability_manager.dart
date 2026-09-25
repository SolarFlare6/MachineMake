import 'package:flutter/foundation.dart';
import '../core/models/device_capability.dart';

/// Caches and provides device capabilities per connected device.
class CapabilityManager extends ChangeNotifier {
  static final CapabilityManager _instance = CapabilityManager._();
  factory CapabilityManager() => _instance;
  CapabilityManager._();

  final Map<String, List<DeviceCapability>> _cache = {};

  List<DeviceCapability> getCapabilities(String deviceId) =>
      _cache[deviceId] ?? [];

  void updateCapabilities(String deviceId, List<DeviceCapability> caps) {
    _cache[deviceId] = caps;
    notifyListeners();
  }

  bool hasCapability(String deviceId, CapabilityType type) {
    return _cache[deviceId]?.any((c) => c.type == type) ?? false;
  }

  DeviceCapability? getCapability(String deviceId, CapabilityType type) {
    try {
      return _cache[deviceId]?.firstWhere((c) => c.type == type);
    } catch (_) {
      return null;
    }
  }

  void clearDevice(String deviceId) {
    _cache.remove(deviceId);
    notifyListeners();
  }
}
