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

enum LocalAiEngine { llamaServer, ollama, lmStudio, mistralRs }

extension LocalAiEngineExtension on LocalAiEngine {
  String get id {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return 'llama_server';
      case LocalAiEngine.ollama:
        return 'ollama';
      case LocalAiEngine.lmStudio:
        return 'lm_studio';
      case LocalAiEngine.mistralRs:
        return 'mistral_rs';
    }
  }

  String get displayName {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return 'Встроенный движок (llama.cpp)';
      case LocalAiEngine.ollama:
        return 'Ollama';
      case LocalAiEngine.lmStudio:
        return 'LM Studio';
      case LocalAiEngine.mistralRs:
        return 'Mistral.rs (Rust)';
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
      case LocalAiEngine.mistralRs:
        return 'http://localhost:1234/v1';
    }
  }

  // Локальные движки не показывают «фейковые» модели по умолчанию:
  // список берётся либо из запущенного сервера, либо из скачанных моделей в каталоге.
  List<String> get defaultModels {
    switch (this) {
      case LocalAiEngine.llamaServer:
        return [];
      case LocalAiEngine.ollama:
        return [];
      case LocalAiEngine.lmStudio:
        return [];
      case LocalAiEngine.mistralRs:
        return [];
    }
  }
}

/// Все доступные AI провайдеры
class AiProviders {
  static const google = AiProviderConfig(
    id: 'google',
    displayName: 'Antigravity',
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

  static const grok = AiProviderConfig(
    id: 'grok',
    displayName: 'Grok (xAI)',
    logoEmoji: '🤖',
    apiKeyHint: 'xai-...',
    baseUrl: 'https://api.x.ai/v1',
    defaultModels: ['grok-2', 'grok-2-mini', 'grok-3', 'grok-3-mini'],
  );

  static const together = AiProviderConfig(
    id: 'together',
    displayName: 'Together AI',
    logoEmoji: '🤝',
    apiKeyHint: '...',
    baseUrl: 'https://api.together.xyz/v1',
    defaultModels: [
      'meta-llama/Llama-3-70b-chat-hf',
      'mistralai/Mixtral-8x7B-Instruct-v0.1',
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct-Turbo',
    ],
  );

  static const perplexity = AiProviderConfig(
    id: 'perplexity',
    displayName: 'Perplexity',
    logoEmoji: '🔍',
    apiKeyHint: 'pplx-...',
    baseUrl: 'https://api.perplexity.ai',
    defaultModels: [
      'llama-3.1-sonar-small-128k-online',
      'llama-3.1-sonar-large-128k-online',
      'llama-3.1-sonar-huge-128k-online',
    ],
  );

  static const fireworks = AiProviderConfig(
    id: 'fireworks',
    displayName: 'Fireworks AI',
    logoEmoji: '🎆',
    apiKeyHint: 'fw-...',
    baseUrl: 'https://api.fireworks.ai/inference/v1',
    defaultModels: [
      'accounts/fireworks/models/llama-v3p1-70b-instruct',
      'accounts/fireworks/models/mixtral-8x22b-instruct',
    ],
  );

  static const custom = AiProviderConfig(
    id: 'custom',
    displayName: 'Custom API',
    logoEmoji: '⚙️',
    apiKeyHint: 'API key',
    baseUrl: 'http://localhost:11434/v1',
    defaultModels: ['custom-model'],
    requiresApiKey: false,
  );

  static const localEdge = AiProviderConfig(
    id: 'local_edge',
    displayName: 'Local AI',
    logoEmoji: '🔮',
    apiKeyHint: 'not required',
    baseUrl: 'http://localhost:8080/v1',
    defaultModels: [],
    supportsLocalModels: true,
    requiresApiKey: false,
  );

  static const kimi = AiProviderConfig(
    id: 'kimi',
    displayName: 'Kimi (Moonshot AI)',
    logoEmoji: '🌙',
    apiKeyHint: 'sk-...',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModels: [
      'moonshot-v1-8k',
      'moonshot-v1-32k',
      'moonshot-v1-128k',
    ],
  );

  static const nvidia = AiProviderConfig(
    id: 'nvidia',
    displayName: 'NVIDIA NIM',
    logoEmoji: '💚',
    apiKeyHint: 'nvapi-...',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    defaultModels: [
      'meta/llama-3.1-8b-instruct',
      'meta/llama-3.1-70b-instruct',
      'mistralai/mistral-7b-instruct-v0.3',
      'google/gemma-2-9b-it',
    ],
  );

  static const all = [
    google,
    openai,
    anthropic,
    deepseek,
    groq,
    openrouter,
    grok,
    together,
    perplexity,
    fireworks,
    kimi,
    nvidia,
    custom,
    localEdge,
  ];

  static AiProviderConfig byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => google);
  }
}
