import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/connection/connection_state_enum.dart';
import 'package:machmake2/core/dcp/dcp_message.dart';
import 'package:machmake2/core/discovery/discovered_device.dart';
import 'package:machmake2/core/models/device_capability.dart';
import 'package:machmake2/core/models/device_manifest.dart';
import 'package:machmake2/core/models/device_profile.dart';
import 'package:machmake2/core/models/task_model.dart';
import 'package:machmake2/core/models/tool_definition.dart';
import 'package:flutter/material.dart';
import 'package:machmake2/main.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/services/app_startup_service.dart';
import 'package:machmake2/services/discovery_manager.dart';
import 'package:machmake2/widgets/ssh_dialog.dart';
import 'package:machmake2/screens/ssh_terminal_screen.dart';
import 'package:machmake2/widgets/voice_cmd_dialog.dart';
import 'package:machmake2/widgets/voice_sphere.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('MachineMakeApp launches to WelcomeScreen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MachineMakeApp());
    expect(find.text('Scan for devices'), findsOneWidget);
    expect(find.textContaining('connect, control & create'), findsOneWidget);
  });

  test('AppStartupService setup done and clear data round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    AppStartupService.isFirstSetupDone = false;
    expect(AppStartupService.isFirstSetupDone, isFalse);

    await AppStartupService.setFirstSetupDone(true);
    expect(AppStartupService.isFirstSetupDone, isTrue);

    await AppStartupService.clearAllData();
    expect(AppStartupService.isFirstSetupDone, isFalse);
  });

  group('UDCF Core Models', () {
    test('DeviceConnectionState transitions', () {
      expect(DeviceConnectionState.connected.isOperational, isTrue);
      expect(DeviceConnectionState.pairing.isConnecting, isTrue);
      expect(DeviceConnectionState.offline.label, equals('Offline'));
    });

    test('DcpMessage serialization', () {
      final msg = DcpMessage.hello(
        appVersion: '1.0.0',
        protocolVersion: '1.0',
        clientId: 'client-123',
      );
      final json = msg.toJson();
      // Standard DCP 1.0 format: type='request', command field carries the name
      expect(json['type'], equals('request'));
      expect(json['command'], equals('get_device_info'));
      final args = json['arguments'] as Map<String, dynamic>;
      expect(args['client_id'], equals('client-123'));
      expect(args['app_version'], equals('1.0.0'));

      // Verify execute command format
      final execMsg = DcpMessage.execute(toolName: 'stand', params: {});
      final execJson = execMsg.toJson();
      expect(execJson['type'], equals('request'));
      expect(execJson['command'], equals('execute_tool'));
      final execArgs = execJson['arguments'] as Map<String, dynamic>;
      expect(execArgs['tool'], equals('stand'));
    });

    test('DeviceCapability json round-trip', () {
      const cap = DeviceCapability(
        id: 'gpio-01',
        type: CapabilityType.gpio,
        name: 'GPIO',
        description: 'Pin header',
      );
      final json = cap.toJson();
      final restored = DeviceCapability.fromJson(json);
      expect(restored.type, equals(CapabilityType.gpio));
      expect(restored.id, equals('gpio-01'));
    });

    test('ToolDefinition and TaskModel serialization', () {
      const tool = ToolDefinition(
        name: 'gpio_write',
        description: 'Write pin',
        parameters: [
          ToolParameter(name: 'pin', type: 'int', description: 'Pin index', required: true),
        ],
      );
      expect(tool.parameters.first.required, isTrue);

      final task = DeviceTask(
        taskId: 't-1',
        deviceId: 'dev-1',
        toolName: 'gpio_write',
        state: TaskState.running,
      );
      expect(task.state, equals(TaskState.running));
      final completed = task.copyWith(state: TaskState.completed);
      expect(completed.state, equals(TaskState.completed));
    });

    test('DeviceManifest round-trip', () {
      const manifest = DeviceManifest(
        deviceId: 'rpi-4b',
        name: 'Raspberry Pi 4B',
        type: 'raspberry_pi',
        firmwareVersion: '1.2.0',
      );
      final json = manifest.toJson();
      final restored = DeviceManifest.fromJson(json);
      expect(restored.name, equals('Raspberry Pi 4B'));
      expect(restored.deviceId, equals('rpi-4b'));
    });

    test('DiscoveredDevice multi-transport merge', () {
      final wifiDev = DiscoveredDevice(
        deviceId: 'pico-01',
        name: 'Pi Pico',
        type: 'pico',
        transports: const {'wifi'},
        ipAddress: '192.168.1.100',
        port: 8765,
      );

      final bleDev = DiscoveredDevice(
        deviceId: 'pico-01',
        name: 'Pi Pico W',
        type: 'pico',
        transports: const {'bluetooth'},
        bleAddress: 'AA:BB:CC:DD:EE:FF',
        rssi: -62,
      );

      final merged = wifiDev.mergeWith(bleDev);
      expect(merged.deviceId, equals('pico-01'));
      expect(merged.transports, containsAll(['wifi', 'bluetooth']));
      expect(merged.supportsWifi, isTrue);
      expect(merged.supportsBluetooth, isTrue);
      expect(merged.primaryTransport, equals('wifi'));
      expect(merged.ipAddress, equals('192.168.1.100'));
      expect(merged.bleAddress, equals('AA:BB:CC:DD:EE:FF'));
    });
  });

  group('Phase 4 — Device Profiles & Routing', () {
    test('DeviceProfile.fromString maps known types', () {
      expect(DeviceProfile.fromString('quadruped'), equals(DeviceProfile.quadruped));
      expect(DeviceProfile.fromString('robot'), equals(DeviceProfile.robot));
      expect(DeviceProfile.fromString('raspberry_pi'), equals(DeviceProfile.computer));
      expect(DeviceProfile.fromString('pc'), equals(DeviceProfile.computer));
      expect(DeviceProfile.fromString('laptop'), equals(DeviceProfile.computer));
      expect(DeviceProfile.fromString('pico'), equals(DeviceProfile.microcontroller));
      expect(DeviceProfile.fromString('esp32'), equals(DeviceProfile.microcontroller));
      expect(DeviceProfile.fromString('arduino'), equals(DeviceProfile.microcontroller));
      expect(DeviceProfile.fromString(null), equals(DeviceProfile.generic));
      expect(DeviceProfile.fromString('unknown_type'), equals(DeviceProfile.generic));
    });

    test('DeviceProfile.isRobot flags', () {
      expect(DeviceProfile.quadruped.isRobot, isTrue);
      expect(DeviceProfile.robot.isRobot, isTrue);
      expect(DeviceProfile.computer.isRobot, isFalse);
      expect(DeviceProfile.microcontroller.isRobot, isFalse);
      expect(DeviceProfile.generic.isRobot, isFalse);
    });

    test('DeviceProfile labels', () {
      expect(DeviceProfile.quadruped.label, equals('Quadruped Robot'));
      expect(DeviceProfile.computer.label, equals('Computer / SBC'));
      expect(DeviceProfile.microcontroller.label, equals('Microcontroller'));
      expect(DeviceProfile.generic.label, equals('Generic Device'));
    });

    test('DeviceItem model basics', () {
      final device = DeviceItem(
        id: 'test-01',
        name: 'Test Device',
        profile: 'quadruped',
        deviceType: 'Robot',
        availableTransports: ['wifi', 'bluetooth'],
        iconKey: 'quadruped',
      );
      expect(device.id, equals('test-01'));
      expect(device.profile, equals('quadruped'));
      expect(device.selectedTransport, equals('wifi'));
    });
  });

  group('Voice Command & VoiceSphere UI', () {
    testWidgets('VoiceCmdDialog handles empty devices list cleanly without crash', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceCmdDialog(
              devices: const [],
              selectedDeviceId: '',
              onCommandExecuted: (_, __) {},
            ),
          ),
        ),
      );

      // Verify no red screen / assertion crash occurs
      expect(find.text('No Connected Devices'), findsOneWidget);
      expect(find.text('Scan for Devices'), findsOneWidget);
      expect(find.text('Close'), findsWidgets);
    });

    testWidgets('VoiceCmdDialog displays connected device list', (WidgetTester tester) async {
      final testDevice = DeviceItem(
        id: 'rpi-01',
        name: 'Raspberry Pi 4',
        profile: 'raspberry_pi',
        deviceType: 'Raspberry Pi',
        availableTransports: ['wifi'],
        iconKey: 'rpi',
        isConnected: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceCmdDialog(
              devices: [testDevice],
              selectedDeviceId: 'rpi-01',
              onCommandExecuted: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('Voice Command'), findsOneWidget);
      expect(find.text('Raspberry Pi 4'), findsWidgets);
      expect(find.text('Start Listening'), findsOneWidget);
    });

    testWidgets('VoiceSphere renders with audioLevel and isListening', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceSphere(
              size: 200,
              audioLevel: 0.75,
              isListening: true,
            ),
          ),
        ),
      );

      expect(find.byType(VoiceSphere), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('SSH Shell & Terminal Window UI', () {
    test('SSHConfig stores hostname, username, password and port', () {
      final config = SSHConfig(
        hostname: '192.168.1.50',
        password: 'secret_password',
        port: 2222,
        username: 'admin',
      );
      expect(config.hostname, equals('192.168.1.50'));
      expect(config.password, equals('secret_password'));
      expect(config.port, equals(2222));
      expect(config.username, equals('admin'));
    });

    testWidgets('SSHDialog renders hostname, port, username, password fields and calls onConnectDetailed', (WidgetTester tester) async {
      String? connectedHost;
      String? connectedUser;
      String? connectedPass;
      int? connectedPort;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SSHDialog(
              initialHostname: '192.168.1.100',
              initialUsername: 'pi',
              initialPassword: 'raspberry',
              initialPort: 22,
              onConnectDetailed: (h, u, p, port) {
                connectedHost = h;
                connectedUser = u;
                connectedPass = p;
                connectedPort = port;
              },
            ),
          ),
        ),
      );

      expect(find.text('SSH Shell'), findsOneWidget);
      expect(find.text('Hostname / IP'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Connect Shell'), findsOneWidget);

      await tester.tap(find.text('Connect Shell'));
      await tester.pumpAndSettle();

      expect(connectedHost, equals('192.168.1.100'));
      expect(connectedUser, equals('pi'));
      expect(connectedPass, equals('raspberry'));
      expect(connectedPort, equals(22));
    });

    testWidgets('SshTerminalScreen renders terminal and quick keys bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SshTerminalScreen(
            host: '127.0.0.1',
            port: 22,
            username: 'pi',
            password: 'pwd',
            deviceName: 'Test Raspberry Pi',
            autoConnect: false,
          ),
        ),
      );

      expect(find.text('Test Raspberry Pi'), findsOneWidget);
      expect(find.text('ESC'), findsOneWidget);
      expect(find.text('TAB'), findsOneWidget);
      expect(find.text('Ctrl+C'), findsOneWidget);
      expect(find.text('▲'), findsOneWidget);
      expect(find.text('▼'), findsOneWidget);
    });
  });

  group('DiscoveryManager Device Deduplication', () {
    test('DiscoveryManager deduplicates emulator 10.0.2.2 alias with LAN IP', () {
      final manager = DiscoveryManager();

      // Inject device on emulator gateway (placeholder before response)
      manager.addDiscoveredDevice(DiscoveredDevice(
        deviceId: 'device-10-0-2-2-8765',
        name: 'Device (10.0.2.2)',
        type: 'computer',
        transports: const {'wifi'},
        ipAddress: '10.0.2.2',
        port: 8765,
      ));

      // Inject device with real info from LAN IP probe
      manager.addDiscoveredDevice(DiscoveredDevice(
        deviceId: 'DESKTOP-2EF22FF',
        name: 'DESKTOP-2EF22FF',
        type: 'computer',
        transports: const {'wifi'},
        ipAddress: '10.80.166.248',
        port: 8765,
      ));

      final matched = manager.discovered.where((d) => d.port == 8765).toList();
      expect(matched.length, equals(1));
      expect(matched.first.name, equals('DESKTOP-2EF22FF'));
      expect(matched.first.ipAddress, equals('10.80.166.248'));
    });
  });
}

