import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class GitService {
  final Ref ref;

  GitService(this.ref);

  Future<String> _getGuestPath(String hostPath) async {
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  Future<GitStatus?> getStatus() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return null;

    final guestPath = await _getGuestPath(hostPath);
    
    try {
      final runtime = ref.read(runtimeServiceProvider);
      
      // Check if it's a git repo
      final isRepo = await runtime.runCommand('cd "$guestPath" && git rev-parse --is-inside-work-tree')
          .then((value) => value.trim() == 'true')
          .catchError((_) => false);
          
      if (!isRepo) return null;

      final branch = await runtime.runCommand('cd "$guestPath" && git rev-parse --abbrev-ref HEAD')
          .then((value) => value.trim())
          .catchError((_) => 'initial');

      final output = await runtime.runCommand('cd "$guestPath" && git status --porcelain');
      
      final modified = <String>[];
      final staged = <String>[];
      final untracked = <String>[];
      final conflicted = <String>[];

      for (var line in output.split('\n')) {
        if (line.isEmpty) continue;
        if (line.length < 3) continue;
        final status = line.substring(0, 2);
        final file = line.substring(3).trim();

        const conflictStatuses = {'DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'};
        if (conflictStatuses.contains(status)) {
          conflicted.add(file);
        } else if (status == '??') {
          untracked.add(file);
        } else if (status.startsWith(' ') && status[1] != ' ') {
          modified.add(file);
        } else if (status[0] != ' ' && status[1] == ' ') {
          staged.add(file);
        } else if (status[0] != ' ' && status[1] != ' ') {
          // Partially staged
          staged.add(file);
          modified.add(file);
        }
      }

      return GitStatus(
        modifiedFiles: modified,
        stagedFiles: staged,
        untrackedFiles: untracked,
        conflictedFiles: conflicted,
        currentBranch: branch,
      );
    } catch (e) {
      debugPrint('Git Status failed: $e');
      return null;
    }
  }

  Future<void> add(String filePath) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);
    
    try {
      await runtime.runCommand('cd "$guestPath" && git config --global --add safe.directory "*"');
      await runtime.runCommand('cd "$guestPath" && git add "$filePath"');
    } catch (e) {
      if (e.toString().contains('unable to write file') || e.toString().contains('No such file or directory') || e.toString().contains('fatal')) {
        debugPrint('Git structure error, attempting aggressive repair...');
        // Force create directory structure and re-init
        await runtime.runCommand('cd "$guestPath" && mkdir -p .git/objects && git init');
        await runtime.runCommand('cd "$guestPath" && git config --global --add safe.directory "*"');
        // Retry add
        await runtime.runCommand('cd "$guestPath" && git add "$filePath"');
      } else {
        rethrow;
      }
    }
  }

  Future<void> unstage(String filePath) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git reset HEAD "$filePath"');
  }

  Future<void> commit(String message) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git commit -m "$message"');
  }

  Future<void> push() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git push');
  }

  Future<void> pull() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git pull');
  }

  Future<void> initRepo() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git init');
  }

  Future<String> getFileContentFromGit(String relativePath) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);
    
    try {
      final output = await runtime.runCommand('cd "$guestPath" && git show HEAD:"$relativePath"');
      return output;
    } catch (e) {
      debugPrint('Git show failed: $e');
      return '';
    }
  }

  Future<void> discardChanges(String relativePath) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);
    
    try {
      await runtime.runCommand('cd "$guestPath" && git checkout -- "$relativePath"');
    } catch (e) {
      debugPrint('Git discard failed: $e');
    }
  }
}

final gitServiceProvider = Provider((ref) => GitService(ref));
