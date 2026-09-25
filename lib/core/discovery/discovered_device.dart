/// A device candidate found during network / BLE scanning.
///
/// A single physical device may be discoverable over multiple transports
/// (e.g. the same Raspberry Pi visible over Wi-Fi AND BLE). The [transports]
/// set holds all known transports; [mergeWith] combines two records for the
/// same [deviceId] into one authoritative entry.
class DiscoveredDevice {
  final String deviceId;
  final String name;
  final String type; // 'raspberry_pi' | 'robot' | 'pico' | 'esp32' | …
  final Set<String> transports; // {'wifi'} | {'bluetooth'} | {'wifi','bluetooth'}
  final String? ipAddress;
  final int? port;
  final String? bleAddress;
  final int? rssi;
  final DateTime discoveredAt;

  DiscoveredDevice({
    required this.deviceId,
    required this.name,
    required this.type,
    required this.transports,
    this.ipAddress,
    this.port,
    this.bleAddress,
    this.rssi,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  /// Preferred transport for initial connection: Wi-Fi over BLE when both available.
  String get primaryTransport =>
      transports.contains('wifi') ? 'wifi' : transports.first;

  bool get supportsWifi => transports.contains('wifi');
  bool get supportsBluetooth => transports.contains('bluetooth');

  /// True when last seen within 45 seconds.
  bool get isFresh =>
      DateTime.now().difference(discoveredAt).inSeconds < 45;

  /// Merge another scan hit for the same device — accumulates transports
  /// and refreshes addresses / RSSI without overwriting existing values.
  DiscoveredDevice mergeWith(DiscoveredDevice other) {
    assert(deviceId == other.deviceId);
    return DiscoveredDevice(
      deviceId: deviceId,
      name: other.name.isNotEmpty ? other.name : name,
      type: other.type.isNotEmpty ? other.type : type,
      transports: {...transports, ...other.transports},
      ipAddress: other.ipAddress ?? ipAddress,
      port: other.port ?? port,
      bleAddress: other.bleAddress ?? bleAddress,
      rssi: other.rssi ?? rssi,
      // Keep original discovery time so stale pruning is stable
      discoveredAt: discoveredAt,
    );
  }

  @override
  String toString() =>
      'DiscoveredDevice($deviceId, $name, transports=$transports)';
}
