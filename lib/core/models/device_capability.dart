/// Capabilities supported by devices in the Universal Device Control Framework.
enum CapabilityType {
  gpio,
  pwm,
  i2c,
  spi,
  uart,
  camera,
  networking,
  storage,
  audio,
  display,
  aiInference,
  robotics,
  telemetry,
  power,
  custom,
}

extension CapabilityTypeExtension on CapabilityType {
  String get rawValue {
    switch (this) {
      case CapabilityType.gpio:
        return 'gpio';
      case CapabilityType.pwm:
        return 'pwm';
      case CapabilityType.i2c:
        return 'i2c';
      case CapabilityType.spi:
        return 'spi';
      case CapabilityType.uart:
        return 'uart';
      case CapabilityType.camera:
        return 'camera';
      case CapabilityType.networking:
        return 'networking';
      case CapabilityType.storage:
        return 'storage';
      case CapabilityType.audio:
        return 'audio';
      case CapabilityType.display:
        return 'display';
      case CapabilityType.aiInference:
        return 'ai_inference';
      case CapabilityType.robotics:
        return 'robotics';
      case CapabilityType.telemetry:
        return 'telemetry';
      case CapabilityType.power:
        return 'power';
      case CapabilityType.custom:
        return 'custom';
    }
  }

  static CapabilityType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'gpio':
        return CapabilityType.gpio;
      case 'pwm':
        return CapabilityType.pwm;
      case 'i2c':
        return CapabilityType.i2c;
      case 'spi':
        return CapabilityType.spi;
      case 'uart':
        return CapabilityType.uart;
      case 'camera':
        return CapabilityType.camera;
      case 'networking':
        return CapabilityType.networking;
      case 'storage':
        return CapabilityType.storage;
      case 'audio':
        return CapabilityType.audio;
      case 'display':
        return CapabilityType.display;
      case 'ai_inference':
      case 'aiinference':
        return CapabilityType.aiInference;
      case 'robotics':
        return CapabilityType.robotics;
      case 'telemetry':
        return CapabilityType.telemetry;
      case 'power':
        return CapabilityType.power;
      default:
        return CapabilityType.custom;
    }
  }
}

/// A specific capability descriptor provided by a device.
class DeviceCapability {
  final String id;
  final CapabilityType type;
  final String name;
  final String description;
  final Map<String, dynamic> params;
  final bool enabled;

  const DeviceCapability({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    this.params = const {},
    this.enabled = true,
  });

  factory DeviceCapability.fromAny(dynamic item) {
    if (item is String) {
      return DeviceCapability(
        id: item,
        type: CapabilityTypeExtension.fromString(item),
        name: item,
        description: '',
      );
    } else if (item is Map<String, dynamic>) {
      return DeviceCapability.fromJson(item);
    } else if (item is Map) {
      return DeviceCapability.fromJson(Map<String, dynamic>.from(item));
    }
    return DeviceCapability(
      id: item?.toString() ?? '',
      type: CapabilityType.custom,
      name: item?.toString() ?? '',
      description: '',
    );
  }

  factory DeviceCapability.fromJson(Map<String, dynamic> json) {
    return DeviceCapability(
      id: json['id'] as String? ?? '',
      type: CapabilityTypeExtension.fromString(json['type'] as String? ?? ''),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.rawValue,
        'name': name,
        'description': description,
        'params': params,
        'enabled': enabled,
      };
}
