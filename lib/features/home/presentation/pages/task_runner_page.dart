import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/task_runner_service.dart';

class TaskRunnerPage extends ConsumerStatefulWidget {
  const TaskRunnerPage({super.key});

  @override
  ConsumerState<TaskRunnerPage> createState() => _TaskRunnerPageState();
}

class _TaskRunnerPageState extends ConsumerState<TaskRunnerPage> {
  final _labelController = TextEditingController();
  final _commandController = TextEditingController();
  String _selectedSource = 'all';

  @override
  void dispose() {
    _labelController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  List<TaskDefinition> _filteredTasks(TaskRunnerState state) {
    if (_selectedSource == 'all') return state.tasks;
    if (_selectedSource == 'favorites') return state.tasks.where((t) => t.isFavorite).toList();
    return state.tasks.where((t) => t.source == _selectedSource).toList();
  }

  void _showAddTaskDialog() {
    _labelController.clear();
    _commandController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                hintText: 'Task label',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commandController,
              decoration: const InputDecoration(
                hintText: 'Command to run',
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_labelController.text.isNotEmpty && _commandController.text.isNotEmpty) {
                ref.read(taskRunnerProvider.notifier).addTask(TaskDefinition(
                  label: _labelController.text.trim(),
                  command: _commandController.text.trim(),
                  source: 'custom',
                ));
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final taskState = ref.watch(taskRunnerProvider);
    final filteredTasks = _filteredTasks(taskState);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.circle_play, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('Task Runner', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'favorites', label: Text('★', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'pubspec', label: Text('pub', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'package.json', label: Text('npm', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'Makefile', label: Text('make', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: 'custom', label: Text('custom', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_selectedSource},
                  onSelectionChanged: (v) => setState(() => _selectedSource = v.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _showAddTaskDialog,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  tooltip: 'Add custom task',
                ),
                IconButton(
                  onPressed: () => ref.read(taskRunnerProvider.notifier).refresh(),
                  icon: const Icon(LucideIcons.refresh_cw, size: 16),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.circle_play, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('No tasks found', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      final globalIndex = taskState.tasks.indexOf(task);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: _sourceIcon(task.source, colorScheme),
                          title: Text(task.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text(
                            task.command,
                            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  task.isFavorite ? LucideIcons.star : LucideIcons.star,
                                  size: 14,
                                  color: task.isFavorite ? Colors.amber : colorScheme.onSurfaceVariant,
                                ),
                                onPressed: () => ref.read(taskRunnerProvider.notifier).toggleFavorite(globalIndex),
                                tooltip: 'Favorite',
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                icon: taskState.isRunning && taskState.lastRunTask == task.label
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(LucideIcons.play, size: 14),
                                onPressed: taskState.isRunning
                                    ? null
                                    : () => ref.read(taskRunnerProvider.notifier).runTask(globalIndex),
                                tooltip: 'Run',
                                visualDensity: VisualDensity.compact,
                              ),
                              if (task.source == 'custom')
                                IconButton(
                                  icon: const Icon(LucideIcons.trash_2, size: 14),
                                  onPressed: () => ref.read(taskRunnerProvider.notifier).removeTask(globalIndex),
                                  tooltip: 'Remove',
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sourceIcon(String source, ColorScheme colorScheme) {
    IconData icon;
    Color color;
    switch (source) {
      case 'pubspec':
        icon = LucideIcons.gem;
        color = Colors.blue;
        break;
      case 'package.json':
        icon = LucideIcons.box;
        color = Colors.green;
        break;
      case 'Makefile':
        icon = LucideIcons.wrench;
        color = Colors.orange;
        break;
      default:
        icon = LucideIcons.terminal;
        color = colorScheme.primary;
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
