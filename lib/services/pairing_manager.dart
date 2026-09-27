import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  /// Parses a scanned QR payload (supports both server DCP QR and legacy formats).
  Map<String, dynamic>? parseQrPayload(String raw) {
    try {
      final json = jsonDecode(raw.trim()) as Map<String, dynamic>;
      final isDcpQr = (json['protocol'] == 'DCP' ||
          json['pairing'] == 'qr' ||
          json['action'] == 'pair' ||
          json['pairing_code'] != null);
      if (isDcpQr && json['device_id'] != null) {
        final host = json['host'] ?? json['address'] ?? json['ip'];
        final port = json['port'] is int
            ? json['port'] as int
            : int.tryParse('${json['port']}') ?? 8765;
        return {
          ...json,
          'device_id': json['device_id'].toString(),
          'name': json['name'] ?? json['device_name'] ?? 'Machine Make Device',
          'profile': json['profile'] ?? 'quadruped',
          'host': host?.toString(),
          'address': host?.toString(),
          'port': port,
          'pairing_code': json['pairing_code']?.toString() ?? '',
          'transport': json['transport'] ?? 'wifi',
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Connects to a device via WebSocket, sends a DCP request_pairing command with pairing_code,
  /// and returns the shared secret on success.
  Future<Map<String, dynamic>> pairViaQr({
    required String host,
    required int port,
    required String deviceId,
    required String deviceName,
    required String pairingCode,
    required String clientId,
    String clientName = 'MachineMake App',
  }) async {
    _step = PairingStep.waitingForDeviceConfirmation;
    _lastError = null;
    notifyListeners();

    try {
      final wsUrl = Uri.parse('ws://$host:$port');
      final channel = WebSocketChannel.connect(wsUrl);
      final completer = Completer<Map<String, dynamic>>();

      final pairingMsg = {
        'dcp': '1.0',
        'type': 'request',
        'id': 1,
        'command': 'request_pairing',
        'arguments': {
          'client_id': clientId,
          'client_name': clientName,
          'method': 'qr',
          'pairing_code': pairingCode,
        },
      };

      StreamSubscription? sub;
      Timer? timeout;

      timeout = Timer(const Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('Pairing timed out with device'));
        }
      });

      sub = channel.stream.listen(
        (data) {
          try {
            final resp = jsonDecode(data.toString()) as Map<String, dynamic>;
            final success = resp['success'] == true;
            final d = (resp['data'] ?? resp['payload']) as Map<String, dynamic>? ?? {};
            if (success && d['approved'] == true && d['secret'] != null) {
              if (!completer.isCompleted) completer.complete(d);
            } else {
              final err = resp['error']?['message'] ?? d['reason'] ?? 'Pairing rejected';
              if (!completer.isCompleted) completer.completeError(Exception(err));
            }
          } catch (e) {
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
      );

      channel.sink.add(jsonEncode(pairingMsg));

      final result = await completer.future;
      timeout.cancel();
      await sub.cancel();
      await channel.sink.close();

      final secret = result['secret'] as String;

      final known = KnownDevice(
        deviceId: deviceId,
        name: deviceName,
        type: 'quadruped',
        psk: secret,
        lastIp: host,
        lastPort: port,
        isTrusted: true,
        pairedAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
      );
      await DeviceRegistry().addOrUpdate(known);

      _step = PairingStep.handshakeComplete;
      notifyListeners();

      return {
        'success': true,
        'secret': secret,
        'device': known,
      };
    } catch (e) {
      _step = PairingStep.failed;
      _lastError = e.toString();
      notifyListeners();
      rethrow;
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
