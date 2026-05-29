import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum McpServerType { stdio, sse }

class McpServerConfig {
  final String name;
  final McpServerType type;
  final String command; // for stdio
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
  Process? _process;
  HttpClientRequest? _sseRequest;
  HttpClientResponse? _sseResponse;
  String? _ssePostUrl;
  final StreamController<String> _incomingMessages = StreamController<String>.broadcast();
  int _requestId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  bool _isConnecting = false;

  McpClientInstance(this.config);

  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      if (config.type == McpServerType.stdio) {
        await _connectStdio();
      } else {
        await _connectSse();
      }
    } catch (e) {
      debugPrint('Error connecting to MCP server ${config.name}: $e');
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _connectStdio() async {
    if (config.command.isEmpty) return;
    try {
      _process = await Process.start(
        config.command,
        config.args,
        environment: config.env.isNotEmpty ? config.env : null,
      );
      
      // Handle stderr
      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('MCP [${config.name}] stderr: $data');
      });

      // Handle stdout
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleIncomingLine(line);
      });
    } catch (e) {
      debugPrint('Failed to start stdio MCP client: $e');
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
        if (line.startsWith('event:')) {
          final event = line.substring(6).trim();
          if (event == 'endpoint') {
            // Next data line will contain the endpoint URL for POST requests
          }
        } else if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          try {
            // First data can be the session endpoint configuration
            if (_ssePostUrl == null) {
              if (data.startsWith('http') || data.startsWith('/')) {
                _ssePostUrl = data;
                if (_ssePostUrl!.startsWith('/')) {
                  final baseUri = Uri.parse(config.url);
                  _ssePostUrl = '${baseUri.scheme}://${baseUri.host}:${baseUri.port}$_ssePostUrl';
                }
                debugPrint('MCP [${config.name}] SSE session endpoint: $_ssePostUrl');
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
    try {
      final json = jsonDecode(line.trim());
      if (json is Map<String, dynamic>) {
        if (json.containsKey('id')) {
          final id = json['id'] as int;
          if (_pendingRequests.containsKey(id)) {
            _pendingRequests[id]!.complete(json);
            _pendingRequests.remove(id);
          }
        }
      }
    } catch (e) {
      // Not a valid JSON-RPC, ignore or log
    }
  }

  Future<Map<String, dynamic>> sendRequest(String method, Map<String, dynamic> params) async {
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
        // SSE requires POST requests for commands
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

    // Await with a timeout
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request $method timed out');
      },
    );
  }

  Future<List<Map<String, dynamic>>> listTools() async {
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

  Future<Map<String, dynamic>> callTool(String toolName, Map<String, dynamic> arguments) async {
    final res = await sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    if (res.containsKey('error')) {
      throw Exception(res['error']['message'] ?? 'MCP execution error');
    }
    return res['result'] ?? {};
  }

  void disconnect() {
    _process?.kill();
    _process = null;
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
  final Map<String, McpClientInstance> _clients = {};
  bool _internetAccess = true;

  McpService() : super([]) {
    _loadConfigs();
  }

  bool get internetAccess => _internetAccess;

  Future<void> _loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    _internetAccess = prefs.getBool('mcp_internet_access') ?? true;
    final list = prefs.getStringList('mcp_servers');
    if (list != null) {
      try {
        state = list
            .map((s) => McpServerConfig.fromJson(jsonDecode(s)))
            .toList();
        // Connect to enabled servers
        for (final server in state) {
          if (server.isEnabled) {
            _getOrCreateClient(server).connect();
          }
        }
      } catch (e) {
        debugPrint('Error loading MCP configs: $e');
      }
    }
  }

  Future<void> setInternetAccess(bool enabled) async {
    _internetAccess = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mcp_internet_access', enabled);
    state = [...state]; // Trigger rebuild
  }

  McpClientInstance _getOrCreateClient(McpServerConfig server) {
    if (!_clients.containsKey(server.name)) {
      _clients[server.name] = McpClientInstance(server);
    }
    return _clients[server.name]!;
  }

  Future<void> saveConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = state.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('mcp_servers', list);
  }

  Future<void> addServer(McpServerConfig config) async {
    state = [...state, config];
    await saveConfigs();
    if (config.isEnabled) {
      await _getOrCreateClient(config).connect();
    }
  }

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
          _getOrCreateClient(updated).connect();
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
      }
    }
    return allTools;
  }

  Future<Map<String, dynamic>> executeMcpTool(String serverName, String toolName, Map<String, dynamic> arguments) async {
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

final mcpServiceProvider = StateNotifierProvider<McpService, List<McpServerConfig>>((ref) {
  return McpService();
});
