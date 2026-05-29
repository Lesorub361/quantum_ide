import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:path/path.dart' as p;

import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class AnalysisService {
  final Ref ref;
  Timer? _debounceTimer;
  bool _isAnalyzing = false;
  bool _pendingAnalysis = false;

  AnalysisService(this.ref);

  Future<String> _getGuestPath(String hostPath) async {
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  void triggerAnalysis({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      runAnalysis();
    } else {
      _debounceTimer = Timer(const Duration(seconds: 2), () {
        runAnalysis();
      });
    }
  }

  Future<void> runAnalysis() async {
    if (_isAnalyzing) {
      _pendingAnalysis = true;
      return;
    }

    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;

    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);
    if (!runtime.isInitialized) return;

    _isAnalyzing = true;
    _pendingAnalysis = false;
    
    try {
      debugPrint('AnalysisService: Starting full project analysis in PRoot...');
      
      final output = await runtime.runCommand(
        'cd "$guestPath" && dart analyze --format=machine . 2>/dev/null || true',
      );

      final diagnosticsMap = <String, List<CodeDiagnostic>>{};

      if (output.isNotEmpty) {
        final lines = output.split('\n');
        for (var line in lines) {
          if (line.isEmpty) continue;
          final parts = line.split('|');
          if (parts.length < 8) continue;

          // Format: SEVERITY|TYPE|ERROR_CODE|FILE_PATH|LINE|COLUMN|LENGTH|MESSAGE
          final severityStr = parts[0];
          final relativePath = parts[3];
          final lineNum = int.tryParse(parts[4]) ?? 1;
          final colNum = int.tryParse(parts[5]) ?? 1;
          final length = int.tryParse(parts[6]) ?? 0;
          final message = parts.sublist(7).join('|');

          final severity = _parseSeverity(severityStr);
          // The path from dart analyze inside proot is relative to guestPath
          final guestFullPath = p.isAbsolute(relativePath) ? relativePath : p.join(guestPath, relativePath);
          final fullPath = PathMapper.mapToHost(guestFullPath, runtime.appDirectory, activeWorkspacePath: hostPath);
          
          final diagnostic = CodeDiagnostic(
            range: CodeLineRange(
              index: lineNum - 1,
              start: colNum - 1,
              end: colNum - 1 + length,
            ),
            message: message,
            severity: severity,
          );

          if (!diagnosticsMap.containsKey(fullPath)) {
            diagnosticsMap[fullPath] = [];
          }
          diagnosticsMap[fullPath]!.add(diagnostic);
        }
      }

      // Update the editor notifier with new diagnostics
      final editorNotifier = ref.read(editorProvider.notifier);
      
      // Update files with new diagnostics
      for (final path in diagnosticsMap.keys) {
        editorNotifier.updateDiagnostics(path, diagnosticsMap[path]!);
      }
      
      // Clear diagnostics for files that were previously analyzed but now have none
      final previousDiagnostics = ref.read(editorProvider).allDiagnostics;
      for (final oldPath in previousDiagnostics.keys) {
        if (!diagnosticsMap.containsKey(oldPath)) {
          editorNotifier.updateDiagnostics(oldPath, []);
        }
      }

    } catch (e) {
      debugPrint('Analysis failed: $e');
    } finally {
      _isAnalyzing = false;
      if (_pendingAnalysis) {
        runAnalysis();
      }
    }
  }

  CodeDiagnosticSeverity _parseSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'error': return CodeDiagnosticSeverity.error;
      case 'warning': return CodeDiagnosticSeverity.warning;
      case 'info': return CodeDiagnosticSeverity.hint;
      default: return CodeDiagnosticSeverity.hint;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
  }
}

final analysisServiceProvider = Provider((ref) {
  final service = AnalysisService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
