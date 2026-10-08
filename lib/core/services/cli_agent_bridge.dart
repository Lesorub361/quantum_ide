import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

final cliAgentBridgeProvider = Provider<CliAgentBridge>((ref) {
  final runtime = ref.watch(runtimeServiceProvider);
  return CliAgentBridge(runtime);
});

class CliAgentBridge {
  final RuntimeService _runtime;
  Process? _activeProcess;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  bool _isStopping = false;

  CliAgentBridge(this._runtime);

  bool get isRunning => _activeProcess != null;

  /// Candidate binary paths depending on agent and system
  List<String> _candidateBinaries(AgentKind kind) {
    final home = Platform.environment['HOME'] ?? '';
    final nvmBase = p.join(home, '.config', 'nvm', 'versions', 'node');
    final List<String> nvmBins = [];
    if (Directory(nvmBase).existsSync()) {
      try {
        for (final versionDir in Directory(nvmBase).listSync()) {
          if (versionDir is Directory) {
            nvmBins.add(p.join(versionDir.path, 'bin'));
          }
        }
      } catch (_) {}
    }

    switch (kind) {
      case AgentKind.native:
        return [];
      case AgentKind.antigravity:
        return [
          p.join(home, '.local', 'bin', 'agy'),
          p.join(home, '.local', 'bin', 'agy.real'),
          for (final b in nvmBins) p.join(b, 'gemini'),
          p.join(home, '.local', 'bin', 'gemini'),
          '/usr/local/bin/agy',
          '/usr/bin/agy',
          'agy',
          'gemini',
          'antigravity',
        ];
      case AgentKind.claudeCode:
        return [
          'claude',
          p.join(home, '.local', 'bin', 'claude'),
          for (final b in nvmBins) p.join(b, 'claude'),
          p.join(home, '.config', 'nvm', 'versions', 'node', 'v22.18.0', 'bin', 'claude'),
          '/usr/local/bin/claude',
          '/usr/bin/claude',
        ];
      case AgentKind.deepseekHarness:
        return [
          p.join(home, '.local', 'bin', 'dsh'),
          '/usr/local/lib/dsh/node_modules/.bin/dsh',
          '/usr/local/bin/dsh',
          '/usr/bin/dsh',
          p.join(home, '.local', 'bin', 'deepseek-harness'),
          'dsh',
          'deepseek-harness',
        ];
    }
  }

  /// Resolve absolute or usable path to the binary
  String? resolveBinary(AgentKind kind) {
    for (final candidate in _candidateBinaries(kind)) {
      if (candidate.contains('/')) {
        final f = File(candidate);
        if (f.existsSync()) return candidate;
      } else {
        try {
          final res = Process.runSync('which', [candidate]);
          if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
            return res.stdout.toString().trim();
          }
        } catch (_) {}
      }
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // In Android, check if file exists inside rootfs
      for (final candidate in _candidateBinaries(kind)) {
        if (!candidate.contains('/')) continue;
        final guestPath = candidate.startsWith('/') ? candidate.substring(1) : candidate;
        final filesDir = Platform.environment['FILES_DIR'] ?? '/data/data/com.quantum.ide/files';
        final rootfsCandidate = File(p.join(filesDir, 'rootfs', 'ubuntu', guestPath));
        if (rootfsCandidate.existsSync()) {
          return candidate;
        }
      }
    }

    return null;
  }

  /// Check if agent executable exists
  Future<bool> isAgentInstalled(AgentKind kind) async {
    final direct = resolveBinary(kind);
    if (direct != null) return true;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final names = kind == AgentKind.antigravity
            ? ['agy', 'gemini']
            : (kind == AgentKind.claudeCode ? ['claude'] : ['dsh', 'deepseek-harness']);
        for (final n in names) {
          final res = await _runtime.runCommand('which $n || test -f /root/.local/bin/$n || test -f /usr/local/bin/$n');
          if (res.trim().isNotEmpty) return true;
        }
        return false;
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Returns commands supported by the chosen CLI agent
  List<String> getCliCommands(AgentKind kind) {
    switch (kind) {
      case AgentKind.native:
        return ['/plan', '/goal', '/search', '/terminal', '/diff', '/rollback', '/clear'];
      case AgentKind.antigravity:
        return [
          '/help',
          '/skills',
          '/mcp',
          '/plan',
          '/goal',
          '/schedule',
          '/browser',
          '/grill-me',
          '/boost',
          '/learn',
          '/clear',
          '/yolo',
        ];
      case AgentKind.claudeCode:
        return ['/help', '/compact', '/cost', '/doctor', '/review', '/init'];
      case AgentKind.deepseekHarness:
        return ['/reasoning', '/diff', '/files', '/rollback', '/clear'];
    }
  }

  /// Returns available models for the chosen CLI agent
  List<String> getCliModels(AgentKind kind) {
    switch (kind) {
      case AgentKind.native:
        return [
          'google/gemma-4-31b-it:free',
          'cohere/north-mini-code:free',
          'deepseek/deepseek-chat',
          'deepseek/deepseek-r1:free',
          'gemini-2.5-flash',
          'claude-3-7-sonnet',
        ];
      case AgentKind.antigravity:
        return [
          'gemini-3.8-flash-high',
          'gemini-3.8-flash-medium',
          'gemini-3.8-flash-low',
          'gemini-3.7-flash-high',
          'gemini-3.7-flash-medium',
          'gemini-3.7-flash-low',
          'gemini-3.6-flash-high',
          'gemini-3.6-flash-medium',
          'gemini-3.6-flash-low',
          'gemini-3.1-pro-high',
          'gemini-3.1-pro-low',
          'claude-sonnet-4-6',
          'claude-opus-4-6-thinking',
          'gpt-oss-120b-medium',
          'gemini-2.5-pro',
          'gemini-2.5-flash',
        ];
      case AgentKind.claudeCode:
        return [
          'claude-3-7-sonnet-20250219',
          'claude-3-5-sonnet-20241022',
          'claude-3-5-haiku-20241022',
          'claude-sonnet-4-6',
          'claude-opus-4-6',
          'anthropic/claude-3.7-sonnet',
          'anthropic/claude-3.5-sonnet',
          'default',
        ];
      case AgentKind.deepseekHarness:
        return [
          'deepseek-chat',
          'deepseek-reasoner',
          'deepseek-v4-flash',
          'google/gemma-4-31b-it:free',
          'cohere/north-mini-code:free',
          'qwen/qwen3.8-27b:free',
          'deepseek/deepseek-r1:free',
          'deepseek/deepseek-chat',
        ];
    }
  }

  /// Start a headless streaming CLI agent session
  Future<void> startSession({
    required String projectId,
    required String projectPath,
    required String prompt,
    required AgentKind agentKind,
    String? model,
    String? apiKey,
    required void Function(ActivityItem item) onActivity,
    required void Function(String textDelta) onDeltaText,
    required void Function(String thinking) onThinking,
    required void Function(int durationMillis) onComplete,
    required void Function(String error) onError,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    _isStopping = false;
    final startTime = DateTime.now();

    final binaryPath = resolveBinary(agentKind);
    final isInstalled = binaryPath != null;

    if (!isInstalled) {
      onActivity(ActivityItem(
        title: 'Checking ${agentKind.title}',
        detail: '${agentKind.title} CLI не установлен в системе.',
        isComplete: true,
      ));
      
      onDeltaText(
        '### ${agentKind.title} CLI не установлен\n\n'
        'Для автономного выполнения задач установите агент в разделе **Пакеты** или выполните в терминале:\n\n'
        '```bash\n${_getInstallCommand(agentKind)}\n```\n\n'
        'После установки агент будет автоматически выполнять команды bash, читать/писать файлы и создавать код без ручных подтверждений.',
      );
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      onComplete(duration);
      return;
    }

    final isGeminiCli = binaryPath.endsWith('gemini');
    final commandArgs = _buildCommand(agentKind, prompt, model, isGeminiCli: isGeminiCli, projectPath: projectPath);

    debugPrint('CliAgentBridge: Launching $binaryPath in $projectPath with args: $commandArgs');

    try {
      final env = Map<String, String>.from(Platform.environment);
      final home = Platform.environment['HOME'] ?? '';
      final localBin = p.join(home, '.local', 'bin');
      final nvmBin = p.join(home, '.config', 'nvm', 'versions', 'node', 'v22.18.0', 'bin');
      var path = env['PATH'] ?? '';
      if (Directory(localBin).existsSync() && !path.contains(localBin)) {
        path = '$localBin:$path';
      }
      if (Directory(nvmBin).existsSync() && !path.contains(nvmBin)) {
        path = '$nvmBin:$path';
      }
      env['PATH'] = path;

      if (agentKind == AgentKind.claudeCode) {
        if (apiKey != null && apiKey.isNotEmpty) {
          if (apiKey.startsWith('sk-or-') || (model != null && model.contains('/'))) {
            env['ANTHROPIC_BASE_URL'] = 'https://openrouter.ai/api';
            env['ANTHROPIC_AUTH_TOKEN'] = apiKey;
            env['OPENROUTER_API_KEY'] = apiKey;
            env['ANTHROPIC_API_KEY'] = '';
            final m = (model != null && model.isNotEmpty) ? model : 'anthropic/claude-3.7-sonnet';
            env['ANTHROPIC_MODEL'] = m;
            env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = m;
            env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = m;
            env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = m;
            env['ANTHROPIC_SMALL_MODEL'] = m;
            env['ANTHROPIC_FAST_MODEL'] = m;
            env['CLAUDE_CODE_SUBAGENT_MODEL'] = m;
            env['CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY'] = '1';
            env['CLAUDE_CODE_DISABLE_TOKEN_COUNTING'] = '1';
            env['DISABLE_TELEMETRY'] = '1';
            env['DISABLE_AUTOUPDATER'] = '1';
          } else {
            env['ANTHROPIC_API_KEY'] = apiKey;
            if (model != null && model.isNotEmpty) {
              env['ANTHROPIC_MODEL'] = model;
            }
          }
        }
      } else if (agentKind == AgentKind.deepseekHarness) {
        env['DSH_PERMISSION_MODE'] = 'danger-full-access';
        final dshHome = p.join(home, '.dsh');
        env['DSH_HOME'] = dshHome;

        final m = (model != null && model.isNotEmpty) ? model : 'google/gemma-4-31b-it:free';
        if (apiKey != null && apiKey.isNotEmpty && apiKey.startsWith('sk-or-')) {
          env['OPENROUTER_API_KEY'] = apiKey;
          try {
            final patchFile = File(p.join(dshHome, 'profiles', 'headless', 'cordis.patch.yml'));
            patchFile.parent.createSync(recursive: true);
            patchFile.writeAsStringSync('''
- id: agent-default-model
  name: "@deepseek-ai/dsh-agent-default-model"
  config:
    provider: openrouter
    model: $m
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      openrouter:
        apiKeyEnv: OPENROUTER_API_KEY
        api: openai-completions
        baseURL: https://openrouter.ai/api/v1
        models:
          - id: $m
''');
          } catch (_) {}
        } else if (apiKey != null && apiKey.isNotEmpty) {
          env['DEEPSEEK_API_KEY'] = apiKey;
        }
      } else if (agentKind == AgentKind.antigravity) {
        env.remove('SSH_CONNECTION');
        env.remove('SSH_CLIENT');
        if (apiKey != null && apiKey.isNotEmpty) {
          env['GEMINI_API_KEY'] = apiKey;
        }
      }

      onActivity(const ActivityItem(
        title: 'Think',
        detail: 'Анализ задачи и планирование действий...',
        isComplete: false,
      ));

      _activeProcess = await Process.start(
        binaryPath,
        commandArgs,
        workingDirectory: projectPath.isNotEmpty ? projectPath : null,
        environment: env,
      );

      final stdoutLines = _activeProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      final stderrLines = _activeProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      bool hasStreamedText = false;
      String lastErrorMessage = '';

      _stdoutSub = stdoutLines.listen((line) {
        _handleOutputLine(
          line,
          agentKind,
          onActivity,
          (delta) {
            hasStreamedText = true;
            onDeltaText(delta);
          },
          onThinking,
          onUsage,
          hasStreamedText: hasStreamedText,
          onErrorDetected: (err) => lastErrorMessage = err,
        );
      });

      _stderrSub = stderrLines.listen((line) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('bash: warning:')) return;

        if (trimmed.toLowerCase().contains('reasoning') || trimmed.toLowerCase().contains('thinking')) {
          onThinking(trimmed);
        } else {
          debugPrint('CliAgentBridge STDERR: $trimmed');
          if (trimmed.startsWith('dsh:')) {
            lastErrorMessage = trimmed.replaceFirst(RegExp(r'^dsh:\s*'), '');
          } else if (trimmed.toLowerCase().contains('error') || trimmed.toLowerCase().contains('failed')) {
            lastErrorMessage = trimmed;
          }
        }
      });

      final exitCode = await _activeProcess!.exitCode;
      _activeProcess = null;

      if (_isStopping) {
        onActivity(const ActivityItem(
          title: 'Остановлено',
          detail: 'Задача остановлена пользователем',
          isComplete: true,
        ));
        onError('Остановлено пользователем');
        return;
      }

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      if (exitCode == 0) {
        onComplete(duration);
      } else {
        final errorDetail = lastErrorMessage.isNotEmpty
            ? lastErrorMessage
            : '$binaryPath завершился с кодом $exitCode';
        onError(errorDetail);
      }
    } catch (e) {
      if (_isStopping) {
        onError('Остановлено');
      } else {
        onError('Ошибка запуска $binaryPath: $e');
      }
    } finally {
      _activeProcess = null;
      _stdoutSub?.cancel();
      _stderrSub?.cancel();
    }
  }

  void _handleOutputLine(
    String line,
    AgentKind agentKind,
    void Function(ActivityItem) onActivity,
    void Function(String) onDeltaText,
    void Function(String) onThinking,
    void Function(Map<String, dynamic>)? onUsage, {
    bool hasStreamedText = false,
    void Function(String)? onErrorDetected,
  }) {
    if (line.trim().isEmpty) return;

    if (line.startsWith('dsh:')) {
      final msg = line.replaceFirst(RegExp(r'^dsh:\s*'), '').trim();
      onErrorDetected?.call(msg);
      return;
    }

    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = json['event'] as String?;
      final type = json['type'] as String?;

      // DeepSeek Harness JSON events
      if (type == 'delta') {
        final text = json['text'] as String?;
        if (text != null && text.isNotEmpty) {
          onDeltaText(text);
          return;
        }
      } else if (type == 'final') {
        final text = json['text'] as String?;
        if (!hasStreamedText && text != null && text.isNotEmpty) {
          onDeltaText(text);
        }
        return;
      } else if (type == 'status') {
        final phase = json['phase'] as String?;
        if (phase == 'turn_end') {
          final reason = json['reason'] as Map<String, dynamic>?;
          if (reason?['kind'] == 'error') {
            final err = reason?['error'] as Map<String, dynamic>?;
            final msg = err?['message']?.toString() ?? 'Ошибка DeepSeek Harness';
            onErrorDetected?.call(msg);
          }
        }
        return;
      }

      // Claude Code / Antigravity error detection
      if (json['is_error'] == true || json['error'] != null) {
        final err = json['error']?.toString() ?? json['result']?.toString() ?? 'Ошибка выполнения';
        if (err.contains('Not logged in') || err.contains('authentication_failed')) {
          onErrorDetected?.call('Не выполнен вход в Claude Code. Укажите API ключ Anthropic/OpenRouter или выполните вход.');
        } else if (err.contains('rate_limit') || err.contains('429')) {
          onErrorDetected?.call('Превышен лимит запросов (Rate Limit 429). Повторите через минуту или смените модель.');
        } else {
          onErrorDetected?.call(err);
        }
      }

      if (json['subtype'] == 'api_retry') {
        final status = json['error_status'];
        if (status == 429) {
          onErrorDetected?.call('Модель перегружена (429 Rate Limit). Ожидание ответа...');
        }
      }

      if (event == 'step_update') {
        final step = json['step_update'] as Map<String, dynamic>?;
        if (step != null) {
          final delta = step['text_delta'] as String?;
          if (delta != null && delta.isNotEmpty) {
            onDeltaText(delta);
            return;
          }

          final stepType = (step['step_type'] as String? ?? '').toLowerCase();
          if (stepType.contains('tool') || stepType.contains('command')) {
            final rawName = (step['tool_name'] as String? ??
                (step['tool_info'] as Map<String, dynamic>?)?['name'] as String? ??
                'Tool');
            final name = _mapToolDisplayName(rawName);
            final info = step['tool_info'] as Map<String, dynamic>?;
            final params = info?['parameters'] as Map<String, dynamic>?;

            final targetFile = params?['TargetFile'] as String? ??
                params?['AbsolutePath'] as String? ??
                params?['path'] as String? ??
                params?['file'] as String?;
            final instruction = params?['Instruction'] as String? ??
                params?['Description'] as String? ??
                step['description'] as String?;
            final targetContent = params?['TargetContent'] as String?;
            final replacementContent = params?['ReplacementContent'] as String? ??
                params?['CodeContent'] as String?;
            final output = info?['output']?.toString();

            final detail = _extractToolDetail(step, rawName, targetFile: targetFile, instruction: instruction);
            final state = step['state'] as String? ?? '';
            final isDone = state == 'DONE';

            onActivity(ActivityItem(
              title: name,
              detail: detail.isNotEmpty ? detail : name,
              isComplete: isDone,
              isCommand: rawName.toLowerCase() == 'run_command' || rawName.toLowerCase() == 'bash',
              targetFile: targetFile,
              instruction: instruction,
              targetContent: targetContent,
              replacementContent: replacementContent,
              output: output,
            ));
          }
        }
      } else if (event == 'result' || type == 'result') {
        final result = (json['result'] as Map<String, dynamic>?) ?? json;
        final response = result['response'] as String? ?? (json['result'] is String ? json['result'] as String : null);
        if (response != null && response.isNotEmpty) {
          // If streaming already delivered the text, do not duplicate it!
          if (!hasStreamedText) {
            onDeltaText(response);
          }
        }
        final usage = (result['usage'] ?? json['usage']) as Map<String, dynamic>?;
        if (usage != null && onUsage != null) {
          onUsage(usage);
        }
      } else if (json.containsKey('delta')) {
        final delta = json['delta'] as Map<String, dynamic>?;
        if (delta != null) {
          final text = delta['text'] as String?;
          if (text != null && text.isNotEmpty) onDeltaText(text);

          final thinking = delta['thinking'] as String?;
          if (thinking != null) onThinking(thinking);
        }
      } else if (json.containsKey('tool_use')) {
        final tool = json['tool_use'] as Map<String, dynamic>;
        final toolName = tool['name'] as String? ?? 'Tool';
        final input = tool['input']?.toString() ?? '';
        onActivity(ActivityItem(
          title: _mapToolDisplayName(toolName),
          detail: input,
          isComplete: false,
          isCommand: toolName.toLowerCase() == 'bash',
        ));
      }
    } catch (_) {
      // Plain text stream output
      if (line.startsWith('Think:') || line.startsWith('Reasoning:')) {
        onThinking(line.replaceFirst(RegExp(r'^(Think|Reasoning):\s*'), ''));
      } else if (line.startsWith('Tool:') || line.startsWith('Run:')) {
        onActivity(ActivityItem(
          title: 'Bash',
          detail: line,
          isComplete: true,
          isCommand: true,
        ));
      } else if (!line.startsWith('{')) {
        onDeltaText('$line\n');
      }
    }
  }

  String _mapToolDisplayName(String name) {
    switch (name.toLowerCase()) {
      case 'run_command':
      case 'bash':
        return 'Bash';
      case 'write_to_file':
      case 'replace_file_content':
      case 'multi_replace_file_content':
      case 'write':
      case 'edit':
        return 'Write';
      case 'view_file':
      case 'read':
        return 'Read';
      case 'list_dir':
        return 'List files';
      case 'grep_search':
      case 'search_files':
      case 'grep':
      case 'glob':
        return 'Search';
      default:
        return name.replaceAll('_', ' ').replaceFirstChar((c) => c.toUpperCase());
    }
  }

  String _extractToolDetail(
    Map<String, dynamic> step,
    String rawName, {
    String? targetFile,
    String? instruction,
  }) {
    if (targetFile != null && targetFile.isNotEmpty) {
      final fileName = targetFile.split('/').last;
      if (instruction != null && instruction.isNotEmpty) {
        return '$fileName · $instruction';
      }
      return fileName;
    }

    final desc = step['description'] as String?;
    if (desc != null && desc.isNotEmpty) return desc;

    final info = step['tool_info'] as Map<String, dynamic>?;
    final params = info?['parameters'] as Map<String, dynamic>?;

    if (params != null) {
      for (final key in ['CommandLine', 'command', 'cmd', 'TargetFile', 'AbsolutePath', 'path', 'file', 'Query', 'Pattern']) {
        if (params.containsKey(key) && params[key] != null) {
          final val = params[key].toString();
          return val.length > 120 ? '${val.substring(0, 117)}...' : val;
        }
      }
      return params.toString();
    }
    return '';
  }

  List<String> _buildCommand(AgentKind kind, String prompt, String? model, {bool isGeminiCli = false, String projectPath = ''}) {
    final workspacePrompt = projectPath.isNotEmpty
        ? '<project_workspace>\n'
          'The active project workspace is $projectPath.\n'
          'Create, edit, read, run, and build project files directly in this directory.\n'
          'Do not create project output under scratch or outer directories.\n'
          'When giving commands to the user, make them runnable from this project root.\n'
          '</project_workspace>\n\n$prompt'
        : prompt;

    switch (kind) {
      case AgentKind.native:
        return [];
      case AgentKind.antigravity:
        if (isGeminiCli) {
          final args = ['-p', workspacePrompt, '-y', '--approval-mode', 'yolo'];
          if (model != null && model.isNotEmpty) {
            args.addAll(['-m', model]);
          }
          return args;
        } else {
          final args = [
            '--dangerously-skip-permissions',
            '--output-format',
            'stream-json',
            '--print-timeout',
            '60m',
            '-p',
            workspacePrompt,
          ];
          if (projectPath.isNotEmpty) {
            args.addAll(['--add-dir', projectPath]);
          }
          if (model != null && model.isNotEmpty) {
            args.addAll(['--model', model]);
          }
          return args;
        }

      case AgentKind.claudeCode:
        final args = [
          '--bare',
          '--dangerously-skip-permissions',
          '-p',
          workspacePrompt,
          '--output-format',
          'stream-json',
          '--verbose',
        ];
        if (model != null && model.isNotEmpty && (model.startsWith('claude-') || model == 'default')) {
          args.addAll(['--model', model]);
        }
        return args;

      case AgentKind.deepseekHarness:
        return ['--profile', 'headless', '--json', workspacePrompt];
    }
  }

  String _getInstallCommand(AgentKind kind) {
    switch (kind) {
      case AgentKind.native:
        return 'echo "Native Agent is built-in"';
      case AgentKind.claudeCode:
        return 'npm install -g @anthropic-ai/claude-code';
      case AgentKind.antigravity:
        return 'npm install -g @google/antigravity-cli || npm install -g @google/gemini-cli';
      case AgentKind.deepseekHarness:
        return 'pip install --break-system-packages deepseek-harness || pipx install deepseek-harness';
    }
  }

  void stopActiveSession() {
    _isStopping = true;
    try {
      _stdoutSub?.cancel();
      _stderrSub?.cancel();
      _activeProcess?.kill(ProcessSignal.sigterm);
      _activeProcess?.kill(ProcessSignal.sigkill);
    } catch (_) {}
    _activeProcess = null;
  }
}

extension StringExtension on String {
  String replaceFirstChar(String Function(String) transform) {
    if (isEmpty) return this;
    return transform(this[0]) + substring(1);
  }
}
