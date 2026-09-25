/// Execution states for asynchronous tasks triggered on devices.
enum TaskState {
  pending,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

extension TaskStateExtension on TaskState {
  String get label {
    switch (this) {
      case TaskState.pending:
        return 'Pending';
      case TaskState.running:
        return 'Running';
      case TaskState.paused:
        return 'Paused';
      case TaskState.completed:
        return 'Completed';
      case TaskState.failed:
        return 'Failed';
      case TaskState.cancelled:
        return 'Cancelled';
    }
  }

  static TaskState fromString(String val) {
    switch (val.toLowerCase()) {
      case 'running':
        return TaskState.running;
      case 'paused':
        return TaskState.paused;
      case 'completed':
      case 'success':
        return TaskState.completed;
      case 'failed':
      case 'error':
        return TaskState.failed;
      case 'cancelled':
      case 'canceled':
        return TaskState.cancelled;
      default:
        return TaskState.pending;
    }
  }
}

/// Represents an asynchronous task running on a remote device.
class DeviceTask {
  final String taskId;
  final String deviceId;
  final String toolName;
  final Map<String, dynamic> params;
  TaskState state;
  double progress; // 0.0 to 1.0
  dynamic result;
  String? error;
  final DateTime createdAt;
  DateTime? completedAt;

  DeviceTask({
    required this.taskId,
    required this.deviceId,
    required this.toolName,
    this.params = const {},
    this.state = TaskState.pending,
    this.progress = 0.0,
    this.result,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  DeviceTask copyWith({
    TaskState? state,
    double? progress,
    dynamic result,
    String? error,
    DateTime? completedAt,
  }) {
    return DeviceTask(
      taskId: taskId,
      deviceId: deviceId,
      toolName: toolName,
      params: params,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      error: error ?? this.error,
      createdAt: createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  factory DeviceTask.fromJson(Map<String, dynamic> json) {
    return DeviceTask(
      taskId: json['task_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      toolName: json['tool_name'] as String? ?? '',
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      state: TaskStateExtension.fromString(json['state'] as String? ?? 'pending'),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      result: json['result'],
      error: json['error'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'device_id': deviceId,
        'tool_name': toolName,
        'params': params,
        'state': state.name,
        'progress': progress,
        if (result != null) 'result': result,
        if (error != null) 'error': error,
        'created_at': createdAt.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      };
}
