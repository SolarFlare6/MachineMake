import 'dart:async';
import '../connection/connection_state_enum.dart';

/// Abstract bidirectional transport for DCP communication.
///
/// Implementations: [WifiTransport], [BluetoothTransport], [MockTransport].
abstract class DeviceTransport {
  /// Unique identifier of the target device.
  String get deviceId;

  /// Transport medium: 'wifi', 'bluetooth', or 'mock'.
  String get transportType;

  /// Whether the physical/network connection is currently open.
  bool get isConnected;

  /// Stream of raw incoming JSON messages from the device.
  Stream<String> get messageStream;

  /// Stream of coarse connection state changes from this transport.
  Stream<DeviceConnectionState> get connectionStateStream;

  /// Open connection to the device.
  Future<void> connect();

  /// Close connection and clean up resources.
  Future<void> disconnect();

  /// Send a raw JSON string to the device.
  Future<void> send(String jsonMessage);

  /// Release resources permanently.
  void dispose();
}
