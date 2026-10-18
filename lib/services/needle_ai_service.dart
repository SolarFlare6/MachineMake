import 'package:flutter/foundation.dart';

import '../core/needle/hybrid_needle_router.dart';
import '../core/needle/needle_engine.dart';
import '../core/needle/needle_models.dart';
import '../models/dcp_models.dart';
import 'device_manager.dart';
import 'llm_model_manager.dart';

/// Facade service connecting Needle AI (Hybrid Rules + Local LLM + On-Device)
/// to the Universal Device Control Framework.
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

  NeedleEngine get engine => _engine;

  /// History of recent Needle AI actions and reasoning plans (max 30).
  List<NeedleResponse> get history => List.unmodifiable(_history);

  /// Most recent execution response.
  NeedleResponse? get lastResponse =>
      _history.isNotEmpty ? _history.first : null;

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

  /// Generates a synchronous preview plan (Stage 0 Target Resolution + Stage 1 Fast Rules)
  /// without executing it (useful for live UI previews in the Voice Command dialog).
  HybridRoutingResult previewHybridRouting(String deviceId, String prompt) {
    final dev = _findDevice(deviceId);
    final connected = DeviceManager().devices.isNotEmpty
        ? DeviceManager().devices
        : [dev];
    return _engine.router.planSync(
      prompt: prompt,
      defaultDevice: dev,
      connectedDevices: connected,
      toolsProvider: (id) => DeviceManager().tool.getTools(id),
    );
  }

  /// Generates a preview plan without executing it.
  NeedlePlan previewPlan(String deviceId, String prompt) {
    return previewHybridRouting(deviceId, prompt).plan;
  }

  /// Processes and executes a natural language command using the Hybrid Needle AI pipeline.
  Future<NeedleResponse> processCommand({
    required String deviceId,
    required String prompt,
    NeedleExecutionMode mode = NeedleExecutionMode.auto,
    bool allowDestructive = false,
  }) async {
    final dev = _findDevice(deviceId);
    final conn = DeviceManager().getConnection(deviceId);
    final manifest = conn?.manifest;
    final tools = DeviceManager().tool.getTools(deviceId);
    final connected = DeviceManager().devices.isNotEmpty
        ? DeviceManager().devices
        : [dev];

    final response = await _engine.execute(
      device: dev,
      manifest: manifest,
      tools: tools,
      prompt: prompt,
      connectedDevices: connected,
      toolsProvider: (id) => DeviceManager().tool.getTools(id),
      mode: mode,
      allowDestructive: allowDestructive,
    );

    _history.insert(0, response);
    if (_history.length > 30) {
      _history.removeLast();
    }

    notifyListeners();
    return response;
  }

  /// Runs a non-executing diagnostic self-test of the hybrid planner (used by Settings UI).
  Future<String> runDiagnosticTest({String? customPrompt}) async {
    final sw = Stopwatch()..start();

    final manager = LlmModelManager.instance;
    if (manager.isInstalled && manager.isEnabled && !manager.runtime.isLoaded) {
      await manager.ensureLoadedInRam();
    }

    final testPrompt = customPrompt ??
        (manager.isReadyForInference
            ? 'On the connected PC please type hello and press enter'
            : 'On the connected PC press enter');

    final mockPc = DeviceItem(
      id: 'pc-test',
      name: 'Desktop PC',
      profile: 'pc',
      deviceType: 'Desktop PC',
      availableTransports: const ['wifi'],
      selectedTransport: 'wifi',
      isPaired: true,
      isConnected: true,
      iconKey: 'laptop',
    );
    final mockRobot = DeviceItem(
      id: 'robot-test',
      name: 'Quadruped Robot',
      profile: 'quadruped',
      deviceType: 'Quadruped Robot',
      availableTransports: const ['wifi'],
      selectedTransport: 'wifi',
      isPaired: true,
      isConnected: true,
      iconKey: 'quadruped',
    );

    final connected = DeviceManager().devices.isNotEmpty
        ? DeviceManager().devices
        : [mockPc, mockRobot];

    final routing = await _engine.router.routeAndPlan(
      prompt: testPrompt,
      defaultDevice: connected.first,
      connectedDevices: connected,
      toolsProvider: (id) => DeviceManager().tool.getTools(id),
    );
    sw.stop();

    final plan = routing.plan;
    final String llmStatus;
    if (manager.runtime.isLoaded) {
      llmStatus = 'SmolLM2-360M Loaded in RAM';
    } else if (manager.isInstalled && manager.errorMessage != null) {
      llmStatus = 'Fallback to Fast Rules (${manager.errorMessage})';
    } else if (manager.isInstalled) {
      llmStatus = 'SmolLM2-360M Installed on Disk';
    } else {
      llmStatus = 'Rules Only (LLM not installed)';
    }

    final toolSummary = plan.steps.length > 1
        ? plan.steps.map((s) => '${s.toolName}(${s.parameters})').join(' → ')
        : '${plan.toolName}(${plan.parameters})';

    if (plan.toolName.isNotEmpty) {
      return 'Prompt: "$testPrompt"\n'
          'Target: ${routing.targetResolution.targetDevice.name}\n'
          'Engine: ${plan.source.badgeLabel}\n'
          'LLM Status: $llmStatus\n'
          'Tool Call: $toolSummary\n'
          'Latency: ${sw.elapsedMilliseconds} ms';
    } else {
      return 'Prompt: "$testPrompt"\n'
          'LLM Status: $llmStatus\n'
          'Result: No tool matched (${sw.elapsedMilliseconds} ms)';
    }
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
