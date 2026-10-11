import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Cross-platform utility helper for filesystem paths, shells, and OS abstractions.
class PlatformUtils {
  /// Returns the user's home directory across Windows, macOS, Linux, and mobile.
  static String get userHomeDir {
    if (kIsWeb) return '';
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ??
          Platform.environment['APPDATA'] ??
          Directory.current.path;
    }
    return Platform.environment['HOME'] ?? Directory.current.path;
  }

  /// Whether current platform is a desktop operating system (Windows, Linux, macOS).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  /// Whether current platform is a mobile operating system (Android, iOS).
  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Default interactive shell command name or binary path for the platform.
  static String get defaultShell {
    if (kIsWeb) return 'sh';
    if (Platform.isAndroid) return '/system/bin/sh';
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? 'bash';
  }

  /// Command for looking up binary paths on the platform ('where' on Windows, 'which' on Unix).
  static String get whichCommand =>
      (!kIsWeb && Platform.isWindows) ? 'where' : 'which';

  /// Standard application data directory for Quantum IDE settings and runtime files.
  static String get desktopDataDir {
    final home = userHomeDir;
    return p.join(home, '.quantum_ide');
  }

  /// List of common directories where developer CLI tools and language servers are installed.
  static List<String> get commonBinaryDirs {
    if (kIsWeb) return const [];
    final home = userHomeDir;
    final List<String> dirs = [];

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      
      if (appData.isNotEmpty) dirs.add(p.join(appData, 'npm'));
      if (localAppData.isNotEmpty) {
        dirs.add(p.join(localAppData, 'Programs'));
        dirs.add(p.join(localAppData, 'Programs', 'Python'));
      }
      dirs.add(p.join(home, '.cargo', 'bin'));
      dirs.add(p.join(programFiles, 'nodejs'));
      dirs.add(p.join(programFiles, 'Git', 'bin'));
      dirs.add(p.join(programFiles, 'Git', 'usr', 'bin'));
    } else {
      // Linux & macOS
      dirs.addAll([
        '/usr/local/bin',
        '/usr/bin',
        '/bin',
        '/opt/homebrew/bin',
        '/opt/homebrew/sbin',
        p.join(home, '.local', 'bin'),
        p.join(home, '.cargo', 'bin'),
        p.join(home, 'bin'),
        p.join(home, 'flutter', 'bin'),
      ]);
    }
    return dirs;
  }
}
