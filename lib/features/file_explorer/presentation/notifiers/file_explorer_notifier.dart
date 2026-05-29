import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/features/file_explorer/domain/file_node.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

class FileExplorerState {
  final String currentPath;
  final AsyncValue<List<FileNode>> files;

  FileExplorerState({
    required this.currentPath,
    this.files = const AsyncValue.loading(),
  });

  FileExplorerState copyWith({
    String? currentPath,
    AsyncValue<List<FileNode>>? files,
  }) {
    return FileExplorerState(
      currentPath: currentPath ?? this.currentPath,
      files: files ?? this.files,
    );
  }
}

class FileExplorerNotifier extends StateNotifier<FileExplorerState> {
  final Ref _ref;
  FileExplorerNotifier(this._ref, String initialPath) : super(FileExplorerState(currentPath: initialPath)) {
    scanDirectory(initialPath);
    
    // React to sort mode changes reactively
    _ref.listen<FileSortMode>(fileSortModeProvider, (previous, next) {
      if (state.currentPath.isNotEmpty) {
        scanDirectory(state.currentPath);
      }
    });
  }

  Future<void> scanDirectory(String path) async {
    if (path.isEmpty) {
      state = state.copyWith(files: const AsyncValue.data([]));
      return;
    }
    
    state = state.copyWith(files: const AsyncValue.loading(), currentPath: path);
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        state = state.copyWith(files: AsyncValue.error('Directory does not exist: $path', StackTrace.current));
        return;
      }

      final List<FileSystemEntity> entities = [];
      await for (final entity in dir.list()) {
        entities.add(entity);
      }
      
      final nodes = entities.map((e) => FileNode.fromEntity(e)).toList();
      
      final sortMode = _ref.read(fileSortModeProvider);
      nodes.sort((a, b) {
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        switch (sortMode) {
          case FileSortMode.size:
            return b.size.compareTo(a.size);
          case FileSortMode.date:
            return b.modified.compareTo(a.modified);
          case FileSortMode.name:
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        }
      });

      state = state.copyWith(files: AsyncValue.data(nodes));
    } catch (e, stack) {
      state = state.copyWith(files: AsyncValue.error('Failed to list directory: $e', stack));
    }
  }

  void navigateTo(String path) {
    scanDirectory(path);
  }

  void goUp() {
    final parent = Directory(state.currentPath).parent.path;
    scanDirectory(parent);
  }

  Future<void> deleteEntity(String path) async {
    try {
      final entity = FileSystemEntity.typeSync(path) == FileSystemEntityType.directory 
          ? Directory(path) 
          : File(path);
      await entity.delete(recursive: true);
      
      // Mirror deletion
      await _ref.read(projectServiceProvider.notifier).mirrorDelete(path);

      await scanDirectory(state.currentPath);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> renameEntity(String oldPath, String newName) async {
    try {
      final parentDir = Directory(oldPath).parent.path;
      final newPath = p.join(parentDir, newName);
      final entity = FileSystemEntity.typeSync(oldPath) == FileSystemEntityType.directory 
          ? Directory(oldPath) 
          : File(oldPath);
      await entity.rename(newPath);

      // Mirror rename (delete old, mirror new)
      await _ref.read(projectServiceProvider.notifier).mirrorDelete(oldPath);
      await _ref.read(projectServiceProvider.notifier).mirrorEntity(newPath);

      await scanDirectory(state.currentPath);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> compressToZip(List<String> paths, String zipName) async {
    try {
      final zipFilePath = p.join(state.currentPath, zipName.endsWith('.zip') ? zipName : '$zipName.zip');
      final encoder = ZipFileEncoder();
      encoder.create(zipFilePath);
      
      for (final path in paths) {
        final file = File(path);
        if (await file.exists()) {
          await encoder.addFile(file);
        } else {
          final dir = Directory(path);
          if (await dir.exists()) {
            await encoder.addDirectory(dir);
          }
        }
      }
      encoder.close();
      
      await _ref.read(projectServiceProvider.notifier).mirrorEntity(zipFilePath);
      await scanDirectory(state.currentPath);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> extractZip(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      
      for (final file in archive) {
        final filename = file.name;
        final destPath = p.join(state.currentPath, filename);
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(destPath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
          await _ref.read(projectServiceProvider.notifier).mirrorEntity(destPath);
        } else {
          final outDir = Directory(destPath);
          await outDir.create(recursive: true);
          await _ref.read(projectServiceProvider.notifier).mirrorEntity(destPath);
        }
      }
      
      await scanDirectory(state.currentPath);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMultipleEntities(List<String> paths) async {
    try {
      for (final path in paths) {
        final isDir = FileSystemEntity.typeSync(path) == FileSystemEntityType.directory;
        if (isDir) {
          await Directory(path).delete(recursive: true);
        } else {
          await File(path).delete();
        }
        await _ref.read(projectServiceProvider.notifier).mirrorDelete(path);
      }
      await scanDirectory(state.currentPath);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> moveEntity(String oldPath, String targetDir) async {
    try {
      final fileName = p.basename(oldPath);
      final newPath = p.join(targetDir, fileName);
      if (oldPath == newPath) return; // same path

      final isDir = FileSystemEntity.typeSync(oldPath) == FileSystemEntityType.directory;
      if (isDir) {
        await Directory(oldPath).rename(newPath);
      } else {
        await File(oldPath).rename(newPath);
      }

      await _ref.read(projectServiceProvider.notifier).mirrorDelete(oldPath);
      await _ref.read(projectServiceProvider.notifier).mirrorEntity(newPath);
      
      await scanDirectory(state.currentPath);
    } catch (e) {
      rethrow;
    }
  }
}

final fileExplorerProvider = StateNotifierProvider<FileExplorerNotifier, FileExplorerState>((ref) {
  final workspace = ref.watch(workspaceProvider);
  final initialPath = workspace.currentPath ?? '';
  return FileExplorerNotifier(ref, initialPath);
});
