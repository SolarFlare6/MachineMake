import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';

import 'device_transport.dart';
import '../connection/connection_state_enum.dart';

/// In-memory mock transport that simulates a full DCP device for testing and development.
class MockTransport implements DeviceTransport {
  @override
  final String deviceId;
  final String mockDeviceType;

  final StreamController<String> _incomingController =
      StreamController<String>.broadcast();
  final StreamController<DeviceConnectionState> _stateController =
      StreamController<DeviceConnectionState>.broadcast();

  bool _isConnected = false;
  Timer? _telemetryTimer;
  final Random _rng = Random();

  MockTransport({
    required this.deviceId,
    this.mockDeviceType = 'raspberry_pi',
  });

  @override
  String get transportType => 'mock';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<String> get messageStream => _incomingController.stream;

  @override
  Stream<DeviceConnectionState> get connectionStateStream => _stateController.stream;

  @override
  Future<void> connect() async {
    await Future.delayed(const Duration(milliseconds: 250));
    _isConnected = true;
    _stateController.add(DeviceConnectionState.connected);
    _startTelemetry();
  }

  void _startTelemetry() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isConnected) return;
      final telemetryMsg = jsonEncode({
        'msg_id': const Uuid().v4(),
        'type': 'event',
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        'payload': {
          'event_type': 'telemetry',
          'device_id': deviceId,
          'data': {
            'cpu': 15 + _rng.nextInt(45),
            'ram': 30 + _rng.nextInt(35),
            'gpu': 20 + _rng.nextInt(50),
            'temp': 42.0 + _rng.nextDouble() * 18.0,
          },
        },
      });
      _incomingController.add(telemetryMsg);
    });
  }

  @override
  Future<void> send(String jsonMessage) async {
    if (!_isConnected) {
      throw StateError('MockTransport is not connected');
    }

    try {
      final msg = jsonDecode(jsonMessage) as Map<String, dynamic>;
      final command = msg['command'] as String?;
      final type = msg['type'] as String? ?? '';
      final msgId = (msg['id'] ?? msg['msg_id'] ?? const Uuid().v4()).toString();
      final payload = (msg['arguments'] as Map<String, dynamic>?) ??
          (msg['payload'] as Map<String, dynamic>?) ??
          {};

      // Simulate network latency
      await Future.delayed(const Duration(milliseconds: 60));

      Map<String, dynamic> responsePayload = {};
      String responseType = '${type}_ack';

      final effectiveCommand = command ?? type;

      switch (effectiveCommand) {
        case 'get_device_info':
        case 'hello':
          responseType = 'hello_ack';
          responsePayload = {
            'device_id': deviceId,
            'name': _deviceNameForType(mockDeviceType),
            'type': mockDeviceType == 'robot' ? 'robot' : (mockDeviceType == 'raspberry_pi' ? 'raspberry_pi' : 'pico'),
            'profile': mockDeviceType == 'robot' ? 'quadruped' : (mockDeviceType == 'raspberry_pi' ? 'computer' : 'microcontroller'),
            'firmware_version': '2.1.0',
            'supported_versions': ['1.0', '1.1'],
            'ai': _aiMetadataForType(mockDeviceType),
          };
          break;

        case 'negotiate':
          responseType = 'negotiate_ack';
          responsePayload = {'selected_version': '1.0'};
          break;

        case 'authenticate':
        case 'auth':
          responseType = 'auth_ack';
          responsePayload = {
            'success': true,
            'authenticated': true,
            'session_token': 'mock_token_${const Uuid().v4().substring(0, 8)}',
          };
          break;

        case 'get_capabilities':
        case 'capabilities':
          responseType = 'capabilities_response';
          responsePayload = {'capabilities': _capabilitiesForType(mockDeviceType)};
          break;

        case 'get_tools':
        case 'tools':
          responseType = 'tools_response';
          responsePayload = {'tools': _toolsForType(mockDeviceType)};
          break;

        case 'subscribe':
        case 'subscribe_events':
          responseType = 'subscribe_ack';
          responsePayload = {'subscribed': ['telemetry', 'imu_update', 'sensor_update']};
          break;

        case 'request_control':
          responseType = 'control_ack';
          responsePayload = {'granted': true};
          break;

        case 'execute_tool':
        case 'execute':
          responseType = 'execute_response';
          final tool = (payload['tool'] ?? payload['tool_name'] ?? '').toString();
          final params = (payload['parameters'] ?? payload['params'] ?? {}) as Map<String, dynamic>;
          responsePayload = {
            'success': true,
            'tool_name': tool,
            'result': {'status': 'executed', 'output': 'Tool $tool executed successfully on $deviceId', 'params': params},
          };
          break;

        case 'ping':
          responseType = 'pong';
          responsePayload = {'timestamp': DateTime.now().millisecondsSinceEpoch};
          break;

        default:
          responseType = 'ack';
          responsePayload = {'received': effectiveCommand};
      }

      final intId = int.tryParse(msgId);
      final responseMsg = jsonEncode({
        'dcp': '1.0',
        'type': 'response',
        if (intId != null) 'id': intId else 'id': msgId,
        'msg_id': const Uuid().v4(),
        'reply_to': msgId,
        'success': true,
        'response_type': responseType,
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
        'data': responsePayload,
        'payload': responsePayload,
      });

      _incomingController.add(responseMsg);
    } catch (_) {}
  }

  String _deviceNameForType(String type) {
    switch (type) {
      case 'raspberry_pi':
        return 'Raspberry Pi 4B';
      case 'pico':
        return 'RPi Pico W';
      case 'robot':
        return 'Quadruped Bot';
      default:
        return 'MachineMake Device';
    }
  }

  Map<String, dynamic> _aiMetadataForType(String type) {
    if (type == 'pico') {
      return {
        'needle': {
          'supported': false,
          'execution': ['client'],
          'preferred': 'client',
        }
      };
    }
    return {
      'needle': {
        'supported': true,
        'execution': ['device', 'client'],
        'preferred': 'device',
      }
    };
  }

  List<Map<String, dynamic>> _capabilitiesForType(String type) {
    if (type == 'robot') {
      return [
        {'id': 'robotics', 'type': 'robotics', 'name': 'Kinematics', 'description': '4-legged IK gait engine'},
        {'id': 'gpio', 'type': 'gpio', 'name': 'GPIO', 'description': 'General Purpose I/O pins'},
        {'id': 'pwm', 'type': 'pwm', 'name': 'PWM Driver', 'description': '16-channel PCA9685'},
        {'id': 'telemetry', 'type': 'telemetry', 'name': 'Telemetry', 'description': 'IMU and load metrics'},
        {'id': 'camera', 'type': 'camera', 'name': 'Camera', 'description': 'Wide-angle navigation feed'},
        {'id': 'ai_inference', 'type': 'ai_inference', 'name': 'Needle AI', 'description': 'On-device AI reasoning engine'},
      ];
    } else if (type == 'pico') {
      return [
        {'id': 'gpio', 'type': 'gpio', 'name': 'Pico GPIO', 'description': '26 GPIO pins'},
        {'id': 'pwm', 'type': 'pwm', 'name': 'PWM Slices', 'description': '8 PWM slices'},
        {'id': 'i2c', 'type': 'i2c', 'name': 'I2C Bus', 'description': 'I2C0 & I2C1'},
      ];
    } else {
      return [
        {'id': 'gpio', 'type': 'gpio', 'name': 'BCM GPIO', 'description': '40-pin header'},
        {'id': 'pwm', 'type': 'pwm', 'name': 'Hardware PWM', 'description': '2-channel HW PWM'},
        {'id': 'camera', 'type': 'camera', 'name': 'CSI Camera', 'description': '1080p Pi Camera V2'},
        {'id': 'telemetry', 'type': 'telemetry', 'name': 'System Monitor', 'description': 'CPU/RAM/Temp telemetry'},
        {'id': 'networking', 'type': 'networking', 'name': 'WiFi & Eth', 'description': 'Gigabit + 802.11ac'},
        {'id': 'ai_inference', 'type': 'ai_inference', 'name': 'Needle AI', 'description': 'On-device AI reasoning engine'},
      ];
    }
  }

  List<Map<String, dynamic>> _toolsForType(String type) {
    final baseTools = <Map<String, dynamic>>[
      {
        'name': 'gpio_write',
        'description': 'Set state of a GPIO pin (HIGH/LOW)',
        'parameters': [
          {'name': 'pin', 'type': 'int', 'description': 'Pin number', 'required': true},
          {'name': 'state', 'type': 'bool', 'description': 'Target state', 'required': true},
        ],
        'is_async': false,
      },
      {
        'name': 'pwm_set',
        'description': 'Set duty cycle of a PWM channel',
        'parameters': [
          {'name': 'channel', 'type': 'int', 'description': 'Channel index', 'required': true},
          {'name': 'value', 'type': 'float', 'description': 'Duty cycle (0.0 to 1.0)', 'required': true},
        ],
        'is_async': false,
      },
      {
        'name': 'system_reboot',
        'description': 'Reboots the device system',
        'parameters': [],
        'is_async': true,
      },
    ];

    if (type == 'pico') {
      return baseTools;
    }

    if (type == 'robot') {
      return [
        ...baseTools,
        {
          'name': 'walk',
          'description': 'Walk in a direction for a given distance',
          'parameters': [
            {'name': 'direction', 'type': 'string', 'description': 'forward/backward/left/right', 'required': true},
            {'name': 'distance', 'type': 'float', 'description': 'Distance in meters', 'required': true},
          ],
          'is_async': false,
        },
        {
          'name': 'turn',
          'description': 'Turn in a direction by angle',
          'parameters': [
            {'name': 'direction', 'type': 'string', 'description': 'left/right', 'required': true},
            {'name': 'angle', 'type': 'float', 'description': 'Angle in degrees', 'required': true},
          ],
          'is_async': false,
        },
        {
          'name': 'stand',
          'description': 'Stand up pose',
          'parameters': [],
          'is_async': false,
        },
        {
          'name': 'sit',
          'description': 'Sit down pose',
          'parameters': [],
          'is_async': false,
        },
        {
          'name': 'set_led',
          'description': 'Turn illumination LED on or off',
          'parameters': [
            {'name': 'on', 'type': 'bool', 'description': 'LED power state', 'required': true},
          ],
          'is_async': false,
        },
        {
          'name': 'camera_snapshot',
          'description': 'Capture photo from camera',
          'parameters': [],
          'is_async': false,
        },
        {
          'name': 'needle_prompt',
          'description': 'Executes on-device Needle AI prompt',
          'parameters': [
            {'name': 'prompt', 'type': 'string', 'description': 'Natural language instruction', 'required': true},
          ],
          'is_async': false,
        },
      ];
    }

    // Raspberry Pi / PC
    return [
      ...baseTools,
      {
        'name': 'camera_snapshot',
        'description': 'Capture photo from camera',
        'parameters': [],
        'is_async': false,
      },
      {
        'name': 'needle_prompt',
        'description': 'Executes on-device Needle AI prompt',
        'parameters': [
          {'name': 'prompt', 'type': 'string', 'description': 'Natural language instruction', 'required': true},
        ],
        'is_async': false,
      },
    ];
  }

  @override
  Future<void> disconnect() async {
    _telemetryTimer?.cancel();
    _isConnected = false;
    _stateController.add(DeviceConnectionState.offline);
  }

  @override
  void dispose() {
    disconnect();
    _incomingController.close();
    _stateController.close();
  }
}
