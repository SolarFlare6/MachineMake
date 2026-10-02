import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';

import '../discovery/discovered_device.dart';

/// Browses for UDCF devices advertised over mDNS / DNS-SD.
///
/// Devices must register a `_dcp._tcp` service and include the following
/// TXT record key=value pairs:
///   device_id: unique device id
///   type: raspberry_pi, robot, pico, esp32, arduino, laptop, custom
///   profile: quadruped, computer, microcontroller, generic
///   protocol: 1.0
class MdnsDiscoverer {
  static const String _serviceType = '_dcp._tcp';

  final _controller = StreamController<DiscoveredDevice>.broadcast();
  MDnsClient? _client;
  bool _running = false;

  /// Stream of devices as they are discovered.
  Stream<DiscoveredDevice> get deviceStream => _controller.stream;

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_running) return;
    _running = true;

    _client = MDnsClient();

    try {
      await _client!.start();
      await _browse(timeout);
    } catch (e) {
      // mDNS may fail on emulators or in restricted networks — log and continue.
      // ignore: avoid_print
      print('[MdnsDiscoverer] scan error: $e');
    } finally {
      _client?.stop();
      _running = false;
    }
  }

  Future<void> stopScan() async {
    _running = false;
    _client?.stop();
  }

  Future<void> _browse(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);

    try {
      await for (final PtrResourceRecord ptr in _client!
          .lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_serviceType))) {
        if (!_running || DateTime.now().isAfter(deadline)) break;

        final serviceName = ptr.domainName;
        await _resolveSrv(serviceName);
      }
    } catch (_) {}
  }

  Future<void> _resolveSrv(String serviceName) async {
    String? host;
    int? port;
    Map<String, String> txtValues = {};

    // Resolve SRV (host + port)
    try {
      await for (final SrvResourceRecord srv in _client!
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(serviceName))) {
        host = srv.target;
        port = srv.port;
        break;
      }
    } catch (_) {}

    if (host == null || port == null) return;

    // Resolve TXT metadata
    try {
      await for (final TxtResourceRecord txt in _client!
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(serviceName))) {
        txtValues = _parseTxt(txt.text);
        break;
      }
    } catch (_) {}

    // Resolve IP address
    try {
      await for (final IPAddressResourceRecord ip in _client!
          .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(host))) {
        final ipStr = ip.address.address;
        final deviceId = txtValues['device_id'] ?? _deriveId(serviceName);
        final name = txtValues['name'] ?? serviceName.split('.').first;
        final type = txtValues['profile'] ?? txtValues['type'] ?? 'generic';

        _controller.add(DiscoveredDevice(
          deviceId: deviceId,
          name: name,
          type: type,
          transports: const {'wifi'},
          ipAddress: ipStr,
          port: port,
        ));
        break;
      }
    } catch (_) {}
  }

  /// Parses "key=value" style TXT record text, supporting null-bytes, commas, and newlines.
  Map<String, String> _parseTxt(String text) {
    final result = <String, String>{};
    for (final line in text.split(RegExp(r'[\n\r\x00,]+'))) {
      final eq = line.indexOf('=');
      if (eq > 0) {
        final key = line.substring(0, eq).trim().toLowerCase();
        final value = line.substring(eq + 1).trim();
        result[key] = value;
      }
    }
    return result;
  }

  String _deriveId(String serviceName) =>
      serviceName.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '-').toLowerCase();

  void dispose() {
    _running = false;
    _client?.stop();
    _controller.close();
  }
}
