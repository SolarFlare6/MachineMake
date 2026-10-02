import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/discovery/discovered_device.dart';
import 'package:machmake2/services/device_manager.dart';
import 'package:machmake2/services/discovery_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Discovery Device Profile Detection Tests', () {
    final dm = DeviceManager();

    setUp(() {
      DiscoveryManager().addDiscoveredDevice(
        DiscoveredDevice(
          deviceId: 'pc-workstation-01',
          name: 'Office PC',
          type: 'pc',
          transports: const {'wifi'},
          ipAddress: '192.168.1.120',
          port: 8765,
        ),
      );

      DiscoveryManager().addDiscoveredDevice(
        DiscoveredDevice(
          deviceId: 'robot-dog-01',
          name: 'Spot Quadruped',
          type: 'quadruped',
          transports: const {'wifi'},
          ipAddress: '192.168.1.121',
          port: 8765,
        ),
      );

      DiscoveryManager().addDiscoveredDevice(
        DiscoveredDevice(
          deviceId: 'generic-robot-01',
          name: 'Arm Robot',
          type: 'robot',
          transports: const {'wifi'},
          ipAddress: '192.168.1.122',
          port: 8765,
        ),
      );
    });

    test('correctly classifies PC as computer profile, not robot', () {
      final pc = dm.nearbyDevices.firstWhere((d) => d.id == 'pc-workstation-01');
      expect(pc.profile, 'computer');
      expect(pc.deviceType, 'Computer / PC');
      expect(pc.iconKey, 'computer');
    });

    test('correctly classifies quadruped and robot', () {
      final dog = dm.nearbyDevices.firstWhere((d) => d.id == 'robot-dog-01');
      expect(dog.profile, 'quadruped');
      expect(dog.deviceType, 'Quadruped Robot');
      expect(dog.iconKey, 'quadruped');

      final arm = dm.nearbyDevices.firstWhere((d) => d.id == 'generic-robot-01');
      expect(arm.profile, 'quadruped');
      expect(arm.deviceType, 'Robot');
      expect(arm.iconKey, 'quadruped');
    });
  });
}
