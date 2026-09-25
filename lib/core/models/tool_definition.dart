/// A single parameter for a tool invocation.
class ToolParameter {
  final String name;
  final String type; // 'string', 'int', 'float', 'bool', 'enum', 'json'
  final String description;
  final bool required;
  final dynamic defaultValue;
  final List<String>? enumValues;

  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.defaultValue,
    this.enumValues,
  });

  factory ToolParameter.fromJson(Map<String, dynamic> json) {
    return ToolParameter(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      description: json['description'] as String? ?? '',
      required: json['required'] as bool? ?? false,
      defaultValue: json['default_value'],
      enumValues: (json['enum_values'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'description': description,
        'required': required,
        if (defaultValue != null) 'default_value': defaultValue,
        if (enumValues != null) 'enum_values': enumValues,
      };
}

/// A tool exposed by a device that can be invoked remotely via DCP.
class ToolDefinition {
  final String name;
  final String description;
  final List<ToolParameter> parameters;
  final String? requiredCapability;
  final bool isAsync;
  final int? timeoutSeconds;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.parameters = const [],
    this.requiredCapability,
    this.isAsync = false,
    this.timeoutSeconds,
  });

  factory ToolDefinition.fromJson(Map<String, dynamic> json) {
    return ToolDefinition(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      parameters: (json['parameters'] as List<dynamic>?)
              ?.map((p) => ToolParameter.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      requiredCapability: json['required_capability'] as String?,
      isAsync: json['is_async'] as bool? ?? false,
      timeoutSeconds: json['timeout_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        if (requiredCapability != null)
          'required_capability': requiredCapability,
        'is_async': isAsync,
        if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
      };
}
