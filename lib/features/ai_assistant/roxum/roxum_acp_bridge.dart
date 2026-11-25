import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/core/services/workspace_path_resolver.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';

/// Supported AI coding agent execution engines in QuantumIDE.
///
/// External engines communicate via the official **Agent Client Protocol (ACP)**
/// (`package:acp_dart`), giving QuantumIDE native Zed/JetBrains-grade support
/// for OpenCode, Gemini CLI, and Claude Code inside Android PRoot, Native Root,
/// and Desktop workspaces.
enum RoxumAgentEngine {
  builtIn,
  opencodeAcp,
  geminiAcp,
  claudeAcp;

  String get id => name;

  String get shortLabel => switch (this) {
    RoxumAgentEngine.builtIn => 'Roxum',
    RoxumAgentEngine.opencodeAcp => 'OpenCode',
    RoxumAgentEngine.geminiAcp => 'Gemini CLI',
    RoxumAgentEngine.claudeAcp => 'Claude Code',
  };

  String get displayName => switch (this) {
    RoxumAgentEngine.builtIn => 'Roxum Built-in (Dart)',
    RoxumAgentEngine.opencodeAcp => 'OpenCode (ACP)',
    RoxumAgentEngine.geminiAcp => 'Gemini CLI (ACP)',
    RoxumAgentEngine.claudeAcp => 'Claude Code (ACP)',
  };

  String get subtitle => switch (this) {
    RoxumAgentEngine.builtIn =>
      'Встроенный Dart-движок без CLI (работает везде по API-ключу)',
    RoxumAgentEngine.opencodeAcp =>
      'Настоящий движок OpenCode по протоколу ACP — 1-в-1 как в терминале',
    RoxumAgentEngine.geminiAcp =>
      'Официальный Google Gemini CLI по протоколу ACP',
    RoxumAgentEngine.claudeAcp =>
      'Anthropic Claude Code по протоколу ACP (claude-code-acp)',
  };

  String get binaryName => switch (this) {
    RoxumAgentEngine.builtIn => '',
    RoxumAgentEngine.opencodeAcp => 'opencode',
    RoxumAgentEngine.geminiAcp => 'gemini',
    RoxumAgentEngine.claudeAcp => 'claude-code-acp',
  };

  List<String> get acpArgs => switch (this) {
    RoxumAgentEngine.builtIn => const [],
    RoxumAgentEngine.opencodeAcp => const ['acp'],
    RoxumAgentEngine.geminiAcp => const ['--experimental-acp'],
    RoxumAgentEngine.claudeAcp => const [],
  };

  String get installCommand => switch (this) {
    RoxumAgentEngine.builtIn => '',
    RoxumAgentEngine.opencodeAcp =>
      'curl -fsSL https://opencode.ai/install | bash || npm install -g opencode-ai',
    RoxumAgentEngine.geminiAcp => 'npm install -g @google/gemini-cli',
    RoxumAgentEngine.claudeAcp =>
      'npm install -g @zed-industries/claude-code-acp',
  };

  static RoxumAgentEngine fromId(String? raw) {
    if (raw == null || raw.isEmpty) return RoxumAgentEngine.builtIn;
    return RoxumAgentEngine.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => RoxumAgentEngine.builtIn,
    );
  }
}

/// Manages a live ACP (Agent Client Protocol) subprocess via `acp_dart`
/// (`opencode acp`, `gemini --experimental-acp`, `claude-code-acp`) and bridges
/// real-time thoughts, text chunks, tool calls, and file diffs directly into
/// QuantumIDE's chat timeline and code editor.
class RoxumAcpBridge {
  static const String _extraPathExport =
      r'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin:$PATH"; ';

  Process? _process;
  ClientSideConnection? _connection;
  _QuantumAcpClient? _clientHandler;
  String? _acpSessionId;
  RoxumAgentEngine? _activeEngine;
  String? _activeWorkspace;
  String? _activeChatSessionId;
  List<ModelInfo> _availableModels = const [];
  String? _currentAcpModelId;
  bool _turnCancelled = false;

  List<ModelInfo> get availableModels => List.unmodifiable(_availableModels);
  String? get currentAcpModelId => _currentAcpModelId;
  bool get isConnected => _process != null && _connection != null;

  /// Checks which external ACP CLI engines are installed in the active runtime
  /// (Android PRoot Ubuntu, Native Root, or Desktop).
  static Future<Map<RoxumAgentEngine, bool>> detectInstalledEngines(
    RuntimeService runtime,
  ) async {
    final result = <RoxumAgentEngine, bool>{
      RoxumAgentEngine.builtIn: true,
      RoxumAgentEngine.opencodeAcp: false,
      RoxumAgentEngine.geminiAcp: false,
      RoxumAgentEngine.claudeAcp: false,
    };
    try {
      const cmd =
          '$_extraPathExport'
          'for b in opencode gemini claude-code-acp; do '
          '  if command -v "\$b" >/dev/null 2>&1; then echo "FOUND:\$b"; fi; '
          'done';
      final out = await runtime
          .runCommand(cmd, timeout: const Duration(seconds: 12));
      for (final line in out.split('\n')) {
        final t = line.trim();
        if (t == 'FOUND:opencode') {
          result[RoxumAgentEngine.opencodeAcp] = true;
        } else if (t == 'FOUND:gemini') {
          result[RoxumAgentEngine.geminiAcp] = true;
        } else if (t == 'FOUND:claude-code-acp') {
          result[RoxumAgentEngine.claudeAcp] = true;
        }
      }
    } catch (e) {
      TalkerService.warning('[RoxumACP] Engine detection warning: $e');
    }
    return result;
  }

  /// Installs an ACP CLI engine inside the current runtime.
  static Future<({bool success, String output})> installEngine(
    RuntimeService runtime,
    RoxumAgentEngine engine,
  ) async {
    if (engine == RoxumAgentEngine.builtIn || engine.installCommand.isEmpty) {
      return (success: true, output: 'Built-in engine is already available.');
    }
    try {
      final res = await runtime.runCommandDetailed(
        '$_extraPathExport${engine.installCommand} 2>&1',
        timeout: const Duration(minutes: 4),
      );
      final detected = await detectInstalledEngines(runtime);
      final ok = detected[engine] == true || res.exitCode == 0;
      return (success: ok, output: res.combined.trim());
    } catch (e) {
      return (success: false, output: 'Ошибка установки ${engine.displayName}: $e');
    }
  }

  /// Builds API key environment map from QuantumIDE settings so OpenCode /
  /// Gemini CLI / Claude Code immediately inherit the user's configured keys.
  static Map<String, String> buildApiKeyEnv(SettingsState settings) {
    final env = <String, String>{};
    if (settings.openrouterApiKey.trim().isNotEmpty) {
      env['OPENROUTER_API_KEY'] = settings.openrouterApiKey.trim();
    }
    if (settings.deepseekApiKey.trim().isNotEmpty) {
      env['DEEPSEEK_API_KEY'] = settings.deepseekApiKey.trim();
    }
    if (settings.openaiApiKey.trim().isNotEmpty) {
      env['OPENAI_API_KEY'] = settings.openaiApiKey.trim();
    }
    if (settings.anthropicApiKey.trim().isNotEmpty) {
      env['ANTHROPIC_API_KEY'] = settings.anthropicApiKey.trim();
    }
    if (settings.geminiApiKey.trim().isNotEmpty) {
      final key = settings.geminiApiKey.trim();
      env['GEMINI_API_KEY'] = key;
      env['GOOGLE_GENERATIVE_AI_API_KEY'] = key;
    }
    if (settings.groqApiKey.trim().isNotEmpty) {
      env['GROQ_API_KEY'] = settings.groqApiKey.trim();
    }
    if (settings.xaiApiKey.trim().isNotEmpty) {
      env['XAI_API_KEY'] = settings.xaiApiKey.trim();
    }
    if (settings.mistralApiKey.trim().isNotEmpty) {
      env['MISTRAL_API_KEY'] = settings.mistralApiKey.trim();
    }
    return env;
  }

  /// Maps QuantumIDE's `provider:model` ID (e.g. `openrouter:qwen/qwen3-coder:free`)
  /// to the best matching ACP model ID advertised by the agent (`openrouter/qwen/qwen3-coder:free`).
  static String? resolveAcpModelId(
    String? quantumModelId,
    List<ModelInfo> availableModels,
  ) {
    if (quantumModelId == null || quantumModelId.trim().isEmpty) return null;
    final raw = quantumModelId.trim();
    final colonIdx = raw.indexOf(':');
    final slashVariant = colonIdx > 0
        ? '${raw.substring(0, colonIdx)}/${raw.substring(colonIdx + 1)}'
        : raw;
    final bareModel = colonIdx > 0 ? raw.substring(colonIdx + 1) : raw;

    if (availableModels.isEmpty) {
      return slashVariant;
    }

    for (final m in availableModels) {
      if (m.modelId == raw || m.modelId == slashVariant) return m.modelId;
    }
    final bareLower = bareModel.toLowerCase();
    for (final m in availableModels) {
      final idLower = m.modelId.toLowerCase();
      if (idLower == bareLower || idLower.endsWith('/$bareLower')) {
        return m.modelId;
      }
    }
    return null;
  }

  /// Runs a full prompt turn via ACP (`acp_dart`), streaming thoughts, text,
  /// tool calls, and file diffs back into QuantumIDE's UI callbacks.
  Future<String> runPromptTurn({
    required Ref ref,
    required RoxumAgentEngine engine,
    required String workspacePath,
    required String chatSessionId,
    required String promptText,
    required List<RoxumAttachment> attachments,
    required SettingsState settings,
    required String? selectedModelId,
    required Map<String, RoxumPendingEdit> pendingEdits,
    required void Function(Map<String, RoxumPendingEdit> updated)
        onPendingEditsChanged,
    required void Function(RoxumToolCallRecord record) onToolEvent,
    required void Function(String partialText) onAssistantText,
    required void Function(String reasoningText) onReasoningText,
    required void Function(RoxumUsageStats usage) onUsage,
    required bool Function() isCancelled,
  }) async {
    _turnCancelled = false;

    final runtime = ref.read(runtimeServiceProvider);
    final guestWorkspace = workspacePath.isNotEmpty
        ? runtime.toProotPath(workspacePath)
        : '/root';

    final needsRestart =
        _process == null ||
        _connection == null ||
        _acpSessionId == null ||
        _activeEngine != engine ||
        _activeWorkspace != workspacePath ||
        _activeChatSessionId != chatSessionId;

    if (needsRestart) {
      await resetSession();
      await _startAndInitialize(
        ref: ref,
        engine: engine,
        workspacePath: workspacePath,
        guestWorkspace: guestWorkspace,
        chatSessionId: chatSessionId,
        settings: settings,
      );
    }

    final conn = _connection;
    final sessionId = _acpSessionId;
    final handler = _clientHandler;
    if (conn == null || sessionId == null || handler == null) {
      throw StateError('Не удалось установить ACP-соединение с ${engine.displayName}.');
    }

    // Best-effort model sync with ACP agent (OpenCode / Gemini / Claude)
    final desiredAcpModel = resolveAcpModelId(selectedModelId, _availableModels);
    if (desiredAcpModel != null && desiredAcpModel != _currentAcpModelId) {
      try {
        await conn
            .setSessionModel(
              SetSessionModelRequest(
                sessionId: sessionId,
                modelId: desiredAcpModel,
              ),
            )
            ?.timeout(const Duration(seconds: 8));
        _currentAcpModelId = desiredAcpModel;
      } catch (e) {
        TalkerService.info(
          '[RoxumACP] setSessionModel($desiredAcpModel) skipped: $e',
        );
      }
    }

    final resolver = WorkspacePathResolver(
      workspacePath,
      androidFilesDir: runtime.filesDir,
    );

    handler.beginTurn(
      resolver: resolver,
      workspacePath: workspacePath,
      pendingEdits: pendingEdits,
      onPendingEditsChanged: onPendingEditsChanged,
      onToolEvent: onToolEvent,
      onAssistantText: onAssistantText,
      onReasoningText: onReasoningText,
      isCancelled: () => _turnCancelled || isCancelled(),
      onReloadFile: (hostPath) async {
        try {
          await ref.read(editorProvider.notifier).reloadFileFromDisk(hostPath);
        } catch (_) {}
      },
      onRefreshExplorer: () {
        try {
          ref.read(fileTreeRefreshProvider.notifier).state++;
          ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
        } catch (_) {}
      },
    );

    final blocks = <ContentBlock>[
      if (promptText.trim().isNotEmpty) TextContentBlock(text: promptText),
      for (final att in attachments)
        if (att.isImage && att.base64Data != null)
          ImageContentBlock(data: att.base64Data!, mimeType: att.mimeType)
        else if (att.textContent != null && att.textContent!.isNotEmpty)
          TextContentBlock(
            text:
                '<attached_file name="${att.name}">\n${att.textContent}\n</attached_file>',
          ),
    ];
    if (blocks.isEmpty) {
      blocks.add(TextContentBlock(text: promptText));
    }

    try {
      final response = await conn.prompt(
        PromptRequest(sessionId: sessionId, prompt: blocks),
      );

      final u = response.usage;
      if (u != null && u.totalTokens > 0) {
        onUsage(
          RoxumUsageStats(
            promptTokens: u.inputTokens,
            completionTokens: u.outputTokens,
            totalTokens: u.totalTokens,
          ),
        );
      }

      // Refresh workspace tree and open tabs once turn finishes
      try {
        ref.read(fileTreeRefreshProvider.notifier).state++;
        ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
      } catch (_) {}

      final answer = handler.accumulatedAnswer.trim();
      if (answer.isNotEmpty) return answer;
      if (response.stopReason == StopReason.cancelled) {
        return '';
      }
      return 'Выполнено через ${engine.displayName}.';
    } catch (e) {
      if (_turnCancelled || isCancelled()) {
        return handler.accumulatedAnswer.trim();
      }
      final stderrTail = handler.stderrTail;
      await resetSession();
      final details = stderrTail.isNotEmpty ? '\n\nЛог агента:\n$stderrTail' : '';
      throw Exception('${engine.displayName} (ACP): $e$details');
    }
  }

  Future<void> _startAndInitialize({
    required Ref ref,
    required RoxumAgentEngine engine,
    required String workspacePath,
    required String guestWorkspace,
    required String chatSessionId,
    required SettingsState settings,
  }) async {
    final runtime = ref.read(runtimeServiceProvider);
    final apiEnv = buildApiKeyEnv(settings);
    final escapedArgs = engine.acpArgs
        .map((a) => "'${a.replaceAll("'", "'\\''")}'")
        .join(' ');
    final envExports = apiEnv.entries
        .map((e) => "export ${e.key}='${e.value.replaceAll("'", "'\\''")}'; ")
        .join();
    final cmdBody =
        '$_extraPathExport$envExports'
        'if ! command -v ${engine.binaryName} >/dev/null 2>&1; then '
        '  echo "ACP_BINARY_MISSING:${engine.binaryName}" >&2; exit 127; '
        'fi; '
        'exec ${engine.binaryName}${escapedArgs.isNotEmpty ? ' $escapedArgs' : ''}';

    Process proc;
    if (Platform.isAndroid) {
      final initHost = p.join(runtime.filesDir, 'bin', 'init-host');
      if (runtime.useNativeRootMode) {
        final wd = workspacePath.isNotEmpty
            ? "cd '${workspacePath.replaceAll("'", "'\\''")}' 2>/dev/null; "
            : '';
        proc = await Process.start(
          'su',
          ['-c', '$wd$cmdBody'],
          environment: {...runtime.env, ...apiEnv},
        );
      } else if (await File(initHost).exists()) {
        proc = await Process.start(
          'sh',
          [
            initHost,
            runtime.filesDir,
            guestWorkspace,
            '/bin/bash',
            '-c',
            cmdBody,
          ],
          environment: {...runtime.env, ...apiEnv},
        );
      } else {
        proc = await Process.start(
          engine.binaryName,
          engine.acpArgs,
          workingDirectory: workspacePath.isNotEmpty ? workspacePath : null,
          environment: {...runtime.env, ...apiEnv},
        );
      }
    } else {
      final mergedEnv = {...runtime.desktopEnv, ...apiEnv};
      if (Platform.isWindows) {
        proc = await Process.start(
          engine.binaryName,
          engine.acpArgs,
          workingDirectory: workspacePath.isNotEmpty ? workspacePath : null,
          environment: mergedEnv,
          runInShell: true,
        );
      } else {
        proc = await Process.start(
          'bash',
          ['-c', cmdBody],
          workingDirectory: workspacePath.isNotEmpty ? workspacePath : null,
          environment: mergedEnv,
        );
      }
    }

    final handler = _QuantumAcpClient();
    proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((
      chunk,
    ) {
      handler.appendStderr(chunk);
    });

    unawaited(
      proc.exitCode.then((code) {
        if (_process == proc) {
          TalkerService.info(
            '[RoxumACP] ${engine.displayName} exited with code $code',
          );
          _process = null;
          _connection = null;
          _acpSessionId = null;
        }
      }),
    );

    final stream = ndJsonStream(
      proc.stdout,
      proc.stdin,
      onParseError: (line, error) {
        // Ignore non-JSON startup banners from PRoot/shell
        TalkerService.info('[RoxumACP] Ignored non-JSON stdout line: $line');
      },
    );
    final conn = ClientSideConnection((_) => handler, stream);

    try {
      await conn
          .initialize(
            InitializeRequest(
              protocolVersion: 1,
              clientInfo: Implementation(
                name: 'QuantumIDE',
                title: 'QuantumIDE',
                version: '1.2.308',
              ),
              // Keep fs/terminal false so OpenCode / Gemini CLI / Claude Code
              // use their own battle-tested native file, edit, LSP, and bash tools!
              clientCapabilities: ClientCapabilities(
                fs: FileSystemCapability(
                  readTextFile: false,
                  writeTextFile: false,
                ),
                terminal: false,
              ),
            ),
          )
          .timeout(const Duration(seconds: 30));

      final sessionCwd =
          (Platform.isAndroid && !runtime.useNativeRootMode)
              ? guestWorkspace
              : (workspacePath.isNotEmpty
                    ? workspacePath
                    : Directory.current.path);

      final sessionRes = await conn
          .newSession(
            NewSessionRequest(cwd: sessionCwd, mcpServers: const []),
          )
          .timeout(const Duration(seconds: 30));

      _process = proc;
      _connection = conn;
      _clientHandler = handler;
      _acpSessionId = sessionRes.sessionId;
      _activeEngine = engine;
      _activeWorkspace = workspacePath;
      _activeChatSessionId = chatSessionId;
      _availableModels = sessionRes.models?.availableModels ?? const [];
      _currentAcpModelId = sessionRes.models?.currentModelId;
    } catch (e) {
      try {
        proc.kill();
      } catch (_) {}
      final errLog = handler.stderrTail;
      if (errLog.contains('ACP_BINARY_MISSING:')) {
        throw Exception(
          '${engine.displayName} не установлен в среде.\n'
          'Откройте выбор движка внизу чата и нажмите «Установить ${engine.shortLabel}», '
          'либо выполните в терминале:\n${engine.installCommand}',
        );
      }
      rethrow;
    }
  }

  /// Cancels the active ACP turn (without tearing down the session if possible).
  Future<void> cancelActiveTurn() async {
    _turnCancelled = true;
    final conn = _connection;
    final sid = _acpSessionId;
    if (conn != null && sid != null) {
      try {
        await conn
            .cancel(CancelNotification(sessionId: sid))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        await resetSession();
      }
    }
  }

  /// Terminates the running ACP subprocess and clears cached session state.
  Future<void> resetSession() async {
    _turnCancelled = true;
    final proc = _process;
    _process = null;
    _connection = null;
    _clientHandler = null;
    _acpSessionId = null;
    _activeEngine = null;
    _activeWorkspace = null;
    _activeChatSessionId = null;
    _availableModels = const [];
    _currentAcpModelId = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
  }
}

class _QuantumAcpClient implements Client {
  final StringBuffer _answerBuf = StringBuffer();
  final StringBuffer _thoughtBuf = StringBuffer();
  final StringBuffer _stderrBuf = StringBuffer();
  final Map<String, RoxumToolCallRecord> _toolRecords = {};

  WorkspacePathResolver? _resolver;
  String _workspacePath = '';
  Map<String, RoxumPendingEdit> _pendingEdits = {};
  void Function(Map<String, RoxumPendingEdit>)? _onPendingEditsChanged;
  void Function(RoxumToolCallRecord)? _onToolEvent;
  void Function(String)? _onAssistantText;
  void Function(String)? _onReasoningText;
  bool Function()? _isCancelled;
  Future<void> Function(String hostPath)? _onReloadFile;
  void Function()? _onRefreshExplorer;

  String get accumulatedAnswer => _answerBuf.toString();

  String get stderrTail {
    final s = _stderrBuf.toString().trim();
    if (s.length <= 1500) return s;
    return s.substring(s.length - 1500);
  }

  void appendStderr(String chunk) {
    _stderrBuf.write(chunk);
    if (_stderrBuf.length > 8000) {
      final keep = _stderrBuf.toString().substring(_stderrBuf.length - 4000);
      _stderrBuf
        ..clear()
        ..write(keep);
    }
  }

  void beginTurn({
    required WorkspacePathResolver resolver,
    required String workspacePath,
    required Map<String, RoxumPendingEdit> pendingEdits,
    required void Function(Map<String, RoxumPendingEdit>) onPendingEditsChanged,
    required void Function(RoxumToolCallRecord) onToolEvent,
    required void Function(String) onAssistantText,
    required void Function(String) onReasoningText,
    required bool Function() isCancelled,
    required Future<void> Function(String hostPath) onReloadFile,
    required void Function() onRefreshExplorer,
  }) {
    _answerBuf.clear();
    _thoughtBuf.clear();
    _toolRecords.clear();
    _resolver = resolver;
    _workspacePath = workspacePath;
    _pendingEdits = pendingEdits;
    _onPendingEditsChanged = onPendingEditsChanged;
    _onToolEvent = onToolEvent;
    _onAssistantText = onAssistantText;
    _onReasoningText = onReasoningText;
    _isCancelled = isCancelled;
    _onReloadFile = onReloadFile;
    _onRefreshExplorer = onRefreshExplorer;
  }

  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    if (_isCancelled?.call() == true) {
      return RequestPermissionResponse(outcome: CancelledOutcome());
    }
    if (params.options.isEmpty) {
      return RequestPermissionResponse(outcome: CancelledOutcome());
    }
    final preferred = params.options.firstWhere(
      (o) => o.kind == PermissionOptionKind.allowAlways,
      orElse: () => params.options.firstWhere(
        (o) => o.kind == PermissionOptionKind.allowOnce,
        orElse: () => params.options.first,
      ),
    );
    return RequestPermissionResponse(
      outcome: SelectedOutcome(optionId: preferred.optionId),
    );
  }

  @override
  Future<void> sessionUpdate(SessionNotification params) async {
    final update = params.update;

    if (update is AgentMessageChunkSessionUpdate) {
      final text = _extractContentBlockText(update.content);
      if (text.isNotEmpty) {
        _answerBuf.write(text);
        _onAssistantText?.call(_answerBuf.toString());
      }
      return;
    }

    if (update is AgentThoughtChunkSessionUpdate) {
      final thought = _extractContentBlockText(update.content);
      if (thought.isNotEmpty) {
        _thoughtBuf.write(thought);
        _onReasoningText?.call(_thoughtBuf.toString());
      }
      return;
    }

    if (update is PlanSessionUpdate) {
      if (update.entries.isNotEmpty) {
        final planLines = update.entries
            .map((e) => '• [${e.status.name}] ${e.content}')
            .join('\n');
        _thoughtBuf.writeln('\n[Plan]\n$planLines');
        _onReasoningText?.call(_thoughtBuf.toString());
      }
      return;
    }

    if (update is ToolCallSessionUpdate) {
      await _handleToolUpdate(
        id: update.toolCallId,
        title: update.title.isNotEmpty
            ? update.title
            : (update.name ?? update.kind?.name ?? 'tool'),
        rawInput: update.rawInput,
        rawOutput: update.rawOutput,
        status: update.status,
        content: update.content,
        locations: update.locations,
      );
      return;
    }

    if (update is ToolCallUpdateSessionUpdate) {
      await _handleToolUpdate(
        id: update.toolCallId,
        title: update.title ?? update.name,
        rawInput: update.rawInput,
        rawOutput: update.rawOutput,
        status: update.status,
        content: update.content,
        locations: update.locations,
      );
      return;
    }
  }

  Future<void> _handleToolUpdate({
    required String id,
    String? title,
    Object? rawInput,
    Object? rawOutput,
    ToolCallStatus? status,
    List<ToolCallContent>? content,
    List<ToolCallLocation>? locations,
  }) async {
    final prev = _toolRecords[id];
    final effectiveName =
        (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : (prev?.name ?? 'tool');
    final args = _coerceArgsMap(rawInput) ?? prev?.arguments ?? const {};
    final isRunning =
        status == null ||
        status == ToolCallStatus.pending ||
        status == ToolCallStatus.inProgress;
    final success = status != ToolCallStatus.failed;
    final formattedOut = _formatToolOutput(content, rawOutput);
    final effectiveOutput = formattedOut.isNotEmpty
        ? formattedOut
        : (prev?.output ?? '');

    final record = RoxumToolCallRecord(
      id: id,
      name: effectiveName,
      arguments: args,
      isRunning: isRunning,
      success: success,
      output: effectiveOutput,
    );
    _toolRecords[id] = record;
    _onToolEvent?.call(record);

    // Record real file diffs & reload modified files in QuantumIDE editor
    final touchedHostPaths = <String>{};
    if (content != null) {
      for (final c in content) {
        if (c is DiffToolCallContent) {
          final hostPath = _toHostPath(c.path);
          touchedHostPaths.add(hostPath);
          final oldText = c.oldText ?? '';
          final newText = c.newText;
          final prevOriginal =
              _pendingEdits[hostPath]?.originalContent ?? oldText;
          final prevExisted =
              _pendingEdits[hostPath]?.existedBefore ?? (c.oldText != null);
          final counts = _diffLineCounts(prevOriginal, newText);
          _pendingEdits[hostPath] = RoxumPendingEdit(
            filePath: hostPath,
            originalContent: prevOriginal,
            updatedContent: newText,
            existedBefore: prevExisted,
            addedLines: counts.added,
            removedLines: counts.removed,
          );
          _onPendingEditsChanged?.call(
            Map<String, RoxumPendingEdit>.from(_pendingEdits),
          );
        }
      }
    }

    if (!isRunning) {
      if (locations != null) {
        for (final loc in locations) {
          if (loc.path.trim().isNotEmpty) {
            touchedHostPaths.add(_toHostPath(loc.path));
          }
        }
      }
      for (final hp in touchedHostPaths) {
        await _onReloadFile?.call(hp);
      }
      if (touchedHostPaths.isNotEmpty) {
        _onRefreshExplorer?.call();
      }
    }
  }

  String _toHostPath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return _workspacePath;
    if (_resolver != null) return _resolver!.toHostPath(trimmed);
    return p.isAbsolute(trimmed) ? trimmed : p.join(_workspacePath, trimmed);
  }

  static ({int added, int removed}) _diffLineCounts(
    String before,
    String after,
  ) {
    final a = before.isEmpty ? <String>[] : before.split('\n');
    final b = after.isEmpty ? <String>[] : after.split('\n');
    final setA = a.toSet();
    final setB = b.toSet();
    final added = b.where((l) => !setA.contains(l)).length;
    final removed = a.where((l) => !setB.contains(l)).length;
    return (added: added, removed: removed);
  }

  static String _extractContentBlockText(ContentBlock block) {
    if (block is TextContentBlock) return block.text;
    return '';
  }

  static Map<String, dynamic>? _coerceArgsMap(Object? raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {'input': raw.toString()};
  }

  static String _formatToolOutput(
    List<ToolCallContent>? content,
    Object? rawOutput,
  ) {
    final buf = StringBuffer();
    if (content != null) {
      for (final item in content) {
        if (item is ContentToolCallContent) {
          final txt = _extractContentBlockText(item.content);
          if (txt.isNotEmpty) buf.writeln(txt);
        } else if (item is DiffToolCallContent) {
          final counts = _diffLineCounts(item.oldText ?? '', item.newText);
          buf.writeln(
            'Modified ${item.path} (+${counts.added} / -${counts.removed})',
          );
        }
      }
    }
    if (buf.isEmpty && rawOutput != null) {
      if (rawOutput is String) {
        buf.write(rawOutput);
      } else {
        try {
          buf.write(jsonEncode(rawOutput));
        } catch (_) {
          buf.write(rawOutput.toString());
        }
      }
    }
    final res = buf.toString().trim();
    if (res.length > 3500) {
      return '${res.substring(0, 3500)}\n... [truncated]';
    }
    return res;
  }

  @override
  Future<WriteTextFileResponse>? writeTextFile(WriteTextFileRequest params) async {
    final hostPath = _toHostPath(params.path);
    final file = File(hostPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(params.content);
    await _onReloadFile?.call(hostPath);
    _onRefreshExplorer?.call();
    return WriteTextFileResponse();
  }

  @override
  Future<ReadTextFileResponse>? readTextFile(ReadTextFileRequest params) async {
    final hostPath = _toHostPath(params.path);
    final file = File(hostPath);
    if (!await file.exists()) {
      throw RequestError.resourceNotFound(params.path);
    }
    final lines = await file.readAsLines();
    final start = ((params.line ?? 1) - 1).clamp(0, lines.length);
    final end = params.limit != null
        ? (start + params.limit!).clamp(start, lines.length)
        : lines.length;
    return ReadTextFileResponse(content: lines.sublist(start, end).join('\n'));
  }

  @override
  Future<CreateTerminalResponse>? createTerminal(
    CreateTerminalRequest params,
  ) => null;

  @override
  Future<TerminalOutputResponse>? terminalOutput(
    TerminalOutputRequest params,
  ) => null;

  @override
  Future<ReleaseTerminalResponse?>? releaseTerminal(
    ReleaseTerminalRequest params,
  ) => null;

  @override
  Future<WaitForTerminalExitResponse>? waitForTerminalExit(
    WaitForTerminalExitRequest params,
  ) => null;

  @override
  Future<KillTerminalCommandResponse?>? killTerminal(
    KillTerminalCommandRequest params,
  ) => null;

  @override
  Future<Map<String, dynamic>>? extMethod(
    String method,
    Map<String, dynamic> params,
  ) async => const {};

  @override
  Future<void>? extNotification(
    String method,
    Map<String, dynamic> params,
  ) async {}
}
