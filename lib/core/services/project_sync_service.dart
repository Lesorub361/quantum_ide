import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/log_service.dart';

enum ProjectSyncStatus {
  idle,
  syncing,
  success,
  error,
}

class ProjectSyncState {
  final ProjectSyncStatus status;
  final String title;
  final String currentStep;
  final List<String> logs;
  final List<String> problems;
  final List<String> appLogs;
  final bool isPanelVisible;
  final int activeTab; // 0: Вывод, 1: Проблемы, 2: Логи приложения
  final double? progress;
  final String? projectPath;
  final String? projectType;

  const ProjectSyncState({
    this.status = ProjectSyncStatus.idle,
    this.title = 'Синхронизация проекта...',
    this.currentStep = 'Инициализация синхронизации...',
    this.logs = const [],
    this.problems = const [],
    this.appLogs = const [],
    this.isPanelVisible = false,
    this.activeTab = 0,
    this.progress,
    this.projectPath,
    this.projectType,
  });

  bool get isSyncing => status == ProjectSyncStatus.syncing;
  bool get hasProblems => problems.isNotEmpty;

  ProjectSyncState copyWith({
    ProjectSyncStatus? status,
    String? title,
    String? currentStep,
    List<String>? logs,
    List<String>? problems,
    List<String>? appLogs,
    bool? isPanelVisible,
    int? activeTab,
    double? progress,
    bool clearProgress = false,
    String? projectPath,
    String? projectType,
  }) {
    return ProjectSyncState(
      status: status ?? this.status,
      title: title ?? this.title,
      currentStep: currentStep ?? this.currentStep,
      logs: logs ?? this.logs,
      problems: problems ?? this.problems,
      appLogs: appLogs ?? this.appLogs,
      isPanelVisible: isPanelVisible ?? this.isPanelVisible,
      activeTab: activeTab ?? this.activeTab,
      progress: clearProgress ? null : (progress ?? this.progress),
      projectPath: projectPath ?? this.projectPath,
      projectType: projectType ?? this.projectType,
    );
  }
}

class ProjectSyncNotifier extends StateNotifier<ProjectSyncState> {
  final Ref ref;
  StreamingCommand? _currentHandle;
  Timer? _autoHideTimer;

  ProjectSyncNotifier(this.ref) : super(const ProjectSyncState());

  void setPanelVisible(bool visible) {
    state = state.copyWith(isPanelVisible: visible);
  }

  void togglePanel() {
    state = state.copyWith(isPanelVisible: !state.isPanelVisible);
  }

  void setActiveTab(int index) {
    state = state.copyWith(activeTab: index);
  }

  void dismiss() {
    _autoHideTimer?.cancel();
    state = state.copyWith(isPanelVisible: false);
  }

  Future<void> startSync(String workspacePath, {bool force = false}) async {
    // If already syncing this path, don't restart unless forced
    if (state.isSyncing && !force && state.projectPath == workspacePath) {
      return;
    }

    _autoHideTimer?.cancel();
    _currentHandle?.cancel();

    final dir = Directory(workspacePath);
    if (!await dir.exists()) return;

    // Detect project type
    String detectedType = 'generic';
    String command = '';
    String initialStep = 'Определение структуры проекта...';

    final hasPubspec = await File(p.join(workspacePath, 'pubspec.yaml')).exists();
    final hasGradle = await File(p.join(workspacePath, 'build.gradle')).exists() ||
        await File(p.join(workspacePath, 'build.gradle.kts')).exists() ||
        await File(p.join(workspacePath, 'android', 'build.gradle')).exists();
    final hasPackageJson = await File(p.join(workspacePath, 'package.json')).exists();
    final hasRequirements = await File(p.join(workspacePath, 'requirements.txt')).exists();

    if (hasPubspec) {
      detectedType = 'flutter';
      initialStep = 'Выполняется Flutter pub get...';
      command =
          '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && flutter pub get';
    } else if (hasGradle) {
      detectedType = 'gradle';
      initialStep = 'Синхронизация Gradle и плагинов...';
      command = 'if [ -f gradlew ]; then chmod +x gradlew && ./gradlew --dry-run; else gradle --dry-run; fi';
    } else if (hasPackageJson) {
      detectedType = 'node';
      initialStep = 'Проверка npm зависимостей...';
      command = 'npm install --dry-run 2>/dev/null || npm list --depth=0';
    } else if (hasRequirements) {
      detectedType = 'python';
      initialStep = 'Проверка зависимостей Python (pip)...';
      command = 'pip check 2>/dev/null || pip list';
    } else {
      // Nothing to sync for raw directory
      return;
    }

    final initialLogs = [
      'Starting sync for project: ${p.basename(workspacePath)}',
      'Target environment: Linux aarch64 (Ubuntu container)',
      'Timestamp: ${DateTime.now().toIso8601String()}',
      '--------------------------------------------------',
    ];

    state = ProjectSyncState(
      status: ProjectSyncStatus.syncing,
      title: 'Синхронизация проекта...',
      currentStep: initialStep,
      logs: initialLogs,
      problems: [],
      appLogs: ['[Sync] Project sync started for $workspacePath ($detectedType)'],
      isPanelVisible: true,
      activeTab: 0,
      progress: null,
      projectPath: workspacePath,
      projectType: detectedType,
    );

    final runtime = ref.read(runtimeServiceProvider);

    try {
      _currentHandle = runtime.runCommandStream(
        command,
        workingDirectory: workspacePath,
        onLine: (line, {bool isError = false, bool replace = false}) {
          _processOutputLine(line, isError: isError);
        },
      );

      final exitCode = await _currentHandle!.exitCode;
      _onSyncFinished(exitCode);
    } catch (e) {
      _processOutputLine('Ошибка запуска синхронизации: $e', isError: true);
      _onSyncFinished(1);
    }
  }

  void _processOutputLine(String line, {bool isError = false}) {
    if (!mounted) return;

    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final updatedLogs = List<String>.from(state.logs)..add(trimmed);
    final updatedProblems = List<String>.from(state.problems);
    final updatedAppLogs = List<String>.from(state.appLogs);

    // Check for problems / errors
    final lower = trimmed.toLowerCase();
    if (isError ||
        lower.contains('error:') ||
        lower.contains('failed') ||
        lower.contains('exception:') ||
        lower.contains('fatal:')) {
      updatedProblems.add(trimmed);
      updatedAppLogs.add('[Problem] $trimmed');
    }

    // Try to extract dynamic step information
    String newStep = state.currentStep;
    if (trimmed.startsWith('Resolving dependencies') ||
        trimmed.startsWith('Downloading') ||
        trimmed.startsWith('Got dependencies') ||
        trimmed.startsWith('Running') ||
        trimmed.contains('Starting build') ||
        trimmed.contains('Evaluating project') ||
        trimmed.contains('Resolved plugin') ||
        trimmed.contains('Apply plugin') ||
        trimmed.contains('Creating ClassLoader') ||
        trimmed.contains('Run init scripts')) {
      newStep = trimmed;
    }

    state = state.copyWith(
      logs: updatedLogs,
      problems: updatedProblems,
      appLogs: updatedAppLogs,
      currentStep: newStep,
    );
  }

  void _onSyncFinished(int exitCode) {
    if (!mounted) return;

    final isSuccess = exitCode == 0;
    final finishMsg = isSuccess
        ? '✓ Синхронизация проекта завершена успешно!'
        : '⚠️ Ошибка синхронизации (код $exitCode)';

    final updatedLogs = List<String>.from(state.logs)
      ..add('--------------------------------------------------')
      ..add(finishMsg);

    final updatedAppLogs = List<String>.from(state.appLogs)
      ..add('[Sync] Process exited with code $exitCode');

    state = state.copyWith(
      status: isSuccess ? ProjectSyncStatus.success : ProjectSyncStatus.error,
      title: isSuccess ? 'Проект синхронизирован' : 'Синхронизация с ошибками',
      currentStep: finishMsg,
      logs: updatedLogs,
      appLogs: updatedAppLogs,
      activeTab: isSuccess ? state.activeTab : (state.problems.isNotEmpty ? 1 : 0),
    );

    LogService.log('ProjectSync finished with exit code: $exitCode');

    // Auto-dismiss floating banner after success in 4 seconds
    if (isSuccess) {
      _autoHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && state.status == ProjectSyncStatus.success) {
          state = state.copyWith(isPanelVisible: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _currentHandle?.cancel();
    super.dispose();
  }
}

final projectSyncProvider =
    StateNotifierProvider<ProjectSyncNotifier, ProjectSyncState>((ref) {
  return ProjectSyncNotifier(ref);
});
