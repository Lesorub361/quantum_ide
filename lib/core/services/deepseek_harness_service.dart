import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/settings_service.dart';

class DeepSeekHarnessService extends ChangeNotifier {
  Process? _process;
  String? _currentProjectPath;
  int _currentPort = 3080;
  bool _isStarting = false;
  bool _isUpdating = false;
  String _statusMessage = 'Остановлен';
  final List<String> _logs = [];

  bool get isRunning => _process != null;
  bool get isStarting => _isStarting;
  bool get isUpdating => _isUpdating;
  String? get currentProjectPath => _currentProjectPath;
  int get port => _currentPort;
  String get serverUrl => 'http://127.0.0.1:$_currentPort';
  String get statusMessage => _statusMessage;
  List<String> get logs => List.unmodifiable(_logs);

  void _addLog(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    _logs.add(trimmed);
    if (_logs.length > 200) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Проверяет, установлен ли Node.js в системе
  Future<bool> isNodeAvailable() async {
    try {
      final res = await Process.run('node', ['--version'], runInShell: true);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Проверяет, установлен ли dsh глобально
  Future<bool> isDshAvailable() async {
    try {
      final res = await Process.run('dsh', ['--version'], runInShell: true);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Обновляет или устанавливает @deepseek-ai/dsh до @latest версии
  Future<bool> updateOrInstallDsh({void Function(String)? onProgress}) async {
    if (_isUpdating) return false;
    _isUpdating = true;
    _statusMessage = 'Обновление DeepSeek Harness (@deepseek-ai/dsh@latest)...';
    notifyListeners();

    try {
      _addLog('[DSH] Запуск npm install -g @deepseek-ai/dsh@latest...');
      final process = await Process.start(
        'npm',
        ['install', '-g', '@deepseek-ai/dsh@latest'],
        runInShell: true,
      );

      process.stdout.transform(utf8.decoder).listen((data) {
        _addLog(data);
        onProgress?.call(data);
      });

      process.stderr.transform(utf8.decoder).listen((data) {
        _addLog('[stderr] $data');
        onProgress?.call(data);
      });

      final exitCode = await process.exitCode;
      _isUpdating = false;
      if (exitCode == 0) {
        _addLog('[DSH] DeepSeek Harness успешно установлен / обновлен!');
        _statusMessage = 'Обновлен до актуальной версии';
        notifyListeners();
        return true;
      } else {
        _addLog('[DSH] Ошибка установки, код: $exitCode');
        _statusMessage = 'Ошибка обновления';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isUpdating = false;
      _addLog('[DSH] Ошибка запуска npm: $e');
      _statusMessage = 'Ошибка: $e';
      notifyListeners();
      return false;
    }
  }

  /// Запускает сервер DeepSeek Harness в папке указанного проекта
  Future<bool> startServer({
    required String projectPath,
    required SettingsState settings,
  }) async {
    if (_process != null) {
      if (_currentProjectPath == projectPath) {
        return true;
      }
      await stopServer();
    }

    _isStarting = true;
    _currentProjectPath = projectPath;
    _currentPort = settings.dshPort > 0 ? settings.dshPort : 3080;
    _statusMessage = 'Запуск на порту $_currentPort в $projectPath...';
    _addLog('[DSH] Инициализация агента в директории: $projectPath');
    notifyListeners();

    // Формируем переменные окружения с ключами провайдеров
    final env = Map<String, String>.from(Platform.environment);
    if (settings.deepseekApiKey.isNotEmpty) {
      env['DEEPSEEK_API_KEY'] = settings.deepseekApiKey;
    }
    if (settings.openrouterApiKey.isNotEmpty) {
      env['OPENROUTER_API_KEY'] = settings.openrouterApiKey;
    }
    if (settings.openaiApiKey.isNotEmpty) {
      env['OPENAI_API_KEY'] = settings.openaiApiKey;
    }
    if (settings.anthropicApiKey.isNotEmpty) {
      env['ANTHROPIC_API_KEY'] = settings.anthropicApiKey;
    }

    // Проверяем, существует ли папка проекта
    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        _addLog('[DSH Error] Не удалось создать директорию проекта: $e');
      }
    }

    try {
      // Пытаемся запустить через глобальный бинарник dsh, либо через npx
      final bool hasDsh = await isDshAvailable();
      final String executable = hasDsh ? 'dsh' : 'npx';
      final List<String> args = hasDsh
          ? ['web', '--port', '$_currentPort', '--no-open']
          : ['@deepseek-ai/dsh', 'web', '--port', '$_currentPort', '--no-open'];

      _addLog('[DSH] Выполняем: $executable ${args.join(' ')}');

      _process = await Process.start(
        executable,
        args,
        workingDirectory: projectPath,
        environment: env,
        runInShell: true,
      );

      _process?.stdout.transform(utf8.decoder).listen((data) {
        _addLog(data);
      });

      _process?.stderr.transform(utf8.decoder).listen((data) {
        _addLog('[stderr] $data');
      });

      _process?.exitCode.then((code) {
        _addLog('[DSH] Процесс завершился с кодом: $code');
        _process = null;
        _isStarting = false;
        _statusMessage = 'Остановлен (код $code)';
        notifyListeners();
      });

      // Ожидание старта сервера (health check)
      final bool ready = await _waitForServerReady(_currentPort);
      _isStarting = false;

      if (ready) {
        _statusMessage = 'Работает (порт $_currentPort)';
        _addLog('[DSH] Сервер готов к работе на $serverUrl');
        notifyListeners();
        return true;
      } else {
        _statusMessage = 'Запущен (ожидание подключения)';
        notifyListeners();
        return true;
      }
    } catch (e) {
      _isStarting = false;
      _process = null;
      _statusMessage = 'Ошибка запуска: $e';
      _addLog('[DSH Error] Исключение при запуске: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> _waitForServerReady(int port, {int timeoutSeconds = 12}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 500));
        socket.destroy();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  /// Останавливает сервер
  Future<void> stopServer() async {
    if (_process != null) {
      _addLog('[DSH] Остановка сервера...');
      _process?.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(milliseconds: 300));
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
    }
    _isStarting = false;
    _statusMessage = 'Остановлен';
    _addLog('[DSH] Сервер остановлен.');
    notifyListeners();
  }

  /// Перезапуск сервера
  Future<bool> restartServer({
    required String projectPath,
    required SettingsState settings,
  }) async {
    await stopServer();
    await Future.delayed(const Duration(milliseconds: 300));
    return await startServer(projectPath: projectPath, settings: settings);
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}

final deepseekHarnessServiceProvider = ChangeNotifierProvider<DeepSeekHarnessService>((ref) {
  return DeepSeekHarnessService();
});
