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

  /// Cache of the most recent IMU telemetry payload per deviceId.
  final Map<String, Map<String, dynamic>> _latestImuData = {};
  Map<String, dynamic>? _lastGlobalImuData;

  /// Cache of the most recent camera tracking state per deviceId.
  final Map<String, Map<String, dynamic>> _latestTrackingInfo = {};
  Map<String, dynamic>? _lastGlobalTrackingInfo;

  /// Cache of the most recent YOLOv8 object detections per deviceId.
  final Map<String, List<Map<String, dynamic>>> _latestDetections = {};
  List<Map<String, dynamic>> _lastGlobalDetections = const [];

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

  /// Returns the latest IMU telemetry map (`pitch`, `roll`, `yaw`, `accel`, `gyro`) for [deviceId].
  Map<String, dynamic>? latestImuData([String? deviceId]) {
    if (deviceId != null && _latestImuData.containsKey(deviceId)) {
      return _latestImuData[deviceId];
    }
    return _lastGlobalImuData;
  }

  /// Returns the latest camera tracking metadata (`active`, `bbox`, `target_label`) for [deviceId].
  Map<String, dynamic>? latestTrackingInfo([String? deviceId]) {
    if (deviceId != null && _latestTrackingInfo.containsKey(deviceId)) {
      return _latestTrackingInfo[deviceId];
    }
    return _lastGlobalTrackingInfo;
  }

  /// Returns whether visual object tracking is currently locked on [deviceId].
  bool isTrackingActive([String? deviceId]) {
    final info = latestTrackingInfo(deviceId);
    return info != null && info['active'] == true;
  }

  /// Returns the active tracked object label (if any) for [deviceId].
  String? trackingTargetLabel([String? deviceId]) {
    final info = latestTrackingInfo(deviceId);
    final lbl = info?['target_label'] ?? info?['label'];
    if (lbl is String && lbl.trim().isNotEmpty) {
      return lbl.trim();
    }
    return null;
  }

  /// Returns the latest YOLOv8 detections reported in `camera_frame` for [deviceId].
  List<Map<String, dynamic>> latestDetections([String? deviceId]) {
    if (deviceId != null && _latestDetections.containsKey(deviceId)) {
      return _latestDetections[deviceId]!;
    }
    return _lastGlobalDetections;
  }

  /// Optimistically updates the local tracking state for [deviceId] when the user starts/stops tracking.
  void setTrackingState(
    String? deviceId, {
    required bool active,
    String? label,
  }) {
    final map = <String, dynamic>{
      'active': active,
      if (label != null) 'target_label': label,
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      _latestTrackingInfo[deviceId] = map;
    }
    _lastGlobalTrackingInfo = map;
    notifyListeners();
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

      final rawTracking = event.data['tracking'];
      if (rawTracking is Map) {
        final trkMap = Map<String, dynamic>.from(rawTracking);
        if (event.deviceId.isNotEmpty) {
          _latestTrackingInfo[event.deviceId] = trkMap;
        }
        _lastGlobalTrackingInfo = trkMap;
      }

      final rawDetections = event.data['detections'];
      if (rawDetections is List) {
        final detList = rawDetections
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        if (event.deviceId.isNotEmpty) {
          _latestDetections[event.deviceId] = detList;
        }
        _lastGlobalDetections = detList;
      }
    } else if (event.eventType == 'telemetry') {
      final rawImu = event.data['imu'];
      if (rawImu is Map) {
        final imuMap = Map<String, dynamic>.from(rawImu);
        if (event.deviceId.isNotEmpty) {
          _latestImuData[event.deviceId] = imuMap;
        }
        _lastGlobalImuData = imuMap;
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
