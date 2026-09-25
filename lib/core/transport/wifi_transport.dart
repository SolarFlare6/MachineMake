import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'device_transport.dart';
import '../connection/connection_state_enum.dart';

/// WebSocket-based TCP transport implementation for Wi-Fi connected devices.
class WifiTransport implements DeviceTransport {
  @override
  final String deviceId;
  final String host;
  final int port;

  WebSocketChannel? _channel;
  final StreamController<String> _messageController =
      StreamController<String>.broadcast();
  final StreamController<DeviceConnectionState> _connectionStateController =
      StreamController<DeviceConnectionState>.broadcast();

  bool _isConnected = false;
  bool _isDisposed = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;

  WifiTransport({
    required this.deviceId,
    required this.host,
    this.port = 8765,
  });

  @override
  String get transportType => 'wifi';

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<DeviceConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  Future<void> connect() async {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();

    try {
      final uri = Uri.parse('ws://$host:$port/dcp');
      _channel = WebSocketChannel.connect(uri);

      // Listen for incoming messages
      _channel!.stream.listen(
        (data) {
          if (!_isConnected) {
            _isConnected = true;
            _reconnectAttempts = 0;
            _connectionStateController.add(DeviceConnectionState.connected);
          }
          if (data is String) {
            _messageController.add(data);
          }
        },
        onError: (error) {
          _handleDisconnect(error: error.toString());
        },
        onDone: () {
          _handleDisconnect();
        },
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _connectionStateController.add(DeviceConnectionState.connected);
    } catch (e) {
      _handleDisconnect(error: e.toString());
      rethrow;
    }
  }

  void _handleDisconnect({String? error}) {
    if (!_isConnected && _reconnectAttempts == 0) return;
    _isConnected = false;
    _connectionStateController.add(DeviceConnectionState.offline);

    if (!_isDisposed && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectAttempts++;
    final delaySeconds = 1 << (_reconnectAttempts - 1); // 1, 2, 4, 8, 16
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposed && !_isConnected) {
        connect().catchError((_) {});
      }
    });
  }

  @override
  Future<void> send(String jsonMessage) async {
    if (!_isConnected || _channel == null) {
      throw StateError('WifiTransport is not connected to device $deviceId');
    }
    _channel!.sink.add(jsonMessage);
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _isConnected = false;
    _connectionStateController.add(DeviceConnectionState.offline);
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    disconnect();
    _messageController.close();
    _connectionStateController.close();
  }
}
