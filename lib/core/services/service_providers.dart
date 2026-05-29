import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'build_diagnostics_service.dart';
import 'editor_performance_service.dart';

/// Provider for BuildDiagnosticsService
final buildDiagnosticsServiceProvider = Provider((ref) {
  final service = BuildDiagnosticsService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for EditorPerformanceService
final editorPerformanceServiceProvider = Provider((ref) {
  final service = EditorPerformanceService();
  ref.onDispose(() => service.dispose());
  return service;
});
