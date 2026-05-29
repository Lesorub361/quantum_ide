import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/project_model.dart';

/// Определяет тип проекта по содержимому директории.
class ProjectDetector {
  /// Анализирует директорию [path] и возвращает [ProjectType].
  static Future<ProjectType> detect(String path) async {
    if (path.isEmpty) return ProjectType.other;

    // Flutter / Dart
    if (await File(p.join(path, 'pubspec.yaml')).exists()) {
      final pubspec = await File(p.join(path, 'pubspec.yaml')).readAsString();
      if (pubspec.contains('flutter:')) return ProjectType.flutter;
      return ProjectType.dart;
    }

    // Node.js
    if (await File(p.join(path, 'package.json')).exists()) {
      return ProjectType.nodejs;
    }

    // Python
    if (await File(p.join(path, 'main.py')).exists() ||
        await File(p.join(path, 'app.py')).exists() ||
        await File(p.join(path, 'manage.py')).exists() ||
        await File(p.join(path, 'requirements.txt')).exists()) {
      return ProjectType.python;
    }

    // Web (HTML)
    if (await File(p.join(path, 'index.html')).exists() ||
        await File(p.join(path, 'index.htm')).exists()) {
      return ProjectType.web;
    }

    // Shell
    if (await File(p.join(path, 'main.sh')).exists() ||
        await File(p.join(path, 'run.sh')).exists()) {
      return ProjectType.shell;
    }

    // Android Java / Kotlin
    if (await File(p.join(path, 'build.gradle')).exists() ||
        await File(p.join(path, 'build.gradle.kts')).exists()) {
      final mainDir = Directory(p.join(path, 'app', 'src', 'main'));
      if (await mainDir.exists()) {
        final kotlinDir = Directory(p.join(mainDir.path, 'kotlin'));
        if (await kotlinDir.exists()) return ProjectType.androidKotlin;
        final javaDir = Directory(p.join(mainDir.path, 'java'));
        if (await javaDir.exists()) {
          bool hasKotlin = false;
          try {
            await for (final entity in javaDir.list(recursive: true)) {
              if (entity is File && entity.path.endsWith('.kt')) {
                hasKotlin = true;
                break;
              }
            }
          } catch (_) {}
          if (hasKotlin) return ProjectType.androidKotlin;
          return ProjectType.androidJava;
        }
      }
      return ProjectType.androidKotlin;
    }

    // Rust
    if (await File(p.join(path, 'Cargo.toml')).exists()) {
      return ProjectType.other;
    }

    return ProjectType.other;
  }

  /// Возвращает конфигурацию запуска для типа проекта.
  static RunConfig runConfig(ProjectType type, String guestPath) {
    switch (type) {
      case ProjectType.flutter:
        return RunConfig(
          label: 'Flutter Run (web)',
          command: 'cd "$guestPath" && flutter run -d web-server --web-port 8080',
          port: 8080,
          supportsPreview: true,
          icon: '🐦',
          color: 0xFF027DFD,
          extraCommands: [
            RunCommand('Build APK', 'cd "$guestPath" && flutter build apk --release'),
            RunCommand('Flutter Test', 'cd "$guestPath" && flutter test'),
            RunCommand('Pub Get', 'cd "$guestPath" && flutter pub get'),
          ],
        );
      case ProjectType.dart:
        return RunConfig(
          label: 'Dart Run',
          command: 'cd "$guestPath" && dart bin/main.dart',
          port: null,
          supportsPreview: false,
          icon: '🎯',
          color: 0xFF00B4AB,
          extraCommands: [
            RunCommand('Dart Compile', 'cd "$guestPath" && dart compile exe bin/main.dart'),
            RunCommand('Dart Test', 'cd "$guestPath" && dart test'),
          ],
        );
      case ProjectType.python:
        return RunConfig(
          label: 'Python Run',
          command: 'cd "$guestPath" && python3 main.py',
          port: null,
          supportsPreview: false,
          icon: '🐍',
          color: 0xFF3776AB,
          extraCommands: [
            RunCommand('Flask Dev Server', 'cd "$guestPath" && python3 -m flask run --port 5000'),
            RunCommand('Django Dev Server', 'cd "$guestPath" && python3 manage.py runserver 8000'),
            RunCommand('HTTP Server', 'cd "$guestPath" && python3 -m http.server 8080'),
            RunCommand('Install deps', 'cd "$guestPath" && pip3 install -r requirements.txt'),
          ],
        );
      case ProjectType.nodejs:
        return RunConfig(
          label: 'Node.js Run',
          command: 'cd "$guestPath" && node index.js',
          port: 3000,
          supportsPreview: false,
          icon: '🟩',
          color: 0xFF339933,
          extraCommands: [
            RunCommand('npm start', 'cd "$guestPath" && npm start'),
            RunCommand('npm install', 'cd "$guestPath" && npm install'),
            RunCommand('npm run dev', 'cd "$guestPath" && npm run dev'),
          ],
        );
      case ProjectType.web:
        return RunConfig(
          label: 'Web Server',
          command: 'cd "$guestPath" && python3 -m http.server 8080',
          port: 8080,
          supportsPreview: true,
          icon: '🌐',
          color: 0xFFE34F26,
          extraCommands: [
            RunCommand('Live Reload (npx)', 'cd "$guestPath" && npx live-server --port=8080'),
          ],
        );
      case ProjectType.shell:
        return RunConfig(
          label: 'Shell Script',
          command: 'cd "$guestPath" && chmod +x main.sh && ./main.sh',
          port: null,
          supportsPreview: false,
          icon: '🔧',
          color: 0xFF4EAA25,
          extraCommands: [],
        );
      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        return RunConfig(
          label: 'Gradle Build (Debug APK)',
          command: 'cd "$guestPath" && chmod +x gradlew && ./gradlew assembleDebug',
          port: null,
          supportsPreview: false,
          icon: '🤖',
          color: 0xFF3DDC84,
          extraCommands: [
            RunCommand('Install Debug APK', 'cd "$guestPath" && chmod +x gradlew && ./gradlew installDebug'),
            RunCommand('Clean Project', 'cd "$guestPath" && chmod +x gradlew && ./gradlew clean'),
            RunCommand('Build Release APK', 'cd "$guestPath" && chmod +x gradlew && ./gradlew assembleRelease'),
          ],
        );
      default:
        return RunConfig(
          label: 'List Files',
          command: 'cd "$guestPath" && ls -la',
          port: null,
          supportsPreview: false,
          icon: '📁',
          color: 0xFF607D8B,
          extraCommands: [],
        );
    }
  }

  static String typeLabel(ProjectType type) {
    switch (type) {
      case ProjectType.flutter: return 'Flutter';
      case ProjectType.dart:    return 'Dart';
      case ProjectType.python:  return 'Python';
      case ProjectType.nodejs:  return 'Node.js';
      case ProjectType.web:     return 'HTML/CSS/JS';
      case ProjectType.shell:   return 'Shell';
      case ProjectType.androidJava:   return 'Android (Java)';
      case ProjectType.androidKotlin: return 'Android (Kotlin)';
      default:                  return 'Other';
    }
  }
}

class RunConfig {
  final String label;
  final String command;
  final int? port;
  final bool supportsPreview;
  final String icon;
  final int color;
  final List<RunCommand> extraCommands;

  const RunConfig({
    required this.label,
    required this.command,
    required this.port,
    required this.supportsPreview,
    required this.icon,
    required this.color,
    required this.extraCommands,
  });
}

class RunCommand {
  final String label;
  final String command;
  const RunCommand(this.label, this.command);
}
