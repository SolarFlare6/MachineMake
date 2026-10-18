import '../models/tool_definition.dart';
import 'needle_models.dart';

/// Validates and sanitizes a [NeedlePlan] against the target device's
/// registered [ToolDefinition] schemas, flags destructive commands, and
/// computes closest-matching tool suggestions when a prompt fails to match.
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
      final first = validatedSteps.first;
      final anyInvalid = validatedSteps.any((s) => s.toolName.isEmpty);
      if (anyInvalid) {
        return NeedlePlan(
          toolName: '',
          parameters: const {},
          explanation: 'One or more steps failed tool schema validation',
          confidence: 0.0,
          thoughts: [
            ...plan.thoughts,
            'Multi-step validation failed because a step referenced an invalid tool.',
          ],
          source: plan.source,
          targetDeviceId: plan.targetDeviceId,
          targetDeviceName: plan.targetDeviceName,
        );
      }
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

    // If the device has not reported any tool schemas yet, allow well-known tools
    // with basic parameter clamping.
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

    // Check common aliases if exact tool name wasn't in availableTools
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
        'stop': ['stand'],
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

    // Coerce parameters against schema if toolDef exists
    final coercedParams = Map<String, dynamic>.from(plan.parameters);
    if (toolDef != null) {
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
    } else if (toolName == 'walk' && result['distance'] is num) {
      result['distance'] =
          (result['distance'] as num).toDouble().clamp(0.1, 10.0);
    } else if (toolName == 'turn' && result['angle'] is num) {
      result['angle'] = (result['angle'] as num).toDouble().clamp(5.0, 360.0);
    }
    return result;
  }

  /// Generates up to 3 human-friendly example voice commands based on the
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
        (deviceProfile?.toLowerCase().contains('quadruped') ?? false) ||
        (deviceProfile?.toLowerCase().contains('robot') ?? false)) {
      suggestions.addAll([
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
