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

/// Информация о модели ИИ (включая флаг бесплатности и отображаемое имя)
class DiscoveredModel {
  final String id;
  final String displayName;
  final bool isFree;
  final String? providerId;

  const DiscoveredModel({
    required this.id,
    String? displayName,
    this.isFree = false,
    this.providerId,
  }) : displayName = displayName ?? id;
}

/// Все доступные AI провайдеры
class AiProviders {
  static const google = AiProviderConfig(
    id: 'google',
    displayName: 'Google Antigravity',
    logoEmoji: '✨',
    apiKeyHint: 'Не требуется (OAuth / agy)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModels: [
      'gemini-3.8-flash-high',
      'gemini-3.8-flash-medium',
      'gemini-3.8-flash-low',
      'gemini-3.7-flash-high',
      'gemini-3.7-flash-medium',
      'gemini-3.7-flash-low',
      'gemini-3.6-flash-high',
      'gemini-3.6-flash-medium',
      'gemini-3.6-flash-low',
      'gemini-3.1-pro-high',
      'gemini-3.1-pro-low',
      'claude-sonnet-4-6',
      'claude-opus-4-6-thinking',
      'gpt-oss-120b-medium',
      'gemini-2.5-pro',
      'gemini-2.5-flash',
    ],
    supportsLocalModels: true,
    requiresApiKey: false,
  );

  static const claudeSubscription = AiProviderConfig(
    id: 'claude_subscription',
    displayName: 'Claude subscription',
    logoEmoji: '👑',
    apiKeyHint: 'setup-token...',
    baseUrl: '',
    defaultModels: ['default'],
    requiresApiKey: false,
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
      'o1-preview',
      'o1-mini',
      'gpt-4-turbo',
      'gpt-4',
      'gpt-3.5-turbo',
    ],
    supportsLocalModels: true,
  );

  static const anthropic = AiProviderConfig(
    id: 'anthropic',
    displayName: 'Anthropic API',
    logoEmoji: '🧠',
    apiKeyHint: 'sk-ant-...',
    baseUrl: 'https://api.anthropic.com',
    defaultModels: [
      'claude-3-7-sonnet-20250219',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-sonnet-4-6',
      'claude-opus-4-6',
      'claude-opus-4-5',
      'claude-sonnet-4-5',
      'claude-haiku-4-5',
    ],
    supportsLocalModels: true,
  );

  static const deepseek = AiProviderConfig(
    id: 'deepseek',
    displayName: 'DeepSeek',
    logoEmoji: '🐳',
    apiKeyHint: 'sk-...',
    baseUrl: 'https://api.deepseek.com',
    defaultModels: [
      'deepseek-chat',
      'deepseek-reasoner',
      'deepseek-coder',
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
      'dots-studio/dots-3-note-preview:free',
      'deepseek/deepseek-r1:free',
      'meta-llama/llama-3.3-70b-instruct:free',
      'qwen/qwen-2.5-coder-32b-instruct:free',
      'google/gemini-2.0-flash-exp:free',
      'deepseek/deepseek-r1',
      'anthropic/claude-3.7-sonnet',
      'anthropic/claude-3.5-sonnet',
      'google/gemini-2.5-pro',
      'openai/gpt-4o',
      'meta-llama/llama-3.3-70b-instruct',
      'qwen/qwen-2.5-coder-32b-instruct',
    ],
    supportsLocalModels: true,
  );

  static const opencodeZen = AiProviderConfig(
    id: 'opencode_zen',
    displayName: 'OpenCode Zen',
    logoEmoji: '⚡',
    apiKeyHint: 'sk-...',
    baseUrl: 'https://opencode.ai/zen/v1',
    defaultModels: ['deepseek-v4-flash'],
  );

  static const kimi = AiProviderConfig(
    id: 'kimi',
    displayName: 'Kimi (Moonshot AI)',
    logoEmoji: '🌙',
    apiKeyHint: 'sk-...',
    baseUrl: 'https://api.moonshot.ai/anthropic',
    defaultModels: [
      'kimi-k2.6',
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
      'qwen/qwen2.5-coder-32b-instruct',
      'meta/llama-3.1-70b-instruct',
      'meta/llama-3.1-8b-instruct',
      'mistralai/mistral-7b-instruct-v0.3',
      'google/gemma-2-9b-it',
    ],
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

  static const mistral = AiProviderConfig(
    id: 'mistral',
    displayName: 'Mistral AI',
    logoEmoji: '🌪️',
    apiKeyHint: '...',
    baseUrl: 'https://api.mistral.ai/v1',
    defaultModels: [
      'codestral-latest',
      'mistral-large-latest',
      'mistral-small-latest',
      'codestral-mamba-latest',
      'pixtral-large-latest',
    ],
    supportsLocalModels: true,
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
    defaultModels: ['qwen2.5-coder-1.5b-instruct'],
    supportsLocalModels: true,
    requiresApiKey: false,
  );

  static const all = [
    openrouter,
    deepseek,
    anthropic,
    google,
    mistral,
    opencodeZen,
    kimi,
    nvidia,
    openai,
    groq,
    grok,
    together,
    perplexity,
    fireworks,
    custom,
    claudeSubscription,
    localEdge,
  ];

  static AiProviderConfig byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => openrouter);
  }

  /// Возвращает рекомендуемые модели с описанием и флагом бесплатности
  static List<DiscoveredModel> getRecommendedDiscoveredModels(String providerId) {
    final provider = byId(providerId);
    return provider.defaultModels.map((m) {
      final isFree = m.endsWith(':free');
      String display = m;
      if (m.contains('/')) {
        final parts = m.split('/');
        display = parts.length > 1 ? '${parts[1]} (${parts[0]})' : m;
      }
      return DiscoveredModel(
        id: m,
        displayName: display,
        isFree: isFree,
        providerId: providerId,
      );
    }).toList();
  }
}
