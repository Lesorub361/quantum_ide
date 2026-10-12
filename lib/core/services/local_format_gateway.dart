import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Local loopback proxy that translates Anthropic Messages API requests into
/// OpenAI-compatible Chat Completion requests and formats the responses back.
///
/// This allows CLI agents like Claude Code to seamlessly run against DeepSeek,
/// OpenRouter, Groq, Ollama, LM Studio, and any OpenAI-compatible API.
class LocalFormatGateway {
  final String upstreamBaseUrl;
  final List<String> upstreamApiKeys;
  final String targetModel;
  final Map<String, String> extraHeaders;

  int _activeKeyIndex = 0;
  HttpServer? _server;
  final HttpClient _client = HttpClient();
  bool _isRunning = false;

  LocalFormatGateway({
    required this.upstreamBaseUrl,
    required dynamic upstreamApiKey,
    required this.targetModel,
    this.extraHeaders = const {},
  }) : upstreamApiKeys = _parseKeys(upstreamApiKey);

  static List<String> _parseKeys(dynamic input) {
    if (input is List<String>) {
      return input.where((k) => k.trim().isNotEmpty).toList();
    }
    if (input is String) {
      return input.split(RegExp(r'[,;\n]')).map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    }
    return [];
  }

  String get upstreamApiKey => upstreamApiKeys.isNotEmpty
      ? upstreamApiKeys[_activeKeyIndex % upstreamApiKeys.length]
      : '';

  bool get isRunning => _isRunning;

  String get url {
    if (_server == null) {
      throw StateError('LocalFormatGateway is not running. Call start() first.');
    }
    return 'http://127.0.0.1:${_server!.port}';
  }

  /// Starts the gateway on an ephemeral loopback port
  Future<LocalFormatGateway> start() async {
    if (_isRunning) return this;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _isRunning = true;
    final keysCount = upstreamApiKeys.length;
    debugPrint('LocalFormatGateway: Listening on $url -> $upstreamBaseUrl ($targetModel, $keysCount keys in pool)');

    _server!.listen(
      _handleRequest,
      onError: (err) {
        debugPrint('LocalFormatGateway error: $err');
      },
    );

    return this;
  }

  /// Stops the gateway and frees the port
  Future<void> stop() async {
    _isRunning = false;
    _client.close(force: true);
    await _server?.close(force: true);
    _server = null;
    debugPrint('LocalFormatGateway: Stopped');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    // 1. Token count endpoint
    if (path.endsWith('/count_tokens')) {
      final body = await utf8.decoder.bind(request).join();
      final approxTokens = (body.length / 4).ceil() + 1;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'input_tokens': approxTokens}));
      await request.response.close();
      return;
    }

    // 2. Models discovery endpoint
    if (path.endsWith('/models')) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': [
            {'id': targetModel, 'object': 'model'},
          ],
        }));
      await request.response.close();
      return;
    }

    // 3. Messages endpoint
    if (path.endsWith('/messages')) {
      try {
        final bodyStr = await utf8.decoder.bind(request).join();
        if (bodyStr.trim().isEmpty) {
          _sendError(request, HttpStatus.badRequest, 'Empty request body');
          return;
        }

        final anthropicReq = jsonDecode(bodyStr) as Map<String, dynamic>;
        final isStreaming = anthropicReq['stream'] == true;

        final openAiPayload = _anthropicToOpenAi(anthropicReq);

        if (isStreaming) {
          await _handleStreamingRequest(request, openAiPayload);
        } else {
          await _handleUnaryRequest(request, openAiPayload, anthropicReq);
        }
      } catch (e, stack) {
        debugPrint('LocalFormatGateway handler error: $e\n$stack');
        _sendError(request, HttpStatus.internalServerError, 'Gateway translation error: $e');
      }
      return;
    }

    _sendError(request, HttpStatus.notFound, 'Endpoint not supported: $path');
  }

  /// Translates Anthropic messages format to OpenAI Chat Completion format
  Map<String, dynamic> _anthropicToOpenAi(Map<String, dynamic> source) {
    final messages = <Map<String, dynamic>>[];

    // Extract system prompt
    final system = source['system'];
    if (system != null) {
      if (system is String && system.trim().isNotEmpty) {
        messages.add({'role': 'system', 'content': system.trim()});
      } else if (system is List) {
        final sysParts = <String>[];
        for (final item in system) {
          if (item is Map && item['type'] == 'text') {
            sysParts.add(item['text']?.toString() ?? '');
          } else if (item is String) {
            sysParts.add(item);
          }
        }
        if (sysParts.isNotEmpty) {
          messages.add({'role': 'system', 'content': sysParts.join('\n\n')});
        }
      }
    }

    // Process conversation turns
    final rawMessages = source['messages'] as List? ?? [];
    for (final raw in rawMessages) {
      if (raw is! Map) continue;
      final role = raw['role']?.toString() ?? 'user';
      final content = raw['content'];

      if (content is String) {
        messages.add({'role': role, 'content': content});
        continue;
      }

      if (content is List) {
        final textParts = <String>[];
        final toolCalls = <Map<String, dynamic>>[];

        for (final block in content) {
          if (block is! Map) continue;
          final type = block['type']?.toString();

          if (type == 'text') {
            textParts.add(block['text']?.toString() ?? '');
          } else if (type == 'tool_use') {
            toolCalls.add({
              'id': block['id'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
              'type': 'function',
              'function': {
                'name': block['name'] ?? '',
                'arguments': jsonEncode(block['input'] ?? {}),
              },
            });
          } else if (type == 'tool_result') {
            // Anthropic puts tool_result as a content block in a user turn
            final callId = block['tool_use_id']?.toString() ?? '';
            var resultStr = '';
            final blockContent = block['content'];
            if (blockContent is String) {
              resultStr = blockContent;
            } else if (blockContent is List) {
              resultStr = blockContent
                  .map((e) => (e is Map && e['type'] == 'text') ? (e['text'] ?? '') : e.toString())
                  .join('\n');
            } else if (blockContent != null) {
              resultStr = jsonEncode(blockContent);
            }

            messages.add({
              'role': 'tool',
              'tool_call_id': callId,
              'content': resultStr,
            });
          }
        }

        if (role == 'assistant') {
          final assistantTurn = <String, dynamic>{
            'role': 'assistant',
            'content': textParts.join('\n'),
          };
          if (toolCalls.isNotEmpty) {
            assistantTurn['tool_calls'] = toolCalls;
          }
          messages.add(assistantTurn);
        } else if (role == 'user' && textParts.isNotEmpty) {
          messages.add({
            'role': 'user',
            'content': textParts.join('\n'),
          });
        }
      }
    }

    final targetPayload = <String, dynamic>{
      'model': targetModel,
      'messages': messages,
    };

    if (source.containsKey('max_tokens')) {
      targetPayload['max_tokens'] = source['max_tokens'];
    }
    if (source.containsKey('temperature')) {
      targetPayload['temperature'] = source['temperature'];
    }
    if (source['stream'] == true) {
      targetPayload['stream'] = true;
    }

    // Convert tools
    final tools = source['tools'] as List?;
    if (tools != null && tools.isNotEmpty) {
      final openAiTools = <Map<String, dynamic>>[];
      for (final t in tools) {
        if (t is! Map) continue;
        openAiTools.add({
          'type': 'function',
          'function': {
            'name': t['name'] ?? '',
            'description': t['description'] ?? '',
            'parameters': t['input_schema'] ?? {},
          },
        });
      }
      if (openAiTools.isNotEmpty) {
        targetPayload['tools'] = openAiTools;
      }
    }

    return targetPayload;
  }

  /// Handles non-streaming requests using dart:io HttpClient
  Future<void> _handleUnaryRequest(
    HttpRequest request,
    Map<String, dynamic> openAiPayload,
    Map<String, dynamic> originalAnthropicReq,
  ) async {
    final upstreamUri = Uri.parse(_normalizeEndpoint(upstreamBaseUrl));
    final encoded = utf8.encode(jsonEncode(openAiPayload));

    HttpClientResponse? upstreamResp;
    String respBody = '';
    final maxAttempts = upstreamApiKeys.isNotEmpty ? upstreamApiKeys.length : 1;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final currentKey = upstreamApiKey;
      final clientReq = await _client.postUrl(upstreamUri);
      clientReq.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (currentKey.isNotEmpty) {
        clientReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $currentKey');
      }
      extraHeaders.forEach((k, v) => clientReq.headers.set(k, v));
      clientReq.contentLength = encoded.length;
      clientReq.add(encoded);

      upstreamResp = await clientReq.close();
      respBody = await utf8.decoder.bind(upstreamResp).join();

      final code = upstreamResp.statusCode;
      if ((code == 429 || code == 401 || code == 403) && upstreamApiKeys.length > 1 && attempt < maxAttempts - 1) {
        debugPrint('LocalFormatGateway: HTTP $code on key #$_activeKeyIndex. Rotating to next key in pool...');
        _activeKeyIndex = (_activeKeyIndex + 1) % upstreamApiKeys.length;
        continue;
      }
      break;
    }

    if (upstreamResp == null || upstreamResp.statusCode < 200 || upstreamResp.statusCode >= 300) {
      request.response
        ..statusCode = upstreamResp?.statusCode ?? HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(respBody);
      await request.response.close();
      return;
    }

    final upstreamJson = jsonDecode(respBody) as Map<String, dynamic>;
    final anthropicResponse = _openAiToAnthropic(upstreamJson, originalAnthropicReq);

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(anthropicResponse));
    await request.response.close();
  }

  /// Converts OpenAI non-streaming response to Anthropic message format
  Map<String, dynamic> _openAiToAnthropic(
    Map<String, dynamic> openAiResp,
    Map<String, dynamic> anthropicReq,
  ) {
    final choices = openAiResp['choices'] as List? ?? [];
    final firstChoice = choices.isNotEmpty ? choices.first as Map<String, dynamic> : <String, dynamic>{};
    final msg = firstChoice['message'] as Map<String, dynamic>? ?? {};

    final contentBlocks = <Map<String, dynamic>>[];

    final text = msg['content']?.toString();
    if (text != null && text.isNotEmpty) {
      contentBlocks.add({
        'type': 'text',
        'text': text,
      });
    }

    final toolCalls = msg['tool_calls'] as List?;
    if (toolCalls != null) {
      for (final call in toolCalls) {
        if (call is! Map) continue;
        final fn = call['function'] as Map? ?? {};
        final name = fn['name']?.toString() ?? '';
        final argsRaw = fn['arguments']?.toString() ?? '{}';
        Map<String, dynamic> parsedArgs = {};
        try {
          parsedArgs = jsonDecode(argsRaw) as Map<String, dynamic>;
        } catch (_) {}

        contentBlocks.add({
          'type': 'tool_use',
          'id': call['id']?.toString() ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
          'name': name,
          'input': parsedArgs,
        });
      }
    }

    final finishReason = firstChoice['finish_reason']?.toString();
    String stopReason = 'end_turn';
    if (finishReason == 'tool_calls' || finishReason == 'function_call') {
      stopReason = 'tool_use';
    } else if (finishReason == 'length') {
      stopReason = 'max_tokens';
    }

    final usage = openAiResp['usage'] as Map<String, dynamic>? ?? {};
    final inputTokens = usage['prompt_tokens'] as int? ?? 0;
    final outputTokens = usage['completion_tokens'] as int? ?? 0;

    return {
      'id': openAiResp['id']?.toString() ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'type': 'message',
      'role': 'assistant',
      'model': anthropicReq['model'] ?? targetModel,
      'content': contentBlocks,
      'stop_reason': stopReason,
      'stop_sequence': null,
      'usage': {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
      },
    };
  }

  /// Handles streaming requests and translates SSE streams on the fly
  Future<void> _handleStreamingRequest(
    HttpRequest request,
    Map<String, dynamic> openAiPayload,
  ) async {
    final upstreamUri = Uri.parse(_normalizeEndpoint(upstreamBaseUrl));
    final encoded = utf8.encode(jsonEncode(openAiPayload));

    HttpClientResponse? upstreamResp;
    String errBody = '';
    final maxAttempts = upstreamApiKeys.isNotEmpty ? upstreamApiKeys.length : 1;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final currentKey = upstreamApiKey;
      final clientReq = await _client.postUrl(upstreamUri);
      clientReq.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (currentKey.isNotEmpty) {
        clientReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $currentKey');
      }
      extraHeaders.forEach((k, v) => clientReq.headers.set(k, v));
      clientReq.contentLength = encoded.length;
      clientReq.add(encoded);

      upstreamResp = await clientReq.close();

      final code = upstreamResp.statusCode;
      if ((code == 429 || code == 401 || code == 403) && upstreamApiKeys.length > 1 && attempt < maxAttempts - 1) {
        debugPrint('LocalFormatGateway: Streaming HTTP $code on key #$_activeKeyIndex. Rotating to next key in pool...');
        _activeKeyIndex = (_activeKeyIndex + 1) % upstreamApiKeys.length;
        await upstreamResp.drain();
        continue;
      }

      if (code < 200 || code >= 300) {
        errBody = await utf8.decoder.bind(upstreamResp).join();
      }
      break;
    }

    if (upstreamResp == null || upstreamResp.statusCode < 200 || upstreamResp.statusCode >= 300) {
      request.response
        ..statusCode = upstreamResp?.statusCode ?? HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(errBody);
      await request.response.close();
      return;
    }

    // Set SSE headers
    request.response.headers.set('Content-Type', 'text/event-stream; charset=utf-8');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');

    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    // 1. message_start event
    _writeSseEvent(request.response, 'message_start', {
      'type': 'message_start',
      'message': {
        'id': msgId,
        'type': 'message',
        'role': 'assistant',
        'model': targetModel,
        'content': [],
        'stop_reason': null,
        'usage': {'input_tokens': 1, 'output_tokens': 0},
      },
    });

    int currentBlockIndex = 0;
    bool hasTextBlock = false;
    final activeToolCalls = <int, Map<String, dynamic>>{};

    final lines = upstreamResp
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final dataStr = line.substring(6).trim();
      if (dataStr == '[DONE]') break;

      Map<String, dynamic> chunk;
      try {
        chunk = jsonDecode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final choices = chunk['choices'] as List? ?? [];
      if (choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'] as Map<String, dynamic>? ?? {};

      // Text delta
      final contentText = delta['content']?.toString();
      if (contentText != null && contentText.isNotEmpty) {
        if (!hasTextBlock) {
          _writeSseEvent(request.response, 'content_block_start', {
            'type': 'content_block_start',
            'index': currentBlockIndex,
            'content_block': {'type': 'text', 'text': ''},
          });
          hasTextBlock = true;
        }

        _writeSseEvent(request.response, 'content_block_delta', {
          'type': 'content_block_delta',
          'index': currentBlockIndex,
          'delta': {'type': 'text_delta', 'text': contentText},
        });
      }

      // Tool call deltas
      final toolCalls = delta['tool_calls'] as List?;
      if (toolCalls != null) {
        if (hasTextBlock) {
          _writeSseEvent(request.response, 'content_block_stop', {
            'type': 'content_block_stop',
            'index': currentBlockIndex,
          });
          currentBlockIndex++;
          hasTextBlock = false;
        }

        for (final call in toolCalls) {
          if (call is! Map) continue;
          final toolIndex = call['index'] as int? ?? 0;
          final callId = call['id']?.toString();
          final fn = call['function'] as Map? ?? {};
          final name = fn['name']?.toString();
          final argsChunk = fn['arguments']?.toString();

          if (callId != null && name != null) {
            final blockIdx = currentBlockIndex++;
            activeToolCalls[toolIndex] = {'blockIndex': blockIdx, 'id': callId, 'name': name};
            _writeSseEvent(request.response, 'content_block_start', {
              'type': 'content_block_start',
              'index': blockIdx,
              'content_block': {'type': 'tool_use', 'id': callId, 'name': name, 'input': {}},
            });
          }

          if (argsChunk != null && argsChunk.isNotEmpty) {
            final toolInfo = activeToolCalls[toolIndex];
            if (toolInfo != null) {
              _writeSseEvent(request.response, 'content_block_delta', {
                'type': 'content_block_delta',
                'index': toolInfo['blockIndex'],
                'delta': {'type': 'input_json_delta', 'partial_json': argsChunk},
              });
            }
          }
        }
      }
    }

    // Close any open blocks
    if (hasTextBlock) {
      _writeSseEvent(request.response, 'content_block_stop', {
        'type': 'content_block_stop',
        'index': currentBlockIndex,
      });
    }
    for (final info in activeToolCalls.values) {
      _writeSseEvent(request.response, 'content_block_stop', {
        'type': 'content_block_stop',
        'index': info['blockIndex'],
      });
    }

    // End message
    _writeSseEvent(request.response, 'message_delta', {
      'type': 'message_delta',
      'delta': {
        'stop_reason': activeToolCalls.isNotEmpty ? 'tool_use' : 'end_turn',
        'stop_sequence': null,
      },
      'usage': {'output_tokens': 10},
    });

    _writeSseEvent(request.response, 'message_stop', {
      'type': 'message_stop',
    });

    await request.response.close();
  }

  void _writeSseEvent(HttpResponse response, String eventName, Map<String, dynamic> data) {
    response.write('event: $eventName\ndata: ${jsonEncode(data)}\n\n');
  }

  String _normalizeEndpoint(String base) {
    var b = base.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.endsWith('/chat/completions')) {
      if (b.endsWith('/v1')) {
        b = '$b/chat/completions';
      } else {
        b = '$b/v1/chat/completions';
      }
    }
    return b;
  }

  void _sendError(HttpRequest request, int code, String msg) {
    request.response
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'type': 'error',
        'error': {'type': 'api_error', 'message': msg},
      }));
    request.response.close();
  }
}
