import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class LogService {
  static String? _cacheDir;
  static File? _logFile;
  
  static final List<String> _inMemoryLogs = [];
  static const int _maxInMemoryLines = 1000;
  
  static final StreamController<String> _logStreamController = StreamController<String>.broadcast();
  
  static Stream<String> get logStream => _logStreamController.stream;
  static List<String> get logs => List.unmodifiable(_inMemoryLogs);

  static final List<String> _writeBuffer = [];
  static Timer? _flushTimer;
  static const Duration _flushInterval = Duration(seconds: 2);

  static Future<void> init(String cacheDir) async {
    _cacheDir = cacheDir;
    await _updateLogFile();
    _startFlushTimer();
    log('LogService initialized. App version logs starting.');
  }

  static void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  static Future<void> _flush() async {
    if (_writeBuffer.isEmpty) return;
    final lines = List<String>.from(_writeBuffer);
    _writeBuffer.clear();

    final file = _logFile;
    if (file == null) return;

    try {
      final sink = file.openWrite(mode: FileMode.append);
      for (final line in lines) {
        sink.writeln(line);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {}
  }

  static Future<void> setWorkspace(String? workspacePath) async {
    await _flush();
    if (workspacePath != null) {
      try {
        final qDir = Directory(p.join(workspacePath, '.quantum'));
        if (!await qDir.exists()) {
          await qDir.create(recursive: true);
        }
        
        final newLogFile = File(p.join(qDir.path, 'app.log'));
        
        if (_logFile != null && await _logFile!.exists()) {
          final content = await _logFile!.readAsString();
          await newLogFile.writeAsString(content, mode: FileMode.write);
          await _logFile!.delete();
        }
        
        _logFile = newLogFile;
        log('Workspace set to: $workspacePath. Logging redirected to .quantum/app.log');
      } catch (e) {
        log('Failed to redirect logs to workspace: $e');
      }
    } else {
      await _updateLogFile();
    }
  }

  static Future<void> _updateLogFile() async {
    if (_cacheDir != null) {
      _logFile = File(p.join(_cacheDir!, 'app_cache.log'));
    }
  }

  static void log(String message) {
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    final formattedLine = '[$timestamp] $message';
    
    _inMemoryLogs.add(formattedLine);
    if (_inMemoryLogs.length > _maxInMemoryLines) {
      _inMemoryLogs.removeAt(0);
    }
    
    _logStreamController.add(formattedLine);
    
    if (kDebugMode) {
      try {
        stdout.writeln(formattedLine);
      } catch (_) {}
    }

    _writeBuffer.add(formattedLine);
  }

  static void clear() {
    _inMemoryLogs.clear();
    _writeBuffer.clear();
    _logStreamController.add('--- Logs Cleared ---');
    _flush().then((_) {
      try {
        if (_logFile != null) {
          _logFile!.writeAsStringSync('', mode: FileMode.write);
        }
      } catch (_) {}
    });
  }

  static void dispose() {
    _flushTimer?.cancel();
    _flush();
  }
}
