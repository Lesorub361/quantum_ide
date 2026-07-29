import 'package:quantum_ide/core/services/agent/agent_tool_output_store.dart';

class AgentToolSettlement {
  final String result;
  final List<String> outputPaths;
  AgentToolSettlement({required this.result, this.outputPaths = const []});
}

abstract class AgentTool {
  String get name;
  String get description;
  Map<String, dynamic> get inputSchema;
  bool get requiresPermission;

  Future<AgentToolSettlement> execute({
    required Map<String, dynamic> arguments,
    required String sessionId,
    required AgentToolOutputStore outputStore,
  });
}
