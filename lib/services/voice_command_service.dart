import '../core/dcp/dcp_message.dart';

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

/// Execution outcome of a voice command.
class VoiceExecutionResult {
  final bool success;
  final String userPrompt;
  final String? toolName;
  final Map<String, dynamic>? params;
  final String message;
  final DcpExecuteResponse? response;

  const VoiceExecutionResult({
    required this.success,
    required this.userPrompt,
    this.toolName,
    this.params,
    required this.message,
    this.response,
  });
}

/// Service that parses natural language voice input into DCP tool commands.
class VoiceCommandService {
  /// Parses raw transcribed text into a structured DCP command.
  static VoiceCommand? parse(String rawText, {List<String>? availableTools}) {
    final text = rawText.trim().toLowerCase();
    if (text.isEmpty) return null;

    // Helper: extracts a float from the sentence (e.g., "walk 2.5 meters", "turn 90 degrees")
    double? extractNumber() {
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
      return null;
    }

    // 1. Stand / Sit poses
    if (RegExp(r'\b(stand|stand up|get up|rise)\b').hasMatch(text)) {
      return const VoiceCommand(
        toolName: 'stand',
        parameters: {},
        description: 'Stand up',
      );
    }

    if (RegExp(r'\b(sit|sit down|rest|crouch|lay down|lie down)\b').hasMatch(text)) {
      return const VoiceCommand(
        toolName: 'sit',
        parameters: {},
        description: 'Sit down',
      );
    }

    // 2. Stop / Halt
    if (RegExp(r'\b(stop|halt|freeze|pause|stay)\b').hasMatch(text)) {
      return const VoiceCommand(
        toolName: 'stand',
        parameters: {},
        description: 'Stop moving and stand',
      );
    }

    // 3. Turning (Check before walking so "turn left" isn't hijacked by "left")
    if (text.contains('turn') || text.contains('rotate') || text.contains('spin')) {
      final isRight = text.contains('right');
      final isLeft = text.contains('left');
      final direction = isRight ? 'right' : 'left';
      final numVal = extractNumber();
      // default 45.0 degrees, clamp between 5.0 and 180.0
      final angle = (numVal != null && numVal > 0) ? numVal.clamp(5.0, 180.0) : 45.0;

      if (isRight || isLeft) {
        return VoiceCommand(
          toolName: 'turn',
          parameters: {'direction': direction, 'angle': angle},
          description: 'Turn $direction by ${angle.toInt()}°',
        );
      }
    }

    // 4. Directional Walking
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
      } else {
        direction = 'forward';
      }

      final numVal = extractNumber();
      // default 1.0 meter, clamp between 0.1 and 5.0
      final distance = (numVal != null && numVal > 0) ? numVal.clamp(0.1, 5.0) : 1.0;

      return VoiceCommand(
        toolName: 'walk',
        parameters: {'direction': direction, 'distance': distance},
        description: 'Walk $direction ${distance.toStringAsFixed(1)}m',
      );
    }

    // 5. LED / Lighting
    if (text.contains('led') || text.contains('light') || text.contains('flash')) {
      if (text.contains('off') || text.contains('disable') || text.contains('kill')) {
        return const VoiceCommand(
          toolName: 'set_led',
          parameters: {'on': false},
          description: 'Turn LED off',
        );
      }
      return const VoiceCommand(
        toolName: 'set_led',
        parameters: {'on': true},
        description: 'Turn LED on',
      );
    }

    // 6. Camera / Photos
    if (text.contains('picture') || text.contains('photo') || text.contains('snapshot') || text.contains('camera')) {
      return const VoiceCommand(
        toolName: 'take_picture',
        parameters: {},
        description: 'Capture photo',
      );
    }

    // 7. Orientation / IMU
    if (text.contains('orientation') || text.contains('imu') || text.contains('angle') || text.contains('tilt')) {
      return const VoiceCommand(
        toolName: 'get_orientation',
        parameters: {},
        description: 'Read IMU orientation',
      );
    }

    // 8. Direct matching of any registered device tool name
    if (availableTools != null) {
      for (final tool in availableTools) {
        final toolClean = tool.toLowerCase().replaceAll('_', ' ');
        if (text.contains(toolClean) || text == tool.toLowerCase()) {
          return VoiceCommand(
            toolName: tool,
            parameters: {},
            description: 'Execute tool $tool',
          );
        }
      }
    }

    return null;
  }
}
