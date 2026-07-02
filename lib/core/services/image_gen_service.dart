import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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
    this.isModelLoaded = false,
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
  ImageGenNotifier() : super(const ImageGenState());

  Future<void> loadModel(String modelPath, {String? modelName}) async {
    if (state.isLoadingModel) return;

    state = state.copyWith(isLoadingModel: true, error: null);

    try {
      if (!File(modelPath).existsSync()) {
        state = state.copyWith(
          isLoadingModel: false,
          error: 'Model file not found: $modelPath',
        );
        return;
      }

      // TODO: Implement actual SD model loading via native bridge
      // For now, mark as loaded to enable UI testing
      await Future.delayed(const Duration(seconds: 1));

      state = state.copyWith(
        isModelLoaded: true,
        isLoadingModel: false,
        loadedModelName: modelName ?? p.basename(modelPath),
        loadedModelPath: modelPath,
        progress: 1.0,
      );
    } catch (e) {
      state = state.copyWith(
        isModelLoaded: false,
        isLoadingModel: false,
        error: 'Failed to load model: $e',
      );
    }
  }

  Future<void> unloadModel() async {
    state = const ImageGenState();
  }

  Future<Uint8List?> generateImage({
    required String prompt,
    int width = 512,
    int height = 512,
    int steps = 4,
    void Function(int step, int totalSteps)? onProgress,
  }) async {
    if (!state.isModelLoaded || state.isGenerating) return null;

    state = state.copyWith(isGenerating: true, currentStep: 0, totalSteps: steps);

    try {
      // TODO: Implement actual SD image generation via native bridge
      // Simulate generation progress
      for (int i = 1; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        state = state.copyWith(currentStep: i, progress: i / steps);
        onProgress?.call(i, steps);
      }

      // For now, return null until native bridge is implemented
      state = state.copyWith(isGenerating: false);
      return null;
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
