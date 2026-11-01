import 'dart:convert';

import '../../models/tool_definition.dart';
import 'tool_relevance_filter.dart';

/// Builds system prompts and JSON Schema tool arrays for Cactus Compute Needle 3
/// (`needle_init`) as well as ChatML fallback prompts.
class ToolPromptBuilder {
  ToolPromptBuilder._();

  /// Serializes [tools] into the OpenAI / Cactus Needle JSON Schema array string
  /// expected by `needle_init(system_prompt, tools_json, NULL)`.
  static String buildNeedleToolsJson(List<ToolDefinition> tools) {
    final list = <Map<String, dynamic>>[];

    for (final t in tools) {
      final properties = <String, dynamic>{};
      final requiredList = <String>[];

      for (final p in t.parameters) {
        final rawType = p.type.toLowerCase();
        String jsonType;
        if (rawType == 'int' || rawType == 'integer') {
          jsonType = 'integer';
        } else if (rawType == 'float' ||
            rawType == 'double' ||
            rawType == 'number') {
          jsonType = 'number';
        } else if (rawType == 'bool' || rawType == 'boolean') {
          jsonType = 'boolean';
        } else {
          jsonType = 'string';
        }

        final propMap = <String, dynamic>{
          'type': jsonType,
          if (p.description.isNotEmpty) 'description': p.description,
        };
        if (p.enumValues != null && p.enumValues!.isNotEmpty) {
          propMap['enum'] = p.enumValues;
        }
        properties[p.name] = propMap;
        if (p.required) {
          requiredList.add(p.name);
        }
      }

      list.add({
        'name': t.name,
        'description': t.description.isNotEmpty
            ? t.description
            : 'Execute ${t.name} hardware action',
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': requiredList,
        },
      });
    }

    return jsonEncode(list);
  }

  static String buildSystemPrompt({
    required String deviceName,
    required String deviceProfile,
    required List<ToolDefinition> filteredTools,
  }) {
    final tools = filteredTools.isNotEmpty
        ? filteredTools
        : ToolRelevanceFilter.defaultToolsForProfile(deviceProfile);

    final buf = StringBuffer();
    buf.writeln(
      'You are Needle, a hardware tool planner for "$deviceName" ($deviceProfile).',
    );
    buf.writeln(
      'Output ONLY JSON: {"calls":[{"tool":"<name>","params":{...}}]}',
    );
    buf.writeln('Tools:');

    for (final t in tools) {
      if (t.parameters.isEmpty) {
        buf.writeln('- ${t.name}()');
      } else {
        final paramsDesc = t.parameters.map((p) {
          if (p.enumValues != null && p.enumValues!.isNotEmpty) {
            return '${p.name}:${p.enumValues!.join("|")}';
          }
          return '${p.name}:${p.type}';
        }).join(', ');
        buf.writeln('- ${t.name}($paramsDesc)');
      }
    }

    buf.writeln('Examples:');
    final p = deviceProfile.toLowerCase();
    if (p.contains('pc') ||
        p.contains('desktop') ||
        p.contains('laptop') ||
        p.contains('computer')) {
      buf.writeln(
        'User: press the windows key then type hello and press enter\n'
        'Assistant: {"calls":[{"tool":"keyboard_press","params":{"key":"win"}},{"tool":"keyboard_type","params":{"text":"hello"}},{"tool":"keyboard_press","params":{"key":"enter"}}]}',
      );
      buf.writeln(
        'User: it is too loud\n'
        'Assistant: {"calls":[{"tool":"media_control","params":{"action":"vol_down"}}]}',
      );
    } else if (p.contains('pico') || p.contains('mcu')) {
      buf.writeln(
        'User: turn on pin 4 and set pwm 0 to 75 percent\n'
        'Assistant: {"calls":[{"tool":"gpio_write","params":{"pin":4,"state":true}},{"tool":"pwm_set","params":{"channel":0,"value":0.75}}]}',
      );
      buf.writeln(
        'User: turn off the light\n'
        'Assistant: {"calls":[{"tool":"set_led","params":{"on":false}}]}',
      );
    } else {
      buf.writeln(
        'User: walk forward 2 meters and take a photo\n'
        'Assistant: {"calls":[{"tool":"walk","params":{"direction":"forward","distance":2.0}},{"tool":"camera_snapshot","params":{}}]}',
      );
      buf.writeln(
        'User: take a break\n'
        'Assistant: {"calls":[{"tool":"sit","params":{}}]}',
      );
    }

    return buf.toString().trim();
  }
}
