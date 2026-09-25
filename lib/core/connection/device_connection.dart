import 'dart:async';
import 'package:flutter/foundation.dart';

import '../dcp/dcp_session.dart';
import '../models/device_manifest.dart';
import '../transport/bluetooth_transport.dart';
import '../transport/device_transport.dart';
import '../transport/mock_transport.dart';
import '../transport/wifi_transport.dart';
import 'connection_state_enum.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Manages the full connection lifecycle for an individual device.
class DeviceConnection extends ChangeNotifier {
  final String deviceId;

  DeviceConnectionState _state = DeviceConnectionState.offline;
  DeviceTransport? _transport;
  DcpSession? _session;
  DeviceManifest? _manifest;
  String? _lastError;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 4;
  Timer? _reconnectTimer;

  // Stored connection parameters for auto-reconnect
  String? _host;
  int? _port;
  String? _bleAddress;
  String? _psk;
  String? _clientId;
  bool _isMock = false;
  String _mockType = 'raspberry_pi';

  DeviceConnection({required this.deviceId});

  DeviceConnectionState get state => _state;
  DcpSession? get session => _session;
  DeviceManifest? get manifest => _manifest;
  String? get lastError => _lastError;
  bool get isConnected => _state == DeviceConnectionState.connected;

  /// Connect using a Wi-Fi WebSocket transport.
  Future<void> connectWifi({
    required String host,
    required int port,
    String? psk,
    required String clientId,
  }) async {
    _host = host;
    _port = port;
    _psk = psk;
    _clientId = clientId;
    _isMock = false;

    final transport = WifiTransport(deviceId: deviceId, host: host, port: port);
    await _initSession(transport, psk, clientId);
  }

  /// Connect using Bluetooth Low Energy transport.
  Future<void> connectBluetooth({
    required String bleAddress,
    String? psk,
    required String clientId,
  }) async {
    _bleAddress = bleAddress;
    _psk = psk;
    _clientId = clientId;
    _isMock = false;

    final device = BluetoothDevice.fromId(bleAddress);
    final transport = BluetoothTransport(deviceId: deviceId, device: device);
    await _initSession(transport, psk, clientId);
  }

  /// Connect using an in-memory Mock transport for development/simulation.
  Future<void> connectMock({
    required String mockDeviceType,
    String? psk,
    required String clientId,
  }) async {
    _isMock = true;
    _mockType = mockDeviceType;
    _clientId = clientId;
    _psk = psk;

    final transport = MockTransport(
      deviceId: deviceId,
      mockDeviceType: mockDeviceType,
    );
    await _initSession(transport, psk, clientId);
  }

  Future<void> _initSession(
    DeviceTransport transport,
    String? psk,
    String clientId,
  ) async {
    _reconnectTimer?.cancel();
    _session?.dispose();
    _transport?.dispose();

    _transport = transport;
    _session = DcpSession(
      transport: transport,
      clientId: clientId,
      psk: psk,
    );

    _setState(DeviceConnectionState.pairing);

    try {
      await _session!.connect();
      _manifest = _session!.manifest;
      _reconnectAttempts = 0;
      _lastError = null;
      _setState(DeviceConnectionState.connected);
    } catch (e) {
      _lastError = e.toString();
      _setState(DeviceConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts || _clientId == null) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: 1 << _reconnectAttempts);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_state != DeviceConnectionState.connected) {
        if (_isMock) {
          connectMock(
            mockDeviceType: _mockType,
            psk: _psk,
            clientId: _clientId!,
          ).catchError((_) {});
        } else if (_host != null && _port != null) {
          connectWifi(
            host: _host!,
            port: _port!,
            psk: _psk,
            clientId: _clientId!,
          ).catchError((_) {});
        } else if (_bleAddress != null) {
          connectBluetooth(
            bleAddress: _bleAddress!,
            psk: _psk,
            clientId: _clientId!,
          ).catchError((_) {});
        }
      }
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectAttempts = _maxReconnectAttempts; // prevent auto-reconnect
    _setState(DeviceConnectionState.disconnecting);
    await _session?.disconnect();
    _transport?.dispose();
    _session = null;
    _transport = null;
    _setState(DeviceConnectionState.offline);
  }

  void _setState(DeviceConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _session?.dispose();
    _transport?.dispose();
    super.dispose();
  }
}
