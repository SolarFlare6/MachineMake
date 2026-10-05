import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:machmake2/core/models/known_device.dart';
import 'package:machmake2/services/backup_service.dart';
import 'package:machmake2/services/device_registry.dart';
import 'package:machmake2/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupService Payload Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generateBackupPayload formats all fields properly', () {
      final service = BackupService.instance;
      final devices = [
        KnownDevice(
          deviceId: 'pi-1',
          name: 'Raspberry Pi',
          type: 'raspberry_pi',
          pairedAt: DateTime.utc(2026, 1, 1),
          lastSeenAt: DateTime.utc(2026, 1, 2),
          isTrusted: true,
          lastIp: '192.168.1.100',
        ),
      ];

      final prefsMap = <String, dynamic>{
        'test_setting': true,
        'app_accent_color': 0xFF39FF14,
      };

      final payload = service.generateBackupPayload(
        prefsMap: prefsMap,
        devices: devices,
        accentColor: const Color(0xFF39FF14),
      );

      expect(payload['app_name'], equals('MachineMake'));
      expect(payload['backup_version'], equals(1));
      expect(payload['accent_color'], equals(const Color(0xFF39FF14).toARGB32()));
      expect(payload['preferences']['test_setting'], isTrue);
      expect((payload['known_devices'] as List).length, equals(1));
      expect((payload['known_devices'] as List)[0]['device_id'], equals('pi-1'));
    });

    test('applyBackupPayload restores preferences, registry and accent color', () async {
      final service = BackupService.instance;
      final prefs = await SharedPreferences.getInstance();
      final registry = DeviceRegistry();
      await registry.load();
      await registry.clearAll();

      final backupData = <String, dynamic>{
        'app_name': 'MachineMake',
        'backup_version': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'accent_color': 0xFF00E5FF,
        'preferences': <String, dynamic>{
          'custom_flag': true,
          'numeric_config': 42,
          'str_config': 'hello world',
          'list_config': ['a', 'b', 'c'],
        },
        'known_devices': [
          {
            'deviceId': 'restored-device-1',
            'name': 'Restored Robot',
            'type': 'robot',
            'pairedAt': DateTime.utc(2026, 2, 1).toIso8601String(),
            'lastSeenAt': DateTime.utc(2026, 2, 2).toIso8601String(),
            'isTrusted': true,
            'lastIp': '192.168.1.150',
          }
        ],
      };

      final restoredCount = await service.applyBackupPayload(
        backupData,
        prefs: prefs,
        registry: registry,
      );

      expect(restoredCount, equals(1));
      expect(prefs.getBool('custom_flag'), isTrue);
      expect(prefs.getInt('numeric_config'), equals(42));
      expect(prefs.getString('str_config'), equals('hello world'));
      expect(prefs.getStringList('list_config'), equals(['a', 'b', 'c']));
      expect(registry.devices.length, equals(1));
      expect(registry.devices.first.deviceId, equals('restored-device-1'));
      expect(registry.devices.first.name, equals('Restored Robot'));
      expect(AppTheme.currentAccentColor.toARGB32(), equals(const Color(0xFF00E5FF).toARGB32()));
    });
  });
}
