import '../core/models/device_event.dart';
import 'device_manager.dart';
import 'keep_alive_service.dart';

/// Executes background / lock-screen notification quick actions against
/// active [DeviceManager] DCP sessions without requiring UI navigation.
class QuickActionDispatcher {
  QuickActionDispatcher._();

  static final Map<String, bool> _picoLedState = {};
  static final Map<String, bool> _robotStandingState = {};

  static Future<void> dispatch(String deviceId, String action) async {
    final dm = DeviceManager();

    // Global action across all connected devices
    if (action == 'disconnect_all') {
      final activeIds = dm.devices.map((d) => d.id).toList();
      for (final id in activeIds) {
        dm.toggleDeviceConnection(id, false);
      }
      await KeepAliveService.instance.stop();
      return;
    }

    // Per-device disconnect
    if (action == 'disconnect') {
      dm.toggleDeviceConnection(deviceId, false);
      await dm.syncKeepAliveNotifications();
      return;
    }

    try {
      switch (action) {
        case 'emergency_stop':
          try {
            await dm.executeTool(deviceId, 'cleanup_servos', {});
          } catch (_) {}
          try {
            await dm.executeTool(deviceId, 'emergency_stop', {});
          } catch (_) {}
          dm.setNotificationFeedback(deviceId, 'EMERGENCY STOP ACTIVE');
          break;

        case 'stand_sit_toggle':
          final currentlyStanding = _robotStandingState[deviceId] ?? false;
          final nextStanding = !currentlyStanding;
          _robotStandingState[deviceId] = nextStanding;
          final toolName = nextStanding ? 'stand' : 'sit';
          try {
            await dm.executeTool(deviceId, toolName, {});
          } catch (_) {
            await dm.executeTool(deviceId, 'walk', {'direction': 'stop', 'posture': toolName});
          }
          dm.setNotificationFeedback(
            deviceId,
            nextStanding ? 'Posture: Standing' : 'Posture: Sitting',
          );
          break;

        case 'led_toggle':
          bool nextLed = !(_picoLedState[deviceId] ?? false);
          try {
            final res = await dm.executeTool(deviceId, 'set_led', {'on': nextLed});
            if (res.result is Map && (res.result as Map)['led_state'] is bool) {
              nextLed = (res.result as Map)['led_state'] as bool;
            }
          } catch (_) {
            try {
              await dm.executeTool(deviceId, 'led_toggle', {});
            } catch (_) {
              await dm.executeTool(deviceId, 'gpio_write', {'pin': 25, 'value': nextLed ? 1 : 0});
            }
          }
          _picoLedState[deviceId] = nextLed;
          dm.setNotificationFeedback(deviceId, 'Built-in LED: ${nextLed ? "ON" : "OFF"}');
          break;

        case 'read_temperature':
          double? tempC;
          try {
            final res = await dm.executeTool(deviceId, 'get_temperature', {});
            if (res.result is Map) {
              final map = res.result as Map;
              final raw = map['temperature_c'] ?? map['temp'] ?? map['temperature'];
              if (raw is num) tempC = raw.toDouble();
            } else if (res.result is num) {
              tempC = (res.result as num).toDouble();
            }
          } catch (_) {
            try {
              final res = await dm.executeTool(deviceId, 'read_temperature', {});
              if (res.result is Map) {
                final map = res.result as Map;
                final raw = map['temperature_c'] ?? map['temp'] ?? map['temperature'];
                if (raw is num) tempC = raw.toDouble();
              } else if (res.result is num) {
                tempC = (res.result as num).toDouble();
              }
            } catch (_) {}
          }
          if (tempC != null) {
            dm.updateTelemetryFromMap(deviceId, {'temp': tempC});
            dm.setNotificationFeedback(deviceId, 'Temp: ${tempC.toStringAsFixed(1)}°C');
          } else {
            dm.setNotificationFeedback(deviceId, 'Temp requested');
          }
          break;

        case 'media_play_pause':
          try {
            await dm.executeTool(deviceId, 'media_control', {'action': 'play_pause'});
          } catch (_) {
            await dm.executeTool(deviceId, 'media_play_pause', {});
          }
          dm.setNotificationFeedback(deviceId, 'Media: Play/Pause toggled');
          break;

        case 'lock_workstation':
          try {
            await dm.executeTool(deviceId, 'lock_device', {'os': 'windows'});
          } catch (_) {
            await dm.executeTool(deviceId, 'lock_workstation', {});
          }
          dm.setNotificationFeedback(deviceId, 'Workstation Locked');
          break;

        case 'ping':
          final alive = await dm.checkDeviceConnection(deviceId);
          dm.setNotificationFeedback(
            deviceId,
            alive ? 'Ping OK · Online' : 'Ping failed · Unreachable',
          );
          break;

        default:
          // Custom user-configured DCP tool name
          await dm.executeTool(deviceId, action, {});
          dm.setNotificationFeedback(deviceId, 'Executed: $action');
          break;
      }
    } catch (e) {
      dm.event.emit(DeviceEvent(
        eventType: 'alert',
        deviceId: deviceId,
        data: {
          'title': 'Quick Action Failed',
          'message': 'Could not run "$action": $e',
          'level': 'warning',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ));
    }

    await dm.syncKeepAliveNotifications();
  }
}
