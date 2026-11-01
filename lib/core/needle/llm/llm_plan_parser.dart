import 'dart:convert';

import '../needle_models.dart';

/// Parses the JSON output produced by Cactus Compute Needle 3
/// (`{"type":"call","function_calls":[{"name":"...","arguments":{...}}],"reasoning":"...","confidence":0.94}`)
/// or GGUF models (`{"calls":[{"tool":"...","params":{...}}]}`) into a [NeedlePlan].
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

      final rawConfidence = decoded['confidence'];
      final parsedConfidence = rawConfidence is num
          ? rawConfidence.toDouble().clamp(0.0, 1.0)
          : 0.88;
      final reasoning = decoded['reasoning']?.toString().trim();

      // Support both Cactus Compute Needle 3 ("function_calls") and legacy ("calls")
      final callsList = decoded['function_calls'] ?? decoded['calls'];
      if (callsList is List && callsList.isNotEmpty) {
        final steps = <NeedlePlan>[];
        final flattenedItems = <Map>[];
        for (final item in callsList) {
          if (item is Map && item['calls'] is List) {
            for (final inner in (item['calls'] as List)) {
              if (inner is Map) flattenedItems.add(inner);
            }
          } else if (item is List) {
            for (final inner in item) {
              if (inner is Map) flattenedItems.add(inner);
            }
          } else if (item is Map) {
            flattenedItems.add(item);
          }
        }
        for (final item in flattenedItems) {
          final tool = (item['name'] ?? item['tool'] ?? '').toString().trim();
          final rawParams =
              item['arguments'] ?? item['params'] ?? item['parameters'];
          final params = rawParams is Map
              ? Map<String, dynamic>.from(rawParams)
              : <String, dynamic>{};
          if (tool.isNotEmpty && tool != 'none') {
            steps.add(
              NeedlePlan(
                toolName: tool,
                parameters: params,
                explanation:
                    'Executing $tool on ${targetDeviceName ?? "device"}',
                confidence: parsedConfidence,
                thoughts: [
                  'Cactus Needle 3 selected tool "$tool" with arguments $params',
                  if (reasoning != null && reasoning.isNotEmpty)
                    'Needle reasoning: $reasoning',
                ],
                source: NeedlePlanSource.localLlm,
                targetDeviceId: targetDeviceId,
                targetDeviceName: targetDeviceName,
              ),
            );
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
          confidence: parsedConfidence,
          thoughts: [
            'Cactus Needle 3 generated ${steps.length}-step plan',
            if (reasoning != null && reasoning.isNotEmpty)
              'Needle reasoning: $reasoning',
            ...steps.expand((s) => s.thoughts),
          ],
          source: NeedlePlanSource.localLlm,
          steps: steps,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }

      // Single-object fallback: `{"tool":"...","params":{...}}` or `{"name":"...","arguments":{...}}`
      final singleTool =
          (decoded['name'] ?? decoded['tool'] ?? '').toString().trim();
      if (singleTool.isNotEmpty && singleTool != 'none') {
        final rawParams =
            decoded['arguments'] ?? decoded['params'] ?? decoded['parameters'] ?? {};
        final params = rawParams is Map
            ? Map<String, dynamic>.from(rawParams)
            : <String, dynamic>{};
        return NeedlePlan(
          toolName: singleTool,
          parameters: params,
          explanation:
              'Executing $singleTool on ${targetDeviceName ?? "device"}',
          confidence: parsedConfidence,
          thoughts: [
            'Cactus Needle 3 selected tool "$singleTool"',
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
