/// How dangerous a tool invocation is — drives the confirmation policy.
/// Ported from PocketStrike (MIT) to keep tool execution predictable.
enum ToolRisk {
  safe,
  external,
  destructive,
}

enum ConfirmationPolicy {
  alwaysAsk,
  destructiveOnly,
  autonomous,
}

extension ConfirmationPolicyX on ConfirmationPolicy {
  String get id => switch (this) {
        ConfirmationPolicy.alwaysAsk => 'alwaysAsk',
        ConfirmationPolicy.destructiveOnly => 'destructiveOnly',
        ConfirmationPolicy.autonomous => 'autonomous',
      };

  static ConfirmationPolicy fromId(String? id) => switch (id) {
        'alwaysAsk' => ConfirmationPolicy.alwaysAsk,
        'autonomous' => ConfirmationPolicy.autonomous,
        _ => ConfirmationPolicy.destructiveOnly,
      };
}

enum ConfirmResult { allow, allowAlways, deny }

/// One normalized tool for the ReAct engine.
///
/// Built-in IDE tools and MCP tools both converge here. MCP tools are named
/// `mcp__<server>__<tool>` so names can't collide across servers.
class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.risk,
    required this.run,
    this.mcpServerId,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final ToolRisk risk;

  /// Returns a plain-text observation that is fed back to the model.
  final Future<String> Function(Map<String, dynamic> args) run;

  final String? mcpServerId;

  Map<String, dynamic> toSpec() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': inputSchema,
        },
      };
}
