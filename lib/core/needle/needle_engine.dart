import '../dcp/dcp_message.dart';
import '../models/device_manifest.dart';
import '../models/tool_definition.dart';
import '../../models/dcp_models.dart';
import '../../services/llm_model_manager.dart';
import 'hybrid_needle_router.dart';
import 'needle_models.dart';
import 'plan_validator.dart';

/// Callback type for executing a tool through the transport/session layer.
typedef ToolExecutor = Future<DcpExecuteResponse> Function(
  String deviceId,
  String toolName,
  Map<String, dynamic> params,
);

/// The Needle AI Core Engine.
///
/// Implements the 4-stage Hybrid AI architecture:
/// - **Stage 0**: Speech-to-text normalization & natural-language target device resolution
///   (e.g. *"On the connected PC press enter"* -> resolves PC & strips prefix).
/// - **Stage 1**: Fast Deterministic & Fuzzy Rules (`0 MB`, `< 1 ms`) for PC, Robot, and Pico/MCU.
/// - **Stage 2**: Downloadable On-Device Local LLM (`SmolLM2-360M-Instruct` via `llama_flutter_android`)
///   when Stage 1 confidence `< 0.85` or for complex phrasing / multi-step chains.
/// - **Stage 3**: Device-hosted `needle_prompt` / `ai_prompt` fallback when connected to a capable server.
/// - **Stage 4**: Helpful closest-tool suggestions & non-intrusive hint if the local model is not installed.
class NeedleEngine {
  final ToolExecutor _toolExecutor;
  final HybridNeedleRouter _router;

  NeedleEngine({
    required ToolExecutor toolExecutor,
    HybridNeedleRouter? router,
  })  : _toolExecutor = toolExecutor,
        _router = router ?? HybridNeedleRouter();

  HybridNeedleRouter get router => _router;

  /// Evaluates whether a device is capable of running Needle AI on-device or locally.
  NeedleCapability evaluateCapability(
    DeviceItem device,
    DeviceManifest? manifest,
  ) {
    return NeedleCapability.fromManifest(manifest, device);
  }

  /// Resolves the effective execution mode (device vs. client) based on device capability
  /// and any user preference.
  NeedleExecutionMode resolveExecutionMode(
    DeviceItem device,
    DeviceManifest? manifest, {
    NeedleExecutionMode requested = NeedleExecutionMode.auto,
  }) {
    final cap = evaluateCapability(device, manifest);

    if (requested == NeedleExecutionMode.device) {
      if (cap.supported) return NeedleExecutionMode.device;
      return NeedleExecutionMode.client;
    }

    if (requested == NeedleExecutionMode.client) {
      return NeedleExecutionMode.client;
    }

    if (cap.supported && cap.preferred == NeedleExecutionMode.device) {
      return NeedleExecutionMode.device;
    }
    return NeedleExecutionMode.client;
  }

  /// Synchronous Stage 0 + Stage 1 preview plan (used for live UI previews and unit tests).
  NeedlePlan planClientSide(
    String prompt,
    List<ToolDefinition> availableTools, {
    DeviceItem? targetDevice,
    List<DeviceItem>? connectedDevices,
  }) {
    final defaultDev = targetDevice ??
        DeviceItem(
          id: 'default',
          name: 'Device',
          profile: 'generic',
          deviceType: 'Device',
          availableTransports: const ['wifi'],
          selectedTransport: 'wifi',
          isPaired: true,
          isConnected: true,
          iconKey: 'device',
        );

    final routing = _router.planSync(
      prompt: prompt,
      defaultDevice: defaultDev,
      connectedDevices: connectedDevices ?? [defaultDev],
      toolsProvider: (_) => availableTools,
    );
    return routing.plan;
  }

  /// Executes a natural language command through the Hybrid Needle AI pipeline.
  Future<NeedleResponse> execute({
    required DeviceItem device,
    required DeviceManifest? manifest,
    required List<ToolDefinition> tools,
    required String prompt,
    List<DeviceItem>? connectedDevices,
    List<ToolDefinition> Function(String deviceId)? toolsProvider,
    NeedleExecutionMode mode = NeedleExecutionMode.auto,
    bool allowDestructive = false,
  }) async {
    final allConnected =
        connectedDevices != null && connectedDevices.isNotEmpty
            ? connectedDevices
            : [device];
    final getToolsFor = toolsProvider ?? ((_) => tools);

    // Run Hybrid Router (Stage 0 -> Stage 1 Fast Rules -> Stage 2 Local LLM)
    final routing = await _router.routeAndPlan(
      prompt: prompt,
      defaultDevice: device,
      connectedDevices: allConnected,
      toolsProvider: getToolsFor,
    );

    final resolvedDevice = routing.targetResolution.targetDevice;
    final resolvedTools = getToolsFor(resolvedDevice.id);
    final plan = routing.plan;

    // If user explicitly forced on-device execution AND Stage 1 didn't match a direct tool,
    // or if Stage 1 + Stage 2 both failed to produce a valid plan, try Stage 3 (Device Server needle_prompt).
    if (plan.toolName.isEmpty || plan.confidence < 0.3) {
      final hasDevicePromptTool = resolvedTools
          .any((t) => t.name == 'needle_prompt' || t.name == 'ai_prompt');
      if (hasDevicePromptTool) {
        return await _executeOnDeviceServer(
          resolvedDevice,
          resolvedTools,
          prompt,
          routing.normalizedActionPrompt,
        );
      }

      final llmInstalled = LlmModelManager.instance.isInstalled;
      final hintSuffix = !llmInstalled
          ? ' (Tip: Download the offline AI model in Settings for complex phrasing)'
          : '';
      final examplesText = routing.suggestions.isNotEmpty
          ? ' Try ${routing.suggestions.join(", ")}.'
          : '';

      return NeedleResponse(
        success: false,
        userPrompt: prompt,
        executedWhere: NeedleExecutionMode.client,
        plan: plan,
        message: 'Unrecognized command.$examplesText$hintSuffix',
        suggestions: routing.suggestions,
      );
    }

    // Safety check for destructive commands (`shutdown`, `reboot`, `sleep`)
    if (plan.requiresConfirmation && !allowDestructive) {
      return NeedleResponse(
        success: false,
        userPrompt: prompt,
        executedWhere: NeedleExecutionMode.client,
        plan: plan,
        message:
            'Confirmation required before executing "${plan.toolName}" on ${resolvedDevice.name}.',
        error: 'CONFIRMATION_REQUIRED',
      );
    }

    // Dispatch single-step or multi-step plan to the resolved target device
    return await _dispatchPlanSteps(
      targetDevice: resolvedDevice,
      userPrompt: prompt,
      plan: plan,
    );
  }

  /// Dispatches a single-step or multi-step [NeedlePlan] sequentially via [_toolExecutor].
  Future<NeedleResponse> _dispatchPlanSteps({
    required DeviceItem targetDevice,
    required String userPrompt,
    required NeedlePlan plan,
  }) async {
    final stepsToRun = plan.steps.isNotEmpty ? plan.steps : [plan];
    final results = <dynamic>[];

    try {
      for (int i = 0; i < stepsToRun.length; i++) {
        final step = stepsToRun[i];
        final resp = await _toolExecutor(
          targetDevice.id,
          step.toolName,
          step.parameters,
        );

        results.add(resp.result);
        if (!resp.success) {
          return NeedleResponse(
            success: false,
            userPrompt: userPrompt,
            executedWhere: NeedleExecutionMode.client,
            plan: plan,
            message: resp.error ??
                'Step ${i + 1} (${step.toolName}) rejected by ${targetDevice.name}',
            error: resp.error,
            result: resp.result,
          );
        }

        // Small pause between chained steps so hardware/OS can process each call cleanly
        if (i < stepsToRun.length - 1) {
          await Future.delayed(const Duration(milliseconds: 220));
        }
      }

      final toolSummary = stepsToRun.map((s) => s.toolName).join(' → ');
      return NeedleResponse(
        success: true,
        userPrompt: userPrompt,
        executedWhere: NeedleExecutionMode.client,
        plan: plan,
        message: '${plan.explanation} ($toolSummary)',
        result: results.length == 1 ? results.first : results,
      );
    } catch (e) {
      return NeedleResponse(
        success: false,
        userPrompt: userPrompt,
        executedWhere: NeedleExecutionMode.client,
        plan: plan,
        message: 'Execution error on ${targetDevice.name}: $e',
        error: e.toString(),
      );
    }
  }

  /// Stage 3 Fallback: Sends the prompt to the connected device server's `needle_prompt` or `ai_prompt` tool.
  Future<NeedleResponse> _executeOnDeviceServer(
    DeviceItem device,
    List<ToolDefinition> tools,
    String originalPrompt,
    String cleanedPrompt,
  ) async {
    final toolName =
        tools.any((t) => t.name == 'needle_prompt') ? 'needle_prompt' : 'ai_prompt';

    try {
      final response = await _toolExecutor(
        device.id,
        toolName,
        {'prompt': cleanedPrompt},
      );
      if (response.success) {
        String msg = 'Needle AI processed command on ${device.name}';
        if (response.result is Map && response.result['message'] != null) {
          msg = response.result['message'].toString();
        } else if (response.result is Map && response.result['output'] != null) {
          msg = response.result['output'].toString();
        }
        return NeedleResponse(
          success: true,
          userPrompt: originalPrompt,
          executedWhere: NeedleExecutionMode.device,
          plan: NeedlePlan(
            toolName: toolName,
            parameters: {'prompt': cleanedPrompt},
            explanation: msg,
            confidence: 1.0,
            thoughts: const [
              'Stage 3: Dispatched prompt to device-side Needle AI engine',
            ],
            source: NeedlePlanSource.device,
            targetDeviceId: device.id,
            targetDeviceName: device.name,
          ),
          message: msg,
          result: response.result,
        );
      } else {
        final suggestions = PlanValidator.suggestExamples(
          tools,
          deviceProfile: '${device.profile} ${device.deviceType}',
        );
        return NeedleResponse(
          success: false,
          userPrompt: originalPrompt,
          executedWhere: NeedleExecutionMode.device,
          message: response.error ?? 'Device could not understand command.',
          error: response.error,
          suggestions: suggestions,
        );
      }
    } catch (e) {
      return NeedleResponse(
        success: false,
        userPrompt: originalPrompt,
        executedWhere: NeedleExecutionMode.device,
        message: 'On-device Needle AI error: $e',
        error: e.toString(),
      );
    }
  }
}
