import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:watcher/watcher.dart';

/// Watches the active workspace directory for external file/build changes
/// (e.g. APKs compiled in terminal) and refreshes the File Explorer tree.
final workspaceWatcherProvider = Provider.autoDispose<void>((ref) {
  if (kIsWeb) return;
  final workspacePath = ref.watch(
    workspaceProvider.select((w) => w.currentPath),
  );
  if (workspacePath == null || workspacePath.trim().isEmpty) return;
  final dir = Directory(workspacePath);
  if (!dir.existsSync()) return;

  StreamSubscription<WatchEvent>? sub;
  Timer? debounce;

  try {
    final watcher = DirectoryWatcher(workspacePath);
    sub = watcher.events.listen(
      (event) {
        final path = event.path;
        if (path.contains('/.git/') ||
            path.contains('\\.git\\') ||
            path.contains('/.dart_tool/') ||
            path.contains('\\.dart_tool\\') ||
            path.contains('/node_modules/') ||
            path.contains('\\node_modules\\')) {
          return;
        }
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 450), () {
          try {
            ref.read(fileTreeRefreshProvider.notifier).state++;
            ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
          } catch (_) {}
        });
      },
      onError: (_) {},
    );
  } catch (_) {}

  ref.onDispose(() {
    debounce?.cancel();
    sub?.cancel();
  });
});
