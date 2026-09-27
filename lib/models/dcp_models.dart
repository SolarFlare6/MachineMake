class DeviceItem {
  final String id;
  final String name;
  final String profile; // 'quadruped', 'raspberry_pi', 'pico', 'microcontroller', 'robot', 'pc'
  final String deviceType; // 'Robot', 'Raspberry Pi', 'Microcontroller', 'Laptop'
  final List<String> availableTransports; // ['wifi', 'bluetooth']
  String selectedTransport; // 'wifi' or 'bluetooth'
  bool isPaired;
  bool isConnected;
  final String iconKey; // 'quadruped', 'rpi', 'pico', 'generic'
  String? ipAddress;
  int port;
  String? macAddress;

  DeviceItem({
    required this.id,
    required this.name,
    required this.profile,
    required this.deviceType,
    required this.availableTransports,
    this.selectedTransport = 'wifi',
    this.isPaired = true,
    this.isConnected = true,
    required this.iconKey,
    this.ipAddress,
    this.port = 8765,
    this.macAddress,
  });
}

class TelemetryData {
  final double cpuUsage; // e.g. 75.0
  final double ramUsage; // e.g. 75.0
  final double gpuUsage; // e.g. 75.0
  final double temperature; // e.g. 30.0 °C

  TelemetryData({
    this.cpuUsage = 75.0,
    this.ramUsage = 75.0,
    this.gpuUsage = 75.0,
    this.temperature = 30.0,
  });

  TelemetryData copyWith({
    double? cpuUsage,
    double? ramUsage,
    double? gpuUsage,
    double? temperature,
  }) {
    return TelemetryData(
      cpuUsage: cpuUsage ?? this.cpuUsage,
      ramUsage: ramUsage ?? this.ramUsage,
      gpuUsage: gpuUsage ?? this.gpuUsage,
      temperature: temperature ?? this.temperature,
    );
  }
}

class SSHConfig {
  String hostname;
  String password;
  int port;
  String username;

  SSHConfig({
    this.hostname = '',
    this.password = '',
    this.port = 22,
    this.username = 'pi',
  });
}

class DcpCommand {
  final int id;
  final String command;
  final Map<String, dynamic> arguments;

  DcpCommand({
    required this.id,
    required this.command,
    required this.arguments,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'command': command,
        'arguments': arguments,
      };
}

class DcpResponse {
  final int id;
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  DcpResponse({
    required this.id,
    required this.success,
    this.data,
    this.error,
  });
}
