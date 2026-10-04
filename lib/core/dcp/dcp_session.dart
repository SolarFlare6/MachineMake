import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../connection/connection_state_enum.dart';
import '../models/device_capability.dart';
import '../models/device_event.dart';
import '../models/device_manifest.dart';
import '../models/tool_definition.dart';
import '../transport/device_transport.dart';
import 'dcp_message.dart';

/// Manages a single DCP protocol session over a DeviceTransport.
/// Handles hello -> negotiate -> auth -> capabilities -> tools lifecycle.
class DcpSession {
  final DeviceTransport transport;
  final String clientId;
  final String? psk;

  DeviceConnectionState _state = DeviceConnectionState.offline;
  StreamSubscription<String>? _messageSubscription;
  final Map<String, Completer<DcpMessage>> _pending = {};
  final StreamController<DeviceEvent> _eventController =
      StreamController<DeviceEvent>.broadcast();

  List<DeviceCapability> _capabilities = [];
  List<ToolDefinition> _tools = [];
  DeviceManifest? _manifest;

  DcpSession({
    required this.transport,
    required this.clientId,
    this.psk,
  });

  DeviceConnectionState get state => _state;
  Stream<DeviceEvent> get events => _eventController.stream;
  List<DeviceCapability> get capabilities => List.unmodifiable(_capabilities);
  List<ToolDefinition> get tools => List.unmodifiable(_tools);
  DeviceManifest? get manifest => _manifest;

  /// Executes the full DCP connection and negotiation handshake.
  Future<void> connect() async {
    _state = DeviceConnectionState.authenticating;

    // Connect underlying transport
    await transport.connect();

    // Listen to messages
    _messageSubscription = transport.messageStream.listen(_handleIncomingMessage);

    // 1. Send Hello / get_device_info
    final helloMsg = DcpMessage.hello(
      appVersion: '1.0.0',
      protocolVersion: '1.0',
      clientId: clientId,
    );
    final helloAck = await sendRequest(helloMsg);
    final deviceName = (helloAck.payload['name'] ??
            helloAck.payload['device_id'] ??
            helloAck.payload['id'] ??
            'Device')
        .toString();
    final deviceType = (helloAck.payload['profile'] ??
            helloAck.payload['type'] ??
            helloAck.payload['deviceType'] ??
            helloAck.payload['device_type'] ??
            (transport.transportType == 'mock' ? 'robot' : 'computer'))
        .toString();
    final firmware = (helloAck.payload['firmware_version'] ?? '1.0').toString();

    // 2. Optional: Negotiate Protocol Version (ignore if unsupported on server)
    _state = DeviceConnectionState.negotiating;
    try {
      final negotiateMsg = DcpMessage.negotiate(selectedVersion: '1.0');
      await sendRequest(negotiateMsg, timeout: const Duration(seconds: 3));
    } catch (_) {}

    // 3. Authenticate if psk provided (two-step HMAC-SHA256 challenge-response)
    _state = DeviceConnectionState.authenticating;
    if (psk != null && psk!.isNotEmpty) {
      try {
        // Step 1: Send client_id to obtain a fresh nonce from the server
        final challengeMsg = DcpMessage.authenticateChallenge(clientId: clientId);
        final challengeAck = await sendRequest(challengeMsg, timeout: const Duration(seconds: 4));
        final nonce = (challengeAck.payload['nonce'] ??
                challengeAck.payload['data']?['nonce'])
            ?.toString();

        if (nonce != null && nonce.isNotEmpty) {
          // Step 2: Compute HMAC-SHA256(hex_secret, nonce_utf8)
          final secretBytes = _hexToBytes(psk!);
          final hmac = Hmac(sha256, secretBytes);
          final responseHex = hmac.convert(utf8.encode(nonce)).toString();

          final verifyMsg = DcpMessage.authenticateResponse(
            clientId: clientId,
            responseHex: responseHex,
          );
          await sendRequest(verifyMsg, timeout: const Duration(seconds: 4));
        } else {
          // Fallback for mock or legacy servers
          final authMsg = DcpMessage.auth(
            method: 'psk',
            token: psk!,
          );
          await sendRequest(authMsg, timeout: const Duration(seconds: 3));
        }
      } catch (_) {}
    }

    // 4. Retrieve Capabilities
    final capsMsg = DcpMessage.getCapabilities();
    final capsAck = await sendRequest(capsMsg);
    final capsList = (capsAck.payload['capabilities'] as List<dynamic>?) ?? [];
    _capabilities = capsList.map((c) => DeviceCapability.fromAny(c)).toList();

    // 5. Retrieve Tools
    final toolsMsg = DcpMessage.getTools();
    final toolsAck = await sendRequest(toolsMsg);
    final toolsList = (toolsAck.payload['tools'] as List<dynamic>?) ?? [];
    _tools = toolsList.map((t) {
      if (t is Map<String, dynamic>) {
        return ToolDefinition.fromJson(t);
      } else if (t is Map) {
        return ToolDefinition.fromJson(Map<String, dynamic>.from(t));
      }
      return ToolDefinition(name: t.toString(), description: '');
    }).toList();

    // 6. Subscribe to asynchronous device events
    try {
      await sendRequest(
        DcpMessage.subscribeEvents(
          ['telemetry', 'alert', 'imu_update', 'sensor_update', 'task_progress', 'task_completed'],
        ),
        timeout: const Duration(seconds: 3),
      );
    } catch (_) {}

    // 7. Request control ownership
    try {
      await sendRequest(DcpMessage.requestControl(), timeout: const Duration(seconds: 3));
    } catch (_) {}

    // Build Manifest
    final Map<String, dynamic> helloMetadata = {};
    if (helloAck.payload['metadata'] is Map<String, dynamic>) {
      helloMetadata.addAll(helloAck.payload['metadata'] as Map<String, dynamic>);
    } else if (helloAck.payload['metadata'] is Map) {
      helloMetadata.addAll(Map<String, dynamic>.from(helloAck.payload['metadata'] as Map));
    }
    if (helloAck.payload['ai'] != null) {
      helloMetadata['ai'] = helloAck.payload['ai'];
    }

    _manifest = DeviceManifest(
      deviceId: transport.deviceId,
      name: deviceName,
      type: deviceType,
      firmwareVersion: firmware,
      capabilities: _capabilities,
      tools: _tools,
      metadata: helloMetadata,
    );

    _state = DeviceConnectionState.connected;
  }

  /// Sends a DCP request and awaits the matching response by message ID.
  Future<DcpMessage> sendRequest(
    DcpMessage message, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final completer = Completer<DcpMessage>();
    _pending[message.msgId] = completer;

    final jsonStr = jsonEncode(message.toJson());
    await transport.send(jsonStr);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(message.msgId);
        throw TimeoutException('DCP request timed out (${message.command ?? message.type.wireName})');
      },
    );
  }

  /// Sends a DCP message without waiting for a response (fire-and-forget).
  Future<void> sendFireAndForget(DcpMessage message) async {
    try {
      final jsonStr = jsonEncode(message.toJson());
      await transport.send(jsonStr);
    } catch (_) {}
  }

  /// Executes a remote tool on the device.
  /// If [fireAndForget] is true, dispatches immediately without registering a pending response Completer.
  Future<DcpExecuteResponse> executeTool(
    String toolName,
    Map<String, dynamic> params, {
    bool fireAndForget = false,
  }) async {
    final msg = DcpMessage.execute(toolName: toolName, params: params);
    if (fireAndForget) {
      await sendFireAndForget(msg);
      return const DcpExecuteResponse(success: true);
    }
    final response = await sendRequest(msg);
    return DcpExecuteResponse.fromPayload(response.payload);
  }

  /// Alias for executeTool
  Future<DcpExecuteResponse> execute(
    String toolName,
    Map<String, dynamic> params, {
    bool fireAndForget = false,
  }) =>
      executeTool(toolName, params, fireAndForget: fireAndForget);

  /// Sends a DCP ping to verify remote device liveness.
  Future<bool> ping({Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final msg = DcpMessage.ping();
      final response = await sendRequest(msg, timeout: timeout);
      return response.payload['pong'] == true ||
          response.payload['success'] == true ||
          response.type == DcpMessageType.pong ||
          response.type == DcpMessageType.helloAck;
    } catch (_) {
      return false;
    }
  }

  void _handleIncomingMessage(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      final msg = DcpMessage.fromJson(json);

      // Check if this is a response to an awaiting request
      final replyKey = msg.replyTo ?? msg.msgId;
      if (_pending.containsKey(replyKey)) {
        _pending.remove(replyKey)!.complete(msg);
        return;
      }

      // Handle async event
      if (json['type'] == 'event' || msg.type == DcpMessageType.event) {
        final event = DeviceEvent.fromJson(json, defaultDeviceId: transport.deviceId);
        _eventController.add(event);
      }
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _state = DeviceConnectionState.disconnecting;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Session disconnected'));
      }
    }
    _pending.clear();
    await transport.disconnect();
    _state = DeviceConnectionState.offline;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }

  static List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      if (i + 2 <= clean.length) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
    }
    return bytes;
  }
}
