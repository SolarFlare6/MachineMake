import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/dcp/dcp_message.dart';
import 'package:machmake2/core/models/device_capability.dart';
import 'package:machmake2/core/models/device_manifest.dart';
import 'package:machmake2/core/models/tool_definition.dart';
import 'package:machmake2/core/needle/needle_engine.dart';
import 'package:machmake2/core/needle/needle_models.dart';
import 'package:machmake2/models/dcp_models.dart';

void main() {
  group('NeedleCapability detection tests', () {
    test('detects microcontroller as incapable and defaults to client-side AI', () {
      final picoDev = DeviceItem(
        id: 'pico-01',
        name: 'Raspberry Pi Pico',
        profile: 'microcontroller',
        deviceType: 'Microcontroller',
        availableTransports: ['bluetooth'],
        selectedTransport: 'bluetooth',
        isPaired: true,
        isConnected: true,
        iconKey: 'pico',
      );

      final picoManifest = DeviceManifest(
        deviceId: 'pico-01',
        name: 'Pico W',
        type: 'pico',
        capabilities: const [
          DeviceCapability(id: 'gpio', type: CapabilityType.gpio, name: 'GPIO', description: ''),
        ],
        tools: const [
          ToolDefinition(name: 'gpio_write', description: ''),
        ],
      );

      final cap = NeedleCapability.fromManifest(picoManifest, picoDev);
      expect(cap.supported, isFalse);
      expect(cap.preferred, NeedleExecutionMode.client);
      expect(cap.executionModes, contains(NeedleExecutionMode.client));
      expect(cap.executionModes.contains(NeedleExecutionMode.device), isFalse);
      expect(cap.reason, contains('Microcontroller'));
    });

    test('detects capable SBC / PC as supporting on-device Needle AI', () {
      final rpiDev = DeviceItem(
        id: 'pi-01',
        name: 'Raspberry Pi 5',
        profile: 'computer',
        deviceType: 'SBC',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'rpi',
      );

      final rpiManifest = DeviceManifest(
        deviceId: 'pi-01',
        name: 'Raspberry Pi 5',
        type: 'raspberry_pi',
        capabilities: const [
          DeviceCapability(id: 'ai_inference', type: CapabilityType.aiInference, name: 'Needle AI', description: ''),
        ],
        tools: const [
          ToolDefinition(name: 'needle_prompt', description: 'Run Needle AI prompt'),
        ],
      );

      final cap = NeedleCapability.fromManifest(rpiManifest, rpiDev);
      expect(cap.supported, isTrue);
      expect(cap.preferred, NeedleExecutionMode.device);
      expect(cap.executionModes, contains(NeedleExecutionMode.device));
      expect(cap.executionModes, contains(NeedleExecutionMode.client));
    });

    test('respects explicit AI manifest metadata from device handshake', () {
      final quadManifest = DeviceManifest(
        deviceId: 'quad-01',
        name: 'Robot Dog',
        type: 'robot',
        metadata: {
          'ai': {
            'needle': {
              'supported': true,
              'execution': ['device', 'client'],
              'preferred': 'device',
            }
          }
        },
      );

      final cap = NeedleCapability.fromManifest(quadManifest, null);
      expect(cap.supported, isTrue);
      expect(cap.preferred, NeedleExecutionMode.device);
    });
  });

  group('NeedleEngine execution mode resolution', () {
    late NeedleEngine engine;

    setUp(() {
      engine = NeedleEngine(
        toolExecutor: (id, tool, params) async => DcpExecuteResponse(success: true),
      );
    });

    final mcuDevice = DeviceItem(
      id: 'esp32-01',
      name: 'ESP32 Node',
      profile: 'microcontroller',
      deviceType: 'Microcontroller',
      availableTransports: ['wifi'],
      selectedTransport: 'wifi',
      isPaired: true,
      isConnected: true,
      iconKey: 'pico',
    );

    final pcDevice = DeviceItem(
      id: 'pc-01',
      name: 'Ubuntu PC',
      profile: 'computer',
      deviceType: 'PC',
      availableTransports: ['wifi'],
      selectedTransport: 'wifi',
      isPaired: true,
      isConnected: true,
      iconKey: 'rpi',
    );

    test('resolves auto mode: client for MCU, device for PC', () {
      final mcuMode = engine.resolveExecutionMode(mcuDevice, null);
      expect(mcuMode, NeedleExecutionMode.client);

      final pcMode = engine.resolveExecutionMode(pcDevice, null);
      expect(pcMode, NeedleExecutionMode.device);
    });

    test('safely falls back to client when user requests device on incapable MCU', () {
      final resolved = engine.resolveExecutionMode(
        mcuDevice,
        null,
        requested: NeedleExecutionMode.device,
      );
      expect(resolved, NeedleExecutionMode.client);
    });

    test('respects client request even on capable PC', () {
      final resolved = engine.resolveExecutionMode(
        pcDevice,
        null,
        requested: NeedleExecutionMode.client,
      );
      expect(resolved, NeedleExecutionMode.client);
    });
  });

  group('NeedleEngine local natural language planning', () {
    late NeedleEngine engine;
    final List<ToolDefinition> robotTools = [
      const ToolDefinition(name: 'walk', description: ''),
      const ToolDefinition(name: 'turn', description: ''),
      const ToolDefinition(name: 'stand', description: ''),
      const ToolDefinition(name: 'sit', description: ''),
      const ToolDefinition(name: 'set_led', description: ''),
      const ToolDefinition(name: 'gpio_write', description: ''),
      const ToolDefinition(name: 'pwm_set', description: ''),
      const ToolDefinition(name: 'camera_snapshot', description: ''),
      const ToolDefinition(name: 'system_reboot', description: ''),
    ];

    setUp(() {
      engine = NeedleEngine(
        toolExecutor: (id, tool, params) async => DcpExecuteResponse(success: true),
      );
    });

    test('plans pose commands', () {
      final standPlan = engine.planClientSide('stand up now', robotTools);
      expect(standPlan.toolName, 'stand');
      expect(standPlan.confidence, greaterThan(0.9));

      final sitPlan = engine.planClientSide('sit down', robotTools);
      expect(sitPlan.toolName, 'sit');

      final stopPlan = engine.planClientSide('emergency halt', robotTools);
      expect(stopPlan.toolName, isIn(['stand', 'stop']));
    });

    test('plans locomotion commands with direction and distance', () {
      final fwdPlan = engine.planClientSide('walk forward 3.5 meters', robotTools);
      expect(fwdPlan.toolName, 'walk');
      expect(fwdPlan.parameters['direction'], 'forward');
      expect(fwdPlan.parameters['distance'], 3.5);

      final leftPlan = engine.planClientSide('strafe left 1.5m', robotTools);
      expect(leftPlan.toolName, 'walk');
      expect(leftPlan.parameters['direction'], 'left');
      expect(leftPlan.parameters['distance'], 1.5);

      final backPlan = engine.planClientSide('back up 0.5', robotTools);
      expect(backPlan.toolName, 'walk');
      expect(backPlan.parameters['direction'], 'backward');
      expect(backPlan.parameters['distance'], 0.5);
    });

    test('plans rotation commands with degrees', () {
      final turnPlan = engine.planClientSide('turn right 90 degrees', robotTools);
      expect(turnPlan.toolName, 'turn');
      expect(turnPlan.parameters['direction'], 'right');
      expect(turnPlan.parameters['angle'], 90.0);

      final pivotPlan = engine.planClientSide('pivot left', robotTools);
      expect(pivotPlan.toolName, 'turn');
      expect(pivotPlan.parameters['direction'], 'left');
      expect(pivotPlan.parameters['angle'], 45.0);
    });

    test('plans GPIO pin commands for hardware control', () {
      final pinOn = engine.planClientSide('turn on pin 4', robotTools);
      expect(pinOn.toolName, 'gpio_write');
      expect(pinOn.parameters['pin'], 4);
      expect(pinOn.parameters['state'], isTrue);

      final pinOff = engine.planClientSide('set gpio 23 low', robotTools);
      expect(pinOff.toolName, 'gpio_write');
      expect(pinOff.parameters['pin'], 23);
      expect(pinOff.parameters['state'], isFalse);
    });

    test('plans PWM duty cycle control', () {
      final pwmPlan = engine.planClientSide('set pwm channel 2 to 75%', robotTools);
      expect(pwmPlan.toolName, 'pwm_set');
      expect(pwmPlan.parameters['channel'], 2);
      expect(pwmPlan.parameters['value'], 0.75);
    });

    test('plans lighting and vision commands', () {
      final ledPlan = engine.planClientSide('turn on the led light', robotTools);
      expect(ledPlan.toolName, 'set_led');
      expect(ledPlan.parameters['on'], isTrue);

      final snapPlan = engine.planClientSide('take a camera snapshot', robotTools);
      expect(snapPlan.toolName, 'camera_snapshot');
    });
  });

  group('NeedleEngine end-to-end execution flow', () {
    test('runs local Needle AI for incapable device and invokes DCP tool', () async {
      String? executedTool;
      Map<String, dynamic>? executedParams;

      final engine = NeedleEngine(
        toolExecutor: (id, tool, params) async {
          executedTool = tool;
          executedParams = params;
          return DcpExecuteResponse(success: true, result: {'status': 'ok'});
        },
      );

      final picoDev = DeviceItem(
        id: 'pico-01',
        name: 'Pico',
        profile: 'microcontroller',
        deviceType: 'Microcontroller',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'pico',
      );

      final response = await engine.execute(
        device: picoDev,
        manifest: null,
        tools: const [
          ToolDefinition(name: 'gpio_write', description: ''),
        ],
        prompt: 'turn on pin 5',
      );

      expect(response.success, isTrue);
      expect(response.executedWhere, NeedleExecutionMode.client);
      expect(executedTool, 'gpio_write');
      expect(executedParams?['pin'], 5);
      expect(executedParams?['state'], isTrue);
    });

    test('runs on-device Needle AI for capable device with needle_prompt tool', () async {
      String? executedTool;
      String? promptSent;

      final engine = NeedleEngine(
        toolExecutor: (id, tool, params) async {
          executedTool = tool;
          promptSent = params['prompt'] as String?;
          return DcpExecuteResponse(
            success: true,
            result: {'output': 'Walk plan synthesized on Raspberry Pi'},
          );
        },
      );

      final rpiDev = DeviceItem(
        id: 'rpi-01',
        name: 'Raspberry Pi',
        profile: 'computer',
        deviceType: 'SBC',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'rpi',
      );

      final rpiManifest = DeviceManifest(
        deviceId: 'rpi-01',
        name: 'Raspberry Pi',
        type: 'raspberry_pi',
        capabilities: const [
          DeviceCapability(id: 'ai_inference', type: CapabilityType.aiInference, name: 'Needle AI', description: ''),
        ],
        tools: const [
          ToolDefinition(name: 'needle_prompt', description: ''),
        ],
      );

      final response = await engine.execute(
        device: rpiDev,
        manifest: rpiManifest,
        tools: rpiManifest.tools,
        prompt: 'patrol the room',
      );

      expect(response.success, isTrue);
      expect(response.executedWhere, NeedleExecutionMode.device);
      expect(executedTool, 'needle_prompt');
      expect(promptSent, 'patrol the room');
    });

    test('gracefully falls back to local AI if on-device tool is missing', () async {
      String? executedTool;

      final engine = NeedleEngine(
        toolExecutor: (id, tool, params) async {
          executedTool = tool;
          return DcpExecuteResponse(success: true, result: {'status': 'done'});
        },
      );

      final rpiDev = DeviceItem(
        id: 'rpi-01',
        name: 'Raspberry Pi',
        profile: 'computer',
        deviceType: 'SBC',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'rpi',
      );

      // Manifest lacks needle_prompt tool
      final rpiManifest = DeviceManifest(
        deviceId: 'rpi-01',
        name: 'Raspberry Pi',
        type: 'raspberry_pi',
        tools: const [
          ToolDefinition(name: 'gpio_write', description: ''),
        ],
      );

      final response = await engine.execute(
        device: rpiDev,
        manifest: rpiManifest,
        tools: rpiManifest.tools,
        prompt: 'turn on pin 4',
      );

      expect(response.success, isTrue);
      expect(response.executedWhere, NeedleExecutionMode.client);
      expect(executedTool, 'gpio_write');
    });
  });
}
