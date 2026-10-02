import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/discovery/discovered_device.dart';
import '../core/discovery/mdns_discoverer.dart';
import '../core/discovery/ble_discoverer.dart';
import '../core/dcp/dcp_message.dart';
import 'permission_service.dart';

export '../core/discovery/discovered_device.dart';

/// Discovers nearby UDCF-compatible devices over Wi-Fi (mDNS) and BLE.
///
/// Deduplication key is [DiscoveredDevice.deviceId]: a device reachable over
/// both Wi-Fi and BLE appears as a single entry with both transports listed.
///
/// In [kDebugMode] without real hardware, simulated mock devices are also
/// injected so the UI remains functional during development.
class DiscoveryManager extends ChangeNotifier {
  static final DiscoveryManager _instance = DiscoveryManager._();
  factory DiscoveryManager() => _instance;
  DiscoveryManager._();

  bool _isScanning = false;
  final Map<String, DiscoveredDevice> _byId = {};

  Timer? _scanTimer;
  Timer? _expiryTimer;

  StreamSubscription? _mDnsSub;
  StreamSubscription? _bleSub;

  final _mdns = MdnsDiscoverer();
  final _ble  = BleDiscoverer();

  bool get isScanning => _isScanning;

  List<DiscoveredDevice> get discovered =>
      List.unmodifiable(_byId.values.toList());

  // ── Scanning lifecycle ─────────────────────────────────────────────────

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    if (_isScanning) return;
    _isScanning = true;
    _byId.clear();
    notifyListeners();

    // Request permissions before scanning
    final permOk = await PermissionService.instance.requestDiscoveryPermissions();
    if (!permOk) {
      // ignore: avoid_print
      print('[DiscoveryManager] permissions denied — skipping BLE/mDNS');
    }

    // ── mDNS discovery ────────────────────────────────────────────────────
    _mDnsSub?.cancel();
    _mDnsSub = _mdns.deviceStream.listen(_addDevice);
    _mdns.startScan(timeout: timeout);

    // ── BLE discovery ─────────────────────────────────────────────────────
    if (permOk) {
      _bleSub?.cancel();
      _bleSub = _ble.deviceStream.listen(_addDevice);
      _ble.startScan(timeout: timeout);
    }

    // ── Direct LAN probe for DCP server on port 8765 ───────────────────────
    _probeKnownHosts(port: 8765);

    // ── Expiry pruning every 10 s ─────────────────────────────────────────
    _expiryTimer?.cancel();
    _expiryTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _pruneStale());

    // ── Auto-stop after timeout ───────────────────────────────────────────
    _scanTimer?.cancel();
    _scanTimer = Timer(timeout + const Duration(seconds: 2), stopScan);
  }

  Future<void> _probeKnownHosts({int port = 8765}) async {
    final candidates = [
      '10.80.166.248',
      '10.0.2.2',
      '127.0.0.1',
      '192.168.1.100',
      '192.168.1.102',
    ];

    for (final host in candidates) {
      if (!_isScanning) break;
      probeHost(host, port: port);
    }
  }

  Future<void> probeHost(String host, {int port = 8765}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 800));
      socket.destroy();

      // Port is open! Query device identity via DCP WebSocket hello
      String devId = 'device-${host.replaceAll('.', '-')}-$port';
      String devName = 'Device ($host)';
      String devType = 'computer';

      try {
        final uri = Uri.parse('ws://$host:$port/dcp');
        final channel = WebSocketChannel.connect(uri);

        final helloMsg = DcpMessage.hello(
          appVersion: '2.0.0',
          protocolVersion: '1.0',
          clientId: 'discovery_probe',
        );
        channel.sink.add(jsonEncode(helloMsg.toJson()));

        final raw = await channel.stream.first.timeout(const Duration(milliseconds: 1800));
        channel.sink.close();

        if (raw is String) {
          final data = jsonDecode(raw) as Map<String, dynamic>;
          final payload = (data['data'] as Map<String, dynamic>?) ??
              (data['payload'] as Map<String, dynamic>?) ??
              data;
          final parsedId = payload['device_id'] ?? data['device_id'];
          final parsedName = payload['name'] ?? payload['device_name'] ?? data['device_name'];
          final parsedType = payload['profile'] ?? payload['type'] ?? payload['device_type'] ?? data['profile'] ?? data['type'];

          if (parsedName != null && parsedName.toString().isNotEmpty) {
            devName = parsedName.toString();
          }
          if (parsedId != null && parsedId.toString().isNotEmpty) {
            devId = parsedId.toString();
          } else if (parsedName != null && parsedName.toString().isNotEmpty) {
            devId = 'device-${parsedName.toString().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '-').toLowerCase()}';
          }
          if (parsedType != null && parsedType.toString().isNotEmpty) {
            devType = parsedType.toString();
          }
        }
      } catch (_) {
        // Fallback: If WebSocket hello didn't reply in time, preserve generic computer classification
      }

      _addDevice(DiscoveredDevice(
        deviceId: devId,
        name: devName,
        type: devType,
        transports: const {'wifi'},
        ipAddress: host,
        port: port,
      ));
    } catch (_) {}
  }

  Future<void> stopScan() async {
    _isScanning = false;
    _scanTimer?.cancel();
    _expiryTimer?.cancel();
    _mDnsSub?.cancel();
    _bleSub?.cancel();
    await _mdns.stopScan();
    await _ble.stopScan();
    notifyListeners();
  }

  // ── Device management ──────────────────────────────────────────────────

  /// Called by real discoverers and mock injector.
  void _addDevice(DiscoveredDevice device) {
    // 1. Direct match by deviceId
    String? existingKey = _byId.containsKey(device.deviceId) ? device.deviceId : null;

    // 2. Name + type match (e.g. same PC reached via 10.0.2.2 emulator alias AND 10.80.166.248 LAN IP)
    if (existingKey == null) {
      for (final entry in _byId.entries) {
        if (entry.value.name == device.name &&
            entry.value.type == device.type &&
            !device.name.startsWith('Device (')) {
          existingKey = entry.key;
          break;
        }
      }
    }

    // 3. Match emulator host alias (10.0.2.2 on port P matches local IP on same port P)
    if (existingKey == null && device.ipAddress != null && device.port != null) {
      for (final entry in _byId.entries) {
        final other = entry.value;
        if (other.port == device.port) {
          final isOneEmulator = (device.ipAddress == '10.0.2.2' || other.ipAddress == '10.0.2.2');
          final isBothLocal = (device.ipAddress?.startsWith('10.') == true || device.ipAddress?.startsWith('192.168.') == true) &&
                              (other.ipAddress?.startsWith('10.') == true || other.ipAddress?.startsWith('192.168.') == true);
          if (isOneEmulator && isBothLocal) {
            existingKey = entry.key;
            break;
          }
        }
      }
    }

    if (existingKey != null) {
      final existing = _byId[existingKey]!;
      final useNewIp = (device.ipAddress != null &&
          device.ipAddress != '127.0.0.1' &&
          device.ipAddress != '10.0.2.2');
      final useNewName = !device.name.startsWith('Device (') &&
          existing.name.startsWith('Device (');
      final useNewType = device.type != 'computer' && existing.type == 'computer';
      final useNewId = !device.deviceId.startsWith('device-') &&
          existing.deviceId.startsWith('device-');
      final finalId = useNewId ? device.deviceId : existing.deviceId;

      final merged = existing.mergeWith(DiscoveredDevice(
        deviceId: finalId,
        name: useNewName ? device.name : existing.name,
        type: useNewType ? device.type : existing.type,
        transports: {...existing.transports, ...device.transports},
        ipAddress: useNewIp ? device.ipAddress : existing.ipAddress,
        port: device.port ?? existing.port,
        bleAddress: device.bleAddress ?? existing.bleAddress,
        rssi: device.rssi ?? existing.rssi,
      ));

      if (useNewId && finalId != existingKey) {
        _byId.remove(existingKey);
        _byId[finalId] = merged;
      } else {
        _byId[existingKey] = merged;
      }
    } else {
      _byId[device.deviceId] = device;
    }
    notifyListeners();
  }

  /// Allows external code (e.g. paired device reconnect) to inject a device.
  void addDiscoveredDevice(DiscoveredDevice device) => _addDevice(device);

  void _pruneStale() {
    final before = _byId.length;
    _byId.removeWhere((_, d) => !d.isFresh);
    if (_byId.length != before) notifyListeners();
  }

  // ── Dispose ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    stopScan();
    _mdns.dispose();
    _ble.dispose();
    super.dispose();
  }
}
