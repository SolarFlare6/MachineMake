import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../discovery/discovered_device.dart';

/// Scans for UDCF devices advertising over Bluetooth Low Energy.
///
/// UDCF firmware must advertise:
///   - Service UUID : [udcfServiceUuid]
///   - Service data (optional): UTF-8 JSON with keys device_id, name, type
///   - Local name  : human-readable device name
class BleDiscoverer {
  /// Custom BLE service UUID that all UDCF-compatible firmware must advertise.
  static const String udcfServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

  final _controller = StreamController<DiscoveredDevice>.broadcast();
  StreamSubscription? _scanSub;
  bool _running = false;

  /// Stream of devices as they are discovered.
  Stream<DiscoveredDevice> get deviceStream => _controller.stream;

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_running) return;
    _running = true;

    try {
      // FlutterBluePlus requires Bluetooth to be on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        // ignore: avoid_print
        print('[BleDiscoverer] Bluetooth adapter is off, skipping BLE scan.');
        _running = false;
        return;
      }

      await FlutterBluePlus.startScan(
        withServices: [Guid(udcfServiceUuid)],
        timeout: timeout,
      );

      _scanSub = FlutterBluePlus.scanResults.listen(_handleResults);
    } catch (e) {
      // ignore: avoid_print
      print('[BleDiscoverer] scan error: $e');
      _running = false;
    }
  }

  Future<void> stopScan() async {
    _running = false;
    _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  void _handleResults(List<ScanResult> results) {
    for (final result in results) {
      _processResult(result);
    }
  }

  void _processResult(ScanResult result) {
    final ad = result.advertisementData;

    // ── Parse service data JSON if present ────────────────────────────────
    Map<String, dynamic> meta = {};
    final serviceDataEntry = ad.serviceData.entries
        .where((e) => e.key.toString().toLowerCase().contains('4fafc201'))
        .firstOrNull;

    if (serviceDataEntry != null) {
      try {
        meta = jsonDecode(utf8.decode(serviceDataEntry.value)) as Map<String, dynamic>;
      } catch (_) {}
    }

    final deviceId = (meta['device_id'] as String?)?.trim() ??
        result.device.remoteId.str.replaceAll(':', '').toLowerCase();
    final name = (meta['name'] as String?)?.trim().isNotEmpty == true
        ? meta['name'] as String
        : ad.advName.trim().isNotEmpty
            ? ad.advName.trim()
            : 'Unknown BLE Device';
    final type = (meta['type'] as String?)?.trim() ?? 'custom';

    _controller.add(DiscoveredDevice(
      deviceId: deviceId,
      name: name,
      type: type,
      transports: const {'bluetooth'},
      bleAddress: result.device.remoteId.str,
      rssi: result.rssi,
    ));
  }

  void dispose() {
    stopScan();
    _controller.close();
  }
}
