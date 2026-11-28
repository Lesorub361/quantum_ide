import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'build_diagnostics_service.dart';
import 'editor_performance_service.dart';
import 'ghost_qa_service.dart';
import 'live_telemetry_service.dart';
import 'shizuku_bridge.dart';
export 'quantum_plugin_service.dart';
export 'adb_device_service.dart';

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

/// Provider for GhostQAService (Autonomous AI Screen & QA Testing Engine)
final ghostQAServiceProvider = Provider<GhostQAService>((ref) {
  return GhostQAService.instance;
});

/// Provider for ShizukuBridge (elevated ADB / root bridge)
final shizukuBridgeProvider = Provider<ShizukuBridge>((ref) {
  return ShizukuBridge.instance;
});

/// Provider for LiveTelemetryService (runtime logs, metrics, terminal monitoring)
final liveTelemetryServiceProvider = Provider<LiveTelemetryService>((ref) {
  return LiveTelemetryService.instance;
});
