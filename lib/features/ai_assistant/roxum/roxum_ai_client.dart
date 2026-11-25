// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:http/http.dart' as http;
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/token_counter_service.dart';

enum RoxumToolCallingMethod {
  openAiCompatible,
  anthropicMessages,
  geminiFunctionCalling,
}

class RoxumModelOption {
  final String id;
  final String name;
  final String provider;
  final String url;
  final String apiKey;
  final String model;
  final RoxumToolCallingMethod method;
  final bool isFree;

  const RoxumModelOption({
    required this.id,
    required this.name,
    required this.provider,
    required this.url,
    required this.apiKey,
    required this.model,
    required this.method,
    this.isFree = false,
  });

  static String normalizeOpenAiBaseUrl(String raw) {
    var base = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return '';
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    } else if (base.endsWith('/models')) {
      base = base.substring(0, base.length - '/models'.length);
    }
    base = base.replaceAll(RegExp(r'/+$'), '');
    if (!RegExp(r'/v\d+(beta\d*)?$|/api/v\d+$').hasMatch(base)) {
      base = '$base/v1';
    }
    return base;
  }

  Map<String, String> get headers {
    switch (method) {
      case RoxumToolCallingMethod.anthropicMessages:
        return {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        };
      case RoxumToolCallingMethod.geminiFunctionCalling:
        return {'Content-Type': 'application/json'};
      case RoxumToolCallingMethod.openAiCompatible:
        final isOpenRouter = url.contains('openrouter.ai');
        return {
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          if (isOpenRouter)
            'HTTP-Referer': 'https://github.com/Lesorub361/quantum_ide',
          if (isOpenRouter) 'X-Title': 'Quantum IDE',
        };
    }
  }

  static List<RoxumModelOption> fromSettings(SettingsState settings) {
    final list = <RoxumModelOption>[];
    if (settings.geminiApiKey.trim().isNotEmpty) {
      final m = settings.geminiModel.isNotEmpty
          ? settings.geminiModel
          : 'gemini-2.5-flash';
      list.add(
        RoxumModelOption(
          id: 'gemini:$m',
          name: m,
          provider: 'Gemini',
          url:
              'https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent?key=${settings.geminiApiKey.trim()}',
          apiKey: settings.geminiApiKey.trim(),
          model: m,
          method: RoxumToolCallingMethod.geminiFunctionCalling,
        ),
      );
    }
    if (settings.deepseekApiKey.trim().isNotEmpty) {
      for (final m in ['deepseek-chat', 'deepseek-reasoner']) {
        list.add(
          RoxumModelOption(
            id: 'deepseek:$m',
            name: m,
            provider: 'DeepSeek',
            url: 'https://api.deepseek.com/chat/completions',
            apiKey: settings.deepseekApiKey.trim(),
            model: m,
            method: RoxumToolCallingMethod.openAiCompatible,
          ),
        );
      }
    }
    if (settings.openaiApiKey.trim().isNotEmpty) {
      for (final m in ['gpt-4o', 'gpt-4o-mini', 'o3-mini']) {
        list.add(
          RoxumModelOption(
            id: 'openai:$m',
            name: m,
            provider: 'OpenAI',
            url: 'https://api.openai.com/v1/chat/completions',
            apiKey: settings.openaiApiKey.trim(),
            model: m,
            method: RoxumToolCallingMethod.openAiCompatible,
          ),
        );
      }
    }
    if (settings.anthropicApiKey.trim().isNotEmpty) {
      for (final m in ['claude-sonnet-4-20250514', 'claude-3-5-haiku-latest']) {
        list.add(
          RoxumModelOption(
            id: 'anthropic:$m',
            name: m,
            provider: 'Anthropic',
            url: 'https://api.anthropic.com/v1/messages',
            apiKey: settings.anthropicApiKey.trim(),
            model: m,
            method: RoxumToolCallingMethod.anthropicMessages,
          ),
        );
      }
    }
    if (settings.openrouterApiKey.trim().isNotEmpty) {
      for (final m in [
        ('qwen/qwen3-coder:free', true),
        ('deepseek/deepseek-chat-v3-0324:free', true),
        ('meta-llama/llama-3.3-70b-instruct:free', true),
        ('qwen/qwen-2.5-coder-32b-instruct', false),
        ('anthropic/claude-3.5-sonnet', false),
        ('google/gemini-2.5-flash', false),
      ]) {
        list.add(
          RoxumModelOption(
            id: 'openrouter:${m.$1}',
            name: m.$1,
            provider: 'OpenRouter',
            url: 'https://openrouter.ai/api/v1/chat/completions',
            apiKey: settings.openrouterApiKey.trim(),
            model: m.$1,
            method: RoxumToolCallingMethod.openAiCompatible,
            isFree: m.$2,
          ),
        );
      }
    }
    if (settings.groqApiKey.trim().isNotEmpty) {
      list.add(
        RoxumModelOption(
          id: 'groq:llama-3.3-70b-versatile',
          name: 'llama-3.3-70b-versatile',
          provider: 'Groq',
          url: 'https://api.groq.com/openai/v1/chat/completions',
          apiKey: settings.groqApiKey.trim(),
          model: 'llama-3.3-70b-versatile',
          method: RoxumToolCallingMethod.openAiCompatible,
        ),
      );
    }
    if (settings.xaiApiKey.trim().isNotEmpty) {
      list.add(
        RoxumModelOption(
          id: 'xai:grok-2-latest',
          name: 'grok-2-latest',
          provider: 'xAI',
          url: 'https://api.x.ai/v1/chat/completions',
          apiKey: settings.xaiApiKey.trim(),
          model: 'grok-2-latest',
          method: RoxumToolCallingMethod.openAiCompatible,
        ),
      );
    }
    if (settings.mistralApiKey.trim().isNotEmpty) {
      list.add(
        RoxumModelOption(
          id: 'mistral:codestral-latest',
          name: 'codestral-latest',
          provider: 'Mistral',
          url: 'https://api.mistral.ai/v1/chat/completions',
          apiKey: settings.mistralApiKey.trim(),
          model: 'codestral-latest',
          method: RoxumToolCallingMethod.openAiCompatible,
        ),
      );
    }
    if (settings.customApiBaseUrl.trim().isNotEmpty &&
        settings.customApiModel.trim().isNotEmpty) {
      final base = normalizeOpenAiBaseUrl(settings.customApiBaseUrl);
      list.add(
        RoxumModelOption(
          id: 'custom:${settings.customApiModel.trim()}',
          name: settings.customApiModel.trim(),
          provider: 'Local / Custom',
          url: '$base/chat/completions',
          apiKey: settings.customApiKey.trim(),
          model: settings.customApiModel.trim(),
          method: RoxumToolCallingMethod.openAiCompatible,
          isFree: true,
        ),
      );
    }
    return list;
  }
}

class RoxumToolCallRecord {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final bool isRunning;
  final bool success;
  final String output;

  const RoxumToolCallRecord({
    required this.id,
    required this.name,
    required this.arguments,
    this.isRunning = true,
    this.success = true,
    this.output = '',
  });

  RoxumToolCallRecord copyWith({
    bool? isRunning,
    bool? success,
    String? output,
  }) {
    return RoxumToolCallRecord(
      id: id,
      name: name,
      arguments: arguments,
      isRunning: isRunning ?? this.isRunning,
      success: success ?? this.success,
      output: output ?? this.output,
    );
  }
}

class RoxumAttachment {
  final String name;
  final String mimeType;
  final String? base64Data;
  final String? textContent;
  final int sizeBytes;

  const RoxumAttachment({
    required this.name,
    required this.mimeType,
    this.base64Data,
    this.textContent,
    this.sizeBytes = 0,
  });

  bool get isImage => mimeType.startsWith('image/') && base64Data != null;
}

class RoxumUsageStats {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final double costUsd;

  const RoxumUsageStats({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.costUsd = 0.0,
  });

  RoxumUsageStats operator +(RoxumUsageStats other) {
    return RoxumUsageStats(
      promptTokens: promptTokens + other.promptTokens,
      completionTokens: completionTokens + other.completionTokens,
      totalTokens: totalTokens + other.totalTokens,
      costUsd: costUsd + other.costUsd,
    );
  }
}

class OpenRouterKeyLimits {
  final String label;
  final double? limitUsd;
  final double? limitRemainingUsd;
  final double usageUsd;
  final double usageDailyUsd;
  final double usageMonthlyUsd;
  final bool isFreeTier;
  final int? freeDailyUsed;
  final int? freeDailyLimit;
  final int? freeDailyRemaining;

  const OpenRouterKeyLimits({
    required this.label,
    this.limitUsd,
    this.limitRemainingUsd,
    this.usageUsd = 0.0,
    this.usageDailyUsd = 0.0,
    this.usageMonthlyUsd = 0.0,
    this.isFreeTier = false,
    this.freeDailyUsed,
    this.freeDailyLimit,
    this.freeDailyRemaining,
  });
}

class _ParsedTurn {
  final String text;
  final String reasoning;
  final List<({String id, String name, Map<String, dynamic> args})> toolCalls;
  final Map<String, dynamic> rawAssistantMessage;
  final RoxumUsageStats usage;
  final String? finishReason;

  const _ParsedTurn({
    required this.text,
    this.reasoning = '',
    required this.toolCalls,
    required this.rawAssistantMessage,
    this.usage = const RoxumUsageStats(),
    this.finishReason,
  });
}

/// Public result of a single provider turn for the new PocketStrike-style
/// [AgentEngine]. Kept separate from the private [_ParsedTurn] so the engine
/// does not depend on this file's internals.
class RoxumAgentTurn {
  const RoxumAgentTurn({
    required this.text,
    this.reasoning = '',
    this.toolCalls = const [],
  });

  final String text;
  final String reasoning;
  final List<({String id, String name, Map<String, dynamic> args})> toolCalls;
}

class RoxumAiClient {
  http.Client? _client;

  static final Dio _retryDio = _createRetryDio();

  static Dio _createRetryDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 7),
        receiveTimeout: const Duration(seconds: 10),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        retries: 2,
        retryDelays: const [Duration(milliseconds: 450), Duration(seconds: 1)],
      ),
    );
    return dio;
  }

  void cancel() {
    _client?.close();
    _client = null;
  }

  static Future<List<String>> fetchRemoteModels({
    required String baseUrl,
    String apiKey = '',
  }) async {
    final raw = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (raw.isEmpty) return const [];
    final normalized = RoxumModelOption.normalizeOpenAiBaseUrl(raw);
    final rawClean = raw.endsWith('/models')
        ? raw
        : (raw.endsWith('/chat/completions')
              ? '${raw.substring(0, raw.length - '/chat/completions'.length)}/models'
              : '$raw/models');
    final rootBase = normalized.endsWith('/v1')
        ? normalized.substring(0, normalized.length - 3)
        : normalized;

    final candidates = <String>{
      '$normalized/models',
      rawClean,
      if (rootBase.isNotEmpty) '$rootBase/api/tags',
    }.toList();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
    };

    Object? lastError;
    for (final url in candidates) {
      try {
        final res = await _retryDio.get<dynamic>(
          url,
          options: Options(headers: headers),
        );
        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300) {
          lastError = Exception('HTTP $status ($url)');
          continue;
        }
        final decoded = res.data is String
            ? jsonDecode(res.data as String)
            : res.data;
        final ids = <String>[];
        if (decoded is Map && decoded['data'] is List) {
          for (final item in decoded['data'] as List) {
            if (item is Map && item['id'] != null) {
              ids.add(item['id'].toString());
            }
          }
        } else if (decoded is Map && decoded['models'] is List) {
          for (final item in decoded['models'] as List) {
            if (item is Map && (item['name'] ?? item['id']) != null) {
              ids.add((item['name'] ?? item['id']).toString());
            }
          }
        }
        if (ids.isNotEmpty) return ids;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }

  static Future<List<RoxumModelOption>> fetchAllProviderModels(
    SettingsState settings,
  ) async {
    final futures = <Future<List<RoxumModelOption>>>[];

    Future<List<RoxumModelOption>> fetchOpenAiStyle({
      required String provider,
      required String modelsUrl,
      required String chatUrl,
      required String apiKey,
      bool Function(String id)? filter,
      bool defaultFree = false,
    }) async {
      try {
        final res = await _retryDio.get<dynamic>(
          modelsUrl,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            },
          ),
        );
        final status = res.statusCode ?? 0;
        if (status < 200 || status >= 300) return const [];
        final decoded = res.data is String
            ? jsonDecode(res.data as String)
            : res.data;
        if (decoded is! Map || decoded['data'] is! List) return const [];
        final out = <RoxumModelOption>[];
        for (final item in decoded['data'] as List) {
          if (item is! Map || item['id'] == null) continue;
          final id = item['id'].toString();
          if (filter != null && !filter(id)) continue;
          final pricing = item['pricing'];
          final isFree =
              defaultFree ||
              id.contains(':free') ||
              (pricing is Map && pricing['prompt']?.toString() == '0');
          out.add(
            RoxumModelOption(
              id: '${provider.toLowerCase()}:$id',
              name: item['name']?.toString() ?? id,
              provider: provider,
              url: chatUrl,
              apiKey: apiKey,
              model: id,
              method: RoxumToolCallingMethod.openAiCompatible,
              isFree: isFree,
            ),
          );
        }
        return out;
      } catch (_) {
        return const [];
      }
    }

    if (settings.openrouterApiKey.trim().isNotEmpty) {
      int codingRank(String modelId) {
        final m = modelId.toLowerCase();
        if (m.contains('qwen3-coder') || m.contains('qwen-2.5-coder')) return 0;
        if (m.contains('claude-sonnet') || m.contains('claude-3.7') || m.contains('claude-3.5')) return 1;
        if (m.contains('deepseek-chat') || m.contains('deepseek-v3')) return 2;
        if (m.contains('gemini-2.5') || m.contains('gemini-2.0')) return 3;
        if (m.contains('codestral') || m.contains('devstral') || m.contains('gpt-4o') || m.contains('gpt-4.1')) return 4;
        if (m.contains('llama-3.3-70b') || m.contains('qwen3') || m.contains('deepseek-r1')) return 5;
        if (m.contains('preview') || m.contains('ernie') || m.contains('nemotron') || m.contains('vl')) return 9;
        return 7;
      }

      futures.add(
        fetchOpenAiStyle(
          provider: 'OpenRouter',
          modelsUrl: 'https://openrouter.ai/api/v1/models',
          chatUrl: 'https://openrouter.ai/api/v1/chat/completions',
          apiKey: settings.openrouterApiKey.trim(),
        ).then((list) {
          list.sort((a, b) {
            if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
            final ra = codingRank(a.model);
            final rb = codingRank(b.model);
            if (ra != rb) return ra.compareTo(rb);
            return a.model.compareTo(b.model);
          });
          return list;
        }),
      );
    }

    if (settings.customApiBaseUrl.trim().isNotEmpty) {
      futures.add(() async {
        try {
          final base = RoxumModelOption.normalizeOpenAiBaseUrl(
            settings.customApiBaseUrl,
          );
          final ids = await fetchRemoteModels(
            baseUrl: settings.customApiBaseUrl,
            apiKey: settings.customApiKey.trim(),
          );
          return ids
              .map(
                (id) => RoxumModelOption(
                  id: 'custom:$id',
                  name: id,
                  provider: 'Local / Custom',
                  url: '$base/chat/completions',
                  apiKey: settings.customApiKey.trim(),
                  model: id,
                  method: RoxumToolCallingMethod.openAiCompatible,
                  isFree: true,
                ),
              )
              .toList();
        } catch (_) {
          return const <RoxumModelOption>[];
        }
      }());
    }

    if (settings.geminiApiKey.trim().isNotEmpty) {
      futures.add(() async {
        final key = settings.geminiApiKey.trim();
        try {
          final res = await http
              .get(
                Uri.parse(
                  'https://generativelanguage.googleapis.com/v1beta/models?key=$key',
                ),
              )
              .timeout(const Duration(seconds: 7));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            return const <RoxumModelOption>[];
          }
          final decoded = jsonDecode(res.body);
          if (decoded is! Map || decoded['models'] is! List) {
            return const <RoxumModelOption>[];
          }
          final out = <RoxumModelOption>[];
          for (final m in decoded['models'] as List) {
            if (m is! Map) continue;
            final methods =
                (m['supportedGenerationMethods'] as List?) ?? const [];
            if (!methods.contains('generateContent')) continue;
            var id = m['name']?.toString() ?? '';
            if (id.startsWith('models/')) id = id.substring(7);
            if (id.isEmpty) continue;
            out.add(
              RoxumModelOption(
                id: 'gemini:$id',
                name: m['displayName']?.toString() ?? id,
                provider: 'Gemini',
                url:
                    'https://generativelanguage.googleapis.com/v1beta/models/$id:generateContent?key=$key',
                apiKey: key,
                model: id,
                method: RoxumToolCallingMethod.geminiFunctionCalling,
                isFree: id.contains('flash'),
              ),
            );
          }
          return out;
        } catch (_) {
          return const <RoxumModelOption>[];
        }
      }());
    }

    if (settings.deepseekApiKey.trim().isNotEmpty) {
      futures.add(
        fetchOpenAiStyle(
          provider: 'DeepSeek',
          modelsUrl: 'https://api.deepseek.com/models',
          chatUrl: 'https://api.deepseek.com/chat/completions',
          apiKey: settings.deepseekApiKey.trim(),
        ),
      );
    }

    if (settings.openaiApiKey.trim().isNotEmpty) {
      futures.add(
        fetchOpenAiStyle(
          provider: 'OpenAI',
          modelsUrl: 'https://api.openai.com/v1/models',
          chatUrl: 'https://api.openai.com/v1/chat/completions',
          apiKey: settings.openaiApiKey.trim(),
          filter: (id) =>
              id.startsWith('gpt-') ||
              id.startsWith('o1') ||
              id.startsWith('o3') ||
              id.startsWith('o4') ||
              id.startsWith('chatgpt'),
        ),
      );
    }

    if (settings.anthropicApiKey.trim().isNotEmpty) {
      futures.add(() async {
        final key = settings.anthropicApiKey.trim();
        try {
          final res = await http
              .get(
                Uri.parse('https://api.anthropic.com/v1/models'),
                headers: {'x-api-key': key, 'anthropic-version': '2023-06-01'},
              )
              .timeout(const Duration(seconds: 7));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            return const <RoxumModelOption>[];
          }
          final decoded = jsonDecode(res.body);
          if (decoded is! Map || decoded['data'] is! List) {
            return const <RoxumModelOption>[];
          }
          return (decoded['data'] as List)
              .whereType<Map>()
              .where((m) => m['id'] != null)
              .map(
                (m) => RoxumModelOption(
                  id: 'anthropic:${m['id']}',
                  name: m['display_name']?.toString() ?? m['id'].toString(),
                  provider: 'Anthropic',
                  url: 'https://api.anthropic.com/v1/messages',
                  apiKey: key,
                  model: m['id'].toString(),
                  method: RoxumToolCallingMethod.anthropicMessages,
                ),
              )
              .toList();
        } catch (_) {
          return const <RoxumModelOption>[];
        }
      }());
    }

    if (settings.groqApiKey.trim().isNotEmpty) {
      futures.add(
        fetchOpenAiStyle(
          provider: 'Groq',
          modelsUrl: 'https://api.groq.com/openai/v1/models',
          chatUrl: 'https://api.groq.com/openai/v1/chat/completions',
          apiKey: settings.groqApiKey.trim(),
          defaultFree: true,
        ),
      );
    }

    if (settings.xaiApiKey.trim().isNotEmpty) {
      futures.add(
        fetchOpenAiStyle(
          provider: 'xAI',
          modelsUrl: 'https://api.x.ai/v1/models',
          chatUrl: 'https://api.x.ai/v1/chat/completions',
          apiKey: settings.xaiApiKey.trim(),
        ),
      );
    }

    if (settings.mistralApiKey.trim().isNotEmpty) {
      futures.add(
        fetchOpenAiStyle(
          provider: 'Mistral',
          modelsUrl: 'https://api.mistral.ai/v1/models',
          chatUrl: 'https://api.mistral.ai/v1/chat/completions',
          apiKey: settings.mistralApiKey.trim(),
        ),
      );
    }

    if (futures.isEmpty) return const [];
    final results = await Future.wait(futures);
    return results.expand((e) => e).toList();
  }

  static Future<OpenRouterKeyLimits> fetchOpenRouterKeyLimits(
    String apiKey,
  ) async {
    final res = await http
        .get(
          Uri.parse('https://openrouter.ai/api/v1/key'),
          headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (decoded['data'] as Map?)?.cast<String, dynamic>() ?? decoded;
    final freeDaily = (data['free_model_daily_requests'] as Map?)
        ?.cast<String, dynamic>();
    return OpenRouterKeyLimits(
      label: data['label']?.toString() ?? 'OpenRouter Key',
      limitUsd: (data['limit'] as num?)?.toDouble(),
      limitRemainingUsd: (data['limit_remaining'] as num?)?.toDouble(),
      usageUsd: (data['usage'] as num?)?.toDouble() ?? 0.0,
      usageDailyUsd: (data['usage_daily'] as num?)?.toDouble() ?? 0.0,
      usageMonthlyUsd: (data['usage_monthly'] as num?)?.toDouble() ?? 0.0,
      isFreeTier: data['is_free_tier'] == true,
      freeDailyUsed: (freeDaily?['used'] as num?)?.toInt(),
      freeDailyLimit: (freeDaily?['limit'] as num?)?.toInt(),
      freeDailyRemaining: (freeDaily?['remaining'] as num?)?.toInt(),
    );
  }

  /// One clean provider turn for the new ReAct engine.
  ///
  /// Only performs one request/stream and returns the parsed result. The ReAct
  /// loop itself lives in PocketStrike's AgentEngine.
  Future<RoxumAgentTurn> streamTurnForAgent({
    required RoxumModelOption model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> toolSpecs,
    required void Function(String text) onText,
    required void Function(String reasoning) onReasoning,
    required bool Function() isCancelled,
  }) async {
    _client?.close();
    final client = http.Client();
    _client = client;

    final payload = _buildPayload(
      model: model,
      messages: messages,
      tools: toolSpecs,
    );

    late final _ParsedTurn turn;
    if (model.method == RoxumToolCallingMethod.openAiCompatible) {
      turn = await _sendOpenAiStreaming(
        client: client,
        model: model,
        payload: payload,
        onAssistantText: onText,
        onReasoningText: onReasoning,
        isCancelled: isCancelled,
      );
    } else {
      final res = await client
          .post(Uri.parse(model.url), headers: model.headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 120));
      if (isCancelled() || res.statusCode < 200 || res.statusCode >= 300) {
        return const RoxumAgentTurn(text: '');
      }
      turn = _parseResponse(model.method, jsonDecode(res.body) as Map<String, dynamic>);
    }

    return RoxumAgentTurn(
      text: turn.text,
      reasoning: turn.reasoning,
      toolCalls: turn.toolCalls,
    );
  }

  _ParsedTurn _withEstimatedUsage(
    _ParsedTurn turn,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) {
    final prompt = TokenCounterService.countTokens(
      jsonEncode({'messages': messages, 'tools': tools}),
    );
    final completion = TokenCounterService.countTokens(
      '${turn.text}\n${turn.reasoning}\n${jsonEncode(turn.toolCalls.map((e) => e.args).toList())}',
    );
    return _ParsedTurn(
      text: turn.text,
      reasoning: turn.reasoning,
      toolCalls: turn.toolCalls,
      rawAssistantMessage: turn.rawAssistantMessage,
      usage: RoxumUsageStats(
        promptTokens: prompt,
        completionTokens: completion,
        totalTokens: prompt + completion,
      ),
      finishReason: turn.finishReason,
    );
  }

  /// Compacts older tool outputs and superseded/older `writeFile` arguments in
  /// assistant messages so multi-step agent loops do not re-send huge file
  /// contents on every subsequent turn while ALWAYS keeping the latest
  /// compiler diagnostics intact.
  void _compactMessagesForTokenSavings(List<Map<String, dynamic>> messages) {
    compactMessagesForTokenSavings(messages);
  }

  static bool _isDiagnosticsToolMessage(Map<String, dynamic> msg) {
    if (msg['role'] != 'tool') return false;
    final name = msg['name']?.toString() ?? '';
    if (name == 'mcp__quantum_token_saver__smart_analyze_errors' ||
        name == 'getLspDiagnostics' ||
        name == 'diagnostics') {
      return true;
    }
    final content = msg['content']?.toString() ?? '';
    return content.contains('[Diagnostics for ') ||
        (content.contains('Summary:') && content.contains('error(s)'));
  }

  /// Public testable compactor that replaces old `tool` outputs and old or
  /// superseded `writeFile`/`createFile` `arguments.content` fields inside
  /// `assistant` messages without mutating caller-owned nested maps.
  static void compactMessagesForTokenSavings(
    List<Map<String, dynamic>> messages,
  ) {
    // 1. Track latest writeFile/createFile index per filePath so superseded
    // writes are compacted immediately even within the recent window.
    final latestWriteByPath = <String, int>{};
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (msg['role'] != 'assistant') continue;
      final toolCalls = msg['tool_calls'];
      if (toolCalls is! List) continue;
      for (final tc in toolCalls) {
        if (tc is! Map) continue;
        final fn = tc['function'];
        if (fn is! Map) continue;
        final name = fn['name']?.toString() ?? '';
        if (name != 'writeFile' && name != 'createFile' && name != 'write') {
          continue;
        }
        final parsed = _tryDecodeArgsMap(fn['arguments']);
        final path =
            (parsed?['filePath'] ?? parsed?['path'])?.toString().trim() ?? '';
        if (path.isNotEmpty) {
          latestWriteByPath[path] = i;
        }
      }
    }

    // Compact assistant writeFile arguments older than the last 2 agent steps
    // (roughly 4 messages) OR already superseded by a later write to the same file.
    final assistantCutoff = messages.length - 4;
    for (int i = 1; i < messages.length; i++) {
      final msg = messages[i];
      if (msg['role'] != 'assistant') continue;
      final toolCalls = msg['tool_calls'];
      if (toolCalls is! List || toolCalls.isEmpty) continue;

      var changed = false;
      final newToolCalls = <dynamic>[];
      for (final tc in toolCalls) {
        if (tc is! Map) {
          newToolCalls.add(tc);
          continue;
        }
        final fn = tc['function'];
        if (fn is! Map) {
          newToolCalls.add(tc);
          continue;
        }
        final name = fn['name']?.toString() ?? '';
        if (name != 'writeFile' && name != 'createFile' && name != 'write') {
          newToolCalls.add(tc);
          continue;
        }
        final parsed = _tryDecodeArgsMap(fn['arguments']);
        if (parsed == null) {
          newToolCalls.add(tc);
          continue;
        }
        final content = parsed['content']?.toString() ?? '';
        final path =
            (parsed['filePath'] ?? parsed['path'])?.toString().trim() ?? '';
        final isSuperseded =
            path.isNotEmpty && (latestWriteByPath[path] ?? i) > i;
        final isOld = i < assistantCutoff;
        if ((isOld || isSuperseded) &&
            content.length > 200 &&
            !content.startsWith('[compacted writeFile content:')) {
          final lineCount = content.split('\n').length;
          final reason = isSuperseded
              ? 'superseded by later edit'
              : 'already on disk';
          final compactedArgs = Map<String, dynamic>.from(parsed)
            ..['content'] =
                '[compacted writeFile content: $lineCount lines — $reason]';
          final newFn = Map<String, dynamic>.from(fn)
            ..['arguments'] = fn['arguments'] is String
                ? jsonEncode(compactedArgs)
                : compactedArgs;
          final newTc = Map<String, dynamic>.from(tc)..['function'] = newFn;
          newToolCalls.add(newTc);
          changed = true;
        } else {
          newToolCalls.add(tc);
        }
      }
      if (changed) {
        messages[i] = {...msg, 'tool_calls': newToolCalls};
      }
    }

    // 2. Locate the MOST RECENT diagnostics tool message so we NEVER truncate
    // active compiler errors, while collapsing older superseded diagnostics so
    // the model never chases stale fixed bugs!
    var latestDiagIdx = -1;
    for (int i = messages.length - 1; i >= 1; i--) {
      if (_isDiagnosticsToolMessage(messages[i])) {
        latestDiagIdx = i;
        break;
      }
    }
    if (latestDiagIdx > 1) {
      for (int i = 1; i < latestDiagIdx; i++) {
        final msg = messages[i];
        if (_isDiagnosticsToolMessage(msg)) {
          final content = msg['content']?.toString() ?? '';
          if (!content.contains('[superseded diagnostics')) {
            messages[i] = {
              ...msg,
              'content': jsonEncode({
                'success': true,
                'output':
                    '[superseded diagnostics — see latest analyzer output in recent messages]',
              }),
            };
          }
        }
      }
    }

    // 3. Aggressively compact large `readFile` / `readFilesBatch` outputs older
    // than 2 steps (4 messages) so huge 900-line reads don't burn 250k+ tokens.
    final readCutoff = messages.length - 4;
    for (int i = 1; i < readCutoff; i++) {
      if (i == latestDiagIdx) continue;
      final msg = messages[i];
      if (msg['role'] != 'tool') continue;
      final name = msg['name']?.toString() ?? '';
      final isReadTool =
          name == 'readFile' ||
          name == 'read' ||
          name == 'read_file' ||
          name == 'readFilesBatch';
      if (!isReadTool) continue;
      final content = msg['content']?.toString() ?? '';
      if (content.length > 3000 &&
          !content.contains('[compacted readFile:') &&
          !content.contains('[compacted tool output:')) {
        final headerMatch = RegExp(r'\[File:[^\]]+\]').firstMatch(content);
        final label = headerMatch?.group(0) ?? name;
        messages[i] = {
          ...msg,
          'content': jsonEncode({
            'success': true,
            'output':
                '$label — [compacted readFile: ${content.length} chars already inspected; re-read a specific startLine/endLine range if needed]',
          }),
        };
      }
    }

    // 4. Compact other older `role: tool` outputs beyond the most recent 6 messages,
    // EXCEPT `latestDiagIdx` which always stays intact.
    if (messages.length <= 8) return;
    final cutoff = messages.length - 6;
    for (int i = 1; i < cutoff; i++) {
      if (i == latestDiagIdx) continue;
      final msg = messages[i];
      if (msg['role'] == 'tool') {
        final content = msg['content']?.toString() ?? '';
        if (content.length > 1400 &&
            !content.contains('[compacted tool output:') &&
            !content.contains('[compacted readFile:') &&
            !content.contains('[superseded diagnostics')) {
          final head = content.substring(0, 700);
          final tail = content.substring(content.length - 300);
          messages[i] = {
            ...msg,
            'content':
                '$head\n...[compacted tool output: ${content.length} chars total to save tokens]...\n$tail',
          };
        }
      }
    }
  }

  static Map<String, dynamic>? _tryDecodeArgsMap(dynamic rawArgs) {
    if (rawArgs is Map<String, dynamic>) return rawArgs;
    if (rawArgs is Map) return Map<String, dynamic>.from(rawArgs);
    if (rawArgs is String && rawArgs.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(rawArgs);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static int _countAnalyzerErrors(String output) {
    if (output.trim().isEmpty) return 0;
    final summaryMatch = RegExp(
      r'Summary:\s*(\d+)\s+error\(s\)',
      caseSensitive: false,
    ).firstMatch(output);
    if (summaryMatch != null) {
      return int.tryParse(summaryMatch.group(1) ?? '0') ?? 0;
    }
    var count = 0;
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t.startsWith('error •') ||
          t.contains(' error • ') ||
          t.startsWith('Error:') ||
          t.contains('error TS')) {
        final multi = RegExp(r'\[(\d+)x\]').firstMatch(t);
        count += multi != null ? (int.tryParse(multi.group(1)!) ?? 1) : 1;
      }
    }
    return count;
  }

  ({String reasoning, String answer}) _splitThinkTags(String raw) {
    final thinkRegex = RegExp(r'<think>([\s\S]*?)</think>', multiLine: true);
    final matches = thinkRegex.allMatches(raw).toList();
    if (matches.isEmpty) {
      final openIdx = raw.indexOf('<think>');
      if (openIdx != -1) {
        return (
          reasoning: raw.substring(openIdx + 7).trim(),
          answer: raw.substring(0, openIdx).trim(),
        );
      }
      return (reasoning: '', answer: raw);
    }
    final reasoning = matches.map((m) => m.group(1)?.trim() ?? '').join('\n\n');
    final answer = raw.replaceAll(thinkRegex, '').trim();
    return (reasoning: reasoning, answer: answer);
  }

  Future<_ParsedTurn> _sendOpenAiStreaming({
    required http.Client client,
    required RoxumModelOption model,
    required Map<String, dynamic> payload,
    required void Function(String partialText) onAssistantText,
    void Function(String reasoningText)? onReasoningText,
    required bool Function() isCancelled,
    void Function(String status)? onRetryStatus,
  }) async {
    final uri = Uri.parse(model.url);
    final isLocalEndpoint =
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host.startsWith('192.168.') ||
        uri.host.startsWith('10.');
    final streamPayload = Map<String, dynamic>.from(payload)
      ..['stream'] = true
      ..addAll(
        isLocalEndpoint
            ? const <String, dynamic>{}
            : const {
                'stream_options': {'include_usage': true},
              },
      );

    http.StreamedResponse streamed;
    for (var attempt = 0; ; attempt++) {
      final req = http.Request('POST', uri)
        ..headers.addAll(model.headers)
        ..body = jsonEncode(streamPayload);
      streamed = await client.send(req).timeout(const Duration(seconds: 90));
      final retryable = const {
        429,
        500,
        502,
        503,
        504,
      }.contains(streamed.statusCode);
      if (!retryable || attempt >= 4) break;
      final retryBody = await streamed.stream.bytesToString();
      final wait = _retryDelay(streamed.headers, attempt);
      onRetryStatus?.call('Лимит API, повтор через ${wait.inSeconds} сек...');
      for (var left = wait.inMilliseconds; left > 0 && !isCancelled();) {
        final slice = left < 250 ? left : 250;
        await Future<void>.delayed(Duration(milliseconds: slice));
        left -= slice;
      }
      if (isCancelled()) {
        return const _ParsedTurn(
          text: '',
          toolCalls: [],
          rawAssistantMessage: {},
        );
      }
      if (retryBody.isEmpty) continue;
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errBody = await streamed.stream.bytesToString();
      // Retry once without stream if endpoint rejects stream_options
      if (streamed.statusCode == 400 || streamed.statusCode == 422) {
        final fallbackRes = await client
            .post(
              Uri.parse(model.url),
              headers: model.headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 90));
        if (fallbackRes.statusCode >= 200 && fallbackRes.statusCode < 300) {
          final decoded = jsonDecode(fallbackRes.body) as Map<String, dynamic>;
          final parsed = _parseResponse(model.method, decoded);
          final split = _splitThinkTags(parsed.text);
          if (split.reasoning.isNotEmpty) {
            onReasoningText?.call(split.reasoning);
          }
          if (split.answer.isNotEmpty) onAssistantText(split.answer);
          return parsed;
        }
      }
      throw Exception('HTTP ${streamed.statusCode}: $errBody');
    }

    final contentType = streamed.headers['content-type'] ?? '';
    if (!contentType.contains('text/event-stream')) {
      final body = await streamed.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final parsed = _parseResponse(model.method, decoded);
      final split = _splitThinkTags(parsed.text);
      if (split.reasoning.isNotEmpty) onReasoningText?.call(split.reasoning);
      if (split.answer.isNotEmpty) onAssistantText(split.answer);
      return parsed;
    }

    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    final toolBuffers =
        <int, ({StringBuffer id, StringBuffer name, StringBuffer args})>{};
    RoxumUsageStats usage = const RoxumUsageStats();
    String? finishReason;

    var lineCarry = '';
    try {
      await for (final chunk in streamed.stream
          .timeout(const Duration(seconds: 45))
          .transform(utf8.decoder)) {
        if (isCancelled()) break;
        final combined = lineCarry + chunk;
        final lines = combined.split('\n');
        lineCarry = lines.removeLast();

        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (!line.startsWith('data:')) continue;
          final dataStr = line.substring(5).trim();
          if (dataStr.isEmpty || dataStr == '[DONE]') continue;

          try {
            final json = jsonDecode(dataStr) as Map<String, dynamic>;
            final u = (json['usage'] as Map?)?.cast<String, dynamic>();
            if (u != null) {
              final pTok = (u['prompt_tokens'] as num?)?.toInt() ?? 0;
              final cTok = (u['completion_tokens'] as num?)?.toInt() ?? 0;
              final tTok = (u['total_tokens'] as num?)?.toInt() ?? (pTok + cTok);
              final cost = (u['cost'] as num?)?.toDouble() ?? 0.0;
              usage = RoxumUsageStats(
                promptTokens: pTok,
                completionTokens: cTok,
                totalTokens: tTok,
                costUsd: cost,
              );
            }

            final choices = (json['choices'] as List?) ?? const [];
            if (choices.isEmpty) continue;
            final firstChoice = choices.first;
            if (firstChoice is Map && firstChoice['finish_reason'] != null) {
              finishReason = firstChoice['finish_reason']?.toString();
            }
            final delta =
                (firstChoice is Map ? firstChoice['delta'] as Map? : null)
                    ?.cast<String, dynamic>();
            if (delta == null) continue;

            final reasoning = delta['reasoning']?.toString();
            final reasoningContent = delta['reasoning_content']?.toString();
            final rDelta = (reasoning != null && reasoning.isNotEmpty)
                ? reasoning
                : ((reasoningContent != null && reasoningContent.isNotEmpty)
                      ? reasoningContent
                      : delta['thought']?.toString());
            if (rDelta != null && rDelta.isNotEmpty) {
              reasoningBuf.write(rDelta);
              onReasoningText?.call(reasoningBuf.toString());
            }
            final rDetails = delta['reasoning_details'];
            if ((rDelta == null || rDelta.isEmpty) && rDetails is List) {
              final buf = StringBuffer();
              for (final item in rDetails) {
                if (item is Map) {
                  final t =
                      item['text']?.toString() ?? item['summary']?.toString();
                  if (t != null && t.isNotEmpty) buf.write(t);
                }
              }
              if (buf.isNotEmpty) {
                reasoningBuf.write(buf.toString());
                onReasoningText?.call(reasoningBuf.toString());
              }
            }

            final cDelta = delta['content']?.toString();
            if (cDelta != null && cDelta.isNotEmpty) {
              contentBuf.write(cDelta);
              final split = _splitThinkTags(contentBuf.toString());
              if (split.reasoning.isNotEmpty && reasoningBuf.isEmpty) {
                onReasoningText?.call(split.reasoning);
              }
              onAssistantText(split.answer);
            }

            final tcList = delta['tool_calls'];
            if (tcList is List) {
              for (final item in tcList) {
                if (item is! Map) continue;
                final rawId = item['id']?.toString() ?? '';
                int idx;
                if (item['index'] is num) {
                  idx = (item['index'] as num).toInt();
                } else if (rawId.isNotEmpty) {
                  final existingIdx = toolBuffers.entries
                      .where((e) => e.value.id.toString() == rawId)
                      .map((e) => e.key)
                      .firstOrNull;
                  idx =
                      existingIdx ??
                      (toolBuffers.isEmpty
                          ? 0
                          : (toolBuffers.keys.reduce((a, b) => a > b ? a : b) +
                                1));
                } else {
                  idx = toolBuffers.isEmpty
                      ? 0
                      : toolBuffers.keys.reduce((a, b) => a > b ? a : b);
                }
                final entry = toolBuffers.putIfAbsent(
                  idx,
                  () => (
                    id: StringBuffer(),
                    name: StringBuffer(),
                    args: StringBuffer(),
                  ),
                );
                if (rawId.isNotEmpty && entry.id.isEmpty) {
                  entry.id.write(rawId);
                }
                final fn = item['function'] as Map?;
                if (fn != null) {
                  if (fn['name'] != null) {
                    entry.name.write(fn['name'].toString());
                  }
                  final rawArgChunk = fn['arguments'];
                  if (rawArgChunk is Map) {
                    entry.args.write(jsonEncode(rawArgChunk));
                  } else if (rawArgChunk != null) {
                    entry.args.write(rawArgChunk.toString());
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
    } on TimeoutException {
      finishReason ??= 'stream_timeout';
      onRetryStatus?.call('Поток модели прервался по таймауту (45с)...');
    }

    final calls = <({String id, String name, Map<String, dynamic> args})>[];
    final rawCalls = <Map<String, dynamic>>[];
    final sortedKeys = toolBuffers.keys.toList()..sort();
    for (final idx in sortedKeys) {
      final buf = toolBuffers[idx]!;
      final id = buf.id.isNotEmpty ? buf.id.toString() : 'call_$idx';
      final name = buf.name.toString().trim();
      final rawArgs = buf.args.isNotEmpty ? buf.args.toString() : '{}';
      final parsedArgs = _decodeToolArgsWithRecovery(
        rawArgs,
        finishReason: finishReason,
      );
      if (name.isNotEmpty) {
        final safeSerializedArgs = parsedArgs.containsKey('__parse_error__')
            ? jsonEncode(parsedArgs)
            : rawArgs;
        calls.add((id: id, name: name, args: parsedArgs));
        rawCalls.add({
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': safeSerializedArgs},
        });
      }
    }

    final finalSplit = _splitThinkTags(contentBuf.toString());
    var cleanAnswer = finalSplit.answer;

    // Fallback: extract `<tool_call>{...}</tool_call>` or `<function=name>{...}</function>`
    // emitted as plain text by OpenRouter free/open-weight models.
    if (calls.isEmpty && cleanAnswer.isNotEmpty) {
      final fallback = extractTextToolCalls(cleanAnswer);
      if (fallback.calls.isNotEmpty) {
        cleanAnswer = fallback.remainingText;
        for (final fc in fallback.calls) {
          calls.add(fc);
          rawCalls.add({
            'id': fc.id,
            'type': 'function',
            'function': {'name': fc.name, 'arguments': jsonEncode(fc.args)},
          });
        }
      }
    }

    final effectiveReasoning = reasoningBuf.isNotEmpty
        ? reasoningBuf.toString()
        : finalSplit.reasoning;
    return _ParsedTurn(
      text: cleanAnswer,
      reasoning: effectiveReasoning,
      toolCalls: calls,
      rawAssistantMessage: {
        'role': 'assistant',
        'content': (cleanAnswer.isEmpty && rawCalls.isNotEmpty)
            ? null
            : cleanAnswer,
        if (rawCalls.isNotEmpty) 'tool_calls': rawCalls,
      },
      usage: usage,
      finishReason: finishReason,
    );
  }

  static Map<String, dynamic> _decodeToolArgsWithRecovery(
    String rawArgs, {
    String? finishReason,
  }) {
    final trimmed = rawArgs.trim();
    if (trimmed.isEmpty || trimmed == '{}') return <String, dynamic>{};
    try {
      final d = jsonDecode(trimmed);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {
      // Strip accidental markdown fences if present
      final stripped = trimmed
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
      try {
        final d2 = jsonDecode(stripped);
        if (d2 is Map<String, dynamic>) return d2;
        if (d2 is Map) return Map<String, dynamic>.from(d2);
      } catch (_) {}
    }
    return {
      '__parse_error__':
          'Tool arguments JSON was truncated or malformed (finish_reason=${finishReason ?? 'unknown'}, ${trimmed.length} chars). '
          'Split large files into smaller modular files (150-250 lines) or use `editFile` / `multiEditFile` instead of sending huge file contents in one call.',
    };
  }

  /// Extracts `<tool_call>{"name": ..., "arguments": ...}</tool_call>` or
  /// `<function=toolName>{...}</function>` blocks emitted in plain text by
  /// open-weight models that occasionally miss OpenAI's streaming `tool_calls`.
  static ({
    List<({String id, String name, Map<String, dynamic> args})> calls,
    String remainingText,
  }) extractTextToolCalls(String text) {
    final extracted = <({String id, String name, Map<String, dynamic> args})>[];
    var cleaned = text;

    final xmlToolCallRe = RegExp(
      r'<tool_call>\s*([\s\S]*?)\s*</tool_call>',
      caseSensitive: false,
    );
    for (final m in xmlToolCallRe.allMatches(text)) {
      final body = m.group(1)?.trim() ?? '';
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final name =
              (decoded['name'] ?? (decoded['function'] as Map?)?['name'])
                  ?.toString()
                  .trim() ??
              '';
          final rawArgs =
              decoded['arguments'] ??
              decoded['parameters'] ??
              (decoded['function'] as Map?)?['arguments'];
          Map<String, dynamic> args = {};
          if (rawArgs is Map) {
            args = Map<String, dynamic>.from(rawArgs);
          } else if (rawArgs is String && rawArgs.trim().startsWith('{')) {
            args = _decodeToolArgsWithRecovery(rawArgs);
          }
          if (name.isNotEmpty) {
            extracted.add((
              id: 'txtcall_${extracted.length}',
              name: name,
              args: args,
            ));
          }
        }
      } catch (_) {}
    }
    if (extracted.isNotEmpty) {
      cleaned = cleaned.replaceAll(xmlToolCallRe, '').trim();
      return (calls: extracted, remainingText: cleaned);
    }

    final fnTagRe = RegExp(
      r'<function=([A-Za-z0-9_]+)>\s*([\s\S]*?)\s*</function>',
      caseSensitive: false,
    );
    for (final m in fnTagRe.allMatches(text)) {
      final name = m.group(1)?.trim() ?? '';
      final body = m.group(2)?.trim() ?? '{}';
      if (name.isNotEmpty) {
        final args = _decodeToolArgsWithRecovery(body);
        extracted.add((
          id: 'fncall_${extracted.length}',
          name: name,
          args: args,
        ));
      }
    }
    if (extracted.isNotEmpty) {
      cleaned = cleaned.replaceAll(fnTagRe, '').trim();
    }
    return (calls: extracted, remainingText: cleaned);
  }

  Duration _retryDelay(Map<String, String> headers, int attempt) {
    final retryAfter = headers['retry-after'];
    final reset = headers['x-ratelimit-reset'];
    var seconds = double.tryParse(retryAfter ?? '') ?? 0;
    if (seconds <= 0 && reset != null) {
      final value = double.tryParse(reset);
      if (value != null) {
        final millis = value > 1e12 ? value : value * 1000;
        seconds = (millis - DateTime.now().millisecondsSinceEpoch) / 1000;
      }
    }
    if (seconds <= 0) {
      seconds = [3, 6, 12, 24, 45][attempt.clamp(0, 4)].toDouble();
    }
    return Duration(seconds: seconds.ceil().clamp(2, 65));
  }

  Map<String, dynamic> _buildPayload({
    required RoxumModelOption model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) {
    final isAgentMode = tools.isNotEmpty;
    final temp = isAgentMode ? 0.15 : 0.4;
    switch (model.method) {
      case RoxumToolCallingMethod.anthropicMessages:
        final systemPrompts = messages
            .where((m) => m['role'] == 'system')
            .map((m) => m['content']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .join('\n\n');
        final nonSystem = messages.where((m) => m['role'] != 'system').toList();
        return {
          'model': model.model,
          'max_tokens': 8192,
          'temperature': temp,
          if (systemPrompts.isNotEmpty) 'system': systemPrompts,
          'messages': _toAnthropicMessages(nonSystem),
          if (tools.isNotEmpty) 'tools': _toAnthropicTools(tools),
        };
      case RoxumToolCallingMethod.geminiFunctionCalling:
        final systemPrompts = messages
            .where((m) => m['role'] == 'system')
            .map((m) => m['content']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .join('\n\n');
        final nonSystem = messages.where((m) => m['role'] != 'system').toList();
        return {
          'contents': _toGeminiContents(nonSystem),
          'generationConfig': {
            'temperature': temp,
            'maxOutputTokens': 16384,
          },
          if (systemPrompts.isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': systemPrompts},
              ],
            },
          if (tools.isNotEmpty)
            'tools': [
              {'functionDeclarations': _toGeminiFunctionDeclarations(tools)},
            ],
        };
      case RoxumToolCallingMethod.openAiCompatible:
        final idLower = model.model.toLowerCase();
        final isOpenAiReasoner =
            idLower.startsWith('o1') ||
            idLower.startsWith('o3') ||
            idLower.startsWith('o4') ||
            idLower.contains('/o1') ||
            idLower.contains('/o3') ||
            idLower.contains('/o4');
        return {
          'model': model.model,
          'messages': messages,
          'max_tokens': 16384,
          if (!isOpenAiReasoner) 'temperature': temp,
          if (tools.isNotEmpty) 'tools': tools,
          if (tools.isNotEmpty) 'tool_choice': 'auto',
        };
    }
  }

  static final _fakeEditRegex = RegExp(
    r'(прочитал|внёс\s+правки|правки\s+применены|вот\s+что\s+сделано|добавил|убрал|исправил|переписал|обновил|edited|applied|updated\s+the\s+file|changes\s+made)',
    caseSensitive: false,
  );

  bool _looksLikeFakeEditClaim(String text) {
    if (text.trim().isEmpty) return false;
    return _fakeEditRegex.hasMatch(text);
  }

  static final _imminentActionPromiseRe = RegExp(
    r'(исправлю|сейчас\s+(исправлю|обновлю|создам|заменю|проверю|перепишу|удалю)|давайте\s+исправим|вношу\s+правки|применяю\s+изменения|let\s+me\s+(fix|edit|update|create|apply|remove|clean|refactor|check|add|build|implement)|i\s+will\s+now\s+(fix|edit|update|write|remove))\s*[:.…]*$',
    caseSensitive: false,
  );

  /// Detects when an LLM stops mid-thought without calling a tool (for example
  /// ending with `"Исправлю:"` or printing a large full-file code block into
  /// chat when no files were modified yet).
  static bool _looksLikeIncompleteStop(
    String text, {
    required bool editedAnyFile,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    // Ends with a colon announcing an action ("Исправлю:", "Обновлю код:")
    if (trimmed.length < 400 && trimmed.endsWith(':')) {
      return true;
    }
    if (trimmed.length < 500 && _imminentActionPromiseRe.hasMatch(trimmed)) {
      return true;
    }
    // Model dumped a large code block (>= 25 lines) in chat without editing any file
    if (!editedAnyFile && trimmed.contains('```')) {
      final fenceMatches = RegExp(r'```[a-zA-Z0-9_+-]*\n([\s\S]*?)```').allMatches(trimmed);
      for (final m in fenceMatches) {
        final codeLines = (m.group(1) ?? '').split('\n').length;
        if (codeLines >= 25) return true;
      }
    }
    return false;
  }

  _ParsedTurn _parseResponse(
    RoxumToolCallingMethod method,
    Map<String, dynamic> json,
  ) {
    switch (method) {
      case RoxumToolCallingMethod.openAiCompatible:
        final firstChoice = (json['choices'] as List).first as Map<String, dynamic>;
        final msg = firstChoice['message'] as Map<String, dynamic>;
        final finishReason = firstChoice['finish_reason']?.toString();
        var text = msg['content']?.toString() ?? '';
        var reasoning =
            msg['reasoning_content']?.toString() ??
            msg['reasoning']?.toString() ??
            '';
        if (reasoning.isEmpty && msg['reasoning_details'] is List) {
          final rBuf = StringBuffer();
          for (final item in (msg['reasoning_details'] as List)) {
            if (item is Map) {
              final t = item['text']?.toString() ?? item['summary']?.toString();
              if (t != null && t.isNotEmpty) rBuf.write(t);
            }
          }
          reasoning = rBuf.toString();
        }
        final calls = <({String id, String name, Map<String, dynamic> args})>[];
        final outRawCalls = <Map<String, dynamic>>[];
        final rawCalls = msg['tool_calls'] as List?;
        if (rawCalls != null) {
          for (final item in rawCalls) {
            if (item is! Map) continue;
            final fn = item['function'] as Map?;
            if (fn == null) continue;
            final id = item['id']?.toString() ?? 'call_${calls.length}';
            final name = fn['name']?.toString().trim() ?? '';
            final rawArgs = fn['arguments']?.toString() ?? '{}';
            final parsedArgs = _decodeToolArgsWithRecovery(
              rawArgs,
              finishReason: finishReason,
            );
            if (name.isNotEmpty) {
              calls.add((id: id, name: name, args: parsedArgs));
              outRawCalls.add(Map<String, dynamic>.from(item));
            }
          }
        }
        if (calls.isEmpty && text.isNotEmpty) {
          final fallback = extractTextToolCalls(text);
          if (fallback.calls.isNotEmpty) {
            text = fallback.remainingText;
            for (final fc in fallback.calls) {
              calls.add(fc);
              outRawCalls.add({
                'id': fc.id,
                'type': 'function',
                'function': {'name': fc.name, 'arguments': jsonEncode(fc.args)},
              });
            }
          }
        }
        final openAiUsage = (json['usage'] as Map?)?.cast<String, dynamic>();
        final oPrompt = (openAiUsage?['prompt_tokens'] as num?)?.toInt() ?? 0;
        final oComp = (openAiUsage?['completion_tokens'] as num?)?.toInt() ?? 0;
        final oTotal =
            (openAiUsage?['total_tokens'] as num?)?.toInt() ??
            (oPrompt + oComp);
        final oCost = (openAiUsage?['cost'] as num?)?.toDouble() ?? 0.0;
        return _ParsedTurn(
          text: text,
          reasoning: reasoning,
          toolCalls: calls,
          rawAssistantMessage: {
            'role': 'assistant',
            'content': (text.isEmpty && outRawCalls.isNotEmpty)
                ? null
                : text,
            if (outRawCalls.isNotEmpty) 'tool_calls': outRawCalls,
          },
          usage: RoxumUsageStats(
            promptTokens: oPrompt,
            completionTokens: oComp,
            totalTokens: oTotal,
            costUsd: oCost,
          ),
        );

      case RoxumToolCallingMethod.anthropicMessages:
        final blocks = (json['content'] as List?) ?? const [];
        final textBuf = StringBuffer();
        final reasonBuf = StringBuffer();
        final calls = <({String id, String name, Map<String, dynamic> args})>[];
        final rawToolCalls = <Map<String, dynamic>>[];
        for (final b in blocks) {
          if (b is! Map) continue;
          if (b['type'] == 'thinking') {
            reasonBuf.write(b['thinking']?.toString() ?? '');
          } else if (b['type'] == 'text') {
            textBuf.write(b['text']?.toString() ?? '');
          } else if (b['type'] == 'tool_use') {
            final id = b['id']?.toString() ?? 'tool_${calls.length}';
            final name = b['name']?.toString() ?? '';
            final input = (b['input'] as Map?)?.cast<String, dynamic>() ?? {};
            calls.add((id: id, name: name, args: input));
            rawToolCalls.add({
              'id': id,
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(input)},
            });
          }
        }
        final antUsage = (json['usage'] as Map?)?.cast<String, dynamic>();
        final aIn = (antUsage?['input_tokens'] as num?)?.toInt() ?? 0;
        final aOut = (antUsage?['output_tokens'] as num?)?.toInt() ?? 0;
        return _ParsedTurn(
          text: textBuf.toString(),
          reasoning: reasonBuf.toString(),
          toolCalls: calls,
          rawAssistantMessage: {
            'role': 'assistant',
            'content': textBuf.toString(),
            if (rawToolCalls.isNotEmpty) 'tool_calls': rawToolCalls,
          },
          usage: RoxumUsageStats(
            promptTokens: aIn,
            completionTokens: aOut,
            totalTokens: aIn + aOut,
          ),
        );

      case RoxumToolCallingMethod.geminiFunctionCalling:
        final candidates = (json['candidates'] as List?) ?? const [];
        if (candidates.isEmpty) {
          return const _ParsedTurn(
            text: '',
            toolCalls: [],
            rawAssistantMessage: {'role': 'assistant', 'content': ''},
          );
        }
        final parts =
            (candidates.first['content']?['parts'] as List?) ?? const [];
        final textBuf = StringBuffer();
        final reasonBuf = StringBuffer();
        final calls = <({String id, String name, Map<String, dynamic> args})>[];
        final rawToolCalls = <Map<String, dynamic>>[];
        for (final part in parts) {
          if (part is! Map) continue;
          if (part['thought'] == true && part['text'] != null) {
            reasonBuf.write(part['text'].toString());
          } else if (part['text'] != null) {
            textBuf.write(part['text'].toString());
          } else if (part['functionCall'] is Map) {
            final fc = part['functionCall'] as Map;
            final name = fc['name']?.toString() ?? '';
            final args = (fc['args'] as Map?)?.cast<String, dynamic>() ?? {};
            final id = 'gem_${calls.length}_$name';
            calls.add((id: id, name: name, args: args));
            rawToolCalls.add({
              'id': id,
              'type': 'function',
              'function': {'name': name, 'arguments': jsonEncode(args)},
            });
          }
        }
        final gemUsage = (json['usageMetadata'] as Map?)
            ?.cast<String, dynamic>();
        final gIn = (gemUsage?['promptTokenCount'] as num?)?.toInt() ?? 0;
        final gOut = (gemUsage?['candidatesTokenCount'] as num?)?.toInt() ?? 0;
        final gTotal =
            (gemUsage?['totalTokenCount'] as num?)?.toInt() ?? (gIn + gOut);
        return _ParsedTurn(
          text: textBuf.toString(),
          reasoning: reasonBuf.toString(),
          toolCalls: calls,
          rawAssistantMessage: {
            'role': 'assistant',
            'content': textBuf.toString(),
            if (rawToolCalls.isNotEmpty) 'tool_calls': rawToolCalls,
          },
          usage: RoxumUsageStats(
            promptTokens: gIn,
            completionTokens: gOut,
            totalTokens: gTotal,
          ),
        );
    }
  }

  List<Map<String, dynamic>> _toAnthropicTools(
    List<Map<String, dynamic>> tools,
  ) {
    return tools.map((t) {
      final fn = t['function'] as Map<String, dynamic>;
      return {
        'name': fn['name'],
        'description': fn['description'],
        'input_schema': fn['parameters'],
      };
    }).toList();
  }

  List<Map<String, dynamic>> _toAnthropicMessages(
    List<Map<String, dynamic>> msgs,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in msgs) {
      final role = m['role']?.toString() ?? 'user';
      if (role == 'tool') {
        out.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': m['tool_call_id'],
              'content': m['content']?.toString() ?? '',
            },
          ],
        });
      } else if (role == 'assistant' && m['tool_calls'] is List) {
        final blocks = <Map<String, dynamic>>[];
        final text = m['content']?.toString() ?? '';
        if (text.isNotEmpty) blocks.add({'type': 'text', 'text': text});
        for (final tc in m['tool_calls'] as List) {
          final fn = tc['function'] as Map;
          Map<String, dynamic> args = {};
          try {
            args =
                jsonDecode(fn['arguments'].toString()) as Map<String, dynamic>;
          } catch (_) {}
          blocks.add({
            'type': 'tool_use',
            'id': tc['id'],
            'name': fn['name'],
            'input': args,
          });
        }
        out.add({'role': 'assistant', 'content': blocks});
      } else {
        final rawContent = m['content'];
        if (rawContent is List) {
          final blocks = <Map<String, dynamic>>[];
          for (final item in rawContent) {
            if (item is! Map) continue;
            if (item['type'] == 'text') {
              blocks.add({
                'type': 'text',
                'text': item['text']?.toString() ?? '',
              });
            } else if (item['type'] == 'image_url') {
              final url = (item['image_url'] as Map?)?['url']?.toString() ?? '';
              final match = RegExp(
                r'^data:([^;]+);base64,(.+)$',
              ).firstMatch(url);
              if (match != null) {
                blocks.add({
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': match.group(1)!,
                    'data': match.group(2)!,
                  },
                });
              }
            }
          }
          out.add({
            'role': role == 'assistant' ? 'assistant' : 'user',
            'content': blocks,
          });
        } else {
          out.add({
            'role': role == 'assistant' ? 'assistant' : 'user',
            'content': rawContent?.toString() ?? '',
          });
        }
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _toGeminiFunctionDeclarations(
    List<Map<String, dynamic>> tools,
  ) {
    return tools.map((t) {
      final fn = t['function'] as Map<String, dynamic>;
      final rawParams = fn['parameters'];
      Map<String, dynamic>? sanitizedParams;
      if (rawParams is Map) {
        final props = rawParams['properties'];
        if (props is Map && props.isNotEmpty) {
          final cleanProps = <String, dynamic>{};
          props.forEach((k, v) {
            if (v is Map) {
              cleanProps[k.toString()] = _sanitizeGeminiSchemaNode(
                v.cast<String, dynamic>(),
              );
            }
          });
          if (cleanProps.isNotEmpty) {
            sanitizedParams = {
              'type': 'OBJECT',
              'properties': cleanProps,
              if (rawParams['required'] is List &&
                  (rawParams['required'] as List).isNotEmpty)
                'required': List<String>.from(
                  (rawParams['required'] as List)
                      .map((e) => e.toString())
                      .where(cleanProps.containsKey),
                ),
            };
          }
        }
      }
      return {
        'name': fn['name'],
        'description': fn['description'],
        ...?sanitizedParams == null ? null : {'parameters': sanitizedParams},
      };
    }).toList();
  }

  Map<String, dynamic> _sanitizeGeminiSchemaNode(Map<String, dynamic> node) {
    final rawType = (node['type']?.toString() ?? 'string').toUpperCase();
    final type =
        const {
          'STRING',
          'NUMBER',
          'INTEGER',
          'BOOLEAN',
          'ARRAY',
          'OBJECT',
        }.contains(rawType)
        ? rawType
        : 'STRING';
    final out = <String, dynamic>{
      'type': type,
      if (node['description'] != null)
        'description': node['description'].toString(),
      if (node['enum'] is List && type == 'STRING')
        'enum': (node['enum'] as List).map((e) => e.toString()).toList(),
    };
    if (type == 'ARRAY') {
      final items = node['items'];
      out['items'] = (items is Map)
          ? _sanitizeGeminiSchemaNode(items.cast<String, dynamic>())
          : {'type': 'STRING'};
    } else if (type == 'OBJECT' && node['properties'] is Map) {
      final childProps = <String, dynamic>{};
      (node['properties'] as Map).forEach((k, v) {
        if (v is Map) {
          childProps[k.toString()] = _sanitizeGeminiSchemaNode(
            v.cast<String, dynamic>(),
          );
        }
      });
      if (childProps.isNotEmpty) {
        out['properties'] = childProps;
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _toGeminiContents(
    List<Map<String, dynamic>> msgs,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in msgs) {
      final role = m['role']?.toString() ?? 'user';
      if (role == 'tool') {
        Map<String, dynamic> resp = {'result': m['content']?.toString() ?? ''};
        try {
          final d = jsonDecode(m['content'].toString());
          if (d is Map<String, dynamic>) resp = d;
        } catch (_) {}
        out.add({
          'role': 'function',
          'parts': [
            {
              'functionResponse': {
                'name': m['name']?.toString() ?? 'tool',
                'response': resp,
              },
            },
          ],
        });
      } else if (role == 'assistant' && m['tool_calls'] is List) {
        final parts = <Map<String, dynamic>>[];
        final text = m['content']?.toString() ?? '';
        if (text.isNotEmpty) parts.add({'text': text});
        for (final tc in m['tool_calls'] as List) {
          final fn = tc['function'] as Map;
          Map<String, dynamic> args = {};
          try {
            args =
                jsonDecode(fn['arguments'].toString()) as Map<String, dynamic>;
          } catch (_) {}
          parts.add({
            'functionCall': {'name': fn['name'], 'args': args},
          });
        }
        out.add({'role': 'model', 'parts': parts});
      } else {
        final rawContent = m['content'];
        if (rawContent is List) {
          final parts = <Map<String, dynamic>>[];
          for (final item in rawContent) {
            if (item is! Map) continue;
            if (item['type'] == 'text') {
              parts.add({'text': item['text']?.toString() ?? ''});
            } else if (item['type'] == 'image_url') {
              final url = (item['image_url'] as Map?)?['url']?.toString() ?? '';
              final match = RegExp(
                r'^data:([^;]+);base64,(.+)$',
              ).firstMatch(url);
              if (match != null) {
                parts.add({
                  'inlineData': {
                    'mimeType': match.group(1)!,
                    'data': match.group(2)!,
                  },
                });
              }
            }
          }
          out.add({
            'role': role == 'assistant' ? 'model' : 'user',
            'parts': parts,
          });
        } else {
          out.add({
            'role': role == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': rawContent?.toString() ?? ''},
            ],
          });
        }
      }
    }
    return out;
  }
}
