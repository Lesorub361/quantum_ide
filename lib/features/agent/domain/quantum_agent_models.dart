import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 1. ВЫЗОВЫ ИНСТРУМЕНТОВ И СООБЩЕНИЯ ЧАТ-БОТА (С <think> THOUGHT DISCLOSURE)
// ═══════════════════════════════════════════════════════════════════════════

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
  final int thinkingDurationMs;
  final List<AgentToolCall> toolCalls;
  final List<String> modifiedFiles;
  final DateTime timestamp;
  final bool isStreaming;

  const AgentChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thinking,
    this.thinkingDurationMs = 0,
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
    int? thinkingDurationMs,
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
      thinkingDurationMs: thinkingDurationMs ?? this.thinkingDurationMs,
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
        'thinkingDurationMs': thinkingDurationMs,
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
        'modifiedFiles': modifiedFiles,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AgentChatMessage.fromJson(Map<String, dynamic> json) => AgentChatMessage(
        id: json['id']?.toString() ?? '',
        role: json['role']?.toString() ?? 'assistant',
        content: json['content']?.toString() ?? '',
        thinking: json['thinking']?.toString(),
        thinkingDurationMs: (json['thinkingDurationMs'] as num?)?.toInt() ?? 0,
        toolCalls: (json['toolCalls'] as List?)
                ?.map((e) => AgentToolCall.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        modifiedFiles: (json['modifiedFiles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. ЛОКАЛЬНЫЕ МОДЕЛИ (ИЗ cross-platform-llm-client / PrivateLM)
// ═══════════════════════════════════════════════════════════════════════════

class LocalAiModel {
  static const runtimeLlama = 'llama';
  static const runtimeLiteRt = 'litert';
  static const runtimeSd = 'sd';

  final String name;
  final String filename;
  final String url;
  final String size;
  final String description;
  final String template;
  final String runtime;
  final bool isVision;
  final bool isImported;
  final bool isCustom;
  final String mmprojFilename;
  final String mmprojUrl;
  final Set<String> recommendedFor;

  const LocalAiModel({
    required this.name,
    required this.filename,
    required this.url,
    required this.size,
    required this.description,
    required this.template,
    required this.runtime,
    this.isVision = false,
    this.isImported = false,
    this.isCustom = false,
    this.mmprojFilename = '',
    this.mmprojUrl = '',
    this.recommendedFor = const {},
  });

  bool get isUncensored {
    final lower = '$name $filename $description'.toLowerCase();
    return lower.contains('uncensored') ||
        lower.contains('abliterated') ||
        lower.contains('unrestricted') ||
        lower.contains('dolphin');
  }

  bool get isImageGen => runtime == runtimeSd || filename.toLowerCase().endsWith('.safetensors');

  String get category {
    if (isImageGen) return 'image';
    if (isUncensored) return 'uncensored';
    if (isVision) return 'vision';
    return 'general';
  }

  LocalAiModel copyWith({
    String? name,
    String? filename,
    String? url,
    String? size,
    String? description,
    String? template,
    String? runtime,
    bool? isVision,
    bool? isImported,
    bool? isCustom,
  }) {
    return LocalAiModel(
      name: name ?? this.name,
      filename: filename ?? this.filename,
      url: url ?? this.url,
      size: size ?? this.size,
      description: description ?? this.description,
      template: template ?? this.template,
      runtime: runtime ?? this.runtime,
      isVision: isVision ?? this.isVision,
      isImported: isImported ?? this.isImported,
      isCustom: isCustom ?? this.isCustom,
      mmprojFilename: mmprojFilename,
      mmprojUrl: mmprojUrl,
      recommendedFor: recommendedFor,
    );
  }

  static const List<LocalAiModel> builtInCatalog = [
    LocalAiModel(
      name: 'LFM2.5 1.2B Instruct (Q4_K_M)',
      filename: 'lfm2.5-1.2b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      size: '731 MB',
      description: 'Liquid AI — быстрая локальная модель для смартфонов среднего класса',
      template: 'chatml',
      runtime: runtimeLlama,
      recommendedFor: {'general'},
    ),
    LocalAiModel(
      name: 'Qwen 3 0.6B (LiteRT-LM)',
      filename: 'Qwen3-0.6B.litertlm',
      url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      size: '586 MB',
      description: 'Самая лёгкая LiteRT-LM модель для телефонов с малым объёмом ОЗУ',
      template: 'litert',
      runtime: runtimeLiteRt,
    ),
    LocalAiModel(
      name: 'Gemma 3 1B Instruct (Q4_0)',
      filename: 'gemma-3-1b-it-q4_0.gguf',
      url: 'https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_0.gguf',
      size: '722 MB',
      description: 'Компактная и быстрая чат-модель от Google',
      template: 'gemma',
      runtime: runtimeLlama,
    ),
    LocalAiModel(
      name: 'Llama-3.2-1B Instruct (Q4_K_M)',
      filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      size: '800 MB',
      description: 'Ультра-лёгкая текстовая модель Meta Llama 3.2',
      template: 'llama3',
      runtime: runtimeLlama,
    ),
    LocalAiModel(
      name: 'Qwen 2.5 1.5B Instruct (LiteRT-LM)',
      filename: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      url: 'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      size: '1.49 GB',
      description: 'Сбалансированная LiteRT-LM модель (int8 квантование)',
      template: 'litert',
      runtime: runtimeLiteRt,
    ),
    LocalAiModel(
      name: 'DeepSeek R1 Distill Qwen 1.5B (LiteRT-LM)',
      filename: 'DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      url: 'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      size: '1.71 GB',
      description: 'Рассуждающая (Reasoning) локальная модель с цепочкой мыслей <think>',
      template: 'litert',
      runtime: runtimeLiteRt,
    ),
    LocalAiModel(
      name: 'Qwen2.5-3B Instruct (Q4_K_M)',
      filename: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      size: '2.1 GB',
      description: 'Лучший баланс скорости и качества кода для мобильных устройств',
      template: 'chatml',
      runtime: runtimeLlama,
    ),
    LocalAiModel(
      name: 'Phi-3.5 Mini Instruct (Q4_K_M)',
      filename: 'phi-3.5-mini-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      size: '2.2 GB',
      description: 'Компактная логическая модель от Microsoft',
      template: 'phi',
      runtime: runtimeLlama,
    ),
    LocalAiModel(
      name: 'Kimi Moonlight 16B-A3B (Q3_K_S)',
      filename: 'moonlight-16b-a3b-instruct-q3_k_s.gguf',
      url: 'https://huggingface.co/mmnga/Moonlight-16B-A3B-Instruct-gguf/resolve/main/Moonlight-16B-A3B-Instruct-Q3_K_S.gguf',
      size: '7.1 GB',
      description: 'Moonshot AI (Kimi) — 3B активных параметров MoE, высокое качество',
      template: 'chatml',
      runtime: runtimeLlama,
    ),
    // ─── VISION МОДЕЛИ ──────────────────────────────────────────────────────
    LocalAiModel(
      name: 'Gemma 4 E2B Instruct Vision (LiteRT-LM)',
      filename: 'gemma-4-E2B-it.litertlm',
      url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      size: '2.46 GB',
      description: 'Мультимодальная модель Google Gemma с пониманием изображений',
      template: 'litert',
      runtime: runtimeLiteRt,
      isVision: true,
      recommendedFor: {'vision'},
    ),
    LocalAiModel(
      name: 'LFM2.5-VL 1.6B Vision (Q4_K_M)',
      filename: 'lfm2.5-vl-1.6b-q4_k_m.gguf',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/LFM2.5-VL-1.6B-Q4_K_M.gguf',
      size: '731 MB + 583 MB vision',
      description: 'Лёгкая Vision-модель Liquid AI для распознавания скриншотов и фото',
      template: 'chatml',
      runtime: runtimeLlama,
      isVision: true,
      mmprojFilename: 'lfm2.5-vl-1.6b-mmproj-q8_0.gguf',
      mmprojUrl: 'https://huggingface.co/LiquidAI/LFM2.5-VL-1.6B-GGUF/resolve/main/mmproj-LFM2.5-VL-1.6b-Q8_0.gguf',
    ),
    LocalAiModel(
      name: 'Qwen2-VL-2B Instruct Vision (Q4_K_M)',
      filename: 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
      size: '986 MB + 710 MB vision',
      description: 'Компактная Vision-модель — читает текст и UI со скриншотов',
      template: 'chatml',
      runtime: runtimeLlama,
      isVision: true,
      mmprojFilename: 'qwen2-vl-2b-instruct-mmproj-q8_0.gguf',
      mmprojUrl: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
    ),
    // ─── UNCENSORED МОДЕЛИ ──────────────────────────────────────────────────
    LocalAiModel(
      name: 'Dolphin-3.0-Qwen2.5-1.5B Uncensored (Q4_K_M)',
      filename: 'dolphin-3.0-qwen2.5-1.5b-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Dolphin3.0-Qwen2.5-1.5B-GGUF/resolve/main/Dolphin3.0-Qwen2.5-1.5B-Q4_K_M.gguf',
      size: '986 MB',
      description: '🔓 Uncensored Dolphin 3.0 — быстрый ассистент без цензуры',
      template: 'chatml',
      runtime: runtimeLlama,
      recommendedFor: {'uncensored'},
    ),
    LocalAiModel(
      name: 'SmolLM2-1.7B-Uncensored (Q4_K_M)',
      filename: 'smollm2-1.7b-instruct-uncensored-q4_k_m.gguf',
      url: 'https://huggingface.co/mradermacher/SmolLM2-1.7B-Instruct-Uncensored-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Uncensored.Q4_K_M.gguf',
      size: '1.1 GB',
      description: '🔓 Ультра-компактная модель без ограничений',
      template: 'chatml',
      runtime: runtimeLlama,
    ),
    LocalAiModel(
      name: 'Gemma-2-2B-Abliterated (Q4_K_M)',
      filename: 'gemma-2-2b-it-abliterated-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/gemma-2-2b-it-abliterated-GGUF/resolve/main/gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      size: '1.6 GB',
      description: '🔓 Abliterated — полностью без фильтров, высокая точность',
      template: 'gemma',
      runtime: runtimeLlama,
    ),
    LocalAiModel(
      name: 'Llama-3.2-3B Uncensored (Q4_K_M)',
      filename: 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
      size: '2.1 GB',
      description: '🔓 Uncensored Llama 3.2 3B — мощная модель без ограничений',
      template: 'llama3',
      runtime: runtimeLlama,
    ),
    // ─── IMAGE GENERATION (SD 1.5) ──────────────────────────────────────────
    LocalAiModel(
      name: 'CyberRealistic V8 FP16 (SD 1.5)',
      filename: 'CyberRealistic_V8_FP16.safetensors',
      url: 'https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V8_FP16.safetensors',
      size: '2.0 GB',
      description: 'Фотореалистичная локальная генерация изображений SD 1.5',
      template: 'sd',
      runtime: runtimeSd,
      recommendedFor: {'image'},
    ),
    LocalAiModel(
      name: 'DreamShaper 8 LCM (SD 1.5)',
      filename: 'DreamShaper8_LCM.safetensors',
      url: 'https://huggingface.co/Lykon/dreamshaper-8-lcm/resolve/main/DreamShaper8_LCM.safetensors',
      size: '2.0 GB',
      description: 'Сверхбыстрая генерация изображений за 4 шага (LCM)',
      template: 'sd',
      runtime: runtimeSd,
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. ПРОВАЙДЕРЫ И ХАРНЕССЫ (cross-platform-llm-client + Mobile-Harness)
// ═══════════════════════════════════════════════════════════════════════════

class SavedApiKeyEntry {
  final String name;
  final String key;
  final bool isActive;
  final bool? isVerified;
  final String? statusMessage;

  const SavedApiKeyEntry({
    required this.name,
    required this.key,
    this.isActive = false,
    this.isVerified,
    this.statusMessage,
  });

  String get maskedKey {
    if (key.length <= 8) return '••••••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  SavedApiKeyEntry copyWith({
    String? name,
    String? key,
    bool? isActive,
    bool? isVerified,
    String? statusMessage,
  }) {
    return SavedApiKeyEntry(
      name: name ?? this.name,
      key: key ?? this.key,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'key': key,
        'isActive': isActive,
        'isVerified': isVerified,
        'statusMessage': statusMessage,
      };

  factory SavedApiKeyEntry.fromJson(Map<String, dynamic> json) => SavedApiKeyEntry(
        name: json['name']?.toString() ?? 'Default',
        key: json['key']?.toString() ?? '',
        isActive: json['isActive'] == true,
        isVerified: json['isVerified'] as bool?,
        statusMessage: json['statusMessage']?.toString(),
      );
}

class QuantumAgentProviderPreset {
  final String id;
  final String name;
  final String subtitle;
  final String baseUrl;
  final String modelsUrl;
  final List<String> models;
  final String keyHint;
  final bool requiresKey;
  final String protocol; // 'openai-completions' | 'anthropic-messages' | 'openai-responses' | 'bridge'
  final Color brandColor;

  const QuantumAgentProviderPreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.baseUrl,
    this.modelsUrl = '',
    required this.models,
    required this.keyHint,
    this.requiresKey = true,
    this.protocol = 'openai-completions',
    this.brandColor = const Color(0xFF8B5CF6),
  });

  IconData get icon {
    switch (id) {
      case 'antigravity_doctor':
        return LucideIcons.wand;
      case 'openrouter':
        return LucideIcons.network;
      case 'openai':
        return LucideIcons.sparkles;
      case 'anthropic':
        return LucideIcons.bot;
      case 'deepseek':
        return LucideIcons.brain_circuit;
      case 'gemini':
        return LucideIcons.gem;
      case 'kimi':
        return LucideIcons.moon;
      case 'nvidia':
        return LucideIcons.cpu;
      case 'groq':
        return LucideIcons.zap;
      case 'local_gguf':
        return LucideIcons.smartphone;
      case 'custom':
      default:
        return LucideIcons.sliders_horizontal;
    }
  }

  static const List<QuantumAgentProviderPreset> presets = [
    QuantumAgentProviderPreset(
      id: 'antigravity_doctor',
      name: 'Antigravity & Auto-Doctor',
      subtitle: 'Встроенный ИИ-доктор + мост Antigravity (без API-ключа)',
      baseUrl: 'http://127.0.0.1:45169',
      models: [
        'gemini-3.8-flash-high',
        'gemini-3.8-flash-medium',
        'gemini-3.6-flash-high',
        'gemini-3.1-pro-high',
        'claude-sonnet-4-6',
        'claude-opus-4-6-thinking',
        'gpt-oss-120b-medium',
        'quantum-doctor-v2',
      ],
      keyHint: 'Ключ не требуется',
      requiresKey: false,
      protocol: 'bridge',
      brandColor: Color(0xFF9C27B0),
    ),
    QuantumAgentProviderPreset(
      id: 'openrouter',
      name: 'OpenRouter',
      subtitle: 'Бесплатные и платные модели · Маршрутизация провайдеров',
      baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
      modelsUrl: 'https://openrouter.ai/api/v1/models',
      models: [
        'deepseek/deepseek-chat-v3-0324:free',
        'qwen/qwen-2.5-coder-32b-instruct:free',
        'google/gemini-2.5-flash',
        'anthropic/claude-3.5-sonnet',
        'openai/gpt-4o-mini',
        'openai/gpt-4o',
        'deepseek/deepseek-chat',
        'meta-llama/llama-3.1-8b-instruct',
      ],
      keyHint: 'sk-or-v1-...',
      brandColor: Color(0xFF6366F1),
    ),
    QuantumAgentProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek',
      subtitle: 'Официальный API DeepSeek V4 & R1 Reasoner',
      baseUrl: 'https://api.deepseek.com/chat/completions',
      modelsUrl: 'https://api.deepseek.com/models',
      models: [
        'deepseek-v4-flash',
        'deepseek-v4-pro',
        'deepseek-chat',
        'deepseek-reasoner',
      ],
      keyHint: 'sk-...',
      brandColor: Color(0xFF0284C7),
    ),
    QuantumAgentProviderPreset(
      id: 'openai',
      name: 'OpenAI',
      subtitle: 'Нативные модели GPT-5.2, GPT-4.1 и GPT-4o',
      baseUrl: 'https://api.openai.com/v1/chat/completions',
      modelsUrl: 'https://api.openai.com/v1/models',
      models: [
        'gpt-5.2',
        'gpt-5.1',
        'gpt-4.1',
        'gpt-4.1-mini',
        'gpt-4o',
        'gpt-4o-mini',
      ],
      keyHint: 'sk-proj-...',
      brandColor: Color(0xFF10B981),
    ),
    QuantumAgentProviderPreset(
      id: 'anthropic',
      name: 'Anthropic Claude',
      subtitle: 'Claude Sonnet 4.6 & Opus 4.6 (Anthropic Console API)',
      baseUrl: 'https://api.anthropic.com/v1/messages',
      modelsUrl: 'https://api.anthropic.com/v1/models',
      models: [
        'claude-sonnet-4-6',
        'claude-opus-4-6-thinking',
        'claude-3-5-sonnet-latest',
        'claude-3-5-haiku-latest',
      ],
      keyHint: 'sk-ant-...',
      protocol: 'anthropic-messages',
      brandColor: Color(0xFFD97706),
    ),
    QuantumAgentProviderPreset(
      id: 'gemini',
      name: 'Google Gemini',
      subtitle: 'Нативные модели Gemini 2.5 Flash & Pro',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      modelsUrl: 'https://generativelanguage.googleapis.com/v1beta/models',
      models: [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash',
        'gemini-1.5-flash',
        'gemini-1.5-pro',
      ],
      keyHint: 'AIzaSy...',
      brandColor: Color(0xFF3B82F6),
    ),
    QuantumAgentProviderPreset(
      id: 'kimi',
      name: 'Kimi (Moonshot AI)',
      subtitle: 'Модели Kimi K2.6 с огромным контекстом',
      baseUrl: 'https://api.moonshot.ai/v1/chat/completions',
      modelsUrl: 'https://api.moonshot.ai/v1/models',
      models: [
        'kimi-k2.6',
        'moonshot-v1-32k',
        'moonshot-v1-128k',
      ],
      keyHint: 'sk-...',
      brandColor: Color(0xFFEC4899),
    ),
    QuantumAgentProviderPreset(
      id: 'nvidia',
      name: 'NVIDIA NIM',
      subtitle: 'Высокоскоростные модели на кластерах NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1/chat/completions',
      modelsUrl: 'https://integrate.api.nvidia.com/v1/models',
      models: [
        'qwen/qwen2.5-coder-32b-instruct',
        'meta/llama-3.3-70b-instruct',
        'nvidia/llama-3.1-nemotron-70b-instruct',
        'meta/llama-3.1-8b-instruct',
        'meta/llama-3.1-70b-instruct',
        'mistralai/mixtral-8x7b-instruct-v0.1',
      ],
      keyHint: 'nvapi-...',
      brandColor: Color(0xFF76B900),
    ),
    QuantumAgentProviderPreset(
      id: 'groq',
      name: 'Groq Cloud',
      subtitle: 'Мгновенная генерация кода на чипах LPU',
      baseUrl: 'https://api.groq.com/openai/v1/chat/completions',
      modelsUrl: 'https://api.groq.com/openai/v1/models',
      models: [
        'llama-3.3-70b-versatile',
        'qwen-2.5-coder-32b',
        'deepseek-r1-distill-llama-70b',
      ],
      keyHint: 'gsk_...',
      brandColor: Color(0xFFF97316),
    ),
    QuantumAgentProviderPreset(
      id: 'local_gguf',
      name: 'Local On-Device (PrivateLM)',
      subtitle: 'Локальные модели GGUF / LiteRT-LM прямо на телефоне',
      baseUrl: 'http://127.0.0.1:8080/v1/chat/completions',
      models: [
        'lfm2.5-1.2b-instruct-q4_k_m.gguf',
        'Qwen3-0.6B.litertlm',
        'qwen2.5-3b-instruct-q4_k_m.gguf',
        'DeepSeek-R1-Distill-Qwen-1.5B.litertlm',
      ],
      keyHint: 'Локальный движок (без ключа)',
      requiresKey: false,
      brandColor: Color(0xFF14B8A6),
    ),
    QuantumAgentProviderPreset(
      id: 'custom',
      name: 'Custom API Gateway',
      subtitle: 'Любой совместимый OpenAI / Anthropic эндпоинт',
      baseUrl: 'https://api.openai.com/v1/chat/completions',
      models: ['custom-model'],
      keyHint: 'Bearer / API Key...',
      brandColor: Color(0xFFA855F7),
    ),
  ];

  static QuantumAgentProviderPreset byId(String id) {
    return presets.firstWhere(
      (p) => p.id == id,
      orElse: () => presets.first,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. ЧЕКПОИНТЫ И DIFF ИЗМЕНЕНИЙ ФАЙЛОВ (ИЗ Mobile-Harness WorkspaceCheckpoints)
// ═══════════════════════════════════════════════════════════════════════════

enum AgentDiffLineType { context, addition, deletion, info }

class AgentDiffLine {
  final AgentDiffLineType type;
  final String text;
  final int? oldLine;
  final int? newLine;

  const AgentDiffLine({
    required this.type,
    required this.text,
    this.oldLine,
    this.newLine,
  });
}

class WorkspaceChangeItem {
  final String relativePath;
  final String beforeContent;
  final String afterContent;
  final int additions;
  final int deletions;
  final List<AgentDiffLine> diffLines;
  final DateTime timestamp;

  const WorkspaceChangeItem({
    required this.relativePath,
    required this.beforeContent,
    required this.afterContent,
    required this.additions,
    required this.deletions,
    required this.diffLines,
    required this.timestamp,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. ЕДИНОЕ СОСТОЯНИЕ ИИ-АГЕНТА, МОДЕЛЕЙ, НАСТРОЕК И СЕРВЕРА
// ═══════════════════════════════════════════════════════════════════════════

class QuantumAgentState {
  final List<AgentChatMessage> messages;
  final bool isWorking;
  final String statusText;

  // Режим и провайдер
  final String inferenceMode; // 'cloud' | 'local'
  final String providerId;
  final String modelId;
  final String apiKey;
  final String customBaseUrl;
  final String customProtocol; // 'openai-completions' | 'anthropic-messages' | 'openai-responses'
  final String selectedHarness; // 'native' | 'antigravity' | 'claude-code' | 'deepseek-harness'
  final String antigravityEffort; // 'low' | 'medium' | 'high'

  // OpenRouter Routing (из Mobile-Harness)
  final String openRouterProviderOrder;
  final bool openRouterAllowFallbacks;
  final bool freeModelsFirst;

  // Параметры генерации (из cross-platform-llm-client)
  final double temperature;
  final int maxTokens;
  final int contextSize;
  final String performanceMode; // 'auto_fast' | 'gpu_fast' | 'cpu_safe'
  final String systemPromptPreset; // 'agent' | 'concise' | 'uncensored' | 'custom'
  final String customSystemPrompt;
  final List<String> stopSequences;
  final bool autoApplyEdits;

  // Мульти-ключи и обнаруженные модели
  final Map<String, List<SavedApiKeyEntry>> savedKeysByProvider;
  final Map<String, List<String>> discoveredModelsByProvider;
  final bool isDiscoveringModels;
  final bool isVerifyingConnection;
  final String? connectionStatusText;
  final bool? connectionVerified;

  // Локальные модели (PrivateLM)
  final List<String> downloadedLocalModels;
  final Map<String, double> downloadProgressByFile;
  final String activeLocalModel;
  final String localModelFilter; // 'general' | 'vision' | 'uncensored' | 'image'

  // Встроенный локальный OpenAI-сервер (из ServerView)
  final bool isLocalServerRunning;
  final int localServerPort;
  final bool localServerAllowNetwork;
  final bool localServerRequireKey;
  final String localServerApiKey;
  final int localServerRequestsCount;

  // Чекпоинты и изменения файлов (из Mobile-Harness)
  final List<WorkspaceChangeItem> pendingChanges;

  const QuantumAgentState({
    this.messages = const [],
    this.isWorking = false,
    this.statusText = '',
    this.inferenceMode = 'cloud',
    this.providerId = 'antigravity_doctor',
    this.modelId = 'gemini-3.8-flash-high',
    this.apiKey = '',
    this.customBaseUrl = '',
    this.customProtocol = 'openai-completions',
    this.selectedHarness = 'native',
    this.antigravityEffort = 'high',
    this.openRouterProviderOrder = '',
    this.openRouterAllowFallbacks = true,
    this.freeModelsFirst = true,
    this.temperature = 0.2,
    this.maxTokens = 2048,
    this.contextSize = 8192,
    this.performanceMode = 'auto_fast',
    this.systemPromptPreset = 'agent',
    this.customSystemPrompt = '',
    this.stopSequences = const [],
    this.autoApplyEdits = true,
    this.savedKeysByProvider = const {},
    this.discoveredModelsByProvider = const {},
    this.isDiscoveringModels = false,
    this.isVerifyingConnection = false,
    this.connectionStatusText,
    this.connectionVerified,
    this.downloadedLocalModels = const [],
    this.downloadProgressByFile = const {},
    this.activeLocalModel = 'lfm2.5-1.2b-instruct-q4_k_m.gguf',
    this.localModelFilter = 'general',
    this.isLocalServerRunning = false,
    this.localServerPort = 8080,
    this.localServerAllowNetwork = false,
    this.localServerRequireKey = false,
    this.localServerApiKey = 'qide-local-key',
    this.localServerRequestsCount = 0,
    this.pendingChanges = const [],
  });

  QuantumAgentState copyWith({
    List<AgentChatMessage>? messages,
    bool? isWorking,
    String? statusText,
    String? inferenceMode,
    String? providerId,
    String? modelId,
    String? apiKey,
    String? customBaseUrl,
    String? customProtocol,
    String? selectedHarness,
    String? antigravityEffort,
    String? openRouterProviderOrder,
    bool? openRouterAllowFallbacks,
    bool? freeModelsFirst,
    double? temperature,
    int? maxTokens,
    int? contextSize,
    String? performanceMode,
    String? systemPromptPreset,
    String? customSystemPrompt,
    List<String>? stopSequences,
    bool? autoApplyEdits,
    Map<String, List<SavedApiKeyEntry>>? savedKeysByProvider,
    Map<String, List<String>>? discoveredModelsByProvider,
    bool? isDiscoveringModels,
    bool? isVerifyingConnection,
    String? connectionStatusText,
    bool? connectionVerified,
    List<String>? downloadedLocalModels,
    Map<String, double>? downloadProgressByFile,
    String? activeLocalModel,
    String? localModelFilter,
    bool? isLocalServerRunning,
    int? localServerPort,
    bool? localServerAllowNetwork,
    bool? localServerRequireKey,
    String? localServerApiKey,
    int? localServerRequestsCount,
    List<WorkspaceChangeItem>? pendingChanges,
  }) {
    return QuantumAgentState(
      messages: messages ?? this.messages,
      isWorking: isWorking ?? this.isWorking,
      statusText: statusText ?? this.statusText,
      inferenceMode: inferenceMode ?? this.inferenceMode,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      apiKey: apiKey ?? this.apiKey,
      customBaseUrl: customBaseUrl ?? this.customBaseUrl,
      customProtocol: customProtocol ?? this.customProtocol,
      selectedHarness: selectedHarness ?? this.selectedHarness,
      antigravityEffort: antigravityEffort ?? this.antigravityEffort,
      openRouterProviderOrder: openRouterProviderOrder ?? this.openRouterProviderOrder,
      openRouterAllowFallbacks: openRouterAllowFallbacks ?? this.openRouterAllowFallbacks,
      freeModelsFirst: freeModelsFirst ?? this.freeModelsFirst,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      contextSize: contextSize ?? this.contextSize,
      performanceMode: performanceMode ?? this.performanceMode,
      systemPromptPreset: systemPromptPreset ?? this.systemPromptPreset,
      customSystemPrompt: customSystemPrompt ?? this.customSystemPrompt,
      stopSequences: stopSequences ?? this.stopSequences,
      autoApplyEdits: autoApplyEdits ?? this.autoApplyEdits,
      savedKeysByProvider: savedKeysByProvider ?? this.savedKeysByProvider,
      discoveredModelsByProvider: discoveredModelsByProvider ?? this.discoveredModelsByProvider,
      isDiscoveringModels: isDiscoveringModels ?? this.isDiscoveringModels,
      isVerifyingConnection: isVerifyingConnection ?? this.isVerifyingConnection,
      connectionStatusText: connectionStatusText ?? this.connectionStatusText,
      connectionVerified: connectionVerified ?? this.connectionVerified,
      downloadedLocalModels: downloadedLocalModels ?? this.downloadedLocalModels,
      downloadProgressByFile: downloadProgressByFile ?? this.downloadProgressByFile,
      activeLocalModel: activeLocalModel ?? this.activeLocalModel,
      localModelFilter: localModelFilter ?? this.localModelFilter,
      isLocalServerRunning: isLocalServerRunning ?? this.isLocalServerRunning,
      localServerPort: localServerPort ?? this.localServerPort,
      localServerAllowNetwork: localServerAllowNetwork ?? this.localServerAllowNetwork,
      localServerRequireKey: localServerRequireKey ?? this.localServerRequireKey,
      localServerApiKey: localServerApiKey ?? this.localServerApiKey,
      localServerRequestsCount: localServerRequestsCount ?? this.localServerRequestsCount,
      pendingChanges: pendingChanges ?? this.pendingChanges,
    );
  }
}
