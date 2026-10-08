import 'package:quantum_ide/core/models/agent_activity_item.dart';

enum MessageRole { user, assistant, system }
enum AiInteractionMode { chat, ask, refactor, autopilot, plan, debug }

class AIAction {
  final String type; // 'read_file', 'list_dir', 'grep_search', 'find_symbols', 'create', 'edit', 'rewrite_whole_file', 'replace_code_block', 'delete', 'command', 'web_search', 'web_fetch', 'mcp', 'insert_log', 'git_stash', 'git_commit'
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
      oldText: json['old_text'] ?? json['search_block'],
      newText: json['new_text'] ?? json['replace_block'],
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
  final List<ActivityItem> workItems;
  final int workedMillis;
  final String? thinkingContent;
  final bool isThinking;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.actions,
    this.imageBase64,
    this.imagePath,
    this.contextFiles,
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
    this.workItems = const [],
    this.workedMillis = 0,
    this.thinkingContent,
    this.isThinking = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'actions': actions?.map((a) => a.toJson()).toList(),
      'imagePath': imagePath,
      'contextFiles': contextFiles,
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
      'workItems': workItems.map((w) => w.toJson()).toList(),
      'workedMillis': workedMillis,
      if (thinkingContent != null) 'thinkingContent': thinkingContent,
      'isThinking': isThinking,
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
      workItems: json['workItems'] != null
          ? (json['workItems'] as List).map((w) => ActivityItem.fromJson(w)).toList()
          : const [],
      workedMillis: json['workedMillis'] ?? 0,
      thinkingContent: json['thinkingContent'],
      isThinking: json['isThinking'] ?? false,
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
    String? sessionId,
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
    List<ActivityItem>? workItems,
    int? workedMillis,
    String? thinkingContent,
    bool? isThinking,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      actions: actions ?? this.actions,
      imageBase64: imageBase64 ?? this.imageBase64,
      imagePath: imagePath ?? this.imagePath,
      contextFiles: contextFiles ?? this.contextFiles,
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
      workItems: workItems ?? this.workItems,
      workedMillis: workedMillis ?? this.workedMillis,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      isThinking: isThinking ?? this.isThinking,
    )..sessionId = sessionId ?? this.sessionId;
  }
}


