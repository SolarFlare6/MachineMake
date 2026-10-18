import '../../models/dcp_models.dart';

/// Result of resolving a target device from a natural language voice prompt.
class TargetResolutionResult {
  /// The resolved target device (either extracted from the spoken phrase or fallback).
  final DeviceItem targetDevice;

  /// Whether the target device was explicitly mentioned in the user's prompt.
  final bool explicitlyMatched;

  /// The remaining action prompt with the device-targeting clause stripped out.
  /// e.g. "On the connected PC press enter" -> "press enter"
  final String cleanedActionPrompt;

  /// Diagnostic note explaining how the target was resolved.
  final String resolutionNote;

  const TargetResolutionResult({
    required this.targetDevice,
    required this.explicitlyMatched,
    required this.cleanedActionPrompt,
    required this.resolutionNote,
  });
}

/// Stage 0b: Resolves target device references in natural language prompts.
///
/// Examples:
/// - "On the connected PC press enter" -> resolves PC device, strips prefix -> "press enter"
/// - "Tell the robot to walk forward" -> resolves Robot device, strips prefix -> "walk forward"
/// - "On the Pico turn on pin 4" -> resolves Pico device, strips prefix -> "turn on pin 4"
class TargetResolver {
  TargetResolver._();

  static const Map<String, List<String>> _categoryAliases = {
    'pc': ['pc', 'computer', 'desktop', 'laptop', 'workstation', 'windows', 'mac'],
    'robot': ['robot', 'quadruped', 'dog', 'spot', 'hexapod', 'rover', 'bot'],
    'pico': ['pico', 'pi pico', 'rp2040', 'rp2350', 'microcontroller', 'mcu', 'board', 'esp32', 'arduino'],
    'sbc': ['raspberry pi', 'raspi', 'rpi', 'pi', 'sbc', 'server'],
  };

  /// Resolves which device should receive the command and returns the cleaned action prompt.
  static TargetResolutionResult resolve({
    required String rawOrNormalizedPrompt,
    required List<DeviceItem> connectedDevices,
    required DeviceItem defaultDevice,
  }) {
    final text = rawOrNormalizedPrompt.trim();
    if (text.isEmpty || connectedDevices.isEmpty) {
      return TargetResolutionResult(
        targetDevice: defaultDevice,
        explicitlyMatched: false,
        cleanedActionPrompt: text,
        resolutionNote: 'Using selected device: ${defaultDevice.name}',
      );
    }

    // Patterns that introduce a target device at the start or end of a sentence:
    // 1. Prefix: "on [the] [connected] <target>[,] <action>"
    // 2. Prefix: "tell/ask [the] [connected] <target> to <action>"
    // 3. Prefix: "for [the] [connected] <target>[,] <action>"
    // 4. Suffix: "<action> on [the] [connected] <target>"
    final prefixPatterns = [
      RegExp(
        r'^(?:on|in|at|to|for)\s+(?:the\s+|my\s+)?(?:connected\s+|active\s+|paired\s+)?([a-z0-9_\-\s]{2,28}?)(?:,\s*|\s+to\s+|\s+)(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:tell|ask|command)\s+(?:the\s+|my\s+)?(?:connected\s+|active\s+)?([a-z0-9_\-\s]{2,28}?)\s+to\s+(.+)$',
        caseSensitive: false,
      ),
    ];

    for (final pattern in prefixPatterns) {
      // Because group(1) is non-greedy, test against known device names and category aliases
      final match = _matchPrefixAgainstDevices(text, connectedDevices);
      if (match != null) {
        return match;
      }
      // Fallback regex check just in case
      final regMatch = pattern.firstMatch(text);
      if (regMatch != null) {
        final candidateTarget = regMatch.group(1)!.trim().toLowerCase();
        final remainingAction = regMatch.group(2)!.trim();
        final resolved = _findMatchingDevice(candidateTarget, connectedDevices);
        if (resolved != null && remainingAction.isNotEmpty) {
          return TargetResolutionResult(
            targetDevice: resolved,
            explicitlyMatched: true,
            cleanedActionPrompt: remainingAction,
            resolutionNote:
                'Resolved target "$candidateTarget" -> ${resolved.name}',
          );
        }
      }
    }

    // Check suffix pattern: "<action> on [the] [connected] <target>"
    final suffixMatch = _matchSuffixAgainstDevices(text, connectedDevices);
    if (suffixMatch != null) {
      return suffixMatch;
    }

    return TargetResolutionResult(
      targetDevice: defaultDevice,
      explicitlyMatched: false,
      cleanedActionPrompt: text,
      resolutionNote: 'Using default target device: ${defaultDevice.name}',
    );
  }

  static TargetResolutionResult? _matchPrefixAgainstDevices(
    String text,
    List<DeviceItem> devices,
  ) {
    final lower = text.toLowerCase();

    // Build list of candidate target phrases (exact device names + category aliases)
    final candidates = <_TargetCandidate>[];
    for (final dev in devices) {
      final devNameLower = dev.name.toLowerCase().trim();
      if (devNameLower.isNotEmpty) {
        candidates.add(_TargetCandidate(devNameLower, dev, 100));
      }
      for (final entry in _categoryAliases.entries) {
        if (_deviceMatchesCategory(dev, entry.key)) {
          for (final alias in entry.value) {
            candidates.add(_TargetCandidate(alias, dev, alias.length));
          }
        }
      }
    }

    // Sort longest alias first so "raspberry pi" matches before "pi"
    candidates.sort((a, b) => b.priority.compareTo(a.priority));

    for (final cand in candidates) {
      final escaped = RegExp.escape(cand.phrase);
      final prefixRegex = RegExp(
        '^(?:on|in|at|to|for|tell|ask|command)?\\s*(?:the\\s+|my\\s+)?(?:connected\\s+|active\\s+|paired\\s+)?$escaped(?:\\s+device|\\s+machine)?(?:,\\s*|\\s+to\\s+|\\s+)(.+)\$',
        caseSensitive: false,
      );
      final m = prefixRegex.firstMatch(lower);
      if (m != null) {
        // Slice from original text to preserve casing of any literal arguments
        final actionPart = text.substring(text.length - m.group(1)!.length).trim();
        if (actionPart.isNotEmpty) {
          return TargetResolutionResult(
            targetDevice: cand.device,
            explicitlyMatched: true,
            cleanedActionPrompt: actionPart,
            resolutionNote:
                'Resolved spoken target "${cand.phrase}" -> ${cand.device.name}',
          );
        }
      }
    }
    return null;
  }

  static TargetResolutionResult? _matchSuffixAgainstDevices(
    String text,
    List<DeviceItem> devices,
  ) {
    final lower = text.toLowerCase();
    final candidates = <_TargetCandidate>[];
    for (final dev in devices) {
      final devNameLower = dev.name.toLowerCase().trim();
      if (devNameLower.isNotEmpty) {
        candidates.add(_TargetCandidate(devNameLower, dev, 100));
      }
      for (final entry in _categoryAliases.entries) {
        if (_deviceMatchesCategory(dev, entry.key)) {
          for (final alias in entry.value) {
            candidates.add(_TargetCandidate(alias, dev, alias.length));
          }
        }
      }
    }
    candidates.sort((a, b) => b.priority.compareTo(a.priority));

    for (final cand in candidates) {
      final escaped = RegExp.escape(cand.phrase);
      final suffixRegex = RegExp(
        '^(.+?)\\s+(?:on|in|at|to|for)\\s+(?:the\\s+|my\\s+)?(?:connected\\s+|active\\s+|paired\\s+)?$escaped(?:\\s+device|\\s+machine)?\$',
        caseSensitive: false,
      );
      final m = suffixRegex.firstMatch(lower);
      if (m != null) {
        final actionLen = m.group(1)!.length;
        final actionPart = text.substring(0, actionLen).trim();
        // Avoid stripping "on" when the command is "turn on pin 4"
        if (actionPart.isNotEmpty &&
            !RegExp(r'\b(turn|set|switch)$', caseSensitive: false)
                .hasMatch(actionPart)) {
          return TargetResolutionResult(
            targetDevice: cand.device,
            explicitlyMatched: true,
            cleanedActionPrompt: actionPart,
            resolutionNote:
                'Resolved spoken suffix target "${cand.phrase}" -> ${cand.device.name}',
          );
        }
      }
    }
    return null;
  }

  static DeviceItem? _findMatchingDevice(
    String candidatePhrase,
    List<DeviceItem> devices,
  ) {
    final clean = candidatePhrase
        .replaceAll(RegExp(r'\b(connected|active|paired|the|my|device|machine)\b'), '')
        .trim();
    if (clean.isEmpty) return null;

    // 1. Exact or substring match on device name or ID
    for (final d in devices) {
      final name = d.name.toLowerCase();
      final id = d.id.toLowerCase();
      if (name == clean || name.contains(clean) || id.contains(clean)) {
        return d;
      }
    }

    // 2. Category alias match
    for (final entry in _categoryAliases.entries) {
      if (entry.value.contains(clean)) {
        for (final d in devices) {
          if (_deviceMatchesCategory(d, entry.key)) {
            return d;
          }
        }
      }
    }

    return null;
  }

  static bool _deviceMatchesCategory(DeviceItem d, String category) {
    final combined =
        '${d.name} ${d.profile} ${d.deviceType} ${d.iconKey}'.toLowerCase();
    switch (category) {
      case 'pc':
        return combined.contains('pc') ||
            combined.contains('desktop') ||
            combined.contains('laptop') ||
            combined.contains('computer') ||
            combined.contains('windows') ||
            combined.contains('workstation');
      case 'robot':
        return combined.contains('robot') ||
            combined.contains('quadruped') ||
            combined.contains('hexapod') ||
            combined.contains('rover');
      case 'pico':
        return combined.contains('pico') ||
            combined.contains('mcu') ||
            combined.contains('esp32') ||
            combined.contains('arduino') ||
            combined.contains('rp2040') ||
            combined.contains('microcontroller');
      case 'sbc':
        return combined.contains('raspberry') ||
            combined.contains('sbc') ||
            combined.contains('pi') && !combined.contains('pico');
      default:
        return false;
    }
  }
}

class _TargetCandidate {
  final String phrase;
  final DeviceItem device;
  final int priority;

  const _TargetCandidate(this.phrase, this.device, this.priority);
}
