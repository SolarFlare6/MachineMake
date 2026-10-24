import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/connection/connection_state_enum.dart';
import 'package:machmake2/core/connection/device_connection.dart';
import 'package:machmake2/core/dcp/dcp_message.dart';
import 'package:machmake2/core/discovery/discovered_device.dart';
import 'package:machmake2/core/models/device_capability.dart';
import 'package:machmake2/core/models/device_manifest.dart';
import 'package:machmake2/core/models/device_notification_model.dart';
import 'package:machmake2/core/models/device_profile.dart';
import 'package:machmake2/core/models/known_device.dart';
import 'package:machmake2/core/models/task_model.dart';
import 'package:machmake2/core/models/tool_definition.dart';
import 'package:flutter/material.dart';
import 'package:machmake2/main.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/services/app_startup_service.dart';
import 'package:machmake2/services/discovery_manager.dart';
import 'package:machmake2/services/keep_alive_service.dart';
import 'package:machmake2/widgets/ssh_dialog.dart';
import 'package:machmake2/widgets/direct_connect_dialog.dart';
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

    testWidgets('DirectConnectDialog renders and can be opened', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DirectConnectDialog.show(context),
                child: const Text('Open Direct'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Direct'));
      await tester.pumpAndSettle();

      expect(find.text('Direct IP Connect'), findsOneWidget);
      expect(find.text('Host / IP Address'), findsOneWidget);
      expect(find.text('Port'), findsOneWidget);
      expect(find.text('Device Profile:'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
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

  group('Connection Persistence & Background Quick Actions', () {
    test('DeviceConnectionState.reconnecting isConnecting and label', () {
      expect(DeviceConnectionState.reconnecting.isConnecting, isTrue);
      expect(DeviceConnectionState.reconnecting.isOperational, isFalse);
      expect(DeviceConnectionState.reconnecting.label, equals('Reconnecting...'));
    });

    test('DeviceNotificationModel resolves profile defaults and caps at 3 actions', () {
      final pcActions = DeviceNotificationModel.defaultActionsForProfile(DeviceProfile.computer);
      expect(pcActions.map((a) => a.key).toList(),
          equals(['lock_workstation', 'media_play_pause', 'press_enter']));

      final picoActions = DeviceNotificationModel.defaultActionsForProfile(DeviceProfile.microcontroller);
      expect(picoActions.map((a) => a.key).toList(),
          equals(['led_toggle', 'read_temperature', 'gpio_toggle:0']));

      final robotActions = DeviceNotificationModel.defaultActionsForProfile(DeviceProfile.quadruped);
      expect(robotActions.map((a) => a.key).toList(),
          equals(['sit', 'stand', 'emergency_stop']));
      // Safety check: emergency_stop must never require unlock
      expect(robotActions.last.requiresUnlock, isFalse);

      // Dynamic GPIO pin resolution
      final gpioCustom = DeviceNotificationModel.actionFromKey('gpio_high:14');
      expect(gpioCustom.key, equals('gpio_high:14'));
      expect(gpioCustom.label, equals('⬆️ Set GP14 High'));
      expect(gpioCustom.requiresUnlock, isFalse);

      // Custom actions resolution (truncates to max 3 and marks sensitive actions as requiresUnlock)
      final custom = DeviceNotificationModel.resolveActions(
        profile: DeviceProfile.computer,
        customActionKeys: ['emergency_stop', 'system_shutdown', 'ping', 'disconnect'],
      );
      expect(custom.length, equals(3));
      expect(custom[0].key, equals('emergency_stop'));
      expect(custom[0].requiresUnlock, isFalse);
      expect(custom[1].key, equals('system_shutdown'));
      expect(custom[1].requiresUnlock, isTrue);
      expect(custom[2].key, equals('ping'));
    });

    test('KnownDevice persists notificationActions round-trip', () {
      final now = DateTime.now();
      final dev = KnownDevice(
        deviceId: 'pico-w-01',
        name: 'Pi Pico W',
        type: 'pico',
        pairedAt: now,
        lastSeenAt: now,
        notificationActions: const ['led_toggle', 'read_temperature'],
      );

      final json = dev.toJson();
      final restored = KnownDevice.fromJson(json);
      expect(restored.notificationActions, equals(['led_toggle', 'read_temperature']));

      final cleared = restored.copyWith(clearNotificationActions: true);
      expect(cleared.notificationActions, isNull);
    });

    test('KeepAliveService invokes start, updateDevices, and stop on MethodChannel', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      KeepAliveService.debugForceEnableForTest = true;
      KeepAliveService.instance.resetForTest();

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('machinemake/keepalive'),
        (MethodCall call) async {
          calls.add(call);
          return true;
        },
      );

      final model = DeviceNotificationModel(
        deviceId: 'pico-01',
        name: 'Pi Pico W',
        profile: 'pico',
        statusLine: 'Connected · Temp 26.4°C',
        actions: DeviceNotificationModel.defaultActionsForProfile(
          DeviceProfile.microcontroller,
        ),
      );

      // First sync starts the foreground service
      await KeepAliveService.instance.sync([model], showOnLockScreen: true);
      expect(calls.length, equals(1));
      expect(calls.first.method, equals('start'));
      expect(KeepAliveService.instance.isRunning, isTrue);

      // Second sync updates devices
      await KeepAliveService.instance.sync([model], showOnLockScreen: false);
      expect(calls.length, equals(2));
      expect(calls[1].method, equals('updateDevices'));

      // Empty sync stops the foreground service
      await KeepAliveService.instance.sync(const [], showOnLockScreen: true);
      expect(calls.length, equals(3));
      expect(calls[2].method, equals('stop'));
      expect(KeepAliveService.instance.isRunning, isFalse);

      KeepAliveService.debugForceEnableForTest = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('machinemake/keepalive'),
        null,
      );
    });

    test('DeviceConnection adaptive heartbeat flags', () {
      DeviceConnection.keepAliveEnabled = true;
      DeviceConnection.isInBackground = false;
      expect(DeviceConnection.keepAliveEnabled, isTrue);
      expect(DeviceConnection.isInBackground, isFalse);
    });
  });
}

