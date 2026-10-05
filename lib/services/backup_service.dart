import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/known_device.dart';
import '../theme/app_theme.dart';
import 'app_startup_service.dart';
import 'device_manager.dart';
import 'device_registry.dart';

class BackupResult {
  final bool success;
  final bool cancelled;
  final String? filePath;
  final String? fileName;
  final int deviceCount;
  final String? error;

  const BackupResult({
    required this.success,
    this.cancelled = false,
    this.filePath,
    this.fileName,
    this.deviceCount = 0,
    this.error,
  });
}

class RestoreResult {
  final bool success;
  final bool cancelled;
  final String? fileName;
  final int devicesRestored;
  final String? error;

  const RestoreResult({
    required this.success,
    this.cancelled = false,
    this.fileName,
    this.devicesRestored = 0,
    this.error,
  });
}

/// Service to handle exporting and importing full MachineMake configuration
/// and device registry backups (MM_backup.json).
class BackupService {
  static final BackupService instance = BackupService._();
  factory BackupService() => instance;
  BackupService._();

  static const String defaultFileName = 'MM_backup.json';

  /// Prompts the user to pick a location and saves MM_backup.json containing
  /// all known devices, SharedPreferences configurations, and accent color.
  Future<BackupResult> createBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final registry = DeviceRegistry();
      if (!registry.isLoaded) {
        await registry.load();
      }

      // 1. Gather all SharedPreferences entries
      final allPrefKeys = prefs.getKeys();
      final prefsMap = <String, dynamic>{};
      for (final key in allPrefKeys) {
        prefsMap[key] = prefs.get(key);
      }

      // 2. Construct backup payload
      final backupPayload = generateBackupPayload(
        prefsMap: prefsMap,
        devices: registry.devices,
        accentColor: AppTheme.currentAccentColor,
      );

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupPayload);
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      // 3. Prompt user to choose location using system file picker
      final selectedPath = await FilePicker.saveFile(
        dialogTitle: 'Save MachineMake Backup',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (selectedPath == null) {
        return const BackupResult(success: false, cancelled: true);
      }

      // 4. Ensure file is written on desktop/file systems where bytes are not auto-written
      if (!kIsWeb) {
        try {
          final file = File(selectedPath);
          if (!await file.exists() || (await file.length()) == 0) {
            await file.writeAsString(jsonString);
          }
        } catch (_) {
          // On mobile platforms with SAF, writing directly may throw if selectedPath
          // is a content URI, but bytes were already handed to FilePicker.saveFile.
        }
      }

      final fileName = selectedPath.split(RegExp(r'[\\/]')).last;

      return BackupResult(
        success: true,
        filePath: selectedPath,
        fileName: fileName.isNotEmpty ? fileName : defaultFileName,
        deviceCount: registry.devices.length,
      );
    } catch (e) {
      debugPrint('[BackupService] Error creating backup: $e');
      return BackupResult(success: false, error: e.toString());
    }
  }

  /// Generates the raw backup JSON map from data.
  Map<String, dynamic> generateBackupPayload({
    required Map<String, dynamic> prefsMap,
    required List<KnownDevice> devices,
    required Color accentColor,
  }) {
    return <String, dynamic>{
      'app_name': 'MachineMake',
      'backup_version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'accent_color': accentColor.toARGB32(),
      'known_devices': devices.map((d) => d.toJson()).toList(),
      'preferences': prefsMap,
    };
  }

  /// Restores settings, device registry, and accent color from a backup payload.
  Future<int> applyBackupPayload(
    Map<String, dynamic> backupData, {
    required SharedPreferences prefs,
    required DeviceRegistry registry,
  }) async {
    // 1. Restore SharedPreferences entries
    if (backupData['preferences'] is Map) {
      final prefsMap = Map<String, dynamic>.from(backupData['preferences'] as Map);
      for (final entry in prefsMap.entries) {
        final val = entry.value;
        if (val is bool) {
          await prefs.setBool(entry.key, val);
        } else if (val is int) {
          await prefs.setInt(entry.key, val);
        } else if (val is double) {
          await prefs.setDouble(entry.key, val);
        } else if (val is String) {
          await prefs.setString(entry.key, val);
        } else if (val is List) {
          await prefs.setStringList(
            entry.key,
            val.map((e) => e.toString()).toList(),
          );
        }
      }
    }

    // 2. Restore Known Devices in DeviceRegistry
    int devicesRestoredCount = 0;
    if (backupData['known_devices'] is List) {
      final rawDevices = backupData['known_devices'] as List;
      for (final item in rawDevices) {
        if (item is Map) {
          try {
            final dev = KnownDevice.fromJson(Map<String, dynamic>.from(item));
            await registry.addOrUpdate(dev);
            devicesRestoredCount++;
          } catch (_) {}
        }
      }
      await registry.save();
    }

    // 3. Restore Accent Color if present
    final accentVal = backupData['accent_color'] ?? backupData['preferences']?['app_accent_color'];
    if (accentVal is int) {
      await AppTheme.setAccentColor(Color(accentVal));
    }

    // 4. Reload DeviceManager and state
    final clientId = prefs.getString('udcf_client_id') ?? DeviceManager().clientId;
    await DeviceManager().reloadFromStartup(clientId: clientId);
    await AppStartupService.run();

    return devicesRestoredCount;
  }

  /// Prompts the user to pick a backup file (MM_backup.json), validates it,
  /// and restores all settings, accent color, and device registry entries.
  Future<RestoreResult> restoreBackup() async {
    try {
      final pickerResult = await FilePicker.pickFiles(
        dialogTitle: 'Select MachineMake Backup File ($defaultFileName)',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (pickerResult == null || pickerResult.files.isEmpty) {
        return const RestoreResult(success: false, cancelled: true);
      }

      final file = pickerResult.files.first;
      String jsonContent;

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        jsonContent = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        jsonContent = await File(file.path!).readAsString();
      } else {
        return const RestoreResult(
          success: false,
          error: 'Unable to read contents of selected backup file.',
        );
      }

      // 1. Parse and validate JSON
      dynamic decoded;
      try {
        decoded = jsonDecode(jsonContent);
      } catch (_) {
        return const RestoreResult(
          success: false,
          error: 'The selected file is not a valid JSON document.',
        );
      }

      if (decoded is! Map) {
        return const RestoreResult(
          success: false,
          error: 'Invalid backup format: root element must be a JSON object.',
        );
      }

      final backupData = Map<String, dynamic>.from(decoded);
      final hasVersion = backupData.containsKey('backup_version');
      final hasDevices = backupData.containsKey('known_devices');
      final hasPrefs = backupData.containsKey('preferences');

      if (!hasVersion && !hasDevices && !hasPrefs) {
        return const RestoreResult(
          success: false,
          error: 'The selected file does not appear to be a MachineMake backup.',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final registry = DeviceRegistry();
      if (!registry.isLoaded) {
        await registry.load();
      }

      final devicesRestoredCount = await applyBackupPayload(
        backupData,
        prefs: prefs,
        registry: registry,
      );

      return RestoreResult(
        success: true,
        fileName: file.name,
        devicesRestored: devicesRestoredCount,
      );
    } catch (e) {
      debugPrint('[BackupService] Error restoring backup: $e');
      return RestoreResult(success: false, error: e.toString());
    }
  }
}
