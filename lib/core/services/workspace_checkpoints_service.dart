import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/diff_service.dart';

enum ChangeType { added, modified, deleted }

class WorkspaceChangeItem {
  final String relativePath;
  final ChangeType type;
  final String? oldContent;
  final String? newContent;
  final List<DiffMarker> diffMarkers;

  const WorkspaceChangeItem({
    required this.relativePath,
    required this.type,
    this.oldContent,
    this.newContent,
    this.diffMarkers = const [],
  });

  Map<String, dynamic> toJson() => {
        'relativePath': relativePath,
        'type': type.name,
      };
}

final workspaceCheckpointsServiceProvider = Provider<WorkspaceCheckpointsService>((ref) {
  return WorkspaceCheckpointsService();
});

class WorkspaceCheckpointsService {
  static const Set<String> _ignoredDirectories = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.gradle',
    '.idea',
    '.vscode',
    '.quantum',
    '.cache',
    'dist',
    '.flutter-plugins-dependencies',
    '.metadata',
  };

  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB max per file

  Directory _getCheckpointBaseDir(String workspacePath, String projectId) {
    return Directory(p.join(workspacePath, '.quantum', 'checkpoints', projectId, 'latest'));
  }

  Directory _getBackupDir(String workspacePath, String projectId) {
    return Directory(p.join(_getCheckpointBaseDir(workspacePath, projectId).path, 'project'));
  }

  File _getChangesManifest(String workspacePath, String projectId) {
    return File(p.join(_getCheckpointBaseDir(workspacePath, projectId).path, 'changes.json'));
  }

  bool _isIgnored(String relativePath) {
    final parts = p.split(relativePath);
    for (final part in parts) {
      if (_ignoredDirectories.contains(part)) return true;
    }
    return false;
  }

  /// Creates a baseline snapshot of the workspace before an agent action runs.
  Future<void> createCheckpoint(String projectId, String workspacePath) async {
    final wsDir = Directory(workspacePath);
    if (!wsDir.existsSync()) return;

    final baseDir = _getCheckpointBaseDir(workspacePath, projectId);
    final backupDir = _getBackupDir(workspacePath, projectId);
    final manifest = _getChangesManifest(workspacePath, projectId);

    // If a previous checkpoint has pending unaccepted changes, preserve it
    if (backupDir.existsSync() && manifest.existsSync()) {
      debugPrint('WorkspaceCheckpoints: Retaining existing unaccepted checkpoint for $projectId');
      return;
    }

    if (baseDir.existsSync()) {
      try {
        baseDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    backupDir.createSync(recursive: true);

    debugPrint('WorkspaceCheckpoints: Creating baseline snapshot for $projectId at ${backupDir.path}');

    try {
      final entities = wsDir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is! File) continue;

        final rel = p.relative(entity.path, from: workspacePath);
        if (_isIgnored(rel)) continue;

        // Skip massive files
        try {
          if (entity.lengthSync() > _maxFileSizeBytes) continue;
        } catch (_) {
          continue;
        }

        final target = File(p.join(backupDir.path, rel));
        target.parent.createSync(recursive: true);
        try {
          entity.copySync(target.path);
        } catch (e) {
          debugPrint('WorkspaceCheckpoints: Failed to copy $rel: $e');
        }
      }
    } catch (e) {
      debugPrint('WorkspaceCheckpoints: Snapshot error: $e');
    }
  }

  /// Calculates all additions, modifications, and deletions comparing the workspace
  /// to the checkpoint snapshot.
  Future<List<WorkspaceChangeItem>> calculateChanges(String projectId, String workspacePath) async {
    final backupDir = _getBackupDir(workspacePath, projectId);
    if (!backupDir.existsSync()) return [];

    final wsDir = Directory(workspacePath);
    if (!wsDir.existsSync()) return [];

    final diffService = DiffService();
    final changes = <WorkspaceChangeItem>[];

    // Collect all relative paths in backup
    final backupFiles = <String, File>{};
    for (final f in backupDir.listSync(recursive: true, followLinks: false)) {
      if (f is File) {
        final rel = p.relative(f.path, from: backupDir.path);
        backupFiles[rel] = f;
      }
    }

    // Collect all relative paths in current workspace
    final currentFiles = <String, File>{};
    for (final f in wsDir.listSync(recursive: true, followLinks: false)) {
      if (f is File) {
        final rel = p.relative(f.path, from: workspacePath);
        if (!_isIgnored(rel)) {
          currentFiles[rel] = f;
        }
      }
    }

    // 1. Check for Modified & Added files
    for (final entry in currentFiles.entries) {
      final rel = entry.key;
      final curFile = entry.value;

      if (!backupFiles.containsKey(rel)) {
        // Added file
        String? newContent;
        try {
          newContent = await curFile.readAsString();
        } catch (_) {}

        changes.add(WorkspaceChangeItem(
          relativePath: rel,
          type: ChangeType.added,
          newContent: newContent,
        ));
      } else {
        // Might be modified
        final bakFile = backupFiles[rel]!;
        try {
          if (curFile.lengthSync() != bakFile.lengthSync()) {
            final oldContent = await bakFile.readAsString();
            final newContent = await curFile.readAsString();
            final markers = await diffService.calculateDiff(oldContent, newContent);

            changes.add(WorkspaceChangeItem(
              relativePath: rel,
              type: ChangeType.modified,
              oldContent: oldContent,
              newContent: newContent,
              diffMarkers: markers,
            ));
          } else {
            // Check content if same length
            final oldBytes = await bakFile.readAsBytes();
            final newBytes = await curFile.readAsBytes();
            if (!listEquals(oldBytes, newBytes)) {
              final oldContent = utf8.decode(oldBytes, allowMalformed: true);
              final newContent = utf8.decode(newBytes, allowMalformed: true);
              final markers = await diffService.calculateDiff(oldContent, newContent);

              changes.add(WorkspaceChangeItem(
                relativePath: rel,
                type: ChangeType.modified,
                oldContent: oldContent,
                newContent: newContent,
                diffMarkers: markers,
              ));
            }
          }
        } catch (_) {}
      }
    }

    // 2. Check for Deleted files
    for (final entry in backupFiles.entries) {
      final rel = entry.key;
      if (!currentFiles.containsKey(rel)) {
        String? oldContent;
        try {
          oldContent = await entry.value.readAsString();
        } catch (_) {}

        changes.add(WorkspaceChangeItem(
          relativePath: rel,
          type: ChangeType.deleted,
          oldContent: oldContent,
        ));
      }
    }

    // Save manifest
    final manifest = _getChangesManifest(workspacePath, projectId);
    try {
      manifest.parent.createSync(recursive: true);
      manifest.writeAsStringSync(jsonEncode(changes.map((c) => c.toJson()).toList()));
    } catch (_) {}

    return changes;
  }

  /// Reverts a single file back to the checkpoint state.
  Future<void> undoFile(String projectId, String workspacePath, String relativePath) async {
    final backupDir = _getBackupDir(workspacePath, projectId);
    final bakFile = File(p.join(backupDir.path, relativePath));
    final wsFile = File(p.join(workspacePath, relativePath));

    if (bakFile.existsSync()) {
      wsFile.parent.createSync(recursive: true);
      bakFile.copySync(wsFile.path);
    } else {
      // Was newly added, delete it
      if (wsFile.existsSync()) {
        wsFile.deleteSync();
      }
    }

    await _removeChangeFromManifest(workspacePath, projectId, relativePath);
  }

  /// Accepts a changed file, removing it from the pending checkpoint list.
  Future<void> keepFile(String projectId, String workspacePath, String relativePath) async {
    final backupDir = _getBackupDir(workspacePath, projectId);
    final bakFile = File(p.join(backupDir.path, relativePath));
    final wsFile = File(p.join(workspacePath, relativePath));

    // Update backup with current accepted state
    if (wsFile.existsSync()) {
      bakFile.parent.createSync(recursive: true);
      wsFile.copySync(bakFile.path);
    } else if (bakFile.existsSync()) {
      bakFile.deleteSync();
    }

    await _removeChangeFromManifest(workspacePath, projectId, relativePath);
  }

  /// Reverts all files back to checkpoint.
  Future<void> undoAll(String projectId, String workspacePath) async {
    final changes = await calculateChanges(projectId, workspacePath);
    for (final change in changes) {
      await undoFile(projectId, workspacePath, change.relativePath);
    }
    final baseDir = _getCheckpointBaseDir(workspacePath, projectId);
    if (baseDir.existsSync()) {
      try {
        baseDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Accepts all changes and clears checkpoint.
  Future<void> keepAll(String projectId, String workspacePath) async {
    final baseDir = _getCheckpointBaseDir(workspacePath, projectId);
    if (baseDir.existsSync()) {
      try {
        baseDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> _removeChangeFromManifest(String workspacePath, String projectId, String relativePath) async {
    final manifest = _getChangesManifest(workspacePath, projectId);
    if (!manifest.existsSync()) return;
    try {
      final list = jsonDecode(manifest.readAsStringSync()) as List? ?? [];
      final remaining = list.where((item) => item['relativePath'] != relativePath).toList();
      if (remaining.isEmpty) {
        final baseDir = _getCheckpointBaseDir(workspacePath, projectId);
        if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
      } else {
        manifest.writeAsStringSync(jsonEncode(remaining));
      }
    } catch (_) {}
  }
}
