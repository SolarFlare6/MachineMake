import 'package:uuid/uuid.dart';


/// Supported DCP message types for request/response and events.
enum DcpMessageType {
  // Requests
  hello,
  negotiate,
  auth,
  capabilities,
  tools,
  execute,
  taskStatus,
  taskCancel,
  subscribeEvents,
  unsubscribeEvents,
  ping,

  // Responses
  helloAck,
  negotiateAck,
  authAck,
  capabilitiesResponse,
  toolsResponse,
  executeResponse,
  taskUpdate,
  event,
  pong,
  error,
}

extension DcpMessageTypeExtension on DcpMessageType {
  String get wireName {
    switch (this) {
      case DcpMessageType.hello:
        return 'hello';
      case DcpMessageType.negotiate:
        return 'negotiate';
      case DcpMessageType.auth:
        return 'auth';
      case DcpMessageType.capabilities:
        return 'capabilities';
      case DcpMessageType.tools:
        return 'tools';
      case DcpMessageType.execute:
        return 'execute';
      case DcpMessageType.taskStatus:
        return 'task_status';
      case DcpMessageType.taskCancel:
        return 'task_cancel';
      case DcpMessageType.subscribeEvents:
        return 'subscribe_events';
      case DcpMessageType.unsubscribeEvents:
        return 'unsubscribe_events';
      case DcpMessageType.ping:
        return 'ping';
      case DcpMessageType.helloAck:
        return 'hello_ack';
      case DcpMessageType.negotiateAck:
        return 'negotiate_ack';
      case DcpMessageType.authAck:
        return 'auth_ack';
      case DcpMessageType.capabilitiesResponse:
        return 'capabilities_response';
      case DcpMessageType.toolsResponse:
        return 'tools_response';
      case DcpMessageType.executeResponse:
        return 'execute_response';
      case DcpMessageType.taskUpdate:
        return 'task_update';
      case DcpMessageType.event:
        return 'event';
      case DcpMessageType.pong:
        return 'pong';
      case DcpMessageType.error:
        return 'error';
    }
  }

  static DcpMessageType fromWireName(String wire) {
    switch (wire) {
      case 'hello':
        return DcpMessageType.hello;
      case 'negotiate':
        return DcpMessageType.negotiate;
      case 'auth':
        return DcpMessageType.auth;
      case 'capabilities':
        return DcpMessageType.capabilities;
      case 'tools':
        return DcpMessageType.tools;
      case 'execute':
        return DcpMessageType.execute;
      case 'task_status':
        return DcpMessageType.taskStatus;
      case 'task_cancel':
        return DcpMessageType.taskCancel;
      case 'subscribe_events':
        return DcpMessageType.subscribeEvents;
      case 'unsubscribe_events':
        return DcpMessageType.unsubscribeEvents;
      case 'ping':
        return DcpMessageType.ping;
      case 'hello_ack':
        return DcpMessageType.helloAck;
      case 'negotiate_ack':
        return DcpMessageType.negotiateAck;
      case 'auth_ack':
        return DcpMessageType.authAck;
      case 'capabilities_response':
        return DcpMessageType.capabilitiesResponse;
      case 'tools_response':
        return DcpMessageType.toolsResponse;
      case 'execute_response':
        return DcpMessageType.executeResponse;
      case 'task_update':
        return DcpMessageType.taskUpdate;
      case 'event':
        return DcpMessageType.event;
      case 'pong':
        return DcpMessageType.pong;
      case 'error':
        return DcpMessageType.error;
      default:
        return DcpMessageType.error;
    }
  }
}

/// Base DCP frame containing metadata and JSON payload.
class DcpMessage {
  static int _idCounter = 1;

  final String msgId;
  final DcpMessageType type;
  final String? command;
  final Map<String, dynamic> payload;
  final int timestampMs;
  final String? replyTo;

  DcpMessage({
    String? msgId,
    required this.type,
    this.command,
    required this.payload,
    int? timestampMs,
    this.replyTo,
  })  : msgId = msgId ?? '${_idCounter++}',
        timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  factory DcpMessage.fromJson(Map<String, dynamic> json) {
    final dcpType = json['type'] as String? ?? 'error';
    final idStr = (json['id'] ?? json['msg_id'] ?? const Uuid().v4()).toString();
    final replyStr = (json['reply_to'] ?? json['id'] ?? json['msg_id'])?.toString();
    final cmd = json['command'] as String?;

    DcpMessageType messageType;
    if (dcpType == 'response') {
      messageType = DcpMessageType.helloAck; // generic response / ack
    } else if (dcpType == 'event') {
      messageType = DcpMessageType.event;
    } else {
      messageType = DcpMessageTypeExtension.fromWireName(dcpType);
    }

    Map<String, dynamic> payloadData = {};
    if (json['data'] is Map<String, dynamic>) {
      payloadData = Map<String, dynamic>.from(json['data'] as Map<String, dynamic>);
      if (json['success'] != null) payloadData['success'] = json['success'];
      if (json['error'] != null) payloadData['error'] = json['error'];
      if (json['task_id'] != null) payloadData['task_id'] = json['task_id'];
    } else if (json['payload'] is Map<String, dynamic>) {
      payloadData = Map<String, dynamic>.from(json['payload'] as Map<String, dynamic>);
      if (json['success'] != null) payloadData['success'] = json['success'];
      if (json['error'] != null) payloadData['error'] = json['error'];
      if (json['task_id'] != null) payloadData['task_id'] = json['task_id'];
    } else if (json['data'] != null) {
      payloadData = {
        'data': json['data'],
        if (json['success'] != null) 'success': json['success'],
        if (json['error'] != null) 'error': json['error'],
        if (json['task_id'] != null) 'task_id': json['task_id'],
      };
    } else {
      payloadData = Map<String, dynamic>.from(json);
    }

    return DcpMessage(
      msgId: idStr,
      type: messageType,
      command: cmd,
      payload: payloadData,
      timestampMs: json['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      replyTo: replyStr,
    );
  }

  Map<String, dynamic> toJson() {
    final intId = int.tryParse(msgId);
    final isEvent = type == DcpMessageType.event;
    final isAckOrResponse = type.wireName.contains('ack') || type.wireName.contains('response');

    return {
      'dcp': '1.0',
      'type': isEvent ? 'event' : (isAckOrResponse ? 'response' : 'request'),
      if (intId != null) 'id': intId else 'id': msgId,
      'msg_id': msgId,
      if (command != null) 'command': command,
      'arguments': payload,
      'payload': payload,
      'timestamp_ms': timestampMs,
      if (replyTo != null) 'reply_to': replyTo,
    };
  }

  // Factory helpers for common messages
  static DcpMessage hello({
    required String appVersion,
    required String protocolVersion,
    required String clientId,
  }) =>
      DcpMessage(
        type: DcpMessageType.hello,
        command: 'get_device_info',
        payload: {
          'app_version': appVersion,
          'protocol_version': protocolVersion,
          'client_id': clientId,
        },
      );

  static DcpMessage getDeviceInfo() => DcpMessage(
        type: DcpMessageType.hello,
        command: 'get_device_info',
        payload: {},
      );

  static DcpMessage negotiate({required String selectedVersion}) => DcpMessage(
        type: DcpMessageType.negotiate,
        command: 'negotiate',
        payload: {'selected_version': selectedVersion},
      );

  static DcpMessage auth({required String method, required String token}) =>
      DcpMessage(
        type: DcpMessageType.auth,
        command: 'authenticate',
        payload: {'method': method, 'token': token},
      );

  static DcpMessage authenticateChallenge({required String clientId}) =>
      DcpMessage(
        type: DcpMessageType.auth,
        command: 'authenticate',
        payload: {'client_id': clientId},
      );

  static DcpMessage authenticateResponse({
    required String clientId,
    required String responseHex,
  }) =>
      DcpMessage(
        type: DcpMessageType.auth,
        command: 'authenticate',
        payload: {
          'client_id': clientId,
          'response': responseHex,
        },
      );

  static DcpMessage raw({
    required String command,
    required Map<String, dynamic> arguments,
  }) =>
      DcpMessage(
        type: DcpMessageType.execute,
        command: command,
        payload: arguments,
      );

  static DcpMessage getCapabilities() => DcpMessage(
        type: DcpMessageType.capabilities,
        command: 'get_capabilities',
        payload: {},
      );

  static DcpMessage getTools() => DcpMessage(
        type: DcpMessageType.tools,
        command: 'get_tools',
        payload: {},
      );

  static DcpMessage execute({
    required String toolName,
    required Map<String, dynamic> params,
    String? taskId,
  }) =>
      DcpMessage(
        type: DcpMessageType.execute,
        command: 'execute_tool',
        payload: {
          'tool': toolName,
          'tool_name': toolName,
          'parameters': params,
          'params': params,
          if (taskId != null) 'task_id': taskId,
        },
      );

  static DcpMessage subscribeEvents(List<String> eventTypes) => DcpMessage(
        type: DcpMessageType.subscribeEvents,
        command: 'subscribe',
        payload: {
          'events': eventTypes,
          'event_types': eventTypes,
        },
      );

  static DcpMessage requestControl() => DcpMessage(
        type: DcpMessageType.execute,
        command: 'request_control',
        payload: {},
      );

  static DcpMessage ping() => DcpMessage(
        type: DcpMessageType.ping,
        command: 'ping',
        payload: {},
      );
}

/// Typed wrapper for execute response
class DcpExecuteResponse {
  final bool success;
  final dynamic result;
  final String? error;
  final String? taskId;

  const DcpExecuteResponse({
    required this.success,
    this.result,
    this.error,
    this.taskId,
  });

  factory DcpExecuteResponse.fromPayload(Map<String, dynamic> payload) {
    return DcpExecuteResponse(
      success: payload['success'] as bool? ?? (payload['error'] == null),
      result: payload['result'] ?? payload['data'],
      error: payload['error'] is Map
          ? (payload['error'] as Map)['message']?.toString()
          : payload['error'] as String?,
      taskId: payload['task_id'] as String?,
    );
  }
}
