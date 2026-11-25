import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart'
    show
        CallToolRequest,
        Implementation,
        McpClient,
        SseClientTransport,
        SseClientTransportOptions,
        StreamableHttpClientTransport,
        StreamableHttpClientTransportOptions,
        TextContent,
        Tool,
        Transport;

import '../domain/agent_tool.dart';

enum McpStatus { idle, connecting, connected, reconnecting, error }

/// Minimal persisted server config (SQLite/SharedPreferences adapter supplies it).
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.transport = 'streamable_http',
    this.enabled = true,
    this.headers = const {},
  });

  final String id;
  final String name;
  final String url;
  final String transport;
  final bool enabled;
  final Map<String, String> headers;
}

class McpConnection {
  const McpConnection({
    required this.config,
    required this.status,
    this.tools = const [],
    this.error,
  });

  final McpServerConfig config;
  final McpStatus status;
  final List<AgentTool> tools;
  final String? error;
}

/// Holds live MCP clients and exposes their tools as normalized [AgentTool]s.
/// Ported from PocketStrike (MIT) with a generic config model.
class McpConnectionManager {
  McpConnectionManager({this.onStatusChanged});

  final void Function(McpConnection connection)? onStatusChanged;

  final Map<String, McpConnection> _connections = {};
  final Map<String, McpClient> _clients = {};
  final Map<String, int> _retries = {};

  Map<String, McpConnection> get connections => Map.unmodifiable(_connections);

  List<AgentTool> toolsForServers(Set<String> serverIds) => [
        for (final entry in _connections.entries)
          if (entry.value.status == McpStatus.connected &&
              serverIds.contains(entry.key))
            ...entry.value.tools,
      ];

  Transport _transport(McpServerConfig c) {
    final uri = Uri.parse(c.url.trim());
    if (c.transport == 'sse') {
      // ignore: deprecated_member_use
      return SseClientTransport(
        uri,
        // ignore: deprecated_member_use
        opts: SseClientTransportOptions(headers: c.headers),
      );
    }
    return StreamableHttpClientTransport(
      uri,
      opts: StreamableHttpClientTransportOptions(
        requestInit: c.headers.isNotEmpty ? {'headers': c.headers} : null,
      ),
    );
  }

  ToolRisk _risk(String name, String? description) {
    final n = name.toLowerCase();
    final d = (description ?? '').toLowerCase();
    if (n.contains('delete') ||
        n.contains('remove') ||
        n.contains('kill') ||
        n.contains('format') ||
        n.contains('drop') ||
        d.contains('irreversible')) {
      return ToolRisk.destructive;
    }
    if (n.contains('get') ||
        n.contains('list') ||
        n.contains('read') ||
        n.contains('search') ||
        n.contains('query') ||
        n.contains('status') ||
        n.contains('info') ||
        n.contains('count') ||
        n.contains('find')) {
      return ToolRisk.safe;
    }
    return ToolRisk.external;
  }

  Future<void> connect(McpServerConfig config) async {
    await disconnect(config.id, silent: true);
    _set(config, McpStatus.connecting);

    final client = McpClient(
      const Implementation(name: 'QuantumIDE', version: '1.2.312'),
    );

    try {
      await client.connect(_transport(config)).timeout(const Duration(seconds: 20));
      _clients[config.id] = client;

      final result = await client.listTools();
      final tools = [
        for (final tool in result.tools)
          AgentTool(
            name: 'mcp__${config.id}__${tool.name}',
            description: tool.description ?? tool.title ?? tool.name,
            inputSchema: _schema(tool),
            risk: _risk(tool.name, tool.description),
            mcpServerId: config.id,
            run: (args) => _call(config.id, tool.name, args),
          ),
      ];

      _retries.remove(config.id);
      final conn = McpConnection(
        config: config,
        status: McpStatus.connected,
        tools: tools,
      );
      _connections[config.id] = conn;
      onStatusChanged?.call(conn);
    } catch (e) {
      final conn = McpConnection(
        config: config,
        status: McpStatus.error,
        error: e.toString(),
      );
      _connections[config.id] = conn;
      onStatusChanged?.call(conn);
      _scheduleReconnect(config);
    }
  }

  void _set(McpServerConfig config, McpStatus status) {
    final conn = McpConnection(config: config, status: status);
    _connections[config.id] = conn;
    onStatusChanged?.call(conn);
  }

  Map<String, dynamic> _schema(Tool tool) {
    try {
      return tool.inputSchema.toJson();
    } catch (_) {
      return const {'type': 'object', 'properties': <String, dynamic>{}};
    }
  }

  Future<String> _call(
    String serverId,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    final client = _clients[serverId];
    if (client == null) {
      throw StateError('MCP server "$serverId" is not connected');
    }
    final result = await client.callTool(
      CallToolRequest(name: toolName, arguments: args),
    );
    final buffer = StringBuffer();
    for (final content in result.content) {
      if (content is TextContent) {
        buffer.writeln(content.text);
      } else {
        buffer.writeln('[${content.type} content]');
      }
    }
    final text = buffer.toString().trim();
    if (result.isError) {
      throw StateError(text.isEmpty ? 'MCP tool returned an error' : text);
    }
    return text.isEmpty ? '(no output)' : text;
  }

  void _scheduleReconnect(McpServerConfig config) {
    final attempt = (_retries[config.id] ?? 0) + 1;
    _retries[config.id] = attempt;
    if (attempt > 5) return;
    Timer(Duration(seconds: 2 * attempt), () {
      if (_connections[config.id]?.status == McpStatus.error) {
        unawaited(connect(config));
      }
    });
  }

  Future<void> disconnect(String id, {bool silent = false}) async {
    final client = _clients.remove(id);
    if (client != null) unawaited(client.close());
    if (!silent) {
      final conn = _connections[id];
      if (conn != null) {
        final next = McpConnection(config: conn.config, status: McpStatus.idle);
        _connections[id] = next;
        onStatusChanged?.call(next);
      }
    }
  }

  Future<void> disposeAll() async {
    for (final client in _clients.values) {
      unawaited(client.close());
    }
    _clients.clear();
    _connections.clear();
  }
}
