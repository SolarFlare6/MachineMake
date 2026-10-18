import '../models/tool_definition.dart';
import 'intent_normalizer.dart';
import 'needle_models.dart';

/// Stage 1: Deterministic & Fuzzy Rule Intent Matcher (0 MB, < 1 ms).
///
/// Covers:
/// - PC / Desktop controls (`keyboard_press`, `keyboard_type`, `lock_device`,
///   `media_control`, `mouse_click`, `mouse_scroll`, `mouse_move`, `sleep`,
///   `reboot`, `shutdown`, `get_telemetry`)
/// - Quadruped / Robotics controls (`stand`, `sit`, `stop`, `walk`, `turn`,
///   `camera_snapshot` / `take_picture`, `get_orientation`)
/// - Pi Pico / MCU controls (`gpio_write`, `gpio_read`, `pwm_set`, `set_led`)
/// - Fuzzy matching against any dynamically registered `ToolDefinition`.
class RuleIntentMatcher {
  RuleIntentMatcher._();

  static const Set<String> _recognizedKeys = {
    'enter',
    'return',
    'space',
    'tab',
    'escape',
    'esc',
    'backspace',
    'delete',
    'del',
    'insert',
    'home',
    'end',
    'pageup',
    'pagedown',
    'up',
    'down',
    'left',
    'right',
    'win',
    'cmd',
    'capslock',
    'printscreen',
    'f1',
    'f2',
    'f3',
    'f4',
    'f5',
    'f6',
    'f7',
    'f8',
    'f9',
    'f10',
    'f11',
    'f12',
  };

  /// Matches a single or multi-step prompt using fast deterministic rules.
  static NeedlePlan match(
    String rawOrNormalizedPrompt,
    List<ToolDefinition> availableTools, {
    String? targetDeviceId,
    String? targetDeviceName,
  }) {
    final normalized = IntentNormalizer.normalize(rawOrNormalizedPrompt);
    final subPrompts = IntentNormalizer.splitMultiStep(normalized);

    if (subPrompts.length > 1) {
      final stepPlans = <NeedlePlan>[];
      for (final sub in subPrompts) {
        final subPlan = _matchSingle(
          sub,
          availableTools,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
        if (subPlan.toolName.isEmpty || subPlan.confidence < 0.75) {
          // If any step in a multi-step command cannot be confidently matched by
          // Stage 1 rules, return low confidence so Stage 2 (Local LLM) handles it.
          return NeedlePlan(
            toolName: '',
            parameters: const {},
            explanation: 'Complex multi-step command deferred to Local LLM',
            confidence: 0.2,
            thoughts: [
              'Detected multi-step prompt (${subPrompts.length} steps), but step "$sub" requires LLM reasoning.',
            ],
            source: NeedlePlanSource.rules,
            targetDeviceId: targetDeviceId,
            targetDeviceName: targetDeviceName,
          );
        }
        stepPlans.add(subPlan);
      }

      final first = stepPlans.first;
      final requiresConfirm = stepPlans.any((p) => p.requiresConfirmation);
      return NeedlePlan(
        toolName: first.toolName,
        parameters: first.parameters,
        explanation: stepPlans.map((p) => p.explanation).join(' → '),
        confidence: stepPlans
            .map((p) => p.confidence)
            .reduce((a, b) => a < b ? a : b),
        thoughts: [
          'Matched ${stepPlans.length}-step command via Stage 1 Fast Rules',
          ...stepPlans.expand((p) => p.thoughts),
        ],
        source: NeedlePlanSource.rules,
        requiresConfirmation: requiresConfirm,
        steps: stepPlans,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    return _matchSingle(
      normalized,
      availableTools,
      targetDeviceId: targetDeviceId,
      targetDeviceName: targetDeviceName,
    );
  }

  static NeedlePlan _matchSingle(
    String normalizedPrompt,
    List<ToolDefinition> availableTools, {
    String? targetDeviceId,
    String? targetDeviceName,
  }) {
    final text = normalizedPrompt.trim();
    final lower = text.toLowerCase();
    final thoughts = <String>[
      'Stage 1 (Fast Rules) analyzing: "$text"',
    ];

    final availableToolNames = availableTools.map((t) => t.name).toSet();

    // ── 1. PC Keyboard Type ("type hello world", "write git status") ────────
    final typeMatch = RegExp(
      r'^(?:type|write|input|enter text)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (typeMatch != null) {
      var literal = typeMatch.group(1)!.trim();
      // Strip surrounding quotes if present
      if ((literal.startsWith('"') && literal.endsWith('"')) ||
          (literal.startsWith("'") && literal.endsWith("'"))) {
        literal = literal.substring(1, literal.length - 1);
      }
      if (literal.isNotEmpty) {
        thoughts.add('Matched PC keyboard_type: "$literal"');
        return NeedlePlan(
          toolName: 'keyboard_type',
          parameters: {'text': literal},
          explanation: 'Typing "$literal" on ${targetDeviceName ?? "device"}',
          confidence: 0.97,
          thoughts: thoughts,
          source: NeedlePlanSource.rules,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }
    }

    // ── 2. PC Keyboard Press ("press enter", "hit escape", "press ctrl+c") ──
    final keyPressMatch = RegExp(
      r'^(?:press|hit|push|tap|send(?:\s+key)?|key)\s+(?:the\s+)?([a-z0-9\+_\-]+)(?:\s+key|\s+button)?$',
      caseSensitive: false,
    ).firstMatch(lower);
    if (keyPressMatch != null) {
      var key = keyPressMatch.group(1)!.trim().toLowerCase();
      if (key == 'return') key = 'enter';
      if (key == 'esc') key = 'escape';
      if (key == 'del') key = 'delete';

      final isCombo = key.contains('+');
      final isSingleChar = key.length == 1;
      if (_recognizedKeys.contains(key) || isCombo || isSingleChar) {
        thoughts.add('Matched PC keyboard_press: key="$key"');
        return NeedlePlan(
          toolName: 'keyboard_press',
          parameters: {'key': key},
          explanation:
              'Pressing key "${key.toUpperCase()}" on ${targetDeviceName ?? "device"}',
          confidence: 0.98,
          thoughts: thoughts,
          source: NeedlePlanSource.rules,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }
    }

    // Also support bare key commands like "enter", "escape", "ctrl+c", "alt+tab"
    if (_recognizedKeys.contains(lower) ||
        RegExp(r'^(?:ctrl|alt|shift|win|cmd)\+[a-z0-9]+$').hasMatch(lower)) {
      final key = lower == 'return'
          ? 'enter'
          : (lower == 'esc' ? 'escape' : lower);
      thoughts.add('Matched direct keyboard shortcut/key: "$key"');
      return NeedlePlan(
        toolName: 'keyboard_press',
        parameters: {'key': key},
        explanation:
            'Pressing key "${key.toUpperCase()}" on ${targetDeviceName ?? "device"}',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 3. PC Lock Screen ("lock screen", "lock pc", "lock computer") ───────
    if (RegExp(r'\b(lock|lock screen|lock pc|lock computer|lock workstation|lock device)\b')
        .hasMatch(lower)) {
      thoughts.add('Matched PC lock_device intent');
      return NeedlePlan(
        toolName: 'lock_device',
        parameters: const {},
        explanation: 'Locking ${targetDeviceName ?? "device"} screen',
        confidence: 0.97,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 4. PC Media & Volume Control ────────────────────────────────────────
    if (RegExp(r'\b(volume up|louder|increase volume|turn up volume|raise volume)\b')
        .hasMatch(lower)) {
      thoughts.add('Matched media_control: vol_up');
      return NeedlePlan(
        toolName: 'media_control',
        parameters: const {'action': 'vol_up'},
        explanation: 'Increasing volume on ${targetDeviceName ?? "device"}',
        confidence: 0.96,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(volume down|quieter|decrease volume|lower volume|turn down volume)\b')
        .hasMatch(lower)) {
      thoughts.add('Matched media_control: vol_down');
      return NeedlePlan(
        toolName: 'media_control',
        parameters: const {'action': 'vol_down'},
        explanation: 'Decreasing volume on ${targetDeviceName ?? "device"}',
        confidence: 0.96,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(mute|unmute|toggle mute|silence audio)\b').hasMatch(lower)) {
      thoughts.add('Matched media_control: mute');
      return NeedlePlan(
        toolName: 'media_control',
        parameters: const {'action': 'mute'},
        explanation: 'Toggling audio mute on ${targetDeviceName ?? "device"}',
        confidence: 0.96,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(next track|skip track|next media)\b').hasMatch(lower)) {
      thoughts.add('Matched media_control: next');
      return NeedlePlan(
        toolName: 'media_control',
        parameters: const {'action': 'next'},
        explanation: 'Skipping to next media track',
        confidence: 0.96,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(previous track|prev track|previous media)\b').hasMatch(lower)) {
      thoughts.add('Matched media_control: prev');
      return NeedlePlan(
        toolName: 'media_control',
        parameters: const {'action': 'prev'},
        explanation: 'Going to previous media track',
        confidence: 0.96,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(play media|pause media|play pause|resume media|pause music|play music|pause video|play video)\b')
            .hasMatch(lower) ||
        (availableToolNames.contains('media_control') &&
            (lower == 'play' || lower == 'pause'))) {
      thoughts.add('Matched media_control: play_pause');
      return NeedlePlan(
        toolName: 'media_control',
        parameters: const {'action': 'play_pause'},
        explanation: 'Toggling media play/pause',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 5. PC Mouse Click / Scroll / Move ───────────────────────────────────
    if (RegExp(r'\b(double click|right click|middle click|left click|click mouse)\b')
            .hasMatch(lower) ||
        lower == 'click') {
      String button = 'left';
      bool doubleClick = false;
      if (lower.contains('right')) {
        button = 'right';
      } else if (lower.contains('middle')) {
        button = 'middle';
      } else if (lower.contains('double')) {
        doubleClick = true;
      }
      final params = <String, dynamic>{'button': button};
      if (doubleClick) params['double'] = true;
      thoughts.add('Matched mouse_click: $params');
      return NeedlePlan(
        toolName: 'mouse_click',
        parameters: params,
        explanation: doubleClick
            ? 'Double-clicking mouse'
            : 'Clicking $button mouse button',
        confidence: 0.96,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (lower.contains('scroll')) {
      final isUp = lower.contains('up');
      final rawAmount = (_extractNumber(lower, defaultVal: 5.0) ?? 5.0).toInt();
      final dy = isUp ? rawAmount.abs() : -rawAmount.abs();
      thoughts.add('Matched mouse_scroll: dy=$dy');
      return NeedlePlan(
        toolName: 'mouse_scroll',
        parameters: {'dy': dy},
        explanation: 'Scrolling ${isUp ? "up" : "down"} ($rawAmount ticks)',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (lower.contains('mouse') || lower.contains('cursor')) {
      final delta = (_extractNumber(lower, defaultVal: 100.0) ?? 100.0).toInt();
      int dx = 0;
      int dy = 0;
      if (lower.contains('left')) dx = -delta;
      if (lower.contains('right')) dx = delta;
      if (lower.contains('up')) dy = -delta;
      if (lower.contains('down')) dy = delta;
      if (dx != 0 || dy != 0) {
        thoughts.add('Matched mouse_move: dx=$dx, dy=$dy');
        return NeedlePlan(
          toolName: 'mouse_move',
          parameters: {'dx': dx, 'dy': dy},
          explanation: 'Moving mouse cursor by ($dx, $dy)',
          confidence: 0.94,
          thoughts: thoughts,
          source: NeedlePlanSource.rules,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }
    }

    // ── 6. Direct GPIO Pin Control ("turn on pin 4", "set gpio 23 high") ────
    final gpioMatch = RegExp(
              r'(?:pin|gpio)\s*([0-9]{1,2})\s*(?:to\s*)?(on|off|high|low|1|0)?',
            ).firstMatch(lower) ??
        RegExp(
          r'(turn|set)\s*(?:on|off)?\s*(?:pin|gpio)\s*([0-9]{1,2})\s*(on|off|high|low|1|0)?',
        ).firstMatch(lower);

    if (gpioMatch != null) {
      final pinGroup = gpioMatch.group(1) ?? gpioMatch.group(2);
      final pin = int.tryParse(pinGroup ?? '');
      if (pin != null) {
        if (lower.contains('read') || lower.contains('status') || lower.contains('check')) {
          thoughts.add('Extracted GPIO read intent: Pin $pin');
          return NeedlePlan(
            toolName: 'gpio_read',
            parameters: {'pin': pin},
            explanation: 'Reading digital state of GPIO pin $pin',
            confidence: 0.96,
            thoughts: thoughts,
            source: NeedlePlanSource.rules,
            targetDeviceId: targetDeviceId,
            targetDeviceName: targetDeviceName,
          );
        }
        bool state = true;
        if (lower.contains('off') ||
            lower.contains('low') ||
            lower.contains(' 0') ||
            lower.contains('disable')) {
          state = false;
        }
        thoughts.add('Extracted GPIO write intent: Pin $pin -> ${state ? "HIGH" : "LOW"}');
        return NeedlePlan(
          toolName: 'gpio_write',
          parameters: {'pin': pin, 'state': state},
          explanation: 'Setting GPIO pin $pin to ${state ? 'HIGH (1)' : 'LOW (0)'}',
          confidence: 0.96,
          thoughts: thoughts,
          source: NeedlePlanSource.rules,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }
    }

    // ── 7. Direct PWM Control ("set pwm 2 to 50%", "pwm channel 0 to 0.75") ─
    final pwmMatch = RegExp(
      r'pwm\s*(?:channel\s*)?([0-9]{1,2})\s*(?:to\s*)?([0-9]+(?:\.[0-9]+)?%?)',
    ).firstMatch(lower);
    if (pwmMatch != null) {
      final channel = int.tryParse(pwmMatch.group(1) ?? '0') ?? 0;
      var rawVal = pwmMatch.group(2) ?? '0.5';
      double val;
      if (rawVal.endsWith('%')) {
        val = (double.tryParse(rawVal.replaceAll('%', '')) ?? 50.0) / 100.0;
      } else {
        val = double.tryParse(rawVal) ?? 0.5;
        if (val > 1.0 && val <= 100.0) val = val / 100.0;
      }
      val = val.clamp(0.0, 1.0);
      thoughts.add('Extracted PWM intent: Channel $channel -> ${(val * 100).toInt()}%');
      return NeedlePlan(
        toolName: 'pwm_set',
        parameters: {'channel': channel, 'value': val},
        explanation:
            'Configuring PWM channel $channel duty cycle to ${(val * 100).toInt()}%',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 8. LED / Illumination ───────────────────────────────────────────────
    if (lower.contains('led') ||
        lower.contains('light') ||
        lower.contains('torch') ||
        lower.contains('flashlight')) {
      final isOff = lower.contains('off') ||
          lower.contains('disable') ||
          lower.contains('kill') ||
          lower.contains('extinguish');
      final state = !isOff;
      final tool = availableToolNames.contains('set_led')
          ? 'set_led'
          : (availableToolNames.contains('gpio_write') ? 'gpio_write' : 'set_led');

      final params =
          tool == 'gpio_write' ? {'pin': 25, 'state': state} : {'on': state};
      thoughts.add('Detected lighting intent: LED state -> $state');
      return NeedlePlan(
        toolName: tool,
        parameters: params,
        explanation: 'Turning ${state ? "on" : "off"} device LED indicator',
        confidence: 0.93,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 9. Locomotion Poses (stand, sit, crouch, stop) ──────────────────────
    if (RegExp(r'\b(stand|stand up|get up|rise|pose stand)\b').hasMatch(lower)) {
      thoughts.add('Detected pose intent: stand up');
      return NeedlePlan(
        toolName: 'stand',
        parameters: const {},
        explanation: 'Commanding robot to assume standing posture',
        confidence: 0.98,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(sit|sit down|rest|crouch|lay down|lie down)\b').hasMatch(lower)) {
      thoughts.add('Detected pose intent: sit down');
      return NeedlePlan(
        toolName: 'sit',
        parameters: const {},
        explanation: 'Commanding robot to sit down safely',
        confidence: 0.98,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(stop|halt|freeze|stay|brake)\b').hasMatch(lower)) {
      final tool = availableToolNames.contains('stop')
          ? 'stop'
          : (availableToolNames.contains('stand') ? 'stand' : 'stop');
      thoughts.add('Detected safety intent: emergency stop / halt');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Immediately halting motion and holding position',
        confidence: 0.99,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 10. Turning / Rotation ──────────────────────────────────────────────
    final isTurningKeyword = lower.contains('rotate') ||
        lower.contains('spin') ||
        lower.contains('pivot') ||
        (lower.contains('turn') &&
            !lower.contains('turn on') &&
            !lower.contains('turn off') &&
            !lower.contains('turn up') &&
            !lower.contains('turn down'));

    if (isTurningKeyword) {
      final direction = lower.contains('right') ? 'right' : 'left';
      final degrees =
          (_extractNumber(lower, defaultVal: 45.0) ?? 45.0).clamp(5.0, 360.0);

      thoughts.add('Detected rotation intent: turn $direction by ${degrees.toInt()}°');
      return NeedlePlan(
        toolName: 'turn',
        parameters: {'direction': direction, 'angle': degrees},
        explanation: 'Executing $direction rotation by ${degrees.toInt()} degrees',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 11. Directional Walking / Movement ──────────────────────────────────
    if (lower.contains('walk') ||
        lower.contains('move') ||
        lower.contains('go') ||
        lower.contains('step') ||
        lower.contains('strafe') ||
        lower.contains('forward') ||
        lower.contains('backward') ||
        lower.contains('back') ||
        lower.contains('advance') ||
        lower.contains('reverse')) {
      String direction = 'forward';
      if (lower.contains('backward') ||
          lower.contains('back') ||
          lower.contains('reverse')) {
        direction = 'backward';
      } else if (lower.contains('left')) {
        direction = 'left';
      } else if (lower.contains('right')) {
        direction = 'right';
      }

      final distance =
          (_extractNumber(lower, defaultVal: 1.0) ?? 1.0).clamp(0.1, 10.0);
      thoughts.add(
          'Detected walking gait intent: $direction for ${distance.toStringAsFixed(1)}m');
      return NeedlePlan(
        toolName: 'walk',
        parameters: {'direction': direction, 'distance': distance},
        explanation:
            'Walking $direction for ${distance.toStringAsFixed(1)} meters',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 12. Camera / Vision Capture ─────────────────────────────────────────
    if (lower.contains('picture') ||
        lower.contains('photo') ||
        lower.contains('snapshot') ||
        lower.contains('camera')) {
      final tool = availableToolNames.contains('camera_snapshot')
          ? 'camera_snapshot'
          : (availableToolNames.contains('take_picture')
              ? 'take_picture'
              : 'camera_snapshot');
      thoughts.add('Detected vision intent: $tool');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Capturing optical snapshot from onboard camera',
        confidence: 0.94,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 13. IMU / Orientation ───────────────────────────────────────────────
    if (lower.contains('orientation') ||
        lower.contains('imu') ||
        lower.contains('tilt')) {
      thoughts.add('Detected orientation / IMU query intent');
      return NeedlePlan(
        toolName: 'get_orientation',
        parameters: const {},
        explanation: 'Reading IMU orientation telemetry',
        confidence: 0.92,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 14. System Power / Destructive Lifecycle (Sleep, Reboot, Shutdown) ──
    if (RegExp(r'\b(sleep|suspend|hibernate)\b').hasMatch(lower)) {
      thoughts.add('Detected system sleep intent');
      return NeedlePlan(
        toolName: 'sleep',
        parameters: const {},
        explanation: 'Putting ${targetDeviceName ?? "device"} to sleep',
        confidence: 0.94,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        requiresConfirmation: true,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(reboot|restart)\b').hasMatch(lower)) {
      final tool = availableToolNames.contains('system_reboot')
          ? 'system_reboot'
          : 'reboot';
      thoughts.add('Detected system reboot intent: $tool');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Initiating system reboot on ${targetDeviceName ?? "device"}',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        requiresConfirmation: true,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    if (RegExp(r'\b(shutdown|power off)\b').hasMatch(lower)) {
      final tool = availableToolNames.contains('system_shutdown')
          ? 'system_shutdown'
          : 'shutdown';
      thoughts.add('Detected system shutdown intent: $tool');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Shutting down ${targetDeviceName ?? "device"}',
        confidence: 0.95,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        requiresConfirmation: true,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 15. System Diagnostics / Telemetry ──────────────────────────────────
    if (lower.contains('battery') ||
        lower.contains('power level') ||
        lower.contains('telemetry') ||
        lower.contains('temperature') ||
        lower.contains('cpu') ||
        lower.contains('ram') ||
        lower.contains('status')) {
      final tool = availableToolNames.contains('get_telemetry')
          ? 'get_telemetry'
          : (availableToolNames.contains('system_status')
              ? 'system_status'
              : 'get_telemetry');
      thoughts.add('Detected telemetry query intent: $tool');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Polling live hardware telemetry',
        confidence: 0.91,
        thoughts: thoughts,
        source: NeedlePlanSource.rules,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
      );
    }

    // ── 16. Exact or Fuzzy Match Against Registered Tool Definitions ────────
    for (final def in availableTools) {
      final cleanName = def.name.toLowerCase().replaceAll('_', ' ');
      if (lower.contains(cleanName) || lower.contains(def.name.toLowerCase())) {
        thoughts.add('Direct matched registered tool: ${def.name}');
        final params = <String, dynamic>{};
        for (final p in def.parameters) {
          if (p.defaultValue != null) {
            params[p.name] = p.defaultValue;
          } else if (p.type == 'int') {
            final numVal = _extractNumber(lower);
            if (numVal != null) params[p.name] = numVal.toInt();
          } else if (p.type == 'float') {
            final numVal = _extractNumber(lower);
            if (numVal != null) params[p.name] = numVal;
          } else if (p.type == 'bool') {
            params[p.name] = !lower.contains('off');
          }
        }
        return NeedlePlan(
          toolName: def.name,
          parameters: params,
          explanation: 'Executing matched tool ${def.name}',
          confidence: 0.88,
          thoughts: thoughts,
          source: NeedlePlanSource.rules,
          targetDeviceId: targetDeviceId,
          targetDeviceName: targetDeviceName,
        );
      }
    }

    // Unmatched by Stage 1 Rules
    thoughts.add('Stage 1 Rules could not confidently match prompt');
    return NeedlePlan(
      toolName: '',
      parameters: const {},
      explanation: 'Prompt not matched by fast rules',
      confidence: 0.0,
      thoughts: thoughts,
      source: NeedlePlanSource.rules,
      targetDeviceId: targetDeviceId,
      targetDeviceName: targetDeviceName,
    );
  }

  static double? _extractNumber(String text, {double? defaultVal}) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? defaultVal;
    }
    return defaultVal;
  }
}
