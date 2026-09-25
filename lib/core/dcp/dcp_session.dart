import 'dart:async';
import 'dart:convert';

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

    // 1. Send Hello
    final helloMsg = DcpMessage.hello(
      appVersion: '1.0.0',
      protocolVersion: '1.0',
      clientId: clientId,
    );
    final helloAck = await sendRequest(helloMsg);
    final deviceName = helloAck.payload['name'] as String? ?? 'Device';
    final firmware = helloAck.payload['firmware_version'] as String? ?? '1.0';

    // 2. Negotiate Protocol Version
    _state = DeviceConnectionState.negotiating;
    final negotiateMsg = DcpMessage.negotiate(selectedVersion: '1.0');
    await sendRequest(negotiateMsg);

    // 3. Authenticate
    _state = DeviceConnectionState.authenticating;
    final authMsg = DcpMessage.auth(
      method: psk != null ? 'psk' : 'none',
      token: psk ?? '',
    );
    final authAck = await sendRequest(authMsg);
    final authSuccess = authAck.payload['success'] as bool? ?? false;
    if (!authSuccess && psk != null) {
      _state = DeviceConnectionState.error;
      throw Exception('Authentication failed with device ${transport.deviceId}');
    }

    // 4. Retrieve Capabilities
    final capsMsg = DcpMessage.getCapabilities();
    final capsAck = await sendRequest(capsMsg);
    final capsList = (capsAck.payload['capabilities'] as List<dynamic>?) ?? [];
    _capabilities = capsList
        .map((c) => DeviceCapability.fromJson(c as Map<String, dynamic>))
        .toList();

    // 5. Retrieve Tools
    final toolsMsg = DcpMessage.getTools();
    final toolsAck = await sendRequest(toolsMsg);
    final toolsList = (toolsAck.payload['tools'] as List<dynamic>?) ?? [];
    _tools = toolsList
        .map((t) => ToolDefinition.fromJson(t as Map<String, dynamic>))
        .toList();

    // 6. Subscribe to all asynchronous device events
    await transport.send(jsonEncode(
      DcpMessage.subscribeEvents(['telemetry', 'alert', 'gpio_change']).toJson(),
    ));

    // Build Manifest
    _manifest = DeviceManifest(
      deviceId: transport.deviceId,
      name: deviceName,
      type: transport.transportType == 'mock' ? 'robot' : 'custom',
      firmwareVersion: firmware,
      capabilities: _capabilities,
      tools: _tools,
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
        throw TimeoutException('DCP request timed out (${message.type.wireName})');
      },
    );
  }

  /// Executes a remote tool on the device.
  Future<DcpExecuteResponse> executeTool(
    String toolName,
    Map<String, dynamic> params,
  ) async {
    final msg = DcpMessage.execute(toolName: toolName, params: params);
    final response = await sendRequest(msg);
    return DcpExecuteResponse.fromPayload(response.payload);
  }

  void _handleIncomingMessage(String rawJson) {
    try {
      final json = jsonDecode(rawJson) as Map<String, dynamic>;
      final msg = DcpMessage.fromJson(json);

      // Check if this is a response to an awaiting request
      final replyTo = msg.replyTo;
      if (replyTo != null && _pending.containsKey(replyTo)) {
        _pending.remove(replyTo)!.complete(msg);
        return;
      }

      // Handle async event
      if (msg.type == DcpMessageType.event) {
        final event = DeviceEvent.fromJson(msg.payload, defaultDeviceId: transport.deviceId);
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
}
