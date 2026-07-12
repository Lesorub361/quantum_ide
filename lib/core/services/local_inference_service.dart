import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'inference_engine.dart';
import 'package:quantum_ide/core/utils/resumable_downloader.dart';
import 'package:quantum_ide/core/services/chat_settings_service.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
// model_catalog_service types are used only via re-export in local_models_dialog; no direct import needed here


enum LocalModelStatus { idle, downloading, loading, ready, error }

class LocalModelInfo {
  final String name;
  final String filename;
  final String url;
  final String size;
  final String description;
  final String template;
  final bool isVision;

  const LocalModelInfo({
    required this.name,
    required this.filename,
    required this.url,
    required this.size,
    required this.description,
    this.template = 'chatml',
    this.isVision = false,
  });

  int get sizeBytes {
    final lower = size.toLowerCase();
    if (lower.contains('gb')) {
      final match = RegExp(r'([0-9.]+)').firstMatch(lower);
      final num = match != null ? double.tryParse(match.group(1) ?? '0') ?? 0 : 0;
      return (num * 1024 * 1024 * 1024).toInt();
    } else if (lower.contains('mb')) {
      final match = RegExp(r'([0-9.]+)').firstMatch(lower);
      final num = match != null ? double.tryParse(match.group(1) ?? '0') ?? 0 : 0;
      return (num * 1024 * 1024).toInt();
    }
    return 0;
  }
}

class DownloadProgress {
  final String filename;
  double progress = 0;
  int downloadedBytes = 0;
  int totalBytes = 0;
  double bytesPerSecond = 0;
  bool isPaused = false;
  final DateTime startedAt = DateTime.now();

  DownloadProgress({required this.filename});

  Duration? get eta {
    final speed = bytesPerSecond;
    final total = totalBytes;
    if (speed <= 0 || total <= 0) return null;
    final remaining = total - downloadedBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / speed).ceil());
  }
}

class LocalInferenceState {
  final LocalModelStatus status;
  final LocalModelInfo? loadedModel;
  final double downloadProgress;
  final double loadProgress;
  final String? error;
  final String? generationSource;
  final int tokenCount;
  final double tokensPerSecond;
  final List<LocalModelInfo> availableModels;
  final List<String> downloadedFiles;
  final Map<String, DownloadProgress> activeDownloads;
  // GPU / acceleration info (from reference project)
  final String gpuName;
  final int gpuLayersUsed;
  final bool isGpuAccelerated;
  final String loadedModelRuntime;
  final String loadedBackend;
  // Context window tracking
  final int contextTokensUsed;
  final int contextTokensTotal;
  // Streaming text buffer for UI
  final String streamingText;
  // Device info
  final String deviceTier;
  final int deviceRamMb;
  final bool isTensorSoC;

  LocalInferenceState({
    this.status = LocalModelStatus.idle,
    this.loadedModel,
    this.downloadProgress = 0,
    this.loadProgress = 0,
    this.error,
    this.generationSource,
    this.tokenCount = 0,
    this.tokensPerSecond = 0,
    this.availableModels = const [],
    this.downloadedFiles = const [],
    this.activeDownloads = const {},
    this.gpuName = '',
    this.gpuLayersUsed = 0,
    this.isGpuAccelerated = false,
    this.loadedModelRuntime = '',
    this.loadedBackend = '',
    this.contextTokensUsed = 0,
    this.contextTokensTotal = 0,
    this.streamingText = '',
    this.deviceTier = 'mid',
    this.deviceRamMb = 0,
    this.isTensorSoC = false,
  });

  LocalInferenceState copyWith({
    LocalModelStatus? status,
    LocalModelInfo? loadedModel,
    double? downloadProgress,
    double? loadProgress,
    String? error,
    String? generationSource,
    int? tokenCount,
    double? tokensPerSecond,
    List<LocalModelInfo>? availableModels,
    List<String>? downloadedFiles,
    Map<String, DownloadProgress>? activeDownloads,
    String? gpuName,
    int? gpuLayersUsed,
    bool? isGpuAccelerated,
    String? loadedModelRuntime,
    String? loadedBackend,
    int? contextTokensUsed,
    int? contextTokensTotal,
    String? streamingText,
    String? deviceTier,
    int? deviceRamMb,
    bool? isTensorSoC,
  }) {
    return LocalInferenceState(
      status: status ?? this.status,
      loadedModel: loadedModel ?? this.loadedModel,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      loadProgress: loadProgress ?? this.loadProgress,
      error: error ?? this.error,
      generationSource: generationSource ?? this.generationSource,
      tokenCount: tokenCount ?? this.tokenCount,
      tokensPerSecond: tokensPerSecond ?? this.tokensPerSecond,
      availableModels: availableModels ?? this.availableModels,
      downloadedFiles: downloadedFiles ?? this.downloadedFiles,
      activeDownloads: activeDownloads ?? this.activeDownloads,
      gpuName: gpuName ?? this.gpuName,
      gpuLayersUsed: gpuLayersUsed ?? this.gpuLayersUsed,
      isGpuAccelerated: isGpuAccelerated ?? this.isGpuAccelerated,
      loadedModelRuntime: loadedModelRuntime ?? this.loadedModelRuntime,
      loadedBackend: loadedBackend ?? this.loadedBackend,
      contextTokensUsed: contextTokensUsed ?? this.contextTokensUsed,
      contextTokensTotal: contextTokensTotal ?? this.contextTokensTotal,
      streamingText: streamingText ?? this.streamingText,
      deviceTier: deviceTier ?? this.deviceTier,
      deviceRamMb: deviceRamMb ?? this.deviceRamMb,
      isTensorSoC: isTensorSoC ?? this.isTensorSoC,
    );
  }
}

class LocalInferenceNotifier extends StateNotifier<LocalInferenceState> {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final InferenceEngine _engine = InferenceEngine();

  static const List<LocalModelInfo> builtinModels = [
    // Text Models
    LocalModelInfo(
      name: 'Qwen2.5-3B Instruct (Q4_K_M)',
      filename: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      size: '2.1 GB',
      description: 'Best balance of speed and quality for mobile',
      template: 'chatml',
    ),
    LocalModelInfo(
      name: 'Phi-3.5 Mini Instruct (Q4_K_M)',
      filename: 'phi-3.5-mini-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      size: '2.2 GB',
      description: "Microsoft's compact reasoning model",
      template: 'phi',
    ),
    LocalModelInfo(
      name: 'Gemma 2 2B Instruct (Q4_K_M)',
      filename: 'gemma-2-2b-it-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      size: '1.71 GB',
      description: "Google's lightweight general chat model — fast and smart",
      template: 'gemma',
    ),
    LocalModelInfo(
      name: 'Llama-3.2-3B Uncensored (Q4_K_M)',
      filename: 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
      size: '2.1 GB',
      description: 'Uncensored Llama 3.2 3B — Smarter and unrestricted',
      template: 'llama3',
    ),
    LocalModelInfo(
      name: 'Llama-3.2-1B Instruct (Q4_K_M)',
      filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      size: '0.8 GB',
      description: 'Ultra-lightweight text model',
      template: 'llama3',
    ),
    LocalModelInfo(
      name: 'SmolLM2-1.7B-Uncensored (Q4_K_M)',
      filename: 'smollm2-1.7b-instruct-uncensored-q4_k_m.gguf',
      url: 'https://huggingface.co/mradermacher/SmolLM2-1.7B-Instruct-Uncensored-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Uncensored.Q4_K_M.gguf',
      size: '1.1 GB',
      description: 'Ultra-compact and unrestricted assistant',
      template: 'chatml',
    ),
    LocalModelInfo(
      name: 'Dolphin-3.0-Qwen2.5-1.5B (Q4_K_M)',
      filename: 'dolphin-3.0-qwen2.5-1.5b-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Dolphin3.0-Qwen2.5-1.5B-GGUF/resolve/main/Dolphin3.0-Qwen2.5-1.5B-Q4_K_M.gguf',
      size: '1.1 GB',
      description: 'Uncensored Dolphin 3.0 — Fast and unrestricted',
      template: 'chatml',
    ),
    LocalModelInfo(
      name: 'Gemma-2-2B-Abliterated (Q4_K_M)',
      filename: 'gemma-2-2b-it-abliterated-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/gemma-2-2b-it-abliterated-GGUF/resolve/main/gemma-2-2b-it-abliterated-Q4_K_M.gguf',
      size: '1.6 GB',
      description: 'Abliterated — Permanently uncensored, very smart',
      template: 'gemma',
    ),
    LocalModelInfo(
      name: 'Kimi Moonlight 16B-A3B (Q3_K_S)',
      filename: 'moonlight-16b-a3b-instruct-q3_k_s.gguf',
      url: 'https://huggingface.co/mmnga/Moonlight-16B-A3B-Instruct-gguf/resolve/main/Moonlight-16B-A3B-Instruct-Q3_K_S.gguf',
      size: '7.1 GB',
      description: 'Moonshot AI (Kimi) — 3B active MoE, high quality',
      template: 'chatml',
    ),
    // Vision Models
    LocalModelInfo(
      name: 'Qwen2-VL-2B Instruct (Q4_K_M)',
      filename: 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
      size: '1.5 GB',
      description: 'Vision-capable — can understand images',
      template: 'chatml',
      isVision: true,
    ),
  ];

  final Ref _ref;

  LocalInferenceNotifier(this._ref) : super(LocalInferenceState()) {
    _init();
  }

  Future<void> _init() async {
    await _detectDeviceInfo();
    await _loadAvailableModels();
    await _loadDownloadedFiles();
  }

  Future<void> _detectDeviceInfo() async {
    try {
      int ramMb = 0;
      bool tensor = false;
      
      if (!kIsWeb && Platform.isAndroid) {
        // Use MethodChannel to get total RAM on Android
        const channel = MethodChannel('com.example.quantum_ide/device_info');
        try {
          final result = await channel.invokeMethod('getDeviceInfo');
          if (result is Map) {
            ramMb = (result['totalMemoryMb'] as int?) ?? 0;
            final model = (result['model'] as String?) ?? '';
            final product = (result['product'] as String?) ?? '';
            tensor = model.toLowerCase().contains('pixel') || 
                     product.toLowerCase().contains('pixel');
          }
        } catch (_) {
          // Fallback: assume mid-range device
          ramMb = 4000;
        }
      } else if (!kIsWeb && Platform.isIOS) {
        // iOS: estimate from device model via MethodChannel
        const channel = MethodChannel('com.example.quantum_ide/device_info');
        try {
          final result = await channel.invokeMethod('getDeviceInfo');
          if (result is Map) {
            ramMb = (result['totalMemoryMb'] as int?) ?? 6000;
          } else {
            ramMb = 6000;
          }
        } catch (_) {
          ramMb = 6000;
        }
      } else {
        // Desktop fallback
        ramMb = 16000;
      }

      String tier;
      if (ramMb > 8000) {
        tier = 'ultra';
      } else if (ramMb > 5000) {
        tier = 'high';
      } else if (ramMb > 3000) {
        tier = 'mid';
      } else {
        tier = 'low';
      }

      debugPrint('[LocalInference] Device: tier=$tier, RAM=${ramMb}MB, Tensor=$tensor');
      state = state.copyWith(
        deviceTier: tier,
        deviceRamMb: ramMb,
        isTensorSoC: tensor,
      );
    } catch (e) {
      debugPrint('[LocalInference] Device detection failed: $e');
      state = state.copyWith(deviceTier: 'mid', deviceRamMb: 4000);
    }
  }

  Future<void> _loadAvailableModels() async {
    // Start with builtin catalog
    final models = List<LocalModelInfo>.from(builtinModels);
    
    // Also discover any downloaded files not in the catalog
    try {
      final dir = Directory(await _getModelsDir());
      if (await dir.exists()) {
        final files = await dir.list().toList();
        for (final f in files.whereType<File>()) {
          final name = p.basename(f.path);
          final isSupported = name.endsWith('.gguf') || name.endsWith('.litertlm') || name.endsWith('.tflite');
          if (isSupported && !models.any((m) => m.filename == name)) {
            // Create a stub entry for user-downloaded models
            final sizeBytes = await f.length();
            final sizeStr = sizeBytes > 1024 * 1024 * 1024
                ? '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB'
                : '${(sizeBytes / 1024 / 1024).toStringAsFixed(0)} MB';
            models.add(LocalModelInfo(
              name: name.replaceAll('.gguf', '').replaceAll('.litertlm', '').replaceAll('.tflite', ''),
              filename: name,
              url: '',
              size: sizeStr,
              description: 'Downloaded model',
              template: 'chatml',
            ));
          }
        }
      }
    } catch (_) {}
    
    state = state.copyWith(availableModels: models);
  }

  Future<void> _loadDownloadedFiles() async {
    try {
      final dir = Directory(await _getModelsDir());
      if (!await dir.exists()) await dir.create(recursive: true);

      final files = await dir.list().toList();
      final downloaded = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.gguf') || f.path.endsWith('.litertlm') || f.path.endsWith('.tflite'))
          .map((f) => p.basename(f.path))
          .toList();

      state = state.copyWith(downloadedFiles: downloaded);
    } catch (e) {
      debugPrint('Error loading downloaded files: $e');
    }
  }

  bool isDownloaded(String filename) {
    return state.downloadedFiles.contains(filename);
  }

  /// Returns the canonical models directory for the current platform.
  /// Android/iOS → Documents/models (same as ModelCatalogNotifier on mobile).
  /// Desktop     → temp/quantum_models (fallback, llama-server manages its own path).
  Future<String> _getModelsDir() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(dir.path, 'models'));
      if (!await modelsDir.exists()) await modelsDir.create(recursive: true);
      return modelsDir.path;
    }
    // Desktop fallback
    final tmp = p.join(Directory.systemTemp.path, 'quantum_models');
    await Directory(tmp).create(recursive: true);
    return tmp;
  }

  Future<String> get modelsDir async => _getModelsDir();

  static const _downloadChannel = MethodChannel('com.example.quantum_ide/download');
  static const _downloadEventChannel = EventChannel('com.example.quantum_ide/download_progress');
  final Map<String, int> _nativeDownloadIds = {};

  Future<void> downloadModel(LocalModelInfo model) async {
    if (isDownloaded(model.filename)) {
      state = state.copyWith(
        status: LocalModelStatus.ready,
        loadedModel: model,
      );
      return;
    }

    final progress = DownloadProgress(filename: model.filename);
    state = state.copyWith(
      activeDownloads: {...state.activeDownloads, model.filename: progress},
      error: null,
    );

    try {
      final modelsPath = await _getModelsDir();

      // On Android, try native DownloadManager first (3-5x faster)
      if (Platform.isAndroid) {
        try {
          final result = await _downloadChannel.invokeMethod<Map>('downloadModel', {
            'url': model.url,
            'filename': model.filename,
            'modelsDir': modelsPath,
          });
          
          if (result != null) {
            final downloadId = result['downloadId'] as int;
            _nativeDownloadIds[model.filename] = downloadId;
            
            // Poll download status
            _pollNativeDownload(model.filename, progress);
            return;
          }
        } catch (e) {
          debugPrint('[LocalInference] Native download failed, falling back to Dio: $e');
        }
      }

      // Fallback: Dio download (iOS/Desktop)
      final filePath = p.join(modelsPath, model.filename);
      final cancelToken = CancelToken();
      _cancelTokens[model.filename] = cancelToken;

      await ResumableDownloader.download(
        url: model.url,
        savePath: filePath,
        cancelToken: cancelToken,
        onProgress: (received, total, speed) {
          progress.downloadedBytes = received;
          progress.totalBytes = total;
          progress.progress = total > 0 ? received / total : 0.0;
          progress.bytesPerSecond = speed;
          
          state = state.copyWith(
            activeDownloads: {...state.activeDownloads},
          );
        },
      );

      final newDownloads = {...state.activeDownloads};
      newDownloads.remove(model.filename);
      
      state = state.copyWith(
        activeDownloads: newDownloads,
        downloadedFiles: [...state.downloadedFiles, model.filename],
      );
      
      await _saveDownloadedList();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        final progress = state.activeDownloads[model.filename];
        if (progress != null) {
          progress.isPaused = true;
        }
        state = state.copyWith(
          activeDownloads: {...state.activeDownloads},
        );
      } else {
        state = state.copyWith(
          error: 'Download failed: ${e.message}',
          activeDownloads: {...state.activeDownloads}..remove(model.filename),
        );
      }
    } catch (e) {
      state = state.copyWith(
        error: 'Download failed: $e',
        activeDownloads: {...state.activeDownloads}..remove(model.filename),
      );
    }
  }

  /// Polls native Android DownloadManager or listens to EventChannel progress updates
  void _pollNativeDownload(String filename, DownloadProgress progress) {
    StreamSubscription? sub;
    
    void fallbackToPolling() {
      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        if (!state.activeDownloads.containsKey(filename)) {
          timer.cancel();
          return;
        }
        try {
          final result = await _downloadChannel.invokeMethod<Map>('getDownloadStatus', {
            'filename': filename,
          });
          if (result == null) {
            timer.cancel();
            _onNativeDownloadComplete(filename);
            return;
          }
          final status = result['status'] as int;
          final downloaded = result['downloaded'] as int;
          final total = result['total'] as int;
          
          progress.downloadedBytes = downloaded;
          progress.totalBytes = total;
          progress.progress = total > 0 ? downloaded / total : 0.0;
          
          final elapsed = DateTime.now().difference(progress.startedAt).inMilliseconds;
          if (elapsed > 0) {
            progress.bytesPerSecond = downloaded / (elapsed / 1000.0);
          }
          state = state.copyWith(activeDownloads: {...state.activeDownloads});
          if (status == 16) {
            timer.cancel();
            _onNativeDownloadComplete(filename);
          }
        } catch (_) {
          timer.cancel();
        }
      });
    }

    try {
      sub = _downloadEventChannel.receiveBroadcastStream({'filename': filename}).listen((event) {
        if (event is Map) {
          final String? eventFilename = event['filename'] as String?;
          if (eventFilename != filename) return;
          final status = event['status'] as int;
          final downloaded = event['downloaded'] as int;
          final total = event['total'] as int;
          
          progress.downloadedBytes = downloaded;
          progress.totalBytes = total;
          progress.progress = total > 0 ? downloaded / total : 0.0;
          
          final elapsed = DateTime.now().difference(progress.startedAt).inMilliseconds;
          if (elapsed > 0) {
            progress.bytesPerSecond = downloaded / (elapsed / 1000.0);
          }
          state = state.copyWith(activeDownloads: {...state.activeDownloads});
          if (status == 16) {
            sub?.cancel();
            _onNativeDownloadComplete(filename);
          }
        }
      }, onError: (_) {
        sub?.cancel();
        fallbackToPolling();
      }, onDone: () {
        sub?.cancel();
      }, cancelOnError: true);
    } catch (_) {
      fallbackToPolling();
    }
  }

  void _onNativeDownloadComplete(String filename) {
    final newDownloads = {...state.activeDownloads};
    newDownloads.remove(filename);
    _nativeDownloadIds.remove(filename);
    
    state = state.copyWith(
      activeDownloads: newDownloads,
      downloadedFiles: [...state.downloadedFiles, filename],
    );
    
    _saveDownloadedList();
  }

  void cancelDownload(String filename) {
    _cancelTokens[filename]?.cancel('paused');
    _cancelTokens.remove(filename);
    
    final progress = state.activeDownloads[filename];
    if (progress != null) {
      progress.isPaused = true;
      state = state.copyWith(
        activeDownloads: {...state.activeDownloads},
      );
    }
  }

  Future<void> deleteModel(String filename) async {
    try {
      final modelsPath = await _getModelsDir();
      final filePath = p.join(modelsPath, filename);
      final file = File(filePath);

      if (await file.exists()) await file.delete();
      // Also remove any partial download
      final partFile = File('$filePath.part');
      if (await partFile.exists()) await partFile.delete();

      state = state.copyWith(
        downloadedFiles: state.downloadedFiles.where((f) => f != filename).toList(),
        loadedModel: state.loadedModel?.filename == filename ? null : state.loadedModel,
        status: state.loadedModel?.filename == filename ? LocalModelStatus.idle : state.status,
      );

      await _saveDownloadedList();
    } catch (e) {
      state = state.copyWith(error: 'Delete failed: $e');
    }
  }

  Future<void> _saveDownloadedList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('downloaded_models', state.downloadedFiles);
  }

  Future<void> loadModel(LocalModelInfo model) async {
    if (!isDownloaded(model.filename)) {
      state = state.copyWith(
        status: LocalModelStatus.error,
        error: 'Model not found. Please download first.',
      );
      return;
    }

    // Guard: native inference engine only works on Android/iOS
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      state = state.copyWith(
        status: LocalModelStatus.error,
        error: 'Native local inference is only supported on Android and iOS.\n'
            'On desktop, use llama-server via the Models panel.',
      );
      return;
    }

    state = state.copyWith(
      status: LocalModelStatus.loading,
      loadProgress: 0,
      error: null,
    );

    try {
      final modelsPath = await _getModelsDir();
      final filePath = p.join(modelsPath, model.filename);

      // Verify file exists and has content
      final file = File(filePath);
      if (!await file.exists()) {
        state = state.copyWith(
          status: LocalModelStatus.error,
          error: 'Model file not found on disk: ${model.filename}\nPlease re-download.',
        );
        return;
      }
      final fileSize = await file.length();
      if (fileSize < 1024 * 1024) {
        state = state.copyWith(
          status: LocalModelStatus.error,
          error: 'Model file seems corrupted (only $fileSize bytes).\nPlease delete and re-download.',
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final settings = _ref.read(chatSettingsProvider);
      final isLiteRt = model.filename.endsWith('.litertlm');
      final liteRtMode = settings.liteRtPerformanceMode;

      // ── GPU Crash Persistence ──
      // IMPORTANT: We save the crash-detection flag BEFORE calling loadModel.
      // A native SIGSEGV/SIGABRT will kill the process and Dart won't get a
      // chance to write to SharedPreferences AFTER the crash — so we must
      // mark the intent before.
      final hadPendingGpuLoad = prefs.getBool('gpu_load_pending') ?? false;
      if (hadPendingGpuLoad) {
        // Previous launch crashed during GPU load — upgrade to crash detected
        await prefs.setBool('gpu_load_pending', false);
        await prefs.setBool('gpu_crash_detected', true);
        final crashedModel = prefs.getString('gpu_load_model') ?? model.filename;
        await _logInferenceError(
          'ВНИМАНИЕ: При предыдущем запуске произошел вылет приложения (Native Crash / SIGSEGV) '
          'при попытке загрузить модель "$crashedModel" на GPU.\n'
          'Система безопасности автоматически заблокировала GPU (Vulkan) для предотвращения новых вылетов и переключила инференс на CPU.'
        );
        debugPrint('[LocalInference] Previous GPU load was pending → crash detected, switching to CPU');
      }
      final gpuCrashDetected = prefs.getBool('gpu_crash_detected') ?? false;

      // ── First-time load safety ──
      // On the very first load attempt for this model, always start with CPU
      // to confirm the model is valid. GPU can be enabled later.
      final firstLoadKey = 'model_first_load_${model.filename}';
      final hasEverLoadedSuccessfully = prefs.getBool(firstLoadKey) ?? false;
      final forceFirstTimeCpu = !hasEverLoadedSuccessfully;

      // Determine if we should force CPU
      bool forceCpu;
      if (isLiteRt) {
        forceCpu = liteRtMode == 'cpu_safe' ||
            (liteRtMode == 'auto_fast' && gpuCrashDetected);
      } else {
        // For GGUF: force CPU on first-ever load OR if GPU previously crashed
        forceCpu = liteRtMode == 'cpu_safe' || gpuCrashDetected || forceFirstTimeCpu;
      }

      // ── Safe contextSize for mobile ──
      // On first-ever load cap at 2048 to avoid OOM on unknown hardware.
      // Once model has loaded at least once, trust the user's settings fully.
      final int userContextSize = settings.contextSize.clamp(512, 8192);
      final int safeContextSize = hasEverLoadedSuccessfully
          ? userContextSize
          : userContextSize.clamp(512, 2048);
      debugPrint('[LocalInference] contextSize: user=$userContextSize, safe=$safeContextSize, firstTime=${!hasEverLoadedSuccessfully}');

      // Detect Google Tensor SoC (Pixel 6/7/8) — known Gemma issues
      bool isTensorSoC = false;
      try {
        final deviceModel = await _getDeviceModel();
        isTensorSoC = deviceModel.toLowerCase().contains('pixel') ||
            deviceModel.toLowerCase().contains('tensor');
      } catch (_) {}

      debugPrint('[LocalInference] Loading ${model.filename}'
        ' (LiteRT=$isLiteRt, forceCpu=$forceCpu, firstTime=$forceFirstTimeCpu,'
        ' ctx=$safeContextSize, tensor=$isTensorSoC, gpuCrash=$gpuCrashDetected)');

      await _logInferenceError(
        'Попытка загрузки модели: "${model.filename}"\n'
        '• Движок: ${isLiteRt ? "LiteRT-LM" : "llama.cpp (GGUF)"}\n'
        '• Режим: ${forceCpu ? "CPU (Безопасный)" : "GPU (Vulkan ускорение)"}\n'
        '• Размер контекста: $safeContextSize токенов\n'
        '• Google Tensor SoC: $isTensorSoC\n'
        '• Предыдущие GPU сбои: $gpuCrashDetected'
      );

      // ── CRITICAL: Mark GPU load BEFORE calling native code ──
      // If we crash inside _engine.loadModel(), the app dies and we never
      // reach the code after it. By writing the flag first, the next app
      // launch will detect the previous crash.
      if (!forceCpu) {
        await prefs.setBool('gpu_load_pending', true);
        await prefs.setString('gpu_load_model', model.filename);
        // Flush to disk immediately so it survives a process kill
        await prefs.reload(); // force sync
      }

      // ── First attempt ──
      LoadResult result;
      try {
        result = await _engine.loadModel(
          modelPath: filePath,
          contextSize: safeContextSize,
          deviceTier: state.deviceTier,
          isTensorSoC: isTensorSoC,
          liteRtPerformanceMode: liteRtMode,
          forceLiteRtCpu: forceCpu,
          clearLiteRtCache: gpuCrashDetected,
          onProgress: (prog) {
            state = state.copyWith(loadProgress: prog);
          },
        );
      } catch (loadError) {
        debugPrint('[LocalInference] Model load crashed: $loadError');
        await _logInferenceError('Model load CRASHED: $loadError for model ${model.filename}');
        // If GPU was enabled, mark crash and retry with CPU
        if (!forceCpu) {
          await prefs.setBool('gpu_crash_detected', true);
          await prefs.setBool('gpu_load_pending', false);
          state = state.copyWith(loadProgress: 0, error: null);
          try {
            result = await _engine.loadModel(
              modelPath: filePath,
              contextSize: userContextSize,
              deviceTier: state.deviceTier,
              isTensorSoC: isTensorSoC,
              liteRtPerformanceMode: 'cpu_safe',
              forceLiteRtCpu: true,
              clearLiteRtCache: true,
              onProgress: (prog) {
                state = state.copyWith(loadProgress: prog);
              },
            );
          } catch (cpuError) {
            debugPrint('[LocalInference] CPU fallback also failed: $cpuError');
            await _logInferenceError('CPU fallback CRASHED: $cpuError for model ${model.filename}');
            await prefs.setBool('gpu_load_pending', false);
            state = state.copyWith(
              status: LocalModelStatus.error,
              error: 'Failed to load model on both GPU and CPU.\nModel may be incompatible with your device.\n\nError: $cpuError',
            );
            return;
          }
        } else {
          await prefs.setBool('gpu_load_pending', false);
          state = state.copyWith(
            status: LocalModelStatus.error,
            error: 'Failed to load model: $loadError',
          );
          return;
        }
      }

      // ── GPU Crash Recovery: retry with CPU if GPU failed ──
      if (!result.success && !forceCpu) {
        final errorMsg = result.message.toLowerCase();
        final isGpuError = errorMsg.contains('gpu') ||
            errorMsg.contains('vulkan') ||
            errorMsg.contains('layers') ||
            errorMsg.contains('signal') ||
            errorMsg.contains('crash') ||
            errorMsg.contains('abort') ||
            errorMsg.contains('segfault') ||
            errorMsg.contains('failed');
        
        if (isGpuError) {
          debugPrint('[LocalInference] GPU load failed, retrying with CPU: ${result.message}');
          await prefs.setBool('gpu_crash_detected', true);
          await prefs.setBool('gpu_load_pending', false);
          state = state.copyWith(loadProgress: 0);

          // CPU retry: use full user context — CPU handles any size
          final cpuContextSize = userContextSize;
          debugPrint('[LocalInference] GPU failed, CPU retry with ctx=$cpuContextSize');
          result = await _engine.loadModel(
            modelPath: filePath,
            contextSize: cpuContextSize,
            deviceTier: state.deviceTier,
            isTensorSoC: isTensorSoC,
            liteRtPerformanceMode: 'cpu_safe',
            forceLiteRtCpu: true,
            clearLiteRtCache: true,
            onProgress: (prog) {
              state = state.copyWith(loadProgress: prog);
            },
          );
        }
      }

      // Clear pending flag on success
      if (result.success) {
        await prefs.setBool('gpu_load_pending', false);
        await prefs.setString('gpu_load_model', '');
        // Mark this model as successfully loaded at least once
        await prefs.setBool('model_first_load_${model.filename}', true);
        // If GPU load succeeded, clear crash detection
        if (result.backend == 'gpu') {
          await prefs.setBool('gpu_crash_detected', false);
        }

        final loadInfo = safeContextSize < settings.contextSize
            ? 'Loaded with safe context ($safeContextSize tokens). '
              'Increase context in Settings → Local Model if needed.'
            : null;

        state = state.copyWith(
          status: LocalModelStatus.ready,
          loadedModel: model,
          loadProgress: 1,
          error: loadInfo, // show info message if we downgraded context
          gpuName: result.gpuName,
          gpuLayersUsed: result.gpuLayers,
          isGpuAccelerated: result.backend == 'gpu' || result.gpuLayers > 0,
          loadedModelRuntime: result.runtime,
          loadedBackend: result.backend,
          contextTokensUsed: 0,
          contextTokensTotal: safeContextSize,
        );
        await _ref.read(aiServiceProvider).setProvider('local_edge');
        debugPrint('[LocalInference] ✓ Model loaded: ${result.runtime} (${result.backend}),'
          ' GPU: ${result.gpuName}, layers: ${result.gpuLayers}, ctx=$safeContextSize');
      } else {
        await prefs.setBool('gpu_load_pending', false);
        state = state.copyWith(
          status: LocalModelStatus.error,
          error: result.message,
        );
        await _logInferenceError('Model load failed: ${result.message} for model ${model.filename}');
      }
    } catch (e, stackTrace) {
      debugPrint('[LocalInference] Model load crashed: $e\n$stackTrace');
      await _logInferenceError('Model load crashed with exception: $e', stackTrace);
      // Save crash state so next attempt uses CPU
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('gpu_load_pending', false);
        await prefs.setBool('gpu_crash_detected', true);
      } catch (_) {}
      
      state = state.copyWith(
        status: LocalModelStatus.error,
        error: 'Failed to load model: $e\n\nTry: restart the app or use a smaller model.',
      );
    }
  }

  /// Write inference errors to a local log file inside the project directory
  Future<void> _logInferenceError(String error, [StackTrace? stack]) async {
    try {
      final workspacePath = _ref.read(workspaceProvider).currentPath;
      if (workspacePath == null) return;
      
      final logDir = Directory('$workspacePath/.quantum');
      if (!await logDir.exists()) await logDir.create(recursive: true);
      
      final logFile = File('$workspacePath/.quantum/inference_errors.log');
      final timestamp = DateTime.now().toLocal().toString().substring(0, 19);
      final sb = StringBuffer();
      sb.writeln('========================================');
      sb.writeln('[$timestamp] INFERENCE ERROR LOG');
      sb.writeln('Error: $error');
      if (stack != null) {
        sb.writeln('StackTrace:\n$stack');
      }
      sb.writeln('========================================\n');
      
      await logFile.writeAsString(sb.toString(), mode: FileMode.append);
      debugPrint('[LocalInference] Saved error log to .quantum/inference_errors.log');
    } catch (e) {
      debugPrint('[LocalInference] Failed to save error log file: $e');
    }
  }

  /// Get device model string for Tensor SoC detection
  Future<String> _getDeviceModel() async {
    try {
      const channel = MethodChannel('com.example.quantum_ide/native');
      final result = await channel.invokeMethod<String>('getDeviceModel');
      return result ?? '';
    } catch (_) {
      return '';
    }
  }

  void unloadModel() {
    _engine.dispose();
    state = state.copyWith(
      status: LocalModelStatus.idle,
      loadedModel: null,
      gpuName: '',
      gpuLayersUsed: 0,
      isGpuAccelerated: false,
      loadedModelRuntime: '',
      loadedBackend: '',
      contextTokensUsed: 0,
      contextTokensTotal: 0,
      tokenCount: 0,
      tokensPerSecond: 0,
      generationSource: null,
      streamingText: '',
      error: null,
    );
  }

  /// Clears all crash / first-load flags so the next loadModel() attempt
  /// uses the full context size from Settings.
  Future<void> resetModelLoadFlags({String? filename}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('gpu_crash_detected', false);
      await prefs.setBool('gpu_load_pending', false);
      await prefs.setString('gpu_load_model', '');
      if (filename != null) {
        await prefs.setBool('model_first_load_$filename', false);
      } else {
        // Clear all first-load flags (covers all cached models)
        final keys = prefs.getKeys();
        for (final k in keys) {
          if (k.startsWith('model_first_load_')) {
            await prefs.remove(k);
          }
        }
      }
      debugPrint('[LocalInference] Load flags reset (filename=$filename)');
      state = state.copyWith(error: null);
    } catch (e) {
      debugPrint('[LocalInference] Failed to reset load flags: $e');
    }
  }

  Future<String> generate({
    required String prompt,
    required List<Map<String, String>> history,
    String? systemInstruction,
    void Function(String token)? onToken,
  }) async {
    if (state.status != LocalModelStatus.ready || state.loadedModel == null) {
      return 'Error: No model loaded. Please download and load a model first.';
    }

    state = state.copyWith(
      generationSource: 'local',
      tokenCount: 0,
      tokensPerSecond: 0.0,
      streamingText: '',
    );
    final buffer = StringBuffer();
    final startTime = DateTime.now();
    DateTime? firstVisibleTokenAt;

    try {
      // Truncate history to avoid exceeding token limits
      final truncatedHistory = _truncateHistory(history, maxChars: 8000);
      
      // Truncate system prompt if too long for local model.
      // 8000 chars keeps project file listing + key instructions intact.
      String sysPrompt = systemInstruction ?? 'You are a helpful coding assistant.';
      if (sysPrompt.length > 8000) {
        // Smart truncation: always keep the END of the prompt (project context is appended last)
        // and keep the beginning (identity/mode instructions).
        // Cut the middle section (tech stack details) if needed.
        const half = 4000;
        final start = sysPrompt.substring(0, half);
        final end = sysPrompt.substring(sysPrompt.length - half);
        sysPrompt = '$start\n\n[...технические детали сокращены для локальной модели...]\n\n$end';
      }
      
      final content = await _engine.generate(
        prompt: prompt,
        conversationHistory: truncatedHistory,
        systemPrompt: sysPrompt,
        modelName: state.loadedModel!.name,
        maxTokens: 2048,
        temperature: 0.7,
        onToken: (token) {
          firstVisibleTokenAt ??= DateTime.now();
          buffer.write(token);
          
          // Update token count and TPS in real-time
          final tokenCount = buffer.toString().split(' ').length;
          final speedStart = firstVisibleTokenAt ?? startTime;
          final elapsedSeconds = DateTime.now().difference(speedStart).inMilliseconds / 1000.0;
          final tps = elapsedSeconds > 0 ? tokenCount / elapsedSeconds : 0.0;
          
          state = state.copyWith(
            tokenCount: tokenCount,
            tokensPerSecond: tps,
            streamingText: buffer.toString(),
          );
          
          onToken?.call(token);
        },
      );

      // Refresh context info after generation
      await refreshContextInfo();
      
      state = state.copyWith(
        generationSource: null,
        streamingText: '',
      );

      return content;
    } catch (e) {
      state = state.copyWith(
        generationSource: null,
        streamingText: '',
        error: 'Generation failed: $e',
      );
      return 'Error: $e';
    }
  }

  /// Refresh context token usage from the native engine
  Future<void> refreshContextInfo() async {
    try {
      final info = await _engine.getContextInfo();
      if (info != null) {
        state = state.copyWith(
          contextTokensUsed: info.tokensUsed,
          contextTokensTotal: info.contextSize,
        );
      }
    } catch (_) {}
  }

  /// Truncate conversation history to fit within token limits.
  /// Keeps the most recent messages that fit within maxChars.
  List<Map<String, String>> _truncateHistory(
    List<Map<String, String>> history, {
    int maxChars = 12000,
  }) {
    if (history.isEmpty) return history;
    
    int totalChars = 0;
    int startIndex = history.length;
    
    // Walk backwards from the end, accumulating characters
    for (int i = history.length - 1; i >= 0; i--) {
      final msg = history[i];
      final msgChars = (msg['content']?.length ?? 0) + 20; // +20 for role overhead
      if (totalChars + msgChars > maxChars) {
        startIndex = i + 1;
        break;
      }
      totalChars += msgChars;
      startIndex = i;
    }
    
    // Always keep at least the last 2 messages for context continuity
    if (startIndex > history.length - 2) {
      startIndex = history.length - 2;
    }
    if (startIndex < 0) startIndex = 0;
    
    return history.sublist(startIndex);
  }

  /// Resets the conversation history and token counter without unloading
  /// the model — useful when context is full or a new topic starts.
  /// Optionally saves a summary to session memory before resetting.
  Future<void> resetContext({List<Map<String, String>>? messagesToSave, String? workspacePath}) async {
    // Save memory BEFORE reset if we have messages and workspace
    if (messagesToSave != null && messagesToSave.isNotEmpty && workspacePath != null) {
      await saveSessionMemory(messagesToSave, workspacePath);
    }
    try {
      await _engine.resetConversation();
    } catch (_) {}
    state = state.copyWith(tokenCount: 0, tokensPerSecond: 0.0, contextTokensUsed: 0);
  }

  /// Saves a compressed summary of the conversation to `.quantum/local_memory.md`.
  /// This file is read at session start so the model "remembers" what it did.
  Future<void> saveSessionMemory(List<Map<String, String>> messages, String workspacePath) async {
    try {
      final memDir = Directory('$workspacePath/.quantum');
      if (!await memDir.exists()) await memDir.create(recursive: true);
      
      final memFile = File('$workspacePath/.quantum/local_memory.md');
      
      // Build a compact summary of what was done
      final sb = StringBuffer();
      sb.writeln('# Память локальной сессии (Local Session Memory)');
      sb.writeln('_Сохранено: ${DateTime.now().toLocal().toString().substring(0, 16)}_');
      sb.writeln();
      sb.writeln('## Что делали в этой сессии:');
      
      // Extract key actions from messages
      final actions = <String>[];
      for (final msg in messages) {
        final role = msg['role'] ?? '';
        final content = msg['content'] ?? '';
        if (role == 'user' && content.isNotEmpty && content.length < 500) {
          actions.add('- **Пользователь:** ${content.substring(0, content.length > 200 ? 200 : content.length)}');
        } else if (role == 'assistant' && content.isNotEmpty) {
          // Only include assistant messages that describe actions (contain file names, commands)
          if (content.contains('.dart') || content.contains('.py') || 
              content.contains('flutter') || content.contains('создал') ||
              content.contains('изменил') || content.contains('ERROR')) {
            final preview = content.substring(0, content.length > 300 ? 300 : content.length);
            actions.add('- **ИИ сделал:** $preview');
          }
        }
      }
      
      if (actions.isNotEmpty) {
        sb.writeln(actions.join('\n'));
      }
      
      sb.writeln();
      sb.writeln('## Как продолжить:');
      sb.writeln('Если пользователь напишет "продолжи" — прочитай эту память и продолжи с того места.');
      sb.writeln('Используй `list_dir` и `read_file` чтобы проверить состояние файлов проекта.');
      
      // Append to existing memory (keep last 3 sessions)
      String existing = '';
      if (await memFile.exists()) {
        existing = await memFile.readAsString();
        // Keep only last 3000 chars of existing memory to avoid bloat
        if (existing.length > 3000) {
          existing = existing.substring(existing.length - 3000);
        }
        existing = '$existing\n\n---\n\n';
      }
      
      await memFile.writeAsString('$existing${sb.toString()}');
      debugPrint('[LocalInference] Session memory saved to .quantum/local_memory.md');
    } catch (e) {
      debugPrint('[LocalInference] Failed to save session memory: $e');
    }
  }

  /// Loads the saved session memory from `.quantum/local_memory.md`.
  /// Returns null if no memory file exists.
  Future<String?> loadSessionMemory(String workspacePath) async {
    try {
      final memFile = File('$workspacePath/.quantum/local_memory.md');
      if (!await memFile.exists()) return null;
      final content = await memFile.readAsString();
      if (content.trim().isEmpty) return null;
      // Return only the last 2000 chars to avoid bloating the prompt
      return content.length > 2000 ? content.substring(content.length - 2000) : content;
    } catch (_) {
      return null;
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _dio.close();
    super.dispose();
  }
}

final localInferenceProvider = StateNotifierProvider<LocalInferenceNotifier, LocalInferenceState>((ref) {
  return LocalInferenceNotifier(ref);
});
