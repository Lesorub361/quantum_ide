import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

enum TestStatus { idle, running, passed, failed, error }

class TestResult {
  final String name;
  final TestStatus status;
  final String? error;
  final Duration? duration;

  const TestResult({
    required this.name,
    required this.status,
    this.error,
    this.duration,
  });
}

class TestRunnerState {
  final TestStatus status;
  final List<TestResult> results;
  final int passed;
  final int failed;
  final String? outputPath;
  final bool isRunning;

  const TestRunnerState({
    this.status = TestStatus.idle,
    this.results = const [],
    this.passed = 0,
    this.failed = 0,
    this.outputPath,
    this.isRunning = false,
  });

  TestRunnerState copyWith({
    TestStatus? status,
    List<TestResult>? results,
    int? passed,
    int? failed,
    String? outputPath,
    bool? isRunning,
  }) {
    return TestRunnerState(
      status: status ?? this.status,
      results: results ?? this.results,
      passed: passed ?? this.passed,
      failed: failed ?? this.failed,
      outputPath: outputPath ?? this.outputPath,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

class TestRunnerNotifier extends StateNotifier<TestRunnerState> {
  final Ref _ref;

  TestRunnerNotifier(this._ref) : super(const TestRunnerState());

  Future<void> runAll() async {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    state = state.copyWith(
      status: TestStatus.running,
      isRunning: true,
      results: [],
      passed: 0,
      failed: 0,
    );

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final result = await runtime.runCommand(
        'cd "$workspacePath" && flutter test --reporter expanded 2>&1',
      );
      _parseOutput(result);
    } catch (e) {
      state = state.copyWith(
        status: TestStatus.error,
        isRunning: false,
        results: [TestResult(name: 'Error', status: TestStatus.error, error: e.toString())],
      );
    }
  }

  Future<void> runFile(String filePath) async {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    state = state.copyWith(
      status: TestStatus.running,
      isRunning: true,
      results: [],
      passed: 0,
      failed: 0,
    );

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final result = await runtime.runCommand(
        'cd "$workspacePath" && flutter test "$filePath" --reporter expanded 2>&1',
      );
      _parseOutput(result);
    } catch (e) {
      state = state.copyWith(
        status: TestStatus.error,
        isRunning: false,
        results: [TestResult(name: 'Error', status: TestStatus.error, error: e.toString())],
      );
    }
  }

  void _parseOutput(String output) {
    final results = <TestResult>[];
    int passed = 0;
    int failed = 0;

    final lines = output.split('\n');
    for (final line in lines) {
      if (line.contains('✓') || line.contains('+')) {
        final name = line.replaceAll(RegExp(r'[✓+\s]'), '').trim();
        if (name.isNotEmpty) {
          results.add(TestResult(name: name, status: TestStatus.passed));
          passed++;
        }
      } else if (line.contains('✗') || line.contains('×')) {
        final name = line.replaceAll(RegExp(r'[✗×\s]'), '').trim();
        if (name.isNotEmpty) {
          results.add(TestResult(name: name, status: TestStatus.failed));
          failed++;
        }
      }
    }

    final status = failed > 0 ? TestStatus.failed : (passed > 0 ? TestStatus.passed : TestStatus.error);

    state = state.copyWith(
      status: status,
      results: results,
      passed: passed,
      failed: failed,
      isRunning: false,
    );
  }

  void clear() {
    state = const TestRunnerState();
  }
}

final testRunnerProvider = StateNotifierProvider<TestRunnerNotifier, TestRunnerState>((ref) {
  return TestRunnerNotifier(ref);
});
