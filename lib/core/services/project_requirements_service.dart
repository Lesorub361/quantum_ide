import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/optional_package.dart';
import '../../models/project_model.dart';
import 'project_detector.dart';
import 'package_service.dart';
import '../../features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';

class ProjectRequirementsResult {
  final String projectPath;
  final String projectName;
  final ProjectType projectType;
  final List<OptionalPackage> missingPackages;

  ProjectRequirementsResult({
    required this.projectPath,
    required this.projectName,
    required this.projectType,
    required this.missingPackages,
  });

  bool get hasMissing => missingPackages.isNotEmpty;
}

class ProjectRequirementsService {
  final Ref _ref;
  final Set<String> _checkedPaths = <String>{};
  static const _checkedPrefsKey = 'checked_project_requirements_paths_v2';

  ProjectRequirementsService(this._ref);

  /// Checks missing packages required for [projectPath].
  /// Returns [ProjectRequirementsResult] or null if already checked and dismissed.
  Future<ProjectRequirementsResult?> checkProjectRequirements(
    String projectPath, {
    bool force = false,
  }) async {
    if (projectPath.isEmpty) return null;
    if (!force && _checkedPaths.contains(projectPath)) return null;

    final prefs = await SharedPreferences.getInstance();
    final persistedPaths = (prefs.getStringList(_checkedPrefsKey) ?? []).toSet();
    _checkedPaths.addAll(persistedPaths);
    if (!force && _checkedPaths.contains(projectPath)) return null;

    final dir = Directory(projectPath);
    if (!await dir.exists()) return null;

    // Wait for actual filesystem package verification before reading state
    await _ref.read(packageServiceProvider.notifier).checkActualInstallation();

    final projectType = await ProjectDetector.detect(projectPath);
    final projectName = p.basename(projectPath);

    // Make sure we have latest packages installation state
    final packagesList = _ref.read(packageServiceProvider);
    final packageMap = {for (final pkg in packagesList) pkg.id: pkg};

    bool hasAnyAndroidPlatform() {
      return (packageMap['platform-android-36']?.isInstalled ?? false) ||
          (packageMap['platform-android-35']?.isInstalled ?? false) ||
          (packageMap['platform-android-34']?.isInstalled ?? false);
    }

    bool hasAnyAndroidBuildTools() {
      return (packageMap['build-tools-36.0.0']?.isInstalled ?? false) ||
          (packageMap['build-tools-35.0.0']?.isInstalled ?? false) ||
          (packageMap['build-tools-34.0.0']?.isInstalled ?? false) ||
          (packageMap['android-sdk-tools-arm64']?.isInstalled ?? false);
    }

    final requiredPackageIds = <String>{};

    switch (projectType) {
      case ProjectType.flutter:
        requiredPackageIds.add('flutter');
        final androidDir = Directory(p.join(projectPath, 'android'));
        if (await androidDir.exists()) {
          requiredPackageIds.add('android-sdk');

          final compileSdk = await _detectCompileSdk(androidDir.path);
          if (!hasAnyAndroidPlatform()) {
            if (compileSdk >= 36) {
              requiredPackageIds.add('platform-android-36');
            } else if (compileSdk == 35) {
              requiredPackageIds.add('platform-android-35');
            } else {
              requiredPackageIds.add('platform-android-34');
            }
          }
          if (!hasAnyAndroidBuildTools()) {
            if (compileSdk >= 36) {
              requiredPackageIds.add('build-tools-36.0.0');
            } else if (compileSdk == 35) {
              requiredPackageIds.add('build-tools-35.0.0');
            } else {
              requiredPackageIds.add('build-tools-34.0.0');
            }
          }

          // Check if C++/CMake is used
          if (await _hasNativeCmake(projectPath)) {
            if (!(packageMap['cmake-3.31']?.isInstalled ?? false)) {
              requiredPackageIds.add('cmake-3.22');
            }
          }
        }
        // Only require Linux desktop build tools when running on Desktop Linux
        if (!Platform.isAndroid && !Platform.isIOS) {
          final linuxDir = Directory(p.join(projectPath, 'linux'));
          if (await linuxDir.exists()) {
            requiredPackageIds.add('desktop-build-tools');
          }
        }
        break;

      case ProjectType.dart:
        requiredPackageIds.add('flutter');
        break;

      case ProjectType.nodejs:
        requiredPackageIds.add('nodejs');
        break;

      case ProjectType.python:
        requiredPackageIds.add('python');
        break;

      case ProjectType.rust:
        requiredPackageIds.add('rust-arm64');
        break;

      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        requiredPackageIds.add('android-sdk');
        final compileSdk = await _detectCompileSdk(projectPath);
        if (!hasAnyAndroidPlatform()) {
          if (compileSdk >= 36) {
            requiredPackageIds.add('platform-android-36');
          } else {
            requiredPackageIds.add('platform-android-35');
          }
        }
        if (!hasAnyAndroidBuildTools()) {
          if (compileSdk >= 36) {
            requiredPackageIds.add('build-tools-36.0.0');
          } else {
            requiredPackageIds.add('build-tools-35.0.0');
          }
        }
        break;

      default:
        if (!Platform.isAndroid && !Platform.isIOS) {
          if (await File(p.join(projectPath, 'CMakeLists.txt')).exists()) {
            requiredPackageIds.add('desktop-build-tools');
          }
        }
        break;
    }

    // Filter missing packages
    final missing = <OptionalPackage>[];
    for (final id in requiredPackageIds) {
      final pkg = packageMap[id];
      if (pkg != null && !pkg.isInstalled) {
        missing.add(pkg);
      }
    }

    _checkedPaths.add(projectPath);
    await prefs.setStringList(_checkedPrefsKey, _checkedPaths.toList());

    return ProjectRequirementsResult(
      projectPath: projectPath,
      projectName: projectName,
      projectType: projectType,
      missingPackages: missing,
    );
  }

  Future<int> _detectCompileSdk(String androidPath) async {
    try {
      final gradleFiles = [
        File(p.join(androidPath, 'app', 'build.gradle')),
        File(p.join(androidPath, 'app', 'build.gradle.kts')),
        File(p.join(androidPath, 'build.gradle')),
        File(p.join(androidPath, 'build.gradle.kts')),
      ];

      final regex = RegExp(r'compileSdk\s*=?\s*([0-9]+)');
      for (final f in gradleFiles) {
        if (await f.exists()) {
          final content = await f.readAsString();
          final match = regex.firstMatch(content);
          if (match != null) {
            return int.tryParse(match.group(1) ?? '') ?? 35;
          }
        }
      }
    } catch (_) {}
    return 35;
  }

  Future<bool> _hasNativeCmake(String projectPath) async {
    try {
      if (await File(p.join(projectPath, 'android', 'CMakeLists.txt')).exists()) return true;
      if (await File(p.join(projectPath, 'CMakeLists.txt')).exists()) return true;
      final localPlugins = Directory(p.join(projectPath, 'local_plugins'));
      if (await localPlugins.exists()) {
        await for (final entity in localPlugins.list(recursive: true)) {
          if (entity is File && p.basename(entity.path) == 'CMakeLists.txt') {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Installs all missing packages in one click by running their commands in sequence
  void installMissingPackages(List<OptionalPackage> packages) {
    if (packages.isEmpty) return;

    final terminal = _ref.read(terminalTabsProvider.notifier);
    final packageService = _ref.read(packageServiceProvider.notifier);

    // Mark packages as installing in UI and persist in preferences
    for (final pkg in packages) {
      pkg.isInstalling = true;
      packageService.markPackageInstalled(pkg.id);
    }

    final commands = <String>[];
    commands.add('echo "=== Установка необходимых пакетов для проекта (${packages.length} шт.) ==="');

    for (final pkg in packages) {
      commands.add('echo ">>> Установка: ${pkg.name}..."');
      String cmd = pkg.command;
      if (!Platform.isAndroid) {
        cmd = cmd.replaceAll('apt install', 'sudo apt install');
      }
      commands.add('($cmd)');
    }

    commands.add('echo "=== Все необходимые пакеты успешно установлены! ==="');

    final fullCommand = commands.join(' && ');
    terminal.sendCommand(fullCommand);

    // Refresh status after installation progresses/completes
    for (final delaySec in [10, 30, 60, 120]) {
      Future.delayed(Duration(seconds: delaySec), () {
        packageService.checkActualInstallation();
      });
    }
  }
}

final projectRequirementsServiceProvider = Provider<ProjectRequirementsService>((ref) {
  return ProjectRequirementsService(ref);
});
