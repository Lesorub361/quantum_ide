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
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_acp_bridge.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_skill_loader.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/agent/data/agent_engine.dart';
import 'package:quantum_ide/features/agent/domain/agent_event.dart';
import 'package:quantum_ide/features/agent/domain/agent_tool.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

/// Feature flag for the PocketStrike-style ReAct engine.
/// Enable with: --dart-define=QI_USE_NEW_AGENT=true
const bool useNewAgentEngine =
    bool.fromEnvironment('QI_USE_NEW_AGENT', defaultValue: false);

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
  final RoxumAgentEngine agentEngine;
  final Map<RoxumAgentEngine, bool> installedEngines;
  final RoxumAgentEngine? installingEngine;
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
    this.agentEngine = RoxumAgentEngine.builtIn,
    this.installedEngines = const {
      RoxumAgentEngine.builtIn: true,
      RoxumAgentEngine.opencodeAcp: false,
      RoxumAgentEngine.geminiAcp: false,
      RoxumAgentEngine.claudeAcp: false,
    },
    this.installingEngine,
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
    RoxumAgentEngine? agentEngine,
    Map<RoxumAgentEngine, bool>? installedEngines,
    RoxumAgentEngine? installingEngine,
    bool clearInstallingEngine = false,
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
      agentEngine: agentEngine ?? this.agentEngine,
      installedEngines: installedEngines ?? this.installedEngines,
      installingEngine: clearInstallingEngine
          ? null
          : (installingEngine ?? this.installingEngine),
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
  static const String _enginePrefsKey = 'roxum_agent_engine_v1';

  final RoxumAiClient _client = RoxumAiClient();
  final RoxumAcpBridge _acpBridge = RoxumAcpBridge();
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
      _client.cancel();
      _acpBridge.resetSession();
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
    Future.microtask(_restoreAndDetectEngines);
    Future.microtask(refreshAllModels);
    return RoxumChatState(
      sessions: [initialSession],
      currentSessionId: initialId,
      toolSelections: normalizeAgenticToolSelections(null),
    );
  }

  Future<void> _restoreAndDetectEngines() async {
    String? savedEngine;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedEngine = prefs.getString(_enginePrefsKey);
      if (savedEngine != null && savedEngine.isNotEmpty) {
        state = state.copyWith(
          agentEngine: RoxumAgentEngine.fromId(savedEngine),
        );
      }
    } catch (_) {}

    final detected = await refreshInstalledEngines();
    // Auto-select OpenCode (ACP) on first launch if `opencode` is already
    // installed in the user's PRoot/Desktop environment!
    if ((savedEngine == null || savedEngine.isEmpty) &&
        detected[RoxumAgentEngine.opencodeAcp] == true) {
      state = state.copyWith(agentEngine: RoxumAgentEngine.opencodeAcp);
    }
  }

  Future<Map<RoxumAgentEngine, bool>> refreshInstalledEngines() async {
    try {
      final runtime = ref.read(runtimeServiceProvider);
      final detected = await RoxumAcpBridge.detectInstalledEngines(runtime);
      state = state.copyWith(installedEngines: detected);
      return detected;
    } catch (_) {
      return state.installedEngines;
    }
  }

  Future<void> setAgentEngine(RoxumAgentEngine engine) async {
    if (state.agentEngine == engine) return;
    await _acpBridge.resetSession();
    state = state.copyWith(agentEngine: engine);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_enginePrefsKey, engine.id);
    } catch (_) {}
  }

  Future<({bool success, String output})> installAgentEngine(
    RoxumAgentEngine engine,
  ) async {
    if (state.installingEngine != null) {
      return (success: false, output: 'Уже выполняется установка другого движка.');
    }
    state = state.copyWith(installingEngine: engine);
    try {
      final runtime = ref.read(runtimeServiceProvider);
      final res = await RoxumAcpBridge.installEngine(runtime, engine);
      await refreshInstalledEngines();
      if (res.success) {
        await setAgentEngine(engine);
      }
      return res;
    } finally {
      state = state.copyWith(clearInstallingEngine: true);
    }
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
    _acpBridge.resetSession();
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
    if (state.currentSessionId != id) {
      _acpBridge.resetSession();
    }
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
    if (state.currentSessionId == id) {
      _acpBridge.resetSession();
    }
    state = state.copyWith(sessions: remaining, currentSessionId: nextId);
    _persistSessions();
  }

  void stopGeneration() {
    _cancelled = true;
    _client.cancel();
    _acpBridge.cancelActiveTurn();
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
    for (final rel in const ['.quantum/AGENTS.md', 'AGENTS.md', 'GEMINI.md']) {
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
    final useAcp =
        state.chatMode == RoxumChatMode.agent &&
        state.agentEngine != RoxumAgentEngine.builtIn;

    if (!useAcp && models.isEmpty) {
      _appendErrorTurn(
        trimmed,
        'Нет настроенных провайдеров. Нажмите «Подключить API» в шапке чата, чтобы добавить ключ или локальный сервер (например http://IP:8080/v1).',
      );
      return;
    }

    final RoxumModelOption? model = models.isEmpty
        ? null
        : models.firstWhere(
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
      selectedModelId: model?.id ?? state.selectedModelId,
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
      if (useAcp) {
        finalAnswer = await _acpBridge.runPromptTurn(
          ref: ref,
          engine: state.agentEngine,
          workspacePath: workspace,
          chatSessionId: state.currentSessionId,
          promptText: trimmed,
          attachments: attachments,
          settings: settings,
          selectedModelId: model?.id ?? state.selectedModelId,
          pendingEdits: pendingCopy,
          onPendingEditsChanged: handlePendingEditsChanged,
          onToolEvent: handleToolEvent,
          onAssistantText: handleAssistantText,
          onReasoningText: handleReasoningText,
          onUsage: handleUsage,
          isCancelled: () => _cancelled,
        );
      } else {
        final baseTools = state.chatMode == RoxumChatMode.agent
            ? RoxumAgenticTools.buildOpenAiTools(state.toolSelections)
            : const <Map<String, dynamic>>[];
        List<Map<String, dynamic>> mcpTools = const [];
        if (state.chatMode == RoxumChatMode.agent &&
            ref.read(mcpServiceProvider).any((s) => s.isEnabled)) {
          try {
            final rawMcp = await ref
                .read(mcpServiceProvider.notifier)
                .getAvailableMcpTools()
                .timeout(const Duration(seconds: 12));
            RoxumAgenticTools.buildMcpOpenAiTools(rawMcp);
            final filteredMcp = _selectRelevantMcpTools(
              rawMcp: rawMcp,
              prompt: trimmed,
              hasNativeFs: baseTools.any((t) {
                final fnName =
                    (t['function'] as Map?)?['name']?.toString() ?? '';
                return fnName == 'readFile' || fnName == 'writeFile';
              }),
            );
            mcpTools = RoxumAgenticTools.buildMcpOpenAiTools(filteredMcp);
            RoxumAgenticTools.buildMcpOpenAiTools(rawMcp);
          } catch (_) {}
        }
        final toolsSchema = <Map<String, dynamic>>[...baseTools, ...mcpTools];

        final projectBlocks = _loadProjectContextBlocks(workspace);
        final matchedSkillsBlock = RoxumSkillLoader.buildMatchedSkillsBlock(
          workspace: workspace,
          userPrompt: trimmed,
          activeFilePath: activeFilePath,
        );

        final systemPrompt = state.chatMode == RoxumChatMode.agent
            ? 'You are Roxum, an autonomous Staff Software Engineer inside QuantumIDE (OpenCode-grade execution engine).\n'
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

        final toolsRunner = state.chatMode == RoxumChatMode.agent
            ? RoxumAgenticTools(
                ref,
                pendingEdits: pendingCopy,
                onPendingEditsChanged: handlePendingEditsChanged,
              )
            : null;

        if (useNewAgentEngine && toolsRunner != null) {
          // PocketStrike-style ReAct engine: UI-agnostic, no ad-hoc nudges.
          final engineTools = <AgentTool>[];
          for (final spec in toolsSchema) {
            final fn = (spec['function'] as Map?) ?? const {};
            final name = fn['name']?.toString() ?? '';
            if (name.isEmpty) continue;
            final description = fn['description']?.toString() ?? name;
            final rawSchema =
                (fn['parameters'] as Map?) ?? const <String, dynamic>{};
            final schema = Map<String, dynamic>.from(rawSchema);
            engineTools.add(
              AgentTool(
                name: name,
                description: description,
                inputSchema: schema,
                risk: name.startsWith('mcp__')
                    ? ToolRisk.external
                    : (name.contains('write') ||
                            name.contains('delete') ||
                            name.contains('runCommand'))
                        ? ToolRisk.destructive
                        : ToolRisk.safe,
                run: (args) async {
                  final res = await toolsRunner.execute(name, args);
                  return res.output;
                },
              ),
            );
          }

          final answerBuffer = StringBuffer();
          final engine = AgentEngine(maxSteps: 48);
          await for (final event in engine.run(
            runTurn: ({
              required messages,
              required toolSpecs,
              required onText,
              required onReasoning,
              required isCancelled,
            }) async {
              final turn = await _client.streamTurnForAgent(
                model: model!,
                messages: messages,
                toolSpecs: toolSpecs,
                onText: onText,
                onReasoning: onReasoning,
                isCancelled: isCancelled,
              );
              return AgentTurnResult(
                text: turn.text,
                reasoning: turn.reasoning,
                toolCalls: turn.toolCalls
                    .map(
                      (c) => (
                        id: c.id,
                        name: c.name,
                        args: c.args,
                      ),
                    )
                    .toList(),
              );
            },
            history: history,
            tools: engineTools,
            policy: ConfirmationPolicy.destructiveOnly,
            requestConfirmation: (tool, call) async {
              // Existing UI confirmation sheet is wired in handleToolEvent for
              // the legacy loop; the new engine currently auto-approves.
              return ConfirmResult.allow;
            },
            isCancelled: () => _cancelled,
          )) {
            switch (event) {
              case AgentStepEvent(:final step):
                currentStep = step;
                stepStartedAt = DateTime.now();
              case AgentStatusEvent(:final message):
                handleReasoningText(message);
              case AgentReasoningEvent(:final text):
                handleReasoningText(text);
              case AgentTextDeltaEvent(:final text):
                answerBuffer.write(text);
                handleAssistantText(text);
              case AgentToolCallStartedEvent(:final name, :final args):
                handleToolEvent(
                  RoxumToolCallRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    arguments: args,
                  ),
                );
              case AgentToolCallCompletedEvent(
                  :final name,
                  :final output,
                  :final isError
                ):
                handleToolEvent(
                  RoxumToolCallRecord(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name,
                    arguments: const {},
                    isRunning: false,
                    success: !isError,
                    output: output,
                  ),
                );
              case AgentRunErrorEvent(:final message):
                handleReasoningText('Error: $message');
              case AgentRunFinishedEvent():
                break;
              default:
                break;
            }
          }
          finalAnswer = answerBuffer.toString();
        } else {
          finalAnswer = await _client.runAgentLoop(
            model: model!,
            historyMessages: history,
            tools: toolsSchema,
            agenticTools: toolsRunner,
            isCancelled: () => _cancelled,
            onStepStart: (step) {
              currentStep = step;
              stepStartedAt = DateTime.now();
            },
            onRetryStatus: (status) {
              handleReasoningText(status);
            },
            onToolEvent: handleToolEvent,
            onAssistantText: handleAssistantText,
            onReasoningText: handleReasoningText,
            onUsage: handleUsage,
          );
        }
      }

      if (model?.provider == 'OpenRouter') {
        refreshOpenRouterLimits();
      }

      if (!_cancelled) {
        final cleanedAnswer = _stripFakeToolMarkers(finalAnswer);
        final effectiveAnswer = cleanedAnswer.trim().isNotEmpty
            ? cleanedAnswer
            : 'Модель вернула пустой ответ. Попробуйте повторить запрос или сменить движок/модель.';
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
}
