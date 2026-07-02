import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';

const _downloadChannel = MethodChannel('com.example.quantum_ide/download');

enum ModelCategory { text, image, vision }

enum ModelRuntime { llama, litert, sd }

enum DownloadStatus { idle, downloading, paused, completed, error }

class AiCatalogModel {
  final String id;
  final String name;
  final String filename;
  final String url;
  final String size;
  final String description;
  final ModelCategory category;
  final ModelRuntime runtime;
  final bool isVision;
  final String template;

  const AiCatalogModel({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.size,
    required this.description,
    required this.category,
    required this.runtime,
    this.isVision = false,
    this.template = 'chatml',
  });
}

class ModelDownloadInfo {
  final String filename;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final String? error;

  const ModelDownloadInfo({
    required this.filename,
    this.status = DownloadStatus.idle,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.error,
  });

  ModelDownloadInfo copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    double? speed,
    String? error,
  }) {
    return ModelDownloadInfo(
      filename: filename,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speed: speed ?? this.speed,
      error: error,
    );
  }
}

class ModelCatalogState {
  final List<AiCatalogModel> models;
  final Map<String, ModelDownloadInfo> downloads;
  final Map<String, bool> downloadedModels;
  final bool isLoading;

  const ModelCatalogState({
    this.models = const [],
    this.downloads = const {},
    this.downloadedModels = const {},
    this.isLoading = false,
  });

  ModelCatalogState copyWith({
    List<AiCatalogModel>? models,
    Map<String, ModelDownloadInfo>? downloads,
    Map<String, bool>? downloadedModels,
    bool? isLoading,
  }) {
    return ModelCatalogState(
      models: models ?? this.models,
      downloads: downloads ?? this.downloads,
      downloadedModels: downloadedModels ?? this.downloadedModels,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ModelCatalogNotifier extends StateNotifier<ModelCatalogState> {
  final Ref _ref;
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};

  static const List<AiCatalogModel> _defaultModels = [
    // === Text Models (GGUF) ===
    AiCatalogModel(
      id: 'qwen3_06b',
      name: 'Qwen 3 0.6B',
      filename: 'Qwen3-0.6B.litertlm',
      url: 'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      size: '586 MB',
      description: 'Smallest chat model for low-RAM phones',
      category: ModelCategory.text,
      runtime: ModelRuntime.litert,
      template: 'litert',
    ),
    AiCatalogModel(
      id: 'qwen25_15b_litert',
      name: 'Qwen 2.5 1.5B (LiteRT)',
      filename: 'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      url: 'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      size: '1.49 GB',
      description: 'Balanced LiteRT chat model with int8 quantization',
      category: ModelCategory.text,
      runtime: ModelRuntime.litert,
      template: 'litert',
    ),
    AiCatalogModel(
      id: 'deepseek_r1_15b_litert',
      name: 'DeepSeek R1 1.5B (LiteRT)',
      filename: 'DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      url: 'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      size: '1.71 GB',
      description: 'Reasoning-focused LiteRT model with int8 quantization',
      category: ModelCategory.text,
      runtime: ModelRuntime.litert,
      template: 'litert',
    ),
    AiCatalogModel(
      id: 'gemma4_e2b',
      name: 'Gemma 4 E2B Instruct',
      filename: 'gemma-4-E2B-it.litertlm',
      url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      size: '2.46 GB',
      description: 'Strong general chat model from Google Gemma',
      category: ModelCategory.vision,
      runtime: ModelRuntime.litert,
      isVision: true,
      template: 'litert',
    ),
    AiCatalogModel(
      id: 'gemma4_e4b',
      name: 'Gemma 4 E4B Instruct',
      filename: 'gemma-4-E4B-it.litertlm',
      url: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      size: '3.40 GB',
      description: 'Highest quality LiteRT option; needs about 5 GB RAM',
      category: ModelCategory.vision,
      runtime: ModelRuntime.litert,
      isVision: true,
      template: 'litert',
    ),
    AiCatalogModel(
      id: 'qwen25_3b',
      name: 'Qwen2.5-3B Instruct (Q4_K_M)',
      filename: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      size: '2.1 GB',
      description: 'Best balance of speed and quality for mobile',
      category: ModelCategory.text,
      runtime: ModelRuntime.llama,
      template: 'chatml',
    ),
    AiCatalogModel(
      id: 'qwen2_vl_2b',
      name: 'Qwen2-VL-2B Instruct (Q4_K_M)',
      filename: 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
      size: '1.5 GB',
      description: 'Vision-capable — can understand images',
      category: ModelCategory.vision,
      runtime: ModelRuntime.llama,
      isVision: true,
      template: 'chatml',
    ),
    AiCatalogModel(
      id: 'phi35_mini',
      name: 'Phi-3.5 Mini Instruct (Q4_K_M)',
      filename: 'phi-3.5-mini-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      size: '2.2 GB',
      description: 'Microsoft compact reasoning model',
      category: ModelCategory.text,
      runtime: ModelRuntime.llama,
      template: 'phi',
    ),
    AiCatalogModel(
      id: 'gemma2_2b',
      name: 'Gemma 2 2B Instruct (Q4_K_M)',
      filename: 'gemma-2-2b-it-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      size: '1.71 GB',
      description: 'Google lightweight general chat model',
      category: ModelCategory.text,
      runtime: ModelRuntime.llama,
      template: 'gemma',
    ),
    AiCatalogModel(
      id: 'llama32_3b',
      name: 'Llama-3.2-3B Uncensored (Q4_K_M)',
      filename: 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
      size: '2.1 GB',
      description: 'Uncensored Llama 3.2 3B',
      category: ModelCategory.text,
      runtime: ModelRuntime.llama,
      template: 'llama3',
    ),
    AiCatalogModel(
      id: 'llama32_1b',
      name: 'Llama-3.2-1B Instruct (Q4_K_M)',
      filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      size: '0.8 GB',
      description: 'Ultra-lightweight text model',
      category: ModelCategory.text,
      runtime: ModelRuntime.llama,
      template: 'llama3',
    ),
    // === Image Models (SD) ===
    AiCatalogModel(
      id: 'dreamshaper8',
      name: 'DreamShaper 8 LCM (SD 1.5)',
      filename: 'DreamShaper8_LCM.safetensors',
      url: 'https://huggingface.co/Lykon/dreamshaper-8-lcm/resolve/main/DreamShaper8_LCM.safetensors',
      size: '2.0 GB',
      description: 'Extremely fast 4-step local image generation',
      category: ModelCategory.image,
      runtime: ModelRuntime.sd,
      template: 'sd',
    ),
    AiCatalogModel(
      id: 'cyberrealistic_v8',
      name: 'CyberRealistic V8 FP16 (SD 1.5)',
      filename: 'CyberRealistic_V8_FP16.safetensors',
      url: 'https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V8_FP16.safetensors',
      size: '2.0 GB',
      description: 'Photorealistic, uncensored local image generation',
      category: ModelCategory.image,
      runtime: ModelRuntime.sd,
      template: 'sd',
    ),
    AiCatalogModel(
      id: 'realistic_vision_v51',
      name: 'Realistic Vision V5.1 fp16 (SD 1.5)',
      filename: 'Realistic_Vision_V5.1_fp16-no-ema.safetensors',
      url: 'https://huggingface.co/SG161222/Realistic_Vision_V5.1_noVAE/resolve/main/Realistic_Vision_V5.1_fp16-no-ema.safetensors',
      size: '2.0 GB',
      description: 'Highly popular photorealistic portrait model',
      category: ModelCategory.image,
      runtime: ModelRuntime.sd,
      template: 'sd',
    ),
    AiCatalogModel(
      id: 'absolutereality',
      name: 'AbsoluteReality 1.8.1 (SD 1.5)',
      filename: 'AbsoluteReality_1.8.1_pruned.safetensors',
      url: 'https://huggingface.co/Lykon/AbsoluteReality/resolve/main/AbsoluteReality_1.8.1_pruned.safetensors',
      size: '2.0 GB',
      description: 'Photorealistic general-purpose image generation',
      category: ModelCategory.image,
      runtime: ModelRuntime.sd,
      template: 'sd',
    ),
    AiCatalogModel(
      id: 'anylora',
      name: 'AnyLoRA (SD 1.5)',
      filename: 'AnyLoRA_noVae_fp16-pruned.safetensors',
      url: 'https://huggingface.co/Lykon/AnyLoRA/resolve/main/AnyLoRA_noVae_fp16-pruned.safetensors',
      size: '2.0 GB',
      description: 'Highly versatile Anime / Stylized image generator',
      category: ModelCategory.image,
      runtime: ModelRuntime.sd,
      template: 'sd',
    ),
  ];

  ModelCatalogNotifier(this._ref) : super(const ModelCatalogState()) {
    state = state.copyWith(models: _defaultModels);
    _loadDownloadedModels();
  }

  Future<void> _loadDownloadedModels() async {
    final runtime = _ref.read(runtimeServiceProvider);
    if (!runtime.isInitialized) return;

    final modelsDir = await getModelsDir();
    if (modelsDir == null) return;

    final dir = Directory(modelsDir);
    if (!await dir.exists()) return;

    final downloaded = <String, bool>{};
    await for (final entity in dir.list()) {
      if (entity is File) {
        final filename = p.basename(entity.path);
        if (filename.endsWith('.gguf') || filename.endsWith('.litertlm') || filename.endsWith('.safetensors')) {
          downloaded[filename] = true;
        }
      }
    }

    state = state.copyWith(downloadedModels: downloaded);
  }

  Future<String?> getModelsDir() async {
    try {
      final runtime = _ref.read(runtimeServiceProvider);
      if (!runtime.isInitialized) return null;
      final modelsDir = p.join(runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models');
      await Directory(modelsDir).create(recursive: true);
      return modelsDir;
    } catch (_) {
      return null;
    }
  }

  Future<void> downloadModel(AiCatalogModel model) async {
    final modelsDir = await getModelsDir();
    if (modelsDir == null) return;

    final savePath = p.join(modelsDir, model.filename);

    state = state.copyWith(
      downloads: {
        ...state.downloads,
        model.filename: ModelDownloadInfo(
          filename: model.filename,
          status: DownloadStatus.downloading,
        ),
      },
    );

    try {
      if (Platform.isAndroid) {
        await _downloadWithNativeManager(model, modelsDir);
      } else {
        await _downloadWithDio(model, savePath);
      }
    } catch (e) {
      state = state.copyWith(
        downloads: {
          ...state.downloads,
          model.filename: ModelDownloadInfo(
            filename: model.filename,
            status: DownloadStatus.error,
            error: e.toString(),
          ),
        },
      );
    }
  }

  Future<void> _downloadWithNativeManager(AiCatalogModel model, String modelsDir) async {
    try {
      final result = await _downloadChannel.invokeMethod('downloadModel', {
        'url': model.url,
        'filename': model.filename,
        'modelsDir': modelsDir,
      });

      final downloadId = result['downloadId'] as int;
      _nativeDownloadIds[model.filename] = downloadId;

      _pollDownloadProgress(model.filename, downloadId);
    } catch (e) {
      rethrow;
    }
  }

  final Map<String, int> _nativeDownloadIds = {};

  void _pollDownloadProgress(String filename, int downloadId) async {
    while (true) {
      await Future.delayed(const Duration(seconds: 1));

      try {
        final result = await _downloadChannel.invokeMethod('getDownloadStatus', {
          'filename': filename,
        });

        if (result == null) continue;

        final status = result['status'] as int;
        final downloaded = result['downloaded'] as int;
        final total = result['total'] as int;

        final progress = total > 0 ? downloaded / total : 0.0;

        state = state.copyWith(
          downloads: {
            ...state.downloads,
            filename: ModelDownloadInfo(
              filename: filename,
              status: DownloadStatus.downloading,
              progress: progress,
              downloadedBytes: downloaded,
              totalBytes: total,
            ),
          },
        );

        if (status == 16) {
          state = state.copyWith(
            downloads: {
              ...state.downloads,
              filename: ModelDownloadInfo(
                filename: filename,
                status: DownloadStatus.completed,
                progress: 1.0,
              ),
            },
            downloadedModels: {
              ...state.downloadedModels,
              filename: true,
            },
          );
          break;
        } else if (status == 8 || status == 16) {
          state = state.copyWith(
            downloads: {
              ...state.downloads,
              filename: ModelDownloadInfo(
                filename: filename,
                status: DownloadStatus.error,
                error: 'Download failed',
              ),
            },
          );
          break;
        }
      } catch (_) {}
    }
  }

  Future<void> _downloadWithDio(AiCatalogModel model, String savePath) async {
    final cancelToken = CancelToken();
    _cancelTokens[model.filename] = cancelToken;

    try {
      final tempPath = '$savePath.part';
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final startTime = DateTime.now();
      int lastBytes = 0;

      await _dio.download(
        model.url,
        tempPath,
        cancelToken: cancelToken,
        deleteOnError: false,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
        ),
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final elapsed = now.difference(startTime).inMilliseconds;
          double speed = 0;
          if (elapsed > 500) {
            speed = (received - lastBytes) / (elapsed / 1000.0);
            lastBytes = received;
          }

          final progress = total > 0 ? received / total : 0.0;
          state = state.copyWith(
            downloads: {
              ...state.downloads,
              model.filename: ModelDownloadInfo(
                filename: model.filename,
                status: DownloadStatus.downloading,
                progress: progress,
                downloadedBytes: received,
                totalBytes: total,
                speed: speed,
              ),
            },
          );
        },
      );

      final finalFile = File(savePath);
      if (await finalFile.exists()) await finalFile.delete();
      await tempFile.rename(savePath);

      _cancelTokens.remove(model.filename);
      state = state.copyWith(
        downloads: {
          ...state.downloads,
          model.filename: ModelDownloadInfo(
            filename: model.filename,
            status: DownloadStatus.completed,
            progress: 1.0,
          ),
        },
        downloadedModels: {
          ...state.downloadedModels,
          model.filename: true,
        },
      );
    } catch (e) {
      _cancelTokens.remove(model.filename);
      rethrow;
    }
  }

  void cancelDownload(String filename) {
    if (Platform.isAndroid) {
      _downloadChannel.invokeMethod('cancelDownload', {'filename': filename});
      _nativeDownloadIds.remove(filename);
    } else {
      _cancelTokens[filename]?.cancel('cancelled');
      _cancelTokens.remove(filename);
    }

    final current = state.downloads[filename];
    if (current != null) {
      state = state.copyWith(
        downloads: {
          ...state.downloads,
          filename: current.copyWith(status: DownloadStatus.idle, progress: 0),
        },
      );
    }
  }

  Future<void> deleteModel(String filename) async {
    final modelsDir = await getModelsDir();
    if (modelsDir == null) return;

    final file = File(p.join(modelsDir, filename));
    if (await file.exists()) await file.delete();

    final partFile = File(p.join(modelsDir, '$filename.part'));
    if (await partFile.exists()) await partFile.delete();

    final downloaded = Map<String, bool>.from(state.downloadedModels);
    downloaded.remove(filename);
    state = state.copyWith(downloadedModels: downloaded);
  }

  bool isDownloaded(String filename) {
    return state.downloadedModels[filename] == true;
  }

  List<AiCatalogModel> getModelsByCategory(ModelCategory category) {
    return state.models.where((m) => m.category == category).toList();
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

final modelCatalogProvider = StateNotifierProvider<ModelCatalogNotifier, ModelCatalogState>((ref) {
  return ModelCatalogNotifier(ref);
});
