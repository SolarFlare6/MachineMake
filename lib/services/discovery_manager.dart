import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/discovery/discovered_device.dart';
import '../core/discovery/mdns_discoverer.dart';
import '../core/discovery/ble_discoverer.dart';
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

    // ── Mock devices in debug mode (so UI works without hardware) ─────────
    if (kDebugMode) {
      _injectMockDevices();
    }

    // ── Expiry pruning every 10 s ─────────────────────────────────────────
    _expiryTimer?.cancel();
    _expiryTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _pruneStale());

    // ── Auto-stop after timeout ───────────────────────────────────────────
    _scanTimer?.cancel();
    _scanTimer = Timer(timeout + const Duration(seconds: 2), stopScan);
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
    final existing = _byId[device.deviceId];
    _byId[device.deviceId] =
        existing != null ? existing.mergeWith(device) : device;
    notifyListeners();
  }

  /// Allows external code (e.g. paired device reconnect) to inject a device.
  void addDiscoveredDevice(DiscoveredDevice device) => _addDevice(device);

  void _pruneStale() {
    final before = _byId.length;
    _byId.removeWhere((_, d) => !d.isFresh);
    if (_byId.length != before) notifyListeners();
  }

  // ── Mock data (debug only) ─────────────────────────────────────────────

  void _injectMockDevices() {
    Timer(const Duration(milliseconds: 600), () {
      if (!_isScanning) return;
      _addDevice(DiscoveredDevice(
        deviceId: 'rpi-4b-01',
        name: 'Raspberry Pi 4B',
        type: 'raspberry_pi',
        transports: const {'wifi'},
        ipAddress: '192.168.1.104',
        port: 8765,
      ));
    });

    Timer(const Duration(milliseconds: 1400), () {
      if (!_isScanning) return;
      _addDevice(DiscoveredDevice(
        deviceId: 'quad-bot-01',
        name: 'Quadruped Bot',
        type: 'robot',
        transports: const {'wifi'},
        ipAddress: '192.168.1.120',
        port: 8765,
      ));
    });

    Timer(const Duration(milliseconds: 2200), () {
      if (!_isScanning) return;
      _addDevice(DiscoveredDevice(
        deviceId: 'pico-w-01',
        name: 'RPi Pico W',
        type: 'pico',
        transports: const {'bluetooth'},
        bleAddress: 'D8:3A:DD:4A:21:05',
        rssi: -58,
      ));
    });

    // Simulate the Pico W also appearing over Wi-Fi to show merge behaviour
    Timer(const Duration(milliseconds: 3500), () {
      if (!_isScanning) return;
      _addDevice(DiscoveredDevice(
        deviceId: 'pico-w-01',
        name: 'RPi Pico W',
        type: 'pico',
        transports: const {'wifi'},
        ipAddress: '192.168.1.131',
        port: 8765,
      ));
    });
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
