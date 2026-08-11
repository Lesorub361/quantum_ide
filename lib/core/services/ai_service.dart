import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';

// ─── Хранилище ключей и настроек ─────────────────────────────────────────────

class AISettings {
  final String selectedProviderId;
  final String selectedModel;
  final Map<String, String> apiKeys; // providerId -> apiKey
  final Map<String, String>
  baseUrls; // providerId -> custom base url (for Ollama/LM Studio)
  final LocalAiEngine selectedLocalEngine;

  const AISettings({
    this.selectedProviderId = 'google',
    this.selectedModel = 'gemini-2.5-flash',
    this.apiKeys = const {},
    this.baseUrls = const {},
    this.selectedLocalEngine = LocalAiEngine.llamaServer,
  });

  String get currentApiKey => apiKeys[selectedProviderId] ?? '';
  AiProviderConfig get currentProvider => AiProviders.byId(selectedProviderId);

  AISettings copyWith({
    String? selectedProviderId,
    String? selectedModel,
    Map<String, String>? apiKeys,
    Map<String, String>? baseUrls,
    LocalAiEngine? selectedLocalEngine,
  }) {
    return AISettings(
      selectedProviderId: selectedProviderId ?? this.selectedProviderId,
      selectedModel: selectedModel ?? this.selectedModel,
      apiKeys: apiKeys ?? this.apiKeys,
      baseUrls: baseUrls ?? this.baseUrls,
      selectedLocalEngine: selectedLocalEngine ?? this.selectedLocalEngine,
    );
  }
}

// ─── Token Usage ─────────────────────────────────────────────────────────────

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });
}

class ChatResponse {
  final String text;
  final TokenUsage? tokenUsage;

  const ChatResponse(this.text, {this.tokenUsage});
}

// ─── AI Service ──────────────────────────────────────────────────────────────

class AIService {
  AISettings _settings = const AISettings();
  GenerativeModel? _geminiModel;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
    ),
  );
  static const int _maxRetries = 3;

  AISettings get settings => _settings;
  String get selectedProviderId => _settings.selectedProviderId;
  String get selectedModel => _settings.selectedModel;

  // Backwards compat
  String get apiKey => _settings.currentApiKey;

  AIService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();

    var providerId = prefs.getString('ai_provider_id') ?? 'google';
    var localEngineIndex =
        prefs.getInt('ai_local_engine') ?? LocalAiEngine.llamaServer.index;

    // Migrate old local providers to consolidated local_edge provider
    if (providerId == 'ollama') {
      providerId = 'local_edge';
      localEngineIndex = LocalAiEngine.ollama.index;
      await prefs.setString('ai_provider_id', 'local_edge');
      await prefs.setInt('ai_local_engine', localEngineIndex);
    } else if (providerId == 'lmstudio') {
      providerId = 'local_edge';
      localEngineIndex = LocalAiEngine.lmStudio.index;
      await prefs.setString('ai_provider_id', 'local_edge');
      await prefs.setInt('ai_local_engine', localEngineIndex);
    }

    final localEngine = LocalAiEngine.values[localEngineIndex];

    var model = prefs.getString('ai_selected_model') ?? 'gemini-2.5-flash';
    if (model == 'gemini-2.0-flash') {
      model = 'gemini-2.5-flash';
    }

    // Load all keys
    final keys = <String, String>{};
    for (final p in AiProviders.all) {
      final k = prefs.getString('ai_key_${p.id}');
      if (k != null && k.isNotEmpty) {
        keys[p.id] = k;
      }
    }

    // Load custom base URLs
    final urls = <String, String>{};
    for (final p in AiProviders.all) {
      final u = prefs.getString('ai_url_${p.id}');
      if (u != null && u.isNotEmpty) urls[p.id] = u;
    }

    _settings = AISettings(
      selectedProviderId: providerId,
      selectedModel: model,
      apiKeys: keys,
      baseUrls: urls,
      selectedLocalEngine: localEngine,
    );

    _rebuildGemini();
  }

  void _rebuildGemini() {
    final key = _settings.apiKeys['google'] ?? '';
    if (_settings.selectedProviderId == 'google' && key.isNotEmpty) {
      try {
        // For custom proxy URLs: we still use standard GenerativeModel.
        // Custom base URL routing for Gemini proxies is handled via Dio
        // in _executeOpenAiCompatRequest (OpenAI-compatible fallback).
        _geminiModel = GenerativeModel(
          model: _settings.selectedModel,
          apiKey: key,
        );
      } catch (_) {
        _geminiModel = null;
      }
    } else {
      _geminiModel = null;
    }
  }

  // ─── Сохранение настроек ─────────────────────────────────────────────────

  LocalAiEngine get selectedLocalEngine => _settings.selectedLocalEngine;

  Future<void> setProvider(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider_id', providerId);
    _settings = _settings.copyWith(selectedProviderId: providerId);
    _rebuildGemini();
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_selected_model', model);
    _settings = _settings.copyWith(selectedModel: model);
    _rebuildGemini();
  }

  Future<void> setApiKey(String providerId, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_key_$providerId', key);
    final newKeys = Map<String, String>.from(_settings.apiKeys);
    newKeys[providerId] = key;
    _settings = _settings.copyWith(apiKeys: newKeys);
    _rebuildGemini();
  }

  Future<void> setBaseUrl(String providerId, String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_url_$providerId', url);
    final newUrls = Map<String, String>.from(_settings.baseUrls);
    newUrls[providerId] = url;
    _settings = _settings.copyWith(baseUrls: newUrls);
  }

  Future<void> setLocalEngine(LocalAiEngine engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_local_engine', engine.index);
    _settings = _settings.copyWith(selectedLocalEngine: engine);
  }

  String getApiKey(String providerId) => _settings.apiKeys[providerId] ?? '';
  String getBaseUrl(String providerId) {
    final custom = _settings.baseUrls[providerId];
    if (custom != null && custom.isNotEmpty) return custom;
    if (providerId == 'local_edge') {
      return _settings.selectedLocalEngine.defaultBaseUrl;
    }
    return AiProviders.byId(providerId).baseUrl;
  }

  String _cleanseBaseUrl(String url) {
    var cleanUrl = url.trim();
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (cleanUrl.endsWith('/chat/completions')) {
      cleanUrl = cleanUrl.substring(
        0,
        cleanUrl.length - '/chat/completions'.length,
      );
    } else if (cleanUrl.endsWith('/models')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - '/models'.length);
    }
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    return cleanUrl;
  }

  Future<Response> _executeOpenAiCompatRequest(
    String pid,
    String pathSuffix, { // e.g. '/chat/completions' or '/models'
    dynamic data,
    Options? options,
    bool isGet = false,
  }) async {
    final key = _settings.apiKeys[pid] ?? '';
    final originalBaseUrl = getBaseUrl(pid);
    final cleansed = _cleanseBaseUrl(originalBaseUrl);

    final candidates = <String>[];
    candidates.add('$cleansed$pathSuffix');
    if (!cleansed.endsWith('/v1')) {
      candidates.add('$cleansed/v1$pathSuffix');
    }

    dynamic lastException;
    for (final endpoint in candidates) {
      for (int attempt = 0; attempt <= _maxRetries; attempt++) {
        try {
          final requestOptions = (options ?? Options()).copyWith(
            headers: {
              if (isGet == false) 'Content-Type': 'application/json',
              if (key.isNotEmpty) 'Authorization': 'Bearer $key',
              ...?options?.headers,
            },
            receiveTimeout: pid == 'local_edge' ? Duration.zero : null,
          );

          final Response resp;
          if (isGet) {
            resp = await _dio.get(endpoint, options: requestOptions);
          } else {
            resp = await _dio.post(endpoint, data: data, options: requestOptions);
          }

          if (resp.statusCode == 404) {
            break; // Try next candidate
          }

          // Handle 429 (rate limit) with exponential backoff
          if (resp.statusCode == 429 && attempt < _maxRetries) {
            final retryAfter = resp.headers.value('retry-after');
            final delayMs = retryAfter != null
                ? (int.tryParse(retryAfter) ?? 1) * 1000
                : (1 << attempt) * 1000; // 1s, 2s, 4s
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }

          // Handle 403 (forbidden) - throw with clear message
          if (resp.statusCode == 403) {
            throw Exception(
              'API key is invalid or expired (HTTP 403). '
              'Please check your API key in AI Settings.',
            );
          }

          // Handle 5xx server errors with retry
          if (resp.statusCode != null && resp.statusCode! >= 500 && attempt < _maxRetries) {
            await Future.delayed(Duration(milliseconds: (1 << attempt) * 1000));
            continue;
          }

          // If worked with /v1 fallback, auto-update base URL
          if (endpoint.contains('/v1$pathSuffix') &&
              !originalBaseUrl.endsWith('/v1')) {
            final newBaseUrl = '$cleansed/v1';
            await setBaseUrl(pid, newBaseUrl);
          }

          return resp;
        } on DioException catch (e) {
          lastException = e;
          // Retry on connection errors
          if (attempt < _maxRetries && _isRetryableError(e)) {
            await Future.delayed(Duration(milliseconds: (1 << attempt) * 1000));
            continue;
          }
          break; // Move to next candidate
        } catch (e) {
          lastException = e;
          break;
        }
      }
    }

    throw lastException ?? Exception('Failed to connect to API after $_maxRetries retries');
  }

  bool _isRetryableError(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  // ─── Загрузка доступных моделей ──────────────────────────────────────────

  Future<List<String>> fetchAvailableModels([String? providerId]) async {
    final pid = providerId ?? _settings.selectedProviderId;
    switch (pid) {
      case 'google':
        return await _fetchGoogleModels();
      case 'openai':
      case 'deepseek':
      case 'groq':
      case 'openrouter':
      case 'grok':
      case 'together':
      case 'perplexity':
      case 'fireworks':
      case 'kimi':
      case 'nvidia':
        return await _fetchOpenAiCompatModels(pid);
      case 'anthropic':
        return _anthropicModels(); // API не отдаёт список
      case 'local_edge':
        switch (_settings.selectedLocalEngine) {
          case LocalAiEngine.llamaServer:
            return await _fetchLocalEdgeModels();
          case LocalAiEngine.ollama:
            return await _fetchOllamaModels();
          case LocalAiEngine.lmStudio:
            return await _fetchLmStudioModels();
        }
      default:
        return AiProviders.byId(pid).defaultModels;
    }
  }

  Future<List<String>> _fetchGoogleModels() async {
    final key = _settings.apiKeys['google'] ?? '';
    if (key.isEmpty) {
      throw Exception('API key for Google is not set');
    }

    final originalBaseUrl = getBaseUrl('google');
    final cleansed = _cleanseBaseUrl(originalBaseUrl);

    final candidates = <String>[];
    candidates.add('$cleansed/models');
    if (!cleansed.endsWith('/v1')) {
      candidates.add('$cleansed/v1/models');
    }
    candidates.add('$cleansed/openai/v1/models');
    candidates.add('$cleansed/openai/models');

    dynamic lastException;
    for (final endpoint in candidates) {
      try {
        final isDefaultGoogle = endpoint.contains(
          'generativelanguage.googleapis.com',
        );
        final resp = await _dio.get(
          endpoint,
          queryParameters: isDefaultGoogle ? {'key': key} : null,
          options: Options(
            headers: {
              if (!isDefaultGoogle) 'Authorization': 'Bearer $key',
              if (!isDefaultGoogle) 'x-goog-api-key': key,
            },
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

        if (resp.statusCode == 404) {
          continue;
        }

        final data = resp.data;
        List<String> models = [];
        if (data is Map) {
          if (data.containsKey('models')) {
            models = (data['models'] as List)
                .map((m) => (m['name'] as String).replaceAll('models/', ''))
                .toList();
          } else if (data.containsKey('data')) {
            models = (data['data'] as List)
                .map((m) => m['id'] as String)
                .toList();
          }
        }

        if (models.isEmpty) {
          continue;
        }

        // Auto-correct base URL if a fallback endpoint worked
        if (endpoint.contains('/v1/models') &&
            !originalBaseUrl.endsWith('/v1')) {
          await setBaseUrl('google', '$cleansed/v1');
        } else if (endpoint.contains('/openai/v1/models') &&
            !originalBaseUrl.contains('/openai')) {
          await setBaseUrl('google', '$cleansed/openai/v1');
        } else if (endpoint.contains('/openai/models') &&
            !originalBaseUrl.contains('/openai')) {
          await setBaseUrl('google', '$cleansed/openai');
        }

        final filtered =
            models.where((m) => m.toLowerCase().contains('gemini')).toList()
              ..sort();
        if (filtered.isNotEmpty) {
          return filtered;
        }
        models.sort();
        return models;
      } catch (e) {
        lastException = e;
        continue;
      }
    }

    throw lastException ?? Exception('Failed to load Google models');
  }

  Future<List<String>> _fetchOpenAiCompatModels(String pid) async {
    final key = _settings.apiKeys[pid] ?? '';
    if (key.isEmpty) {
      throw Exception(
        'API key for ${AiProviders.byId(pid).displayName} is not set',
      );
    }
    try {
      final resp = await _executeOpenAiCompatRequest(
        pid,
        '/models',
        isGet: true,
      );
      final models =
          (resp.data['data'] as List).map((m) => m['id'] as String).toList()
            ..sort();
      if (models.isEmpty) {
        throw Exception(
          'Received empty model list from ${AiProviders.byId(pid).displayName}',
        );
      }
      return models;
    } catch (e) {
      throw Exception('API error for ${AiProviders.byId(pid).displayName}: $e');
    }
  }

  List<String> _anthropicModels() => AiProviders.anthropic.defaultModels;

  Future<List<String>> _fetchOllamaModels() async {
    final base = getBaseUrl('local_edge');
    try {
      final resp = await _dio.get('$base/api/tags');
      final models =
          (resp.data['models'] as List).map((m) => m['name'] as String).toList()
            ..sort();
      if (models.isEmpty) {
        throw Exception('No models found in Ollama. Pull some models first.');
      }
      return models;
    } catch (e) {
      throw Exception(
        'Could not connect to Ollama at $base. Make sure Ollama is running.',
      );
    }
  }

  Future<List<String>> _fetchLmStudioModels() async {
    final base = getBaseUrl('local_edge');
    try {
      final resp = await _executeOpenAiCompatRequest(
        'local_edge',
        '/models',
        isGet: true,
      );
      final models =
          (resp.data['data'] as List).map((m) => m['id'] as String).toList()
            ..sort();
      if (models.isEmpty) {
        throw Exception('No models loaded in LM Studio.');
      }
      return models;
    } catch (e) {
      throw Exception(
        'Could not connect to LM Studio at $base. Make sure LM Studio is running.',
      );
    }
  }

  Future<List<String>> _fetchLocalEdgeModels() async {
    try {
      final resp = await _executeOpenAiCompatRequest(
        'local_edge',
        '/models',
        isGet: true,
      );
      final models =
          (resp.data['data'] as List).map((m) => m['id'] as String).toList()
            ..sort();
      if (models.isEmpty) {
        return AiProviders.localEdge.defaultModels;
      }
      return models;
    } catch (_) {
      return AiProviders.localEdge.defaultModels;
    }
  }

  /// Проверяет, доступна ли модель (пробный запрос с минимальным токеном)
  Future<bool> checkModelAvailability(
    String model, [
    String? providerId,
  ]) async {
    final pid = providerId ?? _settings.selectedProviderId;
    try {
      if (pid == 'google') {
        final key = _settings.apiKeys['google'] ?? '';
        if (key.isEmpty) return false;

        final originalBaseUrl = getBaseUrl('google');
        final cleansed = _cleanseBaseUrl(originalBaseUrl);

        final candidates = [
          '$cleansed/models/$model:generateContent',
          '$cleansed/v1/models/$model:generateContent',
          '$cleansed/chat/completions',
          '$cleansed/v1/chat/completions',
        ];

        for (final endpoint in candidates) {
          try {
            final isDefaultGoogle = endpoint.contains(
              'generativelanguage.googleapis.com',
            );
            final isChat = endpoint.contains('chat/completions');

            final Response resp;
            if (isChat) {
              resp = await _dio.post(
                endpoint,
                options: Options(
                  headers: {
                    'Authorization': 'Bearer $key',
                    'x-goog-api-key': key,
                    'Content-Type': 'application/json',
                  },
                  validateStatus: (s) => s != null && s < 600,
                  receiveTimeout: const Duration(seconds: 10),
                ),
                data: jsonEncode({
                  'model': model,
                  'messages': [
                    {'role': 'user', 'content': 'Hi'},
                  ],
                  'max_tokens': 1,
                }),
              );
            } else {
              resp = await _dio.post(
                endpoint,
                queryParameters: isDefaultGoogle ? {'key': key} : null,
                data: {
                  'contents': [
                    {
                      'parts': [
                        {'text': 'Hi'},
                      ],
                    },
                  ],
                  'generationConfig': {'maxOutputTokens': 1},
                },
                options: Options(
                  headers: {
                    if (!isDefaultGoogle) 'Authorization': 'Bearer $key',
                    if (!isDefaultGoogle) 'x-goog-api-key': key,
                  },
                  validateStatus: (s) => s != null && s < 600,
                  receiveTimeout: const Duration(seconds: 10),
                ),
              );
            }

            final code = resp.statusCode ?? 0;
            if (code == 200 || code == 429 || code == 503) {
              return true;
            }
          } catch (_) {
            continue;
          }
        }
        return false;
      }
      if (pid == 'openai' ||
          pid == 'deepseek' ||
          pid == 'groq' ||
          pid == 'openrouter' ||
          pid == 'grok' ||
          pid == 'together' ||
          pid == 'perplexity' ||
          pid == 'fireworks' ||
          pid == 'lmstudio' ||
          pid == 'local_edge') {
        final key = _settings.apiKeys[pid] ?? '';
        if (key.isEmpty && pid != 'lmstudio' && pid != 'local_edge') {
          return false;
        }
        final resp = await _executeOpenAiCompatRequest(
          pid,
          '/chat/completions',
          options: Options(
            validateStatus: (s) => s != null && s < 600,
            receiveTimeout: const Duration(seconds: 10),
          ),
          data: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': 'Hi'},
            ],
            'max_tokens': 1,
          }),
        );
        final code = resp.statusCode ?? 0;
        return code == 200 || code == 429 || code == 503;
      }
      // For other providers just assume available if key is set
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Генерация ответа ────────────────────────────────────────────────────

  Future<String> getCompletion(String prompt) async {
    switch (_settings.selectedProviderId) {
      case 'google':
        return await _geminiCompletion(prompt);
      case 'openai':
      case 'deepseek':
      case 'groq':
      case 'openrouter':
      case 'grok':
      case 'together':
      case 'perplexity':
      case 'fireworks':
      case 'kimi':
      case 'nvidia':
        return await _openAiCompatCompletion(prompt);
      case 'local_edge':
        if (_settings.selectedLocalEngine == LocalAiEngine.ollama) {
          return await _ollamaCompletion(prompt);
        }
        return await _openAiCompatCompletion(prompt);
      case 'anthropic':
        return await _anthropicCompletion(prompt);
      default:
        return 'Provider not supported.';
    }
  }

  Future<String> _geminiCompletion(String prompt) async {
    if (_geminiModel == null) {
      return 'Error: Set Gemini API key in settings.';
    }
    try {
      final response = await _geminiModel!.generateContent([
        Content.text(prompt),
      ]);
      return response.text ?? 'No response from AI';
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String> _openAiCompatCompletion(String prompt) async {
    final pid = _settings.selectedProviderId;
    final key = _settings.apiKeys[pid] ?? '';
    if (key.isEmpty && pid != 'local_edge') {
      return 'Error: Set API key in settings.';
    }
    try {
      final resp = await _executeOpenAiCompatRequest(
        pid,
        '/chat/completions',
        data: jsonEncode({
          'model': _settings.selectedModel,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 4096,
        }),
      );
      return resp.data?['choices']?[0]?['message']?['content']?.toString() ?? 'Error: Unexpected API response format';
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String> _anthropicCompletion(String prompt) async {
    final key = _settings.apiKeys['anthropic'] ?? '';
    if (key.isEmpty) {
      return 'Error: Set Anthropic API key in settings.';
    }
    try {
      final resp = await _dio.post(
        '${getBaseUrl('anthropic')}/messages',
        options: Options(
          headers: {
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode({
          'model': _settings.selectedModel,
          'max_tokens': 4096,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );
      return resp.data?['content']?[0]?['text']?.toString() ?? 'Error: Unexpected Anthropic response format';
    } catch (e) {
      return 'Anthropic Error: $e';
    }
  }

  Future<String> _ollamaCompletion(String prompt) async {
    final base = getBaseUrl('local_edge');
    try {
      final resp = await _dio.post(
        '$base/api/generate',
        options: Options(receiveTimeout: Duration.zero),
        data: jsonEncode({
          'model': _settings.selectedModel,
          'prompt': prompt,
          'stream': false,
        }),
      );
      return resp.data?['response']?.toString() ?? 'Error: Unexpected Ollama response format';
    } catch (e) {
      return 'Ollama Error (ensure Ollama is running): $e';
    }
  }

  // ─── Chat session (Gemini) ───────────────────────────────────────────────

  ChatSession? startChat({List<Content>? history}) {
    if (_geminiModel == null) return null;
    return _geminiModel!.startChat(history: history);
  }

  /// Отправить сообщение в чат (универсальный метод)
  Future<ChatResponse> sendChatMessage(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
    String? imageBase64,
  }) async {
    switch (_settings.selectedProviderId) {
      case 'google':
        return await _geminiChatMessage(
          message,
          history,
          systemInstruction: systemInstruction,
          imageBase64: imageBase64,
        );
      case 'openai':
      case 'deepseek':
      case 'groq':
      case 'openrouter':
      case 'grok':
      case 'together':
      case 'perplexity':
      case 'fireworks':
      case 'kimi':
      case 'nvidia':
        return await _openAiChatMessage(
          message,
          history,
          systemInstruction: systemInstruction,
          imageBase64: imageBase64,
        );
      case 'local_edge':
        if (_settings.selectedLocalEngine == LocalAiEngine.ollama) {
          return await _ollamaChatMessage(
            message,
            history,
            systemInstruction: systemInstruction,
          );
        }
        return await _openAiChatMessage(
          message,
          history,
          systemInstruction: systemInstruction,
          imageBase64: imageBase64,
        );
      case 'anthropic':
        return await _anthropicChatMessage(
          message,
          history,
          systemInstruction: systemInstruction,
          imageBase64: imageBase64,
        );
      default:
        final text = await getCompletion(message);
        return ChatResponse(text);
    }
  }

  /// Stream chat message - returns tokens one by one via onToken callback
  Future<ChatResponse> streamChatMessage(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
    void Function(String token)? onToken,
  }) async {
    final pid = _settings.selectedProviderId;
    
    // For OpenAI-compatible providers, use streaming
    if (pid == 'openai' || pid == 'deepseek' || pid == 'groq' || 
        pid == 'openrouter' || pid == 'grok' || pid == 'together' ||
        pid == 'perplexity' || pid == 'fireworks' ||
        pid == 'kimi' || pid == 'nvidia' ||
        pid == 'local_edge') {
      return await _streamOpenAICompatibleChat(
        message,
        history,
        systemInstruction: systemInstruction,
        onToken: onToken,
      );
    }
    
    // For other providers, fall back to non-streaming
    return await sendChatMessage(message, history, systemInstruction: systemInstruction);
  }

  Future<ChatResponse> _streamOpenAICompatibleChat(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
    void Function(String token)? onToken,
  }) async {
    final pid = _settings.selectedProviderId;
    try {
      final messages = [
        if (systemInstruction != null)
          {'role': 'system', 'content': systemInstruction},
        ...history.map((m) => {'role': m['role'], 'content': m['content']}),
        {'role': 'user', 'content': message},
      ];

      final key = _settings.apiKeys[pid] ?? '';
      final originalBaseUrl = getBaseUrl(pid);
      final cleansed = _cleanseBaseUrl(originalBaseUrl);
      
      String endpoint = '$cleansed/chat/completions';
      if (!cleansed.endsWith('/v1')) {
        endpoint = '$cleansed/v1/chat/completions';
      }

      // Retry logic for streaming
      for (int attempt = 0; attempt <= _maxRetries; attempt++) {
        try {
          final response = await _dio.post(
            endpoint,
            options: Options(
              headers: {
                'Content-Type': 'application/json',
                if (key.isNotEmpty) 'Authorization': 'Bearer $key',
                'Accept': 'text/event-stream',
              },
              responseType: ResponseType.stream,
              validateStatus: (s) => s != null && s < 600,
            ),
            data: jsonEncode({
              'model': _settings.selectedModel,
              'messages': messages,
              'max_tokens': 4096,
              'stream': true,
            }),
          );

          // Handle error status codes before streaming
          if (response.statusCode == 403) {
            return ChatResponse(
              '❌ **API key error (403 Forbidden)**\n\n'
              'Your API key for ${AiProviders.byId(pid).displayName} is invalid or expired.\n'
              'Please go to **AI Settings** and update your API key.',
            );
          }
          if (response.statusCode == 429 && attempt < _maxRetries) {
            final retryAfter = response.headers.value('retry-after');
            final delayMs = retryAfter != null
                ? (int.tryParse(retryAfter) ?? 1) * 1000
                : (1 << attempt) * 1000;
            await Future.delayed(Duration(milliseconds: delayMs));
            continue;
          }
          if (response.statusCode != null && response.statusCode! >= 500 && attempt < _maxRetries) {
            await Future.delayed(Duration(milliseconds: (1 << attempt) * 1000));
            continue;
          }

          final buffer = StringBuffer();
          final stream = response.data.stream;
          String lineBuffer = '';
          int promptTokens = 0;
          int completionTokens = 0;

          await for (final chunk in stream) {
            lineBuffer += utf8.decode(chunk);
            final lines = lineBuffer.split('\n');
            lineBuffer = lines.removeLast(); // Keep incomplete line in buffer

            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

              final payload = trimmed.substring(5).trim();
              if (payload == '[DONE]') break;

              try {
                final data = jsonDecode(payload);
                // Parse token usage from Ollama/llama-server streaming
                if (data.containsKey('prompt_eval_count')) {
                  promptTokens = data['prompt_eval_count'] as int? ?? 0;
                }
                if (data.containsKey('eval_count')) {
                  completionTokens = data['eval_count'] as int? ?? 0;
                }
                // Also handle OpenAI-style usage
                if (data.containsKey('usage') && data['usage'] is Map) {
                  final usage = data['usage'] as Map;
                  promptTokens = usage['prompt_tokens'] as int? ?? promptTokens;
                  completionTokens = usage['completion_tokens'] as int? ?? completionTokens;
                }
                final choice = (data['choices'] as List?)?.isNotEmpty == true
                    ? data['choices'][0] as Map
                    : null;
                final delta = choice?['delta'] as Map?;
                final token = delta?['content']?.toString();
                if (token != null && token.isNotEmpty) {
                  buffer.write(token);
                  onToken?.call(token);
                }
              } catch (_) {}
            }
          }

          return ChatResponse(
            buffer.toString(),
            tokenUsage: TokenUsage(
              promptTokens: promptTokens,
              completionTokens: completionTokens,
              totalTokens: promptTokens + completionTokens,
            ),
          );
        } on DioException catch (e) {
          if (attempt < _maxRetries && _isRetryableError(e)) {
            await Future.delayed(Duration(milliseconds: (1 << attempt) * 1000));
            continue;
          }
          if (e.response?.statusCode == 429) {
            return ChatResponse(
              '⏳ **Rate limit exceeded (429)**\n\n'
              'Too many requests to ${AiProviders.byId(pid).displayName}. '
              'Please wait a moment and try again.',
            );
          }
          return ChatResponse('Error: $e');
        }
      }

      return ChatResponse('Error: Failed after $_maxRetries retries');
    } catch (e) {
      return ChatResponse('Error: $e');
    }
  }

  Future<ChatResponse> _geminiChatMessage(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
    String? imageBase64,
  }) async {
    if (_geminiModel == null) return ChatResponse('Error: Set Gemini API key.');
    try {
      var model = _geminiModel!;
      if (systemInstruction != null) {
        final key = _settings.apiKeys['google'] ?? '';
        // Use standard GenerativeModel with systemInstruction.
        // Custom proxy URLs are handled via OpenAI-compatible Dio endpoint.
        model = GenerativeModel(
          model: _settings.selectedModel,
          apiKey: key,
          systemInstruction: Content.system(systemInstruction),
        );
      }
      
      // Build content with optional image
      final parts = <Part>[TextPart(message)];
      if (imageBase64 != null) {
        parts.insert(0, DataPart('image/jpeg', base64Decode(imageBase64)));
      }
      
      final geminiHistory = history
          .map(
            (m) => m['role'] == 'user'
                ? Content('user', [TextPart(m['content'] ?? '')])
                : Content.model([TextPart(m['content'] ?? '')]),
          )
          .toList();
      final session = model.startChat(history: geminiHistory);
      final resp = await session.sendMessage(Content('user', parts));
      final text = resp.text ?? 'No response';
      int promptTokens = 0;
      int completionTokens = 0;
      if (resp.usageMetadata != null) {
        promptTokens = resp.usageMetadata?.promptTokenCount ?? 0;
        completionTokens = resp.usageMetadata?.candidatesTokenCount ?? 0;
      }
      return ChatResponse(
        text,
        tokenUsage: TokenUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: promptTokens + completionTokens,
        ),
      );
    } catch (e) {
      return ChatResponse('Error: $e');
    }
  }

  Future<ChatResponse> _openAiChatMessage(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
    String? imageBase64,
  }) async {
    final pid = _settings.selectedProviderId;
    try {
      // Build user message with optional image
      dynamic userContent;
      if (imageBase64 != null) {
        userContent = [
          {'type': 'text', 'text': message},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$imageBase64'}
          },
        ];
      } else {
        userContent = message;
      }

      final messages = [
        if (systemInstruction != null)
          {'role': 'system', 'content': systemInstruction},
        ...history.map((m) => {'role': m['role'], 'content': m['content']}),
        {'role': 'user', 'content': userContent},
      ];
      final resp = await _executeOpenAiCompatRequest(
        pid,
        '/chat/completions',
        data: jsonEncode({
          'model': _settings.selectedModel,
          'messages': messages,
          'max_tokens': 4096,
        }),
      );
      final text = resp.data?['choices']?[0]?['message']?['content']?.toString() ?? 'Error: Unexpected API response format';
      int promptTokens = 0;
      int completionTokens = 0;
      if (resp.data?['usage'] is Map) {
        final usage = resp.data['usage'] as Map;
        promptTokens = usage['prompt_tokens'] as int? ?? 0;
        completionTokens = usage['completion_tokens'] as int? ?? 0;
      }
      return ChatResponse(
        text,
        tokenUsage: TokenUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: promptTokens + completionTokens,
        ),
      );
    } on Exception catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('403')) {
        return ChatResponse(
          '❌ **API key error (403 Forbidden)**\n\n'
          'Your API key for ${AiProviders.byId(pid).displayName} is invalid or expired.\n'
          'Please go to **AI Settings** and update your API key.',
        );
      }
      if (errorStr.contains('429')) {
        return ChatResponse(
          '⏳ **Rate limit exceeded (429)**\n\n'
          'Too many requests to ${AiProviders.byId(pid).displayName}. '
          'Please wait a moment and try again.',
        );
      }
      if (errorStr.contains('connection') || errorStr.contains('SocketException')) {
        return ChatResponse(
          '🔌 **Connection error**\n\n'
          'Could not connect to ${AiProviders.byId(pid).displayName}. '
          'Check your internet connection and try again.',
        );
      }
      return ChatResponse('Error: $e');
    }
  }

  Future<ChatResponse> _anthropicChatMessage(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
    String? imageBase64,
  }) async {
    final key = _settings.apiKeys['anthropic'] ?? '';
    if (key.isEmpty) return ChatResponse('Error: Set Anthropic API key.');
    try {
      // Build user content with optional image
      dynamic userContent;
      if (imageBase64 != null) {
        userContent = [
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': 'image/jpeg',
              'data': imageBase64,
            }
          },
          {'type': 'text', 'text': message},
        ];
      } else {
        userContent = message;
      }

      final messages = [
        ...history.map((m) => {'role': m['role'], 'content': m['content']}),
        {'role': 'user', 'content': userContent},
      ];
      final Map<String, dynamic> payload = {
        'model': _settings.selectedModel,
        'max_tokens': 4096,
        'messages': messages,
      };
      if (systemInstruction != null) {
        payload['system'] = systemInstruction;
      }
      final resp = await _dio.post(
        '${getBaseUrl('anthropic')}/messages',
        options: Options(
          headers: {
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ),
        data: jsonEncode(payload),
      );
      final text = resp.data?['content']?[0]?['text']?.toString() ?? 'Error: Unexpected Anthropic response format';
      int promptTokens = 0;
      int completionTokens = 0;
      if (resp.data?['usage'] is Map) {
        final usage = resp.data['usage'] as Map;
        promptTokens = usage['input_tokens'] as int? ?? 0;
        completionTokens = usage['output_tokens'] as int? ?? 0;
      }
      return ChatResponse(
        text,
        tokenUsage: TokenUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: promptTokens + completionTokens,
        ),
      );
    } catch (e) {
      return ChatResponse('Anthropic Error: $e');
    }
  }

  Future<ChatResponse> _ollamaChatMessage(
    String message,
    List<Map<String, String>> history, {
    String? systemInstruction,
  }) async {
    final base = getBaseUrl('local_edge');
    try {
      final messages = [
        if (systemInstruction != null)
          {'role': 'system', 'content': systemInstruction},
        ...history.map((m) => {'role': m['role'], 'content': m['content']}),
        {'role': 'user', 'content': message},
      ];
      final resp = await _dio.post(
        '$base/api/chat',
        options: Options(receiveTimeout: Duration.zero),
        data: jsonEncode({
          'model': _settings.selectedModel,
          'messages': messages,
          'stream': false,
        }),
      );
      final text = resp.data?['message']?['content']?.toString() ?? 'Error: Unexpected Ollama response format';
      final promptTokens = resp.data?['prompt_eval_count'] as int? ?? 0;
      final completionTokens = resp.data?['eval_count'] as int? ?? 0;
      return ChatResponse(
        text,
        tokenUsage: TokenUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: promptTokens + completionTokens,
        ),
      );
    } catch (e) {
      return ChatResponse('Ollama Error: $e');
    }
  }
}

final aiServiceProvider = Provider<AIService>((ref) => AIService());
