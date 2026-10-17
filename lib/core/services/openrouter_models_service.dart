import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final openRouterModelsServiceProvider = Provider<OpenRouterModelsService>((ref) {
  return OpenRouterModelsService();
});

class OpenRouterAccountInfo {
  final String label;
  final int freeLimit;
  final int freeUsed;
  final int freeRemaining;
  final double totalCredits;
  final double totalUsage;
  final double balance;
  final bool isFreeTier;

  const OpenRouterAccountInfo({
    required this.label,
    required this.freeLimit,
    required this.freeUsed,
    required this.freeRemaining,
    required this.totalCredits,
    required this.totalUsage,
    required this.balance,
    required this.isFreeTier,
  });

  double get freeUsageRatio => freeLimit > 0 ? (freeUsed / freeLimit).clamp(0.0, 1.0) : 0.0;
}

class OpenRouterModelInfo {
  final String id;
  final String name;
  final String description;
  final int contextLength;
  final String modality;
  final bool isFree;
  final bool isReasoning;
  final bool isCoding;
  final String providerName;
  final double promptPrice;
  final double completionPrice;

  const OpenRouterModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.contextLength,
    required this.modality,
    required this.isFree,
    this.isReasoning = false,
    this.isCoding = false,
    required this.providerName,
    this.promptPrice = 0.0,
    this.completionPrice = 0.0,
  });

  String get formattedContext {
    if (contextLength >= 1000000) {
      final m = contextLength / 1000000;
      return m % 1 == 0 ? '${m.toInt()}M' : '${m.toStringAsFixed(1)}M';
    }
    if (contextLength >= 1000) {
      return '${(contextLength / 1000).round()}k';
    }
    return '$contextLength';
  }
}

class OpenRouterModelsService {
  final Dio _dio;
  List<OpenRouterModelInfo>? _cachedModels;
  DateTime? _lastModelsFetch;

  OpenRouterModelsService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'HTTP-Referer': 'https://github.com/Lesorub361/quantum_ide',
                'X-Title': 'QuantumIDE Mobile',
              },
            ));

  /// Fetch user account limits, balance and free credits from OpenRouter API
  Future<OpenRouterAccountInfo?> fetchAccountInfo(String apiKey) async {
    if (apiKey.isEmpty) return null;
    final cleanKey = apiKey.trim();

    try {
      final keyResp = await _dio.get(
        'https://openrouter.ai/api/v1/auth/key',
        options: Options(headers: {'Authorization': 'Bearer $cleanKey'}),
      );

      final keyData = keyResp.data is Map<String, dynamic>
          ? (keyResp.data['data'] as Map<String, dynamic>? ?? {})
          : <String, dynamic>{};

      final label = keyData['label']?.toString() ?? 'OpenRouter Key';
      final freeDaily = keyData['free_model_daily_requests'] as Map<String, dynamic>?;
      final freeLimit = (freeDaily?['limit'] as num?)?.toInt() ?? 1000;
      final freeUsed = (freeDaily?['used'] as num?)?.toInt() ?? 0;
      final freeRemaining = (freeDaily?['remaining'] as num?)?.toInt() ?? (freeLimit - freeUsed);
      final isFreeTier = keyData['is_free_tier'] == true;

      double totalCredits = 0.0;
      double totalUsage = 0.0;

      try {
        final creditsResp = await _dio.get(
          'https://openrouter.ai/api/v1/credits',
          options: Options(headers: {'Authorization': 'Bearer $cleanKey'}),
        );
        final creditsData = creditsResp.data is Map<String, dynamic>
            ? (creditsResp.data['data'] as Map<String, dynamic>? ?? {})
            : <String, dynamic>{};

        totalCredits = (creditsData['total_credits'] as num?)?.toDouble() ?? 0.0;
        totalUsage = (creditsData['total_usage'] as num?)?.toDouble() ?? 0.0;
      } catch (e) {
        debugPrint('OpenRouterModelsService: Credits fetch warning: $e');
      }

      final balance = (totalCredits - totalUsage).clamp(0.0, double.infinity);

      return OpenRouterAccountInfo(
        label: label,
        freeLimit: freeLimit,
        freeUsed: freeUsed,
        freeRemaining: freeRemaining,
        totalCredits: totalCredits,
        totalUsage: totalUsage,
        balance: balance,
        isFreeTier: isFreeTier,
      );
    } catch (e) {
      debugPrint('OpenRouterModelsService: Error fetching account info: $e');
      return null;
    }
  }

  /// Get list of models: dynamically from OpenRouter or falling back to built-in catalog
  Future<List<OpenRouterModelInfo>> getModels({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedModels != null &&
        _lastModelsFetch != null &&
        DateTime.now().difference(_lastModelsFetch!) < const Duration(hours: 1)) {
      return _cachedModels!;
    }

    try {
      final resp = await _dio.get('https://openrouter.ai/api/v1/models');
      final data = resp.data;
      final List rawList;
      if (data is Map<String, dynamic> && data['data'] is List) {
        rawList = data['data'] as List;
      } else if (data is String) {
        final parsed = jsonDecode(data) as Map<String, dynamic>;
        rawList = parsed['data'] as List? ?? [];
      } else {
        rawList = [];
      }

      final List<OpenRouterModelInfo> result = [];

      for (final item in rawList) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        final isFree = id.endsWith(':free');
        // We include all free models, plus notable coding and deepseek/claude models
        final isRelevant = isFree ||
            id.startsWith('deepseek/') ||
            id.startsWith('anthropic/') ||
            id.contains('coder') ||
            id.contains('code') ||
            id.startsWith('qwen/');

        if (!isRelevant) continue;

        final name = item['name']?.toString() ?? id.split('/').last;
        final description = item['description']?.toString() ?? '';
        final contextLength = (item['context_length'] as num?)?.toInt() ?? 8192;
        final arch = item['architecture'] as Map<String, dynamic>?;
        final modality = arch?['modality']?.toString() ?? 'text->text';
        final pricing = item['pricing'] as Map<String, dynamic>?;
        final promptPrice = double.tryParse(pricing?['prompt']?.toString() ?? '0') ?? 0.0;
        final completionPrice = double.tryParse(pricing?['completion']?.toString() ?? '0') ?? 0.0;

        final providerName = id.contains('/') ? id.split('/').first : 'OpenRouter';
        final isReasoning = id.contains('r1') ||
            id.contains('reasoning') ||
            id.contains('think') ||
            name.toLowerCase().contains('r1') ||
            name.toLowerCase().contains('reasoning');
        final isCoding = id.contains('code') ||
            id.contains('coder') ||
            name.toLowerCase().contains('code') ||
            name.toLowerCase().contains('coder');

        result.add(OpenRouterModelInfo(
          id: id,
          name: name,
          description: description,
          contextLength: contextLength,
          modality: modality,
          isFree: isFree,
          isReasoning: isReasoning,
          isCoding: isCoding,
          providerName: providerName,
          promptPrice: promptPrice,
          completionPrice: completionPrice,
        ));
      }

      // Sort: free models first, then coding & reasoning
      result.sort((a, b) {
        if (a.isFree && !b.isFree) return -1;
        if (!a.isFree && b.isFree) return 1;
        if (a.isCoding && !b.isCoding) return -1;
        if (!a.isCoding && b.isCoding) return 1;
        return a.name.compareTo(b.name);
      });

      if (result.isNotEmpty) {
        _cachedModels = result;
        _lastModelsFetch = DateTime.now();
        return result;
      }
    } catch (e) {
      debugPrint('OpenRouterModelsService: Fetch models warning: $e');
    }

    return _cachedModels ?? getBuiltinFreeModels();
  }

  /// Built-in fallback catalog of all 16 free models + official DeepSeek models
  List<OpenRouterModelInfo> getBuiltinFreeModels() {
    return const [
      OpenRouterModelInfo(
        id: 'cohere/north-mini-code:free',
        name: 'Cohere: North Mini Code (free)',
        description: 'Специализированная модель для написания кода, отладки и агентских задач со встроенными размышлениями.',
        contextLength: 256000,
        modality: 'text->text',
        isFree: true,
        isReasoning: true,
        isCoding: true,
        providerName: 'Cohere',
      ),
      OpenRouterModelInfo(
        id: 'liquid/lfm-2.5-2.6b:free',
        name: 'LiquidAI: LFM2.5-2.6B (free)',
        description: 'Компактная сверхбыстрая модель архитектуры Liquid Neural Network с мгновенным откликом и reasoning-блоками.',
        contextLength: 65536,
        modality: 'text->text',
        isFree: true,
        isReasoning: true,
        isCoding: false,
        providerName: 'LiquidAI',
      ),
      OpenRouterModelInfo(
        id: 'nvidia/nemotron-3.5-lightning:free',
        name: 'NVIDIA: Nemotron 3.5 Lightning (free)',
        description: 'Флагманская высокоскоростная модель от NVIDIA с гигантским контекстным окном в 1 миллион токенов.',
        contextLength: 1000000,
        modality: 'text->text',
        isFree: true,
        isReasoning: false,
        isCoding: true,
        providerName: 'NVIDIA',
      ),
      OpenRouterModelInfo(
        id: 'nvidia/nemotron-3-ultra-550b-a55b:free',
        name: 'NVIDIA: Nemotron 3 Ultra (free)',
        description: 'Мощнейшая архитектура 550B параметров от NVIDIA с контекстом 1M токенов для глубокого анализа архитектуры.',
        contextLength: 1000000,
        modality: 'text->text',
        isFree: true,
        isReasoning: true,
        isCoding: true,
        providerName: 'NVIDIA',
      ),
      OpenRouterModelInfo(
        id: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
        name: 'NVIDIA: Nemotron 3 Nano Omni (free)',
        description: 'Мультимодальная модель с активным блоком пошаговых рассуждений (Reasoning) и контекстом 256k.',
        contextLength: 256000,
        modality: 'text+image+audio+video->text',
        isFree: true,
        isReasoning: true,
        isCoding: false,
        providerName: 'NVIDIA',
      ),
      OpenRouterModelInfo(
        id: 'google/gemma-4-31b-it:free',
        name: 'Google: Gemma 4 31B (free)',
        description: 'Мультимодальная модель Google последнего поколения (Gemma 4) с поддержкой изображений, видео и кода.',
        contextLength: 262144,
        modality: 'text+image+video->text',
        isFree: true,
        isReasoning: false,
        isCoding: true,
        providerName: 'Google',
      ),
      OpenRouterModelInfo(
        id: 'google/gemma-4-26b-a4b-it:free',
        name: 'Google: Gemma 4 26B A4B (free)',
        description: 'Оптимизированная по скорости версия Google Gemma 4 для повседневной кодогенерации и анализа интерфейсов.',
        contextLength: 262144,
        modality: 'text+image+video->text',
        isFree: true,
        isReasoning: false,
        isCoding: true,
        providerName: 'Google',
      ),
      OpenRouterModelInfo(
        id: 'thinkingmachines/inkling:free',
        name: 'Thinking Machines: Inkling (free)',
        description: 'Мультимодальная модель с контекстным окном свыше 1 миллиона токенов для работы с огромными файлами.',
        contextLength: 1048576,
        modality: 'text+image+audio->text',
        isFree: true,
        isReasoning: true,
        isCoding: false,
        providerName: 'Thinking Machines',
      ),
      OpenRouterModelInfo(
        id: 'thinkingmachines/inkling-small:free',
        name: 'Thinking Machines: Inkling Small (free)',
        description: 'Быстрая облегчённая версия Inkling с миллионным контекстом и низким временем первого токена.',
        contextLength: 1048576,
        modality: 'text+image+audio->text',
        isFree: true,
        isReasoning: false,
        isCoding: false,
        providerName: 'Thinking Machines',
      ),
      OpenRouterModelInfo(
        id: 'poolside/laguna-s-2.1:free',
        name: 'Poolside: Laguna S 2.1 (free)',
        description: 'Специализированная нейросеть для генерации, оптимизации и рефакторинга программного кода.',
        contextLength: 262144,
        modality: 'text->text',
        isFree: true,
        isReasoning: false,
        isCoding: true,
        providerName: 'Poolside',
      ),
      OpenRouterModelInfo(
        id: 'poolside/laguna-xs-2.1:free',
        name: 'Poolside: Laguna XS 2.1 (free)',
        description: 'Легковесная сверхбыстрая модель Poolside для автодополнения кода и простых правок.',
        contextLength: 262144,
        modality: 'text->text',
        isFree: true,
        isReasoning: false,
        isCoding: true,
        providerName: 'Poolside',
      ),
      OpenRouterModelInfo(
        id: 'nvidia/nemotron-3.5-super-vl:free',
        name: 'NVIDIA: Nemotron 3.5 Super VL (free)',
        description: 'NVIDIA Vision-Language модель с контекстом 1M токенов для анализа скриншотов приложений и макетов Figma.',
        contextLength: 1000000,
        modality: 'text+image+video->text',
        isFree: true,
        isReasoning: false,
        isCoding: false,
        providerName: 'NVIDIA',
      ),
      OpenRouterModelInfo(
        id: 'dots-studio/dots-3-note-preview:free',
        name: 'Dots Studio: Dots3-Note Preview (free)',
        description: 'Мультимодальная модель для структурирования документации, заметок и технического проектирования.',
        contextLength: 512000,
        modality: 'text+image->text',
        isFree: true,
        isReasoning: false,
        isCoding: false,
        providerName: 'Dots Studio',
      ),
      OpenRouterModelInfo(
        id: 'xingchen-agi/xing4.0-29b-a4b:free',
        name: 'XingChen: Xing4.0 29B A4B (free)',
        description: 'Широкопрофильная языковая модель XingChen с контекстным окном 262k для решения комплексных задач.',
        contextLength: 262144,
        modality: 'text->text',
        isFree: true,
        isReasoning: false,
        isCoding: false,
        providerName: 'XingChen',
      ),
      OpenRouterModelInfo(
        id: 'nvidia/nemotron-3-super-120b-a12b:free',
        name: 'NVIDIA: Nemotron 3 Super (free)',
        description: '120B модель NVIDIA с высоким качеством обобщения и синтеза логических цепочек.',
        contextLength: 262144,
        modality: 'text->text',
        isFree: true,
        isReasoning: false,
        isCoding: false,
        providerName: 'NVIDIA',
      ),
      OpenRouterModelInfo(
        id: 'nvidia/nemotron-3.5-content-safety:free',
        name: 'NVIDIA: Nemotron 3.5 Safety (free)',
        description: 'Фильтрующая модель для проверки сгенерированных артефактов на безопасность и соответствие политикам.',
        contextLength: 128000,
        modality: 'text+image->text',
        isFree: true,
        isReasoning: false,
        isCoding: false,
        providerName: 'NVIDIA',
      ),
      // Official DeepSeek
      OpenRouterModelInfo(
        id: 'deepseek-chat',
        name: 'DeepSeek Chat (V3)',
        description: 'Официальная модель DeepSeek V3 (671B MoE). Сверхбыстрый автономный агент для рефакторинга и разработки.',
        contextLength: 65536,
        modality: 'text->text',
        isFree: false,
        isReasoning: false,
        isCoding: true,
        providerName: 'DeepSeek',
      ),
      OpenRouterModelInfo(
        id: 'deepseek-reasoner',
        name: 'DeepSeek Reasoner (R1)',
        description: 'Официальная модель DeepSeek R1 с глубокой пошаговой логикой и отображением цепочки рассуждений (Thinking).',
        contextLength: 65536,
        modality: 'text->text',
        isFree: false,
        isReasoning: true,
        isCoding: true,
        providerName: 'DeepSeek',
      ),
      // Paid OpenRouter popular
      OpenRouterModelInfo(
        id: 'anthropic/claude-3.7-sonnet',
        name: 'Claude 3.7 Sonnet',
        description: 'Флагман Anthropic с гибридным режимом мгновенного ответа и расширенного рассуждения.',
        contextLength: 200000,
        modality: 'text+image->text',
        isFree: false,
        isReasoning: true,
        isCoding: true,
        providerName: 'Anthropic',
      ),
      OpenRouterModelInfo(
        id: 'anthropic/claude-3.5-sonnet',
        name: 'Claude 3.5 Sonnet',
        description: 'Золотой стандарт кодогенерации и агентской работы от Anthropic.',
        contextLength: 200000,
        modality: 'text+image->text',
        isFree: false,
        isReasoning: false,
        isCoding: true,
        providerName: 'Anthropic',
      ),
    ];
  }
}
