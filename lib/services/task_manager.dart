import 'package:flutter/foundation.dart';
import '../core/models/task_model.dart';

/// Tracks state and progress of asynchronous tasks executed across devices.
class TaskManager extends ChangeNotifier {
  static final TaskManager _instance = TaskManager._();
  factory TaskManager() => _instance;
  TaskManager._();

  final Map<String, DeviceTask> _tasks = {};

  List<DeviceTask> get allTasks => _tasks.values.toList();

  List<DeviceTask> tasksForDevice(String deviceId) =>
      _tasks.values.where((t) => t.deviceId == deviceId).toList();

  List<DeviceTask> activeTasks(String deviceId) => _tasks.values
      .where((t) => t.deviceId == deviceId && t.state == TaskState.running)
      .toList();

  DeviceTask? getTask(String taskId) => _tasks[taskId];

  void addTask(DeviceTask task) {
    _tasks[task.taskId] = task;
    notifyListeners();
  }

  void updateTask(
    String taskId, {
    TaskState? state,
    double? progress,
    dynamic result,
    String? error,
  }) {
    final existing = _tasks[taskId];
    if (existing == null) return;

    final isDone = state == TaskState.completed ||
        state == TaskState.failed ||
        state == TaskState.cancelled;

    _tasks[taskId] = existing.copyWith(
      state: state,
      progress: progress,
      result: result,
      error: error,
      completedAt: isDone ? DateTime.now() : null,
    );
    notifyListeners();
  }

  void cancelTask(String taskId) {
    updateTask(taskId, state: TaskState.cancelled);
  }

  void clearCompleted() {
    _tasks.removeWhere((_, t) =>
        t.state == TaskState.completed ||
        t.state == TaskState.failed ||
        t.state == TaskState.cancelled);
    notifyListeners();
  }
}
