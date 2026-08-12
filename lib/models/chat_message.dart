enum MessageRole { user, assistant, system }
enum AiInteractionMode { chat, refactor, autopilot, plan }

class AIAction {
  final String type; // 'edit', 'create', 'delete', 'command', 'web_search', 'web_fetch', 'mcp', 'edit_patch'
  final String path;
  final String content;
  final String? description;
  final String? server; // for MCP
  final String? tool; // for MCP
  final Map<String, dynamic>? arguments; // for MCP
  final String? oldText; // for edit_patch: text to find
  final String? newText; // for edit_patch: replacement text
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
    this.oldText,
    this.newText,
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
      oldText: json['old_text'],
      newText: json['new_text'],
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
      if (oldText != null) 'old_text': oldText,
      if (newText != null) 'new_text': newText,
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
  final String? imageBase64;
  final String? imagePath;
  final List<String>? contextFiles;
  String? sessionId;

  // Reasoning/thinking block shown live while streaming
  final String? thinking;
  // Error state: when the assistant message is an error card with retry
  final bool isError;
  final String? errorMessage;
  final String? retryPrompt;
  // Transient: true while tokens are still streaming into this message (not persisted)
  final bool isStreaming;

  // Structured metadata fields
  final String? taskName;
  final int? stepNumber;
  final int? totalSteps;
  final List<AIAction>? executedActions;
  final Map<String, String>? actionResults;
  final bool isStepSummary;
  final bool isActionStep;
  final String? actionStepType;
  final String? actionStepPath;
  final String? actionStepResult;
  final Map<String, String?>? fileBackups;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.actions,
    this.imageBase64,
    this.imagePath,
    this.contextFiles,
    this.thinking,
    this.isError = false,
    this.errorMessage,
    this.retryPrompt,
    this.isStreaming = false,
    this.taskName,
    this.stepNumber,
    this.totalSteps,
    this.executedActions,
    this.actionResults,
    this.isStepSummary = false,
    this.isActionStep = false,
    this.actionStepType,
    this.actionStepPath,
    this.actionStepResult,
    this.fileBackups,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'actions': actions?.map((a) => a.toJson()).toList(),
      'imagePath': imagePath,
      'contextFiles': contextFiles,
      if (thinking != null) 'thinking': thinking,
      'isError': isError,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (retryPrompt != null) 'retryPrompt': retryPrompt,
      'taskName': taskName,
      'stepNumber': stepNumber,
      'totalSteps': totalSteps,
      'executedActions': executedActions?.map((a) => a.toJson()).toList(),
      'actionResults': actionResults,
      'isStepSummary': isStepSummary,
      'isActionStep': isActionStep,
      if (actionStepType != null) 'actionStepType': actionStepType,
      if (actionStepPath != null) 'actionStepPath': actionStepPath,
      if (actionStepResult != null) 'actionStepResult': actionStepResult,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => MessageRole.system,
      ),
      content: json['content'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      actions: json['actions'] != null
          ? (json['actions'] as List).map((a) => AIAction.fromJson(a)).toList()
          : null,
      imagePath: json['imagePath'],
      contextFiles: json['contextFiles'] != null ? List<String>.from(json['contextFiles']) : null,
      thinking: json['thinking'],
      isError: json['isError'] ?? false,
      errorMessage: json['errorMessage'],
      retryPrompt: json['retryPrompt'],
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
      isActionStep: json['isActionStep'] ?? false,
      actionStepType: json['actionStepType'],
      actionStepPath: json['actionStepPath'],
      actionStepResult: json['actionStepResult'],
    );
  }

  ChatMessage copyWith({
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    List<AIAction>? actions,
    String? imageBase64,
    String? imagePath,
    List<String>? contextFiles,
    String? thinking,
    bool? isError,
    String? errorMessage,
    String? retryPrompt,
    bool? isStreaming,
    String? taskName,
    int? stepNumber,
    int? totalSteps,
    List<AIAction>? executedActions,
    Map<String, String>? actionResults,
    bool? isStepSummary,
    bool? isActionStep,
    String? actionStepType,
    String? actionStepPath,
    String? actionStepResult,
    Map<String, String?>? fileBackups,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      actions: actions ?? this.actions,
      imageBase64: imageBase64 ?? this.imageBase64,
      imagePath: imagePath ?? this.imagePath,
      contextFiles: contextFiles ?? this.contextFiles,
      thinking: thinking ?? this.thinking,
      isError: isError ?? this.isError,
      errorMessage: errorMessage ?? this.errorMessage,
      retryPrompt: retryPrompt ?? this.retryPrompt,
      isStreaming: isStreaming ?? this.isStreaming,
      taskName: taskName ?? this.taskName,
      stepNumber: stepNumber ?? this.stepNumber,
      totalSteps: totalSteps ?? this.totalSteps,
      executedActions: executedActions ?? this.executedActions,
      actionResults: actionResults ?? this.actionResults,
      isStepSummary: isStepSummary ?? this.isStepSummary,
      isActionStep: isActionStep ?? this.isActionStep,
      actionStepType: actionStepType ?? this.actionStepType,
      actionStepPath: actionStepPath ?? this.actionStepPath,
      actionStepResult: actionStepResult ?? this.actionStepResult,
      fileBackups: fileBackups ?? this.fileBackups,
    );
  }
}


