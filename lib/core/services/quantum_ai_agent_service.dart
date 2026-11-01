import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class QuantumModelItem {
  final String id;
  final String name;
  final String providerName; // 'OpenRouter', 'DeepSeek Direct', 'OpenAI Direct', 'Anthropic Direct', 'Local'
  final String category; // 'Популярные', 'Рассуждения', 'Кодинг', 'Бесплатные', 'Флагманы', 'Прямой API'
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
      id: 'deepseek/deepseek-r1',
      name: 'DeepSeek R1 (Reasoning)',
      providerName: 'OpenRouter',
      category: 'Рассуждения',
      badge: 'R1 Reasoning',
      badgeColorValue: 0xFF8B5CF6,
      isReasoning: true,
    ),
    QuantumModelItem(
      id: 'deepseek/deepseek-r1:free',
      name: 'DeepSeek R1 (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
      isReasoning: true,
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
      id: 'google/gemini-2.0-flash-exp:free',
      name: 'Gemini 2.0 Flash (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
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
      id: 'qwen/qwen-2.5-coder-32b-instruct:free',
      name: 'Qwen 2.5 Coder (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
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
      id: 'meta-llama/llama-3.3-70b-instruct:free',
      name: 'Llama 3.3 70B (Free)',
      providerName: 'OpenRouter',
      category: 'Бесплатные',
      badge: 'FREE',
      badgeColorValue: 0xFF10B981,
    ),
    QuantumModelItem(
      id: 'mistralai/codestral-2501',
      name: 'Codestral 2501',
      providerName: 'OpenRouter',
      category: 'Кодинг',
      badge: 'Codestral',
      badgeColorValue: 0xFFF97316,
    ),

    // Direct API Models
    QuantumModelItem(
      id: 'deepseek-chat',
      name: 'DeepSeek V3 (Direct)',
      providerName: 'DeepSeek Direct',
      category: 'Прямой API',
      badge: 'Direct API',
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
    QuantumModelItem(
      id: 'gpt-4o',
      name: 'OpenAI GPT-4o (Direct)',
      providerName: 'OpenAI Direct',
      category: 'Прямой API',
      badge: 'Direct API',
      badgeColorValue: 0xFF059669,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'claude-3-5-sonnet-20241022',
      name: 'Claude 3.5 Sonnet (Direct)',
      providerName: 'Anthropic Direct',
      category: 'Прямой API',
      badge: 'Direct API',
      badgeColorValue: 0xFFD97706,
      isOpenRouter: false,
    ),
    QuantumModelItem(
      id: 'default',
      name: 'Локальный / Custom API',
      providerName: 'Local',
      category: 'Локальный',
      badge: 'Local',
      badgeColorValue: 0xFF6B7280,
      isOpenRouter: false,
    ),
  ];
}

enum AiProvider {
  deepseek('DeepSeek', 'deepseek-chat'),
  deepseekR1('DeepSeek R1', 'deepseek-reasoner'),
  openrouterClaude('Claude 3.5 Sonnet', 'anthropic/claude-3.5-sonnet'),
  openrouterGpt4o('GPT-4o (OpenRouter)', 'openai/gpt-4o'),
  openrouterQwen('Qwen 2.5 Coder 32B', 'qwen/qwen-2.5-coder-32b-instruct'),
  openrouterGemini('Gemini 2.0 Flash', 'google/gemini-2.0-flash-001'),
  openai('OpenAI GPT-4o', 'gpt-4o'),
  anthropic('Anthropic Claude', 'claude-3-5-sonnet-20241022'),
  custom('Локальный / Custom API', 'default');

  final String label;
  final String defaultModel;
  const AiProvider(this.label, this.defaultModel);
}

enum MessageRole { user, assistant, system }

class AgentAction {
  final String type; // 'write_file', 'read_file', 'run_command', 'diff'
  final String path;
  final String? content;
  final String? command;
  bool isExecuted;

  AgentAction({
    required this.type,
    required this.path,
    this.content,
    this.command,
    this.isExecuted = false,
  });
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

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.thinking,
    this.isThinking = false,
    this.isStreaming = false,
    required this.timestamp,
    List<AgentAction>? actions,
  }) : actions = actions ?? [];
}

class QuantumAiAgentService extends ChangeNotifier {
  final RuntimeService _runtime;
  final SettingsState Function() _getSettings;
  final String? Function() _getWorkspacePath;

  QuantumAiAgentService(this._runtime, this._getSettings, this._getWorkspacePath) {
    // Умный повтор сетевых запросов при сбоях связи (dio_smart_retry)
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        logPrint: (msg) => debugPrint('[QuantumAI-Retry] $msg'),
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
        ],
      ),
    );
    _initDefaultGreeting();
  }

  static List<QuantumModelItem> get predefinedModels => QuantumModelItem.predefinedModels;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
  ));

  CancelToken? _currentCancelToken;
  QuantumModelItem _selectedModel = QuantumModelItem.predefinedModels[0]; // DeepSeek V3 by default
  AiProvider _selectedProvider = AiProvider.deepseek;
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  String _statusMessage = 'Готов к работе';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  String get statusMessage => _statusMessage;
  QuantumModelItem get selectedModel => _selectedModel;
  AiProvider get selectedProvider => _selectedProvider;

  void selectModel(QuantumModelItem model) {
    _selectedModel = model;
    notifyListeners();
  }

  void setCustomModel(String modelId) {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;
    final isR1 = trimmed.toLowerCase().contains('r1') ||
        trimmed.toLowerCase().contains('reasoning') ||
        trimmed.toLowerCase().contains('o3') ||
        trimmed.toLowerCase().contains('o1');

    _selectedModel = QuantumModelItem(
      id: trimmed,
      name: trimmed.contains('/') ? trimmed.split('/').last : trimmed,
      providerName: 'OpenRouter',
      category: 'Пользовательские',
      badge: isR1 ? 'Reasoning' : 'Custom',
      badgeColorValue: isR1 ? 0xFF8B5CF6 : 0xFF10B981,
      isReasoning: isR1,
      isOpenRouter: true,
    );
    notifyListeners();
  }

  void selectProvider(AiProvider provider) {
    _selectedProvider = provider;
    switch (provider) {
      case AiProvider.deepseek:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'deepseek/deepseek-chat', orElse: () => QuantumModelItem.predefinedModels[0]);
        break;
      case AiProvider.deepseekR1:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'deepseek/deepseek-r1', orElse: () => QuantumModelItem.predefinedModels[1]);
        break;
      case AiProvider.openrouterClaude:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'anthropic/claude-3.5-sonnet', orElse: () => QuantumModelItem.predefinedModels[4]);
        break;
      case AiProvider.openrouterGpt4o:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'openai/gpt-4o', orElse: () => QuantumModelItem.predefinedModels[6]);
        break;
      case AiProvider.openrouterQwen:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'qwen/qwen-2.5-coder-32b-instruct', orElse: () => QuantumModelItem.predefinedModels[13]);
        break;
      case AiProvider.openrouterGemini:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'google/gemini-2.0-flash-001', orElse: () => QuantumModelItem.predefinedModels[10]);
        break;
      case AiProvider.openai:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'gpt-4o', orElse: () => QuantumModelItem.predefinedModels[19]);
        break;
      case AiProvider.anthropic:
        _selectedModel = QuantumModelItem.predefinedModels.firstWhere((m) => m.id == 'claude-3-5-sonnet-20241022', orElse: () => QuantumModelItem.predefinedModels[20]);
        break;
      case AiProvider.custom:
        _selectedModel = QuantumModelItem.predefinedModels.last;
        break;
    }
    notifyListeners();
  }

  void clearChat() {
    _messages.clear();
    _initDefaultGreeting();
    notifyListeners();
  }

  void _initDefaultGreeting() {
    _messages.add(
      ChatMessage(
        id: 'msg_welcome',
        role: MessageRole.assistant,
        text: 'Привет! Я встроенный Quantum AI Агент. Я подключен напрямую к твоему проекту, могу анализировать файлы, писать код, находить ошибки и предлагать готовые изменения с кнопкой применения прямо в редактор.\n\nЧем могу помочь?',
        timestamp: DateTime.now(),
      ),
    );
  }

  void stopGeneration() {
    _currentCancelToken?.cancel('Пользователь остановил генерацию');
    _currentCancelToken = null;
    _isGenerating = false;
    _statusMessage = 'Остановлено';
    if (_messages.isNotEmpty && _messages.last.isStreaming) {
      _messages.last.isStreaming = false;
      _messages.last.isThinking = false;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isGenerating) return;

    // Проверка наличия сети через connectivity_plus
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.isNotEmpty &&
          connectivityResults.every((r) => r == ConnectivityResult.none)) {
        _statusMessage = 'Ошибка: нет подключения к сети';
        _messages.add(
          ChatMessage(
            id: 'msg_offline_${DateTime.now().millisecondsSinceEpoch}',
            role: MessageRole.assistant,
            text: '⚠️ Нет активного подключения к интернету. Проверьте соединение с Wi-Fi или мобильной сетью для отправки запросов к ИИ.',
            timestamp: DateTime.now(),
          ),
        );
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[QuantumAI] Connectivity check error: $e');
    }

    final userMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      text: query,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);

    final assistantMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch + 1}',
      role: MessageRole.assistant,
      text: '',
      isStreaming: true,
      timestamp: DateTime.now(),
    );
    _messages.add(assistantMsg);
    _isGenerating = true;
    _statusMessage = 'Генерация ответа...';
    notifyListeners();

    _currentCancelToken = CancelToken();

    try {
      final settings = _getSettings();
      final wsPath = _getWorkspacePath();
      final systemPrompt = _buildSystemPrompt(wsPath);

      // Формируем историю сообщений
      final apiMessages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
      ];

      for (final m in _messages.take(_messages.length - 1)) {
        if (m.role == MessageRole.user) {
          apiMessages.add({'role': 'user', 'content': m.text});
        } else if (m.role == MessageRole.assistant) {
          apiMessages.add({'role': 'assistant', 'content': m.text});
        }
      }

      await _streamCompletion(
        messages: apiMessages,
        settings: settings,
        targetMsg: assistantMsg,
      );

      // После завершения парсим действия (action tags)
      _parseActions(assistantMsg);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        _statusMessage = 'Остановлено пользователем';
      } else {
        assistantMsg.text += '\n\n⚠️ **Ошибка генерации:** $e';
        _statusMessage = 'Ошибка: $e';
      }
    } finally {
      assistantMsg.isStreaming = false;
      assistantMsg.isThinking = false;
      _isGenerating = false;
      _currentCancelToken = null;
      notifyListeners();
    }
  }

  String _buildSystemPrompt(String? wsPath) {
    return '''Ты — ведущий ИИ-разработчик и ассистент Quantum IDE.
Ты работаешь непосредственно с проектом пользователя.
Текущая рабочая директория: ${wsPath ?? 'корень проекта'}.

ПРАВИЛА И ИНСТРУМЕНТЫ:
1. Пиши чистый, современный, структурированный код.
2. Когда ты создаёшь или модифицируешь файл, оборачивай код в специальный блок действия:
<action type="write_file" path="относительный_путь/к/файлу">
содержимое файла
</action>

3. Для вывода команд терминала:
<action type="run_command">
команда_bash
</action>

4. Объясняй изменения кратко и по делу. Поддерживай формулы KaTeX и Markdown.
''';
  }

  Future<void> _streamCompletion({
    required List<Map<String, String>> messages,
    required SettingsState settings,
    required ChatMessage targetMsg,
  }) async {
    String endpoint;
    String apiKey;
    String model = _selectedModel.id;

    if (_selectedModel.isOpenRouter) {
      endpoint = 'https://openrouter.ai/api/v1/chat/completions';
      apiKey = settings.openrouterApiKey;
      // Smart fallback: if user has no OpenRouter key but has DeepSeek direct key
      if (apiKey.isEmpty && settings.deepseekApiKey.isNotEmpty && model.startsWith('deepseek/')) {
        endpoint = 'https://api.deepseek.com/chat/completions';
        apiKey = settings.deepseekApiKey;
        model = model.contains('r1') ? 'deepseek-reasoner' : 'deepseek-chat';
      }
    } else {
      // Direct API model
      if (_selectedModel.id.startsWith('deepseek')) {
        if (settings.deepseekApiKey.isNotEmpty) {
          endpoint = 'https://api.deepseek.com/chat/completions';
          apiKey = settings.deepseekApiKey;
          model = _selectedModel.id;
        } else if (settings.openrouterApiKey.isNotEmpty) {
          // SMART FALLBACK: user entered OpenRouter key, route DeepSeek through OpenRouter!
          endpoint = 'https://openrouter.ai/api/v1/chat/completions';
          apiKey = settings.openrouterApiKey;
          model = _selectedModel.id == 'deepseek-reasoner'
              ? 'deepseek/deepseek-r1'
              : 'deepseek/deepseek-chat';
        } else {
          endpoint = 'https://api.deepseek.com/chat/completions';
          apiKey = '';
          model = _selectedModel.id;
        }
      } else if (_selectedModel.id.startsWith('gpt')) {
        if (settings.openaiApiKey.isNotEmpty) {
          endpoint = 'https://api.openai.com/v1/chat/completions';
          apiKey = settings.openaiApiKey;
        } else if (settings.openrouterApiKey.isNotEmpty) {
          endpoint = 'https://openrouter.ai/api/v1/chat/completions';
          apiKey = settings.openrouterApiKey;
          model = 'openai/${_selectedModel.id}';
        } else {
          endpoint = 'https://api.openai.com/v1/chat/completions';
          apiKey = '';
        }
      } else if (_selectedModel.id.startsWith('claude')) {
        if (settings.anthropicApiKey.isNotEmpty) {
          endpoint = 'https://api.anthropic.com/v1/messages';
          apiKey = settings.anthropicApiKey;
        } else if (settings.openrouterApiKey.isNotEmpty) {
          endpoint = 'https://openrouter.ai/api/v1/chat/completions';
          apiKey = settings.openrouterApiKey;
          model = 'anthropic/${_selectedModel.id}';
        } else {
          endpoint = 'https://api.anthropic.com/v1/messages';
          apiKey = '';
        }
      } else {
        endpoint = 'http://127.0.0.1:11434/v1/chat/completions';
        apiKey = settings.deepseekApiKey.isNotEmpty ? settings.deepseekApiKey : 'ollama';
      }
    }

    if (apiKey.isEmpty && _selectedModel.id != 'default') {
      if (_selectedModel.isOpenRouter) {
        throw Exception(
          'Не указан OpenRouter API ключ. Введите его в настройках ⚙️ (вверху справа). '
          'С ключом OpenRouter вам доступны все модели: DeepSeek V3/R1, Claude 3.7, GPT-4o, Gemini 2.0, Qwen!',
        );
      } else {
        throw Exception(
          'Не указан API ключ для ${_selectedModel.name}. Введите ключ в настройках ⚙️ (или используйте ключ OpenRouter, поддерживающий любые модели).',
        );
      }
    }

    final isUsingOpenRouter = endpoint.contains('openrouter.ai');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    if (isUsingOpenRouter) {
      headers['HTTP-Referer'] = 'https://github.com/Lesorub361/quantum_ide';
      headers['X-Title'] = 'Quantum IDE';
    }

    final body = {
      'model': model,
      'messages': messages,
      'stream': true,
      'temperature': 0.3,
    };

    final response = await _dio.post<ResponseBody>(
      endpoint,
      data: jsonEncode(body),
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
      ),
      cancelToken: _currentCancelToken,
    );

    final stream = response.data?.stream;
    if (stream == null) throw Exception('Пустой поток ответа от сервера');

    final buffer = StringBuffer();
    final thinkBuffer = StringBuffer();
    bool insideThink = false;

    await for (final chunk in stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
      final line = chunk.trim();
      if (line.isEmpty || line == 'data: [DONE]') continue;
      if (!line.startsWith('data: ')) continue;

      final jsonStr = line.substring(6).trim();
      try {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final choices = decoded['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // 1. Проверяем reasoning_content (DeepSeek R1 / o3-mini)
        final reasoning = delta['reasoning_content'] as String?;
        if (reasoning != null && reasoning.isNotEmpty) {
          thinkBuffer.write(reasoning);
          targetMsg.thinking = thinkBuffer.toString();
          targetMsg.isThinking = true;
          notifyListeners();
          continue;
        }

        // 2. Обычный контент
        final content = delta['content'] as String?;
        if (content != null && content.isNotEmpty) {
          // Проверяем теги <think> и </think> в обычном контенте
          if (content.contains('<think>')) {
            insideThink = true;
            targetMsg.isThinking = true;
          }

          if (insideThink) {
            if (content.contains('</think>')) {
              insideThink = false;
              targetMsg.isThinking = false;
              final parts = content.split('</think>');
              thinkBuffer.write(parts[0].replaceAll('<think>', ''));
              targetMsg.thinking = thinkBuffer.toString();
              if (parts.length > 1) {
                buffer.write(parts[1]);
                targetMsg.text = buffer.toString();
              }
            } else {
              thinkBuffer.write(content.replaceAll('<think>', ''));
              targetMsg.thinking = thinkBuffer.toString();
            }
          } else {
            buffer.write(content);
            targetMsg.text = buffer.toString();
          }
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  void _parseActions(ChatMessage msg) {
    final text = msg.text;
    final writeRegExp = RegExp(r'<action\s+type="write_file"\s+path="([^"]+)">([\s\S]*?)<\/action>');
    final matches = writeRegExp.allMatches(text);

    for (final match in matches) {
      final path = match.group(1)?.trim() ?? '';
      final content = match.group(2)?.trim() ?? '';
      if (path.isNotEmpty) {
        msg.actions.add(
          AgentAction(
            type: 'write_file',
            path: path,
            content: content,
          ),
        );
      }
    }

    final cmdRegExp = RegExp(r'<action\s+type="run_command">([\s\S]*?)<\/action>');
    final cmdMatches = cmdRegExp.allMatches(text);
    for (final match in cmdMatches) {
      final cmd = match.group(1)?.trim() ?? '';
      if (cmd.isNotEmpty) {
        msg.actions.add(
          AgentAction(
            type: 'run_command',
            path: '',
            command: cmd,
          ),
        );
      }
    }
    notifyListeners();
  }

  /// Применяет действие агента (записывает файл в проект)
  Future<bool> executeWriteAction(AgentAction action) async {
    final ws = _getWorkspacePath();
    if (ws == null || action.content == null) return false;

    try {
      final fullPath = p.isAbsolute(action.path) ? action.path : p.join(ws, action.path);
      final file = File(fullPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(action.content!);
      action.isExecuted = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[QuantumAiAgent] Write error: $e');
      return false;
    }
  }

  /// Запускает команду терминала
  Future<void> executeCommandAction(AgentAction action) async {
    final ws = _getWorkspacePath();
    if (action.command == null) return;
    try {
      await _runtime.runCommand(action.command!, workingDirectory: ws);
      action.isExecuted = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[QuantumAiAgent] Command error: $e');
    }
  }
}

final quantumAiAgentServiceProvider = ChangeNotifierProvider<QuantumAiAgentService>((ref) {
  final runtime = ref.watch(runtimeServiceProvider);
  final settings = () => ref.read(settingsProvider);
  final ws = () => ref.read(workspaceProvider).currentPath;
  return QuantumAiAgentService(runtime, settings, ws);
});
