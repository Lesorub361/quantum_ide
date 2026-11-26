/// Metadata describing a supported LLM model in QuantumIDE's AI assistant.
class QuantumModelItem {
  final String id;
  final String name;
  final String providerName;
  final String category;
  final String badge;
  final int badgeColorValue;
  final bool isReasoning;
  final bool isOpenRouter;

  const QuantumModelItem({
    required this.id,
    required this.name,
    required this.providerName,
    required this.category,
    required this.badge,
    required this.badgeColorValue,
    this.isReasoning = false,
    this.isOpenRouter = true,
  });

  static const List<QuantumModelItem> predefinedModels = [
    // OpenRouter Auto Free
    QuantumModelItem(
      id: 'openrouter/free',
      name: 'OpenRouter Free (Auto)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'AUTO FREE',
      badgeColorValue: 0xFF10B981,
    ),
    // OpenRouter - DeepSeek
    QuantumModelItem(
      id: 'deepseek/deepseek-chat',
      name: 'DeepSeek V3 (671B)',
      providerName: 'OpenRouter',
      category: 'Кодинг',
      badge: 'V3 671B',
      badgeColorValue: 0xFF3B82F6,
    ),
    QuantumModelItem(
      id: 'deepseek/deepseek-r1-0528',
      name: 'DeepSeek R1 (Reasoning)',
      providerName: 'OpenRouter',
      category: 'Рассуждения',
      badge: 'R1 Reasoning',
      badgeColorValue: 0xFF8B5CF6,
      isReasoning: true,
    ),

    // Real Active Free Models on OpenRouter
    QuantumModelItem(
      id: 'cohere/north-mini-code:free',
      name: 'North Mini Code (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE CODE',
      badgeColorValue: 0xFF10B981,
    ),
    QuantumModelItem(
      id: 'nvidia/nemotron-3.5-lightning:free',
      name: 'Nemotron 3.5 Lightning (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FAST FREE',
      badgeColorValue: 0xFF06B6D4,
      isReasoning: true,
    ),
    QuantumModelItem(
      id: 'nvidia/nemotron-3-ultra-550b-a55b:free',
      name: 'Nemotron 3 Ultra 550B (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: '550B FREE',
      badgeColorValue: 0xFF8B5CF6,
      isReasoning: true,
    ),
    QuantumModelItem(
      id: 'google/gemma-4-31b-it:free',
      name: 'Gemma 4 31B (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'GEMMA FREE',
      badgeColorValue: 0xFF3B82F6,
    ),
    QuantumModelItem(
      id: 'meta-llama/llama-3.3-70b-instruct:free',
      name: 'Llama 3.3 70B (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'TOP FREE',
      badgeColorValue: 0xFF10B981,
    ),
    QuantumModelItem(
      id: 'deepseek/deepseek-r1:free',
      name: 'DeepSeek R1 Reasoning (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE R1',
      badgeColorValue: 0xFF8B5CF6,
      isReasoning: true,
    ),
    QuantumModelItem(
      id: 'qwen/qwen-2.5-coder-32b-instruct:free',
      name: 'Qwen 2.5 Coder 32B (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE CODE',
      badgeColorValue: 0xFF06B6D4,
    ),
    QuantumModelItem(
      id: 'deepseek/deepseek-chat:free',
      name: 'DeepSeek V3 Chat (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
    ),
    QuantumModelItem(
      id: 'google/gemini-2.0-flash-exp:free',
      name: 'Gemini 2.0 Flash (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FAST FREE',
      badgeColorValue: 0xFF3B82F6,
    ),
    QuantumModelItem(
      id: 'google/gemma-2-9b-it:free',
      name: 'Google Gemma 2 9B (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
    ),
    QuantumModelItem(
      id: 'mistralai/mistral-7b-instruct:free',
      name: 'Mistral 7B Instruct (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
    ),

    // Claude
    QuantumModelItem(
      id: 'anthropic/claude-3.7-sonnet',
      name: 'Claude 3.7 Sonnet',
      providerName: 'OpenRouter',
      category: 'Флагманы',
      badge: 'Hybrid 3.7',
      badgeColorValue: 0xFFD97706,
      isReasoning: true,
    ),
    QuantumModelItem(
      id: 'anthropic/claude-3.5-sonnet',
      name: 'Claude 3.5 Sonnet',
      providerName: 'OpenRouter',
      category: 'Кодинг',
      badge: 'Top Code',
      badgeColorValue: 0xFFD97706,
    ),
    QuantumModelItem(
      id: 'anthropic/claude-3.5-haiku',
      name: 'Claude 3.5 Haiku',
      providerName: 'OpenRouter',
      category: 'Быстрые',
      badge: 'Fast',
      badgeColorValue: 0xFFF59E0B,
    ),

    // OpenAI
    QuantumModelItem(
      id: 'openai/gpt-4o',
      name: 'GPT-4o (Omni)',
      providerName: 'OpenRouter',
      category: 'Флагманы',
      badge: 'Omni',
      badgeColorValue: 0xFF059669,
    ),
    QuantumModelItem(
      id: 'openai/gpt-4o-mini',
      name: 'GPT-4o Mini',
      providerName: 'OpenRouter',
      category: 'Быстрые',
      badge: 'Fast',
      badgeColorValue: 0xFF059669,
    ),
    QuantumModelItem(
      id: 'openai/o3-mini',
      name: 'o3-mini (Reasoning)',
      providerName: 'OpenRouter',
      category: 'Рассуждения',
      badge: 'o3 Reasoning',
      badgeColorValue: 0xFF10B981,
      isReasoning: true,
    ),
    QuantumModelItem(
      id: 'openai/o1',
      name: 'o1 (Deep Reasoning)',
      providerName: 'OpenRouter',
      category: 'Рассуждения',
      badge: 'o1',
      badgeColorValue: 0xFF10B981,
      isReasoning: true,
    ),

    // Google Gemini
    QuantumModelItem(
      id: 'google/gemini-2.0-flash-001',
      name: 'Gemini 2.0 Flash',
      providerName: 'OpenRouter',
      category: 'Быстрые',
      badge: 'Flash 2.0',
      badgeColorValue: 0xFF2563EB,
    ),
    QuantumModelItem(
      id: 'google/gemini-2.5-pro',
      name: 'Gemini 2.5 Pro',
      providerName: 'OpenRouter',
      category: 'Флагманы',
      badge: 'Pro 2.5',
      badgeColorValue: 0xFF2563EB,
    ),

    // Qwen & Llama
    QuantumModelItem(
      id: 'qwen/qwen-2.5-coder-32b-instruct',
      name: 'Qwen 2.5 Coder 32B',
      providerName: 'OpenRouter',
      category: 'Кодинг',
      badge: 'Top Coder',
      badgeColorValue: 0xFF6366F1,
    ),
    QuantumModelItem(
      id: 'meta-llama/llama-3.3-70b-instruct',
      name: 'Llama 3.3 70B',
      providerName: 'OpenRouter',
      category: 'Популярные',
      badge: '70B',
      badgeColorValue: 0xFFEC4899,
    ),
    QuantumModelItem(
      id: 'mistralai/codestral-2501',
      name: 'Codestral 2501',
      providerName: 'OpenRouter',
      category: 'Кодинг',
      badge: 'Codestral',
      badgeColorValue: 0xFFF97316,
    ),

    // Direct API Models — DeepSeek
    QuantumModelItem(
      id: 'deepseek-chat',
      name: 'DeepSeek V3 (Direct)',
      providerName: 'DeepSeek Direct',
      category: 'Прямой API',
      badge: 'DeepSeek',
      badgeColorValue: 0xFF3B82F6,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'deepseek-reasoner',
      name: 'DeepSeek R1 (Direct)',
      providerName: 'DeepSeek Direct',
      category: 'Прямой API',
      badge: 'R1 Direct',
      badgeColorValue: 0xFF8B5CF6,
      isReasoning: true,
      isOpenRouter: false,
    ),

    // Direct API Models — Google Gemini Direct
    QuantumModelItem(
      id: 'gemini-2.5-pro',
      name: 'Gemini 2.5 Pro (Direct)',
      providerName: 'Gemini Direct',
      category: 'Прямой API',
      badge: 'Gemini API',
      badgeColorValue: 0xFF2563EB,
      isReasoning: true,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'gemini-2.5-flash',
      name: 'Gemini 2.5 Flash (Direct)',
      providerName: 'Gemini Direct',
      category: 'Прямой API',
      badge: 'Gemini Fast',
      badgeColorValue: 0xFF3B82F6,
      isOpenRouter: false,
    ),

    // Direct API Models — Groq Cloud (Ultra Fast LPU)
    QuantumModelItem(
      id: 'llama-3.3-70b-versatile',
      name: 'Llama 3.3 70B (Groq LPU)',
      providerName: 'Groq Cloud',
      category: 'Прямой API',
      badge: 'Groq LPU',
      badgeColorValue: 0xFFF97316,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'deepseek-r1-distill-llama-70b',
      name: 'DeepSeek R1 70B (Groq LPU)',
      providerName: 'Groq Cloud',
      category: 'Прямой API',
      badge: 'Groq R1',
      badgeColorValue: 0xFFF97316,
      isReasoning: true,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'qwen-2.5-coder-32b',
      name: 'Qwen 2.5 Coder 32B (Groq)',
      providerName: 'Groq Cloud',
      category: 'Прямой API',
      badge: 'Groq Code',
      badgeColorValue: 0xFFF97316,
      isOpenRouter: false,
    ),

    // Direct API Models — OpenAI & Anthropic
    QuantumModelItem(
      id: 'gpt-4o',
      name: 'OpenAI GPT-4o (Direct)',
      providerName: 'OpenAI Direct',
      category: 'Прямой API',
      badge: 'OpenAI',
      badgeColorValue: 0xFF059669,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'o3-mini',
      name: 'OpenAI o3-mini (Direct)',
      providerName: 'OpenAI Direct',
      category: 'Прямой API',
      badge: 'o3 Direct',
      badgeColorValue: 0xFF10B981,
      isReasoning: true,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'claude-3-7-sonnet-20250219',
      name: 'Claude 3.7 Sonnet (Direct)',
      providerName: 'Anthropic Direct',
      category: 'Прямой API',
      badge: 'Anthropic',
      badgeColorValue: 0xFFD97706,
      isReasoning: true,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'claude-3-5-sonnet-20241022',
      name: 'Claude 3.5 Sonnet (Direct)',
      providerName: 'Anthropic Direct',
      category: 'Прямой API',
      badge: 'Anthropic',
      badgeColorValue: 0xFFD97706,
      isOpenRouter: false,
    ),

    // Direct API Models — xAI Grok & Mistral Codestral
    QuantumModelItem(
      id: 'grok-3',
      name: 'xAI Grok 3 (Direct)',
      providerName: 'xAI Direct',
      category: 'Прямой API',
      badge: 'xAI Grok',
      badgeColorValue: 0xFF64748B,
      isReasoning: true,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'grok-2-vision-1212',
      name: 'xAI Grok 2 Vision (Direct)',
      providerName: 'xAI Direct',
      category: 'Прямой API',
      badge: 'xAI Vision',
      badgeColorValue: 0xFF64748B,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'codestral-latest',
      name: 'Mistral Codestral (Direct)',
      providerName: 'Mistral Direct',
      category: 'Прямой API',
      badge: 'Mistral',
      badgeColorValue: 0xFFEF4444,
      isOpenRouter: false,
    ),

    // Local / Custom OpenAI-compatible Server (Ollama / LM Studio / vLLM)
    QuantumModelItem(
      id: 'default',
      name: 'Локальный / Custom API (Ollama)',
      providerName: 'Local',
      category: 'Локальный',
      badge: 'Local API',
      badgeColorValue: 0xFF6B7280,
      isOpenRouter: false,
    ),
  ];
}
