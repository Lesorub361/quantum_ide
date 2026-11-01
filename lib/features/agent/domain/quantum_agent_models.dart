import 'dart:convert';

class AgentToolCall {
  final String id;
  final String toolName;
  final String title;
  final Map<String, dynamic> arguments;
  final String? result;
  final bool isError;
  final bool isRunning;

  const AgentToolCall({
    required this.id,
    required this.toolName,
    required this.title,
    required this.arguments,
    this.result,
    this.isError = false,
    this.isRunning = false,
  });

  AgentToolCall copyWith({
    String? id,
    String? toolName,
    String? title,
    Map<String, dynamic>? arguments,
    String? result,
    bool? isError,
    bool? isRunning,
  }) {
    return AgentToolCall(
      id: id ?? this.id,
      toolName: toolName ?? this.toolName,
      title: title ?? this.title,
      arguments: arguments ?? this.arguments,
      result: result ?? this.result,
      isError: isError ?? this.isError,
      isRunning: isRunning ?? this.isRunning,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'toolName': toolName,
        'title': title,
        'arguments': arguments,
        'result': result,
        'isError': isError,
        'isRunning': isRunning,
      };

  factory AgentToolCall.fromJson(Map<String, dynamic> json) => AgentToolCall(
        id: json['id']?.toString() ?? '',
        toolName: json['toolName']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        arguments: (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
        result: json['result']?.toString(),
        isError: json['isError'] == true,
        isRunning: json['isRunning'] == true,
      );
}

class AgentChatMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? thinking;
  final List<AgentToolCall> toolCalls;
  final List<String> modifiedFiles;
  final DateTime timestamp;
  final bool isStreaming;

  const AgentChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thinking,
    this.toolCalls = const [],
    this.modifiedFiles = const [],
    required this.timestamp,
    this.isStreaming = false,
  });

  AgentChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    String? thinking,
    List<AgentToolCall>? toolCalls,
    List<String>? modifiedFiles,
    DateTime? timestamp,
    bool? isStreaming,
  }) {
    return AgentChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thinking: thinking ?? this.thinking,
      toolCalls: toolCalls ?? this.toolCalls,
      modifiedFiles: modifiedFiles ?? this.modifiedFiles,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'thinking': thinking,
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
        'modifiedFiles': modifiedFiles,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AgentChatMessage.fromJson(Map<String, dynamic> json) => AgentChatMessage(
        id: json['id']?.toString() ?? '',
        role: json['role']?.toString() ?? 'assistant',
        content: json['content']?.toString() ?? '',
        thinking: json['thinking']?.toString(),
        toolCalls: (json['toolCalls'] as List?)
                ?.map((e) => AgentToolCall.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        modifiedFiles: (json['modifiedFiles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      );
}

class QuantumAgentProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final List<String> models;
  final String keyHint;
  final bool requiresKey;

  const QuantumAgentProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
    required this.keyHint,
    this.requiresKey = true,
  });

  static const List<QuantumAgentProviderPreset> presets = [
    QuantumAgentProviderPreset(
      id: 'antigravity_doctor',
      name: '⚡ Quantum Auto-Doctor + Antigravity Bridge (Без ключа)',
      baseUrl: 'http://127.0.0.1:45169',
      models: ['quantum-doctor-v2'],
      keyHint: 'Ключ не требуется',
      requiresKey: false,
    ),
    QuantumAgentProviderPreset(
      id: 'openrouter',
      name: '🌐 OpenRouter (DeepSeek / Qwen / Gemini - есть Free)',
      baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
      models: [
        'deepseek/deepseek-chat-v3-0324:free',
        'qwen/qwen-2.5-coder-32b-instruct:free',
        'google/gemini-2.5-flash',
        'anthropic/claude-3.7-sonnet',
      ],
      keyHint: 'sk-or-v1-...',
    ),
    QuantumAgentProviderPreset(
      id: 'gemini',
      name: '✨ Google Gemini API',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      models: [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash',
      ],
      keyHint: 'AIzaSy...',
    ),
    QuantumAgentProviderPreset(
      id: 'groq',
      name: '🚀 Groq Cloud (Сверхбыстрый Llama 3.3 / Qwen Coder)',
      baseUrl: 'https://api.groq.com/openai/v1/chat/completions',
      models: [
        'llama-3.3-70b-versatile',
        'qwen-2.5-coder-32b',
        'deepseek-r1-distill-llama-70b',
      ],
      keyHint: 'gsk_...',
    ),
    QuantumAgentProviderPreset(
      id: 'deepseek',
      name: '🐋 DeepSeek Official API',
      baseUrl: 'https://api.deepseek.com/chat/completions',
      models: [
        'deepseek-chat',
        'deepseek-reasoner',
      ],
      keyHint: 'sk-...',
    ),
    QuantumAgentProviderPreset(
      id: 'openai',
      name: '🤖 OpenAI API',
      baseUrl: 'https://api.openai.com/v1/chat/completions',
      models: [
        'gpt-4o',
        'gpt-4o-mini',
      ],
      keyHint: 'sk-...',
    ),
  ];

  static QuantumAgentProviderPreset byId(String id) {
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () => presets.first,
    );
  }
}

class QuantumAgentState {
  final List<AgentChatMessage> messages;
  final bool isWorking;
  final String statusText;
  final String providerId;
  final String modelId;
  final String apiKey;
  final bool autoApplyEdits;

  const QuantumAgentState({
    this.messages = const [],
    this.isWorking = false,
    this.statusText = '',
    this.providerId = 'antigravity_doctor',
    this.modelId = 'quantum-doctor-v2',
    this.apiKey = '',
    this.autoApplyEdits = true,
  });

  QuantumAgentState copyWith({
    List<AgentChatMessage>? messages,
    bool? isWorking,
    String? statusText,
    String? providerId,
    String? modelId,
    String? apiKey,
    bool? autoApplyEdits,
  }) {
    return QuantumAgentState(
      messages: messages ?? this.messages,
      isWorking: isWorking ?? this.isWorking,
      statusText: statusText ?? this.statusText,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      apiKey: apiKey ?? this.apiKey,
      autoApplyEdits: autoApplyEdits ?? this.autoApplyEdits,
    );
  }

  String exportHistoryJson() => jsonEncode(messages.map((m) => m.toJson()).toList());
}
