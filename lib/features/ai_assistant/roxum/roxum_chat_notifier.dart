// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

enum RoxumChatMode { ask, agent }

class RoxumConversationTurn {
  final String id;
  final String userRequest;
  final String aiResponse;
  final List<RoxumToolCallRecord> toolCalls;
  final bool isError;
  final DateTime timestamp;

  const RoxumConversationTurn({
    required this.id,
    required this.userRequest,
    this.aiResponse = '',
    this.toolCalls = const [],
    this.isError = false,
    required this.timestamp,
  });

  RoxumConversationTurn copyWith({
    String? userRequest,
    String? aiResponse,
    List<RoxumToolCallRecord>? toolCalls,
    bool? isError,
  }) {
    return RoxumConversationTurn(
      id: id,
      userRequest: userRequest ?? this.userRequest,
      aiResponse: aiResponse ?? this.aiResponse,
      toolCalls: toolCalls ?? this.toolCalls,
      isError: isError ?? this.isError,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userRequest': userRequest,
        'aiResponse': aiResponse,
        'isError': isError,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RoxumConversationTurn.fromJson(Map<String, dynamic> json) {
    return RoxumConversationTurn(
      id: json['id']?.toString() ?? const Uuid().v4(),
      userRequest: json['userRequest']?.toString() ?? '',
      aiResponse: json['aiResponse']?.toString() ?? '',
      isError: json['isError'] == true,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class RoxumChatSession {
  final String id;
  final String title;
  final List<RoxumConversationTurn> turns;
  final DateTime updatedAt;

  const RoxumChatSession({
    required this.id,
    required this.title,
    required this.turns,
    required this.updatedAt,
  });

  RoxumChatSession copyWith({
    String? title,
    List<RoxumConversationTurn>? turns,
    DateTime? updatedAt,
  }) {
    return RoxumChatSession(
      id: id,
      title: title ?? this.title,
      turns: turns ?? this.turns,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'turns': turns.map((t) => t.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RoxumChatSession.fromJson(Map<String, dynamic> json) {
    final rawTurns = (json['turns'] as List?) ?? const [];
    return RoxumChatSession(
      id: json['id']?.toString() ?? const Uuid().v4(),
      title: json['title']?.toString() ?? 'Новый чат',
      turns: rawTurns
          .whereType<Map>()
          .map((e) => RoxumConversationTurn.fromJson(e.cast<String, dynamic>()))
          .toList(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class RoxumChatState {
  final List<RoxumChatSession> sessions;
  final String currentSessionId;
  final RoxumChatMode chatMode;
  final String? selectedModelId;
  final bool isGenerating;
  final Map<String, bool> toolSelections;
  final Map<String, RoxumPendingEdit> pendingEdits;

  const RoxumChatState({
    required this.sessions,
    required this.currentSessionId,
    this.chatMode = RoxumChatMode.agent,
    this.selectedModelId,
    this.isGenerating = false,
    required this.toolSelections,
    this.pendingEdits = const {},
  });

  RoxumChatSession get currentSession {
    return sessions.firstWhere(
      (s) => s.id == currentSessionId,
      orElse: () => sessions.first,
    );
  }

  RoxumChatState copyWith({
    List<RoxumChatSession>? sessions,
    String? currentSessionId,
    RoxumChatMode? chatMode,
    String? selectedModelId,
    bool? isGenerating,
    Map<String, bool>? toolSelections,
    Map<String, RoxumPendingEdit>? pendingEdits,
  }) {
    return RoxumChatState(
      sessions: sessions ?? this.sessions,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      chatMode: chatMode ?? this.chatMode,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      isGenerating: isGenerating ?? this.isGenerating,
      toolSelections: toolSelections ?? this.toolSelections,
      pendingEdits: pendingEdits ?? this.pendingEdits,
    );
  }
}

final roxumChatProvider =
    NotifierProvider<RoxumChatNotifier, RoxumChatState>(RoxumChatNotifier.new);

class RoxumChatNotifier extends Notifier<RoxumChatState> {
  static const _prefsKey = 'roxum_chat_sessions_v1';
  final RoxumAiClient _client = RoxumAiClient();
  bool _cancelled = false;

  @override
  RoxumChatState build() {
    ref.onDispose(_client.cancel);
    final initialId = const Uuid().v4();
    final initialSession = RoxumChatSession(
      id: initialId,
      title: 'Новый чат',
      turns: const [],
      updatedAt: DateTime.now(),
    );
    _restoreSessions();
    return RoxumChatState(
      sessions: [initialSession],
      currentSessionId: initialId,
      toolSelections: normalizeAgenticToolSelections(null),
    );
  }

  Future<void> _restoreSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      final parsed = list
          .whereType<Map>()
          .map((e) => RoxumChatSession.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (parsed.isNotEmpty) {
        state = state.copyWith(
          sessions: parsed,
          currentSessionId: parsed.first.id,
        );
      }
    } catch (e) {
      TalkerService.warning('[RoxumChat] Failed to restore sessions: $e');
    }
  }

  Future<void> _persistSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        state.sessions.take(25).map((s) => s.toJson()).toList(),
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
  }

  void setChatMode(RoxumChatMode mode) {
    state = state.copyWith(chatMode: mode);
  }

  void selectModel(String modelId) {
    state = state.copyWith(selectedModelId: modelId);
  }

  void toggleTool(String toolName, bool enabled) {
    final next = Map<String, bool>.from(state.toolSelections);
    next[toolName] = enabled;
    state = state.copyWith(toolSelections: next);
  }

  void createNewSession() {
    if (state.isGenerating) return;
    final id = const Uuid().v4();
    final session = RoxumChatSession(
      id: id,
      title: 'Новый чат',
      turns: const [],
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      sessions: [session, ...state.sessions],
      currentSessionId: id,
    );
    _persistSessions();
  }

  void switchSession(String id) {
    if (state.isGenerating) return;
    state = state.copyWith(currentSessionId: id);
  }

  void deleteSession(String id) {
    if (state.isGenerating) return;
    final remaining = state.sessions.where((s) => s.id != id).toList();
    if (remaining.isEmpty) {
      createNewSession();
      return;
    }
    final nextId = state.currentSessionId == id
        ? remaining.first.id
        : state.currentSessionId;
    state = state.copyWith(sessions: remaining, currentSessionId: nextId);
    _persistSessions();
  }

  void stopGeneration() {
    _cancelled = true;
    _client.cancel();
    state = state.copyWith(isGenerating: false);
  }

  Future<void> keepEdit(String filePath) async {
    final next = Map<String, RoxumPendingEdit>.from(state.pendingEdits);
    next.remove(filePath);
    state = state.copyWith(pendingEdits: next);
  }

  Future<void> undoEdit(String filePath) async {
    final edit = state.pendingEdits[filePath];
    if (edit == null) return;
    try {
      final file = File(filePath);
      if (edit.existedBefore) {
        await file.writeAsString(edit.originalContent);
      } else if (await file.exists()) {
        await file.delete();
      }
      await ref.read(editorProvider.notifier).reloadFileFromDisk(filePath);
    } catch (e) {
      TalkerService.error('[RoxumChat] Failed to undo edit for $filePath: $e');
    }
    final next = Map<String, RoxumPendingEdit>.from(state.pendingEdits);
    next.remove(filePath);
    state = state.copyWith(pendingEdits: next);
  }

  Future<void> keepAllEdits() async {
    state = state.copyWith(pendingEdits: {});
  }

  Future<void> undoAllEdits() async {
    final paths = state.pendingEdits.keys.toList();
    for (final path in paths) {
      await undoEdit(path);
    }
  }

  Future<void> sendPrompt(
    String prompt, {
    int? truncateFromIndex,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    final settings = ref.read(settingsProvider);
    final models = RoxumModelOption.fromSettings(settings);
    if (models.isEmpty) {
      _appendErrorTurn(
        trimmed,
        'Нет настроенных API-ключей. Откройте Настройки -> AI и добавьте ключ (Gemini, DeepSeek, OpenAI, Anthropic, OpenRouter или Custom/Ollama).',
      );
      return;
    }

    final model = models.firstWhere(
      (m) => m.id == state.selectedModelId,
      orElse: () => models.first,
    );

    final baseTurns = truncateFromIndex != null
        ? state.currentSession.turns.take(truncateFromIndex).toList()
        : List<RoxumConversationTurn>.from(state.currentSession.turns);

    final turnId = const Uuid().v4();
    final newTurn = RoxumConversationTurn(
      id: turnId,
      userRequest: trimmed,
      timestamp: DateTime.now(),
    );

    final updatedTitle = baseTurns.isEmpty
        ? (trimmed.length > 42 ? '${trimmed.substring(0, 42)}...' : trimmed)
        : state.currentSession.title;

    _updateCurrentSession(
      title: updatedTitle,
      turns: [...baseTurns, newTurn],
    );

    _cancelled = false;
    state = state.copyWith(isGenerating: true, selectedModelId: model.id);

    final workspace = ref.read(workspaceProvider).currentPath ?? '';
    final activeFilePath = ref.read(editorProvider).activeFilePath;
    final systemPrompt = state.chatMode == RoxumChatMode.agent
        ? 'You are Roxum Agent inside QuantumIDE. Workspace: "$workspace". '
            '${activeFilePath != null ? 'Active editor file: "$activeFilePath". ' : ''}'
            'Use tools to inspect files, check diagnostics, edit code cleanly, and run commands when needed. '
            'Respond concisely in the user\'s language.'
        : 'You are a helpful coding assistant inside QuantumIDE. '
            '${activeFilePath != null ? 'Active file: "$activeFilePath". ' : ''}'
            'Respond concisely in the user\'s language.';

    final history = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      for (final t in baseTurns) ...[
        {'role': 'user', 'content': t.userRequest},
        if (t.aiResponse.isNotEmpty)
          {'role': 'assistant', 'content': t.aiResponse},
      ],
      {'role': 'user', 'content': trimmed},
    ];

    final pendingCopy = Map<String, RoxumPendingEdit>.from(state.pendingEdits);
    final toolsRunner = state.chatMode == RoxumChatMode.agent
        ? RoxumAgenticTools(
            ref,
            pendingEdits: pendingCopy,
            onPendingEditsChanged: (updated) {
              state = state.copyWith(pendingEdits: updated);
            },
          )
        : null;

    final toolsSchema = state.chatMode == RoxumChatMode.agent
        ? RoxumAgenticTools.buildOpenAiTools(state.toolSelections)
        : const <Map<String, dynamic>>[];

    try {
      final finalAnswer = await _client.runAgentLoop(
        model: model,
        historyMessages: history,
        tools: toolsSchema,
        agenticTools: toolsRunner,
        isCancelled: () => _cancelled,
        onToolEvent: (record) {
          _updateTurn(turnId, (turn) {
            final list = List<RoxumToolCallRecord>.from(turn.toolCalls);
            final idx = list.indexWhere((c) => c.id == record.id);
            if (idx >= 0) {
              list[idx] = record;
            } else {
              list.add(record);
            }
            return turn.copyWith(toolCalls: list);
          });
        },
        onAssistantText: (text) {
          _updateTurn(turnId, (turn) => turn.copyWith(aiResponse: text));
        },
      );

      if (!_cancelled && finalAnswer.isNotEmpty) {
        _updateTurn(turnId, (turn) => turn.copyWith(aiResponse: finalAnswer));
      }
    } catch (e) {
      if (!_cancelled) {
        _updateTurn(
          turnId,
          (turn) => turn.copyWith(
            aiResponse: 'Ошибка запроса: $e',
            isError: true,
          ),
        );
      }
    } finally {
      state = state.copyWith(isGenerating: false);
      _persistSessions();
    }
  }

  void _appendErrorTurn(String request, String errorText) {
    final turn = RoxumConversationTurn(
      id: const Uuid().v4(),
      userRequest: request,
      aiResponse: errorText,
      isError: true,
      timestamp: DateTime.now(),
    );
    _updateCurrentSession(turns: [...state.currentSession.turns, turn]);
  }

  void _updateTurn(
    String turnId,
    RoxumConversationTurn Function(RoxumConversationTurn) transform,
  ) {
    final current = state.currentSession;
    final nextTurns = current.turns
        .map((t) => t.id == turnId ? transform(t) : t)
        .toList();
    _updateCurrentSession(turns: nextTurns);
  }

  void _updateCurrentSession({
    String? title,
    List<RoxumConversationTurn>? turns,
  }) {
    final nextSessions = state.sessions.map((s) {
      if (s.id != state.currentSessionId) return s;
      return s.copyWith(
        title: title ?? s.title,
        turns: turns ?? s.turns,
        updatedAt: DateTime.now(),
      );
    }).toList();
    state = state.copyWith(sessions: nextSessions);
  }
}
