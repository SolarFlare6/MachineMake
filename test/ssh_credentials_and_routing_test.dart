import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/models/known_device.dart';
import 'package:machmake2/core/routing/profile_router.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/screens/generic/generic_device_dashboard_screen.dart';
import 'package:machmake2/screens/robot/quadruped_dashboard_screen.dart';
import 'package:machmake2/services/device_manager.dart';
import 'package:machmake2/services/device_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileRouter Routing Tests', () {
    test('routes quadruped to QuadrupedDashboardScreen', () {
      final dev = DeviceItem(
        id: 'robot-01',
        name: 'Quad Bot',
        profile: 'quadruped',
        deviceType: 'Quadruped Robot',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'quadruped',
      );
      final widget = ProfileRouter.buildProfileUI(dev);
      expect(widget, isA<QuadrupedDashboardScreen>());
    });

    test('routes robot to QuadrupedDashboardScreen', () {
      final dev = DeviceItem(
        id: 'robot-02',
        name: 'Hex Bot',
        profile: 'robot',
        deviceType: 'Robot',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'quadruped',
      );
      final widget = ProfileRouter.buildProfileUI(dev);
      expect(widget, isA<QuadrupedDashboardScreen>());
    });

    test('routes computer / raspberry_pi to GenericDeviceDashboardScreen', () {
      final dev = DeviceItem(
        id: 'pi-01',
        name: 'Raspberry Pi',
        profile: 'raspberry_pi',
        deviceType: 'Raspberry Pi',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'rpi',
      );
      final widget = ProfileRouter.buildProfileUI(dev);
      expect(widget, isA<GenericDeviceDashboardScreen>());
    });

    test('routes microcontroller to GenericDeviceDashboardScreen', () {
      final dev = DeviceItem(
        id: 'pico-01',
        name: 'Raspberry Pi Pico',
        profile: 'pico',
        deviceType: 'Microcontroller',
        availableTransports: ['bluetooth'],
        selectedTransport: 'bluetooth',
        isPaired: true,
        isConnected: true,
        iconKey: 'pico',
      );
      final widget = ProfileRouter.buildProfileUI(dev);
      expect(widget, isA<GenericDeviceDashboardScreen>());
    });

    test('routes generic / unknown devices to GenericDeviceDashboardScreen', () {
      final dev = DeviceItem(
        id: 'gen-01',
        name: 'Custom Device',
        profile: 'custom_sensor',
        deviceType: 'Sensor',
        availableTransports: ['wifi'],
        selectedTransport: 'wifi',
        isPaired: true,
        isConnected: true,
        iconKey: 'device',
      );
      final widget = ProfileRouter.buildProfileUI(dev);
      expect(widget, isA<GenericDeviceDashboardScreen>());
    });
  });

  group('KnownDevice SSH Persistence Tests', () {
    test('serializes and deserializes SSH credentials properly', () {
      final device = KnownDevice(
        deviceId: 'pi-4',
        name: 'Living Room Pi',
        type: 'raspberry_pi',
        lastIp: '192.168.1.150',
        sshUsername: 'pi',
        sshPassword: 'secretpassword',
        sshPort: 2222,
      );

      final json = device.toJson();
      expect(json['ssh_username'], 'pi');
      expect(json['ssh_password'], 'secretpassword');
      expect(json['ssh_port'], 2222);

      final restored = KnownDevice.fromJson(json);
      expect(restored.sshUsername, 'pi');
      expect(restored.sshPassword, 'secretpassword');
      expect(restored.sshPort, 2222);
    });

    test('copyWith updates and clears SSH credentials properly', () {
      final device = KnownDevice(
        deviceId: 'pi-4',
        name: 'Living Room Pi',
        type: 'raspberry_pi',
        sshUsername: 'pi',
        sshPassword: 'secretpassword',
        sshPort: 22,
      );

      final updated = device.copyWith(
        sshUsername: 'admin',
        sshPassword: 'newpassword',
        sshPort: 2200,
      );
      expect(updated.sshUsername, 'admin');
      expect(updated.sshPassword, 'newpassword');
      expect(updated.sshPort, 2200);

      final cleared = updated.copyWith(clearSsh: true);
      expect(cleared.sshUsername, isNull);
      expect(cleared.sshPassword, isNull);
      expect(cleared.sshPort, isNull);
    });
  });

  group('DeviceManager SSH Credentials Management Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and removes SSH credentials for a device', () async {
      final manager = DeviceManager();
      final registry = DeviceRegistry();

      final known = KnownDevice(
        deviceId: 'test-device-99',
        name: 'Test Device',
        type: 'raspberry_pi',
        lastIp: '192.168.1.88',
      );
      await registry.addOrUpdate(known);

      expect(manager.hasSavedSshCredentials('test-device-99'), isFalse);

      await manager.saveSshCredentials(
        'test-device-99',
        username: 'ubuntu',
        password: 'mysecurepassword',
        port: 22,
      );

      expect(manager.hasSavedSshCredentials('test-device-99'), isTrue);
      final cfg = manager.getSSHConfig('test-device-99');
      expect(cfg.username, 'ubuntu');
      expect(cfg.password, 'mysecurepassword');

      await manager.removeSshCredentials('test-device-99');
      expect(manager.hasSavedSshCredentials('test-device-99'), isFalse);
    });
  });
}
