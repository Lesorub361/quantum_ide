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
import 'ai_prompts.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:dio/dio.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:diff_match_patch/diff_match_patch.dart';


enum AiApprovalMode { manual, semiAutonomous, fullAutonomous }

class AIState {
  final bool isLoading;
  final List<ChatMessage> messages;
  final String? error;
  final int totalTokens;
  final List<AIAction> proposedActions;
  final AiApprovalMode approvalMode;
  final String? activeAgentRole; // 'Planner', 'Coder', 'Validator', or null
  /// Пути файлов, которые агент прочитал (для отображения в проводнике)
  final List<String> agentReadFiles;
  final String? currentStatusMessage;
  final List<ChatSession> sessions;
  final String? currentSessionId;

  AIState({
    this.isLoading = false,
    this.messages = const [],
    this.error,
    this.totalTokens = 0,
    this.proposedActions = const [],
    this.approvalMode = AiApprovalMode.semiAutonomous,
    this.activeAgentRole,
    this.agentReadFiles = const [],
    this.currentStatusMessage,
    this.sessions = const [],
    this.currentSessionId,
  });

  bool get isAutopilot => approvalMode != AiApprovalMode.manual;

  AIState copyWith({
    bool? isLoading,
    List<ChatMessage>? messages,
    String? error,
    int? totalTokens,
    List<AIAction>? proposedActions,
    AiApprovalMode? approvalMode,
    String? activeAgentRole,
    bool? isAutopilot,
    List<String>? agentReadFiles,
    String? currentStatusMessage,
    List<ChatSession>? sessions,
    String? currentSessionId,
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
      activeAgentRole: activeAgentRole ?? this.activeAgentRole,
      agentReadFiles: agentReadFiles ?? this.agentReadFiles,
      currentStatusMessage: currentStatusMessage ?? this.currentStatusMessage,
      sessions: sessions ?? this.sessions,
      currentSessionId: currentSessionId ?? this.currentSessionId,
    );
  }
}

class AINotifier extends StateNotifier<AIState> {
  final Ref _ref;
  final Map<String, String?> _currentStepBackups = {};
  final AiContextCompressor _contextCompressor = AiContextCompressor();
  final AiPermissionService _permissionService = const AiPermissionService();

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
    if (workspacePath == null) return;
    try {
      final dir = Directory(p.join(workspacePath, '.quantum'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file = File(p.join(dir.path, 'chat_history.json'));
      final jsonList = state.sessions.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving chat sessions: $e');
    }
  }

  Future<void> _loadSessions(String workspacePath) async {
    try {
      final file = File(p.join(workspacePath, '.quantum', 'chat_history.json'));
      if (!file.existsSync()) {
        // Start a fresh default session
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
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final sessions = jsonList.map((j) => ChatSession.fromJson(j)).toList();
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
      state = state.copyWith(
        sessions: sessions,
        currentSessionId: lastSession.id,
        messages: lastSession.messages,
      );
    } catch (e) {
      debugPrint('Error loading chat sessions: $e');
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
      state = state.copyWith(approvalMode: AiApprovalMode.semiAutonomous);
    } else {
      state = state.copyWith(approvalMode: AiApprovalMode.manual);
    }
  }

  void setApprovalMode(AiApprovalMode mode) {
    state = state.copyWith(approvalMode: mode);
  }

  void stopAutopilot() {
    state = state.copyWith(isLoading: false, activeAgentRole: null);
  }

  Future<void> askAI(String prompt) async {
    final l10n = _ref.read(localizationsProvider);
    
    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: prompt,
      timestamp: DateTime.now(),
    );

    final userTokens = _estimateTokens(prompt);

    state = state.copyWith(
      isLoading: true,
      error: null,
      totalTokens: state.totalTokens + userTokens,
      activeAgentRole: 'Planner', // Start with Planner
      currentStatusMessage: l10n.analyzingTaskAndPlanning,
    );
    _updateMessagesAndSync([...state.messages, userMessage]);

    int currentStep = 0;
    const maxSteps = 10;
    String nextPrompt = prompt;
    // Anti-loop: track which files had errors and how many consecutive fix attempts
    int consecutiveErrorFixAttempts = 0;
    const maxErrorFixAttempts = 2;
    Set<String> lastErrorFiles = {};

    try {
      final workspacePath = _ref.read(workspaceProvider).currentPath;
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
          File(p.join(workspacePath, '.quantumrules')),
          File(p.join(workspacePath, '.agentrules')),
          File(p.join(workspacePath, '.cursorrules')),
        ];
        for (final f in rulesFiles) {
          if (f.existsSync()) {
            try {
              rulesContent = f.readAsStringSync();
              break;
            } catch (e) {
              debugPrint('Failed to read rules file ${f.path}: $e');
            }
          }
        }

        final systemInstruction = AIPrompts.getSystemInstruction(
          compressedContext,
          activeComponents: activeComponents,
          mcpTools: mcpTools,
          internetAccess: internetAccess,
          rulesContent: rulesContent,
        );

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
        final responseText = await _aiService.sendChatMessage(
          nextPrompt,
          history,
          systemInstruction: systemInstruction,
        );
        final responseTokens = _estimateTokens(responseText);

        // Parse proposed actions
        final actions = _parseActions(responseText);

        final cleanContent = responseText
            .replaceAll(RegExp(r'<actions>[\s\S]*?<\/actions>', caseSensitive: false), '')
            .replaceAll(RegExp(r'<action>[\s\S]*?<\/action>', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[\s*\{\s*"type"[\s\S]*?\}\s*\]'), '')
            .trim();

        final assistantMessage = ChatMessage(
          role: MessageRole.assistant,
          content: cleanContent,
          timestamp: DateTime.now(),
          actions: actions.isNotEmpty ? actions : null,
        );

        state = state.copyWith(
          totalTokens: state.totalTokens + responseTokens,
        );
        _updateMessagesAndSync([...state.messages, assistantMessage]);

        // Sub-Agent State Machine processing
        if (state.activeAgentRole == 'Planner') {
          // Move from Planner to Coder once the plan is made
          state = state.copyWith(
            activeAgentRole: 'Coder',
            currentStatusMessage: l10n.generatingCodeChanges,
          );
          _updateMessagesAndSync([
            ...state.messages,
            ChatMessage(
              role: MessageRole.system,
              content: l10n.executionPlanConstructed,
              timestamp: DateTime.now(),
            )
          ]);
          nextPrompt = "Plan accepted. Please implement the changes according to the proposed plan and output the actions.";
          await Future.delayed(const Duration(milliseconds: 500));
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
            nextPrompt = "Please verify the implementation. Are there any compilation or analyzer errors?";
            continue;
          } else {
            // Done
            state = state.copyWith(isLoading: false, activeAgentRole: null, currentStatusMessage: null);
            break;
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
          final blockedText = blockedActions.map((a) => "- ${a.type.toUpperCase()}: ${a.path}").join('\n');
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
              .map((a) => "- ${a.type.toUpperCase()}: ${a.path.isNotEmpty ? p.relative(a.path, from: workspacePath) : a.content}")
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
          await Future.delayed(const Duration(milliseconds: 800));

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
            nextPrompt = "Validation found compilation errors (attempt $consecutiveErrorFixAttempts/$maxErrorFixAttempts).\n\n**Exact analyzer errors:**\n$errorReport\n\nFor each error:\n1. Read the file via read_file if you need context\n2. Fix only the lines with errors, avoid rewriting entire file unnecessarily";
          } else {
            consecutiveErrorFixAttempts = 0;
            lastErrorFiles = {};
            state = state.copyWith(currentStatusMessage: null);
            nextPrompt = "All changes applied successfully. No compilation errors. Verify logic correctness or report completion.";
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

    var regExp = RegExp(r'<actions>([\s\S]*?)<\/actions>', caseSensitive: false);
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

        final List<dynamic> jsonList = jsonDecode(jsonStr);
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
    return lines.isEmpty ? '(нет ошибок)' : lines.join('\n');
  }

  Future<String> applyAction(AIAction action, {bool runInBackground = true}) async {
    final l10n = _ref.read(localizationsProvider);
    final workspacePath = _ref.read(workspaceProvider).currentPath;

    final relPath = workspacePath != null && action.path.startsWith(workspacePath)
        ? p.relative(action.path, from: workspacePath)
        : action.path;

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
          if (!targetFile.existsSync()) {
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
          if (file.existsSync()) {
            if (!_currentStepBackups.containsKey(action.path)) {
              _currentStepBackups[action.path] = file.readAsStringSync();
            }
          } else {
            if (!_currentStepBackups.containsKey(action.path)) {
              _currentStepBackups[action.path] = null;
            }
          }
          // Ensure file is open in editor (loads original content)
          await _ref.read(editorProvider.notifier).openFile(action.path);
          // Apply AI changes to editor (calculates and shows diff)
          _ref.read(editorProvider.notifier).updateFileContentFromAI(action.path, action.content);
          
          await file.parent.create(recursive: true);
          await file.writeAsString(action.content);
          removeAction(action);
          return l10n.fileSuccessfullyWritten(action.path);
        case 'delete':
          final file = File(action.path);
          if (await file.exists()) {
            if (!_currentStepBackups.containsKey(action.path)) {
              _currentStepBackups[action.path] = file.readAsStringSync();
            }
            await file.delete(recursive: true);
          }
          removeAction(action);
          return l10n.fileSuccessfullyDeleted(action.path);
        case 'command':
          final cmdText = action.content.trim().toLowerCase();
          
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
          final dir = Directory(workspacePath);
          final results = <String>[];
          int matchCount = 0;
          try {
            await for (final file in dir.list(recursive: true, followLinks: false)) {
              if (file is File) {
                final path = file.path;
                // Ignore standard build and cache directories to optimize speed
                if (path.contains('/.git/') || 
                    path.contains('/.dart_tool/') || 
                    path.contains('/build/') || 
                    path.contains('/.idea/') ||
                    path.contains('/ios/Pods/')) {
                  continue;
                }
                // Ignore binary formats
                if (path.endsWith('.png') || 
                    path.endsWith('.jpg') || 
                    path.endsWith('.ico') || 
                    path.endsWith('.apk') || 
                    path.endsWith('.pdf')) {
                  continue;
                }
                
                try {
                  final fileContent = await file.readAsString();
                  if (fileContent.toLowerCase().contains(query.toLowerCase())) {
                    final lines = fileContent.split('\n');
                    for (int i = 0; i < lines.length; i++) {
                      if (lines[i].toLowerCase().contains(query.toLowerCase())) {
                        final relPath = p.relative(path, from: workspacePath);
                        results.add('$relPath:${i + 1}: ${lines[i].trim()}');
                        matchCount++;
                        if (matchCount >= 50) break;
                      }
                    }
                  }
                } catch (_) {}
              }
              if (matchCount >= 50) break;
            }
          } catch (e) {
            return l10n.failedToApplyActionWithError('searching: $e');
          }
          removeAction(action);
          if (results.isEmpty) {
            return l10n.aiSearchNoMatches(query);
          }
          return l10n.aiSearchMatchesFound(matchCount, query, results.join('\n'));
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
    final relPath = _ref.read(workspaceProvider).currentPath != null && action.path.startsWith(_ref.read(workspaceProvider).currentPath!)
        ? p.relative(action.path, from: _ref.read(workspaceProvider).currentPath!)
        : action.path;
    _updateMessagesAndSync([
      ...state.messages,
      ChatMessage(
        role: MessageRole.system,
        content: action.type == 'command'
            ? l10n.runningCommandLabel(action.content)
            : l10n.applyingChangeLabel(relPath),
        timestamp: DateTime.now(),
      ),
    ]);

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
    
    for (final action in actionsCopy) {
      removeAction(action);
      final relPath = _ref.read(workspaceProvider).currentPath != null && action.path.startsWith(_ref.read(workspaceProvider).currentPath!)
          ? p.relative(action.path, from: _ref.read(workspaceProvider).currentPath!)
          : action.path;
      _updateMessagesAndSync([
        ...state.messages,
        ChatMessage(
          role: MessageRole.system,
          content: action.type == 'command'
              ? l10n.runningCommandLabel(action.content)
              : l10n.applyingChangeLabel(relPath),
          timestamp: DateTime.now(),
        ),
      ]);

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
          fileBackups: backupsToSave,
        ),
      ]);

      if (action.type == 'command') {
        commandResult = result;
        lastCommand = action.content;
      }
    }

    if (lastCommand.isNotEmpty) {
      final analysisPrompt = 'Results of running command "$lastCommand":\n$commandResult\n\nAnalyze the result. If errors occurred, fix them.';
      await askAI(analysisPrompt);
    }
  }

  void removeAction(AIAction action) {
    state = state.copyWith(
      proposedActions: state.proposedActions.where((a) => a != action).toList(),
    );
  }

  Future<String> _performWebSearch(String query) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
      );
      final html = response.data.toString();
      final results = <String>[];
      final titleMatches = RegExp(r'<a class="result__url"[^>]*>([\s\S]*?)<\/a>').allMatches(html);
      final snippetMatches = RegExp(r'<a class="result__snippet"[^>]*>([\s\S]*?)<\/a>').allMatches(html);
      
      final titleList = titleMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      final snippetList = snippetMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
      
      for (int i = 0; i < titleList.length && i < 5; i++) {
        results.add('[${i+1}] Title: ${titleList[i]}\nSnippet: ${snippetList[i]}\n');
      }
      
      if (results.isEmpty) {
        final liteMatches = RegExp(r'<td class="result-snippet"[^>]*>([\s\S]*?)<\/td>').allMatches(html);
        final liteTitles = RegExp(r'<a class="result-link"[^>]*>([\s\S]*?)<\/a>').allMatches(html);
        final lTitles = liteTitles.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
        final lSnippets = liteMatches.map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '').toList();
        for (int i = 0; i < lTitles.length && i < 5; i++) {
          results.add('[${i+1}] Title: ${lTitles[i]}\nSnippet: ${lSnippets[i]}\n');
        }
      }

      if (results.isEmpty) {
        return 'No search results found. (Maybe DuckDuckGo anti-bot activated)';
      }
      return results.join('\n');
    } catch (e) {
      return 'Web search failed: $e';
    }
  }

  Future<String> _performWebFetch(String url) async {
    try {
      final dio = Dio();
      final resp = await dio.get(
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
