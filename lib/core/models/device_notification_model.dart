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
            key: 'media_play_pause',
            label: '⏯ Play/Pause',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'lock_workstation',
            label: '🔒 Lock PC',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
            key: 'disconnect',
            label: '⏏ Disconnect',
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
            key: 'disconnect',
            label: '⏏ Disconnect',
            requiresUnlock: false,
          ),
        ];
      case DeviceProfile.quadruped:
      case DeviceProfile.robot:
        return const [
          DeviceNotificationAction(
            key: 'emergency_stop',
            label: '🛑 STOP',
            requiresUnlock: false, // Safety critical: never require unlock
          ),
          DeviceNotificationAction(
            key: 'stand_sit_toggle',
            label: '🧍 Stand/Sit',
            requiresUnlock: false,
          ),
          DeviceNotificationAction(
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
        label: '🛑 STOP',
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
