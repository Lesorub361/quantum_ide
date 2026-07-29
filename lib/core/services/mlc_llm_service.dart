import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';

class MlcLlmModel {
  final String id;
  final String name;
  final String description;
  final String filename;
  final double sizeGb;
  final double ramRequiredGb;
  final String url;

  const MlcLlmModel({
    required this.id,
    required this.name,
    required this.description,
    required this.filename,
    required this.sizeGb,
    required this.ramRequiredGb,
    required this.url,
  });
}

const List<MlcLlmModel> availableMlcModels = [
  MlcLlmModel(
    id: 'qwen_coder_1_5b',
    name: 'Qwen 2.5 Coder 1.5B (MLC)',
    description: 'Fast coding model optimized for MLC-LLM runtime.',
    filename: 'Qwen2.5-Coder-1.5B-Instruct-q4f16_1-MLC',
    sizeGb: 1.2,
    ramRequiredGb: 2.5,
    url: 'https://huggingface.co/mlc-ai/Qwen2.5-Coder-1.5B-Instruct-q4f16_1-MLC/resolve/main/',
  ),
  MlcLlmModel(
    id: 'qwen_coder_3b',
    name: 'Qwen 2.5 Coder 3B (MLC)',
    description: 'Balanced coding model for MLC-LLM runtime.',
    filename: 'Qwen2.5-Coder-3B-Instruct-q4f16_1-MLC',
    sizeGb: 2.1,
    ramRequiredGb: 4.0,
    url: 'https://huggingface.co/mlc-ai/Qwen2.5-Coder-3B-Instruct-q4f16_1-MLC/resolve/main/',
  ),
  MlcLlmModel(
    id: 'llama_3_1b',
    name: 'Llama 3.2 1B (MLC)',
    description: 'Lightweight Meta model optimized for MLC-LLM.',
    filename: 'Llama-3.2-1B-Instruct-q4f16_1-MLC',
    sizeGb: 0.9,
    ramRequiredGb: 2.0,
    url: 'https://huggingface.co/mlc-ai/Llama-3.2-1B-Instruct-q4f16_1-MLC/resolve/main/',
  ),
];

enum MlcModelStatus { notDownloaded, downloading, downloaded, loading, loaded, error }

class MlcModelState {
  final bool isRuntimeInstalled;
  final bool isNpuAvailable;
  final bool isGpuAvailable;
  final String? activeModelId;
  final MlcModelStatus modelStatus;
  final double downloadProgress;
  final String? error;
  final bool isInferring;
  final String? autocompleteFilePath;
  final int? autocompleteLineIndex;
  final int? autocompleteColumnOffset;
  final String? autocompleteTriggerWord;
  final String? autocompleteSuggestion;
  final bool autocompleteLoading;

  const MlcModelState({
    this.isRuntimeInstalled = false,
    this.isNpuAvailable = false,
    this.isGpuAvailable = false,
    this.activeModelId,
    this.modelStatus = MlcModelStatus.notDownloaded,
    this.downloadProgress = 0.0,
    this.error,
    this.isInferring = false,
    this.autocompleteFilePath,
    this.autocompleteLineIndex,
    this.autocompleteColumnOffset,
    this.autocompleteTriggerWord,
    this.autocompleteSuggestion,
    this.autocompleteLoading = false,
  });

  MlcModelState copyWith({
    bool? isRuntimeInstalled,
    bool? isNpuAvailable,
    bool? isGpuAvailable,
    String? activeModelId,
    bool clearActiveModel = false,
    MlcModelStatus? modelStatus,
    double? downloadProgress,
    String? error,
    bool clearError = false,
    bool? isInferring,
    String? autocompleteFilePath,
    bool clearAutocompleteFilePath = false,
    int? autocompleteLineIndex,
    int? autocompleteColumnOffset,
    String? autocompleteTriggerWord,
    String? autocompleteSuggestion,
    bool clearAutocompleteSuggestion = false,
    bool? autocompleteLoading,
  }) {
    return MlcModelState(
      isRuntimeInstalled: isRuntimeInstalled ?? this.isRuntimeInstalled,
      isNpuAvailable: isNpuAvailable ?? this.isNpuAvailable,
      isGpuAvailable: isGpuAvailable ?? this.isGpuAvailable,
      activeModelId: clearActiveModel ? null : (activeModelId ?? this.activeModelId),
      modelStatus: modelStatus ?? this.modelStatus,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      error: clearError ? null : (error ?? this.error),
      isInferring: isInferring ?? this.isInferring,
      autocompleteFilePath: clearAutocompleteFilePath ? null : (autocompleteFilePath ?? this.autocompleteFilePath),
      autocompleteLineIndex: autocompleteLineIndex ?? this.autocompleteLineIndex,
      autocompleteColumnOffset: autocompleteColumnOffset ?? this.autocompleteColumnOffset,
      autocompleteTriggerWord: autocompleteTriggerWord ?? this.autocompleteTriggerWord,
      autocompleteSuggestion: clearAutocompleteSuggestion ? null : (autocompleteSuggestion ?? this.autocompleteSuggestion),
      autocompleteLoading: autocompleteLoading ?? this.autocompleteLoading,
    );
  }
}

class MlcLlmService extends StateNotifier<MlcModelState> {
  final Ref ref;
  final _dio = Dio();
  Timer? _debounceTimer;

  MlcLlmService(this.ref) : super(const MlcModelState());

  String get _modelsDir {
    final runtime = ref.read(runtimeServiceProvider);
    return p.join(runtime.appDirectory, 'mlc_models');
  }

  Future<void> checkHardware() async {
    final runtime = ref.read(runtimeServiceProvider);
    try {
      final npuCheck = await runtime.runCommand('ls /dev/accel* /dev/npu* 2>/dev/null || echo "none"');
      final gpuCheck = await runtime.runCommand('ls /dev/mali* /dev/dri/* 2>/dev/null || echo "none"');
      state = state.copyWith(
        isNpuAvailable: !npuCheck.trim().endsWith('none'),
        isGpuAvailable: !gpuCheck.trim().endsWith('none'),
      );
    } catch (_) {
      state = state.copyWith(isNpuAvailable: false, isGpuAvailable: false);
    }
  }

  Future<void> checkRuntime() async {
    final runtime = ref.read(runtimeServiceProvider);
    try {
      final output = await runtime.runCommand('which mlc_llm 2>/dev/null || echo "none"');
      final installed = !output.trim().endsWith('none');
      state = state.copyWith(isRuntimeInstalled: installed);
    } catch (_) {
      state = state.copyWith(isRuntimeInstalled: false);
    }
  }

  Future<void> installRuntime() async {
    final runtime = ref.read(runtimeServiceProvider);
    try {
      state = state.copyWith(error: null);
      await runtime.runCommand('pip3 install --break-system-packages mlc-ai-nightly mlc-chat-nightly');
      await checkRuntime();
    } catch (e) {
      state = state.copyWith(error: 'Failed to install MLC-LLM runtime: $e');
    }
  }

  Future<void> downloadModel(MlcLlmModel model) async {
    state = state.copyWith(
      modelStatus: MlcModelStatus.downloading,
      downloadProgress: 0.0,
      error: null,
    );

    final modelDir = p.join(_modelsDir, model.filename);
    try {
      await Directory(modelDir).create(recursive: true);

      final files = [
        'modelfile.wasm',
        'modelfile.wasm.params',
        'config.json',
      ];

      for (var i = 0; i < files.length; i++) {
        final url = '${model.url}${files[i]}';
        final savePath = p.join(modelDir, files[i]);

        await _dio.download(
          url,
          savePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final fileProgress = (received / total) * (1.0 / files.length);
              final overallProgress = (i / files.length) + fileProgress;
              state = state.copyWith(downloadProgress: overallProgress);
            }
          },
        );
      }

      state = state.copyWith(
        modelStatus: MlcModelStatus.downloaded,
        downloadProgress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(
        modelStatus: MlcModelStatus.error,
        error: 'Download failed: $e',
      );
    }
  }

  bool isModelDownloaded(String modelId) {
    final model = availableMlcModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => availableMlcModels.first,
    );
    return Directory(p.join(_modelsDir, model.filename)).existsSync();
  }

  Future<void> loadModel(MlcLlmModel model) async {
    state = state.copyWith(
      modelStatus: MlcModelStatus.loading,
      error: null,
    );

    try {
      if (!state.isRuntimeInstalled) {
        await installRuntime();
      }

      final modelDir = p.join(_modelsDir, model.filename);
      if (!Directory(modelDir).existsSync()) {
        await downloadModel(model);
      }

      state = state.copyWith(
        modelStatus: MlcModelStatus.loaded,
        activeModelId: model.id,
      );
    } catch (e) {
      state = state.copyWith(
        modelStatus: MlcModelStatus.error,
        error: 'Failed to load model: $e',
      );
    }
  }

  Future<void> unloadModel() async {
    _debounceTimer?.cancel();
    state = state.copyWith(
      modelStatus: MlcModelStatus.downloaded,
      clearActiveModel: true,
      isInferring: false,
    );
  }

  Future<String> infer(String prompt, {int maxTokens = 128}) async {
    if (state.modelStatus != MlcModelStatus.loaded || state.activeModelId == null) {
      throw StateError('No model loaded');
    }

    state = state.copyWith(isInferring: true);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      final model = availableMlcModels.firstWhere(
        (m) => m.id == state.activeModelId,
      );
      final modelDir = p.join(_modelsDir, model.filename);

      final escapedPrompt = prompt.replaceAll('"', '\\"').replaceAll('\n', '\\n');
      final output = await runtime.runCommand(
        'cd "$modelDir" && python3 -c "'
        'from mlc_chat import ChatModule; '
        'cm = ChatModule(model_path=\\"$modelDir\\"); '
        'response = cm.generate_text(\\"$escapedPrompt\\", max_gen_len=$maxTokens); '
        'print(response)"',
      );

      return output.trim();
    } catch (e) {
      state = state.copyWith(error: 'Inference failed: $e');
      rethrow;
    } finally {
      state = state.copyWith(isInferring: false);
    }
  }

  void triggerAutocomplete({
    required String filePath,
    required String text,
    required int lineIndex,
    required int columnOffset,
    required String word,
  }) {
    if (state.modelStatus != MlcModelStatus.loaded) return;

    if (state.autocompleteFilePath == filePath &&
        state.autocompleteLineIndex == lineIndex &&
        state.autocompleteColumnOffset == columnOffset &&
        state.autocompleteTriggerWord == word) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () async {
      await _fetchAutocomplete(
        filePath: filePath,
        text: text,
        lineIndex: lineIndex,
        columnOffset: columnOffset,
        word: word,
      );
    });
  }

  Future<void> _fetchAutocomplete({
    required String filePath,
    required String text,
    required int lineIndex,
    required int columnOffset,
    required String word,
  }) async {
    if (state.modelStatus != MlcModelStatus.loaded) return;

    state = state.copyWith(
      autocompleteLoading: true,
      autocompleteFilePath: filePath,
      autocompleteLineIndex: lineIndex,
      autocompleteColumnOffset: columnOffset,
      autocompleteTriggerWord: word,
      clearAutocompleteSuggestion: true,
    );

    try {
      final codeBefore = _getCodeBeforeCursor(text, lineIndex, columnOffset);
      final filename = p.basename(filePath);

      final prompt = '''Complete the code at cursor position in file $filename. Return ONLY the immediate completion (up to 5 lines). No explanations, no markdown.

Code context:
$codeBefore''';

      final completion = await infer(prompt, maxTokens: 128);
      state = state.copyWith(
        autocompleteLoading: false,
        autocompleteSuggestion: completion.trim(),
      );
    } catch (e) {
      debugPrint('MLC Autocomplete failed: $e');
      state = state.copyWith(
        autocompleteLoading: false,
        autocompleteSuggestion: '',
      );
    }
  }

  String _getCodeBeforeCursor(String text, int lineIndex, int columnOffset) {
    final lines = text.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return text;

    final buffer = StringBuffer();
    final startLine = lineIndex > 50 ? lineIndex - 50 : 0;
    for (var i = startLine; i < lineIndex; i++) {
      buffer.writeln(lines[i]);
    }

    final currentLine = lines[lineIndex];
    if (columnOffset >= 0 && columnOffset <= currentLine.length) {
      buffer.write(currentLine.substring(0, columnOffset));
    } else {
      buffer.write(currentLine);
    }

    return buffer.toString();
  }

  Future<void> deleteModel(MlcLlmModel model) async {
    final modelDir = p.join(_modelsDir, model.filename);
    try {
      final dir = Directory(modelDir);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      if (state.activeModelId == model.id) {
        state = state.copyWith(
          modelStatus: MlcModelStatus.notDownloaded,
          clearActiveModel: true,
        );
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete model: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _dio.close(force: true);
    super.dispose();
  }
}

final mlcLlmServiceProvider =
    StateNotifierProvider<MlcLlmService, MlcModelState>((ref) {
  return MlcLlmService(ref);
});
