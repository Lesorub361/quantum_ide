import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/github_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class GitService {
  final Ref ref;

  GitService(this.ref);

  static final Map<String, bool> _repoCache = {};
  static GitStatus? _cachedStatus;
  static String? _cachedPath;
  static DateTime? _lastStatusTime;
  static const Duration _statusCacheTtl = Duration(seconds: 3);

  Future<String> _getGuestPath(String hostPath) async {
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  Future<GitStatus?> getStatus() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return null;

    if (_cachedStatus != null && _cachedPath == hostPath && _lastStatusTime != null && DateTime.now().difference(_lastStatusTime!) < _statusCacheTtl) {
      return _cachedStatus;
    }

    final guestPath = await _getGuestPath(hostPath);
    
    try {
      final runtime = ref.read(runtimeServiceProvider);
      
      final isRepoKey = '$hostPath|$guestPath';
      if (!_repoCache.containsKey(isRepoKey)) {
        final isRepo = await runtime.runCommand('cd "$guestPath" && git rev-parse --is-inside-work-tree 2>/dev/null')
            .then((value) => value.trim() == 'true')
            .catchError((_) => false);
        _repoCache[isRepoKey] = isRepo;
      }
          
      if (!_repoCache[isRepoKey]!) return null;

      String branch = 'main';
      try {
        final b = await runtime.runCommand('cd "$guestPath" && git rev-parse --abbrev-ref HEAD 2>/dev/null');
        if (b.trim().isNotEmpty) branch = b.trim();
      } catch (_) {
        branch = 'main';
      }

      String output = '';
      try {
        output = await runtime.runCommand('cd "$guestPath" && git status --porcelain');
      } catch (_) {
        output = '';
      }
      
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
          staged.add(file);
          modified.add(file);
        }
      }

      final result = GitStatus(
        modifiedFiles: modified,
        stagedFiles: staged,
        untrackedFiles: untracked,
        conflictedFiles: conflicted,
        currentBranch: branch,
      );
      _cachedStatus = result;
      _cachedPath = hostPath;
      _lastStatusTime = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('Git Status failed: $e');
      return null;
    }
  }

  void invalidateCache() {
    _cachedStatus = null;
    _cachedPath = null;
    _lastStatusTime = null;
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
      invalidateCache();
    } catch (e) {
      if (e.toString().contains('unable to write file') || e.toString().contains('No such file or directory') || e.toString().contains('fatal')) {
        debugPrint('Git structure error, attempting aggressive repair...');
        await runtime.runCommand('cd "$guestPath" && mkdir -p .git/objects && git init');
        await runtime.runCommand('cd "$guestPath" && git config --global --add safe.directory "*"');
        await runtime.runCommand('cd "$guestPath" && git add "$filePath"');
        invalidateCache();
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
    invalidateCache();
  }

  Future<void> commit(String message) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git commit -m "$message"');
    invalidateCache();
  }

  Future<void> push() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    final token = GitHubService().token;
    final authPrefix = token != null && token.isNotEmpty
        ? ' -c "url.https://$token@github.com/.insteadOf=https://github.com/"'
        : '';
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git$authPrefix push');
  }

  Future<void> pull() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    final token = GitHubService().token;
    final authPrefix = token != null && token.isNotEmpty
        ? ' -c "url.https://$token@github.com/.insteadOf=https://github.com/"'
        : '';
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git$authPrefix pull');
    invalidateCache();
  }

  Future<void> initRepo() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git init');
    _repoCache.removeWhere((key, _) => key.startsWith(hostPath));
    invalidateCache();
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
      invalidateCache();
    } catch (e) {
      debugPrint('Git discard failed: $e');
    }
  }
}

final gitServiceProvider = Provider((ref) => GitService(ref));
