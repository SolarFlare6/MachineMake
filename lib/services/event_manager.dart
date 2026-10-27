import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../core/models/device_event.dart';

/// Central reactive event bus routing device events and telemetry to UI subscribers.
class EventManager extends ChangeNotifier {
  static final EventManager _instance = EventManager._();
  factory EventManager() => _instance;
  EventManager._();

  final PublishSubject<DeviceEvent> _bus = PublishSubject<DeviceEvent>();

  /// Cache of the most recent decoded JPEG camera frame per deviceId.
  final Map<String, Uint8List> _latestCameraFrames = {};
  final Map<String, bool> _cameraStreamingState = {};
  Uint8List? _lastGlobalCameraFrame;

  /// Global stream of all events from all devices.
  Stream<DeviceEvent> get events => _bus.stream;

  /// Stream of events filtered for a specific device.
  Stream<DeviceEvent> eventsForDevice(String deviceId) =>
      _bus.where((e) => e.deviceId == deviceId);

  /// Stream of events filtered by event type.
  Stream<DeviceEvent> eventsOfType(String eventType) =>
      _bus.where((e) => e.eventType == eventType);

  /// Returns whether the camera stream is currently active for [deviceId].
  bool isCameraStreaming([String? deviceId]) {
    if (deviceId != null && _cameraStreamingState.containsKey(deviceId)) {
      return _cameraStreamingState[deviceId]!;
    }
    return _cameraStreamingState.values.any((v) => v);
  }

  /// Updates the camera streaming state for [deviceId].
  void setCameraStreaming(String deviceId, bool streaming) {
    _cameraStreamingState[deviceId] = streaming;
    notifyListeners();
  }

  /// Returns the latest decoded JPEG camera frame for [deviceId] (or the most recent frame across devices).
  Uint8List? latestCameraFrame([String? deviceId]) {
    if (deviceId != null && _latestCameraFrames.containsKey(deviceId)) {
      return _latestCameraFrames[deviceId];
    }
    return _lastGlobalCameraFrame;
  }

  /// Stores a decoded JPEG camera frame directly (e.g. from a `camera_snapshot` tool response).
  void updateCameraFrame(String deviceId, Uint8List bytes) {
    if (bytes.isEmpty) return;
    _latestCameraFrames[deviceId] = bytes;
    _lastGlobalCameraFrame = bytes;
    notifyListeners();
  }

  /// Broadcast a received event to all listeners.
  void emit(DeviceEvent event) {
    if (event.eventType == 'camera_frame') {
      final rawB64 = event.data['image_b64'] ??
          event.data['frame_b64'] ??
          event.data['jpeg_b64'] ??
          event.data['data'];
      if (rawB64 is String && rawB64.isNotEmpty) {
        try {
          final bytes = base64Decode(rawB64);
          if (bytes.isNotEmpty) {
            if (event.deviceId.isNotEmpty) {
              _latestCameraFrames[event.deviceId] = bytes;
              _cameraStreamingState[event.deviceId] = true;
            }
            _lastGlobalCameraFrame = bytes;
          }
        } catch (_) {}
      }
    }
    _bus.add(event);
    notifyListeners();
  }

  @override
  void dispose() {
    _bus.close();
    super.dispose();
  }
}
