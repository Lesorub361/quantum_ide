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

  /// Default visible directory on Desktop (Linux/Windows/macOS) where new projects
  /// are created by default so they are immediately visible in the OS file manager.
  static String get defaultDesktopProjectsDir {
    final home = userHomeDir;
    // Prefer /persistent/home/<user> if present on persistent Linux setups
    if (!kIsWeb && Platform.isLinux && home.startsWith('/home/')) {
      final persistentHome = '/persistent$home';
      if (Directory(persistentHome).existsSync()) {
        return p.join(persistentHome, 'QuantumIDEProjects');
      }
    }
    return p.join(home, 'QuantumIDEProjects');
  }

  /// Returns all candidate home directories for the current desktop user
  /// (including resolved symlinks and `/persistent/home/<user>` on Linux).
  static List<String> get candidateHomeDirs {
    if (kIsWeb) return const [];
    final primary = userHomeDir;
    final homes = <String>{if (primary.isNotEmpty) primary};
    try {
      if (primary.isNotEmpty && Directory(primary).existsSync()) {
        final resolved = Directory(primary).resolveSymbolicLinksSync();
        if (resolved.isNotEmpty) homes.add(resolved);
      }
    } catch (_) {}
    if (Platform.isLinux && primary.startsWith('/home/')) {
      final persistentHome = '/persistent$primary';
      if (Directory(persistentHome).existsSync()) {
        homes.add(persistentHome);
      }
    }
    return homes.toList();
  }

  /// Opens [dirPath] in the native desktop file manager (Nautilus/Dolphin/Explorer/Finder).
  static Future<bool> openInFileManager(String dirPath) async {
    if (!isDesktop) return false;
    try {
      final target = Directory(dirPath).existsSync()
          ? dirPath
          : p.dirname(dirPath);
      if (Platform.isLinux) {
        await Process.start('xdg-open', [target], mode: ProcessStartMode.detached);
        return true;
      } else if (Platform.isMacOS) {
        await Process.start('open', [target], mode: ProcessStartMode.detached);
        return true;
      } else if (Platform.isWindows) {
        await Process.start('explorer', [target], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// List of common directories where developer CLI tools and language servers are installed.
  static List<String> get commonBinaryDirs {
    if (kIsWeb) return const [];
    final home = userHomeDir;
    final List<String> dirs = [];

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';

      if (appData.isNotEmpty) dirs.add(p.join(appData, 'npm'));
      if (localAppData.isNotEmpty) {
        dirs.add(p.join(localAppData, 'Programs'));
        dirs.add(p.join(localAppData, 'Programs', 'Python'));
        dirs.add(p.join(localAppData, 'Pub', 'Cache', 'bin'));
      }
      dirs.add(p.join(home, '.cargo', 'bin'));
      dirs.add(p.join(home, '.agy', 'bin'));
      dirs.add(p.join(programFiles, 'nodejs'));
      dirs.add(p.join(programFiles, 'Git', 'bin'));
      dirs.add(p.join(programFiles, 'Git', 'usr', 'bin'));
    } else {
      // Linux & macOS
      dirs.addAll([
        '/usr/local/sbin',
        '/usr/local/bin',
        '/usr/sbin',
        '/usr/bin',
        '/sbin',
        '/bin',
        '/snap/bin',
        '/var/lib/flatpak/exports/bin',
        '/opt/homebrew/bin',
        '/opt/homebrew/sbin',
        '/opt/flutter/bin',
        '/opt/antigravity/bin',
        '/opt/agy/bin',
      ]);
      for (final h in candidateHomeDirs) {
        dirs.addAll([
          p.join(h, '.local', 'bin'),
          p.join(h, 'bin'),
          p.join(h, '.agy', 'bin'),
          p.join(h, '.antigravity', 'bin'),
          p.join(h, '.gemini', 'antigravity', 'bin'),
          p.join(h, '.gemini', 'bin'),
          p.join(h, '.npm-global', 'bin'),
          p.join(h, '.yarn', 'bin'),
          p.join(h, '.local', 'share', 'pnpm'),
          p.join(h, '.cargo', 'bin'),
          p.join(h, 'go', 'bin'),
          p.join(h, '.pub-cache', 'bin'),
          p.join(h, 'flutter', 'bin'),
          p.join(h, 'development', 'flutter', 'bin'),
          p.join(h, '.fvm', 'default', 'bin'),
          p.join(h, '.local', 'share', 'flatpak', 'exports', 'bin'),
        ]);
      }
    }
    return dirs;
  }
}
