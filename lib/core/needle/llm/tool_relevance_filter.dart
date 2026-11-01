import '../../models/tool_definition.dart';

/// Filters a device's full list of [ToolDefinition]s down to the top [maxTools]
/// most relevant tools for a given user prompt and device profile, and provides
/// strictly separated per-device tool catalogs for PC, Quadruped Robot, and Pico/MCU.
class ToolRelevanceFilter {
  ToolRelevanceFilter._();

  static List<ToolDefinition> filter({
    required String prompt,
    required List<ToolDefinition> availableTools,
    String? deviceProfile,
    int maxTools = 12,
  }) {
    final baseTools = availableTools.isNotEmpty
        ? availableTools
        : defaultToolsForProfile(deviceProfile);

    // Exclude recursive meta-tools (`needle_prompt` / `ai_prompt`) from LLM tool schemas
    final effectiveTools = baseTools
        .where((t) => t.name != 'needle_prompt' && t.name != 'ai_prompt')
        .toList();

    if (effectiveTools.length <= maxTools) {
      return effectiveTools;
    }

    final lowerPrompt = prompt.toLowerCase();
    final words = lowerPrompt
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 2)
        .toSet();

    final scored = <_ScoredTool>[];
    for (final tool in effectiveTools) {
      int score = 0;
      final nameLower = tool.name.toLowerCase();
      final descLower = tool.description.toLowerCase();

      for (final w in words) {
        if (nameLower.contains(w)) score += 6;
        if (descLower.contains(w)) score += 3;
        for (final p in tool.parameters) {
          if (p.name.toLowerCase().contains(w)) score += 2;
          if (p.enumValues != null &&
              p.enumValues!.any((e) => e.toLowerCase().contains(w))) {
            score += 4;
          }
        }
      }

      // Semantic synonym boosts for Robot LED strip & Camera Servo tools
      if (lowerPrompt.contains('strip') ||
          lowerPrompt.contains('led') ||
          lowerPrompt.contains('light') ||
          lowerPrompt.contains('color') ||
          lowerPrompt.contains('rgb')) {
        if (nameLower.contains('strip') ||
            nameLower.contains('led') ||
            nameLower.contains('animate') ||
            nameLower.contains('blink') ||
            nameLower.contains('flash')) {
          score += 10;
        }
      }

      if (lowerPrompt.contains('camera') ||
          lowerPrompt.contains('servo') ||
          lowerPrompt.contains('pan') ||
          lowerPrompt.contains('snap') ||
          lowerPrompt.contains('look')) {
        if (nameLower.contains('pan_to_') ||
            nameLower.contains('snap_servo_') ||
            nameLower.contains('servo') ||
            nameLower.contains('camera')) {
          score += 12;
        }
      }

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
      'turn_on_strip_with_color',
      'turn_off_strip',
      'pan_to_left',
      'pan_to_right',
      'speak',
      'gpio_write',
      'pwm_set',
      'set_led',
    };
    return core.contains(toolName);
  }

  /// Provides strictly device-specific tool schemas when a device has not yet
  /// sent a dynamic `tools_response` over DCP (or to augment/validate profile tools).
  static List<ToolDefinition> defaultToolsForProfile(String? profile) {
    final p = (profile ?? '').toLowerCase();

    // ── 1. PC / Desktop / Laptop Profile (ONLY PC tools) ──────────────────
    if (p.contains('pc') ||
        p.contains('desktop') ||
        p.contains('laptop') ||
        (p.contains('computer') && !p.contains('robot'))) {
      return const [
        ToolDefinition(
          name: 'keyboard_press',
          description:
              'Press a keyboard key or shortcut combo on the PC (e.g. enter, escape, space, tab, ctrl+c, alt+tab)',
          parameters: [
            ToolParameter(
              name: 'key',
              type: 'string',
              description: 'Key name or shortcut combo',
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
              description: 'Media control action',
              required: true,
              enumValues: [
                'play_pause',
                'next',
                'prev',
                'vol_up',
                'vol_down',
                'mute',
              ],
            ),
          ],
        ),
        ToolDefinition(
          name: 'mouse_click',
          description: 'Click a mouse button on the PC',
          parameters: [
            ToolParameter(
              name: 'button',
              type: 'enum',
              description: 'Mouse button',
              required: true,
              enumValues: ['left', 'right', 'middle'],
              defaultValue: 'left',
            ),
            ToolParameter(
              name: 'double',
              type: 'bool',
              description: 'True for double-click',
              required: false,
              defaultValue: false,
            ),
          ],
        ),
        ToolDefinition(
          name: 'mouse_scroll',
          description:
              'Scroll the PC mouse wheel up (positive dy) or down (negative dy)',
          parameters: [
            ToolParameter(
              name: 'dy',
              type: 'int',
              description: 'Scroll ticks (positive=up, negative=down)',
              required: true,
              defaultValue: -5,
            ),
          ],
        ),
        ToolDefinition(
          name: 'mouse_move',
          description: 'Move the PC mouse cursor by relative (dx, dy) pixels',
          parameters: [
            ToolParameter(
              name: 'dx',
              type: 'int',
              description: 'Horizontal delta in pixels',
              required: true,
              defaultValue: 0,
            ),
            ToolParameter(
              name: 'dy',
              type: 'int',
              description: 'Vertical delta in pixels',
              required: true,
              defaultValue: 0,
            ),
          ],
        ),
        ToolDefinition(
          name: 'sleep',
          description: 'Put the PC to sleep / suspend',
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
          description: 'Get PC CPU, RAM, and temperature telemetry',
          parameters: [],
        ),
      ];
    }

    // ── 2. Microcontroller / Pi Pico Profile (ONLY MCU tools) ─────────────
    if (p.contains('pico') ||
        p.contains('mcu') ||
        p.contains('esp32') ||
        p.contains('microcontroller')) {
      return const [
        ToolDefinition(
          name: 'gpio_write',
          description: 'Set a digital GPIO pin high (true) or low (false)',
          parameters: [
            ToolParameter(
              name: 'pin',
              type: 'int',
              description: 'GPIO pin number',
              required: true,
            ),
            ToolParameter(
              name: 'state',
              type: 'bool',
              description: 'true=HIGH (on), false=LOW (off)',
              required: true,
            ),
          ],
        ),
        ToolDefinition(
          name: 'gpio_read',
          description: 'Read digital GPIO pin state',
          parameters: [
            ToolParameter(
              name: 'pin',
              type: 'int',
              description: 'GPIO pin number',
              required: true,
            ),
          ],
        ),
        ToolDefinition(
          name: 'pwm_set',
          description: 'Set PWM duty cycle on a channel from 0.0 to 1.0',
          parameters: [
            ToolParameter(
              name: 'channel',
              type: 'int',
              description: 'PWM channel',
              required: true,
            ),
            ToolParameter(
              name: 'value',
              type: 'float',
              description: 'Duty cycle 0.0-1.0',
              required: true,
            ),
          ],
        ),
        ToolDefinition(
          name: 'set_led',
          description: 'Turn onboard microcontroller LED on or off',
          parameters: [
            ToolParameter(
              name: 'on',
              type: 'bool',
              description: 'LED state',
              required: true,
            ),
          ],
        ),
      ];
    }

    // ── 3. Quadruped Robot Profile (ONLY Robot tools) ─────────────────────
    return const [
      ToolDefinition(
        name: 'turn_on_strip_with_color',
        description:
            'Turn on the robot 8-LED RGB strip with an RGB color (r, g, b from 0-255; default green r=0, g=230, b=118)',
        parameters: [
          ToolParameter(
            name: 'r',
            type: 'int',
            description: 'Red value (0-255)',
            required: false,
            defaultValue: 0,
          ),
          ToolParameter(
            name: 'g',
            type: 'int',
            description: 'Green value (0-255)',
            required: false,
            defaultValue: 230,
          ),
          ToolParameter(
            name: 'b',
            type: 'int',
            description: 'Blue value (0-255)',
            required: false,
            defaultValue: 118,
          ),
        ],
      ),
      ToolDefinition(
        name: 'turn_off_strip',
        description: 'Turn off all 8 LEDs on the robot LED strip',
        parameters: [],
      ),
      ToolDefinition(
        name: 'animate_running_process',
        description: 'Run LED strip color chase animation on the robot',
        parameters: [
          ToolParameter(
            name: 'r',
            type: 'int',
            description: 'Red (0-255)',
            required: false,
            defaultValue: 0,
          ),
          ToolParameter(
            name: 'g',
            type: 'int',
            description: 'Green (0-255)',
            required: false,
            defaultValue: 105,
          ),
          ToolParameter(
            name: 'b',
            type: 'int',
            description: 'Blue (0-255)',
            required: false,
            defaultValue: 105,
          ),
        ],
      ),
      ToolDefinition(
        name: 'pan_to_left',
        description:
            'Move or pan the robot camera or servo smoothly to the left (180 degrees). Channel index 0 is the camera servo.',
        parameters: [
          ToolParameter(
            name: 'index',
            type: 'int',
            description: 'Servo channel index (0 for camera servo)',
            required: false,
            defaultValue: 0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'pan_to_right',
        description:
            'Move or pan the robot camera or servo smoothly to the right (0 degrees). Channel index 0 is the camera servo.',
        parameters: [
          ToolParameter(
            name: 'index',
            type: 'int',
            description: 'Servo channel index (0 for camera servo)',
            required: false,
            defaultValue: 0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'snap_servo_left',
        description:
            'Snap a robot servo or the camera immediately to the left (180 degrees). Channel index 0 is the camera servo.',
        parameters: [
          ToolParameter(
            name: 'index',
            type: 'int',
            description: 'Servo channel index (0 for camera servo)',
            required: false,
            defaultValue: 0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'snap_servo_right',
        description:
            'Snap a robot servo or the camera immediately to the right (0 degrees). Channel index 0 is the camera servo.',
        parameters: [
          ToolParameter(
            name: 'index',
            type: 'int',
            description: 'Servo channel index (0 for camera servo)',
            required: false,
            defaultValue: 0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'driver_set_servo_angle_with_index',
        description:
            'Set a robot servo channel (0-15, where 0 is camera) to a specific angle in degrees (0 to 180)',
        parameters: [
          ToolParameter(
            name: 'index',
            type: 'int',
            description: 'Servo channel index (0-15)',
            required: true,
            defaultValue: 0,
          ),
          ToolParameter(
            name: 'angle',
            type: 'float',
            description: 'Angle in degrees (0-180)',
            required: true,
            defaultValue: 90.0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'cleanup_servos',
        description: 'Release and de-energize all 16 robot servo channels',
        parameters: [],
      ),
      ToolDefinition(
        name: 'stand',
        description: 'Command robot to stand up in neutral posture',
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
            description: 'Walking direction',
            required: true,
            enumValues: ['forward', 'backward', 'left', 'right'],
            defaultValue: 'forward',
          ),
          ToolParameter(
            name: 'distance',
            type: 'float',
            description: 'Distance in meters (0.1 to 10.0)',
            required: true,
            defaultValue: 1.0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'turn',
        description: 'Rotate robot body left or right by angle in degrees',
        parameters: [
          ToolParameter(
            name: 'direction',
            type: 'enum',
            description: 'Turn direction',
            required: true,
            enumValues: ['left', 'right'],
            defaultValue: 'left',
          ),
          ToolParameter(
            name: 'angle',
            type: 'float',
            description: 'Angle in degrees (5 to 360)',
            required: true,
            defaultValue: 45.0,
          ),
        ],
      ),
      ToolDefinition(
        name: 'camera_snapshot',
        description: 'Take a photo snapshot with the onboard robot camera',
        parameters: [],
      ),
      ToolDefinition(
        name: 'set_led',
        description: 'Turn robot status LED indicator on or off',
        parameters: [
          ToolParameter(
            name: 'on',
            type: 'bool',
            description: 'LED on/off',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'speak',
        description:
            'Synthesize speech on the robot speaker with optional volume (0.0 to 3.0)',
        parameters: [
          ToolParameter(
            name: 'text',
            type: 'string',
            description: 'Text for the robot to speak',
            required: true,
          ),
          ToolParameter(
            name: 'volume',
            type: 'float',
            description: 'Speaker volume from 0.0 to 3.0',
            required: false,
            defaultValue: 1.7,
          ),
        ],
      ),
      ToolDefinition(
        name: 'set_volume',
        description: 'Set the robot speaker volume from 0.0 to 3.0',
        parameters: [
          ToolParameter(
            name: 'volume',
            type: 'float',
            description: 'Speaker volume from 0.0 to 3.0',
            required: true,
            defaultValue: 1.7,
          ),
        ],
      ),
      ToolDefinition(
        name: 'play_tone',
        description: 'Play a musical note (e.g. C4, A4) on the robot buzzer',
        parameters: [
          ToolParameter(
            name: 'tone',
            type: 'string',
            description: 'Musical note (e.g. C4)',
            required: false,
            defaultValue: 'C4',
          ),
        ],
      ),
      ToolDefinition(
        name: 'stop_tone',
        description: 'Stop the robot tonal buzzer',
        parameters: [],
      ),
      ToolDefinition(
        name: 'stop_audio',
        description: 'Stop robot speaker audio playback',
        parameters: [],
      ),
      ToolDefinition(
        name: 'set_autonomy',
        description: 'Enable or disable autonomous robot navigation mode',
        parameters: [
          ToolParameter(
            name: 'enabled',
            type: 'bool',
            description: 'True to enable autonomy, false to disable',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'set_stabilizer',
        description: 'Enable or disable IMU active balance stabilizer',
        parameters: [
          ToolParameter(
            name: 'enabled',
            type: 'bool',
            description: 'True to enable stabilizer, false to disable',
            required: true,
          ),
        ],
      ),
      ToolDefinition(
        name: 'get_orientation',
        description: 'Read robot IMU orientation (pitch, roll, yaw)',
        parameters: [],
      ),
      ToolDefinition(
        name: 'get_telemetry',
        description: 'Query robot CPU, RAM, and temperature telemetry',
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
