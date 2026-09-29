import 'package:flutter/foundation.dart';

import '../core/needle/needle_engine.dart';
import '../core/needle/needle_models.dart';
import '../models/dcp_models.dart';
import 'device_manager.dart';

/// Facade service connecting Needle AI to the Universal Device Control Framework.
class NeedleAiService extends ChangeNotifier {
  static final NeedleAiService _instance = NeedleAiService._internal();
  factory NeedleAiService() => _instance;
  static NeedleAiService get instance => _instance;

  late final NeedleEngine _engine;
  final List<NeedleResponse> _history = [];

  NeedleAiService._internal() {
    _engine = NeedleEngine(
      toolExecutor: (deviceId, toolName, params) =>
          DeviceManager().executeTool(deviceId, toolName, params),
    );
  }

  /// History of recent Needle AI actions and reasoning plans (max 30).
  List<NeedleResponse> get history => List.unmodifiable(_history);

  /// Most recent execution response.
  NeedleResponse? get lastResponse => _history.isNotEmpty ? _history.first : null;

  /// Evaluates capability profile for the specified device.
  NeedleCapability checkCapability(String deviceId) {
    final dev = _findDevice(deviceId);
    final manifest = DeviceManager().getConnection(deviceId)?.manifest;
    return _engine.evaluateCapability(dev, manifest);
  }

  /// Resolves which execution mode will be chosen for a device.
  NeedleExecutionMode resolveExecutionMode(
    String deviceId, {
    NeedleExecutionMode requested = NeedleExecutionMode.auto,
  }) {
    final dev = _findDevice(deviceId);
    final manifest = DeviceManager().getConnection(deviceId)?.manifest;
    return _engine.resolveExecutionMode(dev, manifest, requested: requested);
  }

  /// Generates a preview plan without executing it (useful for live UI previews).
  NeedlePlan previewPlan(String deviceId, String prompt) {
    final tools = DeviceManager().tool.getTools(deviceId);
    return _engine.planClientSide(prompt, tools);
  }

  /// Processes and executes a natural language command using Needle AI.
  Future<NeedleResponse> processCommand({
    required String deviceId,
    required String prompt,
    NeedleExecutionMode mode = NeedleExecutionMode.auto,
  }) async {
    final dev = _findDevice(deviceId);
    final conn = DeviceManager().getConnection(deviceId);
    final manifest = conn?.manifest;
    final tools = DeviceManager().tool.getTools(deviceId);

    final response = await _engine.execute(
      device: dev,
      manifest: manifest,
      tools: tools,
      prompt: prompt,
      mode: mode,
    );

    _history.insert(0, response);
    if (_history.length > 30) {
      _history.removeLast();
    }

    notifyListeners();
    return response;
  }

  /// Clears command history.
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  DeviceItem _findDevice(String deviceId) {
    return DeviceManager().devices.firstWhere(
          (d) => d.id == deviceId,
          orElse: () => DeviceManager().allPairedDevices.firstWhere(
                (d) => d.id == deviceId,
                orElse: () => DeviceItem(
                  id: deviceId,
                  name: 'Target Device',
                  profile: 'generic',
                  deviceType: 'Device',
                  availableTransports: const ['wifi'],
                  selectedTransport: 'wifi',
                  isPaired: false,
                  isConnected: false,
                  iconKey: 'device',
                ),
              ),
        );
  }
}
