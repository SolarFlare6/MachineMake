import '../../models/tool_definition.dart';

/// Filters a device's full list of [ToolDefinition]s down to the top [maxTools]
/// most relevant tools for a given user prompt and device profile.
///
/// Keeping the tool schema compact (< 350 tokens) speeds up `SmolLM2-360M-Instruct`
/// prefill latency and significantly improves tool selection accuracy.
class ToolRelevanceFilter {
  ToolRelevanceFilter._();

  static List<ToolDefinition> filter({
    required String prompt,
    required List<ToolDefinition> availableTools,
    String? deviceProfile,
    int maxTools = 10,
  }) {
    final effectiveTools = availableTools.isNotEmpty
        ? availableTools
        : defaultToolsForProfile(deviceProfile);

    if (effectiveTools.length <= maxTools) {
      return effectiveTools;
    }

    final words = prompt
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 2)
        .toSet();

    final scored = <_ScoredTool>[];
    for (final tool in effectiveTools) {
      int score = 0;
      final nameLower = tool.name.toLowerCase();
      final descLower = tool.description.toLowerCase();

      for (final w in words) {
        if (nameLower.contains(w)) score += 5;
        if (descLower.contains(w)) score += 2;
        for (final p in tool.parameters) {
          if (p.name.toLowerCase().contains(w)) score += 2;
          if (p.enumValues != null &&
              p.enumValues!.any((e) => e.toLowerCase().contains(w))) {
            score += 4;
          }
        }
      }

      // Boost core profile tools so general/indirect prompts always have them
      if (_isCoreTool(nameLower, deviceProfile)) {
        score += 3;
      }

      scored.add(_ScoredTool(tool, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(maxTools).map((s) => s.tool).toList();
  }

  static bool _isCoreTool(String toolName, String? profile) {
    const core = {
      'keyboard_press',
      'keyboard_type',
      'lock_device',
      'media_control',
      'mouse_click',
      'mouse_scroll',
      'stand',
      'sit',
      'stop',
      'walk',
      'turn',
      'gpio_write',
      'pwm_set',
      'set_led',
      'get_telemetry',
    };
    return core.contains(toolName);
  }

  /// Provides standard fallback tool schemas when a device has not yet sent
  /// a dynamic `tools_response` over DCP.
  static List<ToolDefinition> defaultToolsForProfile(String? profile) {
    final p = (profile ?? '').toLowerCase();

    if (p.contains('pc') || p.contains('desktop') || p.contains('laptop')) {
      return const [
        ToolDefinition(
          name: 'keyboard_press',
          description: 'Press a keyboard key or shortcut combo (e.g. enter, escape, space, tab, ctrl+c, alt+tab)',
          parameters: [
            ToolParameter(
              name: 'key',
              type: 'string',
              description: 'Key name or combo',
              required: true,
            ),
          ],
        ),
        ToolDefinition(
          name: 'keyboard_type',
          description: 'Type a string of text on the PC keyboard',
          parameters: [
            ToolParameter(
              name: 'text',
              type: 'string',
              description: 'Literal text to type',
              required: true,
            ),
          ],
        ),
        ToolDefinition(
          name: 'lock_device',
          description: 'Lock the PC screen / workstation',
          parameters: [],
        ),
        ToolDefinition(
          name: 'media_control',
          description: 'Control PC audio volume or media playback',
          parameters: [
            ToolParameter(
              name: 'action',
              type: 'enum',
              description: 'Media action',
              required: true,
              enumValues: ['play_pause', 'next', 'prev', 'vol_up', 'vol_down', 'mute'],
            ),
          ],
        ),
        ToolDefinition(
          name: 'mouse_click',
          description: 'Click a mouse button',
          parameters: [
            ToolParameter(
              name: 'button',
              type: 'enum',
              description: 'Mouse button',
              required: true,
              enumValues: ['left', 'right', 'middle'],
            ),
          ],
        ),
        ToolDefinition(
          name: 'mouse_scroll',
          description: 'Scroll the mouse wheel up (positive dy) or down (negative dy)',
          parameters: [
            ToolParameter(
              name: 'dy',
              type: 'int',
              description: 'Scroll ticks',
              required: true,
            ),
          ],
        ),
        ToolDefinition(
          name: 'sleep',
          description: 'Put the PC to sleep',
          parameters: [],
        ),
        ToolDefinition(
          name: 'reboot',
          description: 'Restart / reboot the PC',
          parameters: [],
        ),
        ToolDefinition(
          name: 'shutdown',
          description: 'Shut down / power off the PC',
          parameters: [],
        ),
        ToolDefinition(
          name: 'get_telemetry',
          description: 'Get CPU, RAM, and temperature telemetry',
          parameters: [],
        ),
      ];
    }

    if (p.contains('pico') || p.contains('mcu') || p.contains('esp32')) {
      return const [
        ToolDefinition(
          name: 'gpio_write',
          description: 'Set a digital GPIO pin high (true) or low (false)',
          parameters: [
            ToolParameter(name: 'pin', type: 'int', description: 'GPIO pin number', required: true),
            ToolParameter(name: 'state', type: 'bool', description: 'true=HIGH, false=LOW', required: true),
          ],
        ),
        ToolDefinition(
          name: 'gpio_read',
          description: 'Read digital GPIO pin state',
          parameters: [
            ToolParameter(name: 'pin', type: 'int', description: 'GPIO pin number', required: true),
          ],
        ),
        ToolDefinition(
          name: 'pwm_set',
          description: 'Set PWM duty cycle on a channel from 0.0 to 1.0',
          parameters: [
            ToolParameter(name: 'channel', type: 'int', description: 'PWM channel', required: true),
            ToolParameter(name: 'value', type: 'float', description: 'Duty cycle 0.0-1.0', required: true),
          ],
        ),
        ToolDefinition(
          name: 'set_led',
          description: 'Turn onboard LED on or off',
          parameters: [
            ToolParameter(name: 'on', type: 'bool', description: 'LED state', required: true),
          ],
        ),
      ];
    }

    // Default combined Robot + PC + Hardware toolset
    return const [
      ToolDefinition(
        name: 'stand',
        description: 'Command robot to stand up',
        parameters: [],
      ),
      ToolDefinition(
        name: 'sit',
        description: 'Command robot to sit or crouch down',
        parameters: [],
      ),
      ToolDefinition(
        name: 'stop',
        description: 'Emergency stop all robot movement',
        parameters: [],
      ),
      ToolDefinition(
        name: 'walk',
        description: 'Walk robot in a direction for a distance in meters',
        parameters: [
          ToolParameter(
            name: 'direction',
            type: 'enum',
            description: 'Movement direction',
            required: true,
            enumValues: ['forward', 'backward', 'left', 'right'],
          ),
          ToolParameter(
            name: 'distance',
            type: 'float',
            description: 'Distance in meters (0.1 to 10.0)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'turn',
        description: 'Rotate robot left or right by angle in degrees',
        parameters: [
          ToolParameter(
            name: 'direction',
            type: 'enum',
            description: 'Turn direction',
            required: true,
            enumValues: ['left', 'right'],
          ),
          ToolParameter(
            name: 'angle',
            type: 'float',
            description: 'Angle in degrees (5 to 360)',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'camera_snapshot',
        description: 'Take a photo snapshot with the camera',
        parameters: [],
      ),
      ToolDefinition(
        name: 'set_led',
        description: 'Turn device LED light on or off',
        parameters: [
          ToolParameter(name: 'on', type: 'bool', description: 'LED on/off', required: true),
        ],
      ),
      ToolDefinition(
        name: 'keyboard_press',
        description: 'Press a keyboard key (enter, escape, space, ctrl+c)',
        parameters: [
          ToolParameter(name: 'key', type: 'string', description: 'Key name', required: true),
        ],
      ),
      ToolDefinition(
        name: 'keyboard_type',
        description: 'Type text on keyboard',
        parameters: [
          ToolParameter(name: 'text', type: 'string', description: 'Text to type', required: true),
        ],
      ),
      ToolDefinition(
        name: 'get_telemetry',
        description: 'Query battery, temperature, CPU, and RAM telemetry',
        parameters: [],
      ),
    ];
  }
}

class _ScoredTool {
  final ToolDefinition tool;
  final int score;
  const _ScoredTool(this.tool, this.score);
}
