import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../transport/device_transport.dart';
import '../connection/connection_state_enum.dart';

/// Bluetooth Low Energy transport implementing [DeviceTransport].
///
/// Uses a two-characteristic GATT design:
///   TX [txCharUuid] — Write Without Response (app → device)
///   RX [rxCharUuid] — Notify                 (device → app)
///
/// Because BLE MTU is typically 512 bytes (or lower on older phones),
/// large DCP JSON payloads are fragmented into chunks with a 4-byte header:
///   [0..1] total_length  (uint16, big-endian)
///   [2]    chunk_index   (uint8, 0-based)
///   [3]    total_chunks  (uint8)
///   [4..]  payload bytes
class BluetoothTransport implements DeviceTransport {
  // ── GATT UUIDs ─────────────────────────────────────────────────────────
  static const String serviceUuid  = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String txCharUuid   = 'beb5483e-36e1-4688-b7f5-ea07361b26a8'; // app→device
  static const String rxCharUuid   = 'beb5483e-36e1-4688-b7f5-ea07361b26a9'; // device→app

  static const int _headerBytes     = 4;
  static const int _mtu             = 512;
  static const int _maxChunkPayload = _mtu - _headerBytes;

  // ── Public state ────────────────────────────────────────────────────────
  @override final String deviceId;
  @override String get transportType => 'bluetooth';

  // ── Internals ──────────────────────────────────────────────────────────
  final BluetoothDevice _device;
  final _messageController = StreamController<String>.broadcast();
  final _connStateController = StreamController<DeviceConnectionState>.broadcast();

  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription? _rxSub;
  StreamSubscription? _deviceStateSub;
  bool _isConnected = false;

  /// Reassembly buffer: chunkIndex → bytes
  final Map<int, List<int>> _reassemblyBuffer = {};
  int _expectedChunks = 0;

  BluetoothTransport({
    required this.deviceId,
    required BluetoothDevice device,
  }) : _device = device;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Stream<DeviceConnectionState> get connectionStateStream =>
      _connStateController.stream;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  Future<void> connect() async {
    _connStateController.add(DeviceConnectionState.pairing);

    // Monitor device connection state changes
    _deviceStateSub = _device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _isConnected = false;
        _connStateController.add(DeviceConnectionState.offline);
      }
    });

    await _device.connect(timeout: const Duration(seconds: 15));

    final services = await _device.discoverServices();
    _findCharacteristics(services);

    if (_txChar == null || _rxChar == null) {
      await _device.disconnect();
      throw StateError(
        '[BluetoothTransport] UDCF service or characteristics not found on device $deviceId',
      );
    }

    // Subscribe to RX notifications (device → app)
    await _rxChar!.setNotifyValue(true);
    _rxSub = _rxChar!.lastValueStream.listen(_handleChunk);

    _isConnected = true;
    _connStateController.add(DeviceConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _rxSub?.cancel();
    _rxSub = null;
    _deviceStateSub?.cancel();
    _deviceStateSub = null;
    try {
      await _device.disconnect();
    } catch (_) {}
    _connStateController.add(DeviceConnectionState.offline);
  }

  @override
  Future<void> send(String jsonMessage) async {
    if (!_isConnected || _txChar == null) {
      throw StateError('[BluetoothTransport] Not connected — cannot send');
    }

    final payload = utf8.encode(jsonMessage);
    final chunks = _fragment(payload);

    for (final chunk in chunks) {
      await _txChar!.write(chunk, withoutResponse: true);
      // Small delay between chunks to avoid overwhelming the BLE stack
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  void dispose() {
    _rxSub?.cancel();
    _deviceStateSub?.cancel();
    _messageController.close();
    _connStateController.close();
  }

  // ── GATT helpers ───────────────────────────────────────────────────────

  void _findCharacteristics(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid != Guid(serviceUuid)) continue;
      for (final char in service.characteristics) {
        if (char.uuid == Guid(txCharUuid)) _txChar = char;
        if (char.uuid == Guid(rxCharUuid)) _rxChar = char;
      }
    }
  }

  // ── Fragmentation ──────────────────────────────────────────────────────

  /// Splits [payload] into chunks with a 4-byte header each.
  List<List<int>> _fragment(List<int> payload) {
    final totalLength = payload.length;
    final chunks = <List<int>>[];
    var offset = 0;
    var index = 0;
    final totalChunks = (totalLength / _maxChunkPayload).ceil().clamp(1, 255);

    while (offset < totalLength) {
      final end = (offset + _maxChunkPayload).clamp(0, totalLength);
      final slice = payload.sublist(offset, end);
      final header = Uint8List(4)
        ..[0] = (totalLength >> 8) & 0xFF
        ..[1] = totalLength & 0xFF
        ..[2] = index
        ..[3] = totalChunks;
      chunks.add([...header, ...slice]);
      offset = end;
      index++;
    }
    return chunks;
  }

  // ── Reassembly ─────────────────────────────────────────────────────────

  void _handleChunk(List<int> raw) {
    if (raw.length < _headerBytes) return;

    // Parse header
    final totalLength  = (raw[0] << 8) | raw[1];
    final chunkIndex   = raw[2];
    final totalChunks  = raw[3];
    final chunkPayload = raw.sublist(_headerBytes);

    if (totalChunks == 0) return;

    // Single-chunk fast path
    if (totalChunks == 1) {
      _emit(chunkPayload);
      return;
    }

    // Multi-chunk reassembly
    if (_expectedChunks != totalChunks) {
      // New message — clear previous partial buffer
      _reassemblyBuffer.clear();
      _expectedChunks = totalChunks;
    }

    _reassemblyBuffer[chunkIndex] = chunkPayload;

    if (_reassemblyBuffer.length == totalChunks) {
      final assembled = <int>[];
      for (var i = 0; i < totalChunks; i++) {
        assembled.addAll(_reassemblyBuffer[i] ?? []);
      }
      _reassemblyBuffer.clear();
      _expectedChunks = 0;

      // Validate total length
      if (assembled.length == totalLength) {
        _emit(assembled);
      }
    }
  }

  void _emit(List<int> bytes) {
    try {
      _messageController.add(utf8.decode(bytes));
    } catch (_) {
      // ignore corrupt frames
    }
  }
}
