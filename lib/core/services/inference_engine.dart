import 'dart:async';
import 'dart:io' show Platform, Directory;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_litert_lm/flutter_litert_lm.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Whether the current platform supports local inference.
bool get supportsLocalInference => Platform.isAndroid || Platform.isIOS;

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

/// Android & iOS inference engine — wraps llama_flutter_android.
class InferenceEngine {
  LlamaController? _controller;
  LiteLmEngine? _liteEngine;
  LiteLmConversation? _liteConversation;
  StreamSubscription? _subscription;
  StreamSubscription? _loadProgressSub;
  Timer? _idleTimer;
  void Function()? _onStop;
  bool _isLiteRt = false;
  bool _disposed = false;
  bool _hasLoadedModel = false;
  String? _liteConversationSystemPrompt;
  double? _liteConversationTemperature;
  bool _liteConversationHasMessages = false;

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
    // ── Platform Guard ─────────────────────────────────────────────────────
    // Native inference (llama_flutter_android / flutter_litert_lm) is only
    // available on Android/iOS. Return a graceful error on desktop so the app
    // never crashes due to a missing native library.
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return LoadResult(
        success: false,
        message: 'Local inference is not supported on this platform.\n'
            'On desktop, use llama-server via the Models sidebar panel.',
      );
    }

    _disposed = false;
    final runtime = _runtimeFor(modelPath, modelRuntime);
    if (runtime == 'litert') {
      return _loadLiteRtModel(
        modelPath,
        contextSize: contextSize,
        performanceMode: liteRtPerformanceMode,
        forceCpu: forceLiteRtCpu,
        clearCache: clearLiteRtCache,
        enableVision: enableLiteRtVision,
        onProgress: onProgress,
      );
    }

    _isLiteRt = false;
    _controller = LlamaController();

    // ── GPU Detection ──
    int gpuLayers = 0;
    String gpuNameStr = '';

    if (!forceLiteRtCpu) {
      try {
        final gpu = await _controller!.detectGpu();
        gpuNameStr = gpu.gpuName;

        debugPrint('[Inference] GPU: ${gpu.gpuName}');
        debugPrint('[Inference]   Vulkan: ${gpu.vulkanSupported}');
        debugPrint('[Inference]   Free RAM: ${gpu.freeRamBytes ~/ 1024 ~/ 1024}MB');
        debugPrint('[Inference]   Recommended layers: ${gpu.recommendedGpuLayers}');

        if (gpu.vulkanSupported && gpu.recommendedGpuLayers > 0) {
          final gpuNum = _extractGpuModel(gpu.gpuName);
          if (gpuNum >= 700) {
            gpuLayers = 99;
            debugPrint('[Inference] ✓ High-end GPU ($gpuNum) → full offload');
          } else if (gpuNum >= 650) {
            gpuLayers = gpu.recommendedGpuLayers;
            debugPrint('[Inference] ✓ Upper-mid GPU ($gpuNum) → $gpuLayers layers');
          } else {
            gpuLayers = 0;
            debugPrint(
                '[Inference] Mid-range GPU ($gpuNum) — CPU is faster, skipping GPU');
          }
        }
      } catch (e) {
        debugPrint('[Inference] GPU detection failed: $e — CPU fallback');
      }
    } else {
      debugPrint('[Inference] CPU Safe Mode selected — bypassing Vulkan/GPU detection entirely');
    }

    // ── Thread Tuning ──
    int threads;
    if (gpuLayers > 0) {
      threads = deviceTier == 'ultra'
          ? 4
          : deviceTier == 'high'
              ? 4
              : 4;
    } else {
      threads = deviceTier == 'ultra'
          ? 6
          : deviceTier == 'high'
              ? 5
              : deviceTier == 'mid'
                  ? 4
                  : 3;
    }

    // Google Tensor SoC (Pixel 6/7/8) has known Q4_K_M dequant bugs
    // that corrupt logits at >1 thread on Gemma models. Force single-threaded
    // to eliminate KV cache races in the quantization dot-product path.
    final modelName = modelPath.toLowerCase();
    if (isTensorSoC && modelName.contains('gemma')) {
      threads = 1;
      debugPrint(
          '[Inference] Tensor SoC + Gemma detected — forcing single-threaded inference');
    }

    // ── Load Progress ──
    await _loadProgressSub?.cancel();
    _loadProgressSub = null;
    try {
      _loadProgressSub = _controller!.loadProgress.listen((progress) {
        onProgress?.call(_normalizeProgress(progress));
      });
    } catch (_) {}

    // ── Load ──
    await _controller!.loadModel(
      modelPath: modelPath,
      threads: threads,
      contextSize: contextSize,
      gpuLayers: gpuLayers,
    );
    _hasLoadedModel = true;

    final accel = gpuLayers > 0
        ? 'GPU ($gpuLayers layers, $gpuNameStr)'
        : 'CPU ($threads threads)';
    debugPrint('[Inference] ✓ Model loaded: $accel, ctx=$contextSize');

    return LoadResult(
      success: true,
      message: 'Model loaded ($accel).',
      gpuName: gpuNameStr,
      gpuLayers: gpuLayers,
      runtime: 'llama',
      backend: gpuLayers > 0 ? 'gpu' : 'cpu',
    );
  }

  Future<LoadResult> _loadLiteRtModel(
    String modelPath, {
    required int contextSize,
    required String performanceMode,
    required bool forceCpu,
    required bool clearCache,
    required bool enableVision,
    void Function(double)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
          'LiteRT-LM is enabled for Android only in this app.');
    }

    _isLiteRt = true;
    _controller = null;

    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/litert_cache');
    final backend = forceCpu || performanceMode == 'cpu_safe'
        ? LiteLmBackend.cpu
        : LiteLmBackend.gpu;
    final backendLabel = backend == LiteLmBackend.gpu ? 'GPU' : 'CPU';

    try {
      onProgress?.call(0.05);
      if (clearCache && await cacheDir.exists()) {
        try {
          await cacheDir.delete(recursive: true);
        } catch (_) {}
      }
      await cacheDir.create(recursive: true);
      onProgress?.call(0.18);

      _liteEngine = await _createLiteRtEngine(
        modelPath: modelPath,
        contextSize: contextSize,
        cacheDir: cacheDir.path,
        backend: backend,
        enableVision: enableVision,
      );
      _hasLoadedModel = true;
      onProgress?.call(0.92);
      debugPrint(
          '[Inference] LiteRT-LM loaded with $backendLabel backend, ctx=$contextSize');
      return LoadResult(
        success: true,
        message: 'LiteRT-LM model loaded ($backendLabel backend).',
        gpuName: backend == LiteLmBackend.gpu ? 'LiteRT GPU' : '',
        gpuLayers: backend == LiteLmBackend.gpu ? 1 : 0,
        runtime: 'litert',
        backend: backend.name,
      );
    } catch (error) {
      debugPrint('[Inference] LiteRT-LM load failed: $error');
      final errorStr = error.toString();
      if (errorStr.contains('TF_LITE_VISION_ENCODER')) {
        return LoadResult(
          success: false,
          message:
              'This LiteRT-LM file is text-only, but it was loaded as a vision model. Turn off Vision for this model or re-import it as a normal chat model.',
        );
      }
      if (enableVision && errorStr.contains('exactly one signature but got')) {
        debugPrint(
            '[Inference] Vision encoder signature mismatch. Falling back to text-only mode.');
        try {
          _liteEngine = await _createLiteRtEngine(
            modelPath: modelPath,
            contextSize: contextSize,
            cacheDir: cacheDir.path,
            backend: backend,
            enableVision: false,
          );
          _hasLoadedModel = true;
          onProgress?.call(0.92);
          return LoadResult(
            success: true,
            message:
                'Model loaded in text-only mode. Its vision features are incompatible with the LiteRT engine (expected 1 signature, found multiple).',
            gpuName: backend == LiteLmBackend.gpu ? 'LiteRT GPU' : '',
            gpuLayers: backend == LiteLmBackend.gpu ? 1 : 0,
            runtime: 'litert',
            backend: backend.name,
          );
        } catch (fallbackError) {
          debugPrint('[Inference] LiteRT-LM fallback load failed: $fallbackError');
          return LoadResult(
            success: false,
            message: 'LiteRT load failed: $fallbackError',
          );
        }
      }
      if (errorStr.contains('exactly one signature but got')) {
        return LoadResult(
          success: false,
          message:
              'This vision model is incompatible with the LiteRT engine (expected 1 signature, found multiple). Please try a standard GGUF model or a text-only LiteRT model instead.',
        );
      }
      rethrow;
    }
  }

  Future<LiteLmEngine> _createLiteRtEngine({
    required String modelPath,
    required int contextSize,
    required String cacheDir,
    required LiteLmBackend backend,
    required bool enableVision,
  }) {
    return LiteLmEngine.create(
      LiteLmEngineConfig(
        modelPath: modelPath,
        backend: backend,
        cacheDir: cacheDir,
        visionBackend: enableVision ? LiteLmBackend.cpu : null,
        audioBackend: null,
      ),
    );
  }

  double _normalizeProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) return 0.0;
    final normalized = progress > 1 ? progress / 100 : progress;
    return normalized.clamp(0.0, 1.0).toDouble();
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
    if (_isLiteRt) {
      return _generateLiteRt(
        prompt: prompt,
        conversationHistory: conversationHistory,
        systemPrompt: systemPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        imagePath: imagePath,
        audioPath: audioPath,
        onToken: onToken,
      );
    }

    if (_controller == null) throw Exception('No model loaded');
    if (imagePath != null && imagePath.isNotEmpty) {
      return 'GGUF image input is not available in this build yet. This llama runtime is text-only right now: it does not load a matching mmproj vision projector or send image pixels into llama.cpp. Use a LiteRT vision model for image understanding.';
    }
    if (audioPath != null && audioPath.isNotEmpty) {
      return 'GGUF audio input is not available in this build yet. Text files can be read when their content is attached, but audio needs a model/runtime path that supports audio input.';
    }

    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () {
      finish(buffer.toString());
    };

    // ── Use generateChat() for native template handling ──
    Stream<String>? stream;
    try {
      final messages =
          _buildChatMessages(prompt, conversationHistory, systemPrompt);
      stream = _controller!.generateChat(
        messages: messages,
        template: null,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: 0.9,
        topK: 40,
        minP: 0.05,
        repeatPenalty: 1.1,
        repeatLastN: 64,
      );
      debugPrint('[Inference] generateChat() started (${messages.length} messages)');
    } catch (e) {
      debugPrint('[Inference] generateChat() failed: $e — fallback to generate()');
      try {
        await _controller!.stop();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
      final fullPrompt =
          _buildPrompt(prompt, conversationHistory, systemPrompt, modelName);
      stream = _controller!.generate(
        prompt: fullPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: 0.9,
        topK: 40,
        minP: 0.05,
        repeatPenalty: 1.1,
        repeatLastN: 64,
      );
    }

    int tokenCount = 0;
    _subscription = stream.listen(
      (token) {
        if (tokenCount == 0) {
          debugPrint('[Inference] ✓ FIRST TOKEN received! Prefill done.');
        }
        final clean = _sanitizeGemmaGarbage(token);
        if (clean.isEmpty) return;
        buffer.write(clean);
        tokenCount++;
        onToken?.call(clean);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () {
          debugPrint('[Inference] Idle timeout — $tokenCount tokens');
          finish(buffer.toString());
        });
      },
      onDone: () {
        debugPrint('[Inference] Stream onDone — $tokenCount tokens total');
        finish(buffer.toString());
      },
      onError: (error) {
        debugPrint('[Inference] Stream error: $error');
        finish('ERROR: Generation failed — $error');
      },
    );

    // Prefill timeout
    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (tokenCount == 0) {
        finish(
            'ERROR: Model did not respond. Try a smaller model or shorter conversation.');
      }
    });

    // Hard timeout
    Future.delayed(const Duration(seconds: 180), () {
      if (!completed) {
        final partial = buffer.toString();
        finish(partial.isEmpty ? 'ERROR: Generation timed out.' : partial);
      }
    });

    return await completer.future;
  }

  Future<String> _generateLiteRt({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required int maxTokens,
    required double temperature,
    String? imagePath,
    String? audioPath,
    void Function(String token)? onToken,
  }) async {
    if (_liteEngine == null) throw Exception('No LiteRT-LM model loaded');

    await _subscription?.cancel();
    await _ensureLiteRtConversation(
      prompt: prompt,
      conversationHistory: conversationHistory,
      systemPrompt: systemPrompt,
      temperature: temperature,
    );

    final completer = Completer<String>();
    final buffer = StringBuffer();
    bool completed = false;
    bool hasVisibleOutput = false;
    var tokenCount = 0;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () => finish(buffer.toString());

    if ((imagePath != null && imagePath.isNotEmpty) ||
        (audioPath != null && audioPath.isNotEmpty)) {
      final contents = <LiteLmContent>[
        LiteLmContent.text(prompt),
        if (imagePath != null && imagePath.isNotEmpty)
          LiteLmContent.imageFile(imagePath),
        if (audioPath != null && audioPath.isNotEmpty)
          LiteLmContent.audioFile(audioPath),
      ];

      _subscription = null;
      unawaited(_runMultimodalNonStreaming(
        contents,
        prompt: prompt,
        buffer: buffer,
        onToken: onToken,
        finish: finish,
      ));

      _idleTimer = Timer(const Duration(seconds: 90), () {
        if (tokenCount == 0) {
          finish('ERROR: LiteRT-LM multimodal model did not respond.');
        }
      });

      Future.delayed(const Duration(seconds: 240), () {
        if (!completed) {
          final partial = buffer.toString();
          finish(partial.isEmpty
              ? 'ERROR: LiteRT-LM multimodal generation timed out.'
              : partial);
        }
      });

      return completer.future;
    }

    _subscription = _liteConversation!.sendMessageStream(prompt).listen(
      (delta) {
        var text = _cleanLiteRtChunk(delta.text);
        if (text.isEmpty) return;

        if (!hasVisibleOutput) {
          if (!_hasPrintableText(text)) return;
          text = text.trimLeft();
          hasVisibleOutput = true;
        }

        if (tokenCount == 0) {
          debugPrint('[Inference] LiteRT-LM FIRST TOKEN received');
        }
        _liteConversationHasMessages = true;
        tokenCount++;
        buffer.write(text);

        // ── Garbage detection (KV cache overflow protection) ──
        // LiteRT doesn't throw when context overflows — it silently generates
        // garbage (numbers, repeated chars). Detect and stop immediately.
        if (_isLiteRtGarbage(buffer.toString())) {
          debugPrint('[Inference] LiteRT garbage detected at token $tokenCount — resetting session');
          // Reset the LiteRT conversation to clear the corrupted KV cache
          _liteConversation?.dispose().catchError((_) {});
          _liteConversation = null;
          _liteConversationSystemPrompt = null;
          _liteConversationHasMessages = false;
          // Return whatever was generated BEFORE the garbage started
          final clean = buffer.toString();
          final garbageStart = _findGarbageStart(clean);
          final result = garbageStart > 0 ? clean.substring(0, garbageStart).trimRight() : '';
          final msg = result.isEmpty
              ? 'ERROR: Context overflow — the model ran out of memory. Type "continue" to resume with a fresh context.'
              : '$result\n\n⚠️ [Context overflow — continuing in next message]';
          finish(msg);
          return;
        }

        onToken?.call(text);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () {
          debugPrint('[Inference] LiteRT-LM idle timeout - $tokenCount chunks');
          finish(buffer.toString());
        });
      },
      onDone: () {
        _liteConversationHasMessages = true;
        debugPrint('[Inference] LiteRT-LM stream done - $tokenCount chunks');
        finish(buffer.toString());
      },
      onError: (error) {
        debugPrint('[Inference] LiteRT-LM stream error: $error');
        finish('ERROR: LiteRT-LM generation failed - $error');
      },
    );

    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (tokenCount == 0) {
        finish('ERROR: LiteRT-LM model did not respond. Try a smaller model.');
      }
    });

    Future.delayed(const Duration(seconds: 180), () {
      if (!completed) {
        final partial = buffer.toString();
        finish(partial.isEmpty
            ? 'ERROR: LiteRT-LM generation timed out.'
            : partial);
      }
    });

    return completer.future;
  }

  /// LiteRT-LM 0.3.0 has no streaming API for multimodal (image/audio) input.
  /// It returns the full response at once via [LiteLmConversation.sendMultimodalMessage].
  Future<void> _runMultimodalNonStreaming(
    List<LiteLmContent> contents, {
    required String prompt,
    required StringBuffer buffer,
    void Function(String token)? onToken,
    required void Function(String result) finish,
  }) async {
    try {
      final response =
          await _liteConversation!.sendMultimodalMessage(contents);
      _liteConversationHasMessages = true;
      final text = _cleanLiteRtChunk(response.text);
      if (text.isEmpty) {
        finish('');
        return;
      }
      buffer.write(text);
      onToken?.call(text);
      debugPrint(
          '[Inference] LiteRT-LM multimodal response received (${text.length} chars)');
      finish(buffer.toString());
    } catch (error) {
      debugPrint('[Inference] LiteRT-LM multimodal generation failed: $error');
      finish('ERROR: LiteRT-LM multimodal generation failed - $error');
    }
  }

  /// Detects if the LiteRT output stream is generating garbage (KV cache overflow).
  /// Returns true if text contains repetitive patterns like "11111", "aaaa", etc.
  /// This happens when LiteRT KV cache is full but doesn't throw a clean error.
  bool _isLiteRtGarbage(String buffer) {
    if (buffer.length < 12) return false;
    final recent = buffer.length > 50 ? buffer.substring(buffer.length - 50) : buffer;
    // Pattern 1: >10 identical characters in a row ("1111111111", "aaaaaaaaaa")
    if (RegExp(r'(.)\1{9,}').hasMatch(recent)) return true;
    // Pattern 2: >10 consecutive digits mixed with nothing useful
    if (RegExp(r'\d{10,}').hasMatch(recent)) return true;
    // Pattern 3: Repeating 2-char pattern >8 times ("1a1a1a1a...")
    if (RegExp(r'(..)\1{7,}').hasMatch(recent)) return true;
    // Pattern 4: Last 20 non-space chars are ALL digits = numeric garbage
    final nonSpace = recent.replaceAll(' ', '').replaceAll('\n', '');
    if (nonSpace.length > 20) {
      final tail = nonSpace.substring(nonSpace.length - 20);
      if (RegExp(r'^\d+$').hasMatch(tail)) return true;
    }
    return false;
  }

  /// Finds the position in [text] where garbage output begins.
  /// Returns index of last "clean" char before garbage, or -1 if not found.
  int _findGarbageStart(String text) {
    if (text.length < 20) return -1;
    for (int i = text.length - 10; i > text.length ~/ 2; i--) {
      final slice = text.substring(i);
      if (RegExp(r'(.)\1{4,}').hasMatch(slice) ||
          RegExp(r'\d{8,}').hasMatch(slice) ||
          RegExp(r'(..)\1{5,}').hasMatch(slice)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _ensureLiteRtConversation({
    required String prompt,

    required List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required double temperature,
  }) async {
    final hasIncomingHistory = conversationHistory != null &&
        conversationHistory.any((msg) => (msg['content'] ?? '').isNotEmpty);
    final shouldReset = _liteConversation == null ||
        _liteConversationSystemPrompt != systemPrompt ||
        _liteConversationTemperature != temperature ||
        (_liteConversationHasMessages && !hasIncomingHistory);

    if (!shouldReset) return;

    try {
      await _liteConversation?.dispose();
    } catch (_) {}

    // Calculate how much history we can fit.
    // Keep last 8 messages to implement a 'sliding window' —
    // this prevents KV cache overflow that causes garbage output (1111...)
    final safeHistory = conversationHistory != null && conversationHistory.length > 8
        ? conversationHistory.sublist(conversationHistory.length - 8)
        : conversationHistory;

    _liteConversation = await _liteEngine!.createConversation(
      LiteLmConversationConfig(
        systemInstruction: systemPrompt,
        initialMessages:
            _buildLiteRtInitialMessages(prompt, safeHistory),
        samplerConfig: LiteLmSamplerConfig(
          // 0.85 temperature: breaks repetitive loops without hurting quality
          // (0.7 is too deterministic for LiteRT and causes loops when context fills)
          temperature: temperature < 0.8 ? 0.85 : temperature,
          topK: 40,   // lower topK reduces chaotic output at context boundaries
          topP: 0.90,
        ),
      ),
    );
    _liteConversationSystemPrompt = systemPrompt;
    _liteConversationTemperature = temperature;
    _liteConversationHasMessages = hasIncomingHistory;
  }

  Future<void> stop() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    final stopCallback = _onStop;
    _onStop = null;
    stopCallback?.call();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    if (_isLiteRt) {
      _liteConversationHasMessages = true;
      return;
    }
    try {
      await _controller?.stop().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  /// Reset any persistent conversation state so the next generation
  /// starts with a clean context. Essential when switching chat sessions.
  Future<void> resetConversation() async {
    if (_isLiteRt) {
      try {
        await _liteConversation?.dispose();
      } catch (_) {}
      _liteConversation = null;
      _liteConversationSystemPrompt = null;
      _liteConversationTemperature = null;
      _liteConversationHasMessages = false;
    }
    // llama.cpp (GGUF) is stateless per-generation — no native
    // conversation object to reset.
  }

  Future<ContextInfo?> getContextInfo() async {
    if (_isLiteRt) return null;
    try {
      return await _controller?.getContextInfo();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    if (_hasLoadedModel) {
      try {
        await _controller?.dispose();
      } catch (_) {}
    }
    try {
      await _liteConversation?.dispose();
    } catch (_) {}
    try {
      await _liteEngine?.dispose();
    } catch (_) {}
    unawaited(_loadProgressSub?.cancel() ?? Future<void>.value());
    _loadProgressSub = null;
    _controller = null;
    _liteConversation = null;
    _liteEngine = null;
    _isLiteRt = false;
    _hasLoadedModel = false;
    _liteConversationSystemPrompt = null;
    _liteConversationTemperature = null;
    _liteConversationHasMessages = false;
  }

  // ── Helpers ──

  int _extractGpuModel(String gpuName) {
    final match = RegExp(r'(\d{3})').firstMatch(gpuName.toLowerCase());
    return match != null ? (int.tryParse(match.group(1)!) ?? 0) : 0;
  }

  String _runtimeFor(String modelPath, String? modelRuntime) {
    final runtime = modelRuntime?.toLowerCase();
    if (runtime == 'litert' || runtime == 'llama') return runtime!;
    final lower = modelPath.toLowerCase();
    if (lower.endsWith('.litertlm')) return 'litert';
    return 'llama';
  }

  List<LiteLmMessage> _buildLiteRtInitialMessages(
    String prompt,
    List<Map<String, String>>? history,
  ) {
    if (history == null || history.isEmpty) return const [];

    var recent = history.length > 16
        ? history.sublist(history.length - 16)
        : List<Map<String, String>>.from(history);
    if (recent.isNotEmpty &&
        recent.last['role'] == 'user' &&
        recent.last['content'] == prompt) {
      recent = recent.sublist(0, recent.length - 1);
    }

    return recent
        .where((msg) => (msg['content'] ?? '').trim().isNotEmpty)
        .map((msg) {
      final content = msg['content'] ?? '';
      return msg['role'] == 'assistant'
          ? LiteLmMessage.model(content)
          : LiteLmMessage.user(content);
    }).toList();
  }

  String _cleanLiteRtChunk(String text) {
    return _sanitizeGemmaGarbage(
      text
          .replaceAll(
              RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
              '')
          .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
          .replaceAll('\uFFFD', '')
          .replaceAll('<|endoftext|>', '')
          .replaceAll('<|im_end|>', '')
          .replaceAll('<|end|>', ''),
    );
  }

  /// Strip Gemma garbage tokens that leak when Q4_K_M dequant is corrupt
  /// on Google Tensor SoC. Harmless on devices that don't produce them.
  /// NOTE: Do NOT trim() — SentencePiece tokens rely on leading spaces.
  String _sanitizeGemmaGarbage(String text) {
    return text
        .replaceAll(RegExp(r'<unused\d+>'), '')
        .replaceAll(RegExp(r'\[@BOS@\]'), '')
        .replaceAll('<bos>', '')
        .replaceAll('<mask>', '')
        .replaceAll('<pad>', '')
        .replaceAll('<unk>', '')
        .replaceAll('<s>', '')
        .replaceAll('</s>', '');
  }

  bool _hasPrintableText(String text) {
    for (final rune in text.runes) {
      if (rune > 32 &&
          rune != 0x7F &&
          rune != 0x200B &&
          rune != 0x200C &&
          rune != 0x200D &&
          rune != 0xFEFF &&
          rune != 0xFFFD) {
        return true;
      }
    }
    return false;
  }

  List<ChatMessage> _buildChatMessages(
    String prompt,
    List<Map<String, String>>? history,
    String systemPrompt,
  ) {
    final messages = <ChatMessage>[];
    messages.add(ChatMessage(role: 'system', content: systemPrompt));

    if (history != null && history.isNotEmpty) {
      var recent = history.length > 16
          ? history.sublist(history.length - 16)
          : List.of(history);
      if (recent.isNotEmpty &&
          recent.last['role'] == 'user' &&
          recent.last['content'] == prompt) {
        recent = recent.sublist(0, recent.length - 1);
      }
      for (final msg in recent) {
        final content = msg['content'] ?? '';
        messages
            .add(ChatMessage(role: msg['role'] ?? 'user', content: content));
      }
    }

    messages
        .add(ChatMessage(role: 'user', content: prompt));
    return messages;
  }

  String _buildPrompt(
    String userMessage,
    List<Map<String, String>>? history,
    String systemPrompt,
    String modelName,
  ) {
    // Auto-detect template from model name
    final name = modelName.toLowerCase();
    if (name.contains('gemma')) {
      return _buildGemma(userMessage, history, systemPrompt);
    }
    if (name.contains('llama-3') || name.contains('llama3')) {
      return _buildLlama3(userMessage, history, systemPrompt);
    }
    return _buildChatML(userMessage, history, systemPrompt);
  }

  String _buildChatML(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write('<|im_start|>system\n$sys<|im_end|>\n');
    if (history != null) {
      final recent =
          history.length > 10 ? history.sublist(history.length - 10) : history;
      for (final m in recent) {
        final content = m['content'] ?? '';
        final trunc =
            content.length > 2000 ? '${content.substring(0, 2000)}...' : content;
        buf.write('<|im_start|>${m['role'] ?? 'user'}\n$trunc<|im_end|>\n');
      }
    }
    buf.write('<|im_start|>user\n$msg<|im_end|>\n<|im_start|>assistant\n');
    return buf.toString();
  }

  String _buildGemma(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write(
        '<start_of_turn>user\n$sys<end_of_turn>\n<start_of_turn>model\nUnderstood.<end_of_turn>\n');
    if (history != null) {
      final recent =
          history.length > 10 ? history.sublist(history.length - 10) : history;
      for (final m in recent) {
        final role = m['role'] == 'assistant' ? 'model' : 'user';
        final content = m['content'] ?? '';
        final trunc =
            content.length > 2000 ? '${content.substring(0, 2000)}...' : content;
        buf.write('<start_of_turn>$role\n$trunc<end_of_turn>\n');
      }
    }
    buf.write('<start_of_turn>user\n$msg<end_of_turn>\n<start_of_turn>model\n');
    return buf.toString();
  }

  String _buildLlama3(
      String msg, List<Map<String, String>>? history, String sys) {
    final buf = StringBuffer();
    buf.write(
        '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$sys<|eot_id|>');
    if (history != null) {
      final recent =
          history.length > 10 ? history.sublist(history.length - 10) : history;
      for (final m in recent) {
        final content = m['content'] ?? '';
        final trunc =
            content.length > 2000 ? '${content.substring(0, 2000)}...' : content;
        buf.write(
            '<|start_header_id|>${m['role'] ?? 'user'}<|end_header_id|>\n\n$trunc<|eot_id|>');
      }
    }
    buf.write(
        '<|start_header_id|>user<|end_header_id|>\n\n$msg<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n');
    return buf.toString();
  }
}
