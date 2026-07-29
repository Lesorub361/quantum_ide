import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/code_diagnostic.dart';

class AiContextCompressor {
  Set<String> _cachedFilePaths = {};
  String? _cachedWorkspaceRoot;
  bool _hasSentFullContext = false;

  // Кеш результата сканирования — обновляется не чаще раза в 30 секунд
  DateTime? _lastScanTime;
  static const _scanCooldown = Duration(seconds: 30);

  AiContextCompressor();

  /// Reset cache to force full context on next call
  void reset() {
    _cachedFilePaths.clear();
    _cachedWorkspaceRoot = null;
    _hasSentFullContext = false;
    _lastScanTime = null;
  }

  /// Scans workspace and builds the file listing.
  /// Результат кешируется на 30 секунд — повторный вызов вернёт кеш без IO.
  Future<Set<String>> _scanWorkspace(String workspaceRoot) async {
    final now = DateTime.now();
    // Возвращаем кеш если workspace не сменился и прошло < 30 секунд (и мы не в тесте)
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest &&
        _cachedWorkspaceRoot == workspaceRoot &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < _scanCooldown &&
        _cachedFilePaths.isNotEmpty) {
      return _cachedFilePaths;
    }

    final files = <String>{};
    try {
      final dir = Directory(workspaceRoot);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final relPath = p.relative(entity.path, from: workspaceRoot);
            final segments = p.split(relPath);
            // Ignore common build/meta directories
            if (segments.any((s) => s.startsWith('.') ||
                                    s == 'build' ||
                                    s == 'node_modules' ||
                                    s == 'gradle' ||
                                    s == 'android' && segments.first == 'android' && segments.length > 2)) {
              continue;
            }
            files.add(relPath);
          }
        }
      }
    } catch (_) {}

    _lastScanTime = now;
    return files;
  }

  /// Returns compressed context overview for the agent prompt.
  Future<String> getCompressedContext({
    required String workspaceRoot,
    required List<String> openFiles,
    required String activeFile,
    required Map<String, List<CodeDiagnostic>> diagnostics,
    bool forceFull = false,
  }) async {
    final isFirstRun = !_hasSentFullContext || _cachedWorkspaceRoot != workspaceRoot || forceFull;
    _cachedWorkspaceRoot = workspaceRoot;

    // Если forceFull — сбрасываем кеш времени, чтобы принудительно пересканировать
    if (forceFull) _lastScanTime = null;

    final currentFiles = await _scanWorkspace(workspaceRoot);
    final projectName = p.basename(workspaceRoot);
    String projectType = 'Generic Project';
    if (currentFiles.contains('pubspec.yaml')) {
      projectType = 'Flutter/Dart Project';
    } else if (currentFiles.any((f) => f.endsWith('build.gradle') || f.endsWith('build.gradle.kts'))) {
      final hasKotlin = currentFiles.any((f) => f.endsWith('.kt'));
      projectType = hasKotlin ? 'Android Kotlin Project (Gradle)' : 'Android Java Project (Gradle)';
    } else if (currentFiles.contains('package.json')) {
      projectType = 'Node.js/JavaScript Project';
    } else if (currentFiles.contains('CMakeLists.txt')) {
      projectType = 'C/C++ Project';
    } else if (currentFiles.any((f) => f.endsWith('.py'))) {
      projectType = 'Python Project';
    } else if (currentFiles.any((f) => f == 'index.html' || (f.endsWith('.html') && !f.contains('/')))) {
      projectType = 'Web/HTML Project';
    } else if (currentFiles.any((f) => f.endsWith('.sh'))) {
      projectType = 'Shell Script Project';
    }

    final buffer = StringBuffer();
    buffer.writeln('\n=== ТЕКУЩИЙ КОНТЕКСТ ПРОЕКТА (PROJECT CONTEXT) ===');
    buffer.writeln('Имя проекта (Project Name): $projectName');
    buffer.writeln('Тип проекта (Project Type): $projectType');
    buffer.writeln('Путь к проекту (Project Root): $workspaceRoot');

    if (openFiles.isNotEmpty) {
      buffer.writeln('Открытые файлы (Open Tabs): ${openFiles.join(", ")}');
    }
    buffer.writeln('Активный файл в редакторе (Active File): $activeFile');

    // Diagnostics / Analyzer warnings
    final diagnosticsText = <String>[];
    diagnostics.forEach((filePath, diags) {
      if (diags.isNotEmpty) {
        final relPath = p.isWithin(workspaceRoot, filePath)
            ? p.relative(filePath, from: workspaceRoot)
            : filePath;
        for (final d in diags) {
          if (d.severity == CodeDiagnosticSeverity.error || d.severity == CodeDiagnosticSeverity.warning) {
            final severityStr = d.severity == CodeDiagnosticSeverity.error ? 'ERROR' : 'WARNING';
            diagnosticsText.add('- $relPath (строка ${d.range.index + 1}, колонка ${d.range.start + 1}): [$severityStr] ${d.message}');
          }
        }
      }
    });

    if (diagnosticsText.isNotEmpty) {
      buffer.writeln('\nОшибки анализа кода (Project Diagnostics):');
      buffer.writeln(diagnosticsText.join('\n'));
    }

    if (isFirstRun) {
      // Send full file structure on first run or when forced
      buffer.writeln('\nСтруктура файлов проекта (Project Files Structure):');
      if (currentFiles.isNotEmpty) {
        buffer.writeln(currentFiles.map((f) => '- $f').join('\n'));
      } else {
        buffer.writeln('(Пусто)');
      }
      _cachedFilePaths = currentFiles;
      _hasSentFullContext = true;
    } else {
      // Calculate deltas for prefix memory efficiency
      final addedFiles = currentFiles.difference(_cachedFilePaths);
      final removedFiles = _cachedFilePaths.difference(currentFiles);

      buffer.writeln('\n[Префиксная память: Структура файлов кэширована в контексте]');
      buffer.writeln('Всего файлов в проекте (Total files): ${currentFiles.length}');

      if (addedFiles.isNotEmpty) {
        buffer.writeln('Добавленные файлы (Added files since last turn):');
        buffer.writeln(addedFiles.map((f) => '  + $f').join('\n'));
      }
      if (removedFiles.isNotEmpty) {
        buffer.writeln('Удаленные файлы (Removed files since last turn):');
        buffer.writeln(removedFiles.map((f) => '  - $f').join('\n'));
      }

      // Update cached paths
      _cachedFilePaths = currentFiles;
    }

    buffer.writeln('==================================================\n');
    
    String result = buffer.toString();
    
    // Smart truncation: keep total context under 6000 chars for local models,
    // but keep the project path and open files info always.
    // Only trim the file listing if it's too long.
    if (result.length > 6000) {
      final lines = result.split('\n');
      final truncated = <String>[];
      int fileCount = 0;
      bool inFileSection = false;
      int charCount = 0;
      const maxChars = 5500;
      const maxFilesShown = 60;
      
      for (final line in lines) {
        if (line.contains('Project Files Structure') || line.contains('Структура файлов')) {
          inFileSection = true;
          truncated.add(line);
          charCount += line.length + 1;
          continue;
        }
        
        if (line.contains('Кэширована в контексте') || line.contains('Prefix')) {
          inFileSection = false;
        }
        
        if (inFileSection && line.startsWith('- ')) {
          fileCount++;
          if (fileCount > maxFilesShown || charCount > maxChars) {
            // Only add the truncation notice once
            if (fileCount == maxFilesShown + 1 || charCount > maxChars) {
              final remaining = lines.where((l) => l.startsWith('- ')).length - fileCount + 1;
              truncated.add('- ... (ещё $remaining файлов — используй list_dir чтобы посмотреть)');
              inFileSection = false;
            }
            continue;
          }
        }
        
        truncated.add(line);
        charCount += line.length + 1;
      }
      
      result = truncated.join('\n');
    }
    
    return result;
  }
}
