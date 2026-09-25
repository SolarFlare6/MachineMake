import 'package:flutter/foundation.dart';
import '../core/models/tool_definition.dart';

/// Caches and resolves tool definitions per connected device.
class ToolManager extends ChangeNotifier {
  static final ToolManager _instance = ToolManager._();
  factory ToolManager() => _instance;
  ToolManager._();

  final Map<String, List<ToolDefinition>> _cache = {};

  List<ToolDefinition> getTools(String deviceId) => _cache[deviceId] ?? [];

  void updateTools(String deviceId, List<ToolDefinition> tools) {
    _cache[deviceId] = tools;
    notifyListeners();
  }

  ToolDefinition? getTool(String deviceId, String toolName) {
    try {
      return _cache[deviceId]?.firstWhere((t) => t.name == toolName);
    } catch (_) {
      return null;
    }
  }

  void clearDevice(String deviceId) {
    _cache.remove(deviceId);
    notifyListeners();
  }
}
