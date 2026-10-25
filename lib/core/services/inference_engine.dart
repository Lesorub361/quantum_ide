import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Whether the current platform supports local inference (via HTTP/CLI server).
bool get supportsLocalInference => !kIsWeb;

/// Context window usage info.
class ContextInfo {
  final int tokensUsed;
  final int contextSize;

  const ContextInfo({
    required this.tokensUsed,
    required this.contextSize,
  });
}

/// Result from model loading.
class LoadResult {
  final bool success;
  final String message;
  final String gpuName;
  final int gpuLayers;
  final String runtime;
  final String backend;

  LoadResult({
    required this.success,
    required this.message,
    this.gpuName = '',
    this.gpuLayers = 0,
    this.runtime = '',
    this.backend = '',
  });
}

/// Lightweight local inference engine powered by HTTP / CLI (`llama-server` or `ollama serve`)
/// without compiling heavy C++ `llama.cpp` sources into the Flutter APK.
class InferenceEngine {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  Process? _serverProcess;
  CancelToken? _activeCancelToken;
  String _activeServerUrl = 'http://127.0.0.1:8080';
  bool _isOllamaBackend = false;
  String _loadedModelPath = '';
  int _contextSize = 4096;
  int _tokensUsed = 0;
  bool _disposed = false;

  Future<LoadResult> loadModel({
    required String modelPath,
    String? modelRuntime,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    String liteRtPerformanceMode = 'auto_fast',
    bool forceLiteRtCpu = false,
    bool clearLiteRtCache = false,
    bool enableLiteRtVision = false,
    void Function(double)? onProgress,
  }) async {
    if (kIsWeb) {
      return LoadResult(
        success: false,
        message: 'Local inference is not supported on Web.',
      );
    }

    _disposed = false;
    _contextSize = contextSize;
    _loadedModelPath = modelPath;
    onProgress?.call(0.15);

    // 1. Check if Ollama is already running on 127.0.0.1:11434
    if (await _isEndpointAlive('http://127.0.0.1:11434/api/tags')) {
      _activeServerUrl = 'http://127.0.0.1:11434';
      _isOllamaBackend = true;
      onProgress?.call(1.0);
      return LoadResult(
        success: true,
        message: 'Подключено к локальному серверу Ollama (127.0.0.1:11434).',
        runtime: 'ollama',
        backend: 'cpu',
      );
    }

    // 2. Check if llama-server is already running on 127.0.0.1:8080
    if (await _isEndpointAlive('http://127.0.0.1:8080/health') ||
        await _isEndpointAlive('http://127.0.0.1:8080/v1/models')) {
      _activeServerUrl = 'http://127.0.0.1:8080';
      _isOllamaBackend = false;
      onProgress?.call(1.0);
      return LoadResult(
        success: true,
        message: 'Подключено к локальному серверу llama-server (127.0.0.1:8080).',
        runtime: 'llama-server',
        backend: 'cpu',
      );
    }

    onProgress?.call(0.4);

    // 3. Attempt to launch llama-server with the downloaded GGUF file if binary is installed
    final binCandidates = [
      '/usr/local/bin/llama-server',
      '/usr/bin/llama-server',
      '/root/.local/bin/llama-server',
      'llama-server',
    ];

    String? foundBinary;
    for (final candidate in binCandidates) {
      try {
        if (candidate.startsWith('/')) {
          if (File(candidate).existsSync()) {
            foundBinary = candidate;
            break;
          }
        } else {
          final whichRes = await Process.run('which', [candidate]);
          if (whichRes.exitCode == 0 &&
              whichRes.stdout.toString().trim().isNotEmpty) {
            foundBinary = whichRes.stdout.toString().trim();
            break;
          }
        }
      } catch (_) {}
    }

    if (foundBinary != null && File(modelPath).existsSync()) {
      try {
        await _stopServerProcess();
        final threads = (Platform.numberOfProcessors > 2)
            ? (Platform.numberOfProcessors - 1).clamp(2, 6)
            : 2;

        final hasVulkan = File('/system/lib64/libvulkan.so').existsSync() ||
            File('/usr/lib/aarch64-linux-gnu/libvulkan.so').existsSync() ||
            File('/usr/lib/libvulkan.so').existsSync() ||
            File('/vendor/lib64/hw/vulkan.adreno.so').existsSync() ||
            File('/vendor/lib64/hw/vulkan.mali.so').existsSync();

        final serverArgs = [
          '-m',
          modelPath,
          '-c',
          '$contextSize',
          '-t',
          '$threads',
          '--host',
          '127.0.0.1',
          '--port',
          '8080',
          if (hasVulkan) ...['-ngl', '33'],
        ];

        _serverProcess = await Process.start(
          foundBinary,
          serverArgs,
        );

        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          onProgress?.call((0.4 + (i * 0.03)).clamp(0.4, 0.95));
          if (await _isEndpointAlive('http://127.0.0.1:8080/health') ||
              await _isEndpointAlive('http://127.0.0.1:8080/v1/models')) {
            _activeServerUrl = 'http://127.0.0.1:8080';
            _isOllamaBackend = false;
            onProgress?.call(1.0);
            return LoadResult(
              success: true,
              message: 'Запущен локальный llama-server (${hasVulkan ? "Vulkan GPU + " : ""}$threads потоков CPU).',
              runtime: 'llama-server',
              backend: hasVulkan ? 'vulkan' : 'cpu',
            );
          }
        }
      } catch (e) {
        debugPrint('[InferenceEngine] Failed to start llama-server: $e');
      }
    }

    return LoadResult(
      success: false,
      message:
          'Локальный ИИ-сервер (Ollama или llama-server) не запущен.\n'
          'Откройте Настройки → ИИ и локальные модели, чтобы запустить Ollama или llama-server в 1 клик без компиляции исходного кода.',
    );
  }

  Future<bool> _isEndpointAlive(String url) async {
    try {
      final resp = await _dio.get(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: const Duration(seconds: 2),
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> generate({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required String modelName,
    required int maxTokens,
    required double temperature,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    if (_disposed) return 'Error: Engine disposed';

    _activeCancelToken?.cancel();
    _activeCancelToken = CancelToken();

    final messages = <Map<String, String>>[
      if (systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
      if (conversationHistory != null)
        ...conversationHistory.where(
          (m) => (m['content'] ?? '').trim().isNotEmpty,
        ),
      {'role': 'user', 'content': prompt},
    ];

    final endpoint = _isOllamaBackend
        ? '$_activeServerUrl/v1/chat/completions'
        : '$_activeServerUrl/v1/chat/completions';

    final buffer = StringBuffer();

    try {
      final response = await _dio.post<ResponseBody>(
        endpoint,
        cancelToken: _activeCancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Content-Type': 'application/json'},
        ),
        data: jsonEncode({
          'model': modelName.isNotEmpty ? modelName : 'local-model',
          'messages': messages,
          'max_tokens': maxTokens,
          'temperature': temperature,
          'stream': true,
        }),
      );

      final stream = response.data?.stream;
      if (stream == null) {
        return 'Error: Empty response stream from local server';
      }

      String lineBuf = '';
      await for (final chunk in stream) {
        lineBuf += utf8.decode(chunk, allowMalformed: true);
        final lines = lineBuf.split('\n');
        lineBuf = lines.removeLast();

        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (!line.startsWith('data:')) continue;
          final dataStr = line.substring(5).trim();
          if (dataStr == '[DONE]' || dataStr.isEmpty) continue;

          try {
            final json = jsonDecode(dataStr) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices.first['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                buffer.write(content);
                onToken?.call(content);
              }
            }
          } catch (_) {}
        }
      }

      final result = buffer.toString();
      _tokensUsed = (result.length ~/ 4).clamp(1, _contextSize);
      return result;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        return buffer.toString();
      }
      return 'ERROR: Local AI server request failed — $e';
    }
  }

  Future<void> stop() async {
    _activeCancelToken?.cancel('Stopped by user');
    _activeCancelToken = null;
  }

  Future<void> resetConversation() async {
    _tokensUsed = 0;
  }

  Future<ContextInfo?> getContextInfo() async {
    if (_loadedModelPath.isEmpty) return null;
    return ContextInfo(
      tokensUsed: _tokensUsed,
      contextSize: _contextSize,
    );
  }

  Future<void> _stopServerProcess() async {
    try {
      _serverProcess?.kill(ProcessSignal.sigterm);
    } catch (_) {}
    _serverProcess = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _stopServerProcess();
    _dio.close();
  }
}
