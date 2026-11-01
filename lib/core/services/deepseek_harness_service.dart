import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class DeepSeekHarnessService extends ChangeNotifier {
  final RuntimeService _runtime;

  DeepSeekHarnessService(this._runtime);

  Process? _process;
  StreamingCommand? _activeCommand;
  String? _currentProjectPath;
  int _currentPort = 3080;
  bool _isStarting = false;
  bool _isServerReady = false;
  bool _isUpdating = false;
  String _statusMessage = 'Остановлен';
  final List<String> _logs = [];

  bool get isRunning => _process != null && _isServerReady;
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
    if (_logs.length > 250) {
      _logs.removeAt(0);
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// Проверяет, доступен ли Node.js в окружении Quantum IDE
  Future<bool> isNodeAvailable() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final out = await _runtime.runCommand('node --version');
        return out.trim().isNotEmpty && !out.contains('not found');
      } else {
        final res = await Process.run('node', ['--version'], runInShell: true);
        return res.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  /// Проверяет, установлен ли dsh глобально в окружении
  Future<bool> isDshAvailable() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final out = await _runtime.runCommand(
          'which dsh || command -v dsh || (test -f /usr/local/bin/dsh && echo /usr/local/bin/dsh) || (test -f /usr/bin/dsh && echo /usr/bin/dsh)',
        );
        return out.trim().isNotEmpty && !out.contains('not found');
      } else {
        final res = await Process.run('dsh', ['--version'], runInShell: true);
        return res.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  /// Обновляет или устанавливает @deepseek-ai/dsh до @latest версии через внутреннее окружение
  Future<bool> updateOrInstallDsh({void Function(String)? onProgress}) async {
    if (_isUpdating) return false;
    _isUpdating = true;
    _statusMessage = 'Установка / обновление @deepseek-ai/dsh@latest...';
    notifyListeners();

    try {
      _addLog('[DSH] Запуск npm install -g @deepseek-ai/dsh@latest в окружении...');

      final installCmd = 'npm install -g @deepseek-ai/dsh@latest && '
          '(ln -sf \$(which dsh 2>/dev/null || echo /usr/local/lib/nodejs/bin/dsh) /usr/local/bin/dsh 2>/dev/null || true) && '
          '(ln -sf \$(which dsh 2>/dev/null || echo /usr/local/lib/nodejs/bin/dsh) /usr/bin/dsh 2>/dev/null || true)';

      int exitCode;
      if (Platform.isAndroid || Platform.isIOS) {
        final stream = _runtime.runCommandStream(
          installCmd,
          onLine: (line, {bool isError = false, bool replace = false}) {
            final formatted = isError ? '[stderr] $line' : line;
            _addLog(formatted);
            onProgress?.call(line);
          },
        );
        _activeCommand = stream;
        exitCode = await stream.exitCode;
      } else {
        final process = await Process.start(
          Platform.isWindows ? 'cmd' : 'bash',
          Platform.isWindows ? ['/c', installCmd] : ['-c', installCmd],
          environment: _runtime.desktopEnv,
        );
        process.stdout.transform(utf8.decoder).listen((data) {
          _addLog(data);
          onProgress?.call(data);
        });
        process.stderr.transform(utf8.decoder).listen((data) {
          _addLog('[stderr] $data');
          onProgress?.call(data);
        });
        exitCode = await process.exitCode;
      }

      _isUpdating = false;
      _activeCommand = null;
      if (exitCode == 0) {
        _addLog('[DSH] DeepSeek Harness успешно установлен / обновлен!');
        _statusMessage = 'Обновлен до актуальной версии';
        notifyListeners();
        return true;
      } else {
        _addLog('[DSH] Ошибка установки, код завершения: $exitCode');
        _statusMessage = 'Ошибка обновления (код $exitCode)';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isUpdating = false;
      _activeCommand = null;
      _addLog('[DSH] Ошибка: $e');
      _statusMessage = 'Ошибка: $e';
      notifyListeners();
      return false;
    }
  }

  /// Запускает веб-сервер DeepSeek Harness в окружении Quantum IDE для указанного проекта
  Future<bool> startServer({
    required String projectPath,
    required SettingsState settings,
  }) async {
    if (_process != null && _isServerReady) {
      if (_currentProjectPath == projectPath) {
        return true;
      }
      await stopServer();
    }

    _isStarting = true;
    _isServerReady = false;
    _currentProjectPath = projectPath;
    _currentPort = settings.dshPort > 0 ? settings.dshPort : 3080;
    _statusMessage = 'Запуск на порту $_currentPort в $projectPath...';
    _addLog('[DSH] Инициализация агента в директории: $projectPath');
    notifyListeners();

    // Проверяем / создаем директорию проекта
    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        _addLog('[DSH Error] Не удалось создать директорию проекта: $e');
      }
    }

    // Собираем экспорты API-ключей
    final List<String> exportList = [];
    if (settings.deepseekApiKey.isNotEmpty) {
      exportList.add('export DEEPSEEK_API_KEY="${settings.deepseekApiKey.replaceAll('"', r'\"')}"');
    }
    if (settings.openrouterApiKey.isNotEmpty) {
      exportList.add('export OPENROUTER_API_KEY="${settings.openrouterApiKey.replaceAll('"', r'\"')}"');
    }
    if (settings.openaiApiKey.isNotEmpty) {
      exportList.add('export OPENAI_API_KEY="${settings.openaiApiKey.replaceAll('"', r'\"')}"');
    }
    if (settings.anthropicApiKey.isNotEmpty) {
      exportList.add('export ANTHROPIC_API_KEY="${settings.anthropicApiKey.replaceAll('"', r'\"')}"');
    }
    exportList.add('export PORT="$_currentPort"');
    exportList.add('export HOST="127.0.0.1"');

    final exportsPrefix = exportList.isNotEmpty ? '${exportList.join('; ')}; ' : '';
    final runCmd = '${exportsPrefix}if command -v dsh >/dev/null 2>&1; then exec dsh web --port $_currentPort --no-open; else exec npx --yes @deepseek-ai/dsh web --port $_currentPort --no-open; fi';

    _addLog('[DSH] Команда: dsh web --port $_currentPort --no-open');

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final initHost = p.join(_runtime.filesDir, 'bin', 'init-host');
        if (Platform.isAndroid && await File(initHost).exists()) {
          final guestCwd = PathMapper.mapToGuest(projectPath, _runtime.filesDir);
          _addLog('[DSH] Запуск через Linux-окружение Quantum IDE (guest cwd: $guestCwd)...');
          _process = await Process.start(
            'sh',
            [
              initHost,
              _runtime.filesDir,
              guestCwd,
              '/bin/bash',
              '-c',
              runCmd,
            ],
          );
        } else {
          _addLog('[DSH] Запуск напрямую...');
          final env = Map<String, String>.from(Platform.environment);
          if (settings.deepseekApiKey.isNotEmpty) env['DEEPSEEK_API_KEY'] = settings.deepseekApiKey;
          if (settings.openrouterApiKey.isNotEmpty) env['OPENROUTER_API_KEY'] = settings.openrouterApiKey;
          if (settings.openaiApiKey.isNotEmpty) env['OPENAI_API_KEY'] = settings.openaiApiKey;
          if (settings.anthropicApiKey.isNotEmpty) env['ANTHROPIC_API_KEY'] = settings.anthropicApiKey;
          env['PORT'] = '$_currentPort';
          _process = await Process.start(
            'sh',
            ['-c', runCmd],
            workingDirectory: projectPath,
            environment: env,
          );
        }
      } else {
        // Desktop
        final env = _runtime.desktopEnv;
        if (settings.deepseekApiKey.isNotEmpty) env['DEEPSEEK_API_KEY'] = settings.deepseekApiKey;
        if (settings.openrouterApiKey.isNotEmpty) env['OPENROUTER_API_KEY'] = settings.openrouterApiKey;
        if (settings.openaiApiKey.isNotEmpty) env['OPENAI_API_KEY'] = settings.openaiApiKey;
        if (settings.anthropicApiKey.isNotEmpty) env['ANTHROPIC_API_KEY'] = settings.anthropicApiKey;
        env['PORT'] = '$_currentPort';

        _process = await Process.start(
          Platform.isWindows ? 'cmd' : 'bash',
          Platform.isWindows ? ['/c', runCmd] : ['-c', runCmd],
          workingDirectory: projectPath,
          environment: env,
        );
      }

      _process?.stdout.transform(utf8.decoder).listen((data) {
        _addLog(data);
      });

      _process?.stderr.transform(utf8.decoder).listen((data) {
        _addLog('[stderr] $data');
      });

      _process?.exitCode.then((code) {
        _addLog('[DSH] Процесс завершился с кодом: $code');
        _process = null;
        _isServerReady = false;
        _isStarting = false;
        _statusMessage = 'Остановлен (код $code)';
        notifyListeners();
      });

      // Ожидание готовности веб-сервера
      final bool ready = await _waitForServerReady(_currentPort);
      _isStarting = false;

      if (ready) {
        _isServerReady = true;
        _statusMessage = 'Работает (порт $_currentPort)';
        _addLog('[DSH] Сервер готов к работе на $serverUrl');
        notifyListeners();
        return true;
      } else {
        if (_process == null) {
          _statusMessage = 'Ошибка запуска (процесс завершился)';
        } else {
          _statusMessage = 'Запущен (ожидание порта $_currentPort)';
          _isServerReady = true;
        }
        notifyListeners();
        return _isServerReady;
      }
    } catch (e) {
      _isStarting = false;
      _isServerReady = false;
      _process = null;
      _statusMessage = 'Ошибка запуска: $e';
      _addLog('[DSH Error] Исключение при запуске: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> _waitForServerReady(int port, {int timeoutSeconds = 15}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      if (_process == null) return false;
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
    if (Platform.isAndroid) {
      try {
        await _runtime.runCommand('pkill -f "@deepseek-ai/dsh" || pkill -f "dsh web" || true');
      } catch (_) {}
    }
    _isServerReady = false;
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
    await Future.delayed(const Duration(milliseconds: 400));
    return await startServer(projectPath: projectPath, settings: settings);
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}

final deepseekHarnessServiceProvider = ChangeNotifierProvider<DeepSeekHarnessService>((ref) {
  final runtime = ref.watch(runtimeServiceProvider);
  return DeepSeekHarnessService(runtime);
});
