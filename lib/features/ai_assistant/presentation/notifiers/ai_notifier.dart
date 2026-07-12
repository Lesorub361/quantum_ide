import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:quantum_ide/models/chat_session.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/providers/locale_provider.dart';
import 'package:quantum_ide/core/services/ai_permission_service.dart';
import 'package:quantum_ide/core/services/ai_context_compressor.dart';
import 'package:quantum_ide/core/services/analysis_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'ai_prompts.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:dio/dio.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:quantum_ide/core/services/local_inference_service.dart';
import 'package:quantum_ide/core/services/local_action_translator.dart';

// ─── Top-level функция для Isolate — не должна быть методом класса ───
/// Запускается через compute() — не блокирует UI поток.
/// args[0] = workspacePath, args[1] = query
List<String> _grepSearchIsolate(List<String> args) {
  final workspacePath = args[0];
  final query = args[1].toLowerCase();
  final dir = Directory(workspacePath);
  final results = <String>[];
  int matchCount = 0;

  try {
    final entities = dir.listSync(recursive: true, followLinks: false);
    for (final file in entities) {
      if (file is! File) continue;
      final path = file.path;
      // Игнорируем бинарные и служебные директории
      if (path.contains('/.git/') ||
          path.contains('/.dart_tool/') ||
          path.contains('/build/') ||
          path.contains('/.idea/') ||
          path.contains('/ios/Pods/') ||
          path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.ico') ||
          path.endsWith('.apk') ||
          path.endsWith('.pdf') ||
          path.endsWith('.ttf') ||
          path.endsWith('.otf')) {
        continue;
      }
      try {
        final fileContent = file.readAsStringSync();
        if (fileContent.toLowerCase().contains(query)) {
          final lines = fileContent.split('\n');
          for (int i = 0; i < lines.length; i++) {
            if (lines[i].toLowerCase().contains(query)) {
              final relPath = p.relative(path, from: workspacePath);
              results.add('$relPath:${i + 1}: ${lines[i].trim()}');
              matchCount++;
              if (matchCount >= 50) break;
            }
          }
        }
      } catch (_) {}
      if (matchCount >= 50) break;
    }
  } catch (_) {}
  return results;
}


enum AiApprovalMode { manual, semiAutonomous, fullAutonomous }

class AIState {
  final bool isLoading;
  final List<ChatMessage> messages;
  final String? error;
  final int totalTokens;
  final List<AIAction> proposedActions;
  final AiApprovalMode approvalMode;
  final AiInteractionMode interactionMode;
  final String? activeAgentRole; // 'Planner', 'Coder', 'Validator', or null
  /// Пути файлов, которые агент прочитал (для отображения в проводнике)
  final List<String> agentReadFiles;
  final String? currentStatusMessage;
  final List<ChatSession> sessions;
  final String? currentSessionId;
  final String? sessionGoal;
  final int lastPromptTokens;
  final int lastCompletionTokens;

  AIState({
    this.isLoading = false,
    this.messages = const [],
    this.error,
    this.totalTokens = 0,
    this.proposedActions = const [],
    this.approvalMode = AiApprovalMode.manual,
    this.interactionMode = AiInteractionMode.chat,
    this.activeAgentRole,
    this.agentReadFiles = const [],
    this.currentStatusMessage,
    this.sessions = const [],
    this.currentSessionId,
    this.sessionGoal,
    this.lastPromptTokens = 0,
    this.lastCompletionTokens = 0,
  });

  bool get isAutopilot => approvalMode != AiApprovalMode.manual;

  AIState copyWith({
    bool? isLoading,
    List<ChatMessage>? messages,
    String? error,
    int? totalTokens,
    List<AIAction>? proposedActions,
    AiApprovalMode? approvalMode,
    AiInteractionMode? interactionMode,
    String? activeAgentRole,
    bool? isAutopilot,
    List<String>? agentReadFiles,
    String? currentStatusMessage,
    List<ChatSession>? sessions,
    String? currentSessionId,
    String? sessionGoal,
    int? lastPromptTokens,
    int? lastCompletionTokens,
  }) {
    return AIState(
      isLoading: isLoading ?? this.isLoading,
      messages: messages ?? this.messages,
      error: error ?? this.error,
      totalTokens: totalTokens ?? this.totalTokens,
      proposedActions: proposedActions ?? this.proposedActions,
      approvalMode: approvalMode ?? 
          (isAutopilot != null 
               ? (isAutopilot ? AiApprovalMode.semiAutonomous : AiApprovalMode.manual) 
               : this.approvalMode),
      interactionMode: interactionMode ?? this.interactionMode,
      activeAgentRole: activeAgentRole ?? this.activeAgentRole,
      agentReadFiles: agentReadFiles ?? this.agentReadFiles,
      currentStatusMessage: currentStatusMessage ?? this.currentStatusMessage,
      sessions: sessions ?? this.sessions,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      sessionGoal: sessionGoal ?? this.sessionGoal,
      lastPromptTokens: lastPromptTokens ?? this.lastPromptTokens,
      lastCompletionTokens: lastCompletionTokens ?? this.lastCompletionTokens,
    );
  }
}

class AINotifier extends StateNotifier<AIState> {
  final Ref _ref;
  final Map<String, String?> _currentStepBackups = {};
  final AiContextCompressor _contextCompressor = AiContextCompressor();
  final AiPermissionService _permissionService = const AiPermissionService();
  // Shared Dio instance — не создаём новый на каждый запрос
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  AINotifier(this._ref) : super(AIState()) {
    _ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      if (next.currentPath != previous?.currentPath) {
        if (next.currentPath != null) {
          loadSessionsForWorkspace(next.currentPath!);
        } else {
          clear();
        }
      }
    });

    // Load initial workspace if already set
    final initPath = _ref.read(workspaceProvider).currentPath;
    if (initPath != null) {
      loadSessionsForWorkspace(initPath);
    }
  }

  Future<void> loadSessionsForWorkspace(String workspacePath) async {
    await _loadSessions(workspacePath);
  }

  Future<void> _saveSessions() async {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    try {
      // Use workspace .quantum/ dir if available, otherwise fallback to app documents
      final String saveDir;
      if (workspacePath != null) {
        saveDir = p.join(workspacePath, '.quantum');
      } else {
        final appDir = await _getAppDataDir();
        saveDir = p.join(appDir, '.quantum');
      }
      final dir = Directory(saveDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File(p.join(dir.path, 'chat_history.json'));
      // Strip heavy fields to keep file small: executedActions content can be huge
      final trimmedSessions = state.sessions.map((s) {
        final trimmedMessages = s.messages.map((m) {
          final json = m.toJson();
          // Remove executedActions content (can be entire file contents)
          if (json['executedActions'] != null) {
            final actions = (json['executedActions'] as List).map((a) {
              final action = Map<String, dynamic>.from(a);
              if (action['content'] != null && (action['content'] as String).length > 500) {
                action['content'] = '(truncated)';
              }
              return action;
            }).toList();
            json['executedActions'] = actions;
          }
          // Remove large actionResults
          if (json['actionResults'] != null) {
            final results = Map<String, String>.from(json['actionResults']);
            final trimmed = <String, String>{};
            for (final entry in results.entries) {
              trimmed[entry.key] = entry.value.length > 500
                  ? '${entry.value.substring(0, 500)}...'
                  : entry.value;
            }
            json['actionResults'] = trimmed;
          }
          // Remove imageBase64 (can be megabytes)
          json.remove('imageBase64');
          return json;
        }).toList();
        return {
          'id': s.id,
          'title': s.title,
          'messages': trimmedMessages,
          'createdAt': s.createdAt.toIso8601String(),
        };
      }).toList();
      final jsonStr = jsonEncode(trimmedSessions);
      await file.writeAsString(jsonStr);
      debugPrint('[AINotifier] Saved ${state.sessions.length} session(s) with ${state.messages.length} messages to ${file.path} (${jsonStr.length} bytes)');
      
      if (workspacePath != null) {
        await _saveMemory(workspacePath);
      }
    } catch (e) {
      debugPrint('[AINotifier] Error saving chat sessions: $e');
    }
  }

  Future<void> _saveMemory(String workspacePath) async {
    try {
      final dir = Directory(p.join(workspacePath, '.quantum'));
      if (!dir.existsSync()) return;
      
      final file = File(p.join(dir.path, 'memory.md'));
      final buf = StringBuffer();
      buf.writeln('# Session Memory');
      buf.writeln('Last updated: ${DateTime.now().toIso8601String()}');
      buf.writeln('');
      
      if (state.messages.isNotEmpty) {
        final userMessages = state.messages.where((m) => m.role == MessageRole.user).toList();
        if (userMessages.isNotEmpty) {
          buf.writeln('## Recent User Requests');
          for (final msg in userMessages.take(10)) {
            final preview = msg.content.length > 100 ? msg.content.substring(0, 100) : msg.content;
            buf.writeln('- $preview');
          }
          buf.writeln('');
        }

        if (state.agentReadFiles.isNotEmpty) {
          buf.writeln('## Files Read by Agent');
          for (final f in state.agentReadFiles.take(20)) {
            final rel = p.relative(f, from: workspacePath);
            buf.writeln('- $rel');
          }
          buf.writeln('');
        }
        
        buf.writeln('## Session Stats');
        buf.writeln('- Total messages: ${state.messages.length}');
        buf.writeln('- Total tokens used: ${state.totalTokens}');
        buf.writeln('- Files read: ${state.agentReadFiles.length}');
      }
      
      await file.writeAsString(buf.toString());
    } catch (e) {
      debugPrint('[AINotifier] Error saving memory: $e');
    }
  }

  Future<void> _loadSessions(String workspacePath) async {
    try {
      // Try workspace .quantum/ first, fallback to app documents
      var file = File(p.join(workspacePath, '.quantum', 'chat_history.json'));
      if (!file.existsSync()) {
        final appDir = await _getAppDataDir();
        final fallbackFile = File(p.join(appDir, '.quantum', 'chat_history.json'));
        if (fallbackFile.existsSync()) {
          file = fallbackFile;
          debugPrint('[AINotifier] Using fallback chat history from app dir');
        }
      }
      debugPrint('[AINotifier] Loading sessions from: ${file.path}');
      if (!file.existsSync()) {
        debugPrint('[AINotifier] No chat_history.json found, creating default session');
        final defaultSession = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'New Chat',
          messages: [],
          createdAt: DateTime.now(),
        );
        state = state.copyWith(
          sessions: [defaultSession],
          currentSessionId: defaultSession.id,
          messages: [],
        );
        return;
      }
      final jsonStr = await file.readAsString();
      debugPrint('[AINotifier] Read ${jsonStr.length} bytes from chat_history.json');
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final sessions = jsonList.map((j) => ChatSession.fromJson(j)).toList();
      debugPrint('[AINotifier] Loaded ${sessions.length} session(s)');
      if (sessions.isEmpty) {
        final defaultSession = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'New Chat',
          messages: [],
          createdAt: DateTime.now(),
        );
        state = state.copyWith(
          sessions: [defaultSession],
          currentSessionId: defaultSession.id,
          messages: [],
        );
        return;
      }
      // Set the last active/created session as current
      final lastSession = sessions.last;
      final restoredCount = lastSession.messages.length;
      state = state.copyWith(
        sessions: sessions,
        currentSessionId: lastSession.id,
        messages: lastSession.messages,
      );
      debugPrint('[AINotifier] Restored ${restoredCount} messages in active session');
      
      await _restoreMemory(workspacePath);
      
      if (restoredCount > 0 && lastSession.messages.any((m) => m.role == MessageRole.user)) {
        final l10n = _ref.read(localizationsProvider);
        _updateMessagesAndSync([
          ...state.messages,
          ChatMessage(
            role: MessageRole.system,
            content: '🔄 **${l10n.sessionRestored}**\n\n'
                '${l10n.sessionRestoredDetail(restoredCount, state.agentReadFiles.length)}',
            timestamp: DateTime.now(),
          )
        ]);
      }
    } catch (e) {
      debugPrint('[AINotifier] Error loading chat sessions: $e');
    }
  }

  Future<void> _restoreMemory(String workspacePath) async {
    try {
      final memoryFile = File(p.join(workspacePath, '.quantum', 'memory.md'));
      if (!memoryFile.existsSync()) return;
      
      final content = await memoryFile.readAsString();
      debugPrint('[AINotifier] Restored memory from ${memoryFile.path}');
      
      final readFiles = <String>[];
      final lines = content.split('\n');
      bool inFilesSection = false;
      for (final line in lines) {
        if (line.startsWith('## Files Read by Agent')) {
          inFilesSection = true;
          continue;
        }
        if (inFilesSection && line.startsWith('- ')) {
          final relPath = line.substring(2).trim();
          if (relPath.isNotEmpty) {
            readFiles.add(p.join(workspacePath, relPath));
          }
        } else if (line.startsWith('##')) {
          inFilesSection = false;
        }
      }
      
      if (readFiles.isNotEmpty) {
        state = state.copyWith(
          agentReadFiles: readFiles,
        );
      }
    } catch (e) {
      debugPrint('[AINotifier] Error restoring memory: $e');
    }
  }

  void _updateMessagesAndSync(List<ChatMessage> newMessages) {
    final currentId = state.currentSessionId;
    if (currentId == null) {
      state = state.copyWith(messages: newMessages);
      return;
    }
    
    // Auto-generate title from first user message
    String? customTitle;
    try {
      final firstUserMsg = newMessages.firstWhere(
        (m) => m.role == MessageRole.user,
      );
      if (firstUserMsg.content.isNotEmpty) {
        final session = state.sessions.firstWhere(
          (s) => s.id == currentId,
        );
        if (session.title == 'New Chat' || session.title.isEmpty) {
          customTitle = firstUserMsg.content.length > 30 
              ? '${firstUserMsg.content.substring(0, 30)}...' 
              : firstUserMsg.content;
        }
      }
    } catch (_) {}

    final updatedSessions = state.sessions.map((s) {
      if (s.id == currentId) {
        return s.copyWith(
          messages: newMessages,
          title: customTitle ?? s.title,
        );
      }
      return s;
    }).toList();

    state = state.copyWith(
      messages: newMessages,
      sessions: updatedSessions,
    );
    _saveSessions();
  }

  void startNewSession() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Chat',
      messages: [],
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      sessions: [...state.sessions, newSession],
      currentSessionId: newSession.id,
      messages: [],
    );
    _saveSessions();
  }

  void selectSession(String sessionId) {
    final session = state.sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => state.sessions.first,
    );
    state = state.copyWith(
      currentSessionId: sessionId,
      messages: session.messages,
    );
  }

  void deleteSession(String sessionId) {
    final updatedSessions = state.sessions.where((s) => s.id != sessionId).toList();
    
    if (updatedSessions.isEmpty) {
      final defaultSession = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'New Chat',
        messages: [],
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        sessions: [defaultSession],
        currentSessionId: defaultSession.id,
        messages: [],
      );
    } else {
      String? nextActiveId = state.currentSessionId;
      List<ChatMessage> nextMessages = state.messages;
      if (state.currentSessionId == sessionId) {
        final nextActiveSession = updatedSessions.last;
        nextActiveId = nextActiveSession.id;
        nextMessages = nextActiveSession.messages;
      }
      state = state.copyWith(
        sessions: updatedSessions,
        currentSessionId: nextActiveId,
        messages: nextMessages,
      );
    }
    _saveSessions();
  }

  Future<void> rollbackToMessage(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= state.messages.length) return;
    
    final messagesToRollback = state.messages.sublist(messageIndex + 1);
    
    // Roll back in reverse order
    for (int i = messagesToRollback.length - 1; i >= 0; i--) {
      final msg = messagesToRollback[i];
      if (msg.fileBackups != null) {
        for (final entry in msg.fileBackups!.entries) {
          final filePath = entry.key;
          final originalContent = entry.value;
          try {
            final file = File(filePath);
            if (originalContent == null) {
              if (file.existsSync()) {
                file.deleteSync();
              }
            } else {
              file.parent.createSync(recursive: true);
              file.writeAsStringSync(originalContent);
            }
            
            final isOpen = _ref.read(editorProvider).openFiles.any((f) => f.path == filePath);
            if (isOpen) {
              await _ref.read(editorProvider.notifier).openFile(filePath);
            }
          } catch (e) {
            debugPrint('Failed to rollback file $filePath: $e');
          }
        }
      }
    }
    
    final keptMessages = state.messages.sublist(0, messageIndex + 1);
    _updateMessagesAndSync(keptMessages);
  }

  Future<void> editUserRequest(int messageIndex, String newPrompt) async {
    await rollbackToMessage(messageIndex);
    
    final keptMessages = List<ChatMessage>.from(state.messages);
    if (keptMessages.isNotEmpty && keptMessages.length > messageIndex) {
      keptMessages[messageIndex] = ChatMessage(
        role: MessageRole.user,
        content: newPrompt,
        timestamp: DateTime.now(),
      );
    }
    
    _updateMessagesAndSync(keptMessages);
    
    // Run askAI with the updated prompt
    await askAI(newPrompt);
  }

  AIService get _aiService => _ref.read(aiServiceProvider);

  void toggleAutopilot() {
    if (state.approvalMode == AiApprovalMode.manual) {
      state = state.copyWith(
        approvalMode: AiApprovalMode.semiAutonomous,
        interactionMode: AiInteractionMode.autopilot,
      );
    } else {
      state = state.copyWith(
        approvalMode: AiApprovalMode.manual,
        interactionMode: AiInteractionMode.chat,
      );
    }
  }

  void setApprovalMode(AiApprovalMode mode) {
    state = state.copyWith(
      approvalMode: mode,
      interactionMode: mode == AiApprovalMode.manual 
          ? (state.interactionMode == AiInteractionMode.autopilot ? AiInteractionMode.chat : state.interactionMode)
          : AiInteractionMode.autopilot,
    );
  }

  void setInteractionMode(AiInteractionMode mode) {
    AiApprovalMode approval;
    switch (mode) {
      case AiInteractionMode.chat:
      case AiInteractionMode.refactor:
        approval = AiApprovalMode.manual;
        break;
      case AiInteractionMode.autopilot:
        approval = AiApprovalMode.semiAutonomous;
        break;
    }
    state = state.copyWith(
      interactionMode: mode,
      approvalMode: approval,
    );
  }

  void stopAutopilot() {
    state = state.copyWith(isLoading: false, activeAgentRole: null);
  }

  Future<void> askAI(String prompt, {String? imageBase64}) async {
    final l10n = _ref.read(localizationsProvider);

    if (prompt.trim() == '/dream') {
      await _executeDream();
      return;
    }
    
    if (prompt.trim().startsWith('/goal ')) {
      final goal = prompt.trim().substring(6).trim();
      state = state.copyWith(sessionGoal: goal);
      // We will proceed to pass this goal to the LLM to start Autopilot
    }
    
    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: prompt,
      timestamp: DateTime.now(),
      imageBase64: imageBase64,
    );

    final userTokens = _estimateTokens(prompt);

    final isAutopilot = state.interactionMode == AiInteractionMode.autopilot;

    state = state.copyWith(
      isLoading: true,
      error: null,
      totalTokens: state.totalTokens + userTokens,
      activeAgentRole: isAutopilot ? 'Planner' : null,
      currentStatusMessage: isAutopilot ? l10n.analyzingTaskAndPlanning : null,
    );
    _updateMessagesAndSync([...state.messages, userMessage]);

    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (state.totalTokens > 30000 && state.messages.length > 20) {
      // Run compression asynchronously
      _compressOldMessages(workspacePath);
    }

    int currentStep = 0;
    const maxSteps = 10;
    String nextPrompt = prompt;
    // Anti-loop: track which files had errors and how many consecutive fix attempts
    int consecutiveErrorFixAttempts = 0;
    const maxErrorFixAttempts = 2;
    Set<String> lastErrorFiles = {};

    try {
      // Используем уже считанный workspacePath, не читаем повторно (убрана переменная-тень)
      if (workspacePath == null) {
        throw Exception(l10n.projectNotOpened);
      }

      while (state.isLoading) {
        currentStep++;
        if (currentStep > maxSteps) {
          state = state.copyWith(
            isLoading: false,
            activeAgentRole: null,
          );
          _updateMessagesAndSync([
            ...state.messages,
            ChatMessage(
              role: MessageRole.system,
              content: l10n.agentStepLimitExceeded(maxSteps),
              timestamp: DateTime.now(),
            )
          ]);
          break;
        }

        // Build system prompt dynamically using Prefix Memory context compressor and MCA
        final editorState = _ref.read(editorProvider);
        final openFiles = editorState.openFiles.map((f) => p.relative(f.path, from: workspacePath)).toList();
        final activeFile = editorState.activeFilePath != null 
            ? p.relative(editorState.activeFilePath!, from: workspacePath) 
            : 'None';

        final workspaceDiagnostics = <String, List<CodeDiagnostic>>{};
        editorState.allDiagnostics.forEach((filePath, list) {
          if (workspacePath.isNotEmpty && filePath.startsWith(workspacePath)) {
            workspaceDiagnostics[filePath] = list;
          }
        });

        final compressedContext = await _contextCompressor.getCompressedContext(
          workspaceRoot: workspacePath,
          openFiles: openFiles,
          activeFile: activeFile,
          diagnostics: workspaceDiagnostics,
        );

        final activeComponents = <String>[];
        if (state.activeAgentRole != null) {
          final role = state.activeAgentRole!.toLowerCase();
          if (role == 'planner') {
            activeComponents.add('planning');
          } else if (role == 'coder') {
            activeComponents.add('coding');
          } else if (role == 'validator') {
            activeComponents.add('validation');
          } else {
            activeComponents.add(role);
          }
        }
        if (workspaceDiagnostics.values.any((list) => list.isNotEmpty)) {
          activeComponents.add('linter');
        }
        activeComponents.add('git');

        final mcpService = _ref.read(mcpServiceProvider.notifier);
        final mcpTools = await mcpService.getAvailableMcpTools();
        final internetAccess = mcpService.internetAccess;

        String rulesContent = '';
        final rulesFiles = [
          File(p.join(workspacePath, '.agentrules')),
          File(p.join(workspacePath, '.cursorrules')),
          File(p.join(workspacePath, '.quantum', 'memory.md')),
          File(p.join(workspacePath, '.quantum', 'checkpoint.md')),
          File(p.join(workspacePath, '.quantum', 'tasks.md')),
        ];
        for (final f in rulesFiles) {
          if (await f.exists()) {
            try {
              final content = await f.readAsString();
              rulesContent += '\n\n=== ${p.basename(f.path)} ===\n$content';
            } catch (e) {
              debugPrint('Failed to read rules file ${f.path}: $e');
            }
          }
        }

        final isLocalAi = _aiService.selectedProviderId == 'local_edge';
        
        // ── Load session memory for local model ──────────────────────────────
        // If we have a saved session memory, append it to the system instruction
        // so the model "remembers" what it did before context was reset.
        String sessionMemoryAddendum = '';
        if (isLocalAi) {
          final memory = await _ref.read(localInferenceProvider.notifier)
              .loadSessionMemory(workspacePath);
          if (memory != null) {
            sessionMemoryAddendum = '\n\n## ПАМЯТЬ ПРЕДЫДУЩИХ СЕССИЙ (Предыдущая работа):\n$memory\n\n'
                'Если пользователь напишет "продолжи" — используй эту память чтобы продолжить работу.\n';
          }
          
          // ── Auto-save & reset context before it overflows ─────────────────
          // Check if LiteRT/GGUF context is 80%+ full. If so, save memory and
          // reset NOW — before garbage starts generating.
          final localState = _ref.read(localInferenceProvider);
          final totalCtx = localState.contextTokensTotal;
          final usedCtx = localState.contextTokensUsed;
          if (totalCtx > 0 && usedCtx > 0 && usedCtx >= (totalCtx * 0.80).toInt()) {
            debugPrint('[AINotifier] Context $usedCtx/$totalCtx (80%+) — saving memory and resetting');
            final historyToSave = state.messages
                .map((m) => {
                      'role': m.role == MessageRole.user ? 'user' : 'assistant',
                      'content': m.content,
                    })
                .toList();
            await _ref.read(localInferenceProvider.notifier).resetContext(
              messagesToSave: historyToSave,
              workspacePath: workspacePath,
            );
            _contextCompressor.reset();
            // Notify user
            _updateMessagesAndSync([
              ...state.messages,
              ChatMessage(
                role: MessageRole.system,
                content: '🔄 **Контекст сброшен** (80% заполнен)\n\n'
                    'История сохранена в `.quantum/local_memory.md`.\n'
                    'Модель помнит что делала — просто продолжай!',
                timestamp: DateTime.now(),
              ),
            ]);
          }
        }
        
        String systemInstruction = AIPrompts.getSystemInstruction(
          compressedContext,
          activeComponents: activeComponents,
          mcpTools: mcpTools,
          internetAccess: internetAccess && !isLocalAi,
          rulesContent: rulesContent,
          interactionMode: state.interactionMode,
          isLocalModel: isLocalAi,
        );
        
        // Append session memory to local model instruction
        if (sessionMemoryAddendum.isNotEmpty) {
          systemInstruction = systemInstruction + sessionMemoryAddendum;
        }

        // Prepare conversation history
        final history = state.messages
            .where((m) => m != state.messages.last)
            .map((m) => {
                  'role': m.role == MessageRole.user 
                      ? 'user' 
                      : (m.role == MessageRole.system ? 'user' : 'assistant'),
                  'content': m.content,
                })
            .toList();

        // Get completion from AI service
        String responseText;
        int responseTokens = 0;
        int promptTokens = 0;
        int completionTokens = 0;
        
        final localInferenceState = _ref.read(localInferenceProvider);
        final isLocalModelLoaded = localInferenceState.status == LocalModelStatus.ready && localInferenceState.loadedModel != null;

        if (_aiService.selectedProviderId == 'local_edge' && isLocalModelLoaded) {
           // Native inference on Android/iOS via InferenceEngine
           responseText = await _ref.read(localInferenceProvider.notifier).generate(
             prompt: nextPrompt,
             history: history,
             systemInstruction: systemInstruction,
           );
           responseTokens = _estimateTokens(responseText);
        } else if (_aiService.selectedProviderId == 'local_edge' && !isLocalModelLoaded) {
           // local_edge selected but no model loaded → check if it's desktop
           // On desktop: llama-server might or might not be running
           // Try the HTTP request but catch connection errors gracefully
           try {
             final chatResponse = await _aiService.sendChatMessage(
               nextPrompt,
               history,
               systemInstruction: systemInstruction,
               imageBase64: imageBase64,
             );
             responseText = chatResponse.text;
             promptTokens = chatResponse.tokenUsage?.promptTokens ?? 0;
             completionTokens = chatResponse.tokenUsage?.completionTokens ?? 0;
             responseTokens = chatResponse.tokenUsage?.totalTokens ?? _estimateTokens(responseText);
           } catch (e) {
             final errorStr = e.toString();
             final isConnectionError = errorStr.contains('connection error') ||
                 errorStr.contains('В соединении отказано') ||
                 errorStr.contains('Connection refused') ||
                 errorStr.contains('SocketException') ||
                 errorStr.contains('errno = 111');

             if (isConnectionError) {
               responseText = '⚠️ **Локальный ИИ недоступен**\n\n'
                   'Не удалось подключиться к локальному серверу.\n\n'
                   '**На ПК (Linux/Desktop):**\n'
                   '• Откройте боковую панель **Local Models** → нажмите **Start** чтобы запустить llama-server\n'
                   '• Или выберите другого провайдера в настройках (Gemini, OpenAI и др.)\n\n'
                   '**На телефоне (Android):**\n'
                   '• Скачайте модель в панели Local Models → нажмите **Run** — сервер не нужен, ИИ работает прямо на устройстве\n\n'
                   '_Технически: llama-server не запущен на localhost_';
             } else {
               rethrow;
             }
             responseTokens = 0;
           }
        } else {
           final chatResponse = await _aiService.sendChatMessage(
             nextPrompt,
             history,
             systemInstruction: systemInstruction,
             imageBase64: imageBase64,
           );
           responseText = chatResponse.text;
           promptTokens = chatResponse.tokenUsage?.promptTokens ?? 0;
           completionTokens = chatResponse.tokenUsage?.completionTokens ?? 0;
           responseTokens = chatResponse.tokenUsage?.totalTokens ?? _estimateTokens(responseText);
        }

        // Parse proposed actions from <actions> blocks
        var actions = _parseActions(responseText);
        
        // For local models: translate natural language into actions
        if (isLocalAi && actions.isEmpty) {
          actions = LocalActionTranslator.translateResponse(responseText, workspacePath);
          if (actions.isNotEmpty) {
            // Log that we translated actions from natural language
            debugPrint('[LocalActionTranslator] Translated ${actions.length} action(s) from model response');
          }
        }

        // Intercept and auto-execute web_search / web_fetch actions for live internet access
        final webActions = actions.where((a) => a.type == 'web_search' || a.type == 'web_fetch').toList();
        if (webActions.isNotEmpty) {
          final webAction = webActions.first;
          final statusMsg = webAction.type == 'web_search'
              ? 'Поиск в интернете: "${webAction.content}"...'
              : 'Загрузка страницы: "${webAction.path}"...';
          state = state.copyWith(currentStatusMessage: statusMsg);

          final searchResult = await applyAction(webAction, runInBackground: true);

          // Feed search results back to the model as context and continue loop
          nextPrompt = '$nextPrompt\n\n[Результаты поиска из интернета]\n$searchResult\n\nПожалуйста, сформулируй окончательный ответ пользователю на русском языке на основе этих свежих данных.';
          
          // Clean the actions tags from the response before continuing
          responseText = responseText
              .replaceAll(RegExp(r'<actions>[\s\S]*?(?:</actions>|$)', caseSensitive: false), '')
              .replaceAll(RegExp(r'<action>[\s\S]*?(?:</action>|$)', caseSensitive: false), '');
          
          continue;
        }

        final cleanContent = responseText
            .replaceAll(RegExp(r'<actions>[\s\S]*?(?:</actions>|$)', caseSensitive: false), '')
            .replaceAll(RegExp(r'<action>[\s\S]*?(?:</action>|$)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[\s*\{\s*"type"[\s\S]*(?:\]|$)'), '')
            .trim();

        final assistantMessage = ChatMessage(
          role: MessageRole.assistant,
          content: cleanContent,
          timestamp: DateTime.now(),
          actions: actions.isNotEmpty ? actions : null,
        );

        state = state.copyWith(
          totalTokens: state.totalTokens + responseTokens,
          lastPromptTokens: promptTokens,
          lastCompletionTokens: completionTokens,
        );
        _updateMessagesAndSync([...state.messages, assistantMessage]);

        if (!isAutopilot) {
          final readOnlyActions = actions.where(_isReadOnlyAction).toList();
          final modificationActions = actions.where((a) => !_isReadOnlyAction(a)).toList();

          if (modificationActions.isNotEmpty) {
            // Modification actions (edit/create/delete/command/mcp) require user confirmation in Chat/Refactor modes
            state = state.copyWith(
              proposedActions: [...state.proposedActions, ...modificationActions],
              isLoading: false,
              activeAgentRole: null,
              currentStatusMessage: null,
            );
            break;
          } else if (readOnlyActions.isNotEmpty) {
            // Auto-execute read-only actions to collect context
            final results = <String>[];
            for (final action in readOnlyActions) {
              final res = await applyAction(action, runInBackground: true);
              results.add(res);
            }

            final resultsMap = <String, String>{};
            for (int i = 0; i < readOnlyActions.length; i++) {
              final act = readOnlyActions[i];
              resultsMap[act.path.isNotEmpty ? act.path : act.content] = results[i];
            }

            final resultsText = readOnlyActions
                .asMap()
                .map((idx, act) => MapEntry(idx, '[Результат действия ${act.type} для ${act.path.isNotEmpty ? act.path : act.content}]\n${results[idx]}'))
                .values
                .join('\n\n');

            // Add step summary to messages so it becomes part of the conversation history!
            final actionsListText = readOnlyActions
                .map((a) => '- ${a.type.toUpperCase()}: ${a.path.isNotEmpty ? p.relative(a.path, from: workspacePath) : a.content}')
                .join('\n');
            final feedbackContent = l10n.autopilotStepSummary(1, actionsListText, results.join('\n'));

            _updateMessagesAndSync([
              ...state.messages,
              ChatMessage(
                role: MessageRole.system,
                content: feedbackContent,
                timestamp: DateTime.now(),
                executedActions: readOnlyActions,
                actionResults: resultsMap,
                isStepSummary: true,
              )
            ]);

            nextPrompt = '$nextPrompt\n\n$resultsText\n\nПожалуйста, продолжи выполнение запроса пользователя на основе полученных данных.';
            continue;
          } else {
            // No actions proposed, or all executed. Finish chat turn.
            state = state.copyWith(isLoading: false, activeAgentRole: null, currentStatusMessage: null);
            break;
          }
        }

        // Sub-Agent State Machine processing (Autopilot only)
        if (state.activeAgentRole == 'Judge') {
          if (cleanContent.trim().toUpperCase().startsWith('YES')) {
            state = state.copyWith(isLoading: false, activeAgentRole: null, currentStatusMessage: null, sessionGoal: null);
            _updateMessagesAndSync([
              ...state.messages,
              ChatMessage(role: MessageRole.system, content: 'Goal achieved! The Judge approved the completion.', timestamp: DateTime.now())
            ]);
            break;
          } else {
            state = state.copyWith(
              activeAgentRole: 'Coder',
              currentStatusMessage: 'Goal not met. Resuming work based on Judge feedback...',
            );
            nextPrompt = 'Judge feedback: $cleanContent\n\nPlease implement the missing requirements.';
            continue;
          }
        }

        if (state.activeAgentRole == 'Planner') {
          // Move from Planner to Coder once the plan is made
          state = state.copyWith(
            activeAgentRole: 'Coder',
            currentStatusMessage: l10n.generatingCodeChanges,
          );
          nextPrompt = 'Plan accepted. Please implement the changes according to the proposed plan and output the actions.';
          // Убрана искусственная задержка 500мс — она не нужна, только замедляет агента
          continue;
        }

        if (actions.isEmpty) {
          // If no actions returned in Coder/Validator phases, or task is done
          if (state.activeAgentRole == 'Coder') {
            // Check if we should validate
            state = state.copyWith(
              activeAgentRole: 'Validator',
              currentStatusMessage: l10n.verifyingImplementation,
            );
            nextPrompt = 'Please verify the implementation. Are there any compilation or analyzer errors?';
            continue;
          }
        }

        // We have actions to execute. Evaluate risk and security.
        final allowedActions = <AIAction>[];
        final blockedActions = <AIAction>[];
        final highRiskPendingActions = <AIAction>[];

        for (final action in actions) {
          final risk = _permissionService.evaluateActionRisk(action, workspacePath);
          
          // Check if path scope is violated (risk evaluation detects out of scope as HIGH)
          if ((action.type == 'edit' || action.type == 'create' || action.type == 'delete') &&
              !_permissionService.isPathInScope(action.path, workspacePath)) {
            blockedActions.add(action);
            continue;
          }

          // Evaluate auto-approval eligibility based on Mode and Risk
          if (state.approvalMode == AiApprovalMode.fullAutonomous) {
            allowedActions.add(action);
          } else if (state.approvalMode == AiApprovalMode.semiAutonomous) {
            if (risk == AiRiskLevel.low || risk == AiRiskLevel.medium) {
              allowedActions.add(action);
            } else {
              highRiskPendingActions.add(action);
            }
          } else {
            // Manual approval mode
            highRiskPendingActions.add(action);
          }
        }

        // Handle blocked operations
        if (blockedActions.isNotEmpty) {
          final blockedText = blockedActions.map((a) => '- ${a.type.toUpperCase()}: ${a.path}').join('\n');
          state = state.copyWith(
            isLoading: false,
            activeAgentRole: null,
          );
          _updateMessagesAndSync([
            ...state.messages,
            ChatMessage(
              role: MessageRole.system,
              content: l10n.blockedUnsafeActions(blockedText),
              timestamp: DateTime.now(),
            )
          ]);
          break;
        }

        // Handle manual approval gating
        if (highRiskPendingActions.isNotEmpty) {
          state = state.copyWith(
            proposedActions: [...state.proposedActions, ...highRiskPendingActions, ...allowedActions],
            isLoading: false, // Stop loop to wait for user approval
            activeAgentRole: null,
          );
          _updateMessagesAndSync([
            ...state.messages,
            ChatMessage(
              role: MessageRole.system,
              content: l10n.awaitingApprovalHighRisk,
              timestamp: DateTime.now(),
            )
          ]);
          break;
        }

        // Execute allowed/silent actions
        if (allowedActions.isNotEmpty) {
          final results = <String>[];
          for (final action in allowedActions) {
            final res = await applyAction(action, runInBackground: true);
            results.add(res);
          }

          final resultsMap = <String, String>{};
          for (int i = 0; i < allowedActions.length; i++) {
            final action = allowedActions[i];
            final res = results[i];
            resultsMap[action.path.isNotEmpty ? action.path : action.content] = res;
          }

          final actionsListText = allowedActions
              .map((a) => '- ${a.type.toUpperCase()}: ${a.path.isNotEmpty ? p.relative(a.path, from: workspacePath) : a.content}')
              .join('\n');
          final feedbackContent = l10n.autopilotStepSummary(currentStep, actionsListText, results.join('\n'));

          final taskName = state.messages.isNotEmpty ? state.messages.first.content : 'AI Assistant Task';

          final backupsToSave = Map<String, String?>.from(_currentStepBackups);
          _currentStepBackups.clear();

          _updateMessagesAndSync([
            ...state.messages,
            ChatMessage(
              role: MessageRole.system,
              content: feedbackContent,
              timestamp: DateTime.now(),
              taskName: taskName,
              stepNumber: currentStep,
              totalSteps: maxSteps,
              executedActions: allowedActions,
              actionResults: resultsMap,
              isStepSummary: true,
              fileBackups: backupsToSave,
            )
          ]);

          // Transition to Validator to verify the compile state
          state = state.copyWith(
            activeAgentRole: 'Validator',
            currentStatusMessage: l10n.runningStaticAnalysis,
          );
          
          // Trigger compiler analysis first and await it
          await _ref.read(analysisServiceProvider).runAnalysis();
          // Убрана задержка 800мс — анализ уже завершён через await runAnalysis()

          // Re-fetch errors in Validator phase to see if there are issues
          final allDiagnostics = _ref.read(editorProvider).allDiagnostics;
          final currentDiagnostics = <String, List<CodeDiagnostic>>{};
          allDiagnostics.forEach((filePath, list) {
            if (workspacePath.isNotEmpty && filePath.startsWith(workspacePath)) {
              currentDiagnostics[filePath] = list;
            }
          });
          final hasErrors = currentDiagnostics.values.any(
            (list) => list.any((d) => d.severity == CodeDiagnosticSeverity.error)
          );
          
          if (hasErrors) {
            // Collect exact error messages with file+line info
            final errorReport = _formatDiagnosticsForPrompt(currentDiagnostics, workspacePath);
            final errorFiles = currentDiagnostics.entries
                .where((e) => e.value.any((d) => d.severity == CodeDiagnosticSeverity.error))
                .map((e) => e.key)
                .toSet();

            // Anti-loop: check if same files are failing again
            if (lastErrorFiles.isNotEmpty && errorFiles.containsAll(lastErrorFiles)) {
              consecutiveErrorFixAttempts++;
            } else {
              consecutiveErrorFixAttempts = 1;
              lastErrorFiles = errorFiles;
            }

            if (consecutiveErrorFixAttempts > maxErrorFixAttempts) {
              // Stuck in a loop — stop and report to user
              state = state.copyWith(
                isLoading: false,
                activeAgentRole: null,
                currentStatusMessage: null,
              );
              _updateMessagesAndSync([
                ...state.messages,
                ChatMessage(
                  role: MessageRole.system,
                  content: l10n.agentFailedToFixErrors(maxErrorFixAttempts, errorReport),
                  timestamp: DateTime.now(),
                )
              ]);
              break;
            }

            state = state.copyWith(
              activeAgentRole: 'Coder',
              currentStatusMessage: l10n.fixingCompilationErrors,
            );
            nextPrompt = 'Validation found compilation errors (attempt $consecutiveErrorFixAttempts/$maxErrorFixAttempts).\n\n**Exact analyzer errors:**\n$errorReport\n\nFor each error:\n1. Read the file via read_file if you need context\n2. Fix only the lines with errors, avoid rewriting entire file unnecessarily';
          } else {
            consecutiveErrorFixAttempts = 0;
            lastErrorFiles = {};
            state = state.copyWith(currentStatusMessage: null);
            nextPrompt = 'All changes applied successfully. No compilation errors. Verify logic correctness or report completion.';
          }
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString(), activeAgentRole: null, currentStatusMessage: null);
    }
  }

  List<AIAction> _parseActions(String text) {
    final List<AIAction> actions = [];
    final workspacePath = _ref.read(workspaceProvider).currentPath;

    final regExp = RegExp(r'<actions>([\s\S]*?)<\/actions>', caseSensitive: false);
    var matches = regExp.allMatches(text);

    if (matches.isEmpty) {
      final singularRegExp = RegExp(r'<action>([\s\S]*?)<\/action>', caseSensitive: false);
      matches = singularRegExp.allMatches(text);
    }

    final List<String> candidateBlocks = [];
    for (final match in matches) {
      candidateBlocks.add(match.group(1)?.trim() ?? '');
    }

    if (candidateBlocks.isEmpty) {
      final jsonArrayRegExp = RegExp(r'\[\s*\{\s*"type"[\s\S]*?\}\s*\]');
      final arrayMatch = jsonArrayRegExp.firstMatch(text);
      if (arrayMatch != null) {
        candidateBlocks.add(arrayMatch.group(0)!);
      }
    }

    for (var jsonStr in candidateBlocks) {
      try {
        if (jsonStr.contains('```')) {
          final codeBlockRegExp = RegExp(r'```(?:json)?([\s\S]*?)```', caseSensitive: false);
          final codeBlockMatch = codeBlockRegExp.firstMatch(jsonStr);
          if (codeBlockMatch != null) {
            jsonStr = codeBlockMatch.group(1)?.trim() ?? jsonStr;
          } else {
            jsonStr = jsonStr
                .split('\n')
                .where((line) => !line.trim().startsWith('```'))
                .join('\n')
                .trim();
          }
        }

        final decoded = jsonDecode(jsonStr);
        final List<dynamic> jsonList;
        if (decoded is List) {
          jsonList = decoded;
        } else if (decoded is Map) {
          jsonList = [decoded];
        } else {
          jsonList = [];
        }
        for (final item in jsonList) {
          final actionJson = Map<String, dynamic>.from(item);
          final rawPath = actionJson['path'] as String?;
          if (rawPath != null && rawPath.isNotEmpty && workspacePath != null) {
            if (!p.isAbsolute(rawPath)) {
              actionJson['path'] = p.join(workspacePath, rawPath);
            }
          }
          final action = AIAction.fromJson(actionJson);
          if (action.type == 'edit') {
            try {
              final file = File(action.path);
              if (file.existsSync()) {
                final original = file.readAsStringSync();
                final dmp = DiffMatchPatch();
                final diffs = dmp.diff(original, action.content);
                dmp.diffCleanupSemantic(diffs);
                int additions = 0;
                int deletions = 0;
                for (final d in diffs) {
                  final lineCount = '\n'.allMatches(d.text).length + (d.text.isNotEmpty ? 1 : 0);
                  if (d.operation == DIFF_INSERT) {
                    additions += lineCount;
                  } else if (d.operation == DIFF_DELETE) {
                    deletions += lineCount;
                  }
                }
                action.additions = additions;
                action.deletions = deletions;
              }
            } catch (_) {}
          } else if (action.type == 'create') {
            final lineCount = '\n'.allMatches(action.content).length + (action.content.isNotEmpty ? 1 : 0);
            action.additions = lineCount;
            action.deletions = 0;
          }
          actions.add(action);
        }
      } catch (e) {
        debugPrint('Error parsing AI actions: $e');
      }
    }
    return actions;
  }

  int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 4).ceil() + (text.split(' ').length);
  }

  void clear() {
    _contextCompressor.reset();
    state = AIState();
  }

  /// Форматирует диагностику LSP в читаемый список ошибок для промпта
  String _formatDiagnosticsForPrompt(
    Map<String, List<CodeDiagnostic>> diagnostics,
    String? workspacePath,
  ) {
    final lines = <String>[];
    for (final entry in diagnostics.entries) {
      final errors = entry.value.where(
        (d) => d.severity == CodeDiagnosticSeverity.error,
      );
      if (errors.isEmpty) continue;
      final relPath = workspacePath != null && entry.key.startsWith(workspacePath)
          ? p.relative(entry.key, from: workspacePath)
          : entry.key;
      for (final diag in errors) {
        final line = (diag.range.index + 1).toString();
        final col = (diag.range.start + 1).toString();
        lines.add('$relPath:$line:$col  ERROR  ${diag.message}');
      }
    }
    return lines.isEmpty ? '(no errors)' : lines.join('\n');
  }

  Future<String> applyAction(AIAction action, {bool runInBackground = true}) async {
    final l10n = _ref.read(localizationsProvider);
    final workspacePath = _ref.read(workspaceProvider).currentPath;

    final relPath = workspacePath != null && action.path.startsWith(workspacePath)
        ? p.relative(action.path, from: workspacePath)
        : action.path;

    final actionEmoji = _getActionEmoji(action.type);
    final actionLabel = _getActionLabel(action.type);
    
    final actionStepMessage = ChatMessage(
      role: MessageRole.system,
      content: '$actionEmoji $actionLabel `${relPath.isNotEmpty ? relPath : action.content}`',
      timestamp: DateTime.now(),
      isActionStep: true,
      actionStepType: action.type,
      actionStepPath: relPath.isNotEmpty ? relPath : action.content,
    );
    _updateMessagesAndSync([...state.messages, actionStepMessage]);

    if (state.isLoading) {
      String statusMsg;
      switch (action.type) {
        case 'read_file':
          statusMsg = l10n.readingFile(relPath);
          break;
        case 'edit':
        case 'create':
          statusMsg = l10n.savingFile(relPath);
          break;
        case 'delete':
          statusMsg = l10n.deletingFile(relPath);
          break;
        case 'command':
          statusMsg = l10n.runningCommandStatus(action.content);
          break;
        case 'grep_search':
          statusMsg = l10n.searchingCode(action.content);
          break;
        case 'list_dir':
          statusMsg = l10n.listingDirectory(relPath);
          break;
        case 'find_symbols':
          statusMsg = l10n.findingSymbols(action.content);
          break;
        case 'web_search':
          statusMsg = l10n.searchingWeb(action.content);
          break;
        case 'web_fetch':
          statusMsg = l10n.fetchingWebPage(action.path);
          break;
        case 'mcp':
          statusMsg = 'MCP Server ${action.server} -> ${action.tool}...';
          break;
        default:
          statusMsg = l10n.executingAction;
      }
      state = state.copyWith(currentStatusMessage: statusMsg);
    }
    
    // Safety guard
    if (workspacePath != null && 
        (action.type == 'edit' || action.type == 'create' || action.type == 'delete') &&
        !_permissionService.isPathInScope(action.path, workspacePath)) {
      return l10n.safetyGuardFileOutsideWorkspace;
    }

    try {
      switch (action.type) {
        case 'read_file':
          // Агент запрашивает содержимое файла перед правкой
          final targetFile = File(action.path);
          if (!await targetFile.exists()) {
            return l10n.fileNotFound(action.path);
          }
          final content = await targetFile.readAsString();
          // Отмечаем что агент прочитал файл (для проводника)
          final relPath = workspacePath != null && action.path.startsWith(workspacePath)
              ? p.relative(action.path, from: workspacePath)
              : action.path;
          if (!state.agentReadFiles.contains(action.path)) {
            state = state.copyWith(
              agentReadFiles: [...state.agentReadFiles, action.path],
            );
          }
          final lineCount = '\n'.allMatches(content).length + 1;
          final truncatedSuffix = content.length > 8000
              ? '\n\n${l10n.fileTruncatedSuffix(lineCount)}'
              : '';
          final truncated = content.length > 8000
              ? '${content.substring(0, 8000)}$truncatedSuffix'
              : content;
          return l10n.fileContentsHeader(relPath, lineCount, truncated);
        case 'edit':
        case 'create':
          final file = File(action.path);
          String originalContent = '';
          if (await file.exists()) {
            originalContent = await file.readAsString();
            if (!_currentStepBackups.containsKey(action.path)) {
              _currentStepBackups[action.path] = originalContent;
            }
          } else {
            if (!_currentStepBackups.containsKey(action.path)) {
              _currentStepBackups[action.path] = null;
            }
          }
          // Ensure parent dir exists
          await file.parent.create(recursive: true);
          // Write new content to disk
          await file.writeAsString(action.content);
          // Open in editor with diff view, passing original content for proper diff
          await _ref.read(editorProvider.notifier).openFile(
            action.path,
            isDiffView: true,
            overrideOriginalContent: originalContent,
          );
          _refreshFileExplorer(action.path);
          removeAction(action);
          return l10n.fileSuccessfullyWritten(action.path);
        case 'delete':
          final file = File(action.path);
          if (await file.exists()) {
            if (!_currentStepBackups.containsKey(action.path)) {
              _currentStepBackups[action.path] = await file.readAsString();
            }
            await file.delete(recursive: true);
          }
          _refreshFileExplorer(action.path);
          removeAction(action);
          return l10n.fileSuccessfullyDeleted(action.path);
        case 'command':
          final cmdText = action.content.trim().toLowerCase();
          
          // Skip empty commands
          if (cmdText.isEmpty) {
            removeAction(action);
            return 'Skipped empty command';
          }
          
          // Double safety check
          final paths = _permissionService.extractPathCandidates(action.content);
          for (final path in paths) {
            final absPath = p.isAbsolute(path) ? path : p.join(workspacePath ?? '', path);
            if (workspacePath != null && !_permissionService.isPathInScope(absPath, workspacePath)) {
              return l10n.commandRefPathOutsideWorkspace;
            }
          }

          const blacklist = [
            'rm -rf /',
            'rm -rf ~',
            'rm -rf /home',
            'rm -rf /usr',
            'rm -rf /etc',
            'rm -rf /var',
            'rm -rf /boot',
            'dd ',
            'mkfs',
            'shutdown',
            'reboot',
            'chmod -r 777 /',
          ];
          bool isBlocked = false;
          String blockedReason = '';
          for (final pattern in blacklist) {
            if (cmdText.contains(pattern)) {
              isBlocked = true;
              blockedReason = pattern;
              break;
            }
          }
          if (isBlocked) {
            removeAction(action);
            return l10n.commandBlockedUnsafe(blockedReason);
          }

          if (runInBackground) {
            final runtime = _ref.read(runtimeServiceProvider);
            final result = await runtime.runCommand(action.content, workingDirectory: workspacePath);
            removeAction(action);
            return l10n.commandExecutedResult(action.content, result);
          } else {
            await _ref.read(terminalTabsProvider.notifier).sendCommand(action.content);
            _ref.read(panelProvider.notifier).selectTab(PanelTab.terminal);
            removeAction(action);
            return l10n.commandSentToTerminal(action.content);
          }
        case 'grep_search':
          final query = action.content.trim();
          if (query.isEmpty) {
            return l10n.searchQueryEmpty;
          }
          if (workspacePath == null) {
            return l10n.workspaceNotFound;
          }
          // Запускаем в отдельном Isolate — не замораживаем UI!
          final results = await compute(
            _grepSearchIsolate,
            [workspacePath, query],
          );
          removeAction(action);
          if (results.isEmpty) {
            return l10n.aiSearchNoMatches(query);
          }
          return l10n.aiSearchMatchesFound(results.length, query, results.join('\n'));
        case 'find_symbols':
          final query = action.content.trim();
          if (workspacePath == null) {
            return l10n.failedToApplyActionWithError('Workspace not found');
          }
          final symbols = _ref.read(symbolIndexerProvider.notifier).searchSymbols(query);
          removeAction(action);
          if (symbols.isEmpty) {
            return l10n.searchSymbolsNoMatches(query);
          }
          final List<String> symbolLines = [];
          for (final symbol in symbols) {
            final symbolRelPath = p.relative(symbol.filePath, from: workspacePath);
            symbolLines.add(l10n.searchSymbolsItem(
              symbol.type.toUpperCase(),
              symbol.name,
              symbolRelPath,
              symbol.lineNumber,
            ));
          }
          return l10n.searchSymbolsMatchesFound(symbols.length, query, symbolLines.join('\n'));
        case 'list_dir':
          final targetPath = action.path.isEmpty 
              ? (workspacePath ?? '') 
              : (p.isAbsolute(action.path) ? action.path : p.join(workspacePath ?? '', action.path));
          final directory = Directory(targetPath);
          if (!directory.existsSync()) {
            return l10n.directoryNotFound(targetPath);
          }
          final items = <String>[];
          try {
            await for (final item in directory.list(recursive: false)) {
              final name = workspacePath != null 
                  ? p.relative(item.path, from: workspacePath) 
                  : item.path;
              final type = item is Directory ? '[DIR]' : '[FILE]';
              items.add('$type $name');
            }
          } catch (e) {
            return l10n.failedToApplyActionWithError('reading directory: $e');
          }
          removeAction(action);
          if (items.isEmpty) {
            return l10n.directoryEmpty;
          }
          return l10n.directoryContentsHeader(items.join('\n'));
        case 'web_search':
          final searchResult = await _performWebSearch(action.content);
          removeAction(action);
          return searchResult;
        case 'web_fetch':
          final fetchResult = await _performWebFetch(action.path);
          removeAction(action);
          return fetchResult;
        case 'mcp':
          if (action.server == null || action.tool == null) {
            return l10n.mcpMissingParams;
          }
          final mcpService = _ref.read(mcpServiceProvider.notifier);
          final mcpResult = await mcpService.executeMcpTool(action.server!, action.tool!, action.arguments ?? {});
          removeAction(action);
          return jsonEncode(mcpResult);
        default:
          return l10n.unknownAction(action.type);
      }
    } catch (e) {
      final errMsg = l10n.failedToApplyActionWithError(e.toString());
      state = state.copyWith(error: errMsg);
      return errMsg;
    }
  }

  Future<void> executeActionManually(AIAction action) async {
    removeAction(action);
    final l10n = _ref.read(localizationsProvider);
    final workspacePath = _ref.read(workspaceProvider).currentPath ?? '';
    final relPath = workspacePath.isNotEmpty && action.path.startsWith(workspacePath)
        ? p.relative(action.path, from: workspacePath)
        : action.path;
        
    final actionDesc = action.type == 'command'
        ? l10n.runningCommandLabel(action.content)
        : action.type == 'mcp'
            ? 'MCP Server ${action.server}: ${action.tool}'
            : l10n.applyingChangeLabel(relPath);

    _currentStepBackups.clear();
    final result = await applyAction(action, runInBackground: true);
    final backupsToSave = Map<String, String?>.from(_currentStepBackups);
    _currentStepBackups.clear();

    _updateMessagesAndSync([
      ...state.messages,
      ChatMessage(
        role: MessageRole.system,
        content: result,
        timestamp: DateTime.now(),
        taskName: actionDesc,
        executedActions: [action],
        actionResults: { action.path.isNotEmpty ? action.path : action.content : result },
        isStepSummary: true,
        fileBackups: backupsToSave,
      ),
    ]);

    if (action.type == 'command') {
      final analysisPrompt = 'Result of running command "${action.content}":\n$result\n\nAnalyze the result. If errors occurred, fix them.';
      await askAI(analysisPrompt);
    }
  }

  Future<void> executeActionsManually(List<AIAction> actions) async {
    final actionsCopy = List<AIAction>.from(actions);
    String commandResult = '';
    String lastCommand = '';
    final l10n = _ref.read(localizationsProvider);
    final workspacePath = _ref.read(workspaceProvider).currentPath ?? '';
    
    final resultsMap = <String, String>{};
    final executedActions = <AIAction>[];
    final allBackups = <String, String?>{};
    
    for (final action in actionsCopy) {
      removeAction(action);
      _currentStepBackups.clear();
      final result = await applyAction(action, runInBackground: true);
      allBackups.addAll(_currentStepBackups);
      
      resultsMap[action.path.isNotEmpty ? action.path : action.content] = result;
      executedActions.add(action);

      if (action.type == 'command') {
        commandResult = result;
        lastCommand = action.content;
      }
    }
    _currentStepBackups.clear();

    final actionsListText = executedActions
        .map((a) {
          if (a.type == 'mcp') return '- MCP: ${a.server} -> ${a.tool}';
          return '- ${a.type.toUpperCase()}: ${a.path.isNotEmpty ? p.relative(a.path, from: workspacePath) : a.content}';
        })
        .join('\n');
    final feedbackContent = l10n.autopilotStepSummary(1, actionsListText, resultsMap.values.join('\n'));

    _updateMessagesAndSync([
      ...state.messages,
      ChatMessage(
        role: MessageRole.system,
        content: feedbackContent,
        timestamp: DateTime.now(),
        taskName: 'Manual Action Batch',
        executedActions: executedActions,
        actionResults: resultsMap,
        isStepSummary: true,
        fileBackups: allBackups,
      ),
    ]);

    if (commandResult.isNotEmpty && lastCommand.isNotEmpty) {
      final analysisPrompt = 'Result of running command "$lastCommand":\n$commandResult\n\nAnalyze the result. If errors occurred, fix them.';
      await askAI(analysisPrompt);
    }
  }

  Future<String> _getAppDataDir() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final quantumDir = Directory(p.join(dir.path, '.quantum_ide'));
      if (!quantumDir.existsSync()) {
        await quantumDir.create(recursive: true);
      }
      return quantumDir.path;
    } catch (e) {
      debugPrint('[AINotifier] Fallback dir error: $e');
      final tmp = p.join(Directory.systemTemp.path, 'quantum_ide');
      await Directory(tmp).create(recursive: true);
      return tmp;
    }
  }

  void _refreshFileExplorer(String filePath) {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    
    final parentDir = p.dirname(filePath);
    if (parentDir == workspacePath || parentDir.startsWith(workspacePath)) {
      _ref.read(fileExplorerProvider.notifier).scanDirectory(parentDir);
    }
    
    if (filePath.startsWith(workspacePath)) {
      _ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
    }
  }

  Future<void> _compressOldMessages(String? workspacePath) async {
    if (workspacePath == null) return;
    
    // We leave the last 10 messages. The rest are compressed.
    if (state.messages.length <= 10) return;

    final messagesToCompress = state.messages.sublist(0, state.messages.length - 10);
    final history = messagesToCompress
        .map((m) => '${m.role == MessageRole.user ? "User" : "Agent"}: ${m.content}')
        .join('\n\n');

    try {
      final prompt = '''
The following is an older part of our conversation history. Please summarize it concisely, keeping any important technical context, decisions, and tasks.

HISTORY:
$history
''';
      final summary = (await _aiService.sendChatMessage(prompt, [])).text;

      final checkpointFile = File(p.join(workspacePath, '.quantum', 'checkpoint.md'));
      if (!await checkpointFile.parent.exists()) {
        await checkpointFile.parent.create(recursive: true);
      }
      
      String existing = '';
      if (await checkpointFile.exists()) {
        existing = '${await checkpointFile.readAsString()}\n\n';
      }
      await checkpointFile.writeAsString('$existing## Checkpoint - \${DateTime.now().toIso8601String()}\n$summary');

      // Remove compressed messages from state
      final remainingMessages = state.messages.sublist(state.messages.length - 10);
      state = state.copyWith(
        messages: remainingMessages,
        totalTokens: state.totalTokens ~/ 2, // rough estimation
      );
    } catch (e) {
      debugPrint('Context compression failed: \$e');
    }
  }

  Future<void> _executeDream() async {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    state = state.copyWith(
      isLoading: true,
      currentStatusMessage: 'Dreaming: Extracting knowledge to memory...',
    );

    _updateMessagesAndSync([
      ...state.messages,
      ChatMessage(
        role: MessageRole.user,
        content: '/dream',
        timestamp: DateTime.now(),
      )
    ]);

    try {
      final history = state.messages
          .map((m) => '${m.role == MessageRole.user ? "User" : "Agent"}: ${m.content}')
          .join('\n\n');

      final prompt = '''
Review the recent session history below and extract all important architectural decisions, new rules, project structures, or general project knowledge that should be remembered for future sessions.
Format this as a concise Markdown document. Do not include introductory text.

HISTORY:
$history
''';

      final responseText = (await _aiService.sendChatMessage(prompt, [])).text;
      
      final memoryFile = File(p.join(workspacePath, '.quantum', 'memory.md'));
      if (!await memoryFile.parent.exists()) {
        await memoryFile.parent.create(recursive: true);
      }
      
      String existingMemory = '';
      if (await memoryFile.exists()) {
        existingMemory = '${await memoryFile.readAsString()}\n\n';
      }
      
      await memoryFile.writeAsString('$existingMemory## Dream Entry - ${DateTime.now().toIso8601String()}\n$responseText');

      _updateMessagesAndSync([
        ...state.messages,
        ChatMessage(
          role: MessageRole.system,
          content: 'Dream complete! Knowledge distilled and saved to `.quantum/memory.md`.',
          timestamp: DateTime.now(),
        )
      ]);
    } catch (e) {
      _updateMessagesAndSync([
        ...state.messages,
        ChatMessage(
          role: MessageRole.system,
          content: 'Dream failed: $e',
          timestamp: DateTime.now(),
        )
      ]);
    } finally {
      state = state.copyWith(isLoading: false, currentStatusMessage: null);
    }
  }

  void removeAction(AIAction action) {
    state = state.copyWith(
      proposedActions: state.proposedActions.where((a) => a != action).toList(),
    );
    try {
      _ref.read(editorProvider.notifier).setDiffView(action.path, false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  Future<String> _performWebSearch(String query) async {
    // Try lite.duckduckgo.com first (simpler, less anti-bot)
    try {
      final response = await _dio.get(
        'https://lite.duckduckgo.com/lite/?q=${Uri.encodeComponent(query)}',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final html = response.data.toString();
      final results = <String>[];
      
      // lite.duckduckgo.com uses <a rel="nofollow" href="..."> for results
      final linkMatches = RegExp(r'<a[^>]*rel="nofollow"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false).allMatches(html);
      final snippetMatches = RegExp(r'<td class="result-snippet">([\s\S]*?)<\/td>', caseSensitive: false).allMatches(html);
      
      final links = linkMatches.map((m) => m.group(1)?.trim() ?? '').toList();
      final titles = linkMatches.map((m) => m.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      final snippets = snippetMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      
      for (int i = 0; i < titles.length && i < 8; i++) {
        final snippet = i < snippets.length ? snippets[i] : '';
        results.add('[${i+1}] ${titles[i]}\nURL: ${links[i]}\nSnippet: $snippet\n');
      }

      if (results.isEmpty) {
        // Fallback: try classic DuckDuckGo HTML
        final classicResult = await _performWebSearchClassic(query);
        if (classicResult.startsWith('No search results') || classicResult.startsWith('Web search failed')) {
          return await _performWebSearchGoogle(query);
        }
        return classicResult;
      }
      return results.join('\n');
    } catch (e) {
      // Fallback to classic, then to Google
      try {
        final classicResult = await _performWebSearchClassic(query);
        if (classicResult.startsWith('No search results') || classicResult.startsWith('Web search failed')) {
          return await _performWebSearchGoogle(query);
        }
        return classicResult;
      } catch (_) {
        return await _performWebSearchGoogle(query);
      }
    }
  }

  Future<String> _performWebSearchClassic(String query) async {
    try {
      final response = await _dio.get(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final html = response.data.toString();
      final results = <String>[];
      
      final titleMatches = RegExp(r'<a class="result__a"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false).allMatches(html);
      final snippetMatches = RegExp(r'<a class="result__snippet"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false).allMatches(html);
      final urlMatches = RegExp(r'<a class="result__url"[^>]*>([\s\S]*?)<\/a>', caseSensitive: false).allMatches(html);
      
      final titles = titleMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      final snippets = snippetMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      final urls = urlMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      
      for (int i = 0; i < titles.length && i < 8; i++) {
        final url = i < urls.length ? urls[i] : '';
        final snippet = i < snippets.length ? snippets[i] : '';
        results.add('[${i+1}] ${titles[i]}\nURL: $url\nSnippet: $snippet\n');
      }

      if (results.isEmpty) {
        return 'No search results found.';
      }
      return results.join('\n');
    } catch (e) {
      return 'Web search failed: $e';
    }
  }

  Future<String> _performWebSearchGoogle(String query) async {
    try {
      final response = await _dio.get(
        'https://www.google.com/search?q=${Uri.encodeComponent(query)}',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final html = response.data.toString();
      final results = <String>[];

      // Google search mobile links: <a href="/url?q=URL..."
      final matches = RegExp(r'<a href="/url\?q=([^&"]*)[^"]*">([\s\S]*?)<\/a>', caseSensitive: false).allMatches(html);
      int index = 1;
      for (final match in matches) {
        final rawUrl = match.group(1) ?? '';
        final titleHtml = match.group(2) ?? '';
        
        // Skip helper/system links
        if (rawUrl.startsWith('https://support.google.com') ||
            rawUrl.startsWith('https://accounts.google.com') ||
            rawUrl.startsWith('https://maps.google.com')) {
          continue;
        }

        final decodedUrl = Uri.decodeComponent(rawUrl);
        final title = titleHtml.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        
        if (title.isNotEmpty && decodedUrl.startsWith('http')) {
          results.add('[$index] $title\nURL: $decodedUrl\n');
          index++;
          if (index > 8) break;
        }
      }

      if (results.isEmpty) {
        return 'No search results found on Google.';
      }
      return results.join('\n');
    } catch (e) {
      return 'Google Search failed: $e';
    }
  }

  String _getActionEmoji(String type) {
    switch (type) {
      case 'read_file': return '📖';
      case 'list_dir': return '📂';
      case 'grep_search': return '🔍';
      case 'find_symbols': return '🔎';
      case 'create': return '✨';
      case 'edit': return '✏️';
      case 'delete': return '🗑️';
      case 'command': return '💻';
      case 'web_search': return '🌐';
      case 'web_fetch': return '📥';
      case 'mcp': return '🔧';
      default: return '⚙️';
    }
  }

  String _getActionLabel(String type) {
    final l10n = _ref.read(localizationsProvider);
    switch (type) {
      case 'read_file': return l10n.actionReadingFile;
      case 'list_dir': return l10n.actionViewingFolder;
      case 'grep_search': return l10n.actionSearchingCode;
      case 'find_symbols': return l10n.actionFindingSymbol;
      case 'create': return l10n.actionCreatingFile;
      case 'edit': return l10n.actionEditingFile;
      case 'delete': return l10n.actionDeletingFile;
      case 'command': return l10n.actionRunningCommand;
      case 'web_search': return l10n.actionWebSearch;
      case 'web_fetch': return l10n.actionFetchingPage;
      case 'mcp': return l10n.actionMcpTool;
      default: return l10n.actionExecuting;
    }
  }

  String _getActionFriendlyLogText(AIAction action, String workspacePath) {
    final relPath = action.path.isNotEmpty && workspacePath.isNotEmpty
        ? (action.path.startsWith(workspacePath) ? p.relative(action.path, from: workspacePath) : action.path)
        : action.path;

    switch (action.type) {
      case 'read_file':
        return '📁 **Чтение файла:** `$relPath`';
      case 'list_dir':
        return '📂 **Просмотр папки:** `$relPath`';
      case 'grep_search':
        return '🔍 **Поиск по тексту ("${action.content}") в:** `$relPath`';
      case 'find_symbols':
        return '🔎 **Поиск символа "${action.content}"**';
      case 'create':
        return '✨ **Создание нового файла:** `$relPath`';
      case 'edit':
        return '✏️ **Редактирование файла:** `$relPath`';
      case 'delete':
        return '🗑️ **Удаление файла:** `$relPath`';
      case 'command':
        return '💻 **Выполнение команды:** `${action.content}`';
      case 'web_search':
        return '🌐 **Поиск в интернете:** *"${action.content}"*';
      case 'web_fetch':
        return '📥 **Загрузка веб-страницы:** *"${action.path}"*';
      default:
        return '⚙️ **Выполнение действия (${action.type}):** `$relPath`';
    }
  }

  bool _isReadOnlyAction(AIAction action) {
    return action.type == 'read_file' ||
        action.type == 'list_dir' ||
        action.type == 'grep_search' ||
        action.type == 'find_symbols' ||
        action.type == 'web_search' ||
        action.type == 'web_fetch';
  }

  Future<String> _performWebFetch(String url) async {
    try {
      final resp = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
      );
      final html = resp.data.toString();
      String text = html.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?<\/style>'), '');
      text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?<\/script>'), '');
      text = text.replaceAll(RegExp(r'<[^>]*>'), '');
      text = text.replaceAll('&nbsp;', ' ')
                 .replaceAll('&lt;', '<')
                 .replaceAll('&gt;', '>')
                 .replaceAll('&amp;', '&')
                 .replaceAll('&quot;', '"');
      text = text.replaceAll(RegExp(r'\n\s*\n+'), '\n\n').trim();
      
      if (text.length > 5000) {
        text = '${text.substring(0, 5000)}...\n[Content truncated to 5000 chars]';
      }
      return text;
    } catch (e) {
      return 'Web fetch failed: $e';
    }
  }
}

final aiProvider = StateNotifierProvider<AINotifier, AIState>((ref) {
  return AINotifier(ref);
});
