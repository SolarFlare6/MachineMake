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
    // 1. Resolve payload map (could be in 'payload', 'data', or top-level)
    Map<String, dynamic> payloadMap = {};
    if (json['payload'] is Map<String, dynamic>) {
      payloadMap = json['payload'] as Map<String, dynamic>;
    } else if (json['payload'] is Map) {
      payloadMap = Map<String, dynamic>.from(json['payload'] as Map);
    } else if (json['data'] is Map<String, dynamic>) {
      payloadMap = json['data'] as Map<String, dynamic>;
    } else if (json['data'] is Map) {
      payloadMap = Map<String, dynamic>.from(json['data'] as Map);
    } else {
      payloadMap = json;
    }

    // 2. Resolve eventType
    final eventType = json['event_type']?.toString() ??
        json['event']?.toString() ??
        payloadMap['event_type']?.toString() ??
        payloadMap['event']?.toString() ??
        (json['type'] == 'event' ? null : json['type']?.toString()) ??
        'custom';

    // 3. Resolve deviceId
    final deviceId = json['device_id']?.toString() ??
        payloadMap['device_id']?.toString() ??
        json['deviceId']?.toString() ??
        payloadMap['deviceId']?.toString() ??
        defaultDeviceId ??
        '';

    // 4. Resolve data payload
    Map<String, dynamic> data = {};
    if (payloadMap.containsKey('data') && payloadMap['data'] is Map) {
      data = Map<String, dynamic>.from(payloadMap['data'] as Map);
    } else if (json.containsKey('data') && json['data'] is Map) {
      data = Map<String, dynamic>.from(json['data'] as Map);
    } else {
      data = Map<String, dynamic>.from(payloadMap);
    }

    return DeviceEvent(
      eventType: eventType,
      deviceId: deviceId,
      data: data,
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
