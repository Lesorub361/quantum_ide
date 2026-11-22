import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/shizuku_bridge.dart';

/// Сервис непрерывной телеметрии и мониторинга для разработчиков и AI-ассистента.
/// Сохраняет живые метрики CPU, RAM, статус сборки и вывод терминала в /storage/emulated/0/QuantumIDE/
class LiveTelemetryService {
  LiveTelemetryService._();
  static final LiveTelemetryService instance = LiveTelemetryService._();

  File? _statusFile;
  File? _buildOutputFile;
  File? _globalLogFile;
  HttpServer? _httpServer;

  Timer? _periodicTimer;
  String? _lastFlushedJson;
  final List<String> _recentLogs = [];
  final List<String> _buildOutputTail = [];
  final StringBuffer _buildOutputBuffer = StringBuffer();
  Timer? _buildOutputFlushTimer;
  final StringBuffer _logBuffer = StringBuffer();
  Timer? _logFlushTimer;

  double currentCpu = 0.0;
  double currentGpu = 0.0;
  String gpuName = 'GPU';
  int appRamMB = 0;
  int builderRamMB = 0;
  double deviceRamFreeGB = 0.0;
  double deviceRamTotalGB = 0.0;
  String? currentWorkspace;
  String currentBuildStatus = 'Idle';
  bool get isBuilding => currentBuildStatus.toLowerCase() == 'running';
  String currentBuildCommand = '';
  DateTime? buildStartTime;
  Future<void> Function(String path)? onFileUpdated;

  Future<void> init() async {
    try {
      // External /storage/emulated/0/QuantumIDE telemetry disabled for faster I/O.
      _startTimer();
      _startLocalServer();
      logEvent('LiveTelemetryService initialized (in-memory only).');
    } catch (e) {
      debugPrint('[Telemetry] Init error: $e');
    }
  }

  void _startTimer() {
    _periodicTimer?.cancel();
    if (_statusFile != null) {
      _periodicTimer =
          Timer.periodic(const Duration(seconds: 8), (_) => flushStatus());
    }
  }

  Future<void> _startLocalServer() async {
    try {
      _httpServer?.close(force: true);
      _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 45169);
      _httpServer!.listen((HttpRequest request) async {
        try {
          final uri = request.uri.path;
          if (uri == '/status' || uri == '/' || uri == '/diagnostics') {
            final data = _buildStatusMap();
            request.response
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(data));
          } else if (uri == '/build') {
            request.response
              ..headers.contentType = ContentType.text
              ..write(_buildOutputTail.join('\n'));
          } else if (uri == '/logs') {
            request.response
              ..headers.contentType = ContentType.text
              ..write(_recentLogs.join('\n'));
          } else if (uri == '/read') {
            final reqPath = request.uri.queryParameters['path'];
            if (reqPath == null || reqPath.isEmpty) {
              request.response.statusCode = HttpStatus.badRequest;
              request.response.write('Missing path query parameter');
            } else {
              final ws = currentWorkspace;
              final fullPath = p.isAbsolute(reqPath)
                  ? reqPath
                  : (ws != null ? p.join(ws, reqPath) : reqPath);
              final f = File(fullPath);
              if (await f.exists()) {
                request.response
                  ..headers.contentType = ContentType.text
                  ..write(await f.readAsString());
              } else {
                request.response.statusCode = HttpStatus.notFound;
                request.response.write('File not found: $fullPath');
              }
            }
          } else if (uri == '/write' && request.method == 'POST') {
            final reqPath = request.uri.queryParameters['path'];
            if (reqPath == null || reqPath.isEmpty) {
              request.response.statusCode = HttpStatus.badRequest;
              request.response.write('Missing path query parameter');
            } else {
              final body = await utf8.decoder.bind(request).join();
              final ws = currentWorkspace;
              final fullPath = p.isAbsolute(reqPath)
                  ? reqPath
                  : (ws != null ? p.join(ws, reqPath) : reqPath);
              final f = File(fullPath);
              await f.parent.create(recursive: true);
              await f.writeAsString(body, flush: true);

              await onFileUpdated?.call(fullPath);
              logEvent('Remote file updated: $fullPath (${body.length} bytes)');
              request.response
                ..headers.contentType = ContentType.json
                ..write(jsonEncode({'status': 'ok', 'path': fullPath, 'bytes': body.length}));
            }
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
        } catch (e) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('Error: $e');
        } finally {
          await request.response.close();
        }
      });
    } catch (_) {}
  }

  void updateStats({
    required double cpu,
    required double gpu,
    required String gpuTitle,
    required int appRam,
    required int builderRam,
    required double freeRamGB,
    required double totalRamGB,
  }) {
    currentCpu = cpu;
    currentGpu = gpu;
    gpuName = gpuTitle;
    appRamMB = appRam;
    builderRamMB = builderRam;
    deviceRamFreeGB = freeRamGB;
    deviceRamTotalGB = totalRamGB;
  }

  void onBuildStarted(String command) {
    currentBuildStatus = 'Running';
    currentBuildCommand = command;
    buildStartTime = DateTime.now();
    _buildOutputTail.clear();
    _buildOutputBuffer.clear();
    _buildOutputFlushTimer?.cancel();
    try {
      _buildOutputFile?.writeAsString(
        '=== Сборка запущена: ${DateTime.now()} ===\nКоманда: $command\n\n',
        mode: FileMode.write,
      ).catchError((_) => _buildOutputFile!);
    } catch (_) {}
    flushStatus();
  }

  void onBuildFinished(int exitCode) {
    _flushBuildOutputBufferNow();
    final dur = buildStartTime != null
        ? DateTime.now().difference(buildStartTime!).inSeconds
        : 0;
    currentBuildStatus = exitCode == 0 ? 'Success (${dur}s)' : 'Failed (code $exitCode, ${dur}s)';
    try {
      _buildOutputFile?.writeAsString(
        '\n=== Сборка завершена: $currentBuildStatus ===\n',
        mode: FileMode.append,
      ).catchError((_) => _buildOutputFile!);
    } catch (_) {}
    flushStatus();
  }

  void appendBuildOutput(String text) {
    // Strip escape control codes for clean reading
    final clean = text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    final lines = clean.split('\n');
    for (final l in lines) {
      if (l.trim().isNotEmpty) {
        _buildOutputTail.add(l);
        if (_buildOutputTail.length > 300) {
          _buildOutputTail.removeAt(0);
        }

        // Auto-detect build completion if running
        if (currentBuildStatus == 'Running') {
          if (l.contains('BUILD SUCCESSFUL') ||
              l.contains('Built build/app/outputs') ||
              l.contains('✓  Built build/app/outputs') ||
              l.contains('Built build/web')) {
            onBuildFinished(0);
          } else if (l.contains('BUILD FAILED') ||
              l.contains('assembleRelease failed') ||
              l.contains('assembleDebug failed') ||
              l.contains('Compilation failed')) {
            onBuildFinished(1);
          }
        }
      }
    }

    _buildOutputBuffer.write(clean);
    _scheduleBuildOutputFlush();
  }

  void _scheduleBuildOutputFlush() {
    if (_buildOutputFlushTimer != null && _buildOutputFlushTimer!.isActive) return;
    _buildOutputFlushTimer = Timer(const Duration(milliseconds: 300), _flushBuildOutputBufferNow);
  }

  void _flushBuildOutputBufferNow() {
    _buildOutputFlushTimer?.cancel();
    _buildOutputFlushTimer = null;
    if (_buildOutputBuffer.isEmpty) return;
    final textToWrite = _buildOutputBuffer.toString();
    _buildOutputBuffer.clear();
    try {
      _buildOutputFile?.writeAsString(textToWrite, mode: FileMode.append, flush: false).catchError((_) => _buildOutputFile!);
    } catch (_) {}
  }

  void logEvent(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$timestamp] $msg';
    _recentLogs.add(entry);
    if (_recentLogs.length > 100) {
      _recentLogs.removeAt(0);
    }

    _logBuffer.writeln(entry);
    if (_logFlushTimer == null || !_logFlushTimer!.isActive) {
      _logFlushTimer = Timer(const Duration(seconds: 1), _flushLogBufferNow);
    }
  }

  void _flushLogBufferNow() {
    _logFlushTimer?.cancel();
    _logFlushTimer = null;
    if (_logBuffer.isEmpty) return;
    final textToWrite = _logBuffer.toString();
    _logBuffer.clear();
    try {
      _globalLogFile?.writeAsString(textToWrite, mode: FileMode.append, flush: false).catchError((_) => _globalLogFile!);
    } catch (_) {}
  }

  Map<String, dynamic> get statusSnapshot => _buildStatusMap();

  Map<String, dynamic> _buildStatusMap() {
    final logsTail = _recentLogs.length > 20
        ? _recentLogs.sublist(_recentLogs.length - 20)
        : List<String>.from(_recentLogs);
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'system': {
        'cpuPercent': (currentCpu * 100).toStringAsFixed(1),
        'gpuPercent': (currentGpu * 100).toStringAsFixed(1),
        'gpuName': gpuName,
        'appRamMB': appRamMB,
        'builderRamMB': builderRamMB,
        'deviceRamFreeGB': deviceRamFreeGB.toStringAsFixed(2),
        'deviceRamTotalGB': deviceRamTotalGB.toStringAsFixed(1),
      },
      'shizuku': {
        'available': ShizukuBridge.instance.isAvailable,
        'binderAlive': ShizukuBridge.instance.isBinderAlive,
        'permissionGranted': ShizukuBridge.instance.hasPermission,
        'uid': ShizukuBridge.instance.uid,
        'error': ShizukuBridge.instance.lastError,
      },
      'workspace': {
        'path': currentWorkspace ?? 'None',
      },
      'build': {
        'status': currentBuildStatus,
        'command': currentBuildCommand,
        'startTime': buildStartTime?.toIso8601String(),
        'durationSeconds': buildStartTime != null
            ? DateTime.now().difference(buildStartTime!).inSeconds
            : null,
      },
      'recentLogsTail': logsTail,
      'buildOutputTail': _buildOutputTail.length > 30
          ? _buildOutputTail.sublist(_buildOutputTail.length - 30)
          : _buildOutputTail,
    };
  }

  Future<void> flushStatus() async {
    final f = _statusFile;
    if (f == null) return;
    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_buildStatusMap());
      if (jsonStr == _lastFlushedJson) return;
      _lastFlushedJson = jsonStr;
      await f.writeAsString(jsonStr, mode: FileMode.write, flush: false);
    } catch (_) {}
  }
}
