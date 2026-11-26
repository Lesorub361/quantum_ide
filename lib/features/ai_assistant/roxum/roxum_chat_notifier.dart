// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:quantum_ide/core/models/chat_models.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/agent/data/agent_engine.dart';
import 'package:quantum_ide/features/agent/data/built_in_tools.dart';
import 'package:quantum_ide/features/agent/domain/agent_event.dart';
import 'package:quantum_ide/features/agent/domain/agent_tool.dart' as ps;
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_skill_loader.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/mcp/application/mcp_controller.dart';
import 'package:quantum_ide/features/providers/data/anthropic_provider.dart';
import 'package:quantum_ide/features/providers/data/gemini_provider.dart';
import 'package:quantum_ide/features/providers/data/openai_compatible_provider.dart';
import 'package:quantum_ide/features/providers/domain/ai_provider.dart';
import 'package:quantum_ide/features/providers/domain/provider_types.dart';
import 'package:quantum_ide/shared/widgets/confirm_action_sheet.dart'
    show ConfirmResult;

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

  static Map<String, dynamic> _toolCallToJson(RoxumToolCallRecord tc) => {
    'id': tc.id,
    'name': tc.name,
    'arguments': tc.arguments,
    'isRunning': false,
    'success': tc.success,
    'output': tc.output.length > 4000
        ? '${tc.output.substring(0, 4000)}\n... [truncated]'
        : tc.output,
  };

  static RoxumToolCallRecord _toolCallFromJson(Map<String, dynamic> j) =>
      RoxumToolCallRecord(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        arguments: (j['arguments'] is Map)
            ? Map<String, dynamic>.from(j['arguments'] as Map)
            : const {},
        isRunning: false,
        success: j['success'] != false,
        output: j['output']?.toString() ?? '',
      );

  static Map<String, dynamic> _pendingEditToJson(RoxumPendingEdit fe) => {
    'filePath': fe.filePath,
    'existedBefore': fe.existedBefore,
    'addedLines': fe.addedLines,
    'removedLines': fe.removedLines,
  };

  static RoxumPendingEdit _pendingEditFromJson(Map<String, dynamic> j) =>
      RoxumPendingEdit(
        filePath: j['filePath']?.toString() ?? '',
        originalContent: '',
        updatedContent: '',
        existedBefore: j['existedBefore'] != false,
        addedLines: (j['addedLines'] as num?)?.toInt() ?? 0,
        removedLines: (j['removedLines'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'text': text,
    'durationMs': durationMs,
    if (toolCall != null) 'toolCall': _toolCallToJson(toolCall!),
    if (fileEdit != null) 'fileEdit': _pendingEditToJson(fileEdit!),
  };

  factory RoxumTimelineItem.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind']?.toString() ?? 'text';
    final kind = RoxumTimelineKind.values.firstWhere(
      (k) => k.name == kindStr,
      orElse: () => RoxumTimelineKind.text,
    );
    return RoxumTimelineItem(
      id: json['id']?.toString() ?? const Uuid().v4(),
      kind: kind,
      text: json['text']?.toString() ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      toolCall: json['toolCall'] is Map
          ? _toolCallFromJson(
              Map<String, dynamic>.from(json['toolCall'] as Map),
            )
          : null,
      fileEdit: json['fileEdit'] is Map
          ? _pendingEditFromJson(
              Map<String, dynamic>.from(json['fileEdit'] as Map),
            )
          : null,
    );
  }
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
    'toolCalls': toolCalls.map(RoxumTimelineItem._toolCallToJson).toList(),
    'fileEdits': fileEdits.map(RoxumTimelineItem._pendingEditToJson).toList(),
    'timeline': timeline.map((e) => e.toJson()).toList(),
    'attachmentNames': attachmentNames,
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
    final rawTools = (json['toolCalls'] as List?) ?? const [];
    final rawEdits = (json['fileEdits'] as List?) ?? const [];
    final rawTimeline = (json['timeline'] as List?) ?? const [];
    final rawAtts = (json['attachmentNames'] as List?) ?? const [];
    return RoxumConversationTurn(
      id: json['id']?.toString() ?? const Uuid().v4(),
      userRequest: json['userRequest']?.toString() ?? '',
      aiResponse: json['aiResponse']?.toString() ?? '',
      reasoningText: json['reasoningText']?.toString() ?? '',
      thinkingDurationMs: (json['thinkingDurationMs'] as num?)?.toInt() ?? 0,
      toolCalls: rawTools
          .whereType<Map>()
          .map(
            (e) => RoxumTimelineItem._toolCallFromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
      fileEdits: rawEdits
          .whereType<Map>()
          .map(
            (e) => RoxumTimelineItem._pendingEditFromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
      timeline: rawTimeline
          .whereType<Map>()
          .map((e) => RoxumTimelineItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      attachmentNames: rawAtts.map((e) => e.toString()).toList(),
      usage: RoxumUsageStats(
        promptTokens: pTok,
        completionTokens: cTok,
        totalTokens: tTok,
        costUsd: cost,
      ),
      isError: json['isError'] == true,
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
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
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
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

final roxumChatProvider = NotifierProvider<RoxumChatNotifier, RoxumChatState>(
  RoxumChatNotifier.new,
);

class RoxumChatNotifier extends Notifier<RoxumChatState> {
  final RoxumAiClient _client = RoxumAiClient();
  CancelToken? _activeCancelToken;
  bool _cancelled = false;
  int _activeRunToken = 0;
  String _activePrefsKey = 'roxum_chat_sessions_v2_global';

  static String _prefsKeyForWorkspace(String? workspacePath) {
    final normalized = (workspacePath ?? '').trim();
    if (normalized.isEmpty) return 'roxum_chat_sessions_v2_global';
    final encoded = base64Url.encode(utf8.encode(normalized));
    return 'roxum_chat_sessions_v2_$encoded';
  }

  @override
  RoxumChatState build() {
    ref.onDispose(() {
      _activeCancelToken?.cancel('disposed');
      _client.cancel();
    });
    final workspacePath = ref.watch(
      workspaceProvider.select((w) => w.currentPath),
    );
    final prefsKey = _prefsKeyForWorkspace(workspacePath);
    _activePrefsKey = prefsKey;
    final initialId = const Uuid().v4();
    final initialSession = RoxumChatSession(
      id: initialId,
      title: 'Новый чат',
      turns: const [],
      updatedAt: DateTime.now(),
    );
    _restoreSessions(prefsKey);
    Future.microtask(refreshAllModels);
    return RoxumChatState(
      sessions: [initialSession],
      currentSessionId: initialId,
      toolSelections: normalizeAgenticToolSelections(null),
    );
  }

  Future<void> _restoreSessions(String prefsKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_activePrefsKey != prefsKey) return;
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      final parsed = list
          .whereType<Map>()
          .map((e) => RoxumChatSession.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (_activePrefsKey != prefsKey) return;
      final isStillUntouchedInitial =
          state.sessions.length == 1 && state.sessions.first.turns.isEmpty;
      if (parsed.isNotEmpty && isStillUntouchedInitial) {
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
      final key = _activePrefsKey;
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        state.sessions.take(25).map((s) => s.toJson()).toList(),
      );
      await prefs.setString(key, encoded);
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
    _activeCancelToken?.cancel('stopped_by_user');
    _activeCancelToken = null;
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
      final currentValid =
          state.selectedModelId != null &&
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
      TalkerService.warning(
        '[RoxumChat] Failed to fetch OpenRouter limits: $e',
      );
    }
  }

  /// Removes pseudo tool-execution lines that weak models copy as plain text
  /// (e.g. `[Executed tools in this turn: ...]`) instead of making real calls.
  String _stripFakeToolMarkers(String text) {
    final cleaned = text.replaceAll(
      RegExp(
        r'^\s*\[Executed tools in this turn:[^\]]*\]\s*$',
        multiLine: true,
      ),
      '',
    );
    return cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Keeps the LLM tool schema lean (OpenCode-style ~14-16 tools instead of 45+)
  /// by filtering built-in MCP tools based on user intent while preserving all
  /// custom external MCP servers.
  List<Map<String, dynamic>> _selectRelevantMcpTools({
    required List<Map<String, dynamic>> rawMcp,
    required String prompt,
    required bool hasNativeFs,
  }) {
    final q = prompt.toLowerCase();
    final wantsWeb = RegExp(
      r'(http|https|url|docs|документ|найди в инете|поиск|интернет|pub\.dev|npm|mdn|stackoverflow)',
    ).hasMatch(q);
    final wantsBuildOrDevice = RegExp(
      r'(apk|aab|gradle|build|сборк|собери|установи|adb|logcat|shizuku|устройств|телефон|девайс|crash|вылет)',
    ).hasMatch(q);
    final wantsDbOrNet = RegExp(
      r'(sqlite|sql|\.db|database|баз[аыуе]|таблиц|network|трафик|talker|лог)',
    ).hasMatch(q);
    final wantsTests = RegExp(r'(test|тест|todo|fixme)').hasMatch(q);
    final wantsMemory = RegExp(
      r'(запомни|память|memory|сохрани правило)',
    ).hasMatch(q);

    final out = <Map<String, dynamic>>[];
    for (final t in rawMcp) {
      final server = (t['server']?.toString() ?? '').trim();
      final serverLower = server.toLowerCase();
      final name = (t['name']?.toString() ?? '').trim();
      if (hasNativeFs &&
          (serverLower == 'local filesystem access' ||
              serverLower == 'quantum-filesystem' ||
              serverLower == 'quantum-shell')) {
        continue;
      }
      if (!serverLower.startsWith('quantum-')) {
        // User-configured external MCP server (e.g. dart mcp-server, github, etc.)
        out.add(t);
        continue;
      }
      switch (serverLower) {
        case 'quantum-codegraph':
          if (name == 'read_symbol' || name == 'find_symbol_usages') {
            out.add(t);
          }
          break;
        case 'quantum-token-saver':
          if (wantsTests && (name == 'run_tests' || name == 'scan_todos')) {
            out.add(t);
          }
          break;
        case 'quantum-web-fetch':
          if (wantsWeb) out.add(t);
          break;
        case 'quantum-build-doctor':
        case 'quantum-device-qa':
          if (wantsBuildOrDevice) out.add(t);
          break;
        case 'quantum-sqlite-telemetry':
          if (wantsDbOrNet) out.add(t);
          break;
        case 'quantum-memory':
          if (wantsMemory) out.add(t);
          break;
      }
    }
    return out;
  }

  String _buildTurnHistorySummary(RoxumConversationTurn turn, String workspace) {
    final cleanText = _stripFakeToolMarkers(turn.aiResponse);
    if (turn.fileEdits.isEmpty) return cleanText;
    final wsPrefix = workspace.isNotEmpty
        ? '${workspace.replaceAll('\\', '/')}/'
        : '';
    final files = turn.fileEdits
        .map((fe) {
          final norm = fe.filePath.replaceAll('\\', '/');
          final rel = wsPrefix.isNotEmpty && norm.startsWith(wsPrefix)
              ? norm.substring(wsPrefix.length)
              : norm;
          return '$rel (+${fe.addedLines}/-${fe.removedLines})';
        })
        .join(', ');
    if (cleanText.isEmpty) {
      return 'Updated files: $files.';
    }
    return '$cleanText\n\n(Modified files: $files)';
  }

  String _loadProjectContextBlocks(String workspace) {
    if (workspace.isEmpty) return '';
    final buf = StringBuffer();
    for (final rel in const [
      '.quantum/AGENTS.md',
      'AGENTS.md',
      'GEMINI.md',
      'CLAUDE.md',
      '.cursorrules',
    ]) {
      try {
        final f = File('$workspace/$rel');
        if (f.existsSync()) {
          final text = f.readAsStringSync().trim();
          if (text.isNotEmpty) {
            final clipped = text.length > 4000
                ? '${text.substring(0, 4000)}\n...'
                : text;
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
          buf.writeln(
            '\n[PERSISTENT PROJECT MEMORY (.quantum_memory.json)]:\n$clipped',
          );
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

    _updateCurrentSession(title: updatedTitle, turns: [...baseTurns, newTurn]);

    _cancelled = false;
    final runToken = ++_activeRunToken;
    state = state.copyWith(
      isGenerating: true,
      selectedModelId: model.id,
    );

    final workspace = ref.read(workspaceProvider).currentPath ?? '';
    final runtime = ref.read(runtimeServiceProvider);
    final guestWorkspace = runtime.toProotPath(workspace);
    final activeFilePath = ref.read(editorProvider).activeFilePath;

    final startedAt = DateTime.now();
    var stepStartedAt = startedAt;
    var currentStep = 0;
    final stepReasonings = <int, String>{};
    final turnEditedPaths = <String>{};
    final stepEditIds = <String, String>{};
    final pendingCopy = Map<String, RoxumPendingEdit>.from(state.pendingEdits);
    final lastSeenContent = <String, String>{
      for (final e in pendingCopy.entries) e.key: e.value.updatedContent,
    };

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

    void handlePendingEditsChanged(Map<String, RoxumPendingEdit> updated) {
      state = state.copyWith(pendingEdits: updated);
      for (final k in updated.keys) {
        final nextContent = updated[k]!.updatedContent;
        if (lastSeenContent[k] != nextContent || !turnEditedPaths.contains(k)) {
          lastSeenContent[k] = nextContent;
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
    }

    void handleToolEvent(RoxumToolCallRecord record) {
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
        return turn.copyWith(
          aiResponse: record.isRunning ? '' : turn.aiResponse,
          toolCalls: list,
          timeline: tl,
        );
      });
    }

    void handleAssistantText(String text) {
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
    }

    void handleReasoningText(String reasoning) {
      final now = DateTime.now();
      final totalElapsed = now.difference(startedAt).inMilliseconds;
      final stepElapsed = now.difference(stepStartedAt).inMilliseconds;
      if (reasoning.trim().isNotEmpty) {
        stepReasonings[currentStep] = reasoning.trim();
      }
      final combinedReasoning = (stepReasonings.keys.toList()..sort())
          .map((k) => stepReasonings[k]!)
          .join('\n\n');
      _updateTurn(turnId, (turn) {
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
          reasoningText: combinedReasoning,
          thinkingDurationMs: totalElapsed,
          timeline: tl,
        );
      });
    }

    void handleUsage(RoxumUsageStats usage) {
      state = state.copyWith(sessionUsage: state.sessionUsage + usage);
      _updateTurn(turnId, (turn) => turn.copyWith(usage: turn.usage + usage));
    }

    try {
      final String finalAnswer;
      final agentTools = state.chatMode == RoxumChatMode.agent
          ? _buildPocketStrikeTools(
              workspace: workspace,
              pendingCopy: pendingCopy,
              onPendingEditsChanged: handlePendingEditsChanged,
            )
          : const <ps.AgentTool>[];

      final projectBlocks = _loadProjectContextBlocks(workspace);
      final matchedSkillsBlock = RoxumSkillLoader.buildMatchedSkillsBlock(
        workspace: workspace,
        userPrompt: trimmed,
        activeFilePath: activeFilePath,
      );

      final systemPrompt = state.chatMode == RoxumChatMode.agent
          ? 'You are Roxum, an autonomous Staff Software Engineer inside QuantumIDE (PocketStrike execution engine).\n'
                'Workspace: "$workspace"${guestWorkspace != workspace ? ' (shell path: "$guestWorkspace")' : ''}.'
                '${activeFilePath != null ? ' Active file: "$activeFilePath".' : ''}\n\n'
                'CORE OPERATING PRINCIPLES:\n'
                '1) ACT DIRECTLY WITH TOOLS: Execute tasks end-to-end using real tool calls (`readFile`, `writeFile`, `editFile`, `multiEditFile`, `listFiles`, `globSearchFiles`, `grepInFiles`, `getLspDiagnostics`, `runCommand`). NEVER stop mid-task with promises like "Исправлю:" / "Let me fix:" or dump unapplied code into chat.\n'
                '2) ZERO WASTED STEPS: Do NOT call `checkEnvironment` unless a shell command failed with `command not found`. `readFile` reads up to 1200 lines in ONE call — read full files directly instead of making many tiny 15-line reads. Always use workspace-relative paths (e.g. `lib/main.dart`).\n'
                '3) CREATING NEW GAMES & APPS (MODULAR + MOBILE-PLAYABLE): When the user asks to CREATE a game or app (e.g. "создай игру...", "сделай приложение..."), NEVER cram 500-1000 lines into a single `lib/main.dart`, and NEVER stop after merely patching 1-2 lint errors in an old/broken/desktop-only `lib/main.dart` stub! Split cleanly into focused modules of 120-260 lines each (`lib/models/...`, `lib/game/...` or `lib/controllers/...`, `lib/widgets/...`) wired from a clean `lib/main.dart`. For Flutter games on Android/mobile, ALWAYS include working on-screen touch controls (virtual D-pad/joystick + Attack/Mine/Place/Jump buttons) alongside optional keyboard support.\n'
                '4) SURGICAL EDITS & MULTIEDIT: When fixing bugs or modifying existing features, NEVER rewrite whole files with `writeFile` and NEVER use placeholders like `// ... existing code`. Pass a native JSON array (NOT a string) to `multiEditFile` to apply multiple fixes in ONE call, and include 2-3 surrounding lines in `oldText` so it uniquely matches.\n'
                '5) INLINE DIAGNOSTICS & ZERO-ERROR STOP RULE: `writeFile`, `editFile`, and `multiEditFile` automatically run static analysis and append `[Diagnostics for ...]`. Fix every `error •` immediately until `0 error(s)`. Once `0 error(s)` is reached, STOP chasing `info`/`warning` lints (`deprecated_member_use`, `prefer_final_fields`, `unused_field`) and focus on completing the user\'s actual feature or delivering your concise final summary!\n'
                '6) MODERN FLUTTER / DART RULES:\n'
                '   - Keyboard events: NEVER use `RawKeyEvent`, `RawKeyDownEvent`, `RawKeyboardListener`, `Focus(onKey: ...)`, or `KeyboardListener`! Use ONLY `Focus(autofocus: true, onKeyEvent: (node, event) { if (event is KeyDownEvent) { ... } return KeyEventResult.handled; })` with `import \'package:flutter/services.dart\';`.\n'
                '   - Colors & Const: `Color` has NO `*` operator — use `Color.lerp(...)` or `.withValues(alpha: ...)`. Never put `\${...}` string interpolation or runtime getters inside `const` widgets (`const Text(...)`).\n'
                '   - Packages: Add packages via `runCommand` (`flutter pub add <pkg>`). If `pubspec.yaml` has broken/non-existent dependencies or SDK constraints causing analyzer errors, fix `pubspec.yaml` and run `flutter pub get`.\n'
                '7) HONEST SUMMARY: In your final answer, concisely report ONLY the files actually created/modified and verification status.'
                '$projectBlocks'
                '$matchedSkillsBlock\n'
                'Always respond in the user\'s language.'
          : 'You are a helpful coding assistant inside QuantumIDE. '
                '${activeFilePath != null ? 'Active file: "$activeFilePath". ' : ''}'
                '$projectBlocks'
                '$matchedSkillsBlock\n'
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
          if (t.aiResponse.isNotEmpty || t.fileEdits.isNotEmpty)
            {
              'role': 'assistant',
              'content': _buildTurnHistorySummary(t, workspace),
            },
        ],
        {'role': 'user', 'content': currentUserContent},
      ];

      final answerBuffer = StringBuffer();
      final callRecordIds = <String, String>{};
      final turnMessages = history
          .map(
            (m) => ChatMessage(
              id: m['id']?.toString() ?? '',
              role: switch (m['role']?.toString()) {
                'system' => MessageRole.system,
                'user' => MessageRole.user,
                'tool' => MessageRole.tool,
                _ => MessageRole.assistant,
              },
              content: m['content']?.toString() ?? '',
              toolCallId: m['tool_call_id']?.toString(),
              toolName: m['name']?.toString(),
            ),
          )
          .toList();

      final provider = _buildPocketStrikeProvider(model);
      final cancelToken = CancelToken();
      _activeCancelToken = cancelToken;

      await for (final event in AgentEngine(maxSteps: 48).run(
        provider: provider,
        history: turnMessages,
        model: model.model,
        params: GenerationParams(systemPrompt: systemPrompt),
        tools: agentTools,
        policy: ps.ConfirmationPolicy.autonomous,
        cancelToken: cancelToken,
        requestConfirmation: (tool, call) async => ConfirmResult.allow,
      )) {
        switch (event) {
          case AgentStatusEvent(:final status):
            handleReasoningText(status);
          case AgentTextDeltaEvent(:final text):
            answerBuffer.write(text);
            handleAssistantText(text);
          case AgentToolCallStartedEvent(:final call):
            final recordId = callRecordIds.putIfAbsent(
              call.id,
              () => DateTime.now().microsecondsSinceEpoch.toString(),
            );
            handleToolEvent(
              RoxumToolCallRecord(
                id: recordId,
                name: call.name,
                arguments: call.argumentsJson.isEmpty
                    ? const {}
                    : (() {
                        try {
                          return Map<String, dynamic>.from(
                            jsonDecode(call.argumentsJson) as Map,
                          );
                        } catch (_) {
                          return <String, dynamic>{};
                        }
                      })(),
              ),
            );
          case AgentToolCallCompletedEvent(
              :final call,
              :final result,
              :final isError
            ):
            final recordId = callRecordIds.putIfAbsent(
              call.id,
              () => DateTime.now().microsecondsSinceEpoch.toString(),
            );
            handleToolEvent(
              RoxumToolCallRecord(
                id: recordId,
                name: call.name,
                arguments: const {},
                isRunning: false,
                success: !isError,
                output: result,
              ),
            );
          case AgentToolCallDeniedEvent(:final call):
            final recordId = callRecordIds.putIfAbsent(
              call.id,
              () => DateTime.now().microsecondsSinceEpoch.toString(),
            );
            handleToolEvent(
              RoxumToolCallRecord(
                id: recordId,
                name: call.name,
                arguments: const {},
                isRunning: false,
                success: false,
                output: 'Отклонено политикой безопасности',
              ),
            );
          case AgentUsageEvent(:final usage):
            final pTok = usage.promptTokens ?? 0;
            final cTok = usage.completionTokens ?? 0;
            final total = usage.total;
            if (total > 0) {
              handleUsage(
                RoxumUsageStats(
                  promptTokens: pTok,
                  completionTokens: cTok,
                  totalTokens: total,
                ),
              );
            }
          case AgentRunErrorEvent(:final message):
            handleReasoningText('Error: $message');
            if (answerBuffer.isEmpty) {
              answerBuffer.write('Error: $message');
            }
          case AgentAssistantMessageEvent(:final message):
            // AgentEngine streams the final answer as deltas AND emits the
            // assembled message. Do not append it twice.
            if (answerBuffer.isEmpty) {
              answerBuffer.write(message.content);
              handleAssistantText(message.content);
            }
          case AgentRunFinishedEvent():
            break;
        }
      }
      _activeCancelToken = null;
      finalAnswer = answerBuffer.toString();

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
          (turn) =>
              turn.copyWith(aiResponse: 'Ошибка запроса: $e', isError: true),
        );
      }
    } finally {
      if (_activeRunToken == runToken) {
        state = state.copyWith(isGenerating: false);
      }
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

  AIProvider _buildPocketStrikeProvider(RoxumModelOption model) {
    switch (model.method) {
      case RoxumToolCallingMethod.anthropicMessages:
        return AnthropicProvider(
          configId: model.id,
          baseUrl: 'https://api.anthropic.com',
          apiKey: model.apiKey,
        );
      case RoxumToolCallingMethod.geminiFunctionCalling:
        return GeminiProvider(
          configId: model.id,
          baseUrl: 'https://generativelanguage.googleapis.com',
          apiKey: model.apiKey,
        );
      case RoxumToolCallingMethod.openAiCompatible:
        final p = model.provider.toLowerCase();
        final ProviderType providerType;
        if (p.contains('openrouter') || model.url.contains('openrouter.ai')) {
          providerType = ProviderType.openrouter;
        } else if (p == 'openai') {
          providerType = ProviderType.openai;
        } else if (p == 'groq') {
          providerType = ProviderType.groq;
        } else if (p.contains('nvidia')) {
          providerType = ProviderType.nvidia;
        } else if (p.contains('ollama')) {
          providerType = ProviderType.ollama;
        } else {
          providerType = ProviderType.custom;
        }
        return OpenAiCompatibleProvider(
          configId: model.id,
          type: providerType,
          baseUrl: RoxumModelOption.normalizeOpenAiBaseUrl(model.url),
          apiKey: model.apiKey,
        );
    }
  }

  List<ps.AgentTool> _buildPocketStrikeTools({
    required String workspace,
    required Map<String, RoxumPendingEdit> pendingCopy,
    required void Function(Map<String, RoxumPendingEdit>) onPendingEditsChanged,
  }) {
    final agenticRunner = RoxumAgenticTools(
      ref,
      pendingEdits: pendingCopy,
      onPendingEditsChanged: onPendingEditsChanged,
    );
    final openAiSpecs = RoxumAgenticTools.buildOpenAiTools(
      state.toolSelections,
    );
    final tools = <ps.AgentTool>[];
    final seenNames = <String>{};

    for (final spec in openAiSpecs) {
      final fn = spec['function'];
      if (fn is! Map) continue;
      final name = fn['name']?.toString() ?? '';
      if (name.isEmpty || !seenNames.add(name)) continue;
      final description = fn['description']?.toString() ?? '';
      final rawParams = fn['parameters'];
      final schema = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : const <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            };
      final isDestructive =
          isAgenticWriteTool(name) || name == 'runCommand';
      tools.add(
        ps.AgentTool(
          name: name,
          description: description,
          inputSchema: schema,
          risk: isDestructive ? ps.ToolRisk.destructive : ps.ToolRisk.safe,
          run: (args) async {
            final res = await agenticRunner.execute(name, args);
            if (!res.success && !res.output.trimLeft().startsWith('Error')) {
              return 'Error: ${res.output}';
            }
            return res.output;
          },
        ),
      );
    }

    final allowedRoots =
        workspace.isNotEmpty ? <String>[workspace] : const <String>[];
    for (final builtIn in BuiltInTools.all(allowedRoots: allowedRoots)) {
      if (seenNames.add(builtIn.name)) {
        tools.add(builtIn);
      }
    }

    final enabledIds = ref
            .read(mcpServersProvider)
            .value
            ?.where((server) => server.enabled)
            .map((server) => server.id)
            .toSet() ??
        <String>{};
    tools.addAll(
      ref
          .read(mcpConnectionsProvider.notifier)
          .manager
          .toolsForServers(enabledIds),
    );
    return tools;
  }
}
