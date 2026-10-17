import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class GitService {
  final Ref ref;

  GitService(this.ref);

  static final Map<String, bool> _repoCache = {};
  static GitStatus? _cachedStatus;
  static String? _cachedPath;
  static DateTime? _lastStatusTime;
  static const Duration _statusCacheTtl = Duration(seconds: 3);

  String? _resolveRepoHostPath() {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return null;

    final parentGit = Directory(p.join(hostPath, '.git'));
    final nested = p.join(hostPath, p.basename(hostPath));
    final nestedGit = Directory(p.join(nested, '.git'));

    if (nestedGit.existsSync()) {
      if (!parentGit.existsSync()) {
        return nested;
      }
      final parentHead = File(p.join(hostPath, '.git', 'refs', 'heads', 'main'));
      final nestedHead = File(p.join(nested, '.git', 'refs', 'heads', 'main'));
      if (!parentHead.existsSync() && nestedHead.existsSync()) {
        return nested;
      }
    }
    return hostPath;
  }

  Future<String> _getGuestPath(String hostPath) async {
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  Future<String?> _detectProjectVersion(String hostPath) async {
    try {
      final pubspec = File(p.join(hostPath, 'pubspec.yaml'));
      if (await pubspec.exists()) {
        final content = await pubspec.readAsString();
        final match = RegExp(r'^version:\s*([^\s#]+)', multiLine: true).firstMatch(content);
        if (match != null) return match.group(1)?.trim();
      }
      final pkgJson = File(p.join(hostPath, 'package.json'));
      if (await pkgJson.exists()) {
        final content = await pkgJson.readAsString();
        final match = RegExp(r'"version"\s*:\s*"([^"]+)"').firstMatch(content);
        if (match != null) return match.group(1)?.trim();
      }
      final gradleKts = File(p.join(hostPath, 'android', 'app', 'build.gradle.kts'));
      if (await gradleKts.exists()) {
        final content = await gradleKts.readAsString();
        final nameMatch = RegExp(r'versionName\s*=\s*"([^"]+)"').firstMatch(content);
        final codeMatch = RegExp(r'versionCode\s*=\s*(\d+)').firstMatch(content);
        if (nameMatch != null) {
          final vName = nameMatch.group(1);
          final vCode = codeMatch?.group(1);
          return vCode != null ? '$vName+$vCode' : vName;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<GitStatus?> getStatus({bool forceRefresh = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return null;

    if (!forceRefresh &&
        _cachedStatus != null &&
        _cachedPath == hostPath &&
        _lastStatusTime != null &&
        DateTime.now().difference(_lastStatusTime!) < _statusCacheTtl) {
      return _cachedStatus;
    }

    final guestPath = await _getGuestPath(hostPath);

    try {
      final runtime = ref.read(runtimeServiceProvider);

      // Run a single batched shell script to get repo check, branch, ahead/behind,
      // porcelain status with -uall to list all untracked files individually instead
      // of collapsing whole folders into single entries!
      final batchCmd = [
        'cd "$guestPath" 2>/dev/null || exit 0',
        'if [ "\$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then echo "__NOT_GIT_REPO__"; exit 0; fi',
        'echo "__SECTION_BRANCH__"',
        'git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "main"',
        'echo "__SECTION_AHEAD_BEHIND__"',
        '(git rev-list --left-right --count HEAD...@{u} 2>/dev/null || echo "0\t0")',
        'echo "__SECTION_STATUS__"',
        'git status --porcelain -uall 2>/dev/null',
        'echo "__SECTION_NUMSTAT__"',
        '(git diff --numstat 2>/dev/null || true; git diff --cached --numstat 2>/dev/null || true)',
        'echo "__SECTION_COMMITS__"',
        '(git log -n 35 --pretty=format:"%H\t%h\t%s\t%an\t%ar\t%D" 2>/dev/null || true)',
        'echo ""',
        'echo "__SECTION_TAGS__"',
        '(git for-each-ref --sort=-creatordate --format="%(refname:short)\t%(objectname:short)\t%(creatordate:short)\t%(contents:subject)" refs/tags 2>/dev/null | head -n 25 || true)',
        'echo "__SECTION_BRANCHES__"',
        '(git for-each-ref --format="%(refname:short)" refs/heads 2>/dev/null || true)',
        'echo "__SECTION_REMOTE__"',
        '(git config --get remote.origin.url 2>/dev/null || true)',
      ].join(' && ');

      final rawOut = await runtime.runCommand(batchCmd);
      if (rawOut.contains('__NOT_GIT_REPO__') || !rawOut.contains('__SECTION_BRANCH__')) {
        _repoCache['$hostPath|$guestPath'] = false;
        return null;
      }
      _repoCache['$hostPath|$guestPath'] = true;

      String extractSection(String startMarker, String? endMarker) {
        final startIdx = rawOut.indexOf(startMarker);
        if (startIdx == -1) return '';
        final contentStart = startIdx + startMarker.length;
        if (endMarker == null) {
          return rawOut.substring(contentStart).trim();
        }
        final endIdx = rawOut.indexOf(endMarker, contentStart);
        if (endIdx == -1) return rawOut.substring(contentStart).trim();
        return rawOut.substring(contentStart, endIdx).trim();
      }

      final branchRaw = extractSection('__SECTION_BRANCH__', '__SECTION_AHEAD_BEHIND__');
      final branch = branchRaw.split('\n').first.trim().isNotEmpty
          ? branchRaw.split('\n').first.trim()
          : 'main';

      int ahead = 0;
      int behind = 0;
      final abRaw = extractSection('__SECTION_AHEAD_BEHIND__', '__SECTION_STATUS__');
      if (abRaw.isNotEmpty) {
        final parts = abRaw.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          ahead = int.tryParse(parts[0]) ?? 0;
          behind = int.tryParse(parts[1]) ?? 0;
        }
      }

      final statusRaw = extractSection('__SECTION_STATUS__', '__SECTION_NUMSTAT__');
      final modified = <String>[];
      final staged = <String>[];
      final untracked = <String>[];
      final conflicted = <String>[];

      // Note: Do NOT trim leading spaces of statusRaw because porcelain format uses leading space!
      final statusStartIdx = rawOut.indexOf('__SECTION_STATUS__');
      final numstatStartIdx = rawOut.indexOf('__SECTION_NUMSTAT__');
      final rawStatusLines = (statusStartIdx != -1 && numstatStartIdx != -1)
          ? rawOut.substring(statusStartIdx + '__SECTION_STATUS__'.length, numstatStartIdx).split('\n')
          : statusRaw.split('\n');

      for (var line in rawStatusLines) {
        if (line.trim().isEmpty) continue;
        if (line.length < 3) continue;
        final x = line[0];
        final y = line[1];
        final status = line.substring(0, 2);
        var file = line.substring(3).trim();
        if (file.contains(' -> ')) {
          file = file.split(' -> ').last.trim();
        }
        if (file.startsWith('"') && file.endsWith('"') && file.length >= 2) {
          file = file.substring(1, file.length - 1);
        }

        const conflictStatuses = {'DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'};
        if (conflictStatuses.contains(status)) {
          final cleanRel = file.endsWith('/') ? file.substring(0, file.length - 1) : file;
          if (!conflicted.contains(cleanRel)) conflicted.add(cleanRel);
        } else if (status == '??') {
          // If file ends with '/' or is a directory on host, recursively expand it into individual files
          final fullHostPath = p.join(hostPath, file);
          final hostDir = Directory(fullHostPath);
          if (file.endsWith('/') || hostDir.existsSync()) {
            try {
              if (hostDir.existsSync()) {
                final subEntities = hostDir.listSync(recursive: true, followLinks: false);
                for (final ent in subEntities) {
                  if (ent is File) {
                    final rel = p.relative(ent.path, from: hostPath).replaceAll('\\', '/');
                    if (!untracked.contains(rel)) untracked.add(rel);
                  }
                }
                continue;
              }
            } catch (_) {}
          }
          final cleanRel = file.endsWith('/') ? file.substring(0, file.length - 1) : file;
          if (!untracked.contains(cleanRel)) untracked.add(cleanRel);
        } else {
          final cleanRel = file.endsWith('/') ? file.substring(0, file.length - 1) : file;
          if (x != ' ' && x != '?') {
            if (!staged.contains(cleanRel)) staged.add(cleanRel);
          }
          if (y != ' ' && y != '?') {
            if (!modified.contains(cleanRel)) modified.add(cleanRel);
          }
        }
      }

      final diffStats = <String, GitFileDiffStats>{};
      final numstatRaw = extractSection('__SECTION_NUMSTAT__', '__SECTION_COMMITS__');
      for (final line in numstatRaw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final add = int.tryParse(parts[0]) ?? 0;
          final del = int.tryParse(parts[1]) ?? 0;
          final file = parts.sublist(2).join(' ').trim();
          final existing = diffStats[file];
          if (existing != null) {
            diffStats[file] = GitFileDiffStats(existing.additions + add, existing.deletions + del);
          } else {
            diffStats[file] = GitFileDiffStats(add, del);
          }
        }
      }

      final recentCommits = <GitCommitEntry>[];
      final commitsRaw = extractSection('__SECTION_COMMITS__', '__SECTION_TAGS__');
      for (final line in commitsRaw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('\t');
        if (parts.length >= 5) {
          recentCommits.add(GitCommitEntry(
            hash: parts[0].trim(),
            shortHash: parts[1].trim(),
            message: parts[2].trim(),
            author: parts[3].trim(),
            relativeTime: parts[4].trim(),
            refs: parts.length >= 6 ? parts[5].trim() : '',
          ));
        }
      }

      final tags = <GitTagEntry>[];
      final tagsRaw = extractSection('__SECTION_TAGS__', '__SECTION_BRANCHES__');
      for (final line in tagsRaw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('\t');
        if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
          tags.add(GitTagEntry(
            name: parts[0].trim(),
            shortHash: parts.length > 1 ? parts[1].trim() : '',
            date: parts.length > 2 ? parts[2].trim() : '',
            subject: parts.length > 3 ? parts[3].trim() : '',
          ));
        }
      }

      final branches = <String>[];
      final branchesRaw = extractSection('__SECTION_BRANCHES__', '__SECTION_REMOTE__');
      for (final line in branchesRaw.split('\n')) {
        final b = line.trim();
        if (b.isNotEmpty && !branches.contains(b)) {
          branches.add(b);
        }
      }
      if (!branches.contains(branch)) {
        branches.insert(0, branch);
      }

      final remoteRaw = extractSection('__SECTION_REMOTE__', null);
      final remoteUrl = remoteRaw.split('\n').first.trim();

      final projectVersion = await _detectProjectVersion(hostPath);

      final result = GitStatus(
        modifiedFiles: modified,
        stagedFiles: staged,
        untrackedFiles: untracked,
        conflictedFiles: conflicted,
        currentBranch: branch,
        branches: branches,
        ahead: ahead,
        behind: behind,
        diffStats: diffStats,
        recentCommits: recentCommits,
        tags: tags,
        projectVersion: projectVersion,
        remoteUrl: remoteUrl.isNotEmpty ? remoteUrl : null,
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
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      await runtime.runCommand('cd "$guestPath" && git config --global --add safe.directory "*" && git add -A -- "$filePath"');
      invalidateCache();
    } catch (e) {
      if (e.toString().contains('unable to write file') ||
          e.toString().contains('No such file or directory') ||
          e.toString().contains('fatal')) {
        await runtime.runCommand('cd "$guestPath" && mkdir -p .git/objects && git init && git config --global --add safe.directory "*" && git add -A -- "$filePath"');
        invalidateCache();
      } else {
        rethrow;
      }
    }
  }

  Future<void> stageAll() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git add -A');
    invalidateCache();
  }

  Future<void> unstage(String filePath) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git reset HEAD "$filePath"');
    invalidateCache();
  }

  Future<void> unstageAll() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git reset HEAD');
    invalidateCache();
  }

  Future<void> commit(String message, {bool amend = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final escaped = message.replaceAll('"', '\\"');
    final amendFlag = amend ? ' --amend' : '';

    // Ensure git user.name and user.email exist so commit never fails on fresh setups
    final cmd = [
      'cd "$guestPath"',
      'git config user.name >/dev/null 2>&1 || git config user.name "Quantum Developer"',
      'git config user.email >/dev/null 2>&1 || git config user.email "dev@quantum-ide.local"',
      'git commit$amendFlag -m "$escaped"',
    ].join(' && ');

    await ref.read(runtimeServiceProvider).runCommand(cmd);
    invalidateCache();
  }

  Future<void> push() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && (git push 2>&1 || git push -u origin HEAD 2>&1)',
    );
    invalidateCache();
  }

  Future<void> createTag(String tagName, String message) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final escapedMsg = message.replaceAll('"', '\\"');

    await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git config user.name >/dev/null 2>&1 || git config user.name "Quantum Developer" && git config user.email >/dev/null 2>&1 || git config user.email "dev@quantum-ide.local" && git tag -f -a "$tagName" -m "$escapedMsg"',
    );
    invalidateCache();
  }

  Future<void> deleteTag(String tagName) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git tag -d "$tagName"');
    invalidateCache();
  }

  Future<void> pushWithTags() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && (git push || git push -u origin HEAD) && git push --tags',
    );
    invalidateCache();
  }

  Future<void> checkoutBranch(String branchName, {bool createNew = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final flag = createNew ? '-b ' : '';
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git checkout $flag"$branchName"');
    invalidateCache();
  }

  Future<String> getCommitDetails(String commitHash) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);

    try {
      return await ref.read(runtimeServiceProvider).runCommand(
        'cd "$guestPath" && git show --stat --patch --no-color "$commitHash" 2>/dev/null',
      );
    } catch (e) {
      return 'Ошибка получения деталей коммита: $e';
    }
  }

  Future<String> getFileDiff(String relativePath, {bool staged = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);

    try {
      final cachedFlag = staged ? '--cached ' : '';
      final out = await ref.read(runtimeServiceProvider).runCommand(
        'cd "$guestPath" && git diff --no-color $cachedFlag-- "$relativePath" 2>/dev/null',
      );
      if (out.trim().isNotEmpty) return out;
      return await ref.read(runtimeServiceProvider).runCommand(
        'cd "$guestPath" && git diff --no-color HEAD -- "$relativePath" 2>/dev/null',
      );
    } catch (e) {
      return '';
    }
  }

  Future<String?> getRemoteUrl() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return null;
    final guestPath = await _getGuestPath(hostPath);

    try {
      final out = await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git config --get remote.origin.url');
      return out.trim().isNotEmpty ? out.trim() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pull() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git pull --rebase=false');
    invalidateCache();
  }

  Future<void> stashSave([String? message]) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final msgPart = (message != null && message.trim().isNotEmpty)
        ? 'push -m "${message.replaceAll('"', '\\"')}" --include-untracked'
        : 'push --include-untracked';
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git stash $msgPart');
    invalidateCache();
  }

  Future<void> stashPop() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git stash pop');
    invalidateCache();
  }

  Future<void> initRepo() async {
    final hostPath = _resolveRepoHostPath() ?? ref.read(workspaceProvider).currentPath;
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git init');
    _repoCache.removeWhere((key, _) => key.startsWith(hostPath));
    invalidateCache();
  }

  Future<String> getFileContentFromGit(String relativePath) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      final output = await runtime.runCommand('cd "$guestPath" && git show HEAD:"$relativePath" 2>/dev/null');
      return output;
    } catch (e) {
      debugPrint('Git show failed: $e');
      return '';
    }
  }

  Future<void> discardChanges(String relativePath) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      await runtime.runCommand('cd "$guestPath" && (git checkout -- "$relativePath" 2>/dev/null || rm -rf "$relativePath")');
      invalidateCache();
    } catch (e) {
      debugPrint('Git discard failed: $e');
    }
  }

  Future<void> discardAllChanges() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      await runtime.runCommand('cd "$guestPath" && git reset --hard HEAD && git clean -fd');
      invalidateCache();
    } catch (e) {
      debugPrint('Git discard all failed: $e');
    }
  }

  Future<String?> createAgentCheckpoint() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return null;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      await runtime.runCommand('cd "$guestPath" && git config --global --add safe.directory "*"');
      final status = await getStatus();
      final hasUncommitted = status != null && (status.modifiedFiles.isNotEmpty || status.untrackedFiles.isNotEmpty);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (hasUncommitted) {
        final stashName = 'quantum-ide-agent-checkpoint-$timestamp';
        await runtime.runCommand('cd "$guestPath" && git add -A');
        await runtime.runCommand('cd "$guestPath" && git stash push -m "$stashName" --include-untracked');
        invalidateCache();
        return stashName;
      } else {
        final headHash = (await runtime.runCommand('cd "$guestPath" && git rev-parse HEAD')).trim();
        if (headHash.isNotEmpty) {
          return 'clean-head:$headHash';
        }
        return 'clean-head';
      }
    } catch (e) {
      debugPrint('Git checkpoint failed: $e');
      return null;
    }
  }

  Future<bool> rollbackAgentCheckpoint(String? stashRef) async {
    if (stashRef == null) return false;
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return false;
    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      await runtime.runCommand('cd "$guestPath" && git config --global --add safe.directory "*"');

      await runtime.runCommand('cd "$guestPath" && git reset --hard HEAD');
      await runtime.runCommand('cd "$guestPath" && git clean -fd');

      if (stashRef.startsWith('quantum-ide-agent-checkpoint-')) {
        final output = await runtime.runCommand('cd "$guestPath" && git stash list');
        final match = RegExp(r'(stash@\{\d+\}):.*?' + RegExp.escape(stashRef)).firstMatch(output);
        if (match != null) {
          final stashIndex = match.group(1)!;
          await runtime.runCommand('cd "$guestPath" && git stash pop "$stashIndex"');
        } else if (output.contains(stashRef)) {
          await runtime.runCommand('cd "$guestPath" && git stash pop');
        }
      } else if (stashRef.startsWith('clean-head:')) {
        final targetHash = stashRef.substring('clean-head:'.length).trim();
        if (targetHash.isNotEmpty) {
          await runtime.runCommand('cd "$guestPath" && git reset --hard $targetHash');
        }
      }
      invalidateCache();
      return true;
    } catch (e) {
      debugPrint('Git rollback failed: $e');
      return false;
    }
  }
}

final gitServiceProvider = Provider((ref) => GitService(ref));

