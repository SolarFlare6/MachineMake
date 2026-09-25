import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/connection/connection_state_enum.dart';
import 'package:machmake2/core/dcp/dcp_message.dart';
import 'package:machmake2/core/discovery/discovered_device.dart';
import 'package:machmake2/core/models/device_capability.dart';
import 'package:machmake2/core/models/device_manifest.dart';
import 'package:machmake2/core/models/task_model.dart';
import 'package:machmake2/core/models/tool_definition.dart';
import 'package:machmake2/main.dart';

void main() {
  testWidgets('MachineMakeApp launches to WelcomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const MachineMakeApp());
    expect(find.text('Scan for devices'), findsOneWidget);
    expect(find.textContaining('connect, control & create'), findsOneWidget);
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
      expect(json['type'], equals('hello'));
      expect(json['payload']['client_id'], equals('client-123'));

      final restored = DcpMessage.fromJson(json);
      expect(restored.type, equals(DcpMessageType.hello));
      expect(restored.payload['app_version'], equals('1.0.0'));
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
}
