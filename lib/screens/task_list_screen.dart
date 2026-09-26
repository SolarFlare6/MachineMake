import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/models/task_model.dart';
import '../services/task_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/task_progress_widget.dart';

/// Lists all active and recent tasks across all connected devices.
/// Auto-refreshes via TaskManager ChangeNotifier.
class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          'Active Tasks',
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          ListenableBuilder(
            listenable: TaskManager(),
            builder: (context, _) {
              final hasCompleted = TaskManager().allTasks.any(
                (t) => t.state == TaskState.completed ||
                    t.state == TaskState.failed ||
                    t.state == TaskState.cancelled,
              );
              if (!hasCompleted) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => TaskManager().clearCompleted(),
                child: Text(
                  'Clear Done',
                  style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 13),
                ),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: TaskManager(),
        builder: (context, _) {
          final tasks = TaskManager().allTasks;

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.task_alt,
                    size: 64,
                    color: AppTheme.textMuted.withAlpha(80),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tasks yet',
                    style: GoogleFonts.exo2(
                      color: AppTheme.textMuted,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tasks appear here when you invoke tools on connected devices.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          // Separate active from completed
          final active = tasks.where((t) =>
              t.state == TaskState.running ||
              t.state == TaskState.pending ||
              t.state == TaskState.paused).toList();
          final done = tasks.where((t) =>
              t.state == TaskState.completed ||
              t.state == TaskState.failed ||
              t.state == TaskState.cancelled).toList();

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              if (active.isNotEmpty) ...[
                Text(
                  'Active  (${active.length})',
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ...active.map((t) => TaskProgressWidget(taskId: t.taskId)),
                const SizedBox(height: 20),
              ],
              if (done.isNotEmpty) ...[
                Text(
                  'Completed  (${done.length})',
                  style: GoogleFonts.exo2(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ...done.map((t) => TaskProgressWidget(taskId: t.taskId)),
              ],
            ],
          );
        },
      ),
    );
  }
}
