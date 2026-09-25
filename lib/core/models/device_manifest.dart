import 'device_capability.dart';
import 'tool_definition.dart';

/// Full hardware manifest describing a device, its capabilities, and its available tools.
class DeviceManifest {
  final String deviceId;
  final String name;
  final String type; // 'raspberry_pi', 'pico', 'esp32', 'arduino', 'robot', 'laptop', 'custom'
  final String firmwareVersion;
  final String protocolVersion;
  final List<DeviceCapability> capabilities;
  final List<ToolDefinition> tools;
  final Map<String, dynamic> metadata;

  const DeviceManifest({
    required this.deviceId,
    required this.name,
    required this.type,
    this.firmwareVersion = '1.0.0',
    this.protocolVersion = '1.0',
    this.capabilities = const [],
    this.tools = const [],
    this.metadata = const {},
  });

  DeviceManifest copyWith({
    String? name,
    String? firmwareVersion,
    String? protocolVersion,
    List<DeviceCapability>? capabilities,
    List<ToolDefinition>? tools,
    Map<String, dynamic>? metadata,
  }) {
    return DeviceManifest(
      deviceId: deviceId,
      name: name ?? this.name,
      type: type,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      capabilities: capabilities ?? this.capabilities,
      tools: tools ?? this.tools,
      metadata: metadata ?? this.metadata,
    );
  }

  factory DeviceManifest.fromJson(Map<String, dynamic> json) {
    return DeviceManifest(
      deviceId: json['device_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'custom',
      firmwareVersion: json['firmware_version'] as String? ?? '1.0.0',
      protocolVersion: json['protocol_version'] as String? ?? '1.0',
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((c) => DeviceCapability.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      tools: (json['tools'] as List<dynamic>?)
              ?.map((t) => ToolDefinition.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'type': type,
        'firmware_version': firmwareVersion,
        'protocol_version': protocolVersion,
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
        'tools': tools.map((t) => t.toJson()).toList(),
        'metadata': metadata,
      };
}
