import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final bool isOutputExpanded;
  final int activeTab; // 0: Output, 1: Problems, 2: App Logs
  final double? progress;
  final String? projectPath;
  final String? projectType;

  const ProjectSyncState({
    this.status = ProjectSyncStatus.idle,
    this.title = 'Project Sync',
    this.currentStep = 'Initializing synchronization...',
    this.logs = const [],
    this.problems = const [],
    this.appLogs = const [],
    this.isPanelVisible = false,
    this.isOutputExpanded = false,
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
    bool? isOutputExpanded,
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
      isOutputExpanded: isOutputExpanded ?? this.isOutputExpanded,
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

  void setOutputExpanded(bool expanded) {
    state = state.copyWith(isOutputExpanded: expanded);
  }

  void toggleOutputExpanded() {
    state = state.copyWith(isOutputExpanded: !state.isOutputExpanded);
  }

  void togglePanel() {
    state = state.copyWith(isPanelVisible: !state.isPanelVisible);
  }

  void setActiveTab(int index) {
    state = state.copyWith(activeTab: index);
  }

  void dismiss() {
    _autoHideTimer?.cancel();
    state = state.copyWith(isPanelVisible: false, isOutputExpanded: false);
  }

  void cancelSync() {
    _autoHideTimer?.cancel();
    _currentHandle?.cancel();
    _currentHandle = null;
    if (state.isSyncing) {
      state = state.copyWith(status: ProjectSyncStatus.idle, isPanelVisible: false);
    }
  }

  String? _getManifestPath(String workspacePath, String detectedType) {
    switch (detectedType) {
      case 'flutter':
        return p.join(workspacePath, 'pubspec.yaml');
      case 'node':
        return p.join(workspacePath, 'package.json');
      case 'python':
        return p.join(workspacePath, 'requirements.txt');
      case 'gradle':
        final kts = File(p.join(workspacePath, 'build.gradle.kts'));
        if (kts.existsSync()) return kts.path;
        return p.join(workspacePath, 'build.gradle');
      default:
        return null;
    }
  }

  Future<bool> _checkIfAlreadySynced(String workspacePath, String detectedType) async {
    try {
      final manifestPath = _getManifestPath(workspacePath, detectedType);
      if (manifestPath == null) return false;

      final manifestFile = File(manifestPath);
      if (!await manifestFile.exists()) return false;

      // 1. Verify that target dependencies artifact actually exists
      if (detectedType == 'flutter') {
        final packageConfig = File(p.join(workspacePath, '.dart_tool', 'package_config.json'));
        if (!await packageConfig.exists()) {
          // Never synced before on this machine / directory
          return false;
        }
      } else if (detectedType == 'node') {
        final nodeModules = Directory(p.join(workspacePath, 'node_modules'));
        if (!await nodeModules.exists()) return false;
      }

      // 2. Check if manifest has changed since the last recorded sync
      final prefs = await SharedPreferences.getInstance();
      final lastSyncKey = 'project_sync_last_mtime_$workspacePath';
      final lastRecordedMTime = prefs.getInt(lastSyncKey);
      if (lastRecordedMTime == null) {
        // No record of a prior sync in this IDE installation
        return false;
      }

      final stat = await manifestFile.stat();
      final currentMTime = stat.modified.millisecondsSinceEpoch;

      // If manifest was modified after last sync, it needs sync!
      if (currentMTime > lastRecordedMTime) {
        return false;
      }

      // Everything is up-to-date!
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _recordSyncTimestamp(String workspacePath, String detectedType) async {
    try {
      final manifestPath = _getManifestPath(workspacePath, detectedType);
      if (manifestPath == null) return;
      final manifestFile = File(manifestPath);
      if (await manifestFile.exists()) {
        final stat = await manifestFile.stat();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('project_sync_last_mtime_$workspacePath', stat.modified.millisecondsSinceEpoch);
      }
    } catch (_) {}
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
    String initialStep = 'Analyzing project structure...';

    final hasPubspec = await File(p.join(workspacePath, 'pubspec.yaml')).exists();
    final hasGradle = await File(p.join(workspacePath, 'build.gradle')).exists() ||
        await File(p.join(workspacePath, 'build.gradle.kts')).exists() ||
        await File(p.join(workspacePath, 'android', 'build.gradle')).exists();
    final hasPackageJson = await File(p.join(workspacePath, 'package.json')).exists();
    final hasRequirements = await File(p.join(workspacePath, 'requirements.txt')).exists();

    if (hasPubspec) {
      detectedType = 'flutter';
      initialStep = 'Resolving Flutter packages (pub get)...';
      command =
          '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && '
          'flutter pub get && '
          '(if [ -d android ]; then '
          'echo "==> Configuring Android build settings..." && '
          'mkdir -p android ~/.gradle 2>/dev/null || true; '
          'sed -i "/extra-gen-snapshot-options/d" android/gradle.properties ~/.gradle/gradle.properties 2>/dev/null || true; '
          '(grep -q "org.gradle.jvmargs" android/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> android/gradle.properties 2>/dev/null || true); '
          '(grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true); '
          '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true); '
          'echo "==> Android environment ready."; '
          'fi)';
    } else if (hasGradle) {
      detectedType = 'gradle';
      initialStep = 'Resolving Gradle wrapper & properties...';
      command =
          '(mkdir -p ~/.gradle 2>/dev/null || true) && '
          '(if [ -f app/build.gradle.kts ] && grep -q "kotlinOptions" app/build.gradle.kts 2>/dev/null; then python3 -c "import re; p=\'app/build.gradle.kts\'; c=open(p).read(); c=re.sub(r\'[ \\t]*kotlinOptions\\s*[{][^}]*[}]\', \'\\n\', c); c+=\'\\ntasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {\\n    compilerOptions {\\n        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)\\n    }\\n}\\n\' if \'compilerOptions\' not in c else \'\'; open(p,\'w\').write(c)" 2>/dev/null || true; fi) && '
          '(if [ -f app/src/main/AndroidManifest.xml ] && grep -q "@mipmap/ic_launcher" app/src/main/AndroidManifest.xml 2>/dev/null; then sed -i "s/@mipmap\\/ic_launcher_round/@android:drawable\\/sym_def_app_icon/g; s/@mipmap\\/ic_launcher/@android:drawable\\/sym_def_app_icon/g" app/src/main/AndroidManifest.xml 2>/dev/null || true; mkdir -p app/src/main/res/mipmap-anydpi-v26 2>/dev/null || true; printf \'<?xml version="1.0" encoding="utf-8"?>\\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\\n    <background android:color="@android:color/holo_blue_dark"/>\\n    <foreground android:drawable="@android:drawable/sym_def_app_icon"/>\\n</adaptive-icon>\\n\' > app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml 2>/dev/null || true; cp app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml 2>/dev/null || true; fi) && '
          '([ -d /root/android-sdk ] && printf "sdk.dir=/root/android-sdk\\n" > local.properties 2>/dev/null || true) && '
          'sed -i "/extra-gen-snapshot-options/d" gradle.properties ~/.gradle/gradle.properties 2>/dev/null || true; '
          '(grep -q "org.gradle.jvmargs" gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> gradle.properties 2>/dev/null || true); '
          '(grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true); '
          '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true); '
          'if [ -f gradlew ]; then chmod +x gradlew && ./gradlew --no-daemon --max-workers=1 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=/usr/bin/aapt2 -Dandroid.enableJetifier=false -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m" -Djava.net.preferIPv4Stack=true help; else gradle --no-daemon --max-workers=1 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=/usr/bin/aapt2 -Dandroid.enableJetifier=false -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=512m" -Djava.net.preferIPv4Stack=true help; fi';
    } else if (hasPackageJson) {
      detectedType = 'node';
      initialStep = 'Resolving npm packages...';
      command = 'npm install';
    } else if (hasRequirements) {
      detectedType = 'python';
      initialStep = 'Resolving Python dependencies (pip)...';
      command = 'pip install -r requirements.txt';
    } else {
      // Nothing to sync for raw directory
      return;
    }

    // Check if project is already synced and does NOT need sync
    if (!force) {
      final isAlreadySynced = await _checkIfAlreadySynced(workspacePath, detectedType);
      if (isAlreadySynced) {
        LogService.log('ProjectSync: $workspacePath ($detectedType) is already up-to-date, skipping auto-sync.');
        state = state.copyWith(status: ProjectSyncStatus.idle, isPanelVisible: false);
        return;
      }
    }

    final initialLogs = [
      'Starting sync for project: ${p.basename(workspacePath)}',
      'Target environment: Linux aarch64 (Ubuntu container)',
      'Timestamp: ${DateTime.now().toIso8601String()}',
      '--------------------------------------------------',
    ];

    state = ProjectSyncState(
      status: ProjectSyncStatus.syncing,
      title: 'Project Sync',
      currentStep: initialStep,
      logs: initialLogs,
      problems: [],
      appLogs: ['[Sync] Project sync started for $workspacePath ($detectedType)'],
      isPanelVisible: true,
      isOutputExpanded: false,
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
      _processOutputLine('Sync start error: $e', isError: true);
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
    final lower = trimmed.toLowerCase();

    // Filter out standard harmless warnings and progress spinners written to stderr
    final isHarmlessNotice = lower.contains('woah! you appear to be trying to run flutter as root') ||
        lower.contains('we strongly recommend running the flutter tool without superuser privileges') ||
        lower == '/' ||
        lower == '📎' ||
        lower == '|' ||
        lower == '-' ||
        lower == '\\' ||
        lower.contains('picked up _java_options') ||
        lower.contains('resolving dependencies') ||
        lower.contains('downloading') ||
        lower.contains('got dependencies') ||
        lower.contains('running gradle task') ||
        lower.contains('caching disabled for');

    // Only actual fatal errors and exceptions count as problems
    final isActualError = !isHarmlessNotice &&
        (lower.contains('error:') ||
            lower.contains('failed:') ||
            lower.startsWith('error ') ||
            lower.contains('build failed') ||
            lower.contains('exception:') ||
            lower.contains('fatal:'));

    if (isActualError) {
      updatedProblems.add(trimmed);
      updatedAppLogs.add('[Problem] $trimmed');
    }

    // Dynamic step extraction for downloads, transforms and model evaluation
    String newStep = state.currentStep;
    if (trimmed.startsWith('Downloading https://')) {
      final parts = trimmed.split('/');
      if (parts.isNotEmpty) {
        final lastPart = parts.last.split(' ').first;
        newStep = 'Downloading: $lastPart';
      }
    } else if (trimmed.contains('AarTransform:') || trimmed.contains('JetifyTransform:')) {
      final match = RegExp(r'jetified-([^/\s]+)').firstMatch(trimmed);
      if (match != null) {
        newStep = 'Transforming: ${match.group(1)}';
      } else {
        newStep = 'Transforming AAR libraries...';
      }
    } else if (trimmed.contains('VariantDependencies')) {
      newStep = 'Fetching variant dependencies...';
    } else if (trimmed.contains('Selected build variant')) {
      newStep = trimmed;
    } else if (trimmed.contains('CONFIGURE SUCCESSFUL')) {
      newStep = '✓ Gradle configure successful';
    } else if (trimmed.startsWith('Resolving dependencies') ||
        trimmed.startsWith('Got dependencies') ||
        trimmed.startsWith('Running') ||
        trimmed.contains('Starting build') ||
        trimmed.contains('Evaluating project') ||
        trimmed.contains('Resolved plugin') ||
        trimmed.contains('Apply plugin') ||
        trimmed.contains('Creating ClassLoader') ||
        trimmed.contains('Run init scripts') ||
        trimmed.contains('Configuring Android')) {
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

    // Ignore cancelled syncs (e.g. project switched, sync retriggered, or SIGKILL/SIGINT)
    if (_currentHandle?.isCancelled == true || exitCode == -9 || exitCode == 130) {
      LogService.log('ProjectSync: ignored exit code $exitCode (cancelled)');
      return;
    }

    final isSuccess = exitCode == 0;
    final finishMsg = isSuccess
        ? '✓ Project synchronization completed successfully'
        : '⚠️ Sync failed (exit code $exitCode)';

    final updatedLogs = List<String>.from(state.logs)
      ..add('--------------------------------------------------')
      ..add(finishMsg);

    final updatedAppLogs = List<String>.from(state.appLogs)
      ..add('[Sync] Process exited with code $exitCode');

    state = state.copyWith(
      status: isSuccess ? ProjectSyncStatus.success : ProjectSyncStatus.error,
      title: isSuccess ? 'Project Synced' : 'Sync Failed',
      currentStep: finishMsg,
      logs: updatedLogs,
      appLogs: updatedAppLogs,
      activeTab: isSuccess ? state.activeTab : (state.problems.isNotEmpty ? 1 : 0),
      isOutputExpanded: !isSuccess, // Auto-expand details on error
    );

    LogService.log('ProjectSync finished with exit code: $exitCode');

    // Auto-dismiss floating banner after success in 4 seconds if not expanded
    if (isSuccess) {
      if (state.projectPath != null && state.projectType != null) {
        _recordSyncTimestamp(state.projectPath!, state.projectType!);
      }
      _autoHideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && state.status == ProjectSyncStatus.success && !state.isOutputExpanded) {
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
