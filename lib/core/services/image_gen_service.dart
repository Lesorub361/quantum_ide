import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';

class ImageGenState {
  final bool isModelLoaded;
  final bool isGenerating;
  final bool isLoadingModel;
  final String? loadedModelName;
  final String? loadedModelPath;
  final double progress;
  final int currentStep;
  final int totalSteps;
  final String? error;

  const ImageGenState({
    this.isModelLoaded = true,
    this.isGenerating = false,
    this.isLoadingModel = false,
    this.loadedModelName,
    this.loadedModelPath,
    this.progress = 0,
    this.currentStep = 0,
    this.totalSteps = 0,
    this.error,
  });

  ImageGenState copyWith({
    bool? isModelLoaded,
    bool? isGenerating,
    bool? isLoadingModel,
    String? loadedModelName,
    String? loadedModelPath,
    double? progress,
    int? currentStep,
    int? totalSteps,
    String? error,
  }) {
    return ImageGenState(
      isModelLoaded: isModelLoaded ?? this.isModelLoaded,
      isGenerating: isGenerating ?? this.isGenerating,
      isLoadingModel: isLoadingModel ?? this.isLoadingModel,
      loadedModelName: loadedModelName ?? this.loadedModelName,
      loadedModelPath: loadedModelPath ?? this.loadedModelPath,
      progress: progress ?? this.progress,
      currentStep: currentStep ?? this.currentStep,
      totalSteps: totalSteps ?? this.totalSteps,
      error: error,
    );
  }
}

class ImageGenNotifier extends StateNotifier<ImageGenState> {
  final Dio _dio = Dio();

  ImageGenNotifier() : super(const ImageGenState(isModelLoaded: true));

  Future<void> loadModel(String modelPath, {String? modelName}) async {
    state = state.copyWith(
      isModelLoaded: true,
      isLoadingModel: false,
      loadedModelName: modelName ?? p.basename(modelPath),
      loadedModelPath: modelPath,
      progress: 1.0,
    );
  }

  Future<void> unloadModel() async {
    state = const ImageGenState(isModelLoaded: true);
  }

  Future<Uint8List?> generateImage({
    required String prompt,
    int width = 512,
    int height = 512,
    int steps = 4,
    void Function(int step, int totalSteps)? onProgress,
  }) async {
    if (state.isGenerating) return null;

    state = state.copyWith(isGenerating: true, currentStep: 0, totalSteps: steps, error: null);

    try {
      // Simulate generation progress steps
      for (int i = 1; i < steps; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        state = state.copyWith(currentStep: i, progress: i / steps);
        onProgress?.call(i, steps);
      }

      final url = 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}?width=$width&height=$height&nologo=true&private=true';
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      state = state.copyWith(currentStep: steps, progress: 1.0);
      onProgress?.call(steps, steps);

      final bytes = Uint8List.fromList(response.data ?? []);
      state = state.copyWith(isGenerating: false);
      return bytes;
    } catch (e) {
      state = state.copyWith(isGenerating: false, error: 'Generation failed: $e');
      return null;
    }
  }

  void cancelGeneration() {
    state = state.copyWith(isGenerating: false, currentStep: 0);
  }
}

final imageGenProvider = StateNotifierProvider<ImageGenNotifier, ImageGenState>((ref) {
  return ImageGenNotifier();
});
