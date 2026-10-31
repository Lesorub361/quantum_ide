import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:quantum_ide/core/services/ai_service.dart';

class NativeGpuInfo {
  final bool vulkanSupported;
  final String gpuName;
  final int freeRamMb;
  final int recommendedGpuLayers;

  const NativeGpuInfo({
    required this.vulkanSupported,
    required this.gpuName,
    required this.freeRamMb,
    required this.recommendedGpuLayers,
  });
}

class NativeLlamaState {
  final bool isModelLoaded;
  final bool isLoading;
  final bool isGenerating;
  final String? loadedModelPath;
  final NativeGpuInfo? gpuInfo;
  final String? error;
  final String logs;

  const NativeLlamaState({
    this.isModelLoaded = false,
    this.isLoading = false,
    this.isGenerating = false,
    this.loadedModelPath,
    this.gpuInfo,
    this.error,
    this.logs = '',
  });

  NativeLlamaState copyWith({
    bool? isModelLoaded,
    bool? isLoading,
    bool? isGenerating,
    String? loadedModelPath,
    NativeGpuInfo? gpuInfo,
    String? error,
    String? logs,
  }) {
    return NativeLlamaState(
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      isLoading: isLoading ?? this.isLoading,
      isGenerating: isGenerating ?? this.isGenerating,
      loadedModelPath: loadedModelPath ?? this.loadedModelPath,
      gpuInfo: gpuInfo ?? this.gpuInfo,
      error: error,
      logs: logs ?? this.logs,
    );
  }
}

class NativeLlamaService extends StateNotifier<NativeLlamaState> {
  final Ref _ref;
  LlamaController? _controller;
  StreamSubscription<String>? _generationSub;

  NativeLlamaService(this._ref) : super(const NativeLlamaState()) {
    _initGpuInfo();
  }

  void _appendLogs(String text) {
    debugPrint('[NativeLlama] $text');
    final updated = '${state.logs}$text';
    final lines = updated.split('\n');
    final trimmed = lines.length > 200 ? lines.sublist(lines.length - 200).join('\n') : updated;
    state = state.copyWith(logs: trimmed);
  }

  Future<void> _initGpuInfo() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      _controller ??= LlamaController();
      final gpu = await _controller!.detectGpu();
      final freeMb = gpu.freeRamBytes ~/ (1024 * 1024);
      final info = NativeGpuInfo(
        vulkanSupported: gpu.vulkanSupported,
        gpuName: gpu.gpuName,
        freeRamMb: freeMb,
        recommendedGpuLayers: gpu.recommendedGpuLayers,
      );
      state = state.copyWith(gpuInfo: info);
      _appendLogs('[GPU] ${gpu.gpuName} | Vulkan: ${gpu.vulkanSupported} | Free RAM: ${freeMb}MB | Rec layers: ${gpu.recommendedGpuLayers}\n');
    } catch (e) {
      _appendLogs('[GPU Detection Warning] $e\n');
    }
  }

  Future<void> loadModel({
    required String modelPath,
    int? threads,
    int? contextSize,
    int? gpuLayers,
  }) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);
    _appendLogs('[Model] Загрузка модели $modelPath...\n');

    try {
      if (!await File(modelPath).exists()) {
        throw Exception('Файл модели не найден по пути: $modelPath');
      }

      _controller ??= LlamaController();
      if (state.isModelLoaded) {
        await unloadModel();
        _controller = LlamaController();
      }

      int finalGpuLayers = gpuLayers ?? 0;
      if (state.gpuInfo != null && state.gpuInfo!.vulkanSupported && gpuLayers == null) {
        finalGpuLayers = state.gpuInfo!.recommendedGpuLayers;
      }

      await _controller!.loadModel(
        modelPath: modelPath,
        threads: threads ?? 4,
        contextSize: contextSize ?? 2048,
        gpuLayers: finalGpuLayers,
      );

      state = state.copyWith(
        isModelLoaded: true,
        isLoading: false,
        loadedModelPath: modelPath,
      );
      _appendLogs('[Model] Модель успешно загружена (gpuLayers: $finalGpuLayers)!\n');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Ошибка загрузки модели: $e');
      _appendLogs('[Model Error] $e\n');
      rethrow;
    }
  }

  Future<void> unloadModel() async {
    try {
      await stopGeneration();
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      state = state.copyWith(
        isModelLoaded: false,
        loadedModelPath: null,
      );
      _appendLogs('[Model] Модель выгружена из памяти.\n');
    } catch (e) {
      _appendLogs('[Model Unload Error] $e\n');
    }
  }

  Future<void> stopGeneration() async {
    try {
      await _generationSub?.cancel();
      _generationSub = null;
      if (_controller != null) {
        await _controller!.stop();
      }
      state = state.copyWith(isGenerating: false);
    } catch (e) {
      debugPrint('[NativeLlama] Error stopping generation: $e');
    }
  }

  Future<ChatResponse> streamChat({
    required String message,
    required List<Map<String, String>> history,
    String? systemInstruction,
    void Function(String token)? onToken,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    if (!state.isModelLoaded || _controller == null) {
      throw Exception('Нативная модель не загружена в память. Выберите модель в настройках AI.');
    }

    state = state.copyWith(isGenerating: true, error: null);

    final chatMessages = <ChatMessage>[];
    if (systemInstruction != null && systemInstruction.isNotEmpty) {
      chatMessages.add(ChatMessage(role: 'system', content: systemInstruction));
    }

    for (final h in history) {
      final role = h['role'] ?? 'user';
      final content = h['content'] ?? '';
      chatMessages.add(ChatMessage(role: role, content: content));
    }
    chatMessages.add(ChatMessage(role: 'user', content: message));

    final fullResponseBuffer = StringBuffer();
    final completer = Completer<ChatResponse>();

    try {
      final stream = _controller!.generateChat(
        messages: chatMessages,
        temperature: temperature,
        maxTokens: maxTokens,
      );

      _generationSub = stream.listen(
        (token) {
          fullResponseBuffer.write(token);
          if (onToken != null) {
            onToken(token);
          }
        },
        onError: (err) {
          state = state.copyWith(isGenerating: false, error: err.toString());
          if (!completer.isCompleted) {
            completer.completeError(err);
          }
        },
        onDone: () {
          state = state.copyWith(isGenerating: false);
          if (!completer.isCompleted) {
            completer.complete(ChatResponse(fullResponseBuffer.toString()));
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: e.toString());
      rethrow;
    }
  }

  Future<String> getCompletion(
    String prompt, {
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    if (!state.isModelLoaded || _controller == null) {
      throw Exception('Нативная модель не загружена в память. Выберите модель в настройках AI.');
    }

    state = state.copyWith(isGenerating: true, error: null);
    final buffer = StringBuffer();
    final completer = Completer<String>();

    try {
      final stream = _controller!.generate(
        prompt: prompt,
        temperature: temperature,
        maxTokens: maxTokens,
      );

      _generationSub = stream.listen(
        (token) {
          buffer.write(token);
        },
        onError: (err) {
          state = state.copyWith(isGenerating: false, error: err.toString());
          if (!completer.isCompleted) {
            completer.completeError(err);
          }
        },
        onDone: () {
          state = state.copyWith(isGenerating: false);
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: e.toString());
      rethrow;
    }
  }

  @override
  void dispose() {
    _generationSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}

final nativeLlamaServiceProvider =
    StateNotifierProvider<NativeLlamaService, NativeLlamaState>((ref) {
  return NativeLlamaService(ref);
});
