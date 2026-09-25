/// Lifecycle states for a device connection according to the Universal Device Control Framework.
enum DeviceConnectionState {
  /// Device is not reachable or known but not connected
  offline,

  /// Device is broadcasting availability (mDNS or BLE advertisement)
  advertising,

  /// Device has been detected by discovery scan
  discovered,

  /// Pairing handshake in progress (terminal confirmation or PIN)
  pairing,

  /// Authenticating credentials (PSK or session token)
  authenticating,

  /// Device is paired and trusted, but transport session not yet active
  paired,

  /// Transport active, negotiating protocol versions and capabilities
  negotiating,

  /// Fully connected and operational
  connected,

  /// An error occurred during communication
  error,

  /// In the process of closing the connection
  disconnecting,
}

extension DeviceConnectionStateExtension on DeviceConnectionState {
  String get label {
    switch (this) {
      case DeviceConnectionState.offline:
        return 'Offline';
      case DeviceConnectionState.advertising:
        return 'Advertising';
      case DeviceConnectionState.discovered:
        return 'Discovered';
      case DeviceConnectionState.pairing:
        return 'Pairing...';
      case DeviceConnectionState.authenticating:
        return 'Authenticating...';
      case DeviceConnectionState.paired:
        return 'Paired';
      case DeviceConnectionState.negotiating:
        return 'Negotiating...';
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.error:
        return 'Error';
      case DeviceConnectionState.disconnecting:
        return 'Disconnecting...';
    }
  }

  bool get isOperational => this == DeviceConnectionState.connected;
  bool get isConnecting =>
      this == DeviceConnectionState.pairing ||
      this == DeviceConnectionState.authenticating ||
      this == DeviceConnectionState.negotiating;
}
