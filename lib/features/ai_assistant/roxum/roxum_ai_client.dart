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

  const RoxumModelOption({
    required this.id,
    required this.name,
    required this.provider,
    required this.url,
    required this.apiKey,
    required this.model,
    required this.method,
  });

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
        'anthropic/claude-3.5-sonnet',
        'qwen/qwen-2.5-coder-32b-instruct',
        'google/gemini-2.5-flash',
      ]) {
        list.add(
          RoxumModelOption(
            id: 'openrouter:$m',
            name: m,
            provider: 'OpenRouter',
            url: 'https://openrouter.ai/api/v1/chat/completions',
            apiKey: settings.openrouterApiKey.trim(),
            model: m,
            method: RoxumToolCallingMethod.openAiCompatible,
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
      final base =
          settings.customApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      list.add(
        RoxumModelOption(
          id: 'custom:${settings.customApiModel.trim()}',
          name: settings.customApiModel.trim(),
          provider: 'Custom / Ollama',
          url: '$base/chat/completions',
          apiKey: settings.customApiKey.trim(),
          model: settings.customApiModel.trim(),
          method: RoxumToolCallingMethod.openAiCompatible,
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
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return const [];
    final modelsUrl = trimmed.endsWith('/models') ? trimmed : '$trimmed/models';
    final res = await http
        .get(
          Uri.parse(modelsUrl),
          headers: {
            'Content-Type': 'application/json',
            if (apiKey.trim().isNotEmpty)
              'Authorization': 'Bearer ${apiKey.trim()}',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
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
    return ids;
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

        final payload = _buildPayload(
          model: model,
          messages: messages,
          tools: tools,
        );
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
        final turn = _parseResponse(model.method, decoded);
        if (turn.usage.totalTokens > 0 || turn.usage.costUsd > 0) {
          onUsage?.call(turn.usage);
        }

        if (turn.text.isNotEmpty) {
          onAssistantText(turn.text);
        }

        if (turn.toolCalls.isEmpty || agenticTools == null) {
          return turn.text;
        }

        messages.add(turn.rawAssistantMessage);

        for (final call in turn.toolCalls) {
          if (isCancelled()) return turn.text;

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
