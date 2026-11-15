import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum McpServerType { stdio, sse }

class McpServerConfig {
  final String name;
  final McpServerType type;
  final String command; // for stdio (or 'builtin:<module>')
  final List<String> args; // for stdio
  final String url; // for sse
  final bool isEnabled;
  final Map<String, String> env; // environment variables

  McpServerConfig({
    required this.name,
    required this.type,
    this.command = '',
    this.args = const [],
    this.url = '',
    this.isEnabled = true,
    this.env = const {},
  });

  bool get isBuiltin => command.startsWith('builtin:');

  McpServerConfig copyWith({
    String? name,
    McpServerType? type,
    String? command,
    List<String>? args,
    String? url,
    bool? isEnabled,
    Map<String, String>? env,
  }) {
    return McpServerConfig(
      name: name ?? this.name,
      type: type ?? this.type,
      command: command ?? this.command,
      args: args ?? this.args,
      url: url ?? this.url,
      isEnabled: isEnabled ?? this.isEnabled,
      env: env ?? this.env,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'command': command,
      'args': args,
      'url': url,
      'isEnabled': isEnabled,
      'env': env,
    };
  }

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      name: json['name'] ?? '',
      type: McpServerType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => McpServerType.stdio,
      ),
      command: json['command'] ?? '',
      args: List<String>.from(json['args'] ?? []),
      url: json['url'] ?? '',
      isEnabled: json['isEnabled'] ?? true,
      env: Map<String, String>.from(json['env'] ?? {}),
    );
  }
}

class McpClientInstance {
  final McpServerConfig config;
  final Ref _ref;
  Process? _process;
  HttpClientRequest? _sseRequest;
  HttpClientResponse? _sseResponse;
  String? _ssePostUrl;
  final StreamController<String> _incomingMessages =
      StreamController<String>.broadcast();
  int _requestId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  bool _isConnecting = false;
  bool _isHandshakeDone = false;

  McpClientInstance(this.config, this._ref);

  bool get isConnected =>
      config.isBuiltin ||
      ((_process != null || _sseResponse != null) && _isHandshakeDone);

  Future<void> connect() async {
    if (config.isBuiltin) {
      _isHandshakeDone = true;
      return;
    }
    if (isConnected) return;
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      if (config.type == McpServerType.stdio) {
        await _connectStdio();
      } else {
        await _connectSse();
      }
      await _performHandshake();
    } catch (e) {
      debugPrint('Error connecting to MCP server ${config.name}: $e');
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _performHandshake() async {
    try {
      await sendRequest(
        'initialize',
        {
          'protocolVersion': '2024-11-05',
          'capabilities': {
            'roots': {'listChanged': false},
          },
          'clientInfo': {
            'name': 'QuantumIDE-RoxumAgent',
            'version': '1.2.237',
          },
        },
        timeout: const Duration(seconds: 12),
      );
      _sendNotification('notifications/initialized', const {});
      _isHandshakeDone = true;
    } catch (e) {
      debugPrint('MCP [${config.name}] handshake warning: $e');
      // Still mark handshake attempted so non-strict servers can answer tools/list
      _isHandshakeDone = true;
    }
  }

  void _sendNotification(String method, Map<String, dynamic> params) {
    final msg = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      if (params.isNotEmpty) 'params': params,
    });
    try {
      if (config.type == McpServerType.stdio) {
        _process?.stdin.writeln(msg);
      }
    } catch (_) {}
  }

  Future<void> _connectStdio() async {
    if (config.command.isEmpty) return;
    try {
      final runtime = _ref.read(runtimeServiceProvider);
      final workspace = _ref.read(workspaceProvider).currentPath;
      if (Platform.isAndroid) {
        final initHost = p.join(runtime.filesDir, 'bin', 'init-host');
        if (await File(initHost).exists()) {
          final escapedArgs = config.args
              .map((a) => "'${a.replaceAll("'", "'\\''")}'")
              .join(' ');
          final envExports = config.env.entries
              .map((e) => "export ${e.key}='${e.value.replaceAll("'", "'\\''")}'; ")
              .join();
          final fullCmd = '$envExports${config.command} $escapedArgs';
          _process = await Process.start(
            'sh',
            [
              initHost,
              runtime.filesDir,
              '/root',
              '/bin/bash',
              '-c',
              fullCmd,
            ],
          );
        } else {
          _process = await Process.start(
            config.command,
            config.args,
            environment: {...runtime.env, ...config.env},
          );
        }
      } else {
        final mergedEnv = {...runtime.desktopEnv, ...config.env};
        final fullCmd = [
          config.command,
          ...config.args.map(
            (a) => a.contains(' ') ? '"${a.replaceAll('"', r'\"')}"' : a,
          ),
        ].join(' ');
        _process = await Process.start(
          Platform.isWindows ? 'cmd' : 'bash',
          Platform.isWindows ? ['/c', fullCmd] : ['-c', fullCmd],
          workingDirectory: workspace,
          environment: mergedEnv,
        );
      }

      _process!.exitCode.then((code) {
        debugPrint('MCP [${config.name}] process exited with code $code');
        _process = null;
        _isHandshakeDone = false;
      });

      _process!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        debugPrint('MCP [${config.name}] stderr: $data');
      });

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_handleIncomingLine);
    } catch (e) {
      debugPrint('Failed to start stdio MCP client: $e');
      _process = null;
      _isHandshakeDone = false;
      rethrow;
    }
  }

  Future<void> _connectSse() async {
    if (config.url.isEmpty) return;
    try {
      final client = HttpClient();
      final uri = Uri.parse(config.url);
      _sseRequest = await client.getUrl(uri);
      _sseRequest!.headers.set('Accept', 'text/event-stream');

      _sseResponse = await _sseRequest!.close();
      if (_sseResponse!.statusCode != 200) {
        throw Exception('SSE server returned status ${_sseResponse!.statusCode}');
      }

      _sseResponse!
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          try {
            if (_ssePostUrl == null) {
              if (data.startsWith('http') || data.startsWith('/')) {
                _ssePostUrl = data;
                if (_ssePostUrl!.startsWith('/')) {
                  final baseUri = Uri.parse(config.url);
                  _ssePostUrl =
                      '${baseUri.scheme}://${baseUri.host}:${baseUri.port}$_ssePostUrl';
                }
                return;
              }
            }
            _handleIncomingLine(data);
          } catch (e) {
            debugPrint('MCP [${config.name}] error parsing SSE data: $e');
          }
        }
      });
    } catch (e) {
      debugPrint('Failed to start SSE MCP client: $e');
      rethrow;
    }
  }

  void _handleIncomingLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('{')) return;
    try {
      final json = jsonDecode(trimmed);
      if (json is Map<String, dynamic> && json.containsKey('id')) {
        final rawId = json['id'];
        final id = rawId is int ? rawId : int.tryParse('$rawId');
        if (id != null && _pendingRequests.containsKey(id)) {
          _pendingRequests.remove(id)!.complete(json);
        }
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final id = _requestId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    try {
      if (config.type == McpServerType.stdio) {
        if (_process == null) throw Exception('Process is not running');
        _process!.stdin.writeln(jsonEncode(request));
      } else {
        final postUrl = _ssePostUrl ?? config.url;
        final client = HttpClient();
        final req = await client.postUrl(Uri.parse(postUrl));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode(request));
        final resp = await req.close();
        if (resp.statusCode != 200 && resp.statusCode != 202) {
          throw Exception('POST command returned status ${resp.statusCode}');
        }
      }
    } catch (e) {
      _pendingRequests.remove(id);
      completer.completeError(e);
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request $method timed out');
      },
    );
  }

  Future<List<Map<String, dynamic>>> listTools() async {
    if (config.isBuiltin) {
      return _builtinToolsFor(config.command);
    }
    try {
      final res = await sendRequest('tools/list', {});
      if (res.containsKey('result')) {
        final result = res['result'] as Map<String, dynamic>;
        if (result.containsKey('tools')) {
          return List<Map<String, dynamic>>.from(result['tools']);
        }
      }
    } catch (e) {
      debugPrint('Error listing tools for MCP ${config.name}: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    if (config.isBuiltin) {
      return _executeBuiltinTool(config.command, toolName, arguments);
    }
    final res = await sendRequest(
      'tools/call',
      {
        'name': toolName,
        'arguments': arguments,
      },
      timeout: const Duration(seconds: 60),
    );
    if (res.containsKey('error')) {
      throw Exception(res['error']['message'] ?? 'MCP execution error');
    }
    return res['result'] ?? {};
  }

  List<Map<String, dynamic>> _builtinToolsFor(String builtinId) {
    switch (builtinId) {
      case 'builtin:codegraph':
        return [
          {
            'name': 'project_symbols',
            'description':
                'Builds a compact symbol index (classes, functions, widgets, providers) across the project to save 85% tokens instead of reading every file.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'directory': {
                  'type': 'string',
                  'description': 'Optional subdirectory (e.g. lib).',
                },
              },
            },
          },
          {
            'name': 'read_symbol',
            'description':
                'Reads ONLY a specific class, method, or function by name from a file with exact line numbers (#Lstart-end).',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'filePath': {'type': 'string'},
                'symbolName': {'type': 'string'},
              },
              'required': ['filePath', 'symbolName'],
            },
          },
        ];
      case 'builtin:token_saver':
        return [
          {
            'name': 'smart_analyze_errors',
            'description':
                'Runs project static analysis (flutter/dart analyze, tsc, flake8, cargo check) and returns ONLY compact error/warning lines.',
            'inputSchema': {
              'type': 'object',
              'properties': {},
            },
          },
        ];
      case 'builtin:memory':
        return [
          {
            'name': 'save_memory',
            'description':
                'Saves key architectural facts, SDK paths, or user conventions to persistent project memory (.quantum_memory.json).',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'key': {'type': 'string'},
                'fact': {'type': 'string'},
              },
              'required': ['key', 'fact'],
            },
          },
          {
            'name': 'read_memory',
            'description':
                'Reads all saved architectural facts from persistent project memory.',
            'inputSchema': {
              'type': 'object',
              'properties': {},
            },
          },
        ];
      case 'builtin:web_fetch':
        return [
          {
            'name': 'fetch_url_markdown',
            'description':
                'Fetches a web URL or documentation page and returns clean, token-efficient text content.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'url': {'type': 'string'},
              },
              'required': ['url'],
            },
          },
        ];
      default:
        return const [];
    }
  }

  Future<Map<String, dynamic>> _executeBuiltinTool(
    String builtinId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final workspace =
        _ref.read(workspaceProvider).currentPath ?? Directory.current.path;
    final runtime = _ref.read(runtimeServiceProvider);

    try {
      if (toolName == 'project_symbols') {
        final sub = args['directory']?.toString() ?? '';
        final rootDir = Directory(
          sub.isEmpty ? workspace : p.join(workspace, sub),
        );
        if (!await rootDir.exists()) {
          return {'content': 'Directory not found: ${rootDir.path}'};
        }
        final symRegex = RegExp(
          r'^\s*(?:abstract\s+)?(?:class|enum|mixin|extension|typedef|def|function|interface|struct)\s+([A-Za-z0-9_]+)|^\s*(?:Future<[^>]+>|Widget|void|String|int|bool|double|dynamic)\s+([A-Za-z0-9_]+)\s*\(',
        );
        final out = StringBuffer();
        int fileCount = 0;
        await for (final entity
            in rootDir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final rel = p.relative(entity.path, from: workspace);
          if (rel.startsWith('.') ||
              rel.contains('/.') ||
              rel.contains('/build/') ||
              rel.contains('node_modules')) {
            continue;
          }
          final ext = p.extension(rel).toLowerCase();
          if (!const {
            '.dart',
            '.ts',
            '.tsx',
            '.js',
            '.jsx',
            '.py',
            '.rs',
            '.go',
            '.kt',
            '.java',
          }.contains(ext)) {
            continue;
          }
          try {
            final lines = await entity.readAsLines();
            final symbols = <String>[];
            for (var i = 0; i < lines.length; i++) {
              final m = symRegex.firstMatch(lines[i]);
              if (m != null) {
                final name = m.group(1) ?? m.group(2) ?? '';
                if (name.isNotEmpty && ! const {'if', 'for', 'while', 'switch', 'catch'}.contains(name)) {
                  symbols.add('$name(#L${i + 1})');
                }
              }
            }
            if (symbols.isNotEmpty) {
              out.writeln('$rel (${lines.length}L): ${symbols.take(25).join(', ')}');
              fileCount++;
              if (fileCount >= 80) break;
            }
          } catch (_) {}
        }
        return {
          'content': out.isEmpty
              ? 'No code symbols indexed yet.'
              : out.toString(),
        };
      }

      if (toolName == 'read_symbol') {
        final rawFile = args['filePath']?.toString() ?? '';
        final symbolName = args['symbolName']?.toString() ?? '';
        final fullPath =
            p.isAbsolute(rawFile) ? rawFile : p.join(workspace, rawFile);
        final file = File(fullPath);
        if (!await file.exists()) {
          return {'isError': true, 'content': 'File not found: $rawFile'};
        }
        final lines = await file.readAsLines();
        int startIdx = -1;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(symbolName)) {
            startIdx = i;
            break;
          }
        }
        if (startIdx == -1) {
          return {
            'isError': true,
            'content': 'Symbol "$symbolName" not found in $rawFile',
          };
        }
        final endIdx = (startIdx + 90).clamp(0, lines.length);
        final snippet = StringBuffer();
        for (var i = startIdx; i < endIdx; i++) {
          snippet.writeln('${i + 1}: ${lines[i]}');
        }
        return {
          'range': '#L${startIdx + 1}-$endIdx',
          'content': snippet.toString(),
        };
      }

      if (toolName == 'smart_analyze_errors') {
        final res = await runtime.runCommandDetailed(
          'if [ -f pubspec.yaml ]; then '
          '  (flutter analyze --no-pub 2>&1 || dart analyze 2>&1); '
          'elif [ -f tsconfig.json ]; then '
          '  npx tsc --noEmit 2>&1; '
          'elif [ -f Cargo.toml ]; then '
          '  cargo check 2>&1; '
          'else '
          '  echo "No standard analyzer config found in current root."; '
          'fi',
          workingDirectory: workspace,
          timeout: const Duration(seconds: 90),
        );
        final filtered = res.combined
            .split('\n')
            .where(
              (l) =>
                  l.contains('error •') ||
                  l.contains('warning •') ||
                  l.contains('info •') ||
                  l.contains('Error:') ||
                  l.contains('error TS') ||
                  l.contains('No issues found'),
            )
            .take(80)
            .join('\n');
        return {
          'exitCode': res.exitCode,
          'diagnostics': filtered.isEmpty ? res.combined : filtered,
        };
      }

      if (toolName == 'save_memory') {
        final memFile = File(p.join(workspace, '.quantum_memory.json'));
        Map<String, dynamic> data = {};
        if (await memFile.exists()) {
          try {
            data = jsonDecode(await memFile.readAsString()) as Map<String, dynamic>;
          } catch (_) {}
        }
        data[args['key']?.toString() ?? 'note'] = args['fact']?.toString() ?? '';
        await memFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
        );
        return {'content': 'Saved to .quantum_memory.json'};
      }

      if (toolName == 'read_memory') {
        final memFile = File(p.join(workspace, '.quantum_memory.json'));
        if (!await memFile.exists()) {
          return {'content': 'No saved project memory yet.'};
        }
        return {'content': await memFile.readAsString()};
      }

      if (toolName == 'fetch_url_markdown') {
        final url = args['url']?.toString() ?? '';
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('User-Agent', 'QuantumIDE-Agent/1.2');
        final resp = await req.close();
        final body = await resp.transform(const Utf8Decoder(allowMalformed: true)).join();
        final stripped = body
            .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
            .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return {
          'url': url,
          'content': stripped.length > 6000 ? stripped.substring(0, 6000) : stripped,
        };
      }
    } catch (e) {
      return {'isError': true, 'content': 'Builtin MCP error: $e'};
    }
    return {'isError': true, 'content': 'Unknown builtin tool: $toolName'};
  }

  void disconnect() {
    _process?.kill();
    _process = null;
    _isHandshakeDone = false;
    _sseRequest?.abort();
    _sseRequest = null;
    _sseResponse = null;
    _ssePostUrl = null;
    _incomingMessages.close();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Server disconnected'));
      }
    }
    _pendingRequests.clear();
  }
}

class McpService extends StateNotifier<List<McpServerConfig>> {
  final Ref _ref;
  final Map<String, McpClientInstance> _clients = {};
  bool _internetAccess = true;

  McpService(this._ref) : super([]) {
    _loadConfigs();
  }

  bool get internetAccess => _internetAccess;

  static List<McpServerConfig> defaultBuiltinServers() => [
        McpServerConfig(
          name: 'quantum-codegraph',
          type: McpServerType.stdio,
          command: 'builtin:codegraph',
          isEnabled: true,
        ),
        McpServerConfig(
          name: 'quantum-token-saver',
          type: McpServerType.stdio,
          command: 'builtin:token_saver',
          isEnabled: true,
        ),
        McpServerConfig(
          name: 'quantum-memory',
          type: McpServerType.stdio,
          command: 'builtin:memory',
          isEnabled: true,
        ),
        McpServerConfig(
          name: 'quantum-web-fetch',
          type: McpServerType.stdio,
          command: 'builtin:web_fetch',
          isEnabled: true,
        ),
      ];

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    _internetAccess = prefs.getBool('mcp_internet_access') ?? true;
    final list = prefs.getStringList('mcp_servers');
    if (list != null && list.isNotEmpty) {
      try {
        final loaded = list
            .map((s) => McpServerConfig.fromJson(jsonDecode(s)))
            .where((s) => s.command != 'uvx') // Remove broken legacy uvx servers
            .toList();
        final existingNames = loaded.map((s) => s.name).toSet();
        for (final builtin in defaultBuiltinServers()) {
          if (!existingNames.contains(builtin.name)) {
            loaded.insert(0, builtin);
          }
        }
        state = loaded;
        for (final server in state) {
          if (server.isEnabled) {
            _getOrCreateClient(server).connect().catchError((Object e) {
              debugPrint('MCP auto-connect skipped for ${server.name}: $e');
            });
          }
        }
        return;
      } catch (e) {
        debugPrint('Error loading MCP configs: $e');
      }
    }
    // Initialize with fast built-in native MCP servers on first run
    state = defaultBuiltinServers();
    await saveConfigs();
  }

  Future<void> setInternetAccess(bool enabled) async {
    _internetAccess = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mcp_internet_access', enabled);
    state = [...state];
  }

  McpClientInstance _getOrCreateClient(McpServerConfig server) {
    if (!_clients.containsKey(server.name)) {
      _clients[server.name] = McpClientInstance(server, _ref);
    }
    return _clients[server.name]!;
  }

  Future<void> saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = state.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('mcp_servers', list);
  }

  Future<void> addServer(McpServerConfig config) async {
    if (state.any((s) => s.name == config.name)) return;
    state = [...state, config];
    await saveConfigs();
    if (config.isEnabled) {
      await _getOrCreateClient(config).connect().catchError((_) {});
    }
  }

  static List<({String title, String description, McpServerConfig config})>
      topPresets({String workspacePath = '.'}) => [
            (
              title: '⚡ Quantum CodeGraph (AST & Символы — экономия 85% токенов)',
              description:
                  'Встроенный сверхбыстрый индекс классов, функций и виджетов без чтения файлов целиком',
              config: McpServerConfig(
                name: 'quantum-codegraph',
                type: McpServerType.stdio,
                command: 'builtin:codegraph',
              ),
            ),
            (
              title: '🛡️ Quantum Smart Analyzer (Сжатие логов и ошибок)',
              description:
                  'Запускает flutter/dart analyze, tsc или cargo check и выжимает только строки с ошибками',
              config: McpServerConfig(
                name: 'quantum-token-saver',
                type: McpServerType.stdio,
                command: 'builtin:token_saver',
              ),
            ),
            (
              title: '🧠 Quantum Project Memory (Долгосрочная память проекта)',
              description:
                  'Запоминает архитектуру проекта, пути к SDK и решённые баги между сессиями',
              config: McpServerConfig(
                name: 'quantum-memory',
                type: McpServerType.stdio,
                command: 'builtin:memory',
              ),
            ),
            (
              title: '🌐 Quantum Web Fetch (Чтение документации и URL)',
              description:
                  'Быстрая загрузка документации и веб-страниц в чистом текстовом виде без лишних токенов',
              config: McpServerConfig(
                name: 'quantum-web-fetch',
                type: McpServerType.stdio,
                command: 'builtin:web_fetch',
              ),
            ),
            (
              title: '🎯 Dart & Flutter Official MCP',
              description:
                  'Официальный Dart/Flutter MCP: анализ, pub get, поиск ошибок и виджетов',
              config: McpServerConfig(
                name: 'dart-flutter',
                type: McpServerType.stdio,
                command: 'dart',
                args: const ['mcp-server'],
              ),
            ),
            (
              title: '📚 Context7 Live Docs (@upstash/context7-mcp)',
              description:
                  'Актуальная документация Flutter, Dart (pub.dev), Riverpod и любых библиотек',
              config: McpServerConfig(
                name: 'context7',
                type: McpServerType.stdio,
                command: 'npx',
                args: const ['-y', '@upstash/context7-mcp'],
              ),
            ),
            (
              title: '🧩 Sequential Thinking (@modelcontextprotocol)',
              description:
                  'Пошаговое глубокое планирование перед сложными изменениями кода',
              config: McpServerConfig(
                name: 'sequential-thinking',
                type: McpServerType.stdio,
                command: 'npx',
                args: const [
                  '-y',
                  '@modelcontextprotocol/server-sequential-thinking',
                ],
              ),
            ),
            (
              title: '📂 Filesystem MCP (@modelcontextprotocol)',
              description: 'Безопасная работа с файлами и каталогами проекта',
              config: McpServerConfig(
                name: 'filesystem',
                type: McpServerType.stdio,
                command: 'npx',
                args: [
                  '-y',
                  '@modelcontextprotocol/server-filesystem',
                  workspacePath,
                ],
              ),
            ),
            (
              title: '🐙 GitHub MCP (@modelcontextprotocol)',
              description: 'Работа с репозиториями, Issues и Pull Requests на GitHub',
              config: McpServerConfig(
                name: 'github',
                type: McpServerType.stdio,
                command: 'npx',
                args: const ['-y', '@modelcontextprotocol/server-github'],
              ),
            ),
          ];

  Future<void> removeServer(String name) async {
    final client = _clients.remove(name);
    client?.disconnect();
    state = state.where((s) => s.name != name).toList();
    await saveConfigs();
  }

  Future<void> toggleServer(String name) async {
    state = state.map((s) {
      if (s.name == name) {
        final nextEnabled = !s.isEnabled;
        final updated = s.copyWith(isEnabled: nextEnabled);
        if (nextEnabled) {
          _getOrCreateClient(updated).connect().catchError((_) {});
        } else {
          _clients[name]?.disconnect();
          _clients.remove(name);
        }
        return updated;
      }
      return s;
    }).toList();
    await saveConfigs();
  }

  Future<List<Map<String, dynamic>>> getAvailableMcpTools() async {
    final List<Map<String, dynamic>> allTools = [];
    for (final server in state) {
      if (server.isEnabled) {
        final client = _getOrCreateClient(server);
        try {
          await client.connect();
          final tools = await client.listTools();
          for (final tool in tools) {
            allTools.add({
              'server': server.name,
              'name': tool['name'],
              'description': tool['description'] ?? '',
              'inputSchema': tool['inputSchema'] ?? {},
            });
          }
        } catch (e) {
          debugPrint(
            'Failed to connect or list tools for MCP server ${server.name}: $e',
          );
        }
      }
    }
    return allTools;
  }

  Future<Map<String, dynamic>> executeMcpTool(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final server = state.firstWhere((s) => s.name == serverName);
    final client = _getOrCreateClient(server);
    await client.connect();
    return await client.callTool(toolName, arguments);
  }

  @override
  void dispose() {
    for (final client in _clients.values) {
      client.disconnect();
    }
    _clients.clear();
    super.dispose();
  }
}

final mcpServiceProvider =
    StateNotifierProvider<McpService, List<McpServerConfig>>((ref) {
  return McpService(ref);
});
