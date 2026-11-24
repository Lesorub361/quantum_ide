import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/adb_device_service.dart';
import 'package:quantum_ide/core/services/android_app_installer_service.dart';
import 'package:quantum_ide/core/services/android_build_diagnostics_service.dart';
import 'package:quantum_ide/core/services/build_progress_tracker.dart';
import 'package:quantum_ide/core/services/build_resource_optimizer.dart';
import 'package:quantum_ide/core/services/ghost_qa_service.dart';
import 'package:quantum_ide/core/services/network_inspector_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/shizuku_bridge.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

enum McpServerType { stdio, sse }

enum McpCategory {
  architecture,
  diagnostics,
  build,
  devices,
  memory,
  web,
  data,
}

extension McpCategoryLabel on McpCategory {
  String get label => switch (this) {
    McpCategory.architecture => 'Архитектура и навигация по коду',
    McpCategory.diagnostics => 'Диагностика и качество',
    McpCategory.build => 'Сборка и зависимости',
    McpCategory.devices => 'Устройства и runtime',
    McpCategory.memory => 'Память проекта',
    McpCategory.web => 'Документация и веб',
    McpCategory.data => 'Данные и телеметрия',
  };
}

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
  List<Map<String, dynamic>>? _cachedTools;

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
      await sendRequest('initialize', {
        'protocolVersion': '2024-11-05',
        'capabilities': {
          'roots': {'listChanged': false},
        },
        'clientInfo': {'name': 'QuantumIDE-RoxumAgent', 'version': '1.2.304'},
      }, timeout: const Duration(seconds: 12));
      await _sendNotification('notifications/initialized', const {});
      _isHandshakeDone = true;
    } catch (e) {
      debugPrint('MCP [${config.name}] handshake warning: $e');
      // Still mark handshake attempted so non-strict servers can answer tools/list
      _isHandshakeDone = true;
    }
  }

  Future<void> _sendNotification(
    String method,
    Map<String, dynamic> params,
  ) async {
    final msg = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      if (params.isNotEmpty) 'params': params,
    });
    try {
      if (config.type == McpServerType.stdio) {
        _process?.stdin.writeln(msg);
      } else {
        final postUrl = _ssePostUrl ?? config.url;
        if (postUrl.isNotEmpty) {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 6);
          try {
            final req = await client.postUrl(Uri.parse(postUrl));
            req.headers.set('Content-Type', 'application/json');
            req.write(msg);
            final resp = await req.close();
            await resp.drain<void>();
          } finally {
            client.close(force: true);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _connectStdio() async {
    if (config.command.isEmpty) return;
    try {
      final runtime = _ref.read(runtimeServiceProvider);
      final workspace = _ref.read(workspaceProvider).currentPath;
      if (Platform.isAndroid) {
        final escapedArgs = config.args
            .map((a) => "'${a.replaceAll("'", "'\\''")}'")
            .join(' ');
        final envExports = config.env.entries
            .map(
              (e) => "export ${e.key}='${e.value.replaceAll("'", "'\\''")}'; ",
            )
            .join();
        final fullCmd = '$envExports${config.command} $escapedArgs';
        final initHost = p.join(runtime.filesDir, 'bin', 'init-host');
        if (runtime.useNativeRootMode) {
          final wd = (workspace != null && workspace.isNotEmpty)
              ? "cd '${workspace.replaceAll("'", "'\\''")}' 2>/dev/null; "
              : '';
          _process = await Process.start(
            'su',
            ['-c', '$wd$fullCmd'],
            environment: {...runtime.env, ...config.env},
          );
        } else if (await File(initHost).exists()) {
          final guestWorkDir = (workspace != null && workspace.isNotEmpty)
              ? runtime.toProotPath(workspace)
              : '/root';
          _process = await Process.start(
            'sh',
            [
              initHost,
              runtime.filesDir,
              guestWorkDir,
              '/bin/bash',
              '-c',
              fullCmd,
            ],
            environment: {...runtime.env, ...config.env},
          );
        } else {
          _process = await Process.start(
            config.command,
            config.args,
            workingDirectory: workspace,
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
        _cachedTools = null;
      });

      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
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
      _cachedTools = null;
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
        throw Exception(
          'SSE server returned status ${_sseResponse!.statusCode}',
        );
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
                    final baseUri = Uri.parse(config.url);
                    _ssePostUrl = baseUri.resolve(data).toString();
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
      if (json is! Map<String, dynamic>) return;
      if (json.containsKey('method') && json.containsKey('id')) {
        final method = json['method']?.toString() ?? '';
        final rawId = json['id'];
        if (method == 'roots/list') {
          final workspace = _ref.read(workspaceProvider).currentPath ?? '';
          final runtime = _ref.read(runtimeServiceProvider);
          final effectivePath = workspace.isNotEmpty
              ? (Platform.isAndroid ? runtime.toProotPath(workspace) : workspace)
              : '/root';
          final rootUri = Uri.file(effectivePath).toString();
          final resp = jsonEncode({
            'jsonrpc': '2.0',
            'id': rawId,
            'result': {
              'roots': [
                {'uri': rootUri, 'name': 'workspace'},
              ],
            },
          });
          if (config.type == McpServerType.stdio) {
            _process?.stdin.writeln(resp);
          }
          return;
        }
      }
      if (json.containsKey('id')) {
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

  Future<List<Map<String, dynamic>>> listTools({
    bool forceRefresh = false,
  }) async {
    if (config.isBuiltin) {
      return _builtinToolsFor(config.command);
    }
    if (!forceRefresh && _cachedTools != null && _cachedTools!.isNotEmpty) {
      return _cachedTools!;
    }
    try {
      final res = await sendRequest(
        'tools/list',
        {},
        timeout: const Duration(seconds: 10),
      );
      if (res.containsKey('result')) {
        final result = res['result'] as Map<String, dynamic>;
        if (result.containsKey('tools')) {
          final parsed = List<Map<String, dynamic>>.from(result['tools']);
          _cachedTools = parsed;
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('Error listing tools for MCP ${config.name}: $e');
    }
    return _cachedTools ?? [];
  }

  Future<Map<String, dynamic>> callTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    if (config.isBuiltin) {
      return _executeBuiltinTool(config.command, toolName, arguments);
    }
    final res = await sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    }, timeout: _toolTimeout(toolName));
    if (res.containsKey('error')) {
      throw Exception(res['error']['message'] ?? 'MCP execution error');
    }
    return res['result'] ?? {};
  }

  Duration _toolTimeout(String toolName) {
    final lower = toolName.toLowerCase();
    final longRunning =
        lower.contains('analy') ||
        lower.contains('test') ||
        lower.contains('build') ||
        lower.contains('pub') ||
        lower.contains('compile');
    return Duration(seconds: longRunning ? 90 : 30);
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
                'Reads ONLY a specific class, method, or function by name from a file with exact line numbers (#Lstart-end) and brace-balanced scope.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'filePath': {
                  'type': 'string',
                  'description': 'Relative or absolute path to the file.',
                },
                'symbolName': {
                  'type': 'string',
                  'description': 'Class, method, widget, or provider name.',
                },
              },
              'required': ['filePath', 'symbolName'],
            },
          },
          {
            'name': 'find_symbol_usages',
            'description':
                'Finds all references and usages of a symbol (class, method, provider, variable) across the workspace with file paths and line numbers.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'symbolName': {
                  'type': 'string',
                  'description': 'Exact symbol identifier to search for.',
                },
                'directory': {
                  'type': 'string',
                  'description': 'Optional subdirectory filter (e.g. lib).',
                },
              },
              'required': ['symbolName'],
            },
          },
          {
            'name': 'semantic_search_code',
            'description':
                'Performs BM25 semantic & keyword search across workspace symbols, file names, and code snippets via SymbolIndexerService.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': 'Natural language or identifier search query.',
                },
                'limit': {
                  'type': 'integer',
                  'description': 'Maximum results to return (default 15).',
                },
              },
              'required': ['query'],
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
              'properties': {
                'targetPath': {
                  'type': 'string',
                  'description':
                      'Optional specific file or directory to analyze.',
                },
              },
            },
          },
          {
            'name': 'scan_todos',
            'description':
                'Scans workspace source files for TODO, FIXME, BUG, HACK, and XXX markers with file paths and line numbers.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'filter': {
                  'type': 'string',
                  'description': 'Optional tag filter (e.g. FIXME, BUG, TODO).',
                },
              },
            },
          },
          {
            'name': 'run_tests',
            'description':
                'Runs project unit/widget tests (flutter test / dart test / npm test / pytest) and returns a compact pass/fail summary.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'testPath': {
                  'type': 'string',
                  'description': 'Optional specific test file path.',
                },
              },
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
                'Reads saved architectural facts from persistent project memory (.quantum_memory.json).',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'key': {
                  'type': 'string',
                  'description': 'Optional key filter.',
                },
              },
            },
          },
          {
            'name': 'delete_memory',
            'description':
                'Removes an outdated key from persistent project memory (.quantum_memory.json).',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'key': {'type': 'string'},
              },
              'required': ['key'],
            },
          },
        ];
      case 'builtin:web_fetch':
        return [
          {
            'name': 'fetch_url_markdown',
            'description':
                'Fetches a web URL or documentation page and returns clean, token-efficient Markdown/text content.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'url': {'type': 'string'},
              },
              'required': ['url'],
            },
          },
          {
            'name': 'web_search_docs',
            'description':
                'Searches the web and developer documentation (pub.dev, Flutter, npm, MDN, StackOverflow, GitHub) for a query.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string', 'description': 'Search query.'},
              },
              'required': ['query'],
            },
          },
        ];
      case 'builtin:build_doctor':
        return [
          {
            'name': 'get_build_diagnostics',
            'description':
                'Inspects the active/last build status, log tail, structured Gradle/Kotlin/AAPT2/NDK build issues with fix suggestions, and locates built APK outputs.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'logLines': {
                  'type': 'integer',
                  'description':
                      'Number of build log lines to inspect (default 100).',
                },
              },
            },
          },
          {
            'name': 'optimal_build_command',
            'description':
                'Detects CPU cores, available RAM, and battery level to generate a hardware-tuned, OOM-safe Flutter/Gradle APK or AAB build command.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'target': {
                  'type': 'string',
                  'description':
                      'Target type: debug, arm64, arm64D8, split, aab, aabD8 (default arm64D8).',
                },
                'mode': {
                  'type': 'string',
                  'description':
                      'Performance mode: auto, turbo, balanced, safe (default auto).',
                },
              },
            },
          },
          {
            'name': 'install_built_apk',
            'description':
                'Finds the built APK in the project (or given apkPath) and installs it on the Android device via Shizuku silent pm install or PackageInstaller.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'apkPath': {
                  'type': 'string',
                  'description': 'Optional explicit path to .apk file.',
                },
              },
            },
          },
        ];
      case 'builtin:device_qa':
        return [
          {
            'name': 'qa_get_runtime_errors',
            'description':
                'Returns any recorded Flutter runtime exceptions, RenderFlex UI overflow errors, and recent Talker error logs.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'limit': {
                  'type': 'integer',
                  'description': 'Max error entries to return (default 20).',
                },
              },
            },
          },
          {
            'name': 'adb_devices_and_logcat',
            'description':
                'Lists connected ADB/USB-OTG devices, Shizuku status, and optionally fetches recent Android logcat crash/error lines (*:E).',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'includeLogcat': {
                  'type': 'boolean',
                  'description':
                      'Whether to fetch recent logcat errors (default true).',
                },
              },
            },
          },
          {
            'name': 'device_hardware_telemetry',
            'description':
                'Returns live device hardware profile (CPU cores, total/free RAM, battery level/state, Android SDK / Linux kernel info, Shizuku & Root mode status).',
            'inputSchema': {'type': 'object', 'properties': {}},
          },
        ];
      case 'builtin:sqlite_telemetry':
        return [
          {
            'name': 'sqlite_inspect_schema',
            'description':
                'Finds SQLite database files (.db, .sqlite, .sqlite3) in the workspace or inspects all tables, row counts, and columns of a given database.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'dbPath': {
                  'type': 'string',
                  'description':
                      'Optional path to SQLite DB file (if omitted, lists all .db/.sqlite files in workspace).',
                },
              },
            },
          },
          {
            'name': 'sqlite_query',
            'description':
                'Executes a read/diagnostic SQL query against a SQLite database file in the workspace and returns formatted rows.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'dbPath': {
                  'type': 'string',
                  'description':
                      'Relative or absolute path to SQLite database file.',
                },
                'sql': {
                  'type': 'string',
                  'description':
                      'SQL query to run (e.g. SELECT * FROM users LIMIT 20).',
                },
              },
              'required': ['dbPath', 'sql'],
            },
          },
          {
            'name': 'inspect_network_and_logs',
            'description':
                'Returns recent HTTP requests captured by NetworkInspectorService and recent application logs from TalkerService.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'limit': {
                  'type': 'integer',
                  'description': 'Maximum entries to return (default 20).',
                },
              },
            },
          },
        ];
      case 'builtin:filesystem':
        return [
          {
            'name': 'read_file',
            'description':
                'Reads a text file from the project or device filesystem.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': 'Absolute or relative file path.',
                },
              },
              'required': ['path'],
            },
          },
          {
            'name': 'write_file',
            'description':
                'Writes text content to a file (creates or overwrites).',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': 'Absolute or relative file path.',
                },
                'content': {
                  'type': 'string',
                  'description': 'Text content to write.',
                },
              },
              'required': ['path', 'content'],
            },
          },
          {
            'name': 'list_directory',
            'description': 'Lists files and subdirectories in a directory.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': 'Directory path (defaults to workspace root).',
                },
                'recursive': {
                  'type': 'boolean',
                  'description': 'Recursively list subdirectories.',
                },
              },
            },
          },
          {
            'name': 'file_exists',
            'description': 'Checks whether a file or directory exists.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string', 'description': 'Path to check.'},
              },
              'required': ['path'],
            },
          },
          {
            'name': 'delete_file',
            'description': 'Deletes a file or empty directory.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string', 'description': 'Path to delete.'},
              },
              'required': ['path'],
            },
          },
        ];
      case 'builtin:shell':
        return [
          {
            'name': 'run_command',
            'description':
                'Executes a shell command and returns stdout/stderr.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'command': {
                  'type': 'string',
                  'description': 'Shell command to execute.',
                },
                'timeoutSeconds': {
                  'type': 'integer',
                  'description': 'Timeout in seconds (default 30).',
                },
              },
              'required': ['command'],
            },
          },
          {
            'name': 'which',
            'description': 'Finds the path of an executable in PATH.',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'executable': {
                  'type': 'string',
                  'description': 'Executable name.',
                },
              },
              'required': ['executable'],
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
          r'^\s*(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|extension|typedef|def|function|interface|struct)\s+([A-Za-z0-9_]+)|^\s*(?:Future<[^>]+>|Stream<[^>]+>|Widget|void|String|int|bool|double|dynamic)\s+([A-Za-z0-9_]+)\s*\(|^\s*final\s+([A-Za-z0-9_]+Provider)\s*=',
        );
        final out = StringBuffer();
        int fileCount = 0;
        await for (final entity in rootDir.list(
          recursive: true,
          followLinks: false,
        )) {
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
                final name = m.group(1) ?? m.group(2) ?? m.group(3) ?? '';
                if (name.isNotEmpty &&
                    !const {
                      'if',
                      'for',
                      'while',
                      'switch',
                      'catch',
                    }.contains(name)) {
                  symbols.add('$name(#L${i + 1})');
                }
              }
            }
            if (symbols.isNotEmpty) {
              out.writeln(
                '$rel (${lines.length}L): ${symbols.take(28).join(', ')}',
              );
              fileCount++;
              if (fileCount >= 90) break;
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
        final symbolName = args['symbolName']?.toString().trim() ?? '';
        final fullPath = p.isAbsolute(rawFile)
            ? rawFile
            : p.join(workspace, rawFile);
        final file = File(fullPath);
        if (!await file.exists()) {
          return {'isError': true, 'content': 'File not found: $rawFile'};
        }
        final lines = await file.readAsLines();
        final escapedSym = RegExp.escape(symbolName);
        // Prefer the actual type/function declaration over a field or comment
        // that merely references the same identifier (for example
        // `final Calculator calc = Calculator()`).
        final primaryDeclRegex = RegExp(
          '^\\s*(?:abstract\\s+)?(?:class|enum|mixin|extension|typedef|interface|struct)\\s+$escapedSym\\b',
        );
        final declRegex = RegExp(
          '(?:class|enum|mixin|extension|typedef|def|function|interface|struct|Widget|Future|Stream|void|String|int|bool|double|dynamic|final|const|get|set)\\b[^;]*\\b$escapedSym\\b',
        );
        final wordRegex = RegExp('\\b$escapedSym\\b');
        int startIdx = -1;
        for (var i = 0; i < lines.length; i++) {
          final trimmed = lines[i].trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('import ')) {
            continue;
          }
          if (primaryDeclRegex.hasMatch(lines[i])) {
            startIdx = i;
            break;
          }
        }
        if (startIdx == -1) {
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('import ')) {
              continue;
            }
            if (declRegex.hasMatch(lines[i])) {
              startIdx = i;
              break;
            }
          }
        }
        if (startIdx == -1) {
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trimLeft();
            if (trimmed.startsWith('import ')) continue;
            if (wordRegex.hasMatch(lines[i])) {
              startIdx = i;
              break;
            }
          }
        }
        if (startIdx == -1) {
          for (var i = 0; i < lines.length; i++) {
            if (lines[i].contains(symbolName)) {
              startIdx = i;
              break;
            }
          }
        }
        if (startIdx == -1) {
          return {
            'isError': true,
            'content': 'Symbol "$symbolName" not found in $rawFile',
          };
        }

        // Balance braces `{ ... }` to extract the complete symbol body cleanly
        int braceDepth = 0;
        bool seenOpeningBrace = false;
        int endIdx = (startIdx + 120).clamp(0, lines.length);
        final maxEnd = (startIdx + 180).clamp(0, lines.length);
        for (var i = startIdx; i < maxEnd; i++) {
          final line = lines[i];
          for (var c = 0; c < line.length; c++) {
            final ch = line.codeUnitAt(c);
            if (ch == 123) {
              // '{'
              braceDepth++;
              seenOpeningBrace = true;
            } else if (ch == 125) {
              // '}'
              braceDepth--;
            }
          }
          if (seenOpeningBrace && braceDepth <= 0 && i > startIdx) {
            endIdx = i + 1;
            break;
          }
        }

        final snippet = StringBuffer();
        snippet.writeln('[$rawFile #L${startIdx + 1}-$endIdx ($symbolName)]');
        for (var i = startIdx; i < endIdx; i++) {
          snippet.writeln('${i + 1}: ${lines[i]}');
        }
        return {
          'range': '#L${startIdx + 1}-$endIdx',
          'content': snippet.toString(),
        };
      }

      if (toolName == 'find_symbol_usages') {
        final symbolName = args['symbolName']?.toString().trim() ?? '';
        if (symbolName.isEmpty) {
          return {'isError': true, 'content': 'symbolName is required'};
        }
        final sub = args['directory']?.toString() ?? '';
        final rootDir = Directory(
          sub.isEmpty ? workspace : p.join(workspace, sub),
        );
        if (!await rootDir.exists()) {
          return {'isError': true, 'content': 'Directory not found: $sub'};
        }
        final wordRegex = RegExp('\\b${RegExp.escape(symbolName)}\\b');
        final hits = <String>[];
        await for (final entity in rootDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final rel = p.relative(entity.path, from: workspace);
          if (rel.startsWith('.') ||
              rel.contains('/.') ||
              rel.contains('/build/') ||
              rel.contains('node_modules')) {
            continue;
          }
          try {
            final stat = await entity.stat();
            if (stat.size > 512 * 1024) continue;
            final lines = await entity.readAsLines();
            for (var i = 0; i < lines.length; i++) {
              if (wordRegex.hasMatch(lines[i])) {
                hits.add('$rel:${i + 1}: ${lines[i].trim()}');
                if (hits.length >= 80) break;
              }
            }
          } catch (_) {}
          if (hits.length >= 80) break;
        }
        return {
          'content': hits.isEmpty
              ? 'No usages found for "$symbolName".'
              : 'Found ${hits.length} usage(s) of "$symbolName":\n${hits.join('\n')}',
        };
      }

      if (toolName == 'smart_analyze_errors') {
        final rawTarget = args['targetPath']?.toString().trim() ?? '';
        final safeTarget =
            rawTarget.isNotEmpty &&
                !rawTarget.contains(';') &&
                !rawTarget.contains('`') &&
                !rawTarget.contains(r'$')
            ? ' "$rawTarget"'
            : '';
        final res = await runtime.runCommandDetailed(
          'if [ -f pubspec.yaml ]; then '
          '  (dart analyze$safeTarget 2>&1 || flutter analyze --no-pub$safeTarget 2>&1); '
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
        final diagText = McpService.formatCompactAnalyzerDiagnostics(
          res.combined,
        );
        return {
          'exitCode': res.exitCode,
          'diagnostics': diagText,
          'content': diagText,
        };
      }

      if (toolName == 'save_memory') {
        final memFile = File(p.join(workspace, '.quantum_memory.json'));
        Map<String, dynamic> data = {};
        if (await memFile.exists()) {
          try {
            data =
                jsonDecode(await memFile.readAsString())
                    as Map<String, dynamic>;
          } catch (_) {}
        }
        final k = args['key']?.toString() ?? 'note';
        final v = args['fact']?.toString() ?? '';
        data[k] = v;
        await memFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
        );
        return {'content': 'Saved [$k] to .quantum_memory.json'};
      }

      if (toolName == 'read_memory') {
        final memFile = File(p.join(workspace, '.quantum_memory.json'));
        if (!await memFile.exists()) {
          return {'content': 'No saved project memory yet.'};
        }
        final raw = await memFile.readAsString();
        final filterKey = args['key']?.toString().trim() ?? '';
        if (filterKey.isNotEmpty) {
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            if (map.containsKey(filterKey)) {
              return {'content': '$filterKey: ${map[filterKey]}'};
            }
          } catch (_) {}
        }
        return {'content': raw};
      }

      if (toolName == 'delete_memory') {
        final memFile = File(p.join(workspace, '.quantum_memory.json'));
        if (!await memFile.exists()) {
          return {'content': 'No saved project memory yet.'};
        }
        final key = args['key']?.toString().trim() ?? '';
        try {
          final data =
              jsonDecode(await memFile.readAsString()) as Map<String, dynamic>;
          final removed = data.remove(key) != null;
          await memFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
          );
          return {
            'content': removed
                ? 'Deleted [$key] from .quantum_memory.json'
                : 'Key [$key] was not present in .quantum_memory.json',
          };
        } catch (e) {
          return {'isError': true, 'content': 'Failed to update memory: $e'};
        }
      }

      if (toolName == 'fetch_url_markdown') {
        if (!_ref.read(mcpServiceProvider.notifier).internetAccess) {
          return {
            'isError': true,
            'content': 'Internet access is disabled in MCP settings.',
          };
        }
        final url = args['url']?.toString().trim() ?? '';
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == 'http' || uri.scheme == 'https') ||
            uri.host.isEmpty) {
          return {
            'isError': true,
            'content':
                'Invalid URL (must start with http:// or https://): $url',
          };
        }
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        try {
          final req = await client.getUrl(uri);
          req.headers.set('User-Agent', 'Mozilla/5.0 (QuantumIDE-Agent/1.2)');
          final resp = await req.close().timeout(const Duration(seconds: 18));
          final body = await resp
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
          final stripped = _cleanHtmlToMarkdown(body);
          return {
            'url': url,
            'content': stripped.length > 8000
                ? '${stripped.substring(0, 8000)}\n...[truncated]'
                : stripped,
          };
        } finally {
          client.close(force: true);
        }
      }

      if (toolName == 'web_search_docs') {
        if (!_ref.read(mcpServiceProvider.notifier).internetAccess) {
          return {
            'isError': true,
            'content': 'Internet access is disabled in MCP settings.',
          };
        }
        final query = args['query']?.toString().trim() ?? '';
        if (query.isEmpty) {
          return {'isError': true, 'content': 'Search query is empty.'};
        }
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        try {
          final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': query});
          final req = await client.getUrl(uri);
          req.headers.set('User-Agent', 'Mozilla/5.0 (QuantumIDE-Agent/1.2)');
          final resp = await req.close().timeout(const Duration(seconds: 15));
          final html = await resp
              .transform(const Utf8Decoder(allowMalformed: true))
              .join();
          final results = <String>[];
          final linkRe = RegExp(
            r'class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>',
          );
          final snipRe = RegExp(r'class="result__snippet"[^>]*>([\s\S]*?)</a>');
          final links = linkRe.allMatches(html).toList();
          final snips = snipRe.allMatches(html).toList();
          for (var i = 0; i < links.length && results.length < 8; i++) {
            var href = links[i].group(1)!.replaceAll('&amp;', '&');
            final u = Uri.tryParse(
              href.startsWith('//') ? 'https:$href' : href,
            );
            if (u != null && u.queryParameters['uddg'] != null) {
              href = u.queryParameters['uddg']!;
            }
            final title = _cleanHtmlToMarkdown(links[i].group(2)!);
            final snip = i < snips.length
                ? _cleanHtmlToMarkdown(snips[i].group(1)!)
                : '';
            results.add('${results.length + 1}. $title\n   $href\n   $snip');
          }
          return {
            'content': results.isEmpty
                ? 'No search results found for "$query".'
                : results.join('\n\n'),
          };
        } finally {
          client.close(force: true);
        }
      }

      if (toolName == 'semantic_search_code') {
        final query = args['query']?.toString().trim() ?? '';
        final limit = ((args['limit'] as num?)?.toInt() ?? 15).clamp(1, 40);
        if (query.isEmpty) {
          return {'isError': true, 'content': 'Search query is empty.'};
        }
        final indexerNotifier = _ref.read(symbolIndexerProvider.notifier);
        if (_ref.read(symbolIndexerProvider).files.isEmpty) {
          await indexerNotifier.scanWorkspace(workspace);
        }
        final results = await indexerNotifier.semanticSearch(
          query,
          limit: limit,
        );
        if (results.isEmpty) {
          return {'content': 'No semantic matches found for "$query".'};
        }
        final out = results
            .map(
              (r) =>
                  '[${r.type.toUpperCase()}] ${p.relative(r.path, from: workspace)}:${r.lineNumber} — ${r.title} (${r.subtitle})',
            )
            .join('\n');
        return {'content': out};
      }

      if (toolName == 'scan_todos') {
        final filter = args['filter']?.toString().trim().toUpperCase() ?? '';
        final patterns = filter.isNotEmpty
            ? [filter]
            : const ['FIXME', 'BUG', 'TODO', 'HACK', 'XXX'];
        final hits = <String>[];
        final rootDir = Directory(workspace);
        if (await rootDir.exists()) {
          await for (final entity in rootDir.list(
            recursive: true,
            followLinks: false,
          )) {
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
              '.c',
              '.cpp',
            }.contains(ext)) {
              continue;
            }
            try {
              final lines = await entity.readAsLines();
              for (var i = 0; i < lines.length; i++) {
                final line = lines[i];
                for (final pat in patterns) {
                  if (line.contains(pat)) {
                    hits.add('$rel:${i + 1} [$pat]: ${line.trim()}');
                    break;
                  }
                }
                if (hits.length >= 100) break;
              }
            } catch (_) {}
            if (hits.length >= 100) break;
          }
        }
        return {
          'content': hits.isEmpty
              ? 'No TODO/FIXME/BUG items found.'
              : 'Found ${hits.length} item(s):\n${hits.join('\n')}',
        };
      }

      if (toolName == 'run_tests') {
        final testPath = args['testPath']?.toString().trim() ?? '';
        final safeArg =
            testPath.isNotEmpty &&
                !testPath.contains(';') &&
                !testPath.contains('`')
            ? ' "$testPath"'
            : '';
        final res = await runtime.runCommandDetailed(
          'if [ -f pubspec.yaml ]; then '
          '  (flutter test --no-pub$safeArg 2>&1 || dart test$safeArg 2>&1); '
          'elif [ -f package.json ]; then '
          '  npm test 2>&1; '
          'elif [ -f Cargo.toml ]; then '
          '  cargo test 2>&1; '
          'else '
          '  pytest$safeArg 2>&1; '
          'fi',
          workingDirectory: workspace,
          timeout: const Duration(seconds: 120),
        );
        final clipped = res.combined.length > 5000
            ? '${res.combined.substring(0, 2000)}\n...[truncated]...\n${res.combined.substring(res.combined.length - 2500)}'
            : res.combined;
        return {
          'exitCode': res.exitCode,
          'content': '[Test ExitCode: ${res.exitCode}]\n$clipped',
        };
      }

      if (toolName == 'get_build_diagnostics') {
        final logLines = ((args['logLines'] as num?)?.toInt() ?? 100).clamp(
          20,
          300,
        );
        final progress = BuildProgressTracker.instance.progress.value;
        final tail = BuildProgressTracker.instance.logTail(logLines);
        final tailText = tail.join('\n');
        final diagService = _ref.read(androidBuildDiagnosticsServiceProvider);
        final issues = diagService.parseBuildIssues(tailText, workspace);
        final apkInfo = diagService.findDebugApk(workspace);

        final buf = StringBuffer();
        buf.writeln(
          'Build Stage: ${progress.stage.name} (active=${progress.active}, elapsed=${progress.elapsed.inSeconds}s)',
        );
        if (apkInfo != null) {
          buf.writeln(
            'Found Built APK: ${apkInfo.path} (${apkInfo.formattedSize}, modified=${apkInfo.lastModified.toIso8601String()}, stale=${apkInfo.isStale})',
          );
        } else {
          buf.writeln('Found Built APK: none');
        }
        if (issues.isNotEmpty) {
          buf.writeln('\nStructured Build Issues (${issues.length}):');
          for (final issue in issues) {
            buf.writeln(
              '- [${issue.severity.name.toUpperCase()}] ${issue.title}: ${issue.detail}'
              '${issue.filePath != null ? ' (${issue.filePath}:${issue.line ?? 1})' : ''}'
              '${issue.suggestion != null ? '\n  Fix Suggestion: ${issue.suggestion}' : ''}',
            );
          }
        }
        if (tail.isNotEmpty) {
          buf.writeln('\nRecent Build Log ($logLines lines):\n$tailText');
        }
        return {'content': buf.toString().trim()};
      }

      if (toolName == 'optimal_build_command') {
        final rawTarget = args['target']?.toString().trim() ?? 'arm64D8';
        final rawMode = args['mode']?.toString().trim().toLowerCase() ?? 'auto';
        final target = BuildTargetType.values.firstWhere(
          (t) => t.name.toLowerCase() == rawTarget.toLowerCase(),
          orElse: () => BuildTargetType.arm64D8,
        );
        final hw = BuildResourceOptimizer.detectHardware();
        int? batteryLevel;
        try {
          batteryLevel = await Battery().batteryLevel.timeout(
            const Duration(seconds: 2),
          );
        } catch (_) {}

        BuildPerformanceMode perfMode;
        if (rawMode == 'turbo') {
          perfMode = BuildPerformanceMode.turbo;
        } else if (rawMode == 'safe') {
          perfMode = BuildPerformanceMode.safe;
        } else if (rawMode == 'balanced') {
          perfMode = BuildPerformanceMode.balanced;
        } else {
          if ((batteryLevel != null && batteryLevel < 20) ||
              hw.availableRamMb < 2200) {
            perfMode = BuildPerformanceMode.safe;
          } else if (hw.availableRamMb >= 5000 && hw.cpuCores >= 8) {
            perfMode = BuildPerformanceMode.turbo;
          } else {
            perfMode = BuildPerformanceMode.balanced;
          }
        }

        final cmd = BuildResourceOptimizer.generateBuildCommand(
          target: target,
          mode: perfMode,
        );
        return {
          'content':
              'Hardware: $hw'
              '${batteryLevel != null ? ', Battery: $batteryLevel%' : ''}\n'
              'Selected Profile: ${perfMode.name} (target=${target.name})\n'
              'Command:\n$cmd',
        };
      }

      if (toolName == 'install_built_apk') {
        var apkPath = args['apkPath']?.toString().trim() ?? '';
        if (apkPath.isEmpty) {
          final apkInfo = _ref
              .read(androidBuildDiagnosticsServiceProvider)
              .findDebugApk(workspace);
          if (apkInfo == null) {
            return {
              'isError': true,
              'content':
                  'No built APK found in workspace. Run a build first or pass an explicit apkPath.',
            };
          }
          apkPath = apkInfo.path;
        } else if (!p.isAbsolute(apkPath)) {
          apkPath = p.join(workspace, apkPath);
        }
        final installer = _ref.read(androidAppInstallerServiceProvider);
        final res = await installer.installApk(apkPath);
        return {
          'isError': !res.success,
          'content':
              'Install result (success=${res.success}, method=${res.method ?? 'auto'}): ${res.message ?? ''}',
        };
      }

      if (toolName == 'qa_get_runtime_errors') {
        final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 50);
        final talkerHistory = TalkerService.talker.history.reversed
            .take(limit)
            .map((e) => '[${e.title ?? 'LOG'}] ${e.generateTextMessage()}')
            .toList();
        return {
          'content': [
            'GhostQA Active Port: ${GhostQAService.instance.boundPort ?? 'dormant (enable owner key or developer mode)'}',
            if (talkerHistory.isEmpty)
              'No recent runtime errors or logs recorded in Talker.'
            else
              'Recent IDE / Runtime Logs (${talkerHistory.length}):\n${talkerHistory.join('\n')}',
          ].join('\n\n'),
        };
      }

      if (toolName == 'adb_devices_and_logcat') {
        final includeLogcat = args['includeLogcat'] != false;
        final adbNotifier = _ref.read(adbDeviceServiceProvider.notifier);
        await adbNotifier.refreshDevices(silent: true);
        final adbState = _ref.read(adbDeviceServiceProvider);
        final buf = StringBuffer();
        buf.writeln(
          'Shizuku Available: ${ShizukuBridge.instance.isAvailable} (uid=${ShizukuBridge.instance.uid})',
        );
        buf.writeln('Connected ADB Devices (${adbState.devices.length}):');
        for (final d in adbState.devices) {
          buf.writeln(
            '- ${d.id} [${d.status.name}] model=${d.model} (${d.androidVersion ?? 'Android'})',
          );
        }
        if (includeLogcat) {
          final logcat = await adbNotifier.getLogcatErrors(lines: 60);
          buf.writeln('\nRecent Device Logcat Errors:\n$logcat');
        }
        return {'content': buf.toString().trim()};
      }

      if (toolName == 'device_hardware_telemetry') {
        final hw = BuildResourceOptimizer.detectHardware();
        int? batteryLevel;
        String batteryState = 'unknown';
        try {
          final b = Battery();
          batteryLevel = await b.batteryLevel.timeout(
            const Duration(seconds: 2),
          );
          final st = await b.batteryState.timeout(const Duration(seconds: 2));
          batteryState = st.name;
        } catch (_) {}

        String deviceModel = Platform.operatingSystem;
        try {
          if (Platform.isAndroid) {
            final info = await DeviceInfoPlugin().androidInfo;
            deviceModel =
                '${info.manufacturer} ${info.model} (Android ${info.version.release}, SDK ${info.version.sdkInt}, ABIs: ${info.supportedAbis.join(",")})';
          } else if (Platform.isLinux) {
            final info = await DeviceInfoPlugin().linuxInfo;
            deviceModel = info.prettyName;
          }
        } catch (_) {}

        return {
          'content': [
            'Device: $deviceModel',
            'Hardware: $hw',
            if (batteryLevel != null) 'Battery: $batteryLevel% ($batteryState)',
            'Execution Mode: ${runtime.useNativeRootMode ? 'Native Root Kernel (su)' : 'Ubuntu 24.04 PRoot Sandbox'}',
            'Shizuku: binder=${ShizukuBridge.instance.isBinderAlive}, permission=${ShizukuBridge.instance.hasPermission}, uid=${ShizukuBridge.instance.uid}',
          ].join('\n'),
        };
      }

      if (toolName == 'sqlite_inspect_schema') {
        final rawDb = args['dbPath']?.toString().trim() ?? '';
        if (rawDb.isEmpty) {
          final found = <String>[];
          final rootDir = Directory(workspace);
          if (await rootDir.exists()) {
            await for (final entity in rootDir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entity is! File) continue;
              final ext = p.extension(entity.path).toLowerCase();
              if (const {'.db', '.sqlite', '.sqlite3'}.contains(ext)) {
                found.add(p.relative(entity.path, from: workspace));
              }
            }
          }
          return {
            'content': found.isEmpty
                ? 'No SQLite (.db / .sqlite / .sqlite3) files found in workspace.'
                : 'Found SQLite database files:\n${found.join('\n')}',
          };
        }
        final fullPath = p.isAbsolute(rawDb) ? rawDb : p.join(workspace, rawDb);
        if (!await File(fullPath).exists()) {
          return {'isError': true, 'content': 'Database not found: $rawDb'};
        }
        final db = await databaseFactory.openDatabase(
          fullPath,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          );
          final buf = StringBuffer(
            'Database: $rawDb (${tables.length} tables)\n',
          );
          for (final t in tables) {
            final tName = t['name']?.toString() ?? '';
            final cols = await db.rawQuery('PRAGMA table_info("$tName")');
            final cntRes = await db.rawQuery(
              'SELECT COUNT(*) as cnt FROM "$tName"',
            );
            final cnt = cntRes.isNotEmpty ? cntRes.first['cnt'] : 0;
            final colSummary = cols
                .map(
                  (c) =>
                      '${c['name']} ${c['type']}${(c['pk'] as int? ?? 0) > 0 ? ' PK' : ''}',
                )
                .join(', ');
            buf.writeln('- $tName ($cnt rows): ($colSummary)');
          }
          return {'content': buf.toString().trim()};
        } finally {
          await db.close();
        }
      }

      if (toolName == 'sqlite_query') {
        final rawDb = args['dbPath']?.toString().trim() ?? '';
        final sql = args['sql']?.toString().trim() ?? '';
        if (rawDb.isEmpty || sql.isEmpty) {
          return {
            'isError': true,
            'content': 'Both dbPath and sql are required.',
          };
        }
        final fullPath = p.isAbsolute(rawDb) ? rawDb : p.join(workspace, rawDb);
        if (!await File(fullPath).exists()) {
          return {'isError': true, 'content': 'Database not found: $rawDb'};
        }
        final db = await databaseFactory.openDatabase(fullPath);
        try {
          final rows = await db.rawQuery(sql);
          final preview = rows.take(50).toList();
          return {
            'content':
                'Returned ${rows.length} row(s):\n${const JsonEncoder.withIndent('  ').convert(preview)}',
          };
        } finally {
          await db.close();
        }
      }

      if (toolName == 'inspect_network_and_logs') {
        final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 60);
        final reqs = NetworkInspectorService.requestsNotifier.value
            .take(limit)
            .toList();
        final logs = TalkerService.talker.history.reversed.take(limit).toList();
        final buf = StringBuffer();
        buf.writeln('Captured HTTP Requests (${reqs.length}):');
        if (reqs.isEmpty) {
          buf.writeln('  (no HTTP requests recorded yet)');
        } else {
          for (final r in reqs) {
            buf.writeln(
              '  - [${r.statusCode ?? 'ERR'}] ${r.method} ${r.url} (${r.durationMs}ms)${r.error != null ? ' Error: ${r.error}' : ''}',
            );
          }
        }
        buf.writeln('\nRecent Application Logs (${logs.length}):');
        for (final l in logs) {
          buf.writeln('  - ${l.generateTextMessage()}');
        }
        return {'content': buf.toString().trim()};
      }
      if (builtinId == 'builtin:filesystem') {
        if (toolName == 'read_file') {
          final path = args['path']?.toString() ?? '';
          final file = File(
            p.isAbsolute(path) ? path : p.join(workspace, path),
          );
          if (!await file.exists()) {
            return {'isError': true, 'content': 'File not found: $path'};
          }
          final content = await file.readAsString();
          return {'content': content};
        }
        if (toolName == 'write_file') {
          final path = args['path']?.toString() ?? '';
          final content = args['content']?.toString() ?? '';
          final file = File(
            p.isAbsolute(path) ? path : p.join(workspace, path),
          );
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
          return {'content': 'Written ${content.length} bytes to $path'};
        }
        if (toolName == 'list_directory') {
          final dirPath = args['path']?.toString() ?? '';
          final recursive = args['recursive'] as bool? ?? false;
          final dir = Directory(
            p.isAbsolute(dirPath) ? dirPath : p.join(workspace, dirPath),
          );
          if (!await dir.exists()) {
            return {
              'isError': true,
              'content': 'Directory not found: $dirPath',
            };
          }
          final buf = StringBuffer();
          await for (final entity in dir.list(
            recursive: recursive,
            followLinks: false,
          )) {
            buf.writeln(
              '${entity.path} (${entity.runtimeType == File ? 'file' : 'dir'})',
            );
          }
          return {'content': buf.toString().trim()};
        }
        if (toolName == 'file_exists') {
          final path = args['path']?.toString() ?? '';
          final f = await FileSystemEntity.type(
            p.isAbsolute(path) ? path : p.join(workspace, path),
          );
          return {
            'content': f != FileSystemEntityType.notFound
                ? 'exists'
                : 'not found',
          };
        }
        if (toolName == 'delete_file') {
          final path = args['path']?.toString() ?? '';
          final target = p.isAbsolute(path) ? path : p.join(workspace, path);
          final type = await FileSystemEntity.type(target);
          if (type != FileSystemEntityType.notFound) {
            if (type == FileSystemEntityType.file) {
              await File(target).delete();
            } else if (type == FileSystemEntityType.directory) {
              await Directory(target).delete(recursive: false);
            }
            return {'content': 'Deleted $path'};
          }
          return {'isError': true, 'content': 'Not found: $path'};
        }
      }
      if (builtinId == 'builtin:shell') {
        if (toolName == 'run_command') {
          final command = args['command']?.toString() ?? '';
          final timeoutSec = ((args['timeoutSeconds'] as num?)?.toInt() ?? 30);
          try {
            final result = await Process.run(
              'sh',
              ['-c', command],
              workingDirectory: workspace,
            ).timeout(Duration(seconds: timeoutSec));
            return {
              'content':
                  'EXIT CODE: ${result.exitCode}\nSTDOUT:\n${result.stdout}\nSTDERR:\n${result.stderr}',
            };
          } catch (e) {
            return {'isError': true, 'content': 'Command failed: $e'};
          }
        }
        if (toolName == 'which') {
          final executable = args['executable']?.toString() ?? '';
          try {
            final result = await Process.run('which', [executable]);
            if (result.exitCode == 0) {
              return {'content': result.stdout.trim()};
            }
            return {
              'isError': true,
              'content': 'Executable not found: $executable',
            };
          } catch (e) {
            return {'isError': true, 'content': 'which failed: $e'};
          }
        }
      }
    } catch (e) {
      return {'isError': true, 'content': 'Builtin MCP error: $e'};
    }
    return {'isError': true, 'content': 'Unknown builtin tool: $toolName'};
  }

  static String _cleanHtmlToMarkdown(String html) {
    var t = html
        .replaceAll(
          RegExp(
            r'<(script|style|noscript|svg)[\s\S]*?</\1>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        .replaceAll(
          RegExp(
            r'<(br|/p|/div|/li|/h[1-6]|/tr|/pre)[^>]*>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    t = t
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return t
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n+'), '\n')
        .trim();
  }

  void disconnect() {
    _process?.kill();
    _process = null;
    _isHandshakeDone = false;
    _cachedTools = null;
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
  late final Future<void> _ready;

  McpService(this._ref) : super([]) {
    _ready = _loadConfigs();
  }

  bool get internetAccess => _internetAccess;

  static McpCategory categoryForServer(String name) => switch (name) {
    'quantum-codegraph' => McpCategory.architecture,
    'quantum-token-saver' => McpCategory.diagnostics,
    'quantum-build-doctor' => McpCategory.build,
    'quantum-device-qa' => McpCategory.devices,
    'quantum-memory' => McpCategory.memory,
    'quantum-web-fetch' => McpCategory.web,
    'quantum-sqlite-telemetry' => McpCategory.data,
    _ => McpCategory.architecture,
  };

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
    McpServerConfig(
      name: 'quantum-build-doctor',
      type: McpServerType.stdio,
      command: 'builtin:build_doctor',
      isEnabled: true,
    ),
    McpServerConfig(
      name: 'quantum-device-qa',
      type: McpServerType.stdio,
      command: 'builtin:device_qa',
      isEnabled: true,
    ),
    McpServerConfig(
      name: 'quantum-sqlite-telemetry',
      type: McpServerType.stdio,
      command: 'builtin:sqlite_telemetry',
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
            .where(
              (s) => s.command != 'uvx',
            ) // Remove broken legacy uvx servers
            .toList();
        final existingNames = loaded.map((s) => s.name).toSet();
        for (final builtin in defaultBuiltinServers()) {
          if (!existingNames.contains(builtin.name)) {
            loaded.add(builtin);
          }
        }
        if (!mounted) return;
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
    if (!mounted) return;
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
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
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
      title: '⚡ Quantum CodeGraph (AST, BM25 Поиск & Символы)',
      description:
          'Встроенный индекс классов, функций, виджетов, поиск связей и BM25 семантический поиск кода',
      config: McpServerConfig(
        name: 'quantum-codegraph',
        type: McpServerType.stdio,
        command: 'builtin:codegraph',
      ),
    ),
    (
      title: '🛡️ Quantum Smart Analyzer & Test Runner',
      description:
          'Сжатая диагностика ошибок (analyze/tsc/cargo), запуск тестов (run_tests) и поиск TODO/FIXME/BUG',
      config: McpServerConfig(
        name: 'quantum-token-saver',
        type: McpServerType.stdio,
        command: 'builtin:token_saver',
      ),
    ),
    (
      title: '🩺 Quantum Build Doctor & APK Installer',
      description:
          'Анализ логов сборки Gradle/AAPT2/NDK, расчёт оптимальных флагов под CPU/RAM/батарею и установка APK',
      config: McpServerConfig(
        name: 'quantum-build-doctor',
        type: McpServerType.stdio,
        command: 'builtin:build_doctor',
      ),
    ),
    (
      title: '📱 Quantum Device QA, ADB & Shizuku Telemetry',
      description:
          'Инспекция ADB/USB-OTG устройств, Logcat ошибок, статуса Shizuku, батареи и RenderFlex ошибок UI',
      config: McpServerConfig(
        name: 'quantum-device-qa',
        type: McpServerType.stdio,
        command: 'builtin:device_qa',
      ),
    ),
    (
      title: '🗄️ Quantum SQLite & Network Inspector',
      description:
          'Прямой просмотр таблиц и SQL-запросы к базам SQLite проекта + перехват HTTP-запросов и логов Talker',
      config: McpServerConfig(
        name: 'quantum-sqlite-telemetry',
        type: McpServerType.stdio,
        command: 'builtin:sqlite_telemetry',
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
      title: '🌐 Quantum Web Fetch & Search (Документация и Поиск)',
      description:
          'Поиск в интернете и быстрая загрузка документации в чистом текстовом виде без лишних токенов',
      config: McpServerConfig(
        name: 'quantum-web-fetch',
        type: McpServerType.stdio,
        command: 'builtin:web_fetch',
      ),
    ),
    (
      title: '📂 Quantum Filesystem (Builtin, без npm)',
      description:
          'Безопасная работа с файлами и каталогами проекта через встроенный Dart IO (не требует npm/npx)',
      config: McpServerConfig(
        name: 'quantum-filesystem',
        type: McpServerType.stdio,
        command: 'builtin:filesystem',
      ),
    ),
    (
      title: '🎯 Dart & Flutter Official MCP (dart mcp-server)',
      description:
          'Официальный MCP-сервер Dart SDK: Dart Analysis Server, DTD, pub.dev, безопасный pubspec.yaml, тесты и Agentic Hot Reload',
      config: McpServerConfig(
        name: 'dart-flutter-mcp',
        type: McpServerType.stdio,
        command: 'dart',
        args: ['mcp-server'],
      ),
    ),
    (
      title: '🐚 Quantum Shell/Terminal (Builtin, без npm)',
      description:
          'Выполнение команд оболочки и терминала через встроенный Process API (не требует npm/npx)',
      config: McpServerConfig(
        name: 'quantum-shell',
        type: McpServerType.stdio,
        command: 'builtin:shell',
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

  Future<List<Map<String, dynamic>>> getAvailableMcpTools({
    bool forceRefresh = false,
  }) async {
    await _ready;
    if (!mounted) return const [];
    final enabledServers = state.where((s) => s.isEnabled).toList();
    if (enabledServers.isEmpty) return const [];

    final perServerLists = await Future.wait(
      enabledServers.map((server) async {
        final client = _getOrCreateClient(server);
        try {
          await client.connect().timeout(const Duration(seconds: 8));
          final tools = await client
              .listTools(forceRefresh: forceRefresh)
              .timeout(const Duration(seconds: 8));
          return tools
              .map<Map<String, dynamic>>(
                (tool) => {
                  'server': server.name,
                  'name': tool['name'],
                  'description': tool['description'] ?? '',
                  'inputSchema': tool['inputSchema'] ?? {},
                },
              )
              .toList();
        } catch (e) {
          debugPrint(
            'Failed to connect or list tools for MCP server ${server.name}: $e',
          );
          return const <Map<String, dynamic>>[];
        }
      }),
    );

    return perServerLists.expand((list) => list).toList();
  }

  Future<Map<String, dynamic>> executeMcpTool(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    await _ready;
    if (!mounted) {
      throw StateError('MCP service is disposed');
    }
    final server = state.firstWhere(
      (s) => s.name == serverName,
      orElse: () =>
          throw Exception('MCP server "$serverName" is not configured.'),
    );
    final client = _getOrCreateClient(server);
    await client.connect();
    return await client.callTool(toolName, arguments);
  }

  /// Aggregates repetitive analyzer output (e.g. `dart analyze` / `flutter analyze` / `tsc`)
  /// by `(severity, filePath, errorCode)` so the AI agent receives compact, actionable
  /// diagnostics instead of dozens of duplicated lines.
  static String formatCompactAnalyzerDiagnostics(String rawOutput) {
    final trimmedRaw = rawOutput.trim();
    if (trimmedRaw.isEmpty) return 'No issues found.';
    if (trimmedRaw.contains('No issues found')) {
      return 'Summary: 0 error(s), 0 warning(s), 0 info(s).\nNo issues found.';
    }

    final bulletRe = RegExp(
      r'^\s*(error|warning|info)\s+[•\-]\s+(.+?)\s+[•\-]\s+([^:\s]+):(\d+):(\d+)\s+[•\-]\s+([a-zA-Z0-9_]+)\s*$',
    );
    final dartDashRe = RegExp(
      r'^\s*(error|warning|info)\s+-\s+([^:\s]+):(\d+):(\d+)\s+-\s+(.+?)\s+-\s+([a-zA-Z0-9_]+)\s*$',
    );

    final groups =
        <
          String,
          ({
            String severity,
            String file,
            String code,
            String message,
            List<int> lines,
          })
        >{};
    final otherLines = <String>[];
    var errorCount = 0;
    var warningCount = 0;
    var infoCount = 0;

    for (final rawLine in trimmedRaw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      String? severity;
      String? file;
      int? lineNum;
      String? message;
      String? code;

      final mBullet = bulletRe.firstMatch(rawLine);
      if (mBullet != null) {
        severity = mBullet.group(1)!.toLowerCase();
        message = mBullet.group(2)!.trim();
        file = mBullet.group(3)!.trim();
        lineNum = int.tryParse(mBullet.group(4)!) ?? 0;
        code = mBullet.group(6)!.trim();
      } else {
        final mDash = dartDashRe.firstMatch(rawLine);
        if (mDash != null) {
          severity = mDash.group(1)!.toLowerCase();
          file = mDash.group(2)!.trim();
          lineNum = int.tryParse(mDash.group(3)!) ?? 0;
          message = mDash.group(5)!.trim();
          code = mDash.group(6)!.trim();
        }
      }

      if (severity != null &&
          file != null &&
          code != null &&
          message != null) {
        if (severity == 'error') {
          errorCount++;
        } else if (severity == 'warning') {
          warningCount++;
        } else {
          infoCount++;
        }
        final key = '$severity|$file|$code';
        final existing = groups[key];
        if (existing != null) {
          existing.lines.add(lineNum ?? 0);
        } else {
          groups[key] = (
            severity: severity,
            file: file,
            code: code,
            message: message,
            lines: [lineNum ?? 0],
          );
        }
      } else if (line.startsWith('Error:') ||
          line.contains('error TS') ||
          line.contains('error •') ||
          line.contains('warning •')) {
        if (line.startsWith('Error:') ||
            line.contains('error TS') ||
            line.contains('error •')) {
          errorCount++;
        } else {
          warningCount++;
        }
        otherLines.add(line);
      }
    }

    if (groups.isEmpty && otherLines.isEmpty) {
      return trimmedRaw;
    }

    int severityRank(String s) => s == 'error' ? 0 : (s == 'warning' ? 1 : 2);
    final sorted = groups.values.toList()
      ..sort((a, b) {
        final r = severityRank(a.severity).compareTo(severityRank(b.severity));
        if (r != 0) return r;
        return b.lines.length.compareTo(a.lines.length);
      });

    final totalRaw = errorCount + warningCount + infoCount;
    final out = StringBuffer()
      ..writeln(
        'Summary: $errorCount error(s), $warningCount warning(s), $infoCount info(s) '
        '(grouped from $totalRaw raw issues).',
      );

    for (final g in sorted.take(40)) {
      final uniqueLines = g.lines.where((l) => l > 0).toSet().toList()..sort();
      final count = g.lines.length;
      if (count == 1) {
        final loc = uniqueLines.isNotEmpty ? ':${uniqueLines.first}' : '';
        out.writeln('${g.severity} • ${g.file}$loc: ${g.code} — ${g.message}');
      } else {
        final lineDesc = uniqueLines.length <= 4
            ? uniqueLines.join(', ')
            : '${uniqueLines.take(3).join(', ')}..${uniqueLines.last}';
        out.writeln(
          '${g.severity} • ${g.file}: [${count}x] ${g.code} (lines $lineDesc) — ${g.message}',
        );
      }
    }

    for (final extra in otherLines.take(20)) {
      out.writeln(extra);
    }

    return out.toString().trim();
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
