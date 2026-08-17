import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';

enum ActionType { createFile, editFile, runCommand, searchCode, readFile, semanticSearch }

class AgentAction {
  final String id;
  final ActionType type;
  final Map<String, dynamic> params;
  final bool requiresConfirmation;

  AgentAction({
    required this.id,
    required this.type,
    required this.params,
    this.requiresConfirmation = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'params': params,
    'requiresConfirmation': requiresConfirmation,
  };

  factory AgentAction.fromJson(Map<String, dynamic> json) => AgentAction(
    id: json['id'],
    type: ActionType.values.firstWhere((e) => e.name == json['type']),
    params: json['params'],
    requiresConfirmation: json['requiresConfirmation'] ?? false,
  );

  static AgentAction fromAiResponse(Map<String, dynamic> actionJson) {
    final typeStr = actionJson['action'] as String;
    final params = actionJson['params'] as Map<String, dynamic>;

    ActionType type;
    bool needsConfirm;
    switch (typeStr) {
      case 'create_file':
        type = ActionType.createFile;
        needsConfirm = true;
        break;
      case 'edit_file':
        type = ActionType.editFile;
        needsConfirm = true;
        break;
      case 'run_command':
        type = ActionType.runCommand;
        needsConfirm = true;
        break;
      case 'search_code':
        type = ActionType.searchCode;
        needsConfirm = false;
        break;
      case 'read_file':
        type = ActionType.readFile;
        needsConfirm = false;
        break;
      case 'semantic_search':
        type = ActionType.semanticSearch;
        needsConfirm = false;
        break;
      default:
        throw ArgumentError('Unknown action type: $typeStr');
    }

    return AgentAction(
      id: '${typeStr}_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      params: params,
      requiresConfirmation: needsConfirm,
    );
  }
}

class AgentExecutionRecord {
  final AgentAction action;
  final DateTime timestamp;
  final bool success;
  final String output;
  final String? error;

  AgentExecutionRecord({
    required this.action,
    required this.timestamp,
    required this.success,
    required this.output,
    this.error,
  });
}

class AiAgentOrchestrator extends ChangeNotifier {
  final RuntimeService _runtime;
  final Ref _ref;

  final List<AgentExecutionRecord> _history = [];
  final List<AgentAction> _pendingActions = [];
  bool _isProcessing = false;
  bool _awaitingConfirmation = false;

  AiAgentOrchestrator(this._runtime, this._ref);

  List<AgentExecutionRecord> get history => List.unmodifiable(_history);
  List<AgentAction> get pendingActions => List.unmodifiable(_pendingActions);
  bool get isProcessing => _isProcessing;
  bool get awaitingConfirmation => _awaitingConfirmation;

  String get _workspacePath => _ref.read(workspaceProvider).currentPath ?? '';

  List<AgentAction> parseActionsFromResponse(String aiResponse) {
    try {
      final decoded = jsonDecode(aiResponse);
      if (decoded is List) {
        return decoded
            .map((item) => AgentAction.fromAiResponse(item as Map<String, dynamic>))
            .toList();
      }
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('actions')) {
          return (decoded['actions'] as List)
              .map((item) => AgentAction.fromAiResponse(item as Map<String, dynamic>))
              .toList();
        }
        return [AgentAction.fromAiResponse(decoded)];
      }
    } catch (e) {
      debugPrint('AiAgentOrchestrator: parseActionsFromResponse failed: $e');
    }
    return [];
  }

  Future<void> executeActions(List<AgentAction> actions) async {
    if (_isProcessing) return;

    _isProcessing = true;
    notifyListeners();

    final needsConfirm = actions.where((a) => a.requiresConfirmation).toList();
    if (needsConfirm.isNotEmpty) {
      _pendingActions.clear();
      _pendingActions.addAll(actions);
      _awaitingConfirmation = true;
      _isProcessing = false;
      notifyListeners();
      return;
    }

    for (final action in actions) {
      await _executeSingleAction(action);
    }

    _isProcessing = false;
    notifyListeners();
  }

  void confirmPendingActions() {
    _awaitingConfirmation = false;
    _isProcessing = true;
    notifyListeners();

    _executePendingActions();
  }

  void rejectPendingActions() {
    _pendingActions.clear();
    _awaitingConfirmation = false;
    notifyListeners();
  }

  Future<void> _executePendingActions() async {
    final actions = List<AgentAction>.from(_pendingActions);
    _pendingActions.clear();

    for (final action in actions) {
      await _executeSingleAction(action);
    }

    _isProcessing = false;
    notifyListeners();
  }

  Future<void> _executeSingleAction(AgentAction action) async {
    String output = '';
    bool success = true;
    String? error;

    try {
      switch (action.type) {
        case ActionType.createFile:
          output = await _createFile(action);
          break;
        case ActionType.editFile:
          output = await _editFile(action);
          break;
        case ActionType.runCommand:
          output = await _runCommand(action);
          break;
        case ActionType.searchCode:
          output = await _searchCode(action);
          break;
        case ActionType.readFile:
          output = await _readFile(action);
          break;
        case ActionType.semanticSearch:
          output = await _semanticSearch(action);
          break;
      }
    } catch (e) {
      success = false;
      error = e.toString();
      output = 'Error: $e';
    }

    _history.add(AgentExecutionRecord(
      action: action,
      timestamp: DateTime.now(),
      success: success,
      output: output,
      error: error,
    ));

    if (_history.length > 200) {
      _history.removeRange(0, _history.length - 200);
    }
    notifyListeners();
  }

  Future<String> _createFile(AgentAction action) async {
    final path = action.params['path'] as String;
    final content = action.params['content'] as String? ?? '';
    final fullPath = p.isAbsolute(path) ? path : p.join(_workspacePath, path);

    final file = File(fullPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return 'Created $fullPath';
  }

  Future<String> _editFile(AgentAction action) async {
    final path = action.params['path'] as String;
    final oldText = action.params['oldText'] as String;
    final newText = action.params['newText'] as String;
    final fullPath = p.isAbsolute(path) ? path : p.join(_workspacePath, path);

    final file = File(fullPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', fullPath);
    }

    var content = await file.readAsString();
    if (!content.contains(oldText)) {
      throw Exception('oldText not found in file');
    }

    content = content.replaceFirst(oldText, newText);
    await file.writeAsString(content);
    return 'Edited $fullPath';
  }

  Future<String> _runCommand(AgentAction action) async {
    final command = action.params['command'] as String;
    final workingDir = action.params['workingDirectory'] as String?;
    return _runtime.runCommand(command, workingDirectory: workingDir);
  }

  Future<String> _searchCode(AgentAction action) async {
    final query = action.params['query'] as String;
    final directory = action.params['directory'] as String? ?? _workspacePath;

    final result = await _runtime.runCommand(
      'grep -rn "$query" "$directory" --include="*.dart" --include="*.js" --include="*.ts" 2>/dev/null | head -50',
    );
    return result.trim().isEmpty ? 'No matches found' : result;
  }

  Future<String> _semanticSearch(AgentAction action) async {
    final query = action.params['query'] as String;
    final symbolIndexer = _ref.read(symbolIndexerProvider.notifier);
    final results = await symbolIndexer.semanticSearch(query, limit: 20);

    if (results.isEmpty) {
      return 'No semantic matches found for "$query"';
    }

    final buffer = StringBuffer();
    buffer.writeln('Semantic search results for: $query');
    buffer.writeln('');

    for (final result in results) {
      final relPath = p.isAbsolute(result.path)
          ? p.relative(result.path, from: _workspacePath)
          : result.path;
      buffer.writeln('[${result.type.toUpperCase()}] ${result.title}');
      buffer.writeln('  Path: $relPath:${result.lineNumber}');
      buffer.writeln('  ${result.subtitle}');
      buffer.writeln('');
    }

    return buffer.toString().trim();
  }

  Future<String> _readFile(AgentAction action) async {
    final path = action.params['path'] as String;
    final fullPath = p.isAbsolute(path) ? path : p.join(_workspacePath, path);

    final file = File(fullPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', fullPath);
    }

    return await file.readAsString();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}

final aiAgentOrchestratorProvider = ChangeNotifierProvider<AiAgentOrchestrator>((ref) {
  final runtime = ref.watch(runtimeServiceProvider);
  final orchestrator = AiAgentOrchestrator(runtime, ref);
  ref.onDispose(() => orchestrator.dispose());
  return orchestrator;
});
