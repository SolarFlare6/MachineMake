/// Types of asynchronous events emitted by devices.
enum DeviceEventType {
  telemetry,
  gpioChange,
  cameraFrame,
  logEntry,
  alert,
  statusChange,
  custom,
}

extension DeviceEventTypeExtension on DeviceEventType {
  String get rawValue {
    switch (this) {
      case DeviceEventType.telemetry:
        return 'telemetry';
      case DeviceEventType.gpioChange:
        return 'gpio_change';
      case DeviceEventType.cameraFrame:
        return 'camera_frame';
      case DeviceEventType.logEntry:
        return 'log_entry';
      case DeviceEventType.alert:
        return 'alert';
      case DeviceEventType.statusChange:
        return 'status_change';
      case DeviceEventType.custom:
        return 'custom';
    }
  }

  static DeviceEventType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'telemetry':
        return DeviceEventType.telemetry;
      case 'gpio_change':
        return DeviceEventType.gpioChange;
      case 'camera_frame':
        return DeviceEventType.cameraFrame;
      case 'log_entry':
        return DeviceEventType.logEntry;
      case 'alert':
        return DeviceEventType.alert;
      case 'status_change':
        return DeviceEventType.statusChange;
      default:
        return DeviceEventType.custom;
    }
  }
}

/// An asynchronous event received from a connected device.
class DeviceEvent {
  final String eventType;
  final String deviceId;
  final Map<String, dynamic> data;
  final DateTime receivedAt;

  DeviceEvent({
    required this.eventType,
    required this.deviceId,
    required this.data,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory DeviceEvent.fromJson(Map<String, dynamic> json, {String? defaultDeviceId}) {
    return DeviceEvent(
      eventType: json['event_type'] as String? ?? 'custom',
      deviceId: json['device_id'] as String? ?? defaultDeviceId ?? '',
      data: (json['data'] as Map<String, dynamic>?) ?? {},
      receivedAt: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'event_type': eventType,
        'device_id': deviceId,
        'data': data,
        'timestamp': receivedAt.toIso8601String(),
      };
}
