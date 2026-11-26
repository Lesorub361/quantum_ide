/// Supported AI provider presets in QuantumIDE.
enum AiProvider {
  deepseek('DeepSeek', 'deepseek-chat'),
  deepseekR1('DeepSeek R1', 'deepseek-reasoner'),
  openrouterClaude('Claude 3.7 Sonnet', 'anthropic/claude-3.7-sonnet'),
  openrouterGpt4o('GPT-4o (OpenRouter)', 'openai/gpt-4o'),
  openrouterQwen('Qwen 2.5 Coder 32B', 'qwen/qwen-2.5-coder-32b-instruct'),
  openrouterGemini('Gemini 2.5 Pro', 'google/gemini-2.5-pro'),
  geminiDirect('Gemini 2.5 Flash (Direct)', 'gemini-2.5-flash'),
  groqCloud('Groq Llama 3.3 70B', 'llama-3.3-70b-versatile'),
  xaiGrok('xAI Grok 3', 'grok-3'),
  mistralCodestral('Mistral Codestral', 'codestral-latest'),
  openai('OpenAI GPT-4o', 'gpt-4o'),
  anthropic('Anthropic Claude', 'claude-3-7-sonnet-20250219'),
  custom('Локальный / Custom API', 'default');

  final String label;
  final String defaultModel;
  const AiProvider(this.label, this.defaultModel);
}

enum MessageRole { user, assistant, system }

/// Кто выполняет задачу: встроенный агент или внешний CLI-агент (headless).
enum AgentEngine {
  builtin('Встроенный'),
  claudeCode('Claude Code'),
  antigravity('Antigravity');

  final String label;
  const AgentEngine(this.label);
}

/// Ask — только чтение и ответы; Plan — составить план без правок; Build — полный доступ.
enum AgentMode {
  ask('Ask', 'Только чтение и ответы'),
  plan('Plan', 'Составить план, без правок'),
  build('Build', 'Писать код и запускать команды');

  final String label;
  final String hint;
  const AgentMode(this.label, this.hint);
}

class ChatAttachment {
  final String name;
  final String path;
  final String mimeType;
  final bool isImage;
  final String? base64Data;
  final String? textContent;
  final int sizeBytes;

  const ChatAttachment({
    required this.name,
    required this.path,
    required this.mimeType,
    required this.isImage,
    this.base64Data,
    this.textContent,
    this.sizeBytes = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'mimeType': mimeType,
    'isImage': isImage,
    'sizeBytes': sizeBytes,
    'textContent': textContent,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    name: json['name'] as String? ?? '',
    path: json['path'] as String? ?? '',
    mimeType: json['mimeType'] as String? ?? 'text/plain',
    isImage: json['isImage'] as bool? ?? false,
    sizeBytes: json['sizeBytes'] as int? ?? 0,
    textContent: json['textContent'] as String?,
  );
}

class AgentAction {
  final String type; // 'write_file', 'read_file', 'run_command', 'diff'
  final String path;
  final String? content;
  final String? command;
  bool isExecuted;
  bool isExecuting;
  String? executionError;
  String? output;

  /// Состояние файла ДО применения (для отката). null → файла не было.
  String? backupContent;
  bool backupTaken = false;
  bool isUndone = false;

  AgentAction({
    required this.type,
    required this.path,
    this.content,
    this.command,
    this.isExecuted = false,
    this.isExecuting = false,
    this.executionError,
    this.output,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'path': path,
    'content': content,
    'command': command,
    'isExecuted': isExecuted,
    'executionError': executionError,
    'output': output,
    'isUndone': isUndone,
  };

  factory AgentAction.fromJson(Map<String, dynamic> json) => AgentAction(
    type: json['type'] as String? ?? 'write_file',
    path: json['path'] as String? ?? '',
    content: json['content'] as String?,
    command: json['command'] as String?,
    isExecuted: json['isExecuted'] as bool? ?? false,
    executionError: json['executionError'] as String?,
    output: json['output'] as String?,
  )..isUndone = json['isUndone'] as bool? ?? false;
}

class ChatMessage {
  final String id;
  final MessageRole role;
  String text;
  String? thinking;
  bool isThinking;
  bool isStreaming;
  final DateTime timestamp;
  final List<AgentAction> actions;
  final List<ChatAttachment> attachments;

  /// Non-null for tool-result messages (shown as a compact chip, sent to the model as context).
  final String? toolLabel;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.thinking,
    this.isThinking = false,
    this.isStreaming = false,
    required this.timestamp,
    List<AgentAction>? actions,
    List<ChatAttachment>? attachments,
    this.toolLabel,
  }) : actions = actions ?? [],
       attachments = attachments ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'thinking': thinking,
    'timestamp': timestamp.toIso8601String(),
    'toolLabel': toolLabel,
    'actions': actions.map((a) => a.toJson()).toList(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
    role: MessageRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => MessageRole.assistant,
    ),
    text: json['text'] as String? ?? '',
    thinking: json['thinking'] as String?,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    toolLabel: json['toolLabel'] as String?,
    actions: (json['actions'] as List?)
        ?.map((a) => AgentAction.fromJson(a as Map<String, dynamic>))
        .toList(),
    attachments: (json['attachments'] as List?)
        ?.map((a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
        .toList(),
  );
}

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  String? modelId;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.modelId,
    required this.messages,
  });

  String get preview {
    final firstUser = messages.firstWhere(
      (m) => m.role == MessageRole.user,
      orElse: () => messages.isNotEmpty
          ? messages.first
          : ChatMessage(
              id: '',
              role: MessageRole.user,
              text: 'Новый диалог',
              timestamp: DateTime.now(),
            ),
    );
    final clean = firstUser.text.trim();
    if (clean.length > 60) return '${clean.substring(0, 60)}...';
    return clean.isEmpty ? 'Новый диалог' : clean;
  }

  int get userMessageCount =>
      messages.where((m) => m.role == MessageRole.user).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'modelId': modelId,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id:
          json['id'] as String? ??
          'session_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Новый диалог',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      modelId: json['modelId'] as String?,
      messages:
          (json['messages'] as List?)
              ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
