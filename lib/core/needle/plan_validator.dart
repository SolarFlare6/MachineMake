import '../models/tool_definition.dart';
import 'needle_models.dart';

/// Validates and sanitizes a [NeedlePlan] against the target device's
/// registered [ToolDefinition] schemas, rejects tools that do not belong to the
/// target device, flags destructive commands, and computes closest-matching
/// tool suggestions when a prompt fails to match.
class PlanValidator {
  PlanValidator._();

  /// Destructive tools that should require user confirmation or explicit warning.
  static const Set<String> destructiveTools = {
    'shutdown',
    'system_shutdown',
    'reboot',
    'system_reboot',
    'sleep',
  };

  /// Validates and coerces parameters of [plan] (and any multi-step `steps`)
  /// against [availableTools].
  static NeedlePlan validateAndCoerce(
    NeedlePlan plan,
    List<ToolDefinition> availableTools,
  ) {
    if (plan.toolName.isEmpty) return plan;

    if (plan.steps.length > 1) {
      final validatedSteps = plan.steps
          .map((step) => _validateSingleStep(step, availableTools))
          .toList();
      final anyInvalid = validatedSteps.any((s) => s.toolName.isEmpty);
      if (anyInvalid) {
        final failedStep = validatedSteps.firstWhere(
          (s) => s.toolName.isEmpty,
          orElse: () => validatedSteps.first,
        );
        return NeedlePlan(
          toolName: '',
          parameters: const {},
          explanation: failedStep.explanation.isNotEmpty
              ? failedStep.explanation
              : 'One or more steps are not supported on ${plan.targetDeviceName ?? "this device"}',
          confidence: 0.0,
          thoughts: [
            ...plan.thoughts,
            ...validatedSteps.expand((s) => s.thoughts),
          ],
          source: plan.source,
          targetDeviceId: plan.targetDeviceId,
          targetDeviceName: plan.targetDeviceName,
        );
      }
      final first = validatedSteps.first;
      return NeedlePlan(
        toolName: first.toolName,
        parameters: first.parameters,
        explanation: validatedSteps.map((s) => s.explanation).join(' → '),
        confidence: plan.confidence,
        thoughts: validatedSteps.expand((s) => s.thoughts).toList(),
        source: plan.source,
        requiresConfirmation:
            validatedSteps.any((s) => s.requiresConfirmation),
        steps: validatedSteps,
        targetDeviceId: plan.targetDeviceId,
        targetDeviceName: plan.targetDeviceName,
      );
    }

    return _validateSingleStep(plan, availableTools);
  }

  static NeedlePlan _validateSingleStep(
    NeedlePlan plan,
    List<ToolDefinition> availableTools,
  ) {
    final isDestructive =
        plan.requiresConfirmation || destructiveTools.contains(plan.toolName);

    // If no tool definitions were provided at all, allow basic range clamping
    if (availableTools.isEmpty) {
      return NeedlePlan(
        toolName: plan.toolName,
        parameters: _clampStandardRanges(plan.toolName, plan.parameters),
        explanation: plan.explanation,
        confidence: plan.confidence,
        thoughts: plan.thoughts,
        source: plan.source,
        requiresConfirmation: isDestructive,
        steps: plan.steps,
        targetDeviceId: plan.targetDeviceId,
        targetDeviceName: plan.targetDeviceName,
      );
    }

    // Find matching tool definition (or common alias)
    ToolDefinition? toolDef;
    for (final t in availableTools) {
      if (t.name == plan.toolName) {
        toolDef = t;
        break;
      }
    }

    // Check common aliases within the same device category if exact tool name wasn't found
    var resolvedToolName = plan.toolName;
    if (toolDef == null) {
      final aliasMap = <String, List<String>>{
        'camera_snapshot': ['take_picture', 'capture_photo'],
        'take_picture': ['camera_snapshot', 'capture_photo'],
        'reboot': ['system_reboot'],
        'system_reboot': ['reboot'],
        'shutdown': ['system_shutdown'],
        'system_shutdown': ['shutdown'],
        'get_telemetry': ['system_status'],
        'stop': ['emergency_stop', 'stand'],
        'emergency_stop': ['stop', 'stand'],
        'animate_with_color': ['animate_running_process'],
        'animate_running_process': ['animate_with_color'],
        'set_servo_angle': ['driver_set_servo_angle_with_index'],
        'driver_set_servo_angle_with_index': ['set_servo_angle'],
      };
      final candidates = aliasMap[plan.toolName] ?? const [];
      for (final alt in candidates) {
        for (final t in availableTools) {
          if (t.name == alt) {
            toolDef = t;
            resolvedToolName = alt;
            break;
          }
        }
        if (toolDef != null) break;
      }
    }

    // Strictly reject tools that do not exist on the target device!
    if (toolDef == null) {
      final deviceLabel = plan.targetDeviceName ?? 'this device';
      return NeedlePlan(
        toolName: '',
        parameters: const {},
        explanation:
            'Tool "${plan.toolName}" is not available on $deviceLabel',
        confidence: 0.0,
        thoughts: [
          ...plan.thoughts,
          'Rejected tool "${plan.toolName}" because it is not supported by $deviceLabel.',
        ],
        source: plan.source,
        targetDeviceId: plan.targetDeviceId,
        targetDeviceName: plan.targetDeviceName,
      );
    }

    // Coerce parameters against schema
    final coercedParams = Map<String, dynamic>.from(plan.parameters);
    for (final paramDef in toolDef.parameters) {
      final rawVal = coercedParams[paramDef.name];
      if (rawVal == null) {
        if (paramDef.defaultValue != null) {
          coercedParams[paramDef.name] = paramDef.defaultValue;
        }
        continue;
      }

      switch (paramDef.type.toLowerCase()) {
        case 'int':
        case 'integer':
          if (rawVal is num) {
            coercedParams[paramDef.name] = rawVal.toInt();
          } else if (rawVal is String) {
            coercedParams[paramDef.name] =
                int.tryParse(rawVal) ?? paramDef.defaultValue ?? 0;
          }
          break;
        case 'float':
        case 'double':
        case 'number':
          if (rawVal is num) {
            coercedParams[paramDef.name] = rawVal.toDouble();
          } else if (rawVal is String) {
            coercedParams[paramDef.name] =
                double.tryParse(rawVal) ?? paramDef.defaultValue ?? 0.0;
          }
          break;
        case 'bool':
        case 'boolean':
          if (rawVal is! bool) {
            final s = rawVal.toString().toLowerCase();
            coercedParams[paramDef.name] =
                s == 'true' || s == '1' || s == 'on' || s == 'high';
          }
          break;
        case 'enum':
          if (paramDef.enumValues != null && paramDef.enumValues!.isNotEmpty) {
            final s = rawVal.toString();
            if (!paramDef.enumValues!.contains(s)) {
              coercedParams[paramDef.name] = paramDef.enumValues!.first;
            }
          }
          break;
        default:
          coercedParams[paramDef.name] = rawVal.toString();
      }
    }

    final clampedParams = _clampStandardRanges(resolvedToolName, coercedParams);

    return NeedlePlan(
      toolName: resolvedToolName,
      parameters: clampedParams,
      explanation: plan.explanation,
      confidence: plan.confidence,
      thoughts: plan.thoughts,
      source: plan.source,
      requiresConfirmation:
          isDestructive || destructiveTools.contains(resolvedToolName),
      steps: plan.steps,
      targetDeviceId: plan.targetDeviceId,
      targetDeviceName: plan.targetDeviceName,
    );
  }

  static Map<String, dynamic> _clampStandardRanges(
    String toolName,
    Map<String, dynamic> params,
  ) {
    final result = Map<String, dynamic>.from(params);
    if (toolName == 'pwm_set' && result['value'] is num) {
      var v = (result['value'] as num).toDouble();
      if (v > 1.0 && v <= 100.0) v = v / 100.0;
      result['value'] = v.clamp(0.0, 1.0);
    } else if (toolName == 'walk') {
      result['direction'] ??= 'forward';
      final d = (result['distance'] is num)
          ? (result['distance'] as num).toDouble()
          : 1.0;
      result['distance'] = d.clamp(0.1, 10.0);
    } else if (toolName == 'turn') {
      result['direction'] ??= 'left';
      final a =
          (result['angle'] is num) ? (result['angle'] as num).toDouble() : 45.0;
      result['angle'] = a.clamp(5.0, 360.0);
    } else if (toolName == 'turn_on_strip_with_color') {
      int r = (result['r'] is num) ? (result['r'] as num).toInt().clamp(0, 255) : 0;
      int g = (result['g'] is num) ? (result['g'] as num).toInt().clamp(0, 255) : 0;
      int b = (result['b'] is num) ? (result['b'] as num).toInt().clamp(0, 255) : 0;
      if (r == 0 && g == 0 && b == 0) {
        r = 0;
        g = 230;
        b = 118;
      }
      result['r'] = r;
      result['g'] = g;
      result['b'] = b;
    } else if (toolName == 'pan_to_left' ||
        toolName == 'pan_to_right' ||
        toolName == 'snap_servo_left' ||
        toolName == 'snap_servo_right') {
      result['index'] =
          (result['index'] is num) ? (result['index'] as num).toInt().clamp(0, 15) : 0;
    }
    return result;
  }

  /// Generates up to 4 human-friendly example voice commands based on the
  /// target device's available tools or profile.
  static List<String> suggestExamples(
    List<ToolDefinition> availableTools, {
    String? deviceProfile,
  }) {
    final toolNames = availableTools.map((t) => t.name).toSet();
    final suggestions = <String>[];

    if (toolNames.contains('keyboard_press') ||
        (deviceProfile?.toLowerCase().contains('pc') ?? false) ||
        (deviceProfile?.toLowerCase().contains('desktop') ?? false)) {
      suggestions.addAll([
        '"Press Enter"',
        '"Type hello world"',
        '"Lock screen"',
        '"Volume up"',
      ]);
    }
    if (toolNames.contains('walk') ||
        toolNames.contains('stand') ||
        toolNames.contains('turn_on_strip_with_color') ||
        (deviceProfile?.toLowerCase().contains('quadruped') ?? false) ||
        (deviceProfile?.toLowerCase().contains('robot') ?? false)) {
      suggestions.addAll([
        '"Turn on the LED strip and move the camera to the left"',
        '"Walk forward 2 meters"',
        '"Turn left 90 degrees"',
        '"Stand up"',
      ]);
    }
    if (toolNames.contains('gpio_write') ||
        toolNames.contains('pwm_set') ||
        (deviceProfile?.toLowerCase().contains('pico') ?? false)) {
      suggestions.addAll([
        '"Turn on pin 4"',
        '"Set PWM 0 to 50%"',
        '"Turn on LED"',
      ]);
    }

    if (suggestions.isEmpty) {
      suggestions.addAll([
        '"Press Enter"',
        '"Walk forward"',
        '"Turn on pin 4"',
      ]);
    }
    return suggestions.take(4).toList();
  }
}
