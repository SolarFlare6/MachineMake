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
      final type = msg['type'] as String? ?? '';
      final msgId = msg['msg_id'] as String? ?? const Uuid().v4();
      final payload = (msg['payload'] as Map<String, dynamic>?) ?? {};

      // Simulate network latency
      await Future.delayed(const Duration(milliseconds: 60));

      Map<String, dynamic> responsePayload = {};
      String responseType = '${type}_ack';

      switch (type) {
        case 'hello':
          responseType = 'hello_ack';
          responsePayload = {
            'device_id': deviceId,
            'name': _deviceNameForType(mockDeviceType),
            'firmware_version': '2.1.0',
            'supported_versions': ['1.0', '1.1'],
          };
          break;

        case 'negotiate':
          responseType = 'negotiate_ack';
          responsePayload = {'selected_version': '1.0'};
          break;

        case 'auth':
          responseType = 'auth_ack';
          responsePayload = {
            'success': true,
            'session_token': 'mock_token_${const Uuid().v4().substring(0, 8)}',
          };
          break;

        case 'capabilities':
          responseType = 'capabilities_response';
          responsePayload = {'capabilities': _capabilitiesForType(mockDeviceType)};
          break;

        case 'tools':
          responseType = 'tools_response';
          responsePayload = {'tools': _toolsForType(mockDeviceType)};
          break;

        case 'execute':
          responseType = 'execute_response';
          final tool = payload['tool_name'] as String? ?? '';
          responsePayload = {
            'success': true,
            'tool_name': tool,
            'result': {'status': 'executed', 'output': 'Tool $tool executed successfully on $deviceId'},
          };
          break;

        case 'ping':
          responseType = 'pong';
          responsePayload = {'timestamp': DateTime.now().millisecondsSinceEpoch};
          break;

        default:
          responseType = 'ack';
          responsePayload = {'received': type};
      }

      final responseMsg = jsonEncode({
        'msg_id': const Uuid().v4(),
        'reply_to': msgId,
        'type': responseType,
        'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
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

  List<Map<String, dynamic>> _capabilitiesForType(String type) {
    if (type == 'robot') {
      return [
        {'id': 'robotics', 'type': 'robotics', 'name': 'Kinematics', 'description': '4-legged IK gait engine'},
        {'id': 'gpio', 'type': 'gpio', 'name': 'GPIO', 'description': 'General Purpose I/O pins'},
        {'id': 'pwm', 'type': 'pwm', 'name': 'PWM Driver', 'description': '16-channel PCA9685'},
        {'id': 'telemetry', 'type': 'telemetry', 'name': 'Telemetry', 'description': 'IMU and load metrics'},
        {'id': 'camera', 'type': 'camera', 'name': 'Camera', 'description': 'Wide-angle navigation feed'},
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
      ];
    }
  }

  List<Map<String, dynamic>> _toolsForType(String type) {
    return [
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
