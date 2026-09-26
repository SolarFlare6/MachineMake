import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/models/task_model.dart';
import '../services/task_manager.dart';
import '../theme/app_theme.dart';

/// Displays a single [DeviceTask]'s state, progress, and a cancel button.
/// Listens to [TaskManager] for live updates.
class TaskProgressWidget extends StatelessWidget {
  final String taskId;

  const TaskProgressWidget({super.key, required this.taskId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TaskManager(),
      builder: (context, _) {
        final task = TaskManager().getTask(taskId);
        if (task == null) return const SizedBox.shrink();
        return _TaskCard(task: task);
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  final DeviceTask task;

  const _TaskCard({required this.task});

  Color get _stateColor {
    switch (task.state) {
      case TaskState.running:
        return AppTheme.primaryOrange;
      case TaskState.completed:
        return Colors.greenAccent;
      case TaskState.failed:
        return Colors.redAccent;
      case TaskState.cancelled:
        return AppTheme.textMuted;
      case TaskState.paused:
        return Colors.amberAccent;
      default:
        return AppTheme.textMuted;
    }
  }

  IconData get _stateIcon {
    switch (task.state) {
      case TaskState.running:
        return Icons.sync;
      case TaskState.completed:
        return Icons.check_circle_outline;
      case TaskState.failed:
        return Icons.error_outline;
      case TaskState.cancelled:
        return Icons.cancel_outlined;
      case TaskState.paused:
        return Icons.pause_circle_outline;
      default:
        return Icons.hourglass_empty;
    }
  }

  String get _stateLabel {
    switch (task.state) {
      case TaskState.running:
        return 'Running';
      case TaskState.completed:
        return 'Completed';
      case TaskState.failed:
        return 'Failed';
      case TaskState.cancelled:
        return 'Cancelled';
      case TaskState.paused:
        return 'Paused';
      case TaskState.pending:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = task.state == TaskState.running || task.state == TaskState.paused;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _stateColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_stateIcon, color: _stateColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.toolName,
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              // State badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _stateColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _stateColor.withAlpha(80)),
                ),
                child: Text(
                  _stateLabel.toUpperCase(),
                  style: GoogleFonts.exo2(
                    color: _stateColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => TaskManager().cancelTask(task.taskId),
                  child: const Icon(Icons.close, color: AppTheme.textMuted, size: 18),
                ),
              ],
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: task.state == TaskState.running ? task.progress : null,
              backgroundColor: AppTheme.darkBorder,
              valueColor: AlwaysStoppedAnimation(_stateColor),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 4),
            Text(
              '${(task.progress * 100).round()}%',
              style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
            ),
          ],
          if (task.error != null) ...[
            const SizedBox(height: 6),
            Text(
              task.error!,
              style: GoogleFonts.exo2(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          if (task.result != null && task.state == TaskState.completed) ...[
            const SizedBox(height: 6),
            Text(
              'Result: ${task.result}',
              style: GoogleFonts.exo2(color: Colors.greenAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Task: ${task.taskId.substring(0, task.taskId.length.clamp(0, 12))}…  •  Device: ${task.deviceId}',
            style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
