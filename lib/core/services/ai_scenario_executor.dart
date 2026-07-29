import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

class ScenarioAction {
  final String type;
  final Map<String, dynamic> params;
  final String? description;

  ScenarioAction({
    required this.type,
    this.params = const {},
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'params': params,
    'description': description,
  };

  factory ScenarioAction.fromJson(Map<String, dynamic> json) => ScenarioAction(
    type: json['type'] ?? '',
    params: Map<String, dynamic>.from(json['params'] ?? {}),
    description: json['description'],
  );
}

class ScenarioCondition {
  final String type;
  final Map<String, dynamic> params;

  ScenarioCondition({
    required this.type,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'params': params,
  };

  factory ScenarioCondition.fromJson(Map<String, dynamic> json) => ScenarioCondition(
    type: json['type'] ?? '',
    params: Map<String, dynamic>.from(json['params'] ?? {}),
  );
}

class ScenarioRollback {
  final List<ScenarioAction> actions;

  ScenarioRollback({this.actions = const []});

  Map<String, dynamic> toJson() => {
    'actions': actions.map((a) => a.toJson()).toList(),
  };

  factory ScenarioRollback.fromJson(Map<String, dynamic> json) => ScenarioRollback(
    actions: (json['actions'] as List?)
        ?.map((e) => ScenarioAction.fromJson(e))
        .toList() ?? [],
  );
}

class ScenarioStep {
  final String actionId;
  final ScenarioAction action;
  final ScenarioCondition? condition;
  final ScenarioStepStatus status;
  final String? result;
  final String? error;

  ScenarioStep({
    required this.actionId,
    required this.action,
    this.condition,
    this.status = ScenarioStepStatus.pending,
    this.result,
    this.error,
  });

  ScenarioStep copyWith({
    ScenarioStepStatus? status,
    String? result,
    String? error,
  }) {
    return ScenarioStep(
      actionId: actionId,
      action: action,
      condition: condition,
      status: status ?? this.status,
      result: result ?? this.result,
      error: error,
    );
  }
}

enum ScenarioStepStatus { pending, running, completed, failed, skipped }

class AiScenario {
  final String id;
  final String name;
  final String description;
  final List<ScenarioAction> actions;
  final List<ScenarioCondition> conditions;
  final ScenarioRollback? rollback;

  AiScenario({
    required this.id,
    required this.name,
    this.description = '',
    this.actions = const [],
    this.conditions = const [],
    this.rollback,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'actions': actions.map((a) => a.toJson()).toList(),
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'rollback': rollback?.toJson(),
  };

  factory AiScenario.fromJson(Map<String, dynamic> json) => AiScenario(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    description: json['description'] ?? '',
    actions: (json['actions'] as List?)
        ?.map((e) => ScenarioAction.fromJson(e))
        .toList() ?? [],
    conditions: (json['conditions'] as List?)
        ?.map((e) => ScenarioCondition.fromJson(e))
        .toList() ?? [],
    rollback: json['rollback'] != null
        ? ScenarioRollback.fromJson(json['rollback'])
        : null,
  );
}

class AiScenarioExecutionState {
  final AiScenario? scenario;
  final List<ScenarioStep> steps;
  final bool isRunning;
  final int currentStepIndex;
  final String? error;
  final List<String> undoStack;

  AiScenarioExecutionState({
    this.scenario,
    this.steps = const [],
    this.isRunning = false,
    this.currentStepIndex = -1,
    this.error,
    this.undoStack = const [],
  });

  AiScenarioExecutionState copyWith({
    AiScenario? scenario,
    List<ScenarioStep>? steps,
    bool? isRunning,
    int? currentStepIndex,
    String? error,
    List<String>? undoStack,
  }) {
    return AiScenarioExecutionState(
      scenario: scenario ?? this.scenario,
      steps: steps ?? this.steps,
      isRunning: isRunning ?? this.isRunning,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      error: error,
      undoStack: undoStack ?? this.undoStack,
    );
  }

  double get progress {
    if (steps.isEmpty) return 0;
    final completed = steps.where((s) =>
        s.status == ScenarioStepStatus.completed ||
        s.status == ScenarioStepStatus.skipped).length;
    return completed / steps.length;
  }
}

class AiScenarioExecutor extends StateNotifier<AiScenarioExecutionState> {
  final Ref ref;
  late final String _workspacePath;
  final Map<String, String> _fileBackups = {};

  AiScenarioExecutor(this.ref) : super(AiScenarioExecutionState()) {
    _workspacePath = ref.read(workspaceProvider).currentPath ?? '';
  }

  String _resolvePath(String relativePath) {
    if (p.isAbsolute(relativePath)) return relativePath;
    return p.join(_workspacePath, relativePath);
  }

  void loadScenario(AiScenario scenario) {
    final steps = scenario.actions.asMap().entries.map((entry) {
      return ScenarioStep(
        actionId: 'step-${entry.key}',
        action: entry.value,
        condition: entry.key < scenario.conditions.length
            ? scenario.conditions[entry.key]
            : null,
      );
    }).toList();

    state = AiScenarioExecutionState(
      scenario: scenario,
      steps: steps,
    );
  }

  Future<void> executeScenario() async {
    if (state.scenario == null || state.isRunning) return;
    state = state.copyWith(isRunning: true, error: null, undoStack: []);

    try {
      for (int i = 0; i < state.steps.length; i++) {
        final step = state.steps[i];
        state = state.copyWith(currentStepIndex: i);

        if (step.condition != null) {
          final shouldRun = await _evaluateCondition(step.condition!);
          if (!shouldRun) {
            _updateStepStatus(i, ScenarioStepStatus.skipped, result: 'Condition not met');
            continue;
          }
        }

        _updateStepStatus(i, ScenarioStepStatus.running);

        try {
          final result = await _executeAction(step.action);
          _updateStepStatus(i, ScenarioStepStatus.completed, result: result);
        } catch (e) {
          _updateStepStatus(i, ScenarioStepStatus.failed, error: e.toString());
          state = state.copyWith(
            isRunning: false,
            error: 'Step ${i + 1} failed: $e',
          );
          await _rollback();
          return;
        }
      }
      state = state.copyWith(isRunning: false);
    } catch (e) {
      state = state.copyWith(isRunning: false, error: e.toString());
      await _rollback();
    }
  }

  void _updateStepStatus(int index, ScenarioStepStatus status, {String? result, String? error}) {
    final steps = List<ScenarioStep>.from(state.steps);
    steps[index] = steps[index].copyWith(status: status, result: result, error: error);
    state = state.copyWith(steps: steps);
  }

  Future<bool> _evaluateCondition(ScenarioCondition condition) async {
    switch (condition.type) {
      case 'file_exists':
        final path = _resolvePath(condition.params['path'] as String);
        return File(path).exists();
      case 'file_not_exists':
        final path = _resolvePath(condition.params['path'] as String);
        return !(await File(path).exists());
      case 'command_succeeds':
        final command = condition.params['command'] as String;
        final result = await Process.run('sh', ['-c', command],
            workingDirectory: _workspacePath);
        return result.exitCode == 0;
      case 'directory_exists':
        final path = _resolvePath(condition.params['path'] as String);
        return Directory(path).exists();
      default:
        return true;
    }
  }

  Future<String> _executeAction(ScenarioAction action) async {
    switch (action.type) {
      case 'create_file':
        return _createFile(action);
      case 'edit_file':
        return _editFile(action);
      case 'run_command':
        return _runCommand(action);
      case 'read_file':
        return _readFile(action);
      case 'search':
        return _search(action);
      case 'ask_user':
        return _askUser(action);
      default:
        throw Exception('Unknown action type: ${action.type}');
    }
  }

  Future<String> _createFile(ScenarioAction action) async {
    final path = _resolvePath(action.params['path'] as String);
    final content = action.params['content'] as String? ?? '';
    await File(path).create(recursive: true);
    await File(path).writeAsString(content);
    _fileBackups[path] = '';
    return 'Created $path';
  }

  Future<String> _editFile(ScenarioAction action) async {
    final path = _resolvePath(action.params['path'] as String);
    final file = File(path);
    final oldContent = await file.readAsString();
    _fileBackups[path] = oldContent;

    final find = action.params['find'] as String;
    final replace = action.params['replace'] as String;
    final newContent = oldContent.replaceAll(find, replace);
    await file.writeAsString(newContent);
    return 'Edited $path';
  }

  Future<String> _runCommand(ScenarioAction action) async {
    final command = action.params['command'] as String;
    final result = await Process.run(
      'sh',
      ['-c', command],
      workingDirectory: _workspacePath,
    );
    if (result.exitCode != 0) {
      throw Exception('Command failed: ${result.stderr}');
    }
    return result.stdout.toString();
  }

  Future<String> _readFile(ScenarioAction action) async {
    final path = _resolvePath(action.params['path'] as String);
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('File not found: $path');
    }
    return await file.readAsString();
  }

  Future<String> _search(ScenarioAction action) async {
    final pattern = action.params['pattern'] as String;
    final dir = action.params['directory'] != null
        ? _resolvePath(action.params['directory'] as String)
        : _workspacePath;

    final results = <String>[];
    await for (final entity in Directory(dir).list(recursive: true)) {
      if (entity is File && entity.path.contains(pattern)) {
        results.add(entity.path);
      }
    }
    return results.join('\n');
  }

  Future<String> _askUser(ScenarioAction action) async {
    final prompt = action.params['prompt'] as String? ?? 'Action requires user input';
    return 'User input requested: $prompt (auto-approved in scenario mode)';
  }

  Future<void> _rollback() async {
    if (state.scenario?.rollback != null) {
      for (final action in state.scenario!.rollback!.actions) {
        try {
          await _executeAction(action);
        } catch (_) {}
      }
    } else {
      for (final entry in _fileBackups.entries) {
        try {
          final file = File(entry.key);
          if (entry.value.isEmpty) {
            if (await file.exists()) await file.delete();
          } else {
            await file.writeAsString(entry.value);
          }
        } catch (_) {}
      }
    }
  }

  void reset() {
    _fileBackups.clear();
    state = AiScenarioExecutionState();
  }
}

final aiScenarioExecutorProvider =
    StateNotifierProvider<AiScenarioExecutor, AiScenarioExecutionState>((ref) {
  return AiScenarioExecutor(ref);
});
