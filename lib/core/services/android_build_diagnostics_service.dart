import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum AndroidIssueSeverity { info, warning, error }

class AndroidBuildIssue {
  final AndroidIssueSeverity severity;
  final String title;
  final String detail;
  final String? suggestion;
  final String? filePath;
  final int? line;
  final int? column;

  const AndroidBuildIssue({
    this.severity = AndroidIssueSeverity.error,
    required this.title,
    required this.detail,
    this.suggestion,
    this.filePath,
    this.line,
    this.column,
  });

  Map<String, dynamic> toJson() => {
    'severity': severity.name,
    'title': title,
    'detail': detail,
    'suggestion': suggestion,
    'filePath': filePath,
    'line': line,
    'column': column,
  };
}

class AndroidApkInfo {
  final String path;
  final String fileName;
  final int sizeBytes;
  final DateTime lastModified;
  final bool isStale;
  final String? packageName;
  final String? versionName;
  final int? versionCode;

  const AndroidApkInfo({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.lastModified,
    this.isStale = false,
    this.packageName,
    this.versionName,
    this.versionCode,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

final androidBuildDiagnosticsServiceProvider = Provider<AndroidBuildDiagnosticsService>((ref) {
  return AndroidBuildDiagnosticsService();
});

class AndroidBuildDiagnosticsService {
  static const Set<String> _ignoredDirectories = {
    'build',
    '.gradle',
    '.idea',
    '.git',
    '.dart_tool',
    'node_modules',
  };

  static const Set<String> _buildInputExtensions = {
    'kt',
    'java',
    'xml',
    'gradle',
    'kts',
    'properties',
    'toml',
    'pro',
    'json',
    'dart',
    'c',
    'cpp',
    'h',
  };

  /// Locates the freshest built debug APK in the workspace using Gradle's official
  /// output-metadata.json when present, and falls back to filesystem search.
  AndroidApkInfo? findDebugApk(String projectRoot) {
    final rootDir = Directory(projectRoot);
    if (!rootDir.existsSync()) return null;

    // 1. Search for output-metadata.json in APK output folders (standard AGP layout)
    try {
      final metadataFiles = <File>[];
      _collectFilesNamed(rootDir, 'output-metadata.json', metadataFiles, maxDepth: 6);

      metadataFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      for (final metadata in metadataFiles) {
        if (!metadata.path.contains('/outputs/apk/')) continue;
        try {
          final content = metadata.readAsStringSync();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final elements = json['elements'] as List? ?? [];
          for (final elem in elements) {
            if (elem is! Map) continue;
            final outputFile = elem['outputFile']?.toString();
            if (outputFile == null || outputFile.isEmpty) continue;

            final apkFile = File(p.join(metadata.parent.path, outputFile));
            if (apkFile.existsSync() && apkFile.lengthSync() > 0) {
              final isStale = isApkStale(projectRoot, apkFile);
              return AndroidApkInfo(
                path: apkFile.path,
                fileName: p.basename(apkFile.path),
                sizeBytes: apkFile.lengthSync(),
                lastModified: apkFile.lastModifiedSync(),
                isStale: isStale,
                versionCode: elem['versionCode'] is int ? elem['versionCode'] as int : null,
                versionName: elem['versionName']?.toString(),
              );
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    // 2. Direct directory candidates
    final candidateDirs = [
      p.join(projectRoot, 'app', 'build', 'outputs', 'apk', 'debug'),
      p.join(projectRoot, 'build', 'app', 'outputs', 'flutter-apk'),
      p.join(projectRoot, 'app', 'build', 'outputs', 'apk', 'release'),
      p.join(projectRoot, 'build', 'outputs', 'apk', 'debug'),
      p.join(projectRoot, 'app', 'build', 'outputs', 'apk'),
      projectRoot,
    ];

    final foundApks = <File>[];
    for (final dirPath in candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        final entries = dir.listSync();
        for (final entry in entries) {
          if (entry is File && entry.path.toLowerCase().endsWith('.apk')) {
            foundApks.add(entry);
          }
        }
      } catch (_) {}
    }

    if (foundApks.isEmpty) return null;

    foundApks.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final bestApk = foundApks.first;
    final isStale = isApkStale(projectRoot, bestApk);

    return AndroidApkInfo(
      path: bestApk.path,
      fileName: p.basename(bestApk.path),
      sizeBytes: bestApk.lengthSync(),
      lastModified: bestApk.lastModifiedSync(),
      isStale: isStale,
    );
  }

  /// Checks whether any source or build configuration file in [projectRoot]
  /// has been modified after the [apkFile] was created.
  bool isApkStale(String projectRoot, File apkFile) {
    if (!apkFile.existsSync()) return true;
    final apkTimestamp = apkFile.lastModifiedSync();
    final rootDir = Directory(projectRoot);
    if (!rootDir.existsSync()) return false;

    return _hasChangedFiles(rootDir, projectRoot, apkTimestamp, depth: 0, maxDepth: 7);
  }

  bool _hasChangedFiles(
    Directory currentDir,
    String projectRoot,
    DateTime cutoff, {
    required int depth,
    required int maxDepth,
  }) {
    if (depth > maxDepth) return false;

    try {
      final entities = currentDir.listSync(followLinks: false);
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (entity is Directory) {
          if (_ignoredDirectories.contains(name) || name.startsWith('.')) continue;
          if (_hasChangedFiles(entity, projectRoot, cutoff, depth: depth + 1, maxDepth: maxDepth)) {
            return true;
          }
        } else if (entity is File) {
          final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
          final isSource = _buildInputExtensions.contains(ext) ||
              name == 'gradlew' ||
              name == 'gradlew.bat' ||
              name == 'pubspec.yaml';

          if (isSource && entity.lastModifiedSync().isAfter(cutoff)) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  void _collectFilesNamed(Directory root, String targetName, List<File> result, {int depth = 0, int maxDepth = 6}) {
    if (depth > maxDepth) return;
    try {
      final entries = root.listSync(followLinks: false);
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (entry is Directory) {
          if (name == '.git' || name == '.gradle' || name == 'node_modules') continue;
          _collectFilesNamed(entry, targetName, result, depth: depth + 1, maxDepth: maxDepth);
        } else if (entry is File && name == targetName) {
          result.add(entry);
        }
      }
    } catch (_) {}
  }

  /// Parses compilation output from kotlinc, javac, AAPT2, Gradle, or Dart
  /// into structured, actionable [AndroidBuildIssue] objects.
  List<AndroidBuildIssue> parseBuildIssues(String output, String projectRoot, {int exitCode = 0}) {
    final issues = <AndroidBuildIssue>[];

    // Regex matching location lines: file.kt:42:10: error: detail
    final locationRegex = RegExp(
      r'^(.+?\.(?:kt|java|xml|gradle|kts|dart)):(\d+)(?::(\d+))?[: ]+(?:error: )?(.+)$',
      multiLine: true,
      caseSensitive: false,
    );

    for (final match in locationRegex.allMatches(output).take(15)) {
      final rawPath = match.group(1)?.trim() ?? '';
      final lineNum = int.tryParse(match.group(2) ?? '');
      final colNum = int.tryParse(match.group(3) ?? '');
      final detail = match.group(4)?.trim() ?? '';

      String relativePath = rawPath;
      if (p.isAbsolute(rawPath) && rawPath.startsWith(projectRoot)) {
        relativePath = p.relative(rawPath, from: projectRoot);
      } else if (rawPath.contains('/workspace/')) {
        relativePath = rawPath.substring(rawPath.indexOf('/workspace/') + 11);
      }

      issues.add(AndroidBuildIssue(
        severity: AndroidIssueSeverity.error,
        title: 'Ошибка исходного кода',
        detail: detail.length > 300 ? detail.substring(0, 300) : detail,
        suggestion: 'Откройте файл и исправьте строку $lineNum.',
        filePath: relativePath,
        line: lineNum,
        column: colNum,
      ));
    }

    if (issues.isNotEmpty) {
      // Deduplicate by filePath + line + detail
      final seen = <String>{};
      final unique = <AndroidBuildIssue>[];
      for (final issue in issues) {
        final key = '${issue.filePath}:${issue.line}:${issue.detail}';
        if (seen.add(key)) unique.add(issue);
      }
      return unique;
    }

    // High-level failure diagnosis
    final summary = diagnoseBuildFailure(output, exitCode);
    final lower = output.toLowerCase();

    String suggestion = 'Проверьте подробный лог сборки в терминале.';
    if (lower.contains('no space left on device')) {
      suggestion = 'Освободите память на устройстве и перезапустите сборку.';
    } else if (lower.contains('outofmemory') || lower.contains('java heap space')) {
      suggestion = 'Gradle исчерпал память. Запустите сборку с параметрами: --no-daemon --max-workers=2.';
    } else if (lower.contains('could not resolve') || lower.contains('could not get resource')) {
      suggestion = 'Не удалось загрузить зависимость. Проверьте подключение к интернету или репозитории в build.gradle.';
    } else if (lower.contains('manifest merger failed')) {
      suggestion = 'Конфликт манифестов AndroidManifest.xml. Проверьте дубликаты атрибутов или пакетов.';
    } else if (lower.contains('aapt2') || lower.contains('resource linking failed')) {
      suggestion = 'Ошибка ресурсов XML / AAPT2. Проверьте названия файлов в res/ и синтаксис XML.';
    } else if (lower.contains('minimum supported gradle version') || lower.contains('incompatible')) {
      suggestion = 'Несовместимость версии Gradle и Android Gradle Plugin (AGP).';
    } else if (lower.contains('gen_snapshot') || lower.contains('android_aot_release')) {
      suggestion = 'В Linux aarch64 (на телефоне) доступна только целевая архитектура android-arm64. Запустите: flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons';
    }

    return [
      AndroidBuildIssue(
        severity: AndroidIssueSeverity.error,
        title: 'Сборка не удалась',
        detail: summary,
        suggestion: suggestion,
      ),
    ];
  }

  /// Diagnoses the high-level root cause of a failed Gradle/Android build.
  String diagnoseBuildFailure(String output, int exitCode) {
    final lower = output.toLowerCase();
    if (lower.contains('no space left on device')) {
      return 'На устройстве недостаточно свободного места для завершения сборки.';
    }
    if (lower.contains('outofmemoryerror') || lower.contains('java heap space')) {
      return 'Gradle аварийно завершился из-за нехватки оперативной памяти (OOM).';
    }
    if (lower.contains('could not resolve') || lower.contains('could not get resource')) {
      return 'Зависимость проекта недоступна. Требуется интернет-соединение или локальный кэш.';
    }
    if (lower.contains('manifest merger failed')) {
      return 'Слияние AndroidManifest.xml завершилось с ошибкой из-за конфликта деклараций.';
    }
    if (lower.contains('aapt2') || lower.contains('android resource linking failed')) {
      return 'Не удалось скомпилировать Android-ресурсы (ошибка линковщика AAPT2).';
    }
    if (lower.contains('compilation error') || lower.contains('compilation failed') || lower.contains('unresolved reference')) {
      return 'Сбой компиляции Kotlin/Java/Dart исходников.';
    }
    if (lower.contains('minimum supported gradle version') || lower.contains('maximum supported gradle')) {
      return 'Версии Gradle и Android Gradle Plugin в проекте несовместимы.';
    }
    if (lower.contains('gen_snapshot') || lower.contains('android_aot_release')) {
      return 'В Linux ARM64 отсутствует AOT компилятор gen_snapshot для 32-bit ARM/x86. Требуется флаг --target-platform android-arm64.';
    }
    return exitCode != 0
        ? 'Сборка Gradle завершилась с ошибкой (код $exitCode).'
        : 'Произошла ошибка сборки.';
  }
}
