import 'dart:convert';

import '../needle_models.dart';

/// Parses the JSON output produced by `SmolLM2-360M-Instruct`
/// (`{"calls":[{"tool":"...","params":{...}}]}`) into a [NeedlePlan].
class LlmPlanParser {
  LlmPlanParser._();

  static NeedlePlan parse(
    String rawOutput, {
    String? targetDeviceId,
    String? targetDeviceName,
  }) {
    final cleaned = _extractJsonObject(rawOutput);
    if (cleaned.isEmpty) {
      return NeedlePlan(
        toolName: '',
        parameters: const {},
        explanation: 'Local LLM returned empty or non-JSON output',
        confidence: 0.0,
        thoughts: ['Raw LLM output could not be parsed as JSON: "$rawOutput"'],
        source: NeedlePlanSource.localLlm,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) {
        return _failedPlan(rawOutput, targetDeviceId, targetDeviceName);
      }

      final callsList = decoded['calls'];
      if (callsList is List && callsList.isNotEmpty) {
        final steps = <NeedlePlan>[];
        for (final item in callsList) {
          if (item is Map) {
            final tool = (item['tool'] ?? item['name'] ?? '').toString().trim();
            final rawParams = item['params'] ?? item['parameters'] ?? item['arguments'];
            final params = rawParams is Map
                ? Map<String, dynamic>.from(rawParams)
                : <String, dynamic>{};
            if (tool.isNotEmpty && tool != 'none') {
              steps.add(
                NeedlePlan(
                  toolName: tool,
                  parameters: params,
                  explanation: 'Executing $tool on ${targetDeviceName ?? "device"}',
                  confidence: 0.86,
                  thoughts: [
                    'Stage 2 (Local LLM SmolLM2-360M) selected tool "$tool" with params $params',
                  ],
                  source: NeedlePlanSource.localLlm,
                  targetDeviceId: targetDeviceId,
                  targetDeviceName: targetDeviceName,
                ),
              );
            }
          }
        }

        if (steps.isEmpty) {
          return _failedPlan(rawOutput, targetDeviceId, targetDeviceName);
        }

        if (steps.length == 1) {
          return steps.first;
        }

        final first = steps.first;
        return NeedlePlan(
          toolName: first.toolName,
          parameters: first.parameters,
          explanation: steps.map((s) => s.explanation).join(' → '),
          confidence: 0.86,
          thoughts: [
            'Stage 2 (Local LLM SmolLM2-360M) generated ${steps.length}-step plan',
            ...steps.expand((s) => s.thoughts),
          ],
          source: NeedlePlanSource.localLlm,
          steps: steps,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }

      // Single-object fallback: `{"tool":"...","params":{...}}`
      final singleTool = (decoded['tool'] ?? decoded['name'] ?? '').toString().trim();
      if (singleTool.isNotEmpty && singleTool != 'none') {
        final rawParams = decoded['params'] ?? decoded['parameters'] ?? {};
        final params = rawParams is Map
            ? Map<String, dynamic>.from(rawParams)
            : <String, dynamic>{};
        return NeedlePlan(
          toolName: singleTool,
          parameters: params,
          explanation: 'Executing $singleTool on ${targetDeviceName ?? "device"}',
          confidence: 0.85,
          thoughts: [
            'Stage 2 (Local LLM SmolLM2-360M) selected tool "$singleTool"',
          ],
          source: NeedlePlanSource.localLlm,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }
    } catch (e) {
      return NeedlePlan(
        toolName: '',
        parameters: const {},
        explanation: 'Failed to decode Local LLM JSON plan',
        confidence: 0.0,
        thoughts: ['JSON decode error: $e', 'Raw: $rawOutput'],
        source: NeedlePlanSource.localLlm,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    return _failedPlan(rawOutput, targetDeviceId, targetDeviceName);
  }

  static String _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start == -1) return '';

    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < raw.length; i++) {
      final ch = raw[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) {
            return raw.substring(start, i + 1);
          }
        }
      }
    }

    // If truncated before final closing braces, attempt to repair `]}`
    var candidate = raw.substring(start).trim();
    if (!candidate.endsWith('}')) {
      if (!candidate.endsWith(']')) {
        candidate = '$candidate]}';
      } else {
        candidate = '$candidate}';
      }
    }
    return candidate;
  }

  static NeedlePlan _failedPlan(
    String raw,
    String? targetDeviceId,
    String? targetDeviceName,
  ) {
    return NeedlePlan(
      toolName: '',
      parameters: const {},
      explanation: 'Local LLM could not map command to a valid tool',
      confidence: 0.0,
      thoughts: ['Unrecognized LLM output: $raw'],
      source: NeedlePlanSource.localLlm,
      targetDeviceId: targetDeviceId,
      targetDeviceName: targetDeviceName,
    );
  }
}
