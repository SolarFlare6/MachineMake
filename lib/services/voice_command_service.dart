import '../core/dcp/dcp_message.dart';
import '../core/needle/needle_models.dart';
import '../core/needle/rule_intent_matcher.dart';
import '../core/models/tool_definition.dart';

/// Represents a parsed natural language voice command ready for execution.
class VoiceCommand {
  final String toolName;
  final Map<String, dynamic> parameters;
  final String description;

  const VoiceCommand({
    required this.toolName,
    required this.parameters,
    required this.description,
  });

  @override
  String toString() => 'VoiceCommand(tool: $toolName, params: $parameters)';
}

/// Execution outcome of a voice command through the Hybrid Needle AI pipeline.
class VoiceExecutionResult {
  final bool success;
  final String userPrompt;
  final String? toolName;
  final Map<String, dynamic>? params;
  final String message;
  final DcpExecuteResponse? response;
  final NeedleExecutionMode? executedWhere;
  final NeedlePlan? plan;
  final NeedlePlanSource? planSource;
  final String? resolvedDeviceId;
  final String? resolvedDeviceName;
  final bool requiresConfirmation;
  final List<String> suggestions;

  const VoiceExecutionResult({
    required this.success,
    required this.userPrompt,
    this.toolName,
    this.params,
    required this.message,
    this.response,
    this.executedWhere,
    this.plan,
    this.planSource,
    this.resolvedDeviceId,
    this.resolvedDeviceName,
    this.requiresConfirmation = false,
    this.suggestions = const [],
  });
}

/// Service that parses natural language voice input into DCP tool commands.
class VoiceCommandService {
  /// Parses raw transcribed text into a structured DCP command using Stage 1 [RuleIntentMatcher].
  static VoiceCommand? parse(String rawText, {List<String>? availableTools}) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final defs = (availableTools ?? const <String>[])
        .map(
          (name) => ToolDefinition(
            name: name,
            description: 'Registered tool $name',
            parameters: const [],
          ),
        )
        .toList();

    final plan = RuleIntentMatcher.match(text, defs);
    if (plan.toolName.isEmpty || plan.confidence < 0.3) {
      return null;
    }

    return VoiceCommand(
      toolName: plan.toolName,
      parameters: plan.parameters,
      description: plan.explanation,
    );
  }
}
