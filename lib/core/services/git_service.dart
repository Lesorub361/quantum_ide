import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/secure_storage_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class GitService {
  final Ref ref;

  GitService(this.ref);

  static final Map<String, bool> _repoCache = {};
  static GitStatus? _cachedStatus;
  static String? _cachedPath;
  static DateTime? _lastStatusTime;
  static const Duration _statusCacheTtl = Duration(seconds: 15);

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

  /// Builds a `git` command prefix that automatically injects the user's saved
  /// GitHub token via HTTP extraheader so HTTPS remotes work without manual
  /// credential prompts or leaking tokens into `.git/config`.
  Future<String> _gitAuthPrefix() async {
    try {
      final token = await SecureStorageService().retrieve('github_token');
      if (token != null && token.trim().isNotEmpty) {
        final basicAuth = base64Encode(utf8.encode('x-access-token:${token.trim()}'));
        return 'GIT_TERMINAL_PROMPT=0 git -c http.https://github.com/.extraheader="AUTHORIZATION: basic $basicAuth"';
      }
    } catch (_) {}
    return 'GIT_TERMINAL_PROMPT=0 git';
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
      // porcelain status with -uall, diff stats, commits, tags, branches, remotes, stashes, and author config.
      final batchCmd = [
        'cd "$guestPath" 2>/dev/null || exit 0',
        'if [ "\$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then echo "__NOT_GIT_REPO__"; exit 0; fi',
        'echo "__SECTION_BRANCH__"',
        'git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "main"',
        'echo "__SECTION_AHEAD_BEHIND__"',
        '(git rev-list --left-right --count HEAD...@{u} 2>/dev/null || echo "0\t0")',
        'echo "__SECTION_STATUS__"',
        'git status --porcelain -unormal 2>/dev/null',
        'echo "__SECTION_NUMSTAT__"',
        '(git diff --numstat 2>/dev/null || true; git diff --cached --numstat 2>/dev/null || true)',
        'echo "__SECTION_COMMITS__"',
        '(git log -n 45 --pretty=format:"%H\t%h\t%s\t%an\t%ar\t%D" 2>/dev/null || true)',
        'echo ""',
        'echo "__SECTION_TAGS__"',
        '(git for-each-ref --sort=-creatordate --format="%(refname:short)\t%(objectname:short)\t%(creatordate:short)\t%(contents:subject)" refs/tags 2>/dev/null | head -n 30 || true)',
        'echo "__SECTION_BRANCHES__"',
        '(git for-each-ref --format="%(refname:short)" refs/heads 2>/dev/null || true)',
        'echo "__SECTION_REMOTE_BRANCHES__"',
        '(git for-each-ref --format="%(refname:short)" refs/remotes/origin 2>/dev/null || true)',
        'echo "__SECTION_STASHES__"',
        '(git stash list --pretty=format:"%gd\t%gs\t%cr" 2>/dev/null || true)',
        'echo ""',
        'echo "__SECTION_USER__"',
        'echo "\$(git config user.name 2>/dev/null || true)\t\$(git config user.email 2>/dev/null || true)"',
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
      final fileStatusCodes = <String, String>{};

      final modifiedSet = <String>{};
      final stagedSet = <String>{};
      final untrackedSet = <String>{};
      final conflictedSet = <String>{};

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

        final cleanRel = file.endsWith('/') ? file.substring(0, file.length - 1) : file;

        const conflictStatuses = {'DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'};
        if (conflictStatuses.contains(status)) {
          if (conflictedSet.add(cleanRel)) {
            conflicted.add(cleanRel);
            fileStatusCodes[cleanRel] = 'U';
          }
        } else if (status == '??') {
          // Never perform synchronous recursive disk traversal of untracked directories
          // on the main UI thread. Treat the untracked path itself as the item.
          if (untrackedSet.length < 1000) {
            if (untrackedSet.add(cleanRel)) {
              untracked.add(cleanRel);
              fileStatusCodes[cleanRel] = '?';
            }
          }
        } else {
          if (x != ' ' && x != '?') {
            if (stagedSet.add(cleanRel)) {
              staged.add(cleanRel);
              fileStatusCodes[cleanRel] = x;
            }
          }
          if (y != ' ' && y != '?') {
            if (modifiedSet.add(cleanRel)) {
              modified.add(cleanRel);
              fileStatusCodes[cleanRel] = y;
            }
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
      final branchesRaw = extractSection('__SECTION_BRANCHES__', '__SECTION_REMOTE_BRANCHES__');
      for (final line in branchesRaw.split('\n')) {
        final b = line.trim();
        if (b.isNotEmpty && !branches.contains(b)) {
          branches.add(b);
        }
      }
      if (!branches.contains(branch)) {
        branches.insert(0, branch);
      }

      final remoteBranches = <String>[];
      final remoteBranchesRaw = extractSection('__SECTION_REMOTE_BRANCHES__', '__SECTION_STASHES__');
      for (final line in remoteBranchesRaw.split('\n')) {
        final rb = line.trim();
        if (rb.isNotEmpty && rb != 'origin/HEAD' && !rb.endsWith('/HEAD') && !remoteBranches.contains(rb)) {
          remoteBranches.add(rb);
        }
      }

      final stashes = <GitStashEntry>[];
      final stashesRaw = extractSection('__SECTION_STASHES__', '__SECTION_USER__');
      for (final line in stashesRaw.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('\t');
        if (parts.isNotEmpty && parts[0].startsWith('stash@{')) {
          final refName = parts[0].trim();
          final rawSubject = parts.length > 1 ? parts[1].trim() : '';
          final relTime = parts.length > 2 ? parts[2].trim() : '';
          String stashBranch = '';
          String stashMsg = rawSubject;
          final onIdx = rawSubject.indexOf(': ');
          if (onIdx != -1) {
            final prefix = rawSubject.substring(0, onIdx);
            stashMsg = rawSubject.substring(onIdx + 2).trim();
            final branchMatch = RegExp(r'on\s+([^\s:]+)').firstMatch(prefix);
            if (branchMatch != null) {
              stashBranch = branchMatch.group(1) ?? '';
            }
          }
          // Hide internal temporary agent checkpoints from cluttering the user's stash list unless desired
          if (!stashMsg.startsWith('quantum-ide-agent-checkpoint-')) {
            stashes.add(GitStashEntry(
              ref: refName,
              branch: stashBranch,
              message: stashMsg.isEmpty ? refName : stashMsg,
              relativeTime: relTime,
            ));
          }
        }
      }

      String? userName;
      String? userEmail;
      final userRaw = extractSection('__SECTION_USER__', '__SECTION_REMOTE__');
      if (userRaw.isNotEmpty) {
        final uParts = userRaw.split('\t');
        if (uParts.isNotEmpty && uParts[0].trim().isNotEmpty) {
          userName = uParts[0].trim();
        }
        if (uParts.length > 1 && uParts[1].trim().isNotEmpty) {
          userEmail = uParts[1].trim();
        }
      }

      final remoteRaw = extractSection('__SECTION_REMOTE__', null);
      final remoteUrl = remoteRaw.split('\n').first.trim();

      final projectVersion = await _detectProjectVersion(hostPath);

      final result = GitStatus(
        modifiedFiles: modified,
        stagedFiles: staged,
        untrackedFiles: untracked,
        conflictedFiles: conflicted,
        fileStatusCodes: fileStatusCodes,
        currentBranch: branch,
        branches: branches,
        remoteBranches: remoteBranches,
        ahead: ahead,
        behind: behind,
        diffStats: diffStats,
        recentCommits: recentCommits,
        tags: tags,
        stashes: stashes,
        projectVersion: projectVersion,
        remoteUrl: remoteUrl.isNotEmpty ? remoteUrl : null,
        userName: userName,
        userEmail: userEmail,
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

    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git reset HEAD -- "$filePath"');
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

    final out = await ref.read(runtimeServiceProvider).runCommand('$cmd 2>&1');
    invalidateCache();
    if (out.contains('fatal:') || out.contains('error:')) {
      throw Exception(out.trim());
    }
  }

  Future<String> fetch() async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);
    final gitCmd = await _gitAuthPrefix();

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && $gitCmd fetch --all --prune 2>&1',
    );
    invalidateCache();
    if (out.contains('fatal:') || out.contains('error: failed')) {
      throw Exception(out.trim());
    }
    return out.trim();
  }

  Future<String> push({bool force = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);
    final gitCmd = await _gitAuthPrefix();
    final forceFlag = force ? ' --force-with-lease' : '';

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && ($gitCmd push$forceFlag 2>&1 || $gitCmd push -u origin HEAD$forceFlag 2>&1)',
    );
    invalidateCache();
    if (out.contains('fatal:') || out.contains('error: failed to push')) {
      throw Exception(out.trim());
    }
    return out.trim();
  }

  Future<String> pull({bool rebase = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);
    final gitCmd = await _gitAuthPrefix();
    final rebaseFlag = rebase ? '--rebase=true' : '--rebase=false';

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && $gitCmd pull $rebaseFlag 2>&1',
    );
    invalidateCache();
    if (out.contains('fatal:') || out.contains('CONFLICT')) {
      throw Exception(out.trim());
    }
    return out.trim();
  }

  Future<void> setRemoteUrl(String url, {String remoteName = 'origin'}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final cleanUrl = url.trim().replaceAll('"', '');

    await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && (git remote set-url "$remoteName" "$cleanUrl" 2>/dev/null || git remote add "$remoteName" "$cleanUrl")',
    );
    invalidateCache();
  }

  Future<void> setUserConfig(String name, String email, {bool global = true}) async {
    final hostPath = _resolveRepoHostPath();
    final guestPath = hostPath != null ? await _getGuestPath(hostPath) : '/root';
    final scope = global ? '--global' : '';
    final cleanName = name.trim().replaceAll('"', '\\"');
    final cleanEmail = email.trim().replaceAll('"', '\\"');

    await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git config $scope user.name "$cleanName" && git config $scope user.email "$cleanEmail"',
    );
    invalidateCache();
  }

  Future<void> createTag(String tagName, String message, {String? commitHash}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final escapedMsg = message.replaceAll('"', '\\"');
    final target = (commitHash != null && commitHash.trim().isNotEmpty) ? ' "${commitHash.trim()}"' : '';

    await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && (git config user.name >/dev/null 2>&1 || git config user.name "Quantum Developer") && (git config user.email >/dev/null 2>&1 || git config user.email "dev@quantum-ide.local") && git tag -f -a "$tagName" -m "$escapedMsg"$target',
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
    final gitCmd = await _gitAuthPrefix();

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && ($gitCmd push 2>&1 || $gitCmd push -u origin HEAD 2>&1) && $gitCmd push --tags 2>&1',
    );
    invalidateCache();
    if (out.contains('fatal:') || out.contains('error: failed to push')) {
      throw Exception(out.trim());
    }
  }

  Future<void> checkoutBranch(String branchName, {bool createNew = false, String? fromRef}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final flag = createNew ? '-b ' : '';
    final startPoint = (createNew && fromRef != null && fromRef.trim().isNotEmpty) ? ' "${fromRef.trim()}"' : '';

    // If checking out a remote branch like origin/feature, create a local tracking branch automatically
    String cmd;
    if (!createNew && branchName.startsWith('origin/')) {
      final localName = branchName.substring('origin/'.length);
      cmd = 'cd "$guestPath" && (git checkout "$localName" 2>/dev/null || git checkout -b "$localName" --track "$branchName") 2>&1';
    } else {
      cmd = 'cd "$guestPath" && git checkout $flag"$branchName"$startPoint 2>&1';
    }

    final out = await ref.read(runtimeServiceProvider).runCommand(cmd);
    invalidateCache();
    if (out.contains('error:') || out.contains('fatal:')) {
      throw Exception(out.trim());
    }
  }

  Future<String> mergeBranch(String branchName) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git merge --no-edit "$branchName" 2>&1',
    );
    invalidateCache();
    if (out.contains('CONFLICT') || out.contains('fatal:') || out.contains('error:')) {
      throw Exception(out.trim());
    }
    return out.trim();
  }

  Future<void> deleteBranch(String branchName, {bool force = false}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final flag = force ? '-D' : '-d';

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git branch $flag "$branchName" 2>&1',
    );
    invalidateCache();
    if (out.contains('error:') || out.contains('fatal:')) {
      throw Exception(out.trim());
    }
  }

  Future<void> renameBranch(String oldName, String newName) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git branch -m "$oldName" "$newName" 2>&1',
    );
    invalidateCache();
    if (out.contains('error:') || out.contains('fatal:')) {
      throw Exception(out.trim());
    }
  }

  Future<void> resetToCommit(String commitHash, {String mode = 'mixed'}) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final safeMode = (mode == 'soft' || mode == 'hard') ? mode : 'mixed';

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git reset --$safeMode "$commitHash" 2>&1',
    );
    invalidateCache();
    if (out.contains('fatal:') || out.contains('error:')) {
      throw Exception(out.trim());
    }
  }

  Future<void> revertCommit(String commitHash) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git revert --no-edit "$commitHash" 2>&1',
    );
    invalidateCache();
    if (out.contains('CONFLICT') || out.contains('fatal:') || out.contains('error:')) {
      throw Exception(out.trim());
    }
  }

  Future<void> cherryPickCommit(String commitHash) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);

    final out = await ref.read(runtimeServiceProvider).runCommand(
      'cd "$guestPath" && git cherry-pick "$commitHash" 2>&1',
    );
    invalidateCache();
    if (out.contains('CONFLICT') || out.contains('fatal:') || out.contains('error:')) {
      throw Exception(out.trim());
    }
  }

  Future<List<GitCommitFileEntry>> getCommitFiles(String commitHash) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return [];
    final guestPath = await _getGuestPath(hostPath);

    try {
      final out = await ref.read(runtimeServiceProvider).runCommand(
        'cd "$guestPath" && git show --name-status --pretty=format:"" "$commitHash" 2>/dev/null',
      );
      final files = <GitCommitFileEntry>[];
      for (final line in out.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('\t');
        if (parts.length >= 2) {
          final status = parts[0].trim();
          final path = parts.last.trim();
          files.add(GitCommitFileEntry(
            status: status.isNotEmpty ? status[0] : 'M',
            path: path,
          ));
        }
      }
      return files;
    } catch (_) {
      return [];
    }
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

  Future<void> stashPop([String? stashRef]) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    final target = (stashRef != null && stashRef.isNotEmpty) ? ' "$stashRef"' : '';
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git stash pop$target');
    invalidateCache();
  }

  Future<void> stashApply(String stashRef) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git stash apply "$stashRef"');
    invalidateCache();
  }

  Future<void> stashDrop(String stashRef) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final guestPath = await _getGuestPath(hostPath);
    await ref.read(runtimeServiceProvider).runCommand('cd "$guestPath" && git stash drop "$stashRef"');
    invalidateCache();
  }

  Future<String> getStashDiff(String stashRef) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return '';
    final guestPath = await _getGuestPath(hostPath);
    try {
      return await ref.read(runtimeServiceProvider).runCommand(
        'cd "$guestPath" && git stash show -p --stat --no-color "$stashRef" 2>/dev/null',
      );
    } catch (_) {
      return '';
    }
  }

  Future<void> addToGitignore(String pattern) async {
    final hostPath = _resolveRepoHostPath();
    if (hostPath == null) return;
    final gitignoreFile = File(p.join(hostPath, '.gitignore'));
    String existing = '';
    if (await gitignoreFile.exists()) {
      existing = await gitignoreFile.readAsString();
    }
    final lines = existing.split('\n').map((e) => e.trim()).toList();
    if (!lines.contains(pattern.trim())) {
      final prefix = (existing.isNotEmpty && !existing.endsWith('\n')) ? '\n' : '';
      await gitignoreFile.writeAsString('$existing$prefix${pattern.trim()}\n');
    }
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
