import 'device_profile.dart';
import 'tool_definition.dart';

/// Represents a single quick-action button shown inside a device notification.
class DeviceNotificationAction {
  final String key;
  final String label;
  final String? icon;
  final bool requiresUnlock;

  const DeviceNotificationAction({
    required this.key,
    required this.label,
    this.icon,
    this.requiresUnlock = false,
  });

  /// Alias for [key].
  String get actionKey => key;

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        if (icon != null) 'icon': icon,
        'requiresUnlock': requiresUnlock,
      };

  Map<String, dynamic> toJson() => toMap();
}

/// Payload model describing a connected device's notification card and its up to 3 quick actions.
class DeviceNotificationModel {
  final String deviceId;
  final String name;
  final String profile;
  final String statusLine;
  final bool isReconnecting;
  final List<DeviceNotificationAction> actions;

  const DeviceNotificationModel({
    required this.deviceId,
    required this.name,
    required this.profile,
    required this.statusLine,
    this.isReconnecting = false,
    required this.actions,
  });

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'name': name,
        'profile': profile,
        'statusLine': statusLine,
        'isReconnecting': isReconnecting,
        'actions': actions.take(3).map((a) => a.toMap()).toList(),
      };

  Map<String, dynamic> toJson() => toMap();

  /// Returns the default quick actions for a given [DeviceProfile].
  static List<DeviceNotificationAction> defaultActionsForProfile(DeviceProfile profile) {
    switch (profile) {
      case DeviceProfile.computer:
        return const [
          DeviceNotificationAction(
            key: 'lock_workstation',
            label: '🔒 Lock PC',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'media_play_pause',
            label: '⏯ Play/Pause',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'press_enter',
            label: '⏎ Press Enter',
            requiresUnlock: false,
          ),
        ];
      case DeviceProfile.microcontroller:
        return const [
          DeviceNotificationAction(
            key: 'led_toggle',
            label: '💡 Toggle LED',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'read_temperature',
            label: '🌡 Read Temp',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'gpio_toggle:0',
            label: '⚡ GP0 High/Low',
            requiresUnlock: false,
          ),
        ];
      case DeviceProfile.quadruped:
      case DeviceProfile.robot:
        return const [
          DeviceNotificationAction(
            key: 'sit',
            label: '🪑 Sit',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'stand',
            label: '🧍 Stand',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'emergency_stop',
            label: '🛑 E-Stop',
            requiresUnlock: false, // Safety critical: never require unlock
          ),
        ];
      case DeviceProfile.generic:
        return const [
          DeviceNotificationAction(
            key: 'ping',
            label: '📶 Ping',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'disconnect',
            label: '⏏ Disconnect',
            requiresUnlock: false,
          ),
        ];
    }
  }

  /// Returns all selectable quick actions unique to a given [DeviceProfile].
  static List<DeviceNotificationAction> availableActionsForProfile(
    DeviceProfile profile, {
    int gpioPin = 0,
  }) {
    switch (profile) {
      case DeviceProfile.computer:
        return const [
          DeviceNotificationAction(
            key: 'lock_workstation',
            label: '🔒 Lock PC',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'media_play_pause',
            label: '⏯ Play/Pause',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'press_enter',
            label: '⏎ Press Enter',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'space_key',
            label: '␣ Press Space',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'volume_mute',
            label: '🔇 Mute/Unmute',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'volume_up',
            label: '🔊 Volume Up',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'volume_down',
            label: '🔉 Volume Down',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'system_sleep',
            label: '🌙 Sleep PC',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'system_reboot',
            label: '🔄 Reboot',
            requiresUnlock: true,
          ),
          DeviceNotificationAction(
            key: 'system_shutdown',
            label: '⏻ Shutdown',
            requiresUnlock: true,
          ),
          DeviceNotificationAction(
            key: 'disconnect',
            label: '⏏ Disconnect',
            requiresUnlock: false,
          ),
        ];
      case DeviceProfile.quadruped:
      case DeviceProfile.robot:
        return const [
          DeviceNotificationAction(
            key: 'sit',
            label: '🪑 Sit',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'stand',
            label: '🧍 Stand',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'emergency_stop',
            label: '🛑 E-Stop',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'stand_sit_toggle',
            label: '🧍 Stand/Sit Toggle',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'camera_snapshot',
            label: '📷 Snapshot',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'disconnect',
            label: '⏏ Disconnect',
            requiresUnlock: false,
          ),
        ];
      case DeviceProfile.microcontroller:
        return [
          const DeviceNotificationAction(
            key: 'led_toggle',
            label: '💡 Toggle LED',
            requiresUnlock: false,
          ),
          const DeviceNotificationAction(
            key: 'read_temperature',
            label: '🌡 Read Temp',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'gpio_toggle:$gpioPin',
            label: '⚡ GP$gpioPin High/Low',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'gpio_high:$gpioPin',
            label: '⬆️ Set GP$gpioPin High',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'gpio_low:$gpioPin',
            label: '⬇️ Set GP$gpioPin Low',
            requiresUnlock: false,
          ),
          const DeviceNotificationAction(
            key: 'disconnect',
            label: '⏏ Disconnect',
            requiresUnlock: false,
          ),
        ];
      case DeviceProfile.generic:
        return const [
          DeviceNotificationAction(
            key: 'ping',
            label: '📶 Ping',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'disconnect',
            label: '⏏ Disconnect',
            requiresUnlock: false,
          ),
        ];
    }
  }

  /// Resolves a list of custom action keys (or profile defaults if null/empty) into
  /// [DeviceNotificationAction] objects.
  static List<DeviceNotificationAction> resolveActions({
    required DeviceProfile profile,
    List<String>? customActionKeys,
    List<ToolDefinition> availableTools = const [],
  }) {
    if (customActionKeys == null || customActionKeys.isEmpty) {
      return defaultActionsForProfile(profile);
    }

    final resolved = <DeviceNotificationAction>[];
    for (final key in customActionKeys.take(3)) {
      resolved.add(actionFromKey(key, availableTools: availableTools));
    }
    return resolved;
  }

  /// Maps an action key or tool name into a [DeviceNotificationAction] with display label and lock policy.
  static DeviceNotificationAction actionFromKey(
    String key, {
    List<ToolDefinition> availableTools = const [],
  }) {
    final lower = key.toLowerCase();

    // Never require unlock for emergency stop
    if (lower == 'emergency_stop' || lower == 'stop') {
      return const DeviceNotificationAction(
        key: 'emergency_stop',
        label: '🛑 E-Stop',
        requiresUnlock: false,
      );
    }

    // Dynamic GPIO pin actions (e.g., gpio_toggle:4, gpio_high:15, gpio_low:2)
    if (lower.startsWith('gpio_toggle:')) {
      final pin = int.tryParse(lower.substring('gpio_toggle:'.length)) ?? 0;
      return DeviceNotificationAction(
        key: 'gpio_toggle:$pin',
        label: '⚡ GP$pin High/Low',
        requiresUnlock: false,
      );
    }
    if (lower.startsWith('gpio_high:')) {
      final pin = int.tryParse(lower.substring('gpio_high:'.length)) ?? 0;
      return DeviceNotificationAction(
        key: 'gpio_high:$pin',
        label: '⬆️ Set GP$pin High',
        requiresUnlock: false,
      );
    }
    if (lower.startsWith('gpio_low:')) {
      final pin = int.tryParse(lower.substring('gpio_low:'.length)) ?? 0;
      return DeviceNotificationAction(
        key: 'gpio_low:$pin',
        label: '⬇️ Set GP$pin Low',
        requiresUnlock: false,
      );
    }

    // Known built-in actions
    switch (lower) {
      case 'media_play_pause':
        return const DeviceNotificationAction(
          key: 'media_play_pause',
          label: '⏯ Play/Pause',
          requiresUnlock: false,
        );
      case 'lock_workstation':
        return const DeviceNotificationAction(
          key: 'lock_workstation',
          label: '🔒 Lock PC',
          requiresUnlock: false,
        );
      case 'press_enter':
        return const DeviceNotificationAction(
          key: 'press_enter',
          label: '⏎ Press Enter',
          requiresUnlock: false,
        );
      case 'space_key':
        return const DeviceNotificationAction(
          key: 'space_key',
          label: '␣ Press Space',
          requiresUnlock: false,
        );
      case 'volume_mute':
        return const DeviceNotificationAction(
          key: 'volume_mute',
          label: '🔇 Mute/Unmute',
          requiresUnlock: false,
        );
      case 'volume_up':
        return const DeviceNotificationAction(
          key: 'volume_up',
          label: '🔊 Volume Up',
          requiresUnlock: false,
        );
      case 'volume_down':
        return const DeviceNotificationAction(
          key: 'volume_down',
          label: '🔉 Volume Down',
          requiresUnlock: false,
        );
      case 'system_sleep':
        return const DeviceNotificationAction(
          key: 'system_sleep',
          label: '🌙 Sleep PC',
          requiresUnlock: false,
        );
      case 'system_reboot':
        return const DeviceNotificationAction(
          key: 'system_reboot',
          label: '🔄 Reboot',
          requiresUnlock: true,
        );
      case 'system_shutdown':
        return const DeviceNotificationAction(
          key: 'system_shutdown',
          label: '⏻ Shutdown',
          requiresUnlock: true,
        );
      case 'led_toggle':
        return const DeviceNotificationAction(
          key: 'led_toggle',
          label: '💡 Toggle LED',
          requiresUnlock: false,
        );
      case 'read_temperature':
        return const DeviceNotificationAction(
          key: 'read_temperature',
          label: '🌡 Read Temp',
          requiresUnlock: false,
        );
      case 'stand_sit_toggle':
        return const DeviceNotificationAction(
          key: 'stand_sit_toggle',
          label: '🧍 Stand/Sit',
          requiresUnlock: false,
        );
      case 'stand':
        return const DeviceNotificationAction(
          key: 'stand',
          label: '🧍 Stand',
          requiresUnlock: false,
        );
      case 'sit':
        return const DeviceNotificationAction(
          key: 'sit',
          label: '🪑 Sit',
          requiresUnlock: false,
        );
      case 'camera_snapshot':
        return const DeviceNotificationAction(
          key: 'camera_snapshot',
          label: '📷 Snapshot',
          requiresUnlock: false,
        );
      case 'ping':
        return const DeviceNotificationAction(
          key: 'ping',
          label: '📶 Ping',
          requiresUnlock: false,
        );
      case 'disconnect':
        return const DeviceNotificationAction(
          key: 'disconnect',
          label: '⏏ Disconnect',
          requiresUnlock: false,
        );
    }

    // Check if sensitive keyword
    final isSensitive = lower.contains('shutdown') ||
        lower.contains('reboot') ||
        lower.contains('delete') ||
        lower.contains('format') ||
        lower.contains('reset');

    // Format friendly label from tool name
    final words = key.split('_').where((w) => w.isNotEmpty).map((w) {
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');

    return DeviceNotificationAction(
      key: key,
      label: words.isNotEmpty ? words : key,
      requiresUnlock: isSensitive,
    );
  }
}
