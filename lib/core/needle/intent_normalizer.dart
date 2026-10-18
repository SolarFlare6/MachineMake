/// Stage 0a: Speech-to-Text (STT) Normalizer.
///
/// Cleans raw speech recognition transcripts, fixes common hardware/PC STT
/// mishears, and converts spoken number words to numeric digits before routing
/// to Stage 1 (Fast Rules) or Stage 2 (Local LLM).
class IntentNormalizer {
  IntentNormalizer._();

  static const Map<String, String> _wordNumbers = {
    'zero': '0',
    'one': '1',
    'two': '2',
    'to': '2',
    'too': '2',
    'three': '3',
    'four': '4',
    'for': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'ten': '10',
    'eleven': '11',
    'twelve': '12',
    'thirteen': '13',
    'fourteen': '14',
    'fifteen': '15',
    'sixteen': '16',
    'seventeen': '17',
    'eighteen': '18',
    'nineteen': '19',
    'twenty': '20',
    'twenty five': '25',
    'thirty': '30',
    'forty': '40',
    'forty five': '45',
    'fifty': '50',
    'sixty': '60',
    'seventy': '70',
    'seventy five': '75',
    'eighty': '80',
    'ninety': '90',
    'one hundred': '100',
    'a hundred': '100',
    'one eighty': '180',
    'three sixty': '360',
  };

  /// Multi-word and single-word STT mishear corrections.
  static const Map<String, String> _sttMishearFixes = {
    'jeepio': 'gpio',
    'g p i o': 'gpio',
    'gp io': 'gpio',
    'p w m': 'pwm',
    'pee double you em': 'pwm',
    'press inter': 'press enter',
    'hit inter': 'hit enter',
    'push inter': 'push enter',
    'control see': 'ctrl+c',
    'control c': 'ctrl+c',
    'ctrl c': 'ctrl+c',
    'control vee': 'ctrl+v',
    'control v': 'ctrl+v',
    'ctrl v': 'ctrl+v',
    'control zee': 'ctrl+z',
    'control zed': 'ctrl+z',
    'control z': 'ctrl+z',
    'ctrl z': 'ctrl+z',
    'control ex': 'ctrl+x',
    'control x': 'ctrl+x',
    'ctrl x': 'ctrl+x',
    'control a': 'ctrl+a',
    'ctrl a': 'ctrl+a',
    'control s': 'ctrl+s',
    'ctrl s': 'ctrl+s',
    'alt tab': 'alt+tab',
    'alt f4': 'alt+f4',
    'alt f four': 'alt+f4',
    'windows key': 'win',
    'super key': 'win',
    'command key': 'cmd',
    'space bar': 'space',
    'spacebar': 'space',
    'back space': 'backspace',
    'page up': 'pageup',
    'page down': 'pagedown',
    'escape key': 'escape',
    'return key': 'enter',
    'enter key': 'enter',
    'tab key': 'tab',
    'delete key': 'delete',
    'up arrow': 'up',
    'down arrow': 'down',
    'left arrow': 'left',
    'right arrow': 'right',
    'arrow up': 'up',
    'arrow down': 'down',
    'arrow left': 'left',
    'arrow right': 'right',
    'shut down': 'shutdown',
    'power off': 'shutdown',
    'turn off pc': 'shutdown',
    'turn off computer': 'shutdown',
    're boot': 'reboot',
    'un mute': 'unmute',
    'next song': 'next track',
    'previous song': 'previous track',
    'last song': 'previous track',
  };

  /// Normalizes a raw speech or text prompt while preserving literal payloads
  /// for `type "..."` / `write "..."` commands.
  static String normalize(String rawPrompt) {
    if (rawPrompt.trim().isEmpty) return '';

    var text = rawPrompt.trim();

    // Check if the command is a "type <literal>" command so we don't mangle the literal text
    final typeMatch = RegExp(
      r'^(.*?)\b(type|write|input|enter text)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);

    if (typeMatch != null) {
      final prefix = _normalizeSegment(typeMatch.group(1) ?? '');
      final verb = typeMatch.group(2)!.toLowerCase();
      final literal = typeMatch.group(3)!.trim();
      return '${prefix.isEmpty ? '' : '$prefix '}$verb $literal'.trim();
    }

    return _normalizeSegment(text);
  }

  static String _normalizeSegment(String input) {
    if (input.trim().isEmpty) return '';

    var s = input.toLowerCase().trim();

    // Strip polite filler words that don't affect intent
    s = s.replaceAll(
      RegExp(r'\b(please|can you|could you|would you|hey needle|needle)\b'),
      ' ',
    );

    // Apply multi-word STT mishear fixes
    for (final entry in _sttMishearFixes.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }

    // Convert spoken compound numbers in hardware/parameter contexts
    // e.g., "pin four" -> "pin 4", "turn ninety degrees" -> "turn 90 degrees"
    final sortedKeys = _wordNumbers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final word in sortedKeys) {
      final digit = _wordNumbers[word]!;
      // Avoid replacing "to" or "for" unless preceded by "pin", "gpio", "channel", "pwm"
      if (word == 'to' || word == 'too' || word == 'for') {
        s = s.replaceAllMapped(
          RegExp('\\b(pin|gpio|channel|pwm)\\s+$word\\b'),
          (m) => '${m.group(1)} $digit',
        );
      } else {
        s = s.replaceAll(RegExp('\\b$word\\b'), digit);
      }
    }

    // Collapse multiple spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Splits a normalized prompt into multiple sub-commands if the user chained
  /// actions with "and then", "then", "after that", or "and".
  static List<String> splitMultiStep(String normalizedPrompt) {
    final trimmed = normalizedPrompt.trim();
    if (trimmed.isEmpty) return const [];

    // Special case: "type <text> and press/hit <key>"
    final typeAndPress = RegExp(
      r'^((?:type|write|input|enter text)\s+.+?)\s+(?:and then|then|and)\s+((?:press|hit|push|tap|send)\s+.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (typeAndPress != null) {
      return [
        typeAndPress.group(1)!.trim(),
        typeAndPress.group(2)!.trim(),
      ];
    }

    // Do not split arbitrary "and" inside a literal keyboard typing command
    if (RegExp(r'^(?:type|write|input|enter text)\s+', caseSensitive: false)
        .hasMatch(trimmed)) {
      return [trimmed];
    }

    final parts = trimmed
        .split(RegExp(r'\s+(?:and then|then|after that|and)\s+|,\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return parts.isEmpty ? [trimmed] : parts;
  }
}
