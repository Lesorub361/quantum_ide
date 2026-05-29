enum MessageRole { user, assistant, system }

class AIAction {
  final String type; // 'edit', 'create', 'delete', 'command', 'web_search', 'web_fetch', 'mcp'
  final String path;
  final String content;
  final String? description;
  final String? server; // for MCP
  final String? tool; // for MCP
  final Map<String, dynamic>? arguments; // for MCP
  int? additions;
  int? deletions;

  AIAction({
    required this.type,
    required this.path,
    required this.content,
    this.description,
    this.server,
    this.tool,
    this.arguments,
    this.additions,
    this.deletions,
  });

  factory AIAction.fromJson(Map<String, dynamic> json) {
    return AIAction(
      type: json['type'] ?? 'edit',
      path: json['path'] ?? '',
      content: json['content'] ?? '',
      description: json['description'],
      server: json['server'],
      tool: json['tool'],
      arguments: json['arguments'] != null ? Map<String, dynamic>.from(json['arguments']) : null,
      additions: json['additions'],
      deletions: json['deletions'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'path': path,
      'content': content,
      'description': description,
      if (server != null) 'server': server,
      if (tool != null) 'tool': tool,
      if (arguments != null) 'arguments': arguments,
      if (additions != null) 'additions': additions,
      if (deletions != null) 'deletions': deletions,
    };
  }
}

class ChatMessage {
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final List<AIAction>? actions;
  
  // Structured metadata fields
  final String? taskName;
  final int? stepNumber;
  final int? totalSteps;
  final List<AIAction>? executedActions;
  final Map<String, String>? actionResults;
  final bool isStepSummary;
  final Map<String, String?>? fileBackups;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.actions,
    this.taskName,
    this.stepNumber,
    this.totalSteps,
    this.executedActions,
    this.actionResults,
    this.isStepSummary = false,
    this.fileBackups,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'actions': actions?.map((a) => a.toJson()).toList(),
      'taskName': taskName,
      'stepNumber': stepNumber,
      'totalSteps': totalSteps,
      'executedActions': executedActions?.map((a) => a.toJson()).toList(),
      'actionResults': actionResults,
      'isStepSummary': isStepSummary,
      if (fileBackups != null) 'fileBackups': fileBackups,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: MessageRole.values.firstWhere((e) => e.name == json['role']),
      content: json['content'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      actions: json['actions'] != null
          ? (json['actions'] as List).map((a) => AIAction.fromJson(a)).toList()
          : null,
      taskName: json['taskName'],
      stepNumber: json['stepNumber'],
      totalSteps: json['totalSteps'],
      executedActions: json['executedActions'] != null
          ? (json['executedActions'] as List).map((a) => AIAction.fromJson(a)).toList()
          : null,
      actionResults: json['actionResults'] != null
          ? Map<String, String>.from(json['actionResults'])
          : null,
      isStepSummary: json['isStepSummary'] ?? false,
      fileBackups: json['fileBackups'] != null
          ? Map<String, String?>.from(json['fileBackups'])
          : null,
    );
  }
}


