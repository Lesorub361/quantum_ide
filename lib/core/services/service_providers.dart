import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'build_diagnostics_service.dart';
import 'editor_performance_service.dart';
import 'microvm_service.dart';
import 'wasm_plugin_runner.dart';
import 'crdt_sync_service.dart';
import 'ai_agent_orchestrator.dart';
import 'docker_service.dart';
import 'ssh_service.dart';
import 'mlc_llm_service.dart';
import 'marketplace_service.dart';
import 'ai_scenario_executor.dart';
import 'runtime_service.dart';
import 'collaboration_service.dart';

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

/// Provider for MicroVMService (Android 15+ KVM)
final microvmServiceProvider = ChangeNotifierProvider<MicroVMService>((ref) {
  final runtime = ref.read(runtimeServiceProvider);
  final service = MicroVMService(runtime);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for WasmPluginRunner
final wasmPluginRunnerProvider = ChangeNotifierProvider<WasmPluginRunner>((ref) {
  final runtime = ref.read(runtimeServiceProvider);
  final service = WasmPluginRunner(runtime);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for CrdtSyncService
final crdtSyncServiceProvider = ChangeNotifierProvider<CrdtSyncService>((ref) {
  final collaboration = ref.read(collaborationProvider.notifier);
  final service = CrdtSyncService(collaboration);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for AiAgentOrchestrator
final aiAgentOrchestratorProvider = ChangeNotifierProvider<AiAgentOrchestrator>((ref) {
  final runtime = ref.read(runtimeServiceProvider);
  final service = AiAgentOrchestrator(runtime, ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for DockerService
final dockerServiceProvider = ChangeNotifierProvider<DockerService>((ref) {
  final service = DockerService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for SshService
final sshServiceProvider = ChangeNotifierProvider<SshService>((ref) {
  final service = SshService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for MlcLlmService
final mlcLlmServiceProvider = StateNotifierProvider<MlcLlmService, MlcModelState>((ref) {
  final service = MlcLlmService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for MarketplaceService
final marketplaceServiceProvider = StateNotifierProvider<MarketplaceService, MarketplaceState>((ref) {
  final service = MarketplaceService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for AiScenarioExecutor
final aiScenarioExecutorProvider = StateNotifierProvider<AiScenarioExecutor, AiScenarioExecutionState>((ref) {
  final service = AiScenarioExecutor(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
