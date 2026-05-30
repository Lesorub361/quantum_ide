/// Конфигурация AI провайдера
class AiProviderConfig {
  final String id;
  final String displayName;
  final String logoEmoji;
  final String apiKeyHint;
  final String baseUrl;
  final List<String> defaultModels;
  final bool supportsLocalModels;
  final bool requiresApiKey;

  const AiProviderConfig({
    required this.id,
    required this.displayName,
    required this.logoEmoji,
    required this.apiKeyHint,
    required this.baseUrl,
    required this.defaultModels,
    this.supportsLocalModels = false,
    this.requiresApiKey = true,
  });
}

enum LocalAiEngine { llamaServer, ollama, lmStudio }

extension LocalAiEngineExtension on LocalAiEngine {
  String get id {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return 'llama_server';
      case LocalAiEngine.ollama:
        return 'ollama';
      case LocalAiEngine.lmStudio:
        return 'lm_studio';
    }
  }

  String get displayName {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return 'llama-server (built-in)';
      case LocalAiEngine.ollama:
        return 'Ollama';
      case LocalAiEngine.lmStudio:
        return 'LM Studio';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return 'http://localhost:8080/v1';
      case LocalAiEngine.ollama:
        return 'http://localhost:11434';
      case LocalAiEngine.lmStudio:
        return 'http://localhost:1234/v1';
    }
  }

  List<String> get defaultModels {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return ['qwen2.5-coder-1.5b-instruct'];
      case LocalAiEngine.ollama:
        return ['qwen2.5-coder', 'llama3.2', 'llama3.1', 'codellama', 'gemma2'];
      case LocalAiEngine.lmStudio:
        return ['local-model'];
    }
  }
}

/// Все доступные AI провайдеры
class AiProviders {
  static const google = AiProviderConfig(
    id: 'google',
    displayName: 'Google Gemini',
    logoEmoji: '✨',
    apiKeyHint: 'AIza...',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModels: [
      'gemini-2.5-pro-preview-05-06',
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
      'gemini-1.5-flash-8b',
    ],
    supportsLocalModels: true,
  );

  static const openai = AiProviderConfig(
    id: 'openai',
    displayName: 'OpenAI',
    logoEmoji: '🤖',
    apiKeyHint: 'sk-...',
    baseUrl: 'https://api.openai.com/v1',
    defaultModels: [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'gpt-4',
      'gpt-3.5-turbo',
      'o1-preview',
      'o1-mini',
    ],
    supportsLocalModels: true,
  );

  static const anthropic = AiProviderConfig(
    id: 'anthropic',
    displayName: 'Anthropic Claude',
    logoEmoji: '🧠',
    apiKeyHint: 'sk-ant-...',
    baseUrl: 'https://api.anthropic.com/v1',
    defaultModels: [
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'claude-haiku-4-5',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
    ],
    supportsLocalModels: true,
  );

  static const deepseek = AiProviderConfig(
    id: 'deepseek',
    displayName: 'DeepSeek',
    logoEmoji: '🐳',
    apiKeyHint: 'sk-...',
    baseUrl: 'https://api.deepseek.com',
    defaultModels: ['deepseek-chat', 'deepseek-coder'],
    supportsLocalModels: true,
  );

  static const groq = AiProviderConfig(
    id: 'groq',
    displayName: 'Groq',
    logoEmoji: '⚡',
    apiKeyHint: 'gsk_...',
    baseUrl: 'https://api.groq.com/openai/v1',
    defaultModels: [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'mixtral-8x7b-32768',
      'gemma2-9b-it',
    ],
    supportsLocalModels: true,
  );

  static const openrouter = AiProviderConfig(
    id: 'openrouter',
    displayName: 'OpenRouter',
    logoEmoji: '🌐',
    apiKeyHint: 'sk-or-...',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModels: [
      'deepseek/deepseek-chat',
      'google/gemini-2.5-pro',
      'anthropic/claude-3.5-sonnet',
      'meta-llama/llama-3.3-70b-instruct',
    ],
    supportsLocalModels: true,
  );

  static const localEdge = AiProviderConfig(
    id: 'local_edge',
    displayName: 'Local AI',
    logoEmoji: '🔮',
    apiKeyHint: 'not required',
    baseUrl: 'http://localhost:8080/v1',
    defaultModels: ['qwen2.5-coder-1.5b-instruct'],
    supportsLocalModels: true,
    requiresApiKey: false,
  );

  static const all = [
    google,
    openai,
    anthropic,
    deepseek,
    groq,
    openrouter,
    localEdge,
  ];

  static AiProviderConfig byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => google);
  }
}
