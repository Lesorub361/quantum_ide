import 'dart:async';
import 'package:quantum_ide/core/services/agent/agent_tool.dart';
import 'package:quantum_ide/core/services/agent/agent_tool_output_store.dart';

class AgentToolRegistry {
  final Map<String, AgentTool> _tools = {};
  final Map<String, Map<String, dynamic>> _inputSchemas = {};

  void register(AgentTool tool) {
    _tools[tool.name] = tool;
    _inputSchemas[tool.name] = tool.inputSchema;
  }

  Map<String, Map<String, dynamic>> get definitions {
    final result = <String, Map<String, dynamic>>{};
    for (final entry in _tools.entries) {
      result[entry.key] = {
        'type': 'function',
        'function': {
          'name': entry.key,
          'description': entry.value.description,
          'parameters': entry.value.inputSchema,
        },
      };
    }
    return result;
  }

  List<String> get names => _tools.keys.toList();

  bool contains(String name) => _tools.containsKey(name);

  Future<AgentToolSettlement> settle({
    required String name,
    required Map<String, dynamic> arguments,
    required String sessionId,
    required AgentToolOutputStore outputStore,
  }) async {
    final tool = _tools[name];
    if (tool == null) {
      return AgentToolSettlement(result: 'Error: Unknown tool: $name');
    }

    try {
      final result = await tool.execute(
        arguments: arguments,
        sessionId: sessionId,
        outputStore: outputStore,
      );
      return result;
    } catch (e) {
      return AgentToolSettlement(result: 'Error executing $name: $e');
    }
  }
}
