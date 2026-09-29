import '../dcp/dcp_message.dart';
import '../models/device_manifest.dart';
import '../models/tool_definition.dart';
import '../../models/dcp_models.dart';
import 'needle_models.dart';

/// Callback type for executing a tool through the transport/session layer.
typedef ToolExecutor = Future<DcpExecuteResponse> Function(
  String deviceId,
  String toolName,
  Map<String, dynamic> params,
);

/// The Needle AI Core Engine.
///
/// Implements dual-mode AI reasoning:
/// 1. Local App AI (Client): Runs high-level reasoning locally for incapable devices
///    (e.g., microcontrollers, ESP32, Pico), extracting parameters and generating
///    structured DCP tool calls.
/// 2. On-Device AI: For capable hardware (Raspberry Pi, SBC, PC), routes the prompt
///    to the device-hosted Needle agent. Falls back gracefully to Local App AI if needed.
class NeedleEngine {
  final ToolExecutor _toolExecutor;

  NeedleEngine({required ToolExecutor toolExecutor}) : _toolExecutor = toolExecutor;

  /// Evaluates whether a device is capable of running Needle AI on-device or locally.
  NeedleCapability evaluateCapability(DeviceItem device, DeviceManifest? manifest) {
    return NeedleCapability.fromManifest(manifest, device);
  }

  /// Resolves the effective execution mode (device vs. client) based on device capability
  /// and any user preference.
  NeedleExecutionMode resolveExecutionMode(
    DeviceItem device,
    DeviceManifest? manifest, {
    NeedleExecutionMode requested = NeedleExecutionMode.auto,
  }) {
    final cap = evaluateCapability(device, manifest);

    if (requested == NeedleExecutionMode.device) {
      if (cap.supported) return NeedleExecutionMode.device;
      // If user requested device execution on an incapable device, fall back to client
      return NeedleExecutionMode.client;
    }

    if (requested == NeedleExecutionMode.client) {
      return NeedleExecutionMode.client;
    }

    // Auto resolution:
    if (cap.supported && cap.preferred == NeedleExecutionMode.device) {
      return NeedleExecutionMode.device;
    }
    return NeedleExecutionMode.client;
  }

  /// Synthesizes a structured plan from a natural language prompt against available device tools.
  NeedlePlan planClientSide(String prompt, List<ToolDefinition> availableTools) {
    final text = prompt.trim().toLowerCase();
    final thoughts = <String>[];
    thoughts.add('Analyzing prompt: "$prompt"');

    final availableToolNames = availableTools.map((t) => t.name).toSet();
    thoughts.add('Available device tools: ${availableToolNames.isEmpty ? "(none registered)" : availableToolNames.join(", ")}');

    // 1. Direct GPIO Pin Control ("turn on pin 4", "set gpio 23 high", "pin 18 off")
    final gpioMatch = RegExp(r'(?:pin|gpio)\s*([0-9]{1,2})\s*(?:to\s*)?(on|off|high|low|1|0)?').firstMatch(text) ??
        RegExp(r'(turn|set)\s*(?:on|off)?\s*(?:pin|gpio)\s*([0-9]{1,2})\s*(on|off|high|low|1|0)?').firstMatch(text);

    if (gpioMatch != null) {
      final pinGroup = gpioMatch.group(1) ?? gpioMatch.group(2);
      final pin = int.tryParse(pinGroup ?? '');
      if (pin != null) {
        bool state = true;
        if (text.contains('off') || text.contains('low') || text.contains(' 0') || text.contains('disable')) {
          state = false;
        }
        thoughts.add('Extracted GPIO intent: Pin $pin -> ${state ? "HIGH" : "LOW"}');
        return NeedlePlan(
          toolName: 'gpio_write',
          parameters: {'pin': pin, 'state': state},
          explanation: 'Setting GPIO pin $pin to ${state ? 'HIGH (1)' : 'LOW (0)'}',
          confidence: 0.96,
          thoughts: thoughts,
        );
      }
    }

    // 2. Direct PWM Control ("set pwm 2 to 50%", "pwm channel 0 to 0.75")
    final pwmMatch = RegExp(r'pwm\s*(?:channel\s*)?([0-9]{1,2})\s*(?:to\s*)?([0-9]+(?:\.[0-9]+)?%?)').firstMatch(text);
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
        explanation: 'Configuring PWM channel $channel duty cycle to ${(val * 100).toInt()}%',
        confidence: 0.94,
        thoughts: thoughts,
      );
    }

    // 3. LED / Illumination
    if (text.contains('led') || text.contains('light') || text.contains('torch') || text.contains('flashlight')) {
      final isOff = text.contains('off') || text.contains('disable') || text.contains('kill') || text.contains('extinguish');
      final state = !isOff;
      final tool = availableToolNames.contains('set_led')
          ? 'set_led'
          : (availableToolNames.contains('gpio_write') ? 'gpio_write' : 'set_led');

      final params = tool == 'gpio_write' ? {'pin': 2, 'state': state} : {'on': state};
      thoughts.add('Detected lighting intent: LED state -> $state');
      return NeedlePlan(
        toolName: tool,
        parameters: params,
        explanation: 'Turning ${state ? "on" : "off"} device LED indicator',
        confidence: 0.92,
        thoughts: thoughts,
      );
    }

    // 4. Locomotion Poses (stand, sit, crouch, stop)
    if (RegExp(r'\b(stand|stand up|get up|rise|pose stand)\b').hasMatch(text)) {
      final tool = availableToolNames.contains('stand') ? 'stand' : 'stand';
      thoughts.add('Detected pose intent: stand up');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Commanding robot to assume standing posture',
        confidence: 0.98,
        thoughts: thoughts,
      );
    }

    if (RegExp(r'\b(sit|sit down|rest|crouch|lay down|lie down)\b').hasMatch(text)) {
      final tool = availableToolNames.contains('sit') ? 'sit' : 'sit';
      thoughts.add('Detected pose intent: sit down');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Commanding robot to sit down safely',
        confidence: 0.98,
        thoughts: thoughts,
      );
    }

    if (RegExp(r'\b(stop|halt|freeze|pause|stay|brake)\b').hasMatch(text)) {
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
      );
    }

    // 5. Turning / Rotation
    final isTurningKeyword = text.contains('rotate') ||
        text.contains('spin') ||
        text.contains('pivot') ||
        (text.contains('turn') && !text.contains('turn on') && !text.contains('turn off'));

    if (isTurningKeyword) {
      final direction = text.contains('right') ? 'right' : 'left';
      final degrees = (_extractNumber(text, defaultVal: 45.0) ?? 45.0).clamp(5.0, 360.0);

      final tool = availableToolNames.contains('turn') ? 'turn' : 'turn';
      thoughts.add('Detected rotation intent: turn $direction by ${degrees.toInt()}°');
      return NeedlePlan(
        toolName: tool,
        parameters: {'direction': direction, 'angle': degrees},
        explanation: 'Executing $direction rotation by ${degrees.toInt()} degrees',
        confidence: 0.95,
        thoughts: thoughts,
      );
    }

    // 6. Directional Walking / Movement
    if (text.contains('walk') ||
        text.contains('move') ||
        text.contains('go') ||
        text.contains('step') ||
        text.contains('strafe') ||
        text.contains('forward') ||
        text.contains('backward') ||
        text.contains('back') ||
        text.contains('advance') ||
        text.contains('reverse')) {
      String direction = 'forward';
      if (text.contains('backward') || text.contains('back') || text.contains('reverse')) {
        direction = 'backward';
      } else if (text.contains('left')) {
        direction = 'left';
      } else if (text.contains('right')) {
        direction = 'right';
      }

      final distance = (_extractNumber(text, defaultVal: 1.0) ?? 1.0).clamp(0.1, 10.0);
      final tool = availableToolNames.contains('walk') ? 'walk' : 'walk';
      thoughts.add('Detected walking gait intent: $direction for ${distance.toStringAsFixed(1)}m');
      return NeedlePlan(
        toolName: tool,
        parameters: {'direction': direction, 'distance': distance},
        explanation: 'Walking $direction for ${distance.toStringAsFixed(1)} meters',
        confidence: 0.95,
        thoughts: thoughts,
      );
    }

    // 7. Camera / Vision Capture
    if (text.contains('picture') || text.contains('photo') || text.contains('snapshot') || text.contains('camera')) {
      final tool = availableToolNames.contains('camera_snapshot')
          ? 'camera_snapshot'
          : (availableToolNames.contains('take_picture') ? 'take_picture' : 'camera_snapshot');
      thoughts.add('Detected vision intent: camera snapshot');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Capturing optical snapshot from onboard camera',
        confidence: 0.93,
        thoughts: thoughts,
      );
    }

    // 8. System Diagnostics / Telemetry / Reboot
    if (text.contains('reboot') || text.contains('restart')) {
      final tool = availableToolNames.contains('system_reboot') ? 'system_reboot' : 'reboot';
      thoughts.add('Detected system lifecycle intent: reboot');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Initiating safe device system reboot',
        confidence: 0.95,
        thoughts: thoughts,
      );
    }

    if (text.contains('battery') || text.contains('power level') || text.contains('telemetry') || text.contains('status')) {
      final tool = availableToolNames.contains('get_telemetry') ? 'get_telemetry' : 'get_telemetry';
      thoughts.add('Detected telemetry query intent');
      return NeedlePlan(
        toolName: tool,
        parameters: const {},
        explanation: 'Polling live device hardware telemetry',
        confidence: 0.90,
        thoughts: thoughts,
      );
    }

    // 9. Exact or fuzzy match against registered tool definitions
    for (final def in availableTools) {
      final cleanName = def.name.toLowerCase().replaceAll('_', ' ');
      if (text.contains(cleanName) || text.contains(def.name.toLowerCase())) {
        thoughts.add('Direct matched registered tool: ${def.name}');
        final params = <String, dynamic>{};
        // Auto-extract required parameter defaults if simple
        for (final p in def.parameters) {
          if (p.defaultValue != null) {
            params[p.name] = p.defaultValue;
          } else if (p.type == 'int') {
            final numVal = _extractNumber(text);
            if (numVal != null) params[p.name] = numVal.toInt();
          } else if (p.type == 'float') {
            final numVal = _extractNumber(text);
            if (numVal != null) params[p.name] = numVal;
          } else if (p.type == 'bool') {
            params[p.name] = !text.contains('off');
          }
        }
        return NeedlePlan(
          toolName: def.name,
          parameters: params,
          explanation: 'Executing matched tool ${def.name}',
          confidence: 0.88,
          thoughts: thoughts,
        );
      }
    }

    // Unmatched
    thoughts.add('Could not map prompt to an existing tool');
    return NeedlePlan(
      toolName: '',
      parameters: const {},
      explanation: 'Prompt not understood',
      confidence: 0.0,
      thoughts: thoughts,
    );
  }

  /// Executes a natural language command by routing either on-device or locally in-app.
  Future<NeedleResponse> execute({
    required DeviceItem device,
    required DeviceManifest? manifest,
    required List<ToolDefinition> tools,
    required String prompt,
    NeedleExecutionMode mode = NeedleExecutionMode.auto,
  }) async {
    final effectiveMode = resolveExecutionMode(device, manifest, requested: mode);

    if (effectiveMode == NeedleExecutionMode.device) {
      return await _executeOnDevice(device, manifest, tools, prompt);
    } else {
      return await _executeLocally(device, tools, prompt);
    }
  }

  /// Executes Local App AI (Client-side reasoning) and dispatches DCP tool call.
  Future<NeedleResponse> _executeLocally(
    DeviceItem device,
    List<ToolDefinition> tools,
    String prompt,
  ) async {
    final plan = planClientSide(prompt, tools);

    if (plan.toolName.isEmpty || plan.confidence < 0.3) {
      return NeedleResponse(
        success: false,
        userPrompt: prompt,
        executedWhere: NeedleExecutionMode.client,
        plan: plan,
        message: 'Needle AI: Unrecognized command. Try "walk forward", "turn left", "pin 4 on", or "take picture".',
      );
    }

    try {
      final response = await _toolExecutor(device.id, plan.toolName, plan.parameters);
      if (response.success) {
        return NeedleResponse(
          success: true,
          userPrompt: prompt,
          executedWhere: NeedleExecutionMode.client,
          plan: plan,
          message: '${plan.explanation} (${plan.toolName})',
          result: response.result,
        );
      } else {
        return NeedleResponse(
          success: false,
          userPrompt: prompt,
          executedWhere: NeedleExecutionMode.client,
          plan: plan,
          message: response.error ?? 'Execution rejected by device',
          error: response.error,
          result: response.result,
        );
      }
    } catch (e) {
      return NeedleResponse(
        success: false,
        userPrompt: prompt,
        executedWhere: NeedleExecutionMode.client,
        plan: plan,
        message: 'Local Needle AI execution error: $e',
        error: e.toString(),
      );
    }
  }

  /// Attempts to run Needle on-device; if unavailable or fails, falls back gracefully to local AI.
  Future<NeedleResponse> _executeOnDevice(
    DeviceItem device,
    DeviceManifest? manifest,
    List<ToolDefinition> tools,
    String prompt,
  ) async {
    final hasDevicePromptTool = tools.any((t) => t.name == 'needle_prompt' || t.name == 'ai_prompt');

    if (!hasDevicePromptTool) {
      // Device doesn't expose needle_prompt tool; automatically fallback to local execution
      final localResult = await _executeLocally(device, tools, prompt);
      return NeedleResponse(
        success: localResult.success,
        userPrompt: prompt,
        executedWhere: NeedleExecutionMode.client,
        plan: localResult.plan,
        message: '${localResult.message} [Local Fallback: on-device prompt tool not registered]',
        result: localResult.result,
        error: localResult.error,
      );
    }

    final toolName = tools.any((t) => t.name == 'needle_prompt') ? 'needle_prompt' : 'ai_prompt';

    try {
      final response = await _toolExecutor(device.id, toolName, {'prompt': prompt});
      if (response.success) {
        String msg = 'Needle AI processed command on device';
        if (response.result is Map && response.result['message'] != null) {
          msg = response.result['message'].toString();
        } else if (response.result is Map && response.result['output'] != null) {
          msg = response.result['output'].toString();
        }
        return NeedleResponse(
          success: true,
          userPrompt: prompt,
          executedWhere: NeedleExecutionMode.device,
          plan: NeedlePlan(
            toolName: toolName,
            parameters: {'prompt': prompt},
            explanation: msg,
            confidence: 1.0,
            thoughts: ['Prompt dispatched directly to device-side Needle AI engine'],
          ),
          message: msg,
          result: response.result,
        );
      } else {
        // Fall back to client side
        final localResult = await _executeLocally(device, tools, prompt);
        return NeedleResponse(
          success: localResult.success,
          userPrompt: prompt,
          executedWhere: NeedleExecutionMode.client,
          plan: localResult.plan,
          message: '${localResult.message} [Fell back to Local App AI: ${response.error ?? "Device error"}]',
          result: localResult.result,
          error: localResult.error,
        );
      }
    } catch (e) {
      // Fallback to client
      final localResult = await _executeLocally(device, tools, prompt);
      return NeedleResponse(
        success: localResult.success,
        userPrompt: prompt,
        executedWhere: NeedleExecutionMode.client,
        plan: localResult.plan,
        message: '${localResult.message} [Fell back to Local App AI: $e]',
        result: localResult.result,
        error: localResult.error,
      );
    }
  }

  double? _extractNumber(String text, {double? defaultVal}) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? defaultVal;
    }
    return defaultVal;
  }
}
