import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/models/device_manifest.dart';
import '../core/models/known_device.dart';
import 'device_registry.dart';

enum PairingStep {
  idle,
  requestSent,
  waitingForDeviceConfirmation,
  handshakeComplete,
  failed,
}

/// A pairing request session initiated between app and target device.
class PairingRequest {
  final String requestId;
  final String deviceId;
  final String deviceName;
  final String transport;
  final String? address;
  final DateTime createdAt;
  final DateTime expiresAt;

  PairingRequest({
    required this.requestId,
    required this.deviceId,
    required this.deviceName,
    required this.transport,
    this.address,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        expiresAt = (createdAt ?? DateTime.now()).add(const Duration(seconds: 60));

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Manages the pairing handshake, terminal confirmations, and QR generation.
class PairingManager extends ChangeNotifier {
  static final PairingManager _instance = PairingManager._();
  factory PairingManager() => _instance;
  PairingManager._();

  PairingRequest? _activeRequest;
  PairingStep _step = PairingStep.idle;
  String? _lastError;
  Timer? _timeoutTimer;

  PairingStep get step => _step;
  PairingRequest? get activeRequest => _activeRequest;
  String? get lastError => _lastError;

  /// Initiates pairing with a discovered device.
  Future<PairingRequest> initiatePairing({
    required String deviceId,
    required String deviceName,
    required String transport,
    String? address,
  }) async {
    _cancelInternal();

    final req = PairingRequest(
      requestId: const Uuid().v4(),
      deviceId: deviceId,
      deviceName: deviceName,
      transport: transport,
      address: address,
    );

    _activeRequest = req;
    _step = PairingStep.waitingForDeviceConfirmation;
    _lastError = null;
    notifyListeners();

    // Start 60-second expiration timer
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_step == PairingStep.waitingForDeviceConfirmation) {
        _step = PairingStep.failed;
        _lastError = 'Pairing request timed out. Device did not respond.';
        notifyListeners();
      }
    });

    return req;
  }

  /// Finalizes pairing and saves to persistent DeviceRegistry.
  Future<KnownDevice> completePairing({
    required String sessionToken,
    required DeviceManifest manifest,
  }) async {
    if (_activeRequest == null) {
      throw StateError('No active pairing request to complete');
    }

    final req = _activeRequest!;
    final known = KnownDevice(
      deviceId: req.deviceId,
      name: manifest.name.isNotEmpty ? manifest.name : req.deviceName,
      type: manifest.type,
      psk: sessionToken,
      lastIp: req.transport == 'wifi' ? req.address : null,
      lastPort: req.transport == 'wifi' ? 8765 : null,
      lastBleAddress: req.transport == 'bluetooth' ? req.address : null,
      isTrusted: true,
    );

    await DeviceRegistry().addOrUpdate(known);

    _step = PairingStep.handshakeComplete;
    _timeoutTimer?.cancel();
    notifyListeners();

    return known;
  }

  /// Generates QR pairing payload for device display.
  String generateQrPayload(PairingRequest request) {
    return jsonEncode({
      'action': 'pair',
      'request_id': request.requestId,
      'device_id': request.deviceId,
      'app_client_id': const Uuid().v4(),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Parses a scanned QR payload.
  Map<String, dynamic>? parseQrPayload(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['action'] == 'pair' && json['device_id'] != null) {
        return json;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void cancelPairing() {
    _cancelInternal();
    notifyListeners();
  }

  void _cancelInternal() {
    _timeoutTimer?.cancel();
    _activeRequest = null;
    _step = PairingStep.idle;
    _lastError = null;
  }
}
