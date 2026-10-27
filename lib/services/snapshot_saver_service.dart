import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';
import 'event_manager.dart';

/// Saves the currently displayed live camera frame directly to the phone's
/// storage (`Pictures/MachineMake`) without interrupting the active camera stream.
class SnapshotSaverService {
  SnapshotSaverService._();

  static const MethodChannel _mediaChannel =
      MethodChannel('com.machinemake/media');

  /// Grabs the latest in-memory JPEG frame for [deviceId] from [EventManager],
  /// writes it to the phone's Gallery / storage, and shows a feedback SnackBar.
  static Future<String?> saveCurrentFrame(
    BuildContext context, {
    String? deviceId,
    String? deviceName,
  }) async {
    final Uint8List? frameBytes = EventManager().latestCameraFrame(deviceId);

    if (frameBytes == null || frameBytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No camera frame available yet — start the stream first',
              style: GoogleFonts.exo2(),
            ),
            backgroundColor: Colors.amber[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return null;
    }

    final now = DateTime.now();
    final safePrefix = (deviceName ?? 'Robot')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final fileName = '${safePrefix}_$stamp.jpg';

    String? savedLocation;
    try {
      // 1. Try native Android MediaStore (saves directly to Gallery -> Pictures/MachineMake)
      savedLocation = await _mediaChannel.invokeMethod<String>(
        'saveSnapshot',
        {
          'bytes': frameBytes,
          'fileName': fileName,
        },
      );
    } catch (_) {
      // 2. Fallback for desktop / test environments using path_provider
      try {
        final dir = await getApplicationDocumentsDirectory();
        final folder = Directory('${dir.path}${Platform.pathSeparator}MachineMake_Snapshots');
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        final file = File('${folder.path}${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(frameBytes, flush: true);
        savedLocation = file.path;
      } catch (_) {}
    }

    if (context.mounted) {
      if (savedLocation != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved to phone: $savedLocation',
              style: GoogleFonts.exo2(),
            ),
            backgroundColor: AppTheme.primaryOrange,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save snapshot to phone storage',
              style: GoogleFonts.exo2(),
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    return savedLocation;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
