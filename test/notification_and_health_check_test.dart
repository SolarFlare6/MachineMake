import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/connection/connection_state_enum.dart';
import 'package:machmake2/core/connection/device_connection.dart';
import 'package:machmake2/core/dcp/dcp_message.dart';
import 'package:machmake2/core/dcp/dcp_session.dart';
import 'package:machmake2/core/transport/mock_transport.dart';
import 'package:machmake2/services/device_manager.dart';
import 'package:machmake2/services/notification_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NotificationService Tests', () {
    test('NotificationService emits in-app notification events', () async {
      final notifs = <InAppNotification>[];
      final sub = NotificationService.instance.inAppNotifications.listen(notifs.add);

      await NotificationService.instance.showDeviceConnectedNotification(
        deviceName: 'Quadruped Bot',
        deviceId: 'quad-01',
      );

      await NotificationService.instance.showDeviceDisconnectedNotification(
        deviceName: 'Quadruped Bot',
        deviceId: 'quad-01',
      );

      await NotificationService.instance.showSafetyAlertNotification(
        deviceName: 'Quadruped Bot',
        alertMessage: 'Emergency stop activated',
        deviceId: 'quad-01',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifs.length, 3);
      expect(notifs[0].type, 'connected');
      expect(notifs[0].title, 'Device Connected');
      expect(notifs[0].message, contains('Quadruped Bot'));

      expect(notifs[1].type, 'disconnected');
      expect(notifs[1].title, 'Device Disconnected');
      expect(notifs[1].message, contains('lost connection'));

      expect(notifs[2].type, 'alert');
      expect(notifs[2].title, contains('Safety Alert'));
      expect(notifs[2].message, contains('Emergency stop'));

      await sub.cancel();
    });
  });

  group('DCP Ping & Liveness Tests', () {
    test('DcpMessage.ping creates correct request structure', () {
      final ping = DcpMessage.ping();
      expect(ping.type, DcpMessageType.ping);
      expect(ping.command, 'ping');
      final json = ping.toJson();
      expect(json['dcp'], '1.0');
      expect(json['command'], 'ping');
    });

    test('DcpSession.ping responds with mock transport', () async {
      final transport = MockTransport(
        deviceId: 'test-device',
        mockDeviceType: 'raspberry_pi',
      );
      final session = DcpSession(
        transport: transport,
        clientId: 'client-123',
      );

      await session.connect();
      expect(session.state, DeviceConnectionState.connected);

      final isAlive = await session.ping(timeout: const Duration(seconds: 2));
      expect(isAlive, isTrue);

      await session.disconnect();
    });
  });

  group('DeviceConnection Health Check & Disconnect Tests', () {
    test('checkConnection reports true on active connection and false when offline', () async {
      final conn = DeviceConnection(deviceId: 'dev-health-1');
      expect(conn.state, DeviceConnectionState.offline);

      // Initially offline
      final offlineCheck = await conn.checkConnection();
      expect(offlineCheck, isFalse);

      // Connect via mock
      await conn.connectMock(
        mockDeviceType: 'robot',
        clientId: 'test-client',
      );
      expect(conn.state, DeviceConnectionState.connected);

      final onlineCheck = await conn.checkConnection();
      expect(onlineCheck, isTrue);

      await conn.disconnect();
      expect(conn.state, DeviceConnectionState.offline);

      final afterDisconnectCheck = await conn.checkConnection();
      expect(afterDisconnectCheck, isFalse);
    });
  });

  group('DeviceManager Disconnect Alert Setting Tests', () {
    test('toggleAlertOnDisconnect updates setting flag', () {
      final dm = DeviceManager();
      dm.toggleAlertOnDisconnect(false);
      expect(dm.alertOnDisconnect, isFalse);

      dm.toggleAlertOnDisconnect(true);
      expect(dm.alertOnDisconnect, isTrue);
    });

    test('checkAllDeviceConnections executes cleanly', () async {
      final dm = DeviceManager();
      final results = await dm.checkAllDeviceConnections();
      expect(results, isA<Map<String, bool>>());
    });
  });
}
