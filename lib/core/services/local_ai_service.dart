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
    description: 'Оптимизированная модель для кодинга. Очень быстрая, подходит для любых устройств.',
    filename: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    sizeGb: 1.16,
    ramRequiredGb: 2.5,
    url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'qwen_7b',
    name: 'Qwen 2.5 Coder 7B',
    description: 'Мощная модель для сложных задач кодирования. Требует производительное устройство.',
    filename: 'qwen2.5-coder-7b-instruct-q4_k_m.gguf',
    sizeGb: 4.68,
    ramRequiredGb: 8.0,
    url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'llama_1b',
    name: 'Llama 3.2 1B',
    description: 'Легковесная языковая модель от Meta. Высокая скорость работы.',
    filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
    sizeGb: 0.81,
    ramRequiredGb: 1.8,
    url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),
  LocalModelInfo(
    id: 'llama_3b',
    name: 'Llama 3.2 3B',
    description: 'Сбалансированная модель от Meta. Хорошее понимание контекста.',
    filename: 'llama-3.2-3b-instruct-q4_k_m.gguf',
    sizeGb: 2.02,
    ramRequiredGb: 4.0,
    url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    engine: LocalAiEngine.llamaServer,
  ),

  // --- Ollama Models ---
  LocalModelInfo(
    id: 'ollama_qwen_1.5b',
    name: 'Qwen 2.5 Coder 1.5B (Ollama)',
    description: 'Легковесная и быстрая модель для кодинга от Alibaba.',
    filename: 'qwen2.5-coder:1.5b',
    sizeGb: 0.9,
    ramRequiredGb: 2.5,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_qwen_7b',
    name: 'Qwen 2.5 Coder 7B (Ollama)',
    description: 'Мощная модель для широкого спектра задач программирования.',
    filename: 'qwen2.5-coder:7b',
    sizeGb: 4.7,
    ramRequiredGb: 8.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_llama_1b',
    name: 'Llama 3.2 1B (Ollama)',
    description: 'Компактная модель от Meta, отлично подходит для легких задач.',
    filename: 'llama3.2:1b',
    sizeGb: 1.3,
    ramRequiredGb: 2.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_llama_3b',
    name: 'Llama 3.2 3B (Ollama)',
    description: 'Сбалансированная модель от Meta для общих задач и диалогов.',
    filename: 'llama3.2:3b',
    sizeGb: 2.0,
    ramRequiredGb: 4.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_deepseek_1.3b',
    name: 'DeepSeek Coder 1.3B (Ollama)',
    description: 'Специализированная кодинг-модель от DeepSeek.',
    filename: 'deepseek-coder:1.3b',
    sizeGb: 0.8,
    ramRequiredGb: 2.2,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_deepseek_6.7b',
    name: 'DeepSeek Coder 6.7B (Ollama)',
    description: 'Высокоэффективная кодинг-модель от DeepSeek.',
    filename: 'deepseek-coder:6.7b',
    sizeGb: 3.8,
    ramRequiredGb: 7.5,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_mistral_7b',
    name: 'Mistral 7B (Ollama)',
    description: 'Универсальная модель общего назначения с хорошим пониманием кода.',
    filename: 'mistral:7b',
    sizeGb: 4.1,
    ramRequiredGb: 8.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_gemma_2b',
    name: 'Gemma 2 2B (Ollama)',
    description: 'Эффективная и точная компактная модель от Google.',
    filename: 'gemma2:2b',
    sizeGb: 1.6,
    ramRequiredGb: 3.0,
    url: '',
    engine: LocalAiEngine.ollama,
  ),
  LocalModelInfo(
    id: 'ollama_gemma_9b',
    name: 'Gemma 2 9B (Ollama)',
    description: 'Мощная языковая модель общего назначения от Google.',
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

  String get _binaryPath => p.join(
        _runtime.filesDir,
        'rootfs',
        'ubuntu',
        'usr',
        'bin',
        'llama-server',
      );

  String _getOllamaBaseUrl() {
    final aiSvc = _ref.read(aiServiceProvider);
    return aiSvc.getBaseUrl('local_edge');
  }

  Future<void> checkStatus() async {
    if (!_runtime.isInitialized) return;

    final engine = _ref.read(aiServiceProvider).settings.selectedLocalEngine;

    if (engine == LocalAiEngine.llamaServer) {
      final modelsDir = p.join(_runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'models');
      
      final downloadedMap = <String, bool>{};
      bool anyModelDownloaded = false;
      
      final engineModels = availableLocalModels.where((m) => m.engine == LocalAiEngine.llamaServer);
      for (final m in engineModels) {
        final exists = await File(p.join(modelsDir, m.filename)).exists();
        downloadedMap[m.id] = exists;
        if (exists) {
          anyModelDownloaded = true;
        }
      }

      final binaryExists = await File(_binaryPath).exists();

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

      state = state.copyWith(
        isModelDownloaded: anyModelDownloaded,
        isBinaryInstalled: binaryExists,
        isRunning: running,
        downloadedModels: downloadedMap,
        selectedModelFilename: activeFilename,
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

      state = state.copyWith(
        isModelDownloaded: anyModelDownloaded,
        isBinaryInstalled: reachable,
        isRunning: reachable,
        downloadedModels: downloadedMap,
        selectedModelFilename: activeFilename,
      );
    } else {
      state = state.copyWith(
        isModelDownloaded: false,
        isBinaryInstalled: false,
        isRunning: false,
        downloadedModels: {},
        selectedModelFilename: '',
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
    
    final model = availableLocalModels.firstWhere((m) => m.id == modelId);
    
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
      _appendLogs('[Local AI] Начало скачивания модели ${model.name}...\n');
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

      _appendLogs('[Local AI] Модель ${model.name} успешно загружена.\n');
      await checkStatus();
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _appendLogs('[Local AI] Скачивание модели отменено пользователем.\n');
      } else {
        _appendLogs('[Local AI] Ошибка скачивания: $e\n');
        state = state.copyWith(error: 'Ошибка скачивания: $e');
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
      _appendLogs('[Ollama] Запуск скачивания модели ${model.filename}...\n');
      
      final response = await _dio.post(
        '$baseUrl/api/pull',
        data: {'name': model.filename, 'stream': true},
        cancelToken: _downloadCancelToken,
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data.stream as Stream<List<int>>;
      
      StringBuffer buffer = StringBuffer();
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
                  _appendLogs('[Ollama] Скачивание манифеста...\n');
                } else if (status.toString().startsWith('verifying')) {
                  _appendLogs('[Ollama] Верификация контрольной суммы...\n');
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

      _appendLogs('[Ollama] Модель ${model.name} успешно загружена.\n');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_selected_local_model_filename', model.filename);
      await _ref.read(aiServiceProvider).setModel(model.filename);
      
      await checkStatus();
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        _appendLogs('[Ollama] Скачивание отменено пользователем.\n');
      } else {
        _appendLogs('[Ollama] Ошибка скачивания модели: $e\n');
        state = state.copyWith(error: 'Ошибка скачивания: $e');
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
    final model = availableLocalModels.firstWhere((m) => m.id == modelId);
    
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

      _appendLogs('[Local AI] Модель ${model.name} успешно удалена.\n');
    } catch (e) {
      state = state.copyWith(error: 'Ошибка удаления: $e');
      _appendLogs('[Local AI] Ошибка удаления модели: $e\n');
    }
  }

  Future<void> _deleteOllamaModel(LocalModelInfo model) async {
    final baseUrl = _getOllamaBaseUrl();
    try {
      _appendLogs('[Ollama] Удаление модели ${model.filename}...\n');
      await _dio.delete(
        '$baseUrl/api/delete',
        data: jsonEncode({'name': model.filename}),
      );
      
      _appendLogs('[Ollama] Модель ${model.name} успешно удалена.\n');
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
      state = state.copyWith(error: 'Ошибка удаления: $e');
      _appendLogs('[Ollama] Ошибка удаления модели: $e\n');
    }
  }

  Future<void> selectModel(String modelId) async {
    final model = availableLocalModels.firstWhere((m) => m.id == modelId);
    if (state.downloadedModels[modelId] != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_selected_local_model_filename', model.filename);
    await _ref.read(aiServiceProvider).setModel(model.filename);
    state = state.copyWith(selectedModelFilename: model.filename);
    _appendLogs('[Local AI] Выбрана активная модель: ${model.name}\n');
  }

  Future<void> installBinary() async {
    if (state.isBinaryInstalling) return;

    state = state.copyWith(isBinaryInstalling: true, error: null);
    _appendLogs('[Local AI] Начало установки llama-server...\n');

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
      _appendLogs('[Local AI] Вывод установки:\n$output\n');

      await checkStatus();
      if (state.isBinaryInstalled) {
        _appendLogs('[Local AI] llama-server успешно установлен!\n');
      } else {
        throw Exception('Бинарный файл не найден после установки. Проверьте вывод выше.');
      }
    } catch (e) {
      state = state.copyWith(error: 'Ошибка установки llama-server: $e');
      _appendLogs('[Local AI] Ошибка установки llama-server: $e\n');
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

      _appendLogs('[Local AI] Command: llama-server -m /root/models/$activeModelFile -c 2048 --port 8080 --host 127.0.0.1\n');

      final process = await Process.start(
        'sh',
        [
          proot,
          filesDir,
          '/root',
          'llama-server',
          '-m',
          '/root/models/$activeModelFile',
          '-c',
          '2048',
          '--port',
          '8080',
          '--host',
          '127.0.0.1',
        ],
      );

      _process = process;

      process.stdout.transform(utf8.decoder).listen((data) {
        _appendLogs(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        _appendLogs(data);
      });

      int retries = 5;
      bool isHealthy = false;
      while (retries > 0) {
        await Future.delayed(const Duration(seconds: 2));
        isHealthy = await _pingServer();
        if (isHealthy) break;
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
      await _runtime.runCommand('pkill -f llama-server');
    } catch (_) {}

    state = state.copyWith(isRunning: false, isStarting: false);
    _appendLogs('[Local AI] Server stopped.\n');
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
