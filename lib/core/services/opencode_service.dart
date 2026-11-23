import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';

enum OpenCodeServerStatus { stopped, installing, starting, running, error }

class OpenCodeSlashCommand {
  final String name;
  final String description;
  final bool isBuiltin;

  const OpenCodeSlashCommand({
    required this.name,
    required this.description,
    this.isBuiltin = false,
  });
}

class OpenCodeMessageResponse {
  final String text;
  final String reasoning;
  final List<RoxumToolCallRecord> toolCalls;
  final RoxumUsageStats usage;

  const OpenCodeMessageResponse({
    required this.text,
    this.reasoning = '',
    this.toolCalls = const [],
    this.usage = const RoxumUsageStats(),
  });
}

class OpenCodeState {
  final OpenCodeServerStatus status;
  final bool isInstalled;
  final String baseUrl;
  final String statusMessage;
  final List<OpenCodeSlashCommand> commands;
  final Map<String, String> mcpStatuses;
  final String? configPath;

  const OpenCodeState({
    this.status = OpenCodeServerStatus.stopped,
    this.isInstalled = false,
    this.baseUrl = 'http://127.0.0.1:4096',
    this.statusMessage = 'Остановлен',
    this.commands = defaultSlashCommands,
    this.mcpStatuses = const {},
    this.configPath,
  });

  bool get isRunning => status == OpenCodeServerStatus.running;
  bool get isBusy =>
      status == OpenCodeServerStatus.installing ||
      status == OpenCodeServerStatus.starting;

  static const List<OpenCodeSlashCommand> defaultSlashCommands = [
    OpenCodeSlashCommand(
      name: 'compact',
      description: 'Сжать историю сессии и освободить токены',
      isBuiltin: true,
    ),
    OpenCodeSlashCommand(
      name: 'undo',
      description: 'Откатить последние правки файлов агента',
      isBuiltin: true,
    ),
    OpenCodeSlashCommand(
      name: 'redo',
      description: 'Вернуть отменённые правки файлов',
      isBuiltin: true,
    ),
    OpenCodeSlashCommand(
      name: 'diff',
      description: 'Показать все изменения файлов в текущей сессии',
      isBuiltin: true,
    ),
    OpenCodeSlashCommand(
      name: 'init',
      description: 'Проанализировать проект и создать AGENTS.md',
      isBuiltin: true,
    ),
    OpenCodeSlashCommand(
      name: 'new',
      description: 'Начать новый чистый чат OpenCode',
      isBuiltin: true,
    ),
  ];

  OpenCodeState copyWith({
    OpenCodeServerStatus? status,
    bool? isInstalled,
    String? baseUrl,
    String? statusMessage,
    List<OpenCodeSlashCommand>? commands,
    Map<String, String>? mcpStatuses,
    String? configPath,
  }) {
    return OpenCodeState(
      status: status ?? this.status,
      isInstalled: isInstalled ?? this.isInstalled,
      baseUrl: baseUrl ?? this.baseUrl,
      statusMessage: statusMessage ?? this.statusMessage,
      commands: commands ?? this.commands,
      mcpStatuses: mcpStatuses ?? this.mcpStatuses,
      configPath: configPath ?? this.configPath,
    );
  }
}

/// Manages the local OpenCode server (`opencode serve --hostname 127.0.0.1 --port 4096`),
/// auto-syncs `opencode.json` (providers + MCP servers), and communicates via REST/SSE
/// directly inside QuantumIDE's Flutter chat UI.
class OpenCodeService extends StateNotifier<OpenCodeState> {
  final Ref _ref;
  static const int defaultPort = 4096;

  OpenCodeService(this._ref) : super(const OpenCodeState());

  Future<bool> checkInstalled() async {
    final runtime = _ref.read(runtimeServiceProvider);
    final res = await runtime.runCommandDetailed(
      'export PATH="\$HOME/.opencode/bin:\$HOME/.local/bin:\$PATH"; '
      'command -v opencode 2>/dev/null || [ -x "\$HOME/.opencode/bin/opencode" ] && echo ok || true',
      timeout: const Duration(seconds: 8),
    );
    final found = res.stdout.trim().isNotEmpty;
    state = state.copyWith(isInstalled: found);
    return found;
  }

  /// Installs OpenCode CLI into the active Linux runtime (works in Native ARM64 & Ubuntu PRoot).
  Future<bool> installOpenCode() async {
    state = state.copyWith(
      status: OpenCodeServerStatus.installing,
      statusMessage: 'Установка OpenCode CLI...',
    );
    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommandDetailed(
        'export PATH="\$HOME/.opencode/bin:\$HOME/.local/bin:\$PATH"; '
        'if command -v npm >/dev/null 2>&1; then '
        '  npm install -g opencode-ai@latest 2>&1; '
        'elif command -v curl >/dev/null 2>&1; then '
        '  curl -fsSL https://opencode.ai/install | bash 2>&1; '
        'else '
        '  echo "ERROR: neither npm nor curl found"; exit 1; '
        'fi',
        timeout: const Duration(minutes: 4),
      );
      final installed = await checkInstalled();
      if (installed) {
        state = state.copyWith(
          status: OpenCodeServerStatus.stopped,
          isInstalled: true,
          statusMessage: 'OpenCode установлен и готов к запуску',
        );
        return true;
      }
      final tail = res.combined.trim();
      final shortErr = tail.length > 220
          ? tail.substring(tail.length - 220)
          : tail;
      state = state.copyWith(
        status: OpenCodeServerStatus.error,
        statusMessage: 'Не удалось установить OpenCode: $shortErr',
      );
      return false;
    } catch (e) {
      TalkerService.error('OpenCodeService.installOpenCode failed', e);
      state = state.copyWith(
        status: OpenCodeServerStatus.error,
        statusMessage: 'Ошибка установки: $e',
      );
      return false;
    }
  }

  /// Generates or updates `opencode.json` in [workspace] (or app filesDir)
  /// with enabled MCP servers (such as `dart mcp-server`) while preserving user keys.
  Future<String> syncConfig({
    required String workspace,
    required SettingsState settings,
    required List<McpServerConfig> mcpServers,
  }) async {
    final runtime = _ref.read(runtimeServiceProvider);
    final baseDir = workspace.trim().isNotEmpty
        ? workspace.trim()
        : runtime.filesDir;
    final configFile = File(p.join(baseDir, 'opencode.json'));

    Map<String, dynamic> existing = {};
    if (await configFile.exists()) {
      try {
        final decoded = jsonDecode(await configFile.readAsString());
        if (decoded is Map) {
          existing = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    existing[r'$schema'] ??= 'https://opencode.ai/config.json';

    final mcpMap = existing['mcp'] is Map
        ? Map<String, dynamic>.from(existing['mcp'] as Map)
        : <String, dynamic>{};

    for (final s in mcpServers) {
      // Builtin QuantumIDE servers run in-process inside Dart; forward real stdio/sse MCPs
      if (s.command.startsWith('builtin:')) continue;
      if (s.type == McpServerType.stdio && s.command.isNotEmpty) {
        mcpMap[s.name] = {
          'type': 'local',
          'command': [s.command, ...s.args],
          'enabled': s.isEnabled,
          if (s.env.isNotEmpty) 'environment': s.env,
        };
      } else if (s.type == McpServerType.sse && s.url.isNotEmpty) {
        mcpMap[s.name] = {
          'type': 'remote',
          'url': s.url,
          'enabled': s.isEnabled,
        };
      }
    }
    if (mcpMap.isNotEmpty) {
      existing['mcp'] = mcpMap;
    }

    try {
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(existing),
        flush: true,
      );
    } catch (e) {
      debugPrint('OpenCodeService: Failed writing opencode.json: $e');
    }

    state = state.copyWith(configPath: configFile.path);
    return configFile.path;
  }

  Future<bool> _isHealthy() async {
    try {
      final res = await http
          .get(Uri.parse('${state.baseUrl}/config'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Starts `opencode serve --hostname 127.0.0.1 --port 4096` in background
  /// and loads available slash commands (`GET /command`) and MCP statuses (`GET /mcp`).
  Future<bool> startServer({required String workspace}) async {
    if (await _isHealthy()) {
      state = state.copyWith(
        status: OpenCodeServerStatus.running,
        isInstalled: true,
        statusMessage: 'Работает (127.0.0.1:$defaultPort)',
      );
      unawaited(refreshCapabilities());
      return true;
    }

    final settings = _ref.read(settingsProvider);
    final mcpServers = _ref.read(mcpServiceProvider);
    await syncConfig(
      workspace: workspace,
      settings: settings,
      mcpServers: mcpServers,
    );

    final installed = await checkInstalled();
    if (!installed) {
      final ok = await installOpenCode();
      if (!ok) return false;
    }

    state = state.copyWith(
      status: OpenCodeServerStatus.starting,
      statusMessage: 'Запуск локального сервера OpenCode...',
    );

    final runtime = _ref.read(runtimeServiceProvider);
    final envExports = StringBuffer(
      'export PATH="\$HOME/.opencode/bin:\$HOME/.local/bin:\$PATH"; ',
    );
    void addEnv(String key, String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      final safe = v.replaceAll("'", "'\"'\"'");
      envExports.write("export $key='$safe'; ");
    }

    addEnv('OPENROUTER_API_KEY', settings.openrouterApiKey);
    addEnv('GEMINI_API_KEY', settings.geminiApiKey);
    addEnv('GOOGLE_GENERATIVE_AI_API_KEY', settings.geminiApiKey);
    addEnv('OPENAI_API_KEY', settings.openaiApiKey);
    addEnv('ANTHROPIC_API_KEY', settings.anthropicApiKey);
    addEnv('DEEPSEEK_API_KEY', settings.deepseekApiKey);

    try {
      await runtime.runCommandDetailed(
        '${envExports.toString()}'
        'pkill -f "opencode serve" 2>/dev/null || true; '
        'nohup opencode serve --hostname 127.0.0.1 --port $defaultPort >/tmp/opencode_serve.log 2>&1 </dev/null &',
        workingDirectory: workspace.isNotEmpty ? workspace : null,
        timeout: const Duration(seconds: 10),
      );

      for (int i = 0; i < 16; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (await _isHealthy()) {
          state = state.copyWith(
            status: OpenCodeServerStatus.running,
            isInstalled: true,
            statusMessage: 'Работает (127.0.0.1:$defaultPort)',
          );
          unawaited(refreshCapabilities());
          return true;
        }
      }

      final logRes = await runtime.runCommandDetailed(
        'tail -n 20 /tmp/opencode_serve.log 2>/dev/null || true',
        timeout: const Duration(seconds: 4),
      );
      final errDetail = logRes.stdout.trim();
      state = state.copyWith(
        status: OpenCodeServerStatus.error,
        statusMessage: errDetail.isNotEmpty
            ? 'OpenCode не ответил на :$defaultPort:\n$errDetail'
            : 'OpenCode не запустился за 12 сек на 127.0.0.1:$defaultPort',
      );
      return false;
    } catch (e) {
      TalkerService.error('OpenCodeService.startServer failed', e);
      state = state.copyWith(
        status: OpenCodeServerStatus.error,
        statusMessage: 'Ошибка запуска OpenCode: $e',
      );
      return false;
    }
  }

  Future<void> stopServer() async {
    final runtime = _ref.read(runtimeServiceProvider);
    try {
      await runtime.runCommandDetailed(
        'pkill -f "opencode serve" 2>/dev/null || true',
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {}
    state = state.copyWith(
      status: OpenCodeServerStatus.stopped,
      statusMessage: 'Остановлен',
    );
  }

  /// Refreshes slash commands (`GET /command`) and MCP server statuses (`GET /mcp`).
  Future<void> refreshCapabilities() async {
    final mergedCommands = <String, OpenCodeSlashCommand>{
      for (final c in OpenCodeState.defaultSlashCommands) c.name: c,
    };
    try {
      final res = await http
          .get(Uri.parse('${state.baseUrl}/command'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final name = item['name']?.toString().trim() ?? '';
              final desc = item['description']?.toString().trim() ?? '';
              if (name.isNotEmpty) {
                mergedCommands[name] = OpenCodeSlashCommand(
                  name: name,
                  description: desc.isNotEmpty ? desc : 'Команда OpenCode /$name',
                );
              }
            }
          }
        }
      }
    } catch (_) {}

    final mcpMap = <String, String>{};
    try {
      final res = await http
          .get(Uri.parse('${state.baseUrl}/mcp'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              mcpMap[k.toString()] = v['status']?.toString() ?? 'unknown';
            } else {
              mcpMap[k.toString()] = v.toString();
            }
          });
        }
      }
    } catch (_) {}

    if (mounted) {
      state = state.copyWith(
        commands: mergedCommands.values.toList(),
        mcpStatuses: mcpMap,
      );
    }
  }

  Future<String?> createSession({String? title}) async {
    try {
      final res = await http
          .post(
            Uri.parse('${state.baseUrl}/session'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          return decoded['id']?.toString();
        }
      }
    } catch (e) {
      TalkerService.error('OpenCodeService.createSession error', e);
    }
    return null;
  }

  Future<void> deleteSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return;
    try {
      await http
          .delete(Uri.parse('${state.baseUrl}/session/$sessionId'))
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// Maps QuantumIDE's `selectedModelId` (e.g. `openrouter:deepseek/deepseek-chat`)
  /// into OpenCode's `{providerID, modelID}` pair.
  static ({String providerId, String modelId})? parseModelForOpenCode(
    String? selectedModelId,
  ) {
    final raw = selectedModelId?.trim() ?? '';
    if (raw.isEmpty) return null;
    final colonIdx = raw.indexOf(':');
    if (colonIdx > 0 && colonIdx < raw.length - 1) {
      var provider = raw.substring(0, colonIdx).toLowerCase();
      final model = raw.substring(colonIdx + 1);
      if (provider == 'gemini') provider = 'google';
      return (providerId: provider, modelId: model);
    }
    return null;
  }

  /// Sends a prompt to OpenCode session (`POST /session/:id/message`) and returns
  /// structured text, reasoning, tool calls, and token usage.
  Future<OpenCodeMessageResponse> sendMessage({
    required String sessionId,
    required String text,
    String? selectedModelId,
    String agentMode = 'build',
  }) async {
    final modelSpec = parseModelForOpenCode(selectedModelId);
    final body = <String, dynamic>{
      'agent': agentMode,
      if (modelSpec != null)
        'model': {
          'providerID': modelSpec.providerId,
          'modelID': modelSpec.modelId,
        },
      'parts': [
        {'type': 'text', 'text': text},
      ],
    };

    final res = await http
        .post(
          Uri.parse('${state.baseUrl}/session/$sessionId/message'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 6));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('OpenCode HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    return _parseOpenCodeMessage(decoded);
  }

  /// Executes a slash command (`/compact`, `/undo`, `/redo`, `/diff`, `/init`,
  /// or any custom `.opencode/command/*.md` command) against the OpenCode session.
  Future<OpenCodeMessageResponse> runSlashCommand({
    required String sessionId,
    required String command,
    String arguments = '',
    String? selectedModelId,
    String agentMode = 'build',
  }) async {
    final cmd = command.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase();
    final modelSpec = parseModelForOpenCode(selectedModelId);

    if (cmd == 'compact') {
      final res = await http
          .post(
            Uri.parse('${state.baseUrl}/session/$sessionId/summarize'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (modelSpec != null) 'providerID': modelSpec.providerId,
              if (modelSpec != null) 'modelID': modelSpec.modelId,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return const OpenCodeMessageResponse(
          text: '✅ Контекст сессии OpenCode успешно сжат (`/compact`).',
        );
      }
      throw Exception('Ошибка /compact (${res.statusCode}): ${res.body}');
    }

    if (cmd == 'undo') {
      final res = await http
          .post(
            Uri.parse('${state.baseUrl}/session/$sessionId/revert'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(const {}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return const OpenCodeMessageResponse(
          text: '↩️ Последние изменения файлов откатаны (`/undo`).',
        );
      }
      throw Exception('Ошибка /undo (${res.statusCode}): ${res.body}');
    }

    if (cmd == 'redo') {
      final res = await http
          .post(
            Uri.parse('${state.baseUrl}/session/$sessionId/unrevert'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(const {}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return const OpenCodeMessageResponse(
          text: '↪️ Отменённые изменения возвращены (`/redo`).',
        );
      }
      throw Exception('Ошибка /redo (${res.statusCode}): ${res.body}');
    }

    if (cmd == 'diff') {
      final res = await http
          .get(Uri.parse('${state.baseUrl}/session/$sessionId/diff'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final bodyStr = res.body.trim();
        return OpenCodeMessageResponse(
          text: bodyStr.isEmpty || bodyStr == '[]'
              ? 'Нет изменённых файлов в текущей сессии OpenCode.'
              : '```diff\n$bodyStr\n```',
        );
      }
      throw Exception('Ошибка /diff (${res.statusCode}): ${res.body}');
    }

    // Standard OpenCode /command endpoint (/init, /review, custom .opencode/command/*.md)
    final res = await http
        .post(
          Uri.parse('${state.baseUrl}/session/$sessionId/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'command': cmd,
            'arguments': arguments,
            'agent': agentMode,
            if (modelSpec != null)
              'model': '${modelSpec.providerId}/${modelSpec.modelId}',
          }),
        )
        .timeout(const Duration(minutes: 6));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('OpenCode /$cmd HTTP ${res.statusCode}: ${res.body}');
    }
    return _parseOpenCodeMessage(jsonDecode(res.body));
  }

  static OpenCodeMessageResponse _parseOpenCodeMessage(dynamic decoded) {
    if (decoded is! Map) {
      return OpenCodeMessageResponse(text: decoded.toString());
    }
    final textBuf = StringBuffer();
    final reasonBuf = StringBuffer();
    final toolCalls = <RoxumToolCallRecord>[];

    final parts = decoded['parts'];
    if (parts is List) {
      for (final pItem in parts) {
        if (pItem is! Map) continue;
        final type = pItem['type']?.toString() ?? '';
        if (type == 'text') {
          final t = pItem['text']?.toString() ?? '';
          if (t.isNotEmpty) {
            if (textBuf.isNotEmpty) textBuf.writeln();
            textBuf.write(t);
          }
        } else if (type == 'reasoning') {
          final r = pItem['text']?.toString() ?? '';
          if (r.isNotEmpty) {
            if (reasonBuf.isNotEmpty) reasonBuf.writeln();
            reasonBuf.write(r);
          }
        } else if (type == 'tool' || type == 'tool-invocation') {
          final stateMap = pItem['state'] is Map
              ? Map<String, dynamic>.from(pItem['state'] as Map)
              : const <String, dynamic>{};
          final args = stateMap['input'] is Map
              ? Map<String, dynamic>.from(stateMap['input'] as Map)
              : const <String, dynamic>{};
          final out =
              stateMap['output']?.toString() ??
              stateMap['error']?.toString() ??
              '';
          final statusStr = stateMap['status']?.toString() ?? 'completed';
          toolCalls.add(
            RoxumToolCallRecord(
              id: pItem['callID']?.toString() ?? pItem['id']?.toString() ?? '',
              name: pItem['tool']?.toString() ?? 'opencode_tool',
              arguments: args,
              isRunning: false,
              success: statusStr != 'error',
              output: out,
            ),
          );
        }
      }
    }

    var promptTok = 0;
    var compTok = 0;
    var cost = 0.0;
    final info = decoded['info'];
    if (info is Map) {
      final tokens = info['tokens'];
      if (tokens is Map) {
        promptTok = (tokens['input'] as num?)?.toInt() ?? 0;
        compTok = (tokens['output'] as num?)?.toInt() ?? 0;
      }
      cost = (info['cost'] as num?)?.toDouble() ?? 0.0;
    }

    return OpenCodeMessageResponse(
      text: textBuf.toString().trim(),
      reasoning: reasonBuf.toString().trim(),
      toolCalls: toolCalls,
      usage: RoxumUsageStats(
        promptTokens: promptTok,
        completionTokens: compTok,
        totalTokens: promptTok + compTok,
        costUsd: cost,
      ),
    );
  }
}

final openCodeServiceProvider =
    StateNotifierProvider<OpenCodeService, OpenCodeState>((ref) {
      final service = OpenCodeService(ref);
      ref.onDispose(() {
        service.stopServer();
      });
      return service;
    });
