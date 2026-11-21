// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

enum RoxumChatMode { ask, agent }

enum RoxumTimelineKind { reasoning, text, toolCall, fileEdit }

class RoxumTimelineItem {
  final String id;
  final RoxumTimelineKind kind;
  final String text;
  final int durationMs;
  final RoxumToolCallRecord? toolCall;
  final RoxumPendingEdit? fileEdit;

  const RoxumTimelineItem({
    required this.id,
    required this.kind,
    this.text = '',
    this.durationMs = 0,
    this.toolCall,
    this.fileEdit,
  });
}

class RoxumConversationTurn {
  final String id;
  final String userRequest;
  final String aiResponse;
  final String reasoningText;
  final int thinkingDurationMs;
  final List<RoxumToolCallRecord> toolCalls;
  final List<RoxumPendingEdit> fileEdits;
  final List<RoxumTimelineItem> timeline;
  final List<String> attachmentNames;
  final RoxumUsageStats usage;
  final bool isError;
  final DateTime timestamp;

  const RoxumConversationTurn({
    required this.id,
    required this.userRequest,
    this.aiResponse = '',
    this.reasoningText = '',
    this.thinkingDurationMs = 0,
    this.toolCalls = const [],
    this.fileEdits = const [],
    this.timeline = const [],
    this.attachmentNames = const [],
    this.usage = const RoxumUsageStats(),
    this.isError = false,
    required this.timestamp,
  });

  RoxumConversationTurn copyWith({
    String? userRequest,
    String? aiResponse,
    String? reasoningText,
    int? thinkingDurationMs,
    List<RoxumToolCallRecord>? toolCalls,
    List<RoxumPendingEdit>? fileEdits,
    List<RoxumTimelineItem>? timeline,
    List<String>? attachmentNames,
    RoxumUsageStats? usage,
    bool? isError,
  }) {
    return RoxumConversationTurn(
      id: id,
      userRequest: userRequest ?? this.userRequest,
      aiResponse: aiResponse ?? this.aiResponse,
      reasoningText: reasoningText ?? this.reasoningText,
      thinkingDurationMs: thinkingDurationMs ?? this.thinkingDurationMs,
      toolCalls: toolCalls ?? this.toolCalls,
      fileEdits: fileEdits ?? this.fileEdits,
      timeline: timeline ?? this.timeline,
      attachmentNames: attachmentNames ?? this.attachmentNames,
      usage: usage ?? this.usage,
      isError: isError ?? this.isError,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userRequest': userRequest,
        'aiResponse': aiResponse,
        'reasoningText': reasoningText,
        'thinkingDurationMs': thinkingDurationMs,
        'promptTokens': usage.promptTokens,
        'completionTokens': usage.completionTokens,
        'totalTokens': usage.totalTokens,
        'costUsd': usage.costUsd,
        'isError': isError,
        'timestamp': timestamp.toIso8601String(),
      };

  factory RoxumConversationTurn.fromJson(Map<String, dynamic> json) {
    final pTok = (json['promptTokens'] as num?)?.toInt() ?? 0;
    final cTok = (json['completionTokens'] as num?)?.toInt() ?? 0;
    final tTok = (json['totalTokens'] as num?)?.toInt() ?? (pTok + cTok);
    final cost = (json['costUsd'] as num?)?.toDouble() ?? 0.0;
    return RoxumConversationTurn(
      id: json['id']?.toString() ?? const Uuid().v4(),
      userRequest: json['userRequest']?.toString() ?? '',
      aiResponse: json['aiResponse']?.toString() ?? '',
      reasoningText: json['reasoningText']?.toString() ?? '',
      thinkingDurationMs: (json['thinkingDurationMs'] as num?)?.toInt() ?? 0,
      usage: RoxumUsageStats(
        promptTokens: pTok,
        completionTokens: cTok,
        totalTokens: tTok,
        costUsd: cost,
      ),
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
  final RoxumUsageStats sessionUsage;
  final OpenRouterKeyLimits? openRouterLimits;
  final List<RoxumModelOption> discoveredCustomModels;
  final bool isRefreshingModels;

  const RoxumChatState({
    required this.sessions,
    required this.currentSessionId,
    this.chatMode = RoxumChatMode.agent,
    this.selectedModelId,
    this.isGenerating = false,
    required this.toolSelections,
    this.pendingEdits = const {},
    this.sessionUsage = const RoxumUsageStats(),
    this.openRouterLimits,
    this.discoveredCustomModels = const [],
    this.isRefreshingModels = false,
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
    RoxumUsageStats? sessionUsage,
    OpenRouterKeyLimits? openRouterLimits,
    List<RoxumModelOption>? discoveredCustomModels,
    bool? isRefreshingModels,
  }) {
    return RoxumChatState(
      sessions: sessions ?? this.sessions,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      chatMode: chatMode ?? this.chatMode,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      isGenerating: isGenerating ?? this.isGenerating,
      toolSelections: toolSelections ?? this.toolSelections,
      pendingEdits: pendingEdits ?? this.pendingEdits,
      sessionUsage: sessionUsage ?? this.sessionUsage,
      openRouterLimits: openRouterLimits ?? this.openRouterLimits,
      discoveredCustomModels:
          discoveredCustomModels ?? this.discoveredCustomModels,
      isRefreshingModels: isRefreshingModels ?? this.isRefreshingModels,
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
    Future.microtask(refreshAllModels);
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

  List<RoxumModelOption> availableModels(SettingsState settings) {
    final base = RoxumModelOption.fromSettings(settings);
    if (state.discoveredCustomModels.isEmpty) return base;
    final seen = base.map((m) => m.id).toSet();
    return [
      ...base,
      ...state.discoveredCustomModels.where((m) => !seen.contains(m.id)),
    ];
  }

  Future<void> refreshAllModels() async {
    final settings = ref.read(settingsProvider);
    state = state.copyWith(isRefreshingModels: true);
    try {
      final discovered = await RoxumAiClient.fetchAllProviderModels(settings);
      final merged = availableModels(settings);
      final currentValid = state.selectedModelId != null &&
          (discovered.any((m) => m.id == state.selectedModelId) ||
              merged.any((m) => m.id == state.selectedModelId));
      state = state.copyWith(
        discoveredCustomModels: discovered,
        isRefreshingModels: false,
        selectedModelId: currentValid
            ? state.selectedModelId
            : (discovered.isNotEmpty
                ? discovered.first.id
                : (merged.isNotEmpty ? merged.first.id : null)),
      );
    } catch (e) {
      TalkerService.warning('[RoxumChat] Failed to fetch provider models: $e');
      state = state.copyWith(isRefreshingModels: false);
    }
  }

  Future<void> refreshCustomModels() => refreshAllModels();

  Future<void> refreshOpenRouterLimits() async {
    final key = ref.read(settingsProvider).openrouterApiKey.trim();
    if (key.isEmpty) return;
    try {
      final limits = await RoxumAiClient.fetchOpenRouterKeyLimits(key);
      state = state.copyWith(openRouterLimits: limits);
    } catch (e) {
      TalkerService.warning('[RoxumChat] Failed to fetch OpenRouter limits: $e');
    }
  }

  /// Removes pseudo tool-execution lines that weak models copy as plain text
  /// (e.g. `[Executed tools in this turn: ...]`) instead of making real calls.
  String _stripFakeToolMarkers(String text) {
    final cleaned = text.replaceAll(
      RegExp(r'^\s*\[Executed tools in this turn:[^\]]*\]\s*$', multiLine: true),
      '',
    );
    return cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _loadProjectContextBlocks(String workspace) {
    if (workspace.isEmpty) return '';
    final buf = StringBuffer();
    for (final rel in const ['.quantum/AGENTS.md', 'AGENTS.md', 'GEMINI.md']) {
      try {
        final f = File('$workspace/$rel');
        if (f.existsSync()) {
          final text = f.readAsStringSync().trim();
          if (text.isNotEmpty) {
            final clipped =
                text.length > 4000 ? '${text.substring(0, 4000)}\n...' : text;
            buf.writeln('\n[PROJECT RULES ($rel)]:\n$clipped');
            break;
          }
        }
      } catch (_) {}
    }
    try {
      final memFile = File('$workspace/.quantum_memory.json');
      if (memFile.existsSync()) {
        final memText = memFile.readAsStringSync().trim();
        if (memText.isNotEmpty && memText != '{}') {
          final clipped = memText.length > 3000
              ? '${memText.substring(0, 3000)}\n...'
              : memText;
          buf.writeln('\n[PERSISTENT PROJECT MEMORY (.quantum_memory.json)]:\n$clipped');
        }
      }
    } catch (_) {}
    return buf.toString();
  }

  Future<void> sendPrompt(
    String prompt, {
    int? truncateFromIndex,
    List<RoxumAttachment> attachments = const [],
  }) async {
    final trimmed = prompt.trim();
    if ((trimmed.isEmpty && attachments.isEmpty) || state.isGenerating) return;

    final settings = ref.read(settingsProvider);
    final models = availableModels(settings);
    if (models.isEmpty) {
      _appendErrorTurn(
        trimmed,
        'Нет настроенных провайдеров. Нажмите «Подключить API» в шапке чата, чтобы добавить ключ или локальный сервер (например http://IP:8080/v1).',
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

    final effectiveDisplay = trimmed.isNotEmpty
        ? trimmed
        : 'Вложения (${attachments.map((a) => a.name).join(', ')})';
    final turnId = const Uuid().v4();
    final newTurn = RoxumConversationTurn(
      id: turnId,
      userRequest: effectiveDisplay,
      attachmentNames: attachments.map((a) => a.name).toList(),
      timestamp: DateTime.now(),
    );

    final updatedTitle = baseTurns.isEmpty
        ? (effectiveDisplay.length > 42
            ? '${effectiveDisplay.substring(0, 42)}...'
            : effectiveDisplay)
        : state.currentSession.title;

    _updateCurrentSession(
      title: updatedTitle,
      turns: [...baseTurns, newTurn],
    );

    _cancelled = false;
    state = state.copyWith(isGenerating: true, selectedModelId: model.id);

    final workspace = ref.read(workspaceProvider).currentPath ?? '';
    final runtime = ref.read(runtimeServiceProvider);
    final guestWorkspace = runtime.toProotPath(workspace);
    final activeFilePath = ref.read(editorProvider).activeFilePath;

    final baseTools = state.chatMode == RoxumChatMode.agent
        ? RoxumAgenticTools.buildOpenAiTools(state.toolSelections)
        : const <Map<String, dynamic>>[];
    List<Map<String, dynamic>> rawMcp = const [];
    List<Map<String, dynamic>> mcpTools = const [];
    if (state.chatMode == RoxumChatMode.agent &&
        ref.read(mcpServiceProvider).any((s) => s.isEnabled)) {
      try {
        rawMcp = await ref
            .read(mcpServiceProvider.notifier)
            .getAvailableMcpTools()
            .timeout(const Duration(seconds: 12));
        mcpTools = RoxumAgenticTools.buildMcpOpenAiTools(rawMcp);
      } catch (_) {}
    }
    final toolsSchema = <Map<String, dynamic>>[...baseTools, ...mcpTools];

    final mcpSummary = mcpTools.isEmpty
        ? ''
        : '\nACTIVE MCP TOOLS (${mcpTools.length} available — use them proactively!):\n'
            '${mcpTools.map((t) => '- ${(t['function'] as Map)['name']}: ${(t['function'] as Map)['description']}').join('\n')}\n';
    final projectBlocks = _loadProjectContextBlocks(workspace);

    final systemPrompt = state.chatMode == RoxumChatMode.agent
        ? 'You are Roxum Agent inside QuantumIDE with FULL direct access to the user\'s workspace, the device/system filesystem (/root, /storage/emulated/0, SDK directories, host paths), shell (including ADB / Shizuku `rish` when available), and MCP servers via tool calls '
            '(readFile, codeOutline, writeFile, editFile, listFiles, grepInFiles, runCommand, checkEnvironment, installPackages, getLspDiagnostics, gitStatus, and all `mcp__*` tools). '
            'Workspace root: "$workspace"${guestWorkspace != workspace ? ' (in shell/terminal mapped to "$guestWorkspace")' : ''}. '
            '${activeFilePath != null ? 'Active editor file: "$activeFilePath". ' : ''}\n'
            'CRITICAL RULES FOR HIGH EFFICIENCY & ACCURACY:\n'
            '0) ACT, DO NOT DESCRIBE: perform the task with REAL tool calls (writeFile/editFile/runCommand...). NEVER write text like "[Executed tools...]", never claim an edit/build succeeded unless a real tool result confirmed it, and never finish with only a plan or description.\n'
            '1) TOKEN SAVING & CODEGRAPH MCP: For unfamiliar or large files/projects, call `mcp__quantum_codegraph__project_symbols` or `codeOutline` first, use `mcp__quantum_codegraph__read_symbol` to read a specific class/method body with brace balancing, `mcp__quantum_codegraph__find_symbol_usages` to find references across the project, or `readFile` with `startLine` and `endLine`.\n'
            '2) ENVIRONMENT & SDKS: NEVER assume `flutter`, `dart`, `node`, `python`, `java`, or `git` is missing and NEVER try to manually download huge SDK tarballs via curl unless `checkEnvironment` proves it is absent. Always call `checkEnvironment` first to see exact installed SDK paths and versions.\n'
            '3) INSTALLING PACKAGES: If a project or system dependency is missing, install it directly using `installPackages` (supports apt, npm, pip, pub, cargo) or `runCommand`.\n'
            '4) REAL VERIFICATION & SMART ANALYZER MCP: After creating or editing files, ALWAYS call `getLspDiagnostics` or `mcp__quantum_token_saver__smart_analyze_errors` to see all real compiler/analyzer errors and fix them before finishing.\n'
            '5) PROJECT MEMORY MCP: When you discover important architectural facts, SDK paths, or user preferences, save them using `mcp__quantum_memory__save_memory` so they persist across sessions.\n'
            '6) WEB & DOCS MCP: When you need external documentation, package versions, or web search, use `mcp__quantum_web_fetch__web_search_docs` and `mcp__quantum_web_fetch__fetch_url_markdown` (or `mcp__context7__*` if enabled).\n'
            '7) HONESTY: NEVER claim you ran a command, installed an SDK, or edited a file unless you actually invoked the corresponding tool call in this turn.\n'
            '$mcpSummary'
            '$projectBlocks\n'
            'Respond in the user\'s language.'
        : 'You are a helpful coding assistant inside QuantumIDE. '
            '${activeFilePath != null ? 'Active file: "$activeFilePath". ' : ''}'
            '$projectBlocks\n'
            'Respond concisely in the user\'s language.';

    final textBuffer = StringBuffer(trimmed);
    final imageParts = <Map<String, dynamic>>[];
    for (final att in attachments) {
      if (att.isImage) {
        imageParts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${att.mimeType};base64,${att.base64Data}',
          },
        });
      } else if (att.textContent != null && att.textContent!.isNotEmpty) {
        textBuffer.write(
          '\n\n<attached_file name="${att.name}">\n${att.textContent}\n</attached_file>',
        );
      } else {
        textBuffer.write(
          '\n\n[Прикреплён файл: ${att.name} (${att.sizeBytes} байт)]',
        );
      }
    }

    final dynamic currentUserContent = imageParts.isEmpty
        ? textBuffer.toString()
        : [
            {'type': 'text', 'text': textBuffer.toString()},
            ...imageParts,
          ];

    final history = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      for (final t in baseTurns) ...[
        {'role': 'user', 'content': t.userRequest},
        if (t.aiResponse.isNotEmpty)
          {
            'role': 'assistant',
            'content': _stripFakeToolMarkers(t.aiResponse),
          },
      ],
      {'role': 'user', 'content': currentUserContent},
    ];

    final startedAt = DateTime.now();
    var stepStartedAt = startedAt;
    var currentStep = 0;
    final turnEditedPaths = <String>{};
    final stepEditIds = <String, String>{};
    final pendingCopy = Map<String, RoxumPendingEdit>.from(state.pendingEdits);

    List<RoxumTimelineItem> upsertTimeline(
      List<RoxumTimelineItem> current,
      RoxumTimelineItem item,
    ) {
      final list = List<RoxumTimelineItem>.from(current);
      final idx = list.indexWhere((e) => e.id == item.id);
      if (idx >= 0) {
        list[idx] = item;
      } else {
        list.add(item);
      }
      return list;
    }

    final toolsRunner = state.chatMode == RoxumChatMode.agent
        ? RoxumAgenticTools(
            ref,
            pendingEdits: pendingCopy,
            onPendingEditsChanged: (updated) {
              state = state.copyWith(pendingEdits: updated);
              for (final k in updated.keys) {
                if (pendingCopy[k]?.updatedContent != updated[k]?.updatedContent ||
                    !turnEditedPaths.contains(k)) {
                  turnEditedPaths.add(k);
                  stepEditIds['$currentStep::$k'] ??= 'edit_${currentStep}_$k';
                }
              }
              final editsForTurn = turnEditedPaths
                  .map((p) => updated[p])
                  .whereType<RoxumPendingEdit>()
                  .toList();
              _updateTurn(turnId, (t) {
                var tl = t.timeline;
                for (final entry in stepEditIds.entries) {
                  final parts = entry.key.split('::');
                  if (parts.length == 2 &&
                      parts[0] == '$currentStep' &&
                      updated[parts[1]] != null) {
                    tl = upsertTimeline(
                      tl,
                      RoxumTimelineItem(
                        id: entry.value,
                        kind: RoxumTimelineKind.fileEdit,
                        fileEdit: updated[parts[1]],
                      ),
                    );
                  }
                }
                return t.copyWith(fileEdits: editsForTurn, timeline: tl);
              });
            },
          )
        : null;

    try {
      final finalAnswer = await _client.runAgentLoop(
        model: model,
        historyMessages: history,
        tools: toolsSchema,
        agenticTools: toolsRunner,
        isCancelled: () => _cancelled,
        onStepStart: (step) {
          currentStep = step;
          stepStartedAt = DateTime.now();
        },
        onToolEvent: (record) {
          _updateTurn(turnId, (turn) {
            final list = List<RoxumToolCallRecord>.from(turn.toolCalls);
            final idx = list.indexWhere((c) => c.id == record.id);
            if (idx >= 0) {
              list[idx] = record;
            } else {
              list.add(record);
            }
            final tl = upsertTimeline(
              turn.timeline,
              RoxumTimelineItem(
                id: 'tool_${record.id}',
                kind: RoxumTimelineKind.toolCall,
                toolCall: record,
              ),
            );
            return turn.copyWith(toolCalls: list, timeline: tl);
          });
        },
        onAssistantText: (text) {
          _updateTurn(turnId, (turn) {
            final tl = text.trim().isEmpty
                ? turn.timeline
                : upsertTimeline(
                    turn.timeline,
                    RoxumTimelineItem(
                      id: 'step_${currentStep}_text',
                      kind: RoxumTimelineKind.text,
                      text: text,
                    ),
                  );
            return turn.copyWith(aiResponse: text, timeline: tl);
          });
        },
        onReasoningText: (reasoning) {
          final now = DateTime.now();
          final totalElapsed = now.difference(startedAt).inMilliseconds;
          final stepElapsed = now.difference(stepStartedAt).inMilliseconds;
          _updateTurn(
            turnId,
            (turn) {
              final tl = reasoning.trim().isEmpty
                  ? turn.timeline
                  : upsertTimeline(
                      turn.timeline,
                      RoxumTimelineItem(
                        id: 'step_${currentStep}_reasoning',
                        kind: RoxumTimelineKind.reasoning,
                        text: reasoning,
                        durationMs: stepElapsed,
                      ),
                    );
              return turn.copyWith(
                reasoningText: reasoning,
                thinkingDurationMs: totalElapsed,
                timeline: tl,
              );
            },
          );
        },
        onUsage: (usage) {
          state = state.copyWith(sessionUsage: state.sessionUsage + usage);
          _updateTurn(
            turnId,
            (turn) => turn.copyWith(usage: turn.usage + usage),
          );
        },
      );

      if (model.provider == 'OpenRouter') {
        refreshOpenRouterLimits();
      }

      if (!_cancelled) {
        final cleanedAnswer = _stripFakeToolMarkers(finalAnswer);
        final effectiveAnswer = cleanedAnswer.trim().isNotEmpty
            ? cleanedAnswer
            : 'Модель вернула пустой ответ. Попробуйте повторить запрос или сменить модель.';
        _updateTurn(
          turnId,
          (turn) => turn.copyWith(
            aiResponse: effectiveAnswer,
            timeline: upsertTimeline(
              turn.timeline,
              RoxumTimelineItem(
                id: 'step_${currentStep}_text',
                kind: RoxumTimelineKind.text,
                text: effectiveAnswer,
              ),
            ),
          ),
        );
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
