import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/code_diagnostic.dart';

class AiContextCompressor {
  Set<String> _cachedFilePaths = {};
  String? _cachedWorkspaceRoot;
  bool _hasSentFullContext = false;

  AiContextCompressor();

  /// Reset cache to force full context on next call
  void reset() {
    _cachedFilePaths.clear();
    _cachedWorkspaceRoot = null;
    _hasSentFullContext = false;
  }

  /// Scans workspace and builds the file listing
  Future<Set<String>> _scanWorkspace(String workspaceRoot) async {
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

    final currentFiles = await _scanWorkspace(workspaceRoot);
    final projectName = p.basename(workspaceRoot);
    String projectType = 'Generic Project';
    if (currentFiles.contains('pubspec.yaml')) {
      projectType = 'Flutter/Dart Project';
    } else if (currentFiles.contains('package.json')) {
      projectType = 'Node.js/JavaScript Project';
    } else if (currentFiles.contains('CMakeLists.txt')) {
      projectType = 'C/C++ Project';
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
        buffer.writeln(currentFiles.map((p) => "- $p").join('\n'));
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
        buffer.writeln(addedFiles.map((p) => "  + $p").join('\n'));
      }
      if (removedFiles.isNotEmpty) {
        buffer.writeln('Удаленные файлы (Removed files since last turn):');
        buffer.writeln(removedFiles.map((p) => "  - $p").join('\n'));
      }
      
      // Update cached paths
      _cachedFilePaths = currentFiles;
    }
    
    buffer.writeln('==================================================\n');
    return buffer.toString();
  }
}
