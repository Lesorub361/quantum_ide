import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/utils/platform_utils.dart';
import 'package:path_provider/path_provider.dart';

class LocalModelInfo {
  final String id;
  final String name;
  final String description;
  final String filename;
  final double sizeGb;
  final double ramRequiredGb;
  final String url;
  final LocalAiEngine engine;

  const LocalModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.filename,
    required this.sizeGb,
    required this.ramRequiredGb,
    required this.url,
    required this.engine,
  });
}

const List<LocalModelInfo> availableLocalModels = [
  // --- Llama Server Models ---
  LocalModelInfo(
    id: 'qwen_1.5b',
    name: 'Qwen 2.5 Coder 1.5B',
    description: 'Оптимизирована для кодинга. Сверхбыстрая (~35 ток/с), контекст 32K.',
    filename: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    sizeGb: 1.16,
    ramRequiredGb: 2.5,
    url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'deepseek_r1_1.5b',
    name: 'DeepSeek R1 Distill 1.5B',
    description: 'Глубокие пошаговые рассуждения (<think>), математика и логика.',
    filename: 'deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf',
    sizeGb: 1.12,
    ramRequiredGb: 2.5,
    url: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'qwen_3b',
    name: 'Qwen 2.5 Coder 3B',
    description: 'Идеальный баланс точности и скорости. Архитектура функций и классов.',
    filename: 'qwen2.5-3b-instruct-q4_k_m.gguf',
    sizeGb: 2.10,
    ramRequiredGb: 4.0,
    url: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'llama_1b',
    name: 'Llama 3.2 1B',
    description: 'Легкая модель от Meta. Огромный контекст 128K, скорость ~40 ток/с.',
    filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
    sizeGb: 0.81,
    ramRequiredGb: 1.8,
    url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'llama_3b',
    name: 'Llama 3.2 3B (Uncensored)',
    description: 'Без цензуры, отличный контекст 128K, универсальный помощник.',
    filename: 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
    sizeGb: 2.02,
    ramRequiredGb: 4.0,
    url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'qwen_7b',
    name: 'Qwen 2.5 Coder 7B',
    description: 'Мощнейшая автономная модель для сложных проектов. Требует 8 GB RAM.',
    filename: 'qwen2.5-coder-7b-instruct-q4_k_m.gguf',
    sizeGb: 4.68,
    ramRequiredGb: 8.0,
    url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'phi_3.5',
    name: 'Phi-3.5 Mini Instruct',
    description: 'Компактная логическая модель от Microsoft с контекстом 128K.',
    filename: 'phi-3.5-mini-instruct-q4_k_m.gguf',
    sizeGb: 2.20,
    ramRequiredGb: 4.5,
    url: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'gemma_2b',
    name: 'Gemma 2 2B Instruct',
    description: 'Компактная качественная языковая модель от Google DeepMind.',
    filename: 'gemma-2-2b-it-q4_k_m.gguf',
    sizeGb: 1.71,
    ramRequiredGb: 3.0,
    url: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'qwen2_vl_2b',
    name: 'Qwen2-VL 2B (Vision)',
    description: 'Мультимодальная модель: понимает изображения, макеты и скриншоты.',
    filename: 'qwen2-vl-2b-instruct-q4_k_m.gguf',
    sizeGb: 1.50,
    ramRequiredGb: 3.5,
    url: 'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),

  // --- Ollama Models ---
  LocalModelInfo(
    id: 'ollama_qwen_1.5b',
    name: 'Qwen 2.5 Coder 1.5B (Ollama)',
    description: 'Специализированная кодинг-модель. Мгновенный отклик на мобильных.',
    filename: 'qwen2.5-coder:1.5b',
    sizeGb: 0.98,
    ramRequiredGb: 2.5,
    url: 'qwen2.5-coder:1.5b',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_deepseek_r1_1.5b',
    name: 'DeepSeek R1 1.5B (Ollama)',
    description: 'Революционная модель с цепочкой рассуждений (<think>) и математикой.',
    filename: 'deepseek-r1:1.5b',
    sizeGb: 1.10,
    ramRequiredGb: 2.5,
    url: 'deepseek-r1:1.5b',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_qwen_3b',
    name: 'Qwen 2.5 Coder 3B (Ollama)',
    description: 'Высокая точность синтаксиса, сложные функции, документация.',
    filename: 'qwen2.5-coder:3b',
    sizeGb: 1.90,
    ramRequiredGb: 4.0,
    url: 'qwen2.5-coder:3b',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_deepseek_r1_7b',
    name: 'DeepSeek R1 7B (Ollama)',
    description: 'Глубокие рассуждения и доказательства для мощных устройств.',
    filename: 'deepseek-r1:7b',
    sizeGb: 4.70,
    ramRequiredGb: 8.0,
    url: 'deepseek-r1:7b',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_qwen_7b',
    name: 'Qwen 2.5 Coder 7B (Ollama)',
    description: 'Powerful model for a wide range of programming tasks.',
    filename: 'qwen2.5-coder:7b',
    sizeGb: 4.7,
    ramRequiredGb: 8.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_llama_1b',
    name: 'Llama 3.2 1B (Ollama)',
    description: 'Compact model from Meta, great for light tasks.',
    filename: 'llama3.2:1b',
    sizeGb: 1.3,
    ramRequiredGb: 2.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_llama_3b',
    name: 'Llama 3.2 3B (Ollama)',
    description: 'Balanced model from Meta for general tasks and dialogues.',
    filename: 'llama3.2:3b',
    sizeGb: 2.0,
    ramRequiredGb: 4.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_deepseek_1.3b',
    name: 'DeepSeek Coder 1.3B (Ollama)',
    description: 'Specialized coding model from DeepSeek.',
    filename: 'deepseek-coder:1.3b',
    sizeGb: 0.8,
    ramRequiredGb: 2.2,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_deepseek_6.7b',
    name: 'DeepSeek Coder 6.7B (Ollama)',
    description: 'Highly efficient coding model from DeepSeek.',
    filename: 'deepseek-coder:6.7b',
    sizeGb: 3.8,
    ramRequiredGb: 7.5,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_mistral_7b',
    name: 'Mistral 7B (Ollama)',
    description: 'Versatile general-purpose model with good understanding of code.',
    filename: 'mistral:7b',
    sizeGb: 4.1,
    ramRequiredGb: 8.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_gemma_2b',
    name: 'Gemma 2 2B (Ollama)',
    description: 'Efficient and accurate compact model from Google.',
    filename: 'gemma2:2b',
    sizeGb: 1.6,
    ramRequiredGb: 3.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_gemma_9b',
    name: 'Gemma 2 9B (Ollama)',
    description: 'Powerful general-purpose language model from Google.',
    filename: 'gemma2:9b',
    sizeGb: 5.5,
    ramRequiredGb: 10.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
];

class LocalAiState {
  final bool isModelDownloaded;
  final bool isBinaryInstalled;
  final bool isRunning;
  final bool isStarting;
  final String? error;
  final String logs;

  // New fields
  final String? downloadingModelId;
  final double downloadProgress;
  final Map<String, bool> downloadedModels;
  final String selectedModelFilename;
  final bool isBinaryInstalling;

  // NPU / Hardware acceleration settings
  final int threads;
  final int gpuLayers;
  final bool useFlashAttn;
  final int contextSize;

  // Memory diagnostics & safety
  final int availableRamMb;
  final int totalRamMb;
  final int swapTotalMb;
  final int swapFreeMb;
  final bool safeMode;

  LocalAiState({
    this.isModelDownloaded = false,
    this.isBinaryInstalled = false,
    this.isRunning = false,
    this.isStarting = false,
    this.error,
    this.logs = '',
    this.downloadingModelId,
    this.downloadProgress = 0.0,
    this.downloadedModels = const {},
    this.selectedModelFilename = 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    this.isBinaryInstalling = false,
    this.threads = 3,
    this.gpuLayers = 0,
    this.useFlashAttn = true,
    this.contextSize = 2048,
    this.availableRamMb = -1,
    this.totalRamMb = -1,
    this.swapTotalMb = 0,
    this.swapFreeMb = 0,
    this.safeMode = true,
  });

  LocalAiState copyWith({
    bool? isModelDownloaded,
    bool? isBinaryInstalled,
    bool? isRunning,
    bool? isStarting,
    String? error,
    String? logs,
    String? downloadingModelId,
    bool clearDownloadingModel = false,
    double? downloadProgress,
    Map<String, bool>? downloadedModels,
    String? selectedModelFilename,
    bool? isBinaryInstalling,
    int? threads,
    int? gpuLayers,
    bool? useFlashAttn,
    int? contextSize,
    int? availableRamMb,
    int? totalRamMb,
    int? swapTotalMb,
    int? swapFreeMb,
    bool? safeMode,
  }) {
    return LocalAiState(
      isModelDownloaded: isModelDownloaded ?? this.isModelDownloaded,
      isBinaryInstalled: isBinaryInstalled ?? this.isBinaryInstalled,
      isRunning: isRunning ?? this.isRunning,
      isStarting: isStarting ?? this.isStarting,
      error: error,
      logs: logs ?? this.logs,
      downloadingModelId: clearDownloadingModel ? null : (downloadingModelId ?? this.downloadingModelId),
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedModels: downloadedModels ?? this.downloadedModels,
      selectedModelFilename: selectedModelFilename ?? this.selectedModelFilename,
      isBinaryInstalling: isBinaryInstalling ?? this.isBinaryInstalling,
      threads: threads ?? this.threads,
      gpuLayers: gpuLayers ?? this.gpuLayers,
      useFlashAttn: useFlashAttn ?? this.useFlashAttn,
      contextSize: contextSize ?? this.contextSize,
      availableRamMb: availableRamMb ?? this.availableRamMb,
      totalRamMb: totalRamMb ?? this.totalRamMb,
      swapTotalMb: swapTotalMb ?? this.swapTotalMb,
      swapFreeMb: swapFreeMb ?? this.swapFreeMb,
      safeMode: safeMode ?? this.safeMode,
    );
  }
}

class LocalAiService extends StateNotifier<LocalAiState> {
  final Ref _ref;
  Process? _process;
  Timer? _healthCheckTimer;
  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
  CancelToken? _downloadCancelToken;

  LocalAiService(this._ref) : super(LocalAiState()) {
    checkStatus();
  }

  RuntimeService get _runtime => _ref.read(runtimeServiceProvider);

  String get _binaryPath {
    if (Platform.isAndroid || Platform.isIOS) {
      return p.join(
        _runtime.filesDir,
        'rootfs',
        'ubuntu',
        'usr',
        'bin',
        'llama-server',
      );
    }
    return p.join(
      _runtime.filesDir,
      'bin',
      Platform.isWindows ? 'llama-server.exe' : 'llama-server',
    );
  }

  String _getOllamaBaseUrl() {
    final aiSvc = _ref.read(aiServiceProvider);
    return aiSvc.getBaseUrl('local_edge');
  }

  Future<File?> findModelFile(String filename) async {
    final clean = filename.trim();
    if (clean.isEmpty) return null;

    final candidates = <String>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      candidates.add(p.join(docs.path, 'models', clean));
    } catch (_) {}
    if (_runtime.isInitialized) {
      candidates.add(p.join(_runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models', clean));
      candidates.add(p.join(_runtime.filesDir, 'models', clean));
    }
    candidates.add(p.join(Directory.systemTemp.path, 'quantum_models', clean));

    for (final path in candidates) {
      final f = File(path);
      if (await f.exists()) {
        try {
          if (await f.length() > 1024 * 1024) {
            return f;
          }
        } catch (_) {
          return f;
        }
      }
    }
    return null;
  }

  /// Returns available RAM in Megabytes, or -1 if unable to determine.
  static Future<int> getAvailableRamMb() async {
    try {
      final f = File('/proc/meminfo');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        for (final line in lines) {
          if (line.startsWith('MemAvailable:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]);
              if (kb != null) return kb ~/ 1024;
            }
          }
        }
      }
    } catch (_) {}
    return -1;
  }

  /// Returns total RAM in Megabytes, or -1 if unable to determine.
  static Future<int> getTotalRamMb() async {
    try {
      final f = File('/proc/meminfo');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]);
              if (kb != null) return kb ~/ 1024;
            }
          }
        }
      }
    } catch (_) {}
    return -1;
  }

  /// Returns total Swap (zRAM / Android RAM Plus) in Megabytes, or 0 if none.
  static Future<int> getSwapTotalMb() async {
    try {
      final f = File('/proc/meminfo');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        for (final line in lines) {
          if (line.startsWith('SwapTotal:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]);
              if (kb != null) return kb ~/ 1024;
            }
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Returns free Swap (zRAM / Android RAM Plus) in Megabytes, or 0 if none.
  static Future<int> getSwapFreeMb() async {
    try {
      final f = File('/proc/meminfo');
      if (await f.exists()) {
        final lines = await f.readAsLines();
        for (final line in lines) {
          if (line.startsWith('SwapFree:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]);
              if (kb != null) return kb ~/ 1024;
            }
          }
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Estimates total required RAM in Megabytes for a given model and context size.
  Future<int> estimateRequiredRamMb({String? filename, int? contextSize}) async {
    final modelFile = filename ?? state.selectedModelFilename;
    final ctx = contextSize ?? state.contextSize;

    LocalModelInfo? model;
    for (final m in availableLocalModels) {
      if (m.filename == modelFile) {
        model = m;
        break;
      }
    }

    int modelMb = 1500;
    if (model != null) {
      modelMb = (model.ramRequiredGb * 1024).round();
    } else {
      try {
        final f = await findModelFile(modelFile);
        if (f != null && await f.exists()) {
          final sizeMb = (await f.length()) ~/ (1024 * 1024);
          modelMb = (sizeMb * 1.25).round();
        }
      } catch (_) {}
    }

    final kvCacheMb = (ctx / 2048 * 300).round();
    return modelMb + kvCacheMb;
  }

  Future<void> setSafeMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_local_safe_mode', enabled);
    state = state.copyWith(safeMode: enabled);
    _appendLogs('[Local AI] 🛡️ Безопасный режим ${enabled ? "ВКЛЮЧЕН (защита от вылетов и сбоев GPU)" : "ОТКЛЮЧЕН (ограничения памяти сняты)"}.\n');
  }

  Future<void> applyMobileSafeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_local_threads', 3);
    await prefs.setInt('ai_local_gpu_layers', 0);
    await prefs.setBool('ai_local_flash_attn', true);
    await prefs.setInt('ai_local_context_size', 2048);
    await prefs.setBool('ai_local_safe_mode', true);
    state = state.copyWith(
      threads: 3,
      gpuLayers: 0,
      useFlashAttn: true,
      contextSize: 2048,
      safeMode: true,
    );
    _appendLogs('[Local AI] 🛡️ Безопасный режим применен: Потоки=3, GPU=0 (CPU), Контекст=2048, FlashAttn=ВКЛ.\n');
  }

  Future<void> checkStatus() async {
    if (!_runtime.isInitialized) return;

    final availableRam = await getAvailableRamMb();
    final totalRam = await getTotalRamMb();
    final swapTotal = await getSwapTotalMb();
    final swapFree = await getSwapFreeMb();
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final defaultThreads = isMobile ? 3 : (Platform.numberOfProcessors >= 8 ? 6 : (Platform.numberOfProcessors >= 4 ? 4 : 2));
    const defaultGpuLayers = 0; // Pure CPU on mobile to avoid Vulkan/OpenCL driver crashes
    final defaultContextSize = isMobile ? 2048 : 4096;

    final engine = _ref.read(aiServiceProvider).settings.selectedLocalEngine;

    if (engine == LocalAiEngine.llamaServer) {
      final downloadedMap = <String, bool>{};
      bool anyModelDownloaded = false;
      
      final engineModels = availableLocalModels.where((m) => m.engine == LocalAiEngine.llamaServer);
      for (final m in engineModels) {
        final found = await findModelFile(m.filename);
        final exists = found != null;
        downloadedMap[m.id] = exists;
        if (exists) {
          anyModelDownloaded = true;
        }
      }

      bool binaryExists = await File(_binaryPath).exists();
      if (!binaryExists && !Platform.isAndroid && !Platform.isIOS) {
        try {
          final res = await Process.run(PlatformUtils.whichCommand, ['llama-server'], runInShell: Platform.isWindows);
          if (res.exitCode == 0) {
            binaryExists = true;
          }
        } catch (_) {}
      }

      final prefs = await SharedPreferences.getInstance();
      String activeFilename = prefs.getString('ai_selected_local_model_filename') ?? 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf';

      final isValidActive = engineModels.any((m) => m.filename == activeFilename);
      if (!isValidActive) {
        activeFilename = 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf';
        await prefs.setString('ai_selected_local_model_filename', activeFilename);
      }

      bool running = false;
      if (binaryExists && anyModelDownloaded) {
        running = await _pingServer();
      }

      final threads = prefs.getInt('ai_local_threads') ?? defaultThreads;
      final gpuLayers = prefs.getInt('ai_local_gpu_layers') ?? defaultGpuLayers;
      final useFlashAttn = prefs.getBool('ai_local_flash_attn') ?? isMobile;
      final contextSize = prefs.getInt('ai_local_context_size') ?? defaultContextSize;
      final safeMode = prefs.getBool('ai_local_safe_mode') ?? true;

      state = state.copyWith(
        isModelDownloaded: anyModelDownloaded,
        isBinaryInstalled: binaryExists,
        isRunning: running,
        downloadedModels: downloadedMap,
        selectedModelFilename: activeFilename,
        threads: threads,
        gpuLayers: gpuLayers,
        useFlashAttn: useFlashAttn,
        contextSize: contextSize,
        availableRamMb: availableRam,
        totalRamMb: totalRam,
        swapTotalMb: swapTotal,
        swapFreeMb: swapFree,
        safeMode: safeMode,
      );
    } else if (engine == LocalAiEngine.ollama) {
      final baseUrl = _getOllamaBaseUrl();
      bool reachable = false;
      final downloadedMap = <String, bool>{};
      bool anyModelDownloaded = false;

      try {
        final resp = await _dio.get('$baseUrl/api/tags');
        if (resp.statusCode == 200) {
          reachable = true;
          final modelsList = resp.data['models'] as List?;
          final existingNames = <String>{};
          if (modelsList != null) {
            for (final m in modelsList) {
              if (m is Map && m['name'] != null) {
                existingNames.add(m['name'].toString());
              }
            }
          }

          final engineModels = availableLocalModels.where((m) => m.engine == LocalAiEngine.ollama);
          for (final m in engineModels) {
            final exists = existingNames.contains(m.filename) ||
                           existingNames.contains('${m.filename}:latest');
            downloadedMap[m.id] = exists;
            if (exists) {
              anyModelDownloaded = true;
            }
          }
        }
      } catch (_) {
        reachable = false;
      }

      final prefs = await SharedPreferences.getInstance();
      String activeFilename = prefs.getString('ai_selected_local_model_filename') ?? 'qwen2.5-coder:1.5b';

      final engineModels = availableLocalModels.where((m) => m.engine == LocalAiEngine.ollama);
      final isValidActive = engineModels.any((m) => m.filename == activeFilename);
      if (!isValidActive) {
        activeFilename = 'qwen2.5-coder:1.5b';
        await prefs.setString('ai_selected_local_model_filename', activeFilename);
      }

      final threads = prefs.getInt('ai_local_threads') ?? defaultThreads;
      final gpuLayers = prefs.getInt('ai_local_gpu_layers') ?? defaultGpuLayers;
      final useFlashAttn = prefs.getBool('ai_local_flash_attn') ?? isMobile;
      final contextSize = prefs.getInt('ai_local_context_size') ?? defaultContextSize;
      final safeMode = prefs.getBool('ai_local_safe_mode') ?? true;

      state = state.copyWith(
        isModelDownloaded: anyModelDownloaded,
        isBinaryInstalled: reachable,
        isRunning: reachable,
        downloadedModels: downloadedMap,
        selectedModelFilename: activeFilename,
        threads: threads,
        gpuLayers: gpuLayers,
        useFlashAttn: useFlashAttn,
        contextSize: contextSize,
        availableRamMb: availableRam,
        totalRamMb: totalRam,
        swapTotalMb: swapTotal,
        swapFreeMb: swapFree,
        safeMode: safeMode,
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      final threads = prefs.getInt('ai_local_threads') ?? defaultThreads;
      final gpuLayers = prefs.getInt('ai_local_gpu_layers') ?? defaultGpuLayers;
      final useFlashAttn = prefs.getBool('ai_local_flash_attn') ?? isMobile;
      final contextSize = prefs.getInt('ai_local_context_size') ?? defaultContextSize;
      final safeMode = prefs.getBool('ai_local_safe_mode') ?? true;

      state = state.copyWith(
        isModelDownloaded: false,
        isBinaryInstalled: false,
        isRunning: false,
        downloadedModels: {},
        selectedModelFilename: '',
        threads: threads,
        gpuLayers: gpuLayers,
        useFlashAttn: useFlashAttn,
        contextSize: contextSize,
        availableRamMb: availableRam,
        totalRamMb: totalRam,
        swapTotalMb: swapTotal,
        swapFreeMb: swapFree,
        safeMode: safeMode,
      );
    }
  }

  Future<bool> _pingServer() async {
    try {
      final resp = await _dio.get('http://127.0.0.1:8080/health');
      if (resp.statusCode == 200) {
        final data = resp.data;
        if (data is Map && (data['status'] == 'ok' || data.toString().contains('ok'))) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _appendLogs(String text) {
    final lines = (state.logs + text).split('\n');
    if (lines.length > 200) {
      state = state.copyWith(logs: lines.sublist(lines.length - 200).join('\n'));
    } else {
      state = state.copyWith(logs: lines.join('\n'));
    }
  }

  Future<void> downloadModel(String modelId) async {
    if (state.downloadingModelId != null) return;
    
    LocalModelInfo model;
    try {
      model = availableLocalModels.firstWhere((m) => m.id == modelId);
    } catch (_) {
      final tag = modelId.startsWith('ollama_') ? modelId.substring(7) : modelId;
      model = LocalModelInfo(
        id: modelId,
        name: tag,
        description: 'Ollama model $tag',
        filename: tag,
        sizeGb: 2.0,
        ramRequiredGb: 4.0,
        url: tag,
        engine: LocalAiEngine.ollama,
      );
    }
    
    if (model.engine == LocalAiEngine.ollama) {
      await _downloadOllamaModel(model);
      return;
    }

    final modelsDir = p.join(_runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models');
    await Directory(modelsDir).create(recursive: true);

    final savePath = p.join(modelsDir, model.filename);
    final tempPath = '$savePath.tmp';

    state = state.copyWith(
      downloadingModelId: modelId,
      downloadProgress: 0.0,
      error: null,
    );

    _downloadCancelToken = CancelToken();

    try {
      _appendLogs('[Local AI] Start downloading model ${model.name}...\n');
      await _dio.download(
        model.url,
        tempPath,
        cancelToken: _downloadCancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(
              downloadProgress: received / total,
            );
          }
        },
      );

      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.rename(savePath);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_selected_local_model_filename', model.filename);
      await _ref.read(aiServiceProvider).setModel(model.filename);

      _appendLogs('[Local AI] Model ${model.name} downloaded successfully.\n');
      await checkStatus();
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _appendLogs('[Local AI] Model download cancelled by user.\n');
      } else {
        _appendLogs('[Local AI] Download error: $e\n');
        state = state.copyWith(error: 'Download error: $e');
      }
      try {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    } finally {
      _downloadCancelToken = null;
      state = state.copyWith(
        clearDownloadingModel: true,
        downloadProgress: 0.0,
      );
    }
  }

  Future<void> _downloadOllamaModel(LocalModelInfo model) async {
    final baseUrl = _getOllamaBaseUrl();
    state = state.copyWith(
      downloadingModelId: model.id,
      downloadProgress: 0.0,
      error: null,
    );

    _downloadCancelToken = CancelToken();

    try {
      _appendLogs('[Ollama] Starting model download for ${model.filename}...\n');
      
      final response = await _dio.post(
        '$baseUrl/api/pull',
        data: {'name': model.filename, 'stream': true},
        cancelToken: _downloadCancelToken,
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data.stream as Stream<List<int>>;
      
      final StringBuffer buffer = StringBuffer();
      await for (final chunk in stream) {
        final text = utf8.decode(chunk);
        buffer.write(text);
        
        final lines = buffer.toString().split('\n');
        buffer.clear();
        if (lines.isNotEmpty && !text.endsWith('\n')) {
          buffer.write(lines.removeLast());
        }

        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final data = jsonDecode(line);
            if (data is Map) {
              final status = data['status'];
              final completed = data['completed'];
              final total = data['total'];
              
              if (status != null) {
                if (status == 'pulling manifest') {
                  _appendLogs('[Ollama] Pulling manifest...\n');
                } else if (status.toString().startsWith('verifying')) {
                  _appendLogs('[Ollama] Verifying checksum...\n');
                }
              }
              
              if (completed is num && total is num && total > 0) {
                state = state.copyWith(
                  downloadProgress: completed / total,
                );
              }
            }
          } catch (_) {}
        }
      }

      _appendLogs('[Ollama] Model ${model.name} downloaded successfully.\n');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_selected_local_model_filename', model.filename);
      await _ref.read(aiServiceProvider).setModel(model.filename);
      
      await checkStatus();
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _appendLogs('[Ollama] Download cancelled by user.\n');
      } else {
        _appendLogs('[Ollama] Model download error: $e\n');
        state = state.copyWith(error: 'Download error: $e');
      }
    } finally {
      _downloadCancelToken = null;
      state = state.copyWith(
        clearDownloadingModel: true,
        downloadProgress: 0.0,
      );
    }
  }

  void cancelDownload() {
    _downloadCancelToken?.cancel();
  }

  Future<void> deleteModel(String modelId) async {
    LocalModelInfo model;
    try {
      model = availableLocalModels.firstWhere((m) => m.id == modelId);
    } catch (_) {
      final tag = modelId.startsWith('ollama_') ? modelId.substring(7) : modelId;
      model = LocalModelInfo(
        id: modelId,
        name: tag,
        description: 'Ollama model $tag',
        filename: tag,
        sizeGb: 2.0,
        ramRequiredGb: 4.0,
        url: tag,
        engine: LocalAiEngine.ollama,
      );
    }
    
    if (model.engine == LocalAiEngine.ollama) {
      await _deleteOllamaModel(model);
      return;
    }

    final modelsDir = p.join(_runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models');
    final filePath = p.join(modelsDir, model.filename);

    try {
      final f = File(filePath);
      if (await f.exists()) {
        await f.delete();
      }

      await checkStatus();

      if (state.selectedModelFilename == model.filename) {
        String fallback = 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf';
        for (final m in availableLocalModels) {
          if (m.engine == LocalAiEngine.llamaServer && state.downloadedModels[m.id] == true) {
            fallback = m.filename;
            break;
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ai_selected_local_model_filename', fallback);
        await _ref.read(aiServiceProvider).setModel(fallback);
        state = state.copyWith(selectedModelFilename: fallback);
      }

      _appendLogs('[Local AI] Model ${model.name} deleted successfully.\n');
    } catch (e) {
      state = state.copyWith(error: 'Delete error: $e');
      _appendLogs('[Local AI] Model deletion error: $e\n');
    }
  }

  Future<void> _deleteOllamaModel(LocalModelInfo model) async {
    final baseUrl = _getOllamaBaseUrl();
    try {
      _appendLogs('[Ollama] Deleting model ${model.filename}...\n');
      await _dio.delete(
        '$baseUrl/api/delete',
        data: jsonEncode({'name': model.filename}),
      );
      
      _appendLogs('[Ollama] Model ${model.name} deleted successfully.\n');
      await checkStatus();

      if (state.selectedModelFilename == model.filename) {
        String fallback = 'qwen2.5-coder:1.5b';
        for (final m in availableLocalModels) {
          if (m.engine == LocalAiEngine.ollama && state.downloadedModels[m.id] == true) {
            fallback = m.filename;
            break;
          }
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ai_selected_local_model_filename', fallback);
        await _ref.read(aiServiceProvider).setModel(fallback);
        state = state.copyWith(selectedModelFilename: fallback);
      }
    } catch (e) {
      state = state.copyWith(error: 'Delete error: $e');
      _appendLogs('[Ollama] Model deletion error: $e\n');
    }
  }

  Future<void> selectModel(String modelIdOrFilename) async {
    LocalModelInfo? model;
    for (final m in availableLocalModels) {
      if (m.id == modelIdOrFilename || m.filename == modelIdOrFilename) {
        model = m;
        break;
      }
    }
    final filename = model?.filename ?? modelIdOrFilename;
    final name = model?.name ?? modelIdOrFilename;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_selected_local_model_filename', filename);
    await _ref.read(aiServiceProvider).setModel(filename);
    state = state.copyWith(selectedModelFilename: filename);
    _appendLogs('[Local AI] Selected active model: $name\n');
  }

  Future<void> updateSettings({int? threads, int? gpuLayers, bool? useFlashAttn, int? contextSize, bool? safeMode}) async {
    final prefs = await SharedPreferences.getInstance();
    if (threads != null) {
      await prefs.setInt('ai_local_threads', threads);
    }
    if (gpuLayers != null) {
      await prefs.setInt('ai_local_gpu_layers', gpuLayers);
    }
    if (useFlashAttn != null) {
      await prefs.setBool('ai_local_flash_attn', useFlashAttn);
    }
    if (contextSize != null) {
      await prefs.setInt('ai_local_context_size', contextSize);
    }
    if (safeMode != null) {
      await prefs.setBool('ai_local_safe_mode', safeMode);
    }
    state = state.copyWith(
      threads: threads ?? state.threads,
      gpuLayers: gpuLayers ?? state.gpuLayers,
      useFlashAttn: useFlashAttn ?? state.useFlashAttn,
      contextSize: contextSize ?? state.contextSize,
      safeMode: safeMode ?? state.safeMode,
    );
    _appendLogs('[Local AI] Settings updated: threads=${threads ?? state.threads}, gpuLayers=${gpuLayers ?? state.gpuLayers}, useFlashAttn=${useFlashAttn ?? state.useFlashAttn}, contextSize=${contextSize ?? state.contextSize}, safeMode=${safeMode ?? state.safeMode}\n');
  }

  Future<void> installBinary() async {
    if (state.isBinaryInstalling) return;

    state = state.copyWith(isBinaryInstalling: true, error: null);
    _appendLogs('[Local AI] Starting installation of llama-server...\n');

    // Use || true after apt to ignore its non-zero exit codes (CLI warnings)
    // wget with --tries=3 for robustness; no -q so we capture output in logs
    const llamaRelease = 'b4200';
    const llamaArch = 'ubuntu-arm64';
    const llamaTarUrl =
        'https://github.com/ggml-org/llama.cpp/releases/download/$llamaRelease/llama-$llamaRelease-bin-$llamaArch.tar.gz';

    final installCmd = [
      'apt-get update -qq || true',
      'apt-get install -y -qq curl wget tar || true',
      'rm -rf /tmp/llama_dl && mkdir -p /tmp/llama_dl',
      'cd /tmp/llama_dl',
      'wget --tries=3 --timeout=60 -O llama.tar.gz "$llamaTarUrl" 2>&1',
      'tar -xzf llama.tar.gz',
      'ls -la', // log what we extracted
      '[ -f build/bin/llama-server ] && cp build/bin/llama-server /usr/bin/llama-server || cp bin/llama-server /usr/bin/llama-server',
      '[ -f build/bin/llama-cli ] && cp build/bin/llama-cli /usr/bin/llama-cli || cp bin/llama-cli /usr/bin/llama-cli 2>/dev/null || true',
      'chmod +x /usr/bin/llama-server',
      'rm -rf /tmp/llama_dl',
      'echo "llama-server installed: \$(llama-server --version 2>&1 | head -1)"',
    ].join(' && ');

    try {
      final output = await _runtime.runCommand(installCmd);
      _appendLogs('[Local AI] Installation output:\n$output\n');

      await checkStatus();
      if (state.isBinaryInstalled) {
        _appendLogs('[Local AI] llama-server installed successfully!\n');
      } else {
        throw Exception('Binary file not found after installation. Check the output above.');
      }
    } catch (e) {
      state = state.copyWith(error: 'Error installing llama-server: $e');
      _appendLogs('[Local AI] Error installing llama-server: $e\n');
    } finally {
      state = state.copyWith(isBinaryInstalling: false);
    }
  }

  Future<void> startServer() async {
    if (state.isRunning || state.isStarting) return;

    state = state.copyWith(isStarting: true, error: null);
    _appendLogs('\n[Local AI] Starting llama-server...\n');

    try {
      await checkStatus();
      if (!state.isBinaryInstalled || !state.isModelDownloaded) {
        throw Exception('llama-server binary or AI model is not installed. Please install them first.');
      }

      try {
        await _runtime.runCommand('pkill -f llama-server');
      } catch (_) {}

      final proot = _runtime.prootCommand;
      final filesDir = _runtime.filesDir;
      final activeModelFile = state.selectedModelFilename;
      final isMobile = Platform.isAndroid || Platform.isIOS;

      // ── Pre-flight RAM & Safety Checks ──────────────────────────────────
      final availableRam = await getAvailableRamMb();
      final totalRam = await getTotalRamMb();
      final swapTotal = await getSwapTotalMb();
      final swapFree = await getSwapFreeMb();
      final requiredRam = await estimateRequiredRamMb(filename: activeModelFile, contextSize: state.contextSize);

      final effectiveAvailableMem = availableRam + (swapFree > 0 ? swapFree : 0);
      _appendLogs('[Local AI] Диагностика RAM: свободно ${availableRam > 0 ? "$availableRam МБ" : "неизвестно"} / ${totalRam > 0 ? "$totalRam МБ" : "неизвестно"}${swapTotal > 0 ? " · Подкачка (RAM Plus/Swap): +${(swapTotal / 1024).toStringAsFixed(1)} ГБ (свободно ${(swapFree / 1024).toStringAsFixed(1)} ГБ, всего с подкачкой: ${((totalRam + swapTotal) / 1024).toStringAsFixed(1)} ГБ)" : ""}. Требуется для модели: ~$requiredRam МБ.\n');

      if (availableRam > 0 && effectiveAvailableMem < (requiredRam * 0.70)) {
        if (state.safeMode) {
          final warningMsg = 'Недостаточно свободной оперативной памяти (RAM)!\n'
              'Доступно: ${(availableRam / 1024).toStringAsFixed(1)} ГБ'
              '${swapTotal > 0 ? " (с подкачкой: ${(effectiveAvailableMem / 1024).toStringAsFixed(1)} ГБ)" : ""}'
              ', а для модели "$activeModelFile" требуется минимум ${(requiredRam / 1024).toStringAsFixed(1)} ГБ.\n'
              '⛔ Запуск заблокирован для защиты от вылета приложения (Android OOM Killer).\n'
              '💡 Рекомендация: выберите компактную модель (0.5B или 1.5B) либо отключите «Безопасный режим» в настройках, если хотите запустить принудительно.';
          _appendLogs('\n[Local AI] ❌ $warningMsg\n');
          state = state.copyWith(isStarting: false, isRunning: false, error: warningMsg);
          return;
        } else {
          _appendLogs('\n[Local AI] ⚠️ Внимание: Безопасный режим ОТКЛЮЧЕН пользователем! Доступно ${(effectiveAvailableMem / 1024).toStringAsFixed(1)} ГБ при требуемых ${(requiredRam / 1024).toStringAsFixed(1)} ГБ. Запуск продолжается принудительно на ваш страх и риск...\n');
        }
      }

      // Auto-tune context if borderline RAM to avoid crash (only if safeMode enabled)
      int effectiveContextSize = state.contextSize;
      if (state.safeMode && availableRam > 0 && availableRam < requiredRam && effectiveContextSize > 2048) {
        effectiveContextSize = 2048;
        _appendLogs('[Local AI] ⚡ Авто-оптимизация: Контекст уменьшен до 2048 для экономии оперативной памяти.\n');
      }

      // GPU layers: in safeMode disable GPU on mobile to prevent driver crash; otherwise respect user choice
      int effectiveGpuLayers = state.gpuLayers;
      if (state.safeMode && isMobile && effectiveGpuLayers > 0) {
        _appendLogs('[Local AI] ℹ️ Отключение GPU-слоев на мобильном (Безопасный режим) для предотвращения сбоя Vulkan драйвера.\n');
        effectiveGpuLayers = 0;
      }

      // Safe thread limit on mobile (only if safeMode enabled)
      final effectiveThreads = (state.safeMode && isMobile) ? (state.threads > 4 ? 3 : state.threads) : state.threads;
      final useFlashAttn = state.useFlashAttn;

      final found = await findModelFile(activeModelFile);
      if (found != null && isMobile) {
        final rootfsTarget = File(p.join(_runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models', activeModelFile));
        if (!await rootfsTarget.exists() || (await rootfsTarget.length()) == 0) {
          await Directory(rootfsTarget.parent.path).create(recursive: true);
          try {
            await Link(rootfsTarget.path).create(found.path);
          } catch (_) {
            try {
              await found.copy(rootfsTarget.path);
            } catch (_) {}
          }
        }
      }

      final modelsDir = isMobile
          ? p.join(_runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models')
          : p.join(_runtime.filesDir, 'models');
      final modelFilePath = isMobile
          ? '/root/models/$activeModelFile'
          : p.join(modelsDir, activeModelFile);

      final serverArgs = [
        'llama-server',
        '-m',
        modelFilePath,
        '-c',
        '$effectiveContextSize',
        '--port',
        '8080',
        '--host',
        '127.0.0.1',
        '-t',
        '$effectiveThreads',
      ];
      if (effectiveGpuLayers > 0) {
        serverArgs.addAll(['-ngl', '$effectiveGpuLayers']);
      }
      if (useFlashAttn) {
        serverArgs.add('-fa');
      }

      final logArgs = serverArgs.join(' ');
      _appendLogs('[Local AI] Command: $logArgs\n');

      final Process process;
      if (isMobile) {
        process = await Process.start(
          'sh',
          [
            proot,
            filesDir,
            '/root',
            ...serverArgs,
          ],
        );
      } else {
        final binToRun = (await File(_binaryPath).exists()) ? _binaryPath : 'llama-server';
        process = await Process.start(
          binToRun,
          serverArgs.sublist(1),
          runInShell: Platform.isWindows,
        );
      }

      _process = process;

      // Safe UTF-8 decoding to prevent isolate crashes on invalid binary output
      const decoder = Utf8Decoder(allowMalformed: true);
      process.stdout.transform(decoder).listen((data) {
        _appendLogs(data);
      });

      process.stderr.transform(decoder).listen((data) {
        _appendLogs(data);
      });

      // Watch exit code to gracefully catch OOM (SIGKILL 9) and Segfaults (SIGSEGV 11)
      process.exitCode.then((code) {
        if (code != 0 && (state.isRunning || state.isStarting)) {
          if (code == 137 || code == -9) {
            _appendLogs('\n[Local AI] ❌ Сервер принудительно остановлен системой (сигнал 9 / SIGKILL - Android OOM Killer: не хватило оперативной памяти).\n');
            state = state.copyWith(isRunning: false, isStarting: false, error: 'OOM: Не хватило оперативной памяти');
          } else if (code == 139 || code == -11) {
            _appendLogs('\n[Local AI] ❌ Сбой сегментации (SIGSEGV / Segfault). Установите GPU Layers = 0 в настройках.\n');
            state = state.copyWith(isRunning: false, isStarting: false, error: 'Сбой драйвера (Segfault)');
          } else {
            _appendLogs('\n[Local AI] Процесс сервера завершился с кодом $code.\n');
            state = state.copyWith(isRunning: false, isStarting: false, error: 'Сервер остановлен (код $code)');
          }
        }
      });

      int retries = 20;
      bool isHealthy = false;
      int attempt = 0;
      while (retries > 0) {
        attempt++;
        await Future.delayed(const Duration(seconds: 2));
        isHealthy = await _pingServer();
        if (isHealthy) break;
        _appendLogs('[Local AI] Загрузка модели в память RAM... (попытка $attempt/20)\n');
        retries--;
      }

      if (isHealthy) {
        state = state.copyWith(isStarting: false, isRunning: true);
        _appendLogs('[Local AI] Server started successfully and is healthy!\n');
        _startHealthCheckTimer();
      } else {
        throw Exception('Server failed to respond to health checks on port 8080.');
      }
    } catch (e) {
      _process?.kill();
      _process = null;
      state = state.copyWith(isStarting: false, isRunning: false, error: e.toString());
      _appendLogs('[Local AI] Error starting server: $e\n');
    }
  }

  void _startHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final healthy = await _pingServer();
      if (!healthy && state.isRunning) {
        _appendLogs('[Local AI] Health check failed. Server stopped or unreachable.\n');
        stopServer();
      }
    });
  }

  Future<void> stopServer() async {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    _appendLogs('\n[Local AI] Stopping llama-server...\n');

    _process?.kill();
    _process = null;

    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/IM', 'llama-server.exe', '/T']);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await _runtime.runCommand('pkill -f llama-server');
      } else {
        await Process.run('pkill', ['-f', 'llama-server']);
      }
    } catch (_) {}

    state = state.copyWith(isRunning: false, isStarting: false);
    _appendLogs('[Local AI] Server stopped.\n');
  }

  void clearLogs() {
    state = state.copyWith(logs: '');
  }

  Future<void> restartServer() async {
    await stopServer();
    await Future.delayed(const Duration(milliseconds: 800));
    await startServer();
  }

  Future<void> selectAndStartModel(String modelIdOrFilename) async {
    await selectModel(modelIdOrFilename);
    await restartServer();
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _process?.kill();
    super.dispose();
  }
}

final localAiServiceProvider = StateNotifierProvider<LocalAiService, LocalAiState>((ref) {
  final notifier = LocalAiService(ref);
  // React to engine changes (llamaServer <-> Ollama <-> lmStudio)
  ref.listen<LocalAiEngine>(
    aiServiceProvider.select((s) => s.settings.selectedLocalEngine),
    (previous, next) {
      if (previous != null && previous != next) {
        notifier.checkStatus();
      }
    },
  );
  return notifier;
});
