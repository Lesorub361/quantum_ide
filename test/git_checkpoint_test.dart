import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class _MockWorkspaceNotifier extends StateNotifier<WorkspaceState> implements WorkspaceNotifier {
  _MockWorkspaceNotifier(String path) : super(WorkspaceState(currentPath: path));

  @override
  Ref get ref => throw UnimplementedError();

  @override
  Future<void> setWorkspace(String path) async {
    state = state.copyWith(currentPath: path);
  }

  @override
  Future<void> clearWorkspace() async {
    state = state.copyWith(clearCurrentPath: true);
  }

  @override
  Future<void> addToRecent(String path) async {}

  @override
  Future<void> removeFromRecent(String path) async {}

  @override
  Future<void> clearRecent() async {}

  @override
  Future<void> closeWorkspace() async {
    state = state.copyWith(clearCurrentPath: true);
  }

  @override
  Future<void> restoreLastWorkspace() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('quantum_git_test_');
    
    // Set up git repo in tempDir
    final runtime = RuntimeService();
    await runtime.runCommand('cd "${tempDir.path}" && git init');
    await runtime.runCommand('cd "${tempDir.path}" && git config user.email "test@quantum.ide"');
    await runtime.runCommand('cd "${tempDir.path}" && git config user.name "QuantumTester"');
    
    final readme = File('${tempDir.path}/README.md');
    await readme.writeAsString('Initial content\n');
    await runtime.runCommand('cd "${tempDir.path}" && git add README.md && git commit -m "initial"');

    container = ProviderContainer(
      overrides: [
        workspaceProvider.overrideWith((ref) => _MockWorkspaceNotifier(tempDir.path)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Git Checkpoint & Rollback Tests', () {
    test('creates clean-head checkpoint when working tree has no uncommitted changes', () async {
      final gitService = container.read(gitServiceProvider);
      final ref = await gitService.createAgentCheckpoint();

      expect(ref, isNotNull);
      expect(ref!.startsWith('clean-head:'), isTrue);
    });

    test('creates stash checkpoint when working tree has uncommitted modifications', () async {
      final readme = File('${tempDir.path}/README.md');
      await readme.writeAsString('Uncommitted user changes\n');

      final gitService = container.read(gitServiceProvider);
      final ref = await gitService.createAgentCheckpoint();

      expect(ref, isNotNull);
      expect(ref!.startsWith('quantum-ide-agent-checkpoint-'), isTrue);
    });

    test('rolls back agent changes when tree was originally clean', () async {
      final gitService = container.read(gitServiceProvider);
      final checkpointRef = await gitService.createAgentCheckpoint();
      expect(checkpointRef, isNotNull);

      // Simulate agent creating new file and editing README
      final agentFile = File('${tempDir.path}/agent_generated.dart');
      await agentFile.writeAsString('class AgentCode {}\n');
      final readme = File('${tempDir.path}/README.md');
      await readme.writeAsString('Modified by agent\n');

      expect(await agentFile.exists(), isTrue);

      // Perform rollback
      final rolledBack = await gitService.rollbackAgentCheckpoint(checkpointRef);
      expect(rolledBack, isTrue);

      // Verify agent's file is removed and README is restored
      expect(await agentFile.exists(), isFalse);
      expect(await readme.readAsString(), equals('Initial content\n'));
    });

    test('rolls back agent changes and restores user uncommitted work when stashed', () async {
      final readme = File('${tempDir.path}/README.md');
      await readme.writeAsString('User work before agent\n');

      final gitService = container.read(gitServiceProvider);
      final checkpointRef = await gitService.createAgentCheckpoint();
      expect(checkpointRef, isNotNull);
      expect(checkpointRef!.startsWith('quantum-ide-agent-checkpoint-'), isTrue);

      // Simulate agent making changes
      final agentFile = File('${tempDir.path}/new_feature.dart');
      await agentFile.writeAsString('class Feature {}\n');
      await readme.writeAsString('Agent overwritten work\n');

      // Rollback
      final rolledBack = await gitService.rollbackAgentCheckpoint(checkpointRef);
      expect(rolledBack, isTrue);

      // Verify agent file was deleted and user work was restored
      expect(await agentFile.exists(), isFalse);
      expect(await readme.readAsString(), equals('User work before agent\n'));
    });
  });
}
