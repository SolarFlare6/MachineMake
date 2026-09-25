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
  static const _uuid = Uuid();

  final String msgId;
  final DcpMessageType type;
  final Map<String, dynamic> payload;
  final int timestampMs;
  final String? replyTo;

  DcpMessage({
    String? msgId,
    required this.type,
    required this.payload,
    int? timestampMs,
    this.replyTo,
  })  : msgId = msgId ?? _uuid.v4(),
        timestampMs = timestampMs ?? DateTime.now().millisecondsSinceEpoch;

  factory DcpMessage.fromJson(Map<String, dynamic> json) {
    return DcpMessage(
      msgId: json['msg_id'] as String? ?? const Uuid().v4(),
      type: DcpMessageTypeExtension.fromWireName(json['type'] as String? ?? 'error'),
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      timestampMs: json['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      replyTo: json['reply_to'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'msg_id': msgId,
        'type': type.wireName,
        'payload': payload,
        'timestamp_ms': timestampMs,
        if (replyTo != null) 'reply_to': replyTo,
      };

  // Factory helpers for common messages
  static DcpMessage hello({
    required String appVersion,
    required String protocolVersion,
    required String clientId,
  }) =>
      DcpMessage(
        type: DcpMessageType.hello,
        payload: {
          'app_version': appVersion,
          'protocol_version': protocolVersion,
          'client_id': clientId,
        },
      );

  static DcpMessage negotiate({required String selectedVersion}) => DcpMessage(
        type: DcpMessageType.negotiate,
        payload: {'selected_version': selectedVersion},
      );

  static DcpMessage auth({required String method, required String token}) =>
      DcpMessage(
        type: DcpMessageType.auth,
        payload: {'method': method, 'token': token},
      );

  static DcpMessage getCapabilities() => DcpMessage(
        type: DcpMessageType.capabilities,
        payload: {},
      );

  static DcpMessage getTools() => DcpMessage(
        type: DcpMessageType.tools,
        payload: {},
      );

  static DcpMessage execute({
    required String toolName,
    required Map<String, dynamic> params,
    String? taskId,
  }) =>
      DcpMessage(
        type: DcpMessageType.execute,
        payload: {
          'tool_name': toolName,
          'params': params,
          if (taskId != null) 'task_id': taskId,
        },
      );

  static DcpMessage subscribeEvents(List<String> eventTypes) => DcpMessage(
        type: DcpMessageType.subscribeEvents,
        payload: {'event_types': eventTypes},
      );

  static DcpMessage ping() => DcpMessage(
        type: DcpMessageType.ping,
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
      success: payload['success'] as bool? ?? false,
      result: payload['result'],
      error: payload['error'] as String?,
      taskId: payload['task_id'] as String?,
    );
  }
}
