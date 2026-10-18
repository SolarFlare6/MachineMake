import '../models/device_capability.dart';
import '../models/device_manifest.dart';
import '../../models/dcp_models.dart';

/// Where Needle AI executes reasoning and plan synthesis.
enum NeedleExecutionMode {
  /// Executed directly on the target hardware (Raspberry Pi, PC, Laptop, Jetson).
  device,

  /// Executed locally inside the Flutter app (for microcontrollers like ESP32, Pico, Arduino).
  client,

  /// Automatically determined based on device capabilities and hardware constraints.
  auto,
}

extension NeedleExecutionModeExt on NeedleExecutionMode {
  String get label {
    switch (this) {
      case NeedleExecutionMode.device:
        return 'On-Device AI';
      case NeedleExecutionMode.client:
        return 'Local App AI';
      case NeedleExecutionMode.auto:
        return 'Auto';
    }
  }

  String get shortTag {
    switch (this) {
      case NeedleExecutionMode.device:
        return 'Device';
      case NeedleExecutionMode.client:
        return 'Local App';
      case NeedleExecutionMode.auto:
        return 'Auto';
    }
  }
}

/// Represents the Needle AI capability profile for a device.
class NeedleCapability {
  final bool supported;
  final List<NeedleExecutionMode> executionModes;
  final NeedleExecutionMode preferred;
  final String reason;

  const NeedleCapability({
    required this.supported,
    required this.executionModes,
    required this.preferred,
    required this.reason,
  });

  /// Evaluates Needle AI capability from the device manifest, profile, and hardware type.
  factory NeedleCapability.fromManifest(
    DeviceManifest? manifest,
    DeviceItem? device,
  ) {
    // 1. Explicit AI manifest metadata from device handshake
    if (manifest?.metadata['ai'] != null) {
      final aiMeta = manifest!.metadata['ai'];
      if (aiMeta is Map) {
        final needleMeta = aiMeta['needle'];
        if (needleMeta is Map) {
          final isSupported = needleMeta['supported'] == true;
          final rawExec = (needleMeta['execution'] as List<dynamic>?)
                  ?.map((e) => e.toString().toLowerCase())
                  .toList() ??
              [];
          final rawPreferred = needleMeta['preferred']?.toString().toLowerCase();

          final modes = <NeedleExecutionMode>[];
          if (rawExec.contains('device')) modes.add(NeedleExecutionMode.device);
          if (rawExec.contains('client')) modes.add(NeedleExecutionMode.client);
          if (modes.isEmpty) {
            modes.add(isSupported ? NeedleExecutionMode.device : NeedleExecutionMode.client);
          }

          final preferredMode = rawPreferred == 'device' && isSupported
              ? NeedleExecutionMode.device
              : NeedleExecutionMode.client;

          return NeedleCapability(
            supported: isSupported,
            executionModes: modes,
            preferred: preferredMode,
            reason: isSupported
                ? 'Device explicitly advertises native Needle AI support'
                : 'Device explicitly requested client-side Needle AI execution',
          );
        }
      }
    }

    // 2. Hardware profile & type heuristics
    final profile = (device?.profile ?? manifest?.type ?? '').toLowerCase();
    final type = (manifest?.type ?? device?.deviceType ?? '').toLowerCase();

    final isMicrocontroller = profile == 'microcontroller' ||
        profile == 'pico' ||
        profile == 'esp32' ||
        profile == 'arduino' ||
        type.contains('pico') ||
        type.contains('esp32') ||
        type.contains('arduino') ||
        type.contains('microcontroller');

    if (isMicrocontroller) {
      return const NeedleCapability(
        supported: false,
        executionModes: [NeedleExecutionMode.client],
        preferred: NeedleExecutionMode.client,
        reason: 'Microcontroller hardware has limited compute/RAM; running Needle locally in-app',
      );
    }

    // 3. Check if device has an explicit on-device needle tool or AI inference capability
    final hasAiCap = manifest?.capabilities.any((c) => c.type == CapabilityType.aiInference) ?? false;
    final hasNeedleTool = manifest?.tools.any((t) => t.name == 'needle_prompt' || t.name == 'ai_prompt') ?? false;

    if (hasNeedleTool || hasAiCap) {
      return const NeedleCapability(
        supported: true,
        executionModes: [NeedleExecutionMode.device, NeedleExecutionMode.client],
        preferred: NeedleExecutionMode.device,
        reason: 'Device hosts an active AI inference endpoint and Needle tool',
      );
    }

    // 4. Capable SBCs / PCs / Robots: support device if available, otherwise client
    final isSbcOrPc = profile == 'computer' ||
        profile == 'quadruped' ||
        profile == 'robot' ||
        type.contains('raspberry') ||
        type.contains('pc') ||
        type.contains('laptop') ||
        type.contains('robot');

    if (isSbcOrPc) {
      return const NeedleCapability(
        supported: true,
        executionModes: [NeedleExecutionMode.device, NeedleExecutionMode.client],
        preferred: NeedleExecutionMode.device,
        reason: 'High-capability device capable of on-device AI reasoning',
      );
    }

    // Default fallback: Local client execution
    return const NeedleCapability(
      supported: false,
      executionModes: [NeedleExecutionMode.client],
      preferred: NeedleExecutionMode.client,
      reason: 'Standard device; running Needle locally inside app',
    );
  }

  Map<String, dynamic> toJson() => {
        'supported': supported,
        'execution_modes': executionModes.map((e) => e.name).toList(),
        'preferred': preferred.name,
        'reason': reason,
      };
}

/// Which engine synthesized a NeedlePlan.
enum NeedlePlanSource {
  /// Built-in deterministic rule & fuzzy intent matcher (<1 ms, 0 MB).
  rules,

  /// On-phone SmolLM2-360M-Instruct local LLM.
  localLlm,

  /// Remote device-hosted `needle_prompt` tool.
  device,
}

extension NeedlePlanSourceExt on NeedlePlanSource {
  String get label {
    switch (this) {
      case NeedlePlanSource.rules:
        return 'Fast Rules';
      case NeedlePlanSource.localLlm:
        return 'Local LLM (SmolLM2)';
      case NeedlePlanSource.device:
        return 'On-Device AI';
    }
  }

  String get badgeLabel => label;

  String get badgePrefix {
    switch (this) {
      case NeedlePlanSource.rules:
        return '[Fast Rules]';
      case NeedlePlanSource.localLlm:
        return '[Local LLM]';
      case NeedlePlanSource.device:
        return '[On-Device AI]';
    }
  }
}

/// Structured plan produced by Needle AI natural language reasoning.
class NeedlePlan {
  final String toolName;
  final Map<String, dynamic> parameters;
  final String explanation;
  final double confidence;
  final List<String> thoughts;
  final NeedlePlanSource source;
  final bool requiresConfirmation;
  final List<NeedlePlan> steps;
  final String? targetDeviceId;
  final String? targetDeviceName;

  const NeedlePlan({
    required this.toolName,
    required this.parameters,
    required this.explanation,
    this.confidence = 1.0,
    this.thoughts = const [],
    this.source = NeedlePlanSource.rules,
    this.requiresConfirmation = false,
    this.steps = const [],
    this.targetDeviceId,
    this.targetDeviceName,
  });

  NeedlePlan copyWith({
    String? toolName,
    Map<String, dynamic>? parameters,
    String? explanation,
    double? confidence,
    List<String>? thoughts,
    NeedlePlanSource? source,
    bool? requiresConfirmation,
    List<NeedlePlan>? steps,
    String? targetDeviceId,
    String? targetDeviceName,
  }) {
    return NeedlePlan(
      toolName: toolName ?? this.toolName,
      parameters: parameters ?? this.parameters,
      explanation: explanation ?? this.explanation,
      confidence: confidence ?? this.confidence,
      thoughts: thoughts ?? this.thoughts,
      source: source ?? this.source,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      steps: steps ?? this.steps,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      targetDeviceName: targetDeviceName ?? this.targetDeviceName,
    );
  }

  Map<String, dynamic> toJson() => {
        'tool_name': toolName,
        'parameters': parameters,
        'explanation': explanation,
        'confidence': confidence,
        'thoughts': thoughts,
        'source': source.name,
        'requires_confirmation': requiresConfirmation,
        if (steps.isNotEmpty) 'steps': steps.map((s) => s.toJson()).toList(),
        if (targetDeviceId != null) 'target_device_id': targetDeviceId,
        if (targetDeviceName != null) 'target_device_name': targetDeviceName,
      };

  @override
  String toString() =>
      'NeedlePlan(tool: $toolName, params: $parameters, conf: $confidence, source: ${source.name})';
}

/// Result of a Needle AI command execution.
class NeedleResponse {
  final bool success;
  final String userPrompt;
  final NeedleExecutionMode executedWhere;
  final NeedlePlanSource planSource;
  final NeedlePlan? plan;
  final List<NeedlePlan> steps;
  final String? targetDeviceId;
  final String? targetDeviceName;
  final bool requiresConfirmation;
  final List<String> suggestions;
  final String message;
  final dynamic result;
  final String? error;
  final DateTime timestamp;

  NeedleResponse({
    required this.success,
    required this.userPrompt,
    required this.executedWhere,
    this.planSource = NeedlePlanSource.rules,
    this.plan,
    List<NeedlePlan>? steps,
    this.targetDeviceId,
    this.targetDeviceName,
    this.requiresConfirmation = false,
    this.suggestions = const [],
    required this.message,
    this.result,
    this.error,
    DateTime? timestamp,
  })  : steps = steps ?? (plan != null && plan.toolName.isNotEmpty ? [plan] : const []),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'success': success,
        'user_prompt': userPrompt,
        'executed_where': executedWhere.name,
        'plan_source': planSource.name,
        'plan': plan?.toJson(),
        'steps': steps.map((s) => s.toJson()).toList(),
        'target_device_id': targetDeviceId,
        'target_device_name': targetDeviceName,
        'requires_confirmation': requiresConfirmation,
        'suggestions': suggestions,
        'message': message,
        'result': result,
        'error': error,
        'timestamp': timestamp.toIso8601String(),
      };
}
