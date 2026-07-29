import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';

class TaskDefinition {
  final String label;
  final String command;
  final String? dependsOn;
  final bool isBackground;
  final Map<String, String>? env;
  final String source;
  final bool isFavorite;

  const TaskDefinition({
    required this.label,
    required this.command,
    this.dependsOn,
    this.isBackground = false,
    this.env,
    this.source = 'custom',
    this.isFavorite = false,
  });

  TaskDefinition copyWith({
    String? label,
    String? command,
    String? dependsOn,
    bool? isBackground,
    Map<String, String>? env,
    String? source,
    bool? isFavorite,
  }) {
    return TaskDefinition(
      label: label ?? this.label,
      command: command ?? this.command,
      dependsOn: dependsOn ?? this.dependsOn,
      isBackground: isBackground ?? this.isBackground,
      env: env ?? this.env,
      source: source ?? this.source,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  factory TaskDefinition.fromJson(Map<String, dynamic> json) {
    return TaskDefinition(
      label: json['label'] ?? '',
      command: json['command'] ?? '',
      dependsOn: json['dependsOn'],
      isBackground: json['isBackground'] ?? false,
      env: json['env'] != null ? Map<String, String>.from(json['env']) : null,
      source: json['source'] ?? 'custom',
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'command': command,
      if (dependsOn != null) 'dependsOn': dependsOn,
      if (isBackground) 'isBackground': isBackground,
      if (env != null) 'env': env,
      'source': source,
      'isFavorite': isFavorite,
    };
  }
}

class TaskRunnerState {
  final List<TaskDefinition> tasks;
  final String? lastRunTask;
  final bool isRunning;

  const TaskRunnerState({
    this.tasks = const [],
    this.lastRunTask,
    this.isRunning = false,
  });

  TaskRunnerState copyWith({
    List<TaskDefinition>? tasks,
    String? lastRunTask,
    bool? isRunning,
  }) {
    return TaskRunnerState(
      tasks: tasks ?? this.tasks,
      lastRunTask: lastRunTask ?? this.lastRunTask,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

class TaskRunnerService extends StateNotifier<TaskRunnerState> {
  final Ref ref;

  TaskRunnerService(this.ref) : super(const TaskRunnerState()) {
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    final allTasks = <TaskDefinition>[];
    allTasks.addAll(await _parsePubspec(workspacePath));
    allTasks.addAll(await _parsePackageJson(workspacePath));
    allTasks.addAll(await _parseMakefile(workspacePath));
    allTasks.addAll(await _parseCustomTasks(workspacePath));

    state = state.copyWith(tasks: allTasks);
  }

  Future<List<TaskDefinition>> _parsePubspec(String workspacePath) async {
    final pubspecFile = File(p.join(workspacePath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return [];

    try {
      final content = await pubspecFile.readAsString();
      final tasks = <TaskDefinition>[];
      final lines = content.split('\n');
      bool inScripts = false;

      for (final line in lines) {
        if (line.trimRight() == 'scripts:') {
          inScripts = true;
          continue;
        }
        if (inScripts) {
          if (line.startsWith('  ') && line.trim().isNotEmpty) {
            final match = RegExp(r'^\s+(\w+):\s+(.+)$').firstMatch(line);
            if (match != null) {
              final name = match.group(1)!;
              final cmd = match.group(2)!;
              tasks.add(TaskDefinition(
                label: name,
                command: cmd,
                source: 'pubspec',
              ));
            }
          } else if (line.trim().isNotEmpty && !line.startsWith(' ')) {
            inScripts = false;
          }
        }
      }
      return tasks;
    } catch (e) {
      return [];
    }
  }

  Future<List<TaskDefinition>> _parsePackageJson(String workspacePath) async {
    final packageFile = File(p.join(workspacePath, 'package.json'));
    if (!await packageFile.exists()) return [];

    try {
      final content = await packageFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final scripts = json['scripts'] as Map<String, dynamic>?;
      if (scripts == null) return [];

      return scripts.entries.map((e) => TaskDefinition(
        label: e.key,
        command: e.value.toString(),
        source: 'package.json',
      )).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<TaskDefinition>> _parseMakefile(String workspacePath) async {
    final makefile = File(p.join(workspacePath, 'Makefile'));
    if (!await makefile.exists()) return [];

    try {
      final content = await makefile.readAsString();
      final tasks = <TaskDefinition>[];
      final lines = content.split('\n');
      final targetPattern = RegExp(r'^(\w[\w-]*)\s*:');

      for (final line in lines) {
        final match = targetPattern.firstMatch(line);
        if (match != null) {
          final name = match.group(1)!;
          if (!name.startsWith('.')) {
            tasks.add(TaskDefinition(
              label: name,
              command: 'make $name',
              source: 'Makefile',
            ));
          }
        }
      }
      return tasks;
    } catch (e) {
      return [];
    }
  }

  Future<List<TaskDefinition>> _parseCustomTasks(String workspacePath) async {
    final tasksFile = File(p.join(workspacePath, '.quantum', 'tasks.json'));
    if (!await tasksFile.exists()) return [];

    try {
      final content = await tasksFile.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((j) => TaskDefinition.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveCustomTasks() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    final dir = Directory(p.join(workspacePath, '.quantum'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final customTasks = state.tasks.where((t) => t.source == 'custom').toList();
    final tasksFile = File(p.join(workspacePath, '.quantum', 'tasks.json'));
    final jsonList = customTasks.map((t) => t.toJson()).toList();
    await tasksFile.writeAsString(jsonEncode(jsonList));
  }

  Future<void> addTask(TaskDefinition task) async {
    state = state.copyWith(tasks: [...state.tasks, task]);
    await saveCustomTasks();
  }

  Future<void> removeTask(int index) async {
    final tasks = List<TaskDefinition>.from(state.tasks);
    final removed = tasks.removeAt(index);
    state = state.copyWith(tasks: tasks);
    if (removed.source == 'custom') {
      await saveCustomTasks();
    }
  }

  Future<void> toggleFavorite(int index) async {
    final tasks = List<TaskDefinition>.from(state.tasks);
    tasks[index] = tasks[index].copyWith(isFavorite: !tasks[index].isFavorite);
    state = state.copyWith(tasks: tasks);
    await saveCustomTasks();
  }

  Future<void> runTask(int index) async {
    if (index < 0 || index >= state.tasks.length) return;
    final task = state.tasks[index];

    state = state.copyWith(isRunning: true, lastRunTask: task.label);

    final terminalNotifier = ref.read(terminalTabsProvider.notifier);
    terminalNotifier.sendCommand(task.command);

    state = state.copyWith(isRunning: false);
  }

  List<TaskDefinition> get favoriteTasks =>
      state.tasks.where((t) => t.isFavorite).toList();

  List<TaskDefinition> get tasksBySource {
    final grouped = <String, List<TaskDefinition>>{};
    for (final task in state.tasks) {
      grouped.putIfAbsent(task.source, () => []).add(task);
    }
    final result = <TaskDefinition>[];
    for (final source in grouped.keys) {
      result.addAll(grouped[source]!);
    }
    return result;
  }

  void refresh() {
    _loadTasks();
  }
}

final taskRunnerProvider = StateNotifierProvider<TaskRunnerService, TaskRunnerState>((ref) {
  return TaskRunnerService(ref);
});
