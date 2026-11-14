// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';

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
        return {
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
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
      for (final m in [
        'claude-sonnet-4-20250514',
        'claude-3-5-haiku-latest',
      ]) {
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
        ('nvidia/nemotron-3.5-super-vl:free', true),
        ('cohere/north-mini-code:free', true),
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
  final List<({String id, String name, Map<String, dynamic> args})> toolCalls;
  final Map<String, dynamic> rawAssistantMessage;
  final RoxumUsageStats usage;

  const _ParsedTurn({
    required this.text,
    required this.toolCalls,
    required this.rawAssistantMessage,
    this.usage = const RoxumUsageStats(),
  });
}

class RoxumAiClient {
  http.Client? _client;

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
        final res = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          lastError = Exception('HTTP ${res.statusCode} ($url)');
          continue;
        }
        final decoded = jsonDecode(res.body);
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
        final res = await http.get(
          Uri.parse(modelsUrl),
          headers: {
            'Content-Type': 'application/json',
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          },
        ).timeout(const Duration(seconds: 7));
        if (res.statusCode < 200 || res.statusCode >= 300) return const [];
        final decoded = jsonDecode(res.body);
        if (decoded is! Map || decoded['data'] is! List) return const [];
        final out = <RoxumModelOption>[];
        for (final item in decoded['data'] as List) {
          if (item is! Map || item['id'] == null) continue;
          final id = item['id'].toString();
          if (filter != null && !filter(id)) continue;
          final pricing = item['pricing'];
          final isFree = defaultFree ||
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
      futures.add(
        fetchOpenAiStyle(
          provider: 'OpenRouter',
          modelsUrl: 'https://openrouter.ai/api/v1/models',
          chatUrl: 'https://openrouter.ai/api/v1/chat/completions',
          apiKey: settings.openrouterApiKey.trim(),
        ).then((list) {
          list.sort((a, b) {
            if (a.isFree != b.isFree) return a.isFree ? -1 : 1;
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
            final methods = (m['supportedGenerationMethods'] as List?) ?? const [];
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
          final res = await http.get(
            Uri.parse('https://api.anthropic.com/v1/models'),
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
            },
          ).timeout(const Duration(seconds: 7));
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
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (decoded['data'] as Map?)?.cast<String, dynamic>() ?? decoded;
    final freeDaily =
        (data['free_model_daily_requests'] as Map?)?.cast<String, dynamic>();
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

  Future<String> runAgentLoop({
    required RoxumModelOption model,
    required List<Map<String, dynamic>> historyMessages,
    required List<Map<String, dynamic>> tools,
    required RoxumAgenticTools? agenticTools,
    required void Function(RoxumToolCallRecord record) onToolEvent,
    required void Function(String partialText) onAssistantText,
    void Function(String reasoningText)? onReasoningText,
    void Function(int step)? onStepStart,
    void Function(RoxumUsageStats usage)? onUsage,
    required bool Function() isCancelled,
  }) async {
    _client?.close();
    final client = http.Client();
    _client = client;

    final messages = List<Map<String, dynamic>>.from(historyMessages);
    const maxIterations = 16;

    try {
      for (int step = 0; step < maxIterations; step++) {
        if (isCancelled()) return '';
        onStepStart?.call(step);

        final payload = _buildPayload(
          model: model,
          messages: messages,
          tools: tools,
        );

        final _ParsedTurn turn;
        if (model.method == RoxumToolCallingMethod.openAiCompatible) {
          turn = await _sendOpenAiStreaming(
            client: client,
            model: model,
            payload: payload,
            onAssistantText: onAssistantText,
            onReasoningText: onReasoningText,
            isCancelled: isCancelled,
          );
        } else {
          final res = await client
              .post(
                Uri.parse(model.url),
                headers: model.headers,
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 90));

          if (isCancelled()) return '';

          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw Exception('HTTP ${res.statusCode}: ${res.body}');
          }

          final decoded = jsonDecode(res.body) as Map<String, dynamic>;
          turn = _parseResponse(model.method, decoded);
          if (turn.text.isNotEmpty) {
            final extracted = _splitThinkTags(turn.text);
            if (extracted.reasoning.isNotEmpty) {
              onReasoningText?.call(extracted.reasoning);
            }
            onAssistantText(extracted.answer);
          }
        }

        if (isCancelled()) return '';

        if (turn.usage.totalTokens > 0 || turn.usage.costUsd > 0) {
          onUsage?.call(turn.usage);
        }

        if (turn.toolCalls.isEmpty || agenticTools == null) {
          return _splitThinkTags(turn.text).answer;
        }

        messages.add(turn.rawAssistantMessage);

        for (final call in turn.toolCalls) {
          if (isCancelled()) return _splitThinkTags(turn.text).answer;

          final runningRecord = RoxumToolCallRecord(
            id: call.id,
            name: call.name,
            arguments: call.args,
            isRunning: true,
          );
          onToolEvent(runningRecord);

          final result = await agenticTools.execute(call.name, call.args);
          onToolEvent(
            runningRecord.copyWith(
              isRunning: false,
              success: result.success,
              output: result.output,
            ),
          );

          messages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'name': call.name,
            'content': result.toJsonString(),
          });
        }
      }
      return 'Достигнут лимит шагов агента (16).';
    } finally {
      if (_client == client) {
        _client?.close();
        _client = null;
      }
    }
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
  }) async {
    final uri = Uri.parse(model.url);
    final isLocalEndpoint = uri.host == 'localhost' ||
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

    final req = http.Request('POST', uri);
    req.headers.addAll(model.headers);
    req.body = jsonEncode(streamPayload);

    final streamed = await client.send(req).timeout(const Duration(seconds: 90));
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
          if (split.reasoning.isNotEmpty) onReasoningText?.call(split.reasoning);
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
    final toolBuffers = <int, ({StringBuffer id, StringBuffer name, StringBuffer args})>{};
    RoxumUsageStats usage = const RoxumUsageStats();

    var lineCarry = '';
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
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
          final delta = (choices.first['delta'] as Map?)?.cast<String, dynamic>();
          if (delta == null) continue;

          final rDelta = delta['reasoning_content']?.toString() ??
              delta['reasoning']?.toString();
          if (rDelta != null && rDelta.isNotEmpty) {
            reasoningBuf.write(rDelta);
            onReasoningText?.call(reasoningBuf.toString());
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
                idx = existingIdx ??
                    (toolBuffers.isEmpty
                        ? 0
                        : (toolBuffers.keys.reduce((a, b) => a > b ? a : b) + 1));
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
              if (rawId.isNotEmpty && entry.id.isEmpty) entry.id.write(rawId);
              final fn = item['function'] as Map?;
              if (fn != null) {
                if (fn['name'] != null) entry.name.write(fn['name'].toString());
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

    final calls = <({String id, String name, Map<String, dynamic> args})>[];
    final rawCalls = <Map<String, dynamic>>[];
    final sortedKeys = toolBuffers.keys.toList()..sort();
    for (final idx in sortedKeys) {
      final buf = toolBuffers[idx]!;
      final id = buf.id.isNotEmpty ? buf.id.toString() : 'call_$idx';
      final name = buf.name.toString();
      final rawArgs = buf.args.isNotEmpty ? buf.args.toString() : '{}';
      Map<String, dynamic> parsedArgs = {};
      try {
        final d = jsonDecode(rawArgs);
        if (d is Map<String, dynamic>) parsedArgs = d;
      } catch (_) {}
      if (name.isNotEmpty) {
        calls.add((id: id, name: name, args: parsedArgs));
        rawCalls.add({
          'id': id,
          'type': 'function',
          'function': {'name': name, 'arguments': rawArgs},
        });
      }
    }

    final finalSplit = _splitThinkTags(contentBuf.toString());
    return _ParsedTurn(
      text: finalSplit.answer,
      toolCalls: calls,
      rawAssistantMessage: {
        'role': 'assistant',
        'content': (finalSplit.answer.isEmpty && rawCalls.isNotEmpty)
            ? null
            : finalSplit.answer,
        if (rawCalls.isNotEmpty) 'tool_calls': rawCalls,
      },
      usage: usage,
    );
  }

  Map<String, dynamic> _buildPayload({
    required RoxumModelOption model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) {
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
          'max_tokens': 4096,
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
        return {
          'model': model.model,
          'messages': messages,
          if (tools.isNotEmpty) 'tools': tools,
        };
    }
  }

  _ParsedTurn _parseResponse(
    RoxumToolCallingMethod method,
    Map<String, dynamic> json,
  ) {
    switch (method) {
      case RoxumToolCallingMethod.openAiCompatible:
        final msg = (json['choices'] as List).first['message'] as Map<String, dynamic>;
        final text = msg['content']?.toString() ?? '';
        final calls = <({String id, String name, Map<String, dynamic> args})>[];
        final rawCalls = msg['tool_calls'] as List?;
        if (rawCalls != null) {
          for (final item in rawCalls) {
            if (item is! Map) continue;
            final fn = item['function'] as Map?;
            if (fn == null) continue;
            final id = item['id']?.toString() ?? 'call_${calls.length}';
            final name = fn['name']?.toString() ?? '';
            final rawArgs = fn['arguments']?.toString() ?? '{}';
            Map<String, dynamic> parsedArgs = {};
            try {
              final d = jsonDecode(rawArgs);
              if (d is Map<String, dynamic>) parsedArgs = d;
            } catch (_) {}
            if (name.isNotEmpty) {
              calls.add((id: id, name: name, args: parsedArgs));
            }
          }
        }
        final openAiUsage = (json['usage'] as Map?)?.cast<String, dynamic>();
        final oPrompt = (openAiUsage?['prompt_tokens'] as num?)?.toInt() ?? 0;
        final oComp = (openAiUsage?['completion_tokens'] as num?)?.toInt() ?? 0;
        final oTotal = (openAiUsage?['total_tokens'] as num?)?.toInt() ?? (oPrompt + oComp);
        final oCost = (openAiUsage?['cost'] as num?)?.toDouble() ?? 0.0;
        return _ParsedTurn(
          text: text,
          toolCalls: calls,
          rawAssistantMessage: {
            'role': 'assistant',
            'content': text,
            if (rawCalls != null && rawCalls.isNotEmpty) 'tool_calls': rawCalls,
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
        final calls = <({String id, String name, Map<String, dynamic> args})>[];
        final rawToolCalls = <Map<String, dynamic>>[];
        for (final b in blocks) {
          if (b is! Map) continue;
          if (b['type'] == 'text') {
            textBuf.write(b['text']?.toString() ?? '');
          } else if (b['type'] == 'tool_use') {
            final id = b['id']?.toString() ?? 'tool_${calls.length}';
            final name = b['name']?.toString() ?? '';
            final input = (b['input'] as Map?)?.cast<String, dynamic>() ?? {};
            calls.add((id: id, name: name, args: input));
            rawToolCalls.add({
              'id': id,
              'type': 'function',
              'function': {
                'name': name,
                'arguments': jsonEncode(input),
              },
            });
          }
        }
        final antUsage = (json['usage'] as Map?)?.cast<String, dynamic>();
        final aIn = (antUsage?['input_tokens'] as num?)?.toInt() ?? 0;
        final aOut = (antUsage?['output_tokens'] as num?)?.toInt() ?? 0;
        return _ParsedTurn(
          text: textBuf.toString(),
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
        final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
        final textBuf = StringBuffer();
        final calls = <({String id, String name, Map<String, dynamic> args})>[];
        final rawToolCalls = <Map<String, dynamic>>[];
        for (final part in parts) {
          if (part is! Map) continue;
          if (part['text'] != null) {
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
              'function': {
                'name': name,
                'arguments': jsonEncode(args),
              },
            });
          }
        }
        final gemUsage = (json['usageMetadata'] as Map?)?.cast<String, dynamic>();
        final gIn = (gemUsage?['promptTokenCount'] as num?)?.toInt() ?? 0;
        final gOut = (gemUsage?['candidatesTokenCount'] as num?)?.toInt() ?? 0;
        final gTotal = (gemUsage?['totalTokenCount'] as num?)?.toInt() ?? (gIn + gOut);
        return _ParsedTurn(
          text: textBuf.toString(),
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

  List<Map<String, dynamic>> _toAnthropicTools(List<Map<String, dynamic>> tools) {
    return tools.map((t) {
      final fn = t['function'] as Map<String, dynamic>;
      return {
        'name': fn['name'],
        'description': fn['description'],
        'input_schema': fn['parameters'],
      };
    }).toList();
  }

  List<Map<String, dynamic>> _toAnthropicMessages(List<Map<String, dynamic>> msgs) {
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
            args = jsonDecode(fn['arguments'].toString()) as Map<String, dynamic>;
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
              blocks.add({'type': 'text', 'text': item['text']?.toString() ?? ''});
            } else if (item['type'] == 'image_url') {
              final url = (item['image_url'] as Map?)?['url']?.toString() ?? '';
              final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(url);
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
      return {
        'name': fn['name'],
        'description': fn['description'],
        'parameters': fn['parameters'],
      };
    }).toList();
  }

  List<Map<String, dynamic>> _toGeminiContents(List<Map<String, dynamic>> msgs) {
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
            args = jsonDecode(fn['arguments'].toString()) as Map<String, dynamic>;
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
              final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(url);
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
