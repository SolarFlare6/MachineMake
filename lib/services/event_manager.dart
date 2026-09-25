import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../core/models/device_event.dart';

/// Central reactive event bus routing device events and telemetry to UI subscribers.
class EventManager extends ChangeNotifier {
  static final EventManager _instance = EventManager._();
  factory EventManager() => _instance;
  EventManager._();

  final PublishSubject<DeviceEvent> _bus = PublishSubject<DeviceEvent>();

  /// Global stream of all events from all devices.
  Stream<DeviceEvent> get events => _bus.stream;

  /// Stream of events filtered for a specific device.
  Stream<DeviceEvent> eventsForDevice(String deviceId) =>
      _bus.where((e) => e.deviceId == deviceId);

  /// Stream of events filtered by event type.
  Stream<DeviceEvent> eventsOfType(String eventType) =>
      _bus.where((e) => e.eventType == eventType);

  /// Broadcast a received event to all listeners.
  void emit(DeviceEvent event) {
    _bus.add(event);
    notifyListeners();
  }

  @override
  void dispose() {
    _bus.close();
    super.dispose();
  }
}
