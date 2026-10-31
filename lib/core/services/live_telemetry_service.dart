import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Сервис непрерывной телеметрии и мониторинга для разработчиков и AI-ассистента.
/// Сохраняет живые метрики CPU, RAM, статус сборки и вывод терминала в /storage/emulated/0/QuantumIDE/
class LiveTelemetryService {
  LiveTelemetryService._();
  static final LiveTelemetryService instance = LiveTelemetryService._();

  static const String _sharedDir = '/storage/emulated/0/QuantumIDE';
  File? _statusFile;
  File? _buildOutputFile;
  File? _globalLogFile;
  HttpServer? _httpServer;

  Timer? _periodicTimer;
  final List<String> _recentLogs = [];
  final List<String> _buildOutputTail = [];

  double currentCpu = 0.0;
  double currentGpu = 0.0;
  String gpuName = 'GPU';
  int appRamMB = 0;
  int builderRamMB = 0;
  double deviceRamFreeGB = 0.0;
  double deviceRamTotalGB = 0.0;
  String? currentWorkspace;
  String currentBuildStatus = 'Idle';
  String currentBuildCommand = '';
  DateTime? buildStartTime;

  Future<void> init() async {
    try {
      final dir = Directory(_sharedDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _statusFile = File(p.join(_sharedDir, 'live_status.json'));
      _buildOutputFile = File(p.join(_sharedDir, 'build_output.log'));
      _globalLogFile = File(p.join(_sharedDir, 'quantum_live.log'));

      _startTimer();
      _startLocalServer();
      logEvent('LiveTelemetryService initialized successfully.');
    } catch (e) {
      debugPrint('[Telemetry] Init error: $e');
    }
  }

  void _startTimer() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 2), (_) => flushStatus());
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
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
        } catch (_) {
          request.response.statusCode = HttpStatus.internalServerError;
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
    try {
      _buildOutputFile?.writeAsStringSync(
        '=== Сборка запущена: ${DateTime.now()} ===\nКоманда: $command\n\n',
        mode: FileMode.write,
      );
    } catch (_) {}
    flushStatus();
  }

  void onBuildFinished(int exitCode) {
    final dur = buildStartTime != null
        ? DateTime.now().difference(buildStartTime!).inSeconds
        : 0;
    currentBuildStatus = exitCode == 0 ? 'Success (${dur}s)' : 'Failed (code $exitCode, ${dur}s)';
    try {
      _buildOutputFile?.writeAsStringSync(
        '\n=== Сборка завершена: $currentBuildStatus ===\n',
        mode: FileMode.append,
      );
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
              l.contains('✓  Built build/app/outputs')) {
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

    try {
      _buildOutputFile?.writeAsStringSync(clean, mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  void logEvent(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$timestamp] $msg';
    _recentLogs.add(entry);
    if (_recentLogs.length > 100) {
      _recentLogs.removeAt(0);
    }

    try {
      _globalLogFile?.writeAsStringSync('$entry\n', mode: FileMode.append, flush: false);
    } catch (_) {}
  }

  Map<String, dynamic> _buildStatusMap() {
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
      'recentLogsTail': _recentLogs.take(20).toList(),
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
      await f.writeAsString(jsonStr, mode: FileMode.write, flush: true);
    } catch (_) {}
  }
}
