import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';

const _ignoredPathSegments = <String>{
  '.git',
  '.dart_tool',
  'node_modules',
  'build',
  '.gradle',
  '.pub-cache',
  'ephemeral',
  '.quantum',
};

bool _isIgnoredEventPath(String path) {
  final parts = p.split(path);
  for (final part in parts) {
    if (_ignoredPathSegments.contains(part)) return true;
  }
  return false;
}

/// Watches the active workspace root and currently viewed explorer directory
/// non-recursively so large projects (node_modules, .git, build) never exhaust
/// inotify watches or spike CPU on open.
final workspaceWatcherProvider = Provider.autoDispose<void>((ref) {
  if (kIsWeb) return;
  final workspacePath = ref.watch(
    workspaceProvider.select((w) => w.currentPath),
  );
  if (workspacePath == null || workspacePath.trim().isEmpty) return;
  final rootDir = Directory(workspacePath);
  if (!rootDir.existsSync()) return;

  final explorerPath = ref.watch(
    fileExplorerProvider.select((s) => s.currentPath),
  );

  final subscriptions = <StreamSubscription<FileSystemEvent>>[];
  Timer? debounce;

  void onFsEvent(FileSystemEvent event) {
    if (_isIgnoredEventPath(event.path)) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 1200), () {
      try {
        ref.read(fileTreeRefreshProvider.notifier).state++;
        final activeDir = ref.read(fileExplorerProvider).currentPath;
        if (activeDir.isNotEmpty && Directory(activeDir).existsSync()) {
          ref.read(fileExplorerProvider.notifier).scanDirectory(activeDir);
        }
      } catch (_) {}
    });
  }

  void attachShallowWatch(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return;
      subscriptions.add(
        dir.watch(recursive: false).listen(onFsEvent, onError: (_) {}),
      );
    } catch (_) {}
  }

  attachShallowWatch(workspacePath);
  if (explorerPath.isNotEmpty &&
      explorerPath != workspacePath &&
      p.isWithin(workspacePath, explorerPath)) {
    attachShallowWatch(explorerPath);
  }

  ref.onDispose(() {
    debounce?.cancel();
    for (final sub in subscriptions) {
      sub.cancel();
    }
  });
});
