import '../../models/tool_definition.dart';
import 'tool_relevance_filter.dart';

/// Builds a compact ChatML system prompt for `SmolLM2-360M-Instruct` containing
/// only the relevant tools for the target device and 3 domain-matched few-shot
/// examples.
class ToolPromptBuilder {
  ToolPromptBuilder._();

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
      'You are Needle, a hardware tool-calling planner for "$deviceName" ($deviceProfile).',
    );
    buf.writeln(
      'Respond ONLY with a single JSON object matching: {"calls":[{"tool":"<name>","params":{...}}]}',
    );
    buf.writeln('Available tools:');

    for (final t in tools) {
      if (t.parameters.isEmpty) {
        buf.writeln('- ${t.name}(): ${t.description}');
      } else {
        final paramsDesc = t.parameters.map((p) {
          if (p.enumValues != null && p.enumValues!.isNotEmpty) {
            return '${p.name}:${p.enumValues!.join("|")}';
          }
          return '${p.name}:${p.type}';
        }).join(', ');
        buf.writeln('- ${t.name}($paramsDesc): ${t.description}');
      }
    }

    buf.writeln('\nExamples:');
    final p = deviceProfile.toLowerCase();
    if (p.contains('pc') || p.contains('desktop') || p.contains('laptop')) {
      buf.writeln(
        'User: "press enter" -> {"calls":[{"tool":"keyboard_press","params":{"key":"enter"}}]}',
      );
      buf.writeln(
        'User: "type hello and hit enter" -> {"calls":[{"tool":"keyboard_type","params":{"text":"hello"}},{"tool":"keyboard_press","params":{"key":"enter"}}]}',
      );
      buf.writeln(
        'User: "it is too loud" -> {"calls":[{"tool":"media_control","params":{"action":"vol_down"}}]}',
      );
    } else if (p.contains('pico') || p.contains('mcu')) {
      buf.writeln(
        'User: "turn on pin 4" -> {"calls":[{"tool":"gpio_write","params":{"pin":4,"state":true}}]}',
      );
      buf.writeln(
        'User: "set pwm 0 to 75 percent" -> {"calls":[{"tool":"pwm_set","params":{"channel":0,"value":0.75}}]}',
      );
      buf.writeln(
        'User: "turn off the light" -> {"calls":[{"tool":"set_led","params":{"on":false}}]}',
      );
    } else {
      buf.writeln(
        'User: "walk forward 2 meters and take a photo" -> {"calls":[{"tool":"walk","params":{"direction":"forward","distance":2.0}},{"tool":"camera_snapshot","params":{}}]}',
      );
      buf.writeln(
        'User: "take a break" -> {"calls":[{"tool":"sit","params":{}}]}',
      );
      buf.writeln(
        'User: "press enter" -> {"calls":[{"tool":"keyboard_press","params":{"key":"enter"}}]}',
      );
    }

    return buf.toString().trim();
  }
}
