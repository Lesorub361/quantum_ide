import 'dart:io';

import 'package:path/path.dart' as p;

/// Pruned workspace file walker that skips heavy/generated directories
/// BEFORE descending into them, preventing OOM and UI freezes on large repos.
class WorkspaceFileWalker {
  static const Set<String> defaultIgnoredDirs = {
    '.git',
    '.gradle',
    '.dart_tool',
    '.idea',
    '.vscode',
    '.cache',
    '.cxx',
    '.pub-cache',
    '.quantum',
    'node_modules',
    'build',
    'ephemeral',
    'Pods',
    'dist',
    'target',
    '__pycache__',
    '.venv',
    'venv',
  };

  static const Set<String> binaryExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.ico',
    '.bmp',
    '.zip',
    '.tar',
    '.gz',
    '.7z',
    '.rar',
    '.apk',
    '.aab',
    '.jar',
    '.so',
    '.dll',
    '.exe',
    '.dylib',
    '.o',
    '.a',
    '.class',
    '.dex',
    '.pdf',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.mp3',
    '.mp4',
    '.wav',
    '.db',
    '.sqlite',
    '.lock',
  };

  /// Streams searchable text files under [rootPath] while pruning ignored
  /// directories before traversal and capping file count/size.
  static Stream<File> walkTextFiles(
    String rootPath, {
    int maxFiles = 15000,
    int maxFileBytes = 1024 * 1024, // 1 MB
    Set<String> ignoredDirs = defaultIgnoredDirs,
  }) async* {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    final stack = <Directory>[root];
    var yielded = 0;

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      try {
        await for (final entity in current.list(
          recursive: false,
          followLinks: false,
        )) {
          final name = p.basename(entity.path);
          if (entity is Directory) {
            if (!ignoredDirs.contains(name)) {
              stack.add(entity);
            }
            continue;
          }
          if (entity is File) {
            if (name.startsWith('.flutter-plugins')) continue;
            final ext = p.extension(name).toLowerCase();
            if (binaryExtensions.contains(ext)) continue;

            try {
              final len = await entity.length();
              if (len > maxFileBytes) continue;
            } catch (_) {
              continue;
            }

            yield entity;
            yielded++;
            if (yielded >= maxFiles) return;
          }
        }
      } catch (_) {
        // Skip unreadable directories without aborting the whole walk
      }
    }
  }
}
