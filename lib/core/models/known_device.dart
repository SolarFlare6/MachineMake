/// Represents a known/paired device persisted across app sessions.
class KnownDevice {
  final String deviceId;
  final String name;
  final String type;
  final String? psk;
  final String? lastIp;
  final int? lastPort;
  final String? lastBleAddress;
  final String? sshUsername;
  final String? sshPassword;
  final int? sshPort;
  final DateTime pairedAt;
  DateTime lastSeenAt;
  bool isTrusted;

  KnownDevice({
    required this.deviceId,
    required this.name,
    required this.type,
    this.psk,
    this.lastIp,
    this.lastPort,
    this.lastBleAddress,
    this.sshUsername,
    this.sshPassword,
    this.sshPort,
    DateTime? pairedAt,
    DateTime? lastSeenAt,
    this.isTrusted = true,
  })  : pairedAt = pairedAt ?? DateTime.now(),
        lastSeenAt = lastSeenAt ?? DateTime.now();

  KnownDevice copyWith({
    String? name,
    String? type,
    String? psk,
    String? lastIp,
    int? lastPort,
    String? lastBleAddress,
    String? sshUsername,
    String? sshPassword,
    int? sshPort,
    bool clearSsh = false,
    DateTime? lastSeenAt,
    bool? isTrusted,
  }) {
    return KnownDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      type: type ?? this.type,
      psk: psk ?? this.psk,
      lastIp: lastIp ?? this.lastIp,
      lastPort: lastPort ?? this.lastPort,
      lastBleAddress: lastBleAddress ?? this.lastBleAddress,
      sshUsername: clearSsh ? null : (sshUsername ?? this.sshUsername),
      sshPassword: clearSsh ? null : (sshPassword ?? this.sshPassword),
      sshPort: clearSsh ? null : (sshPort ?? this.sshPort),
      pairedAt: pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isTrusted: isTrusted ?? this.isTrusted,
    );
  }

  factory KnownDevice.fromJson(Map<String, dynamic> json) {
    return KnownDevice(
      deviceId: (json['device_id'] ?? json['deviceId'] ?? json['id'] ?? '') as String,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'custom',
      psk: json['psk'] as String?,
      lastIp: json['last_ip'] as String?,
      lastPort: json['last_port'] as int?,
      lastBleAddress: json['last_ble_address'] as String?,
      sshUsername: json['ssh_username'] as String?,
      sshPassword: json['ssh_password'] as String?,
      sshPort: json['ssh_port'] as int?,
      pairedAt: json['paired_at'] != null
          ? DateTime.tryParse(json['paired_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isTrusted: json['is_trusted'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': name,
        'type': type,
        if (psk != null) 'psk': psk,
        if (lastIp != null) 'last_ip': lastIp,
        if (lastPort != null) 'last_port': lastPort,
        if (lastBleAddress != null) 'last_ble_address': lastBleAddress,
        if (sshUsername != null) 'ssh_username': sshUsername,
        if (sshPassword != null) 'ssh_password': sshPassword,
        if (sshPort != null) 'ssh_port': sshPort,
        'paired_at': pairedAt.toIso8601String(),
        'last_seen_at': lastSeenAt.toIso8601String(),
        'is_trusted': isTrusted,
      };
}
