import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class GitCommit {
  final String hash;
  final String shortHash;
  final String author;
  final DateTime date;
  final String message;
  final List<String> parents;
  final List<String> branches;
  final List<String> tags;

  GitCommit({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.date,
    required this.message,
    required this.parents,
    this.branches = const [],
    this.tags = const [],
  });
}

class GraphColumn {
  final int index;
  final Color color;

  const GraphColumn({required this.index, required this.color});
}

class GitGraphEntry {
  final GitCommit commit;
  final List<GraphColumn> columns;

  const GitGraphEntry({required this.commit, required this.columns});
}

class GitGraphService {
  final Ref ref;

  static const List<Color> _branchColors = [
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
    Color(0xFF8BC34A),
  ];

  GitGraphService(this.ref);

  Future<String> _getGuestPath(String hostPath) async {
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  Future<List<GitCommit>> getCommits({int maxCount = 200, String? branch}) async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return [];

    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      final branchArg = branch != null ? '"$branch"' : 'HEAD';
      const separator = '<<<SEP>>>';
      const format = '%H$separator%h$separator%an$separator%aI$separator%s$separator%P';

      final output = await runtime.runCommand(
        'cd "$guestPath" && git log $branchArg --format="$format" --max-count=$maxCount 2>/dev/null',
      );

      if (output.trim().isEmpty) return [];

      return output.split('\n').where((line) => line.isNotEmpty).map((line) {
        final parts = line.split(separator);
        if (parts.length < 5) return null;

        return GitCommit(
          hash: parts[0],
          shortHash: parts[1],
          author: parts[2],
          date: DateTime.tryParse(parts[3]) ?? DateTime.now(),
          message: parts[4],
          parents: parts.length > 5 ? parts[5].trim().split(' ').where((p) => p.isNotEmpty).toList() : [],
        );
      }).whereType<GitCommit>().toList();
    } catch (e) {
      debugPrint('Git graph log failed: $e');
      return [];
    }
  }

  Future<List<String>> getBranches() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return [];

    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      final output = await runtime.runCommand(
        'cd "$guestPath" && git branch --format="%(refname:short)" 2>/dev/null',
      );
      return output.split('\n').where((b) => b.trim().isNotEmpty).map((b) => b.trim()).toList();
    } catch (e) {
      debugPrint('Git branches failed: $e');
      return [];
    }
  }

  Future<Map<String, List<String>>> getBranchRefs() async {
    final workspace = ref.read(workspaceProvider);
    final hostPath = workspace.currentPath;
    if (hostPath == null) return {};

    final guestPath = await _getGuestPath(hostPath);
    final runtime = ref.read(runtimeServiceProvider);

    try {
      final output = await runtime.runCommand(
        'cd "$guestPath" && git log --all --decorate --format="%H %D" --max-count=500 2>/dev/null',
      );

      final refs = <String, List<String>>{};
      for (final line in output.split('\n')) {
        if (line.trim().isEmpty) continue;
        final spaceIdx = line.indexOf(' ');
        if (spaceIdx == -1) continue;
        final hash = line.substring(0, spaceIdx);
        final decorations = line.substring(spaceIdx + 1).trim();
        if (decorations.isEmpty) continue;

        final refNames = <String>[];
        for (final part in decorations.split(',')) {
          final trimmed = part.trim();
          if (trimmed.startsWith('HEAD -> ')) {
            refNames.add(trimmed.substring(8));
          } else if (trimmed.startsWith('tag: ')) {
            refNames.add(trimmed);
          } else if (trimmed.isNotEmpty) {
            refNames.add(trimmed);
          }
        }
        if (refNames.isNotEmpty) refs[hash] = refNames;
      }
      return refs;
    } catch (e) {
      debugPrint('Git branch refs failed: $e');
      return {};
    }
  }

  List<GitGraphEntry> buildGraph(List<GitCommit> commits, Map<String, List<String>> refs) {
    if (commits.isEmpty) return [];

    final commitMap = <String, GitCommit>{};
    for (final c in commits) {
      commitMap[c.hash] = c;
    }

    final activeColumns = <String, int>{};
    final columnColors = <int, Color>{};
    int nextColumn = 0;
    final entries = <GitGraphEntry>[];

    for (int i = 0; i < commits.length; i++) {
      final commit = commits[i];
      final refNames = refs[commit.hash];
      final branches = <String>[];
      final tags = <String>[];

      if (refNames != null) {
        for (final rn in refNames) {
          if (rn.startsWith('tag: ')) {
            tags.add(rn.substring(5));
          } else {
            branches.add(rn);
          }
        }
      }

      final enrichedCommit = GitCommit(
        hash: commit.hash,
        shortHash: commit.shortHash,
        author: commit.author,
        date: commit.date,
        message: commit.message,
        parents: commit.parents,
        branches: branches,
        tags: tags,
      );

      if (!activeColumns.containsKey(commit.hash)) {
        activeColumns[commit.hash] = nextColumn;
        columnColors[nextColumn] = _branchColors[nextColumn % _branchColors.length];
        nextColumn++;
      }

      final columns = <GraphColumn>[];
      final activeColumnValues = activeColumns.values.toSet();

      for (final colIdx in activeColumnValues) {
        final color = columnColors[colIdx] ?? _branchColors[0];
        columns.add(GraphColumn(index: colIdx, color: color));
      }

      entries.add(GitGraphEntry(commit: enrichedCommit, columns: columns));

      final myCol = activeColumns[commit.hash]!;
      activeColumns.remove(commit.hash);

      for (final parentHash in commit.parents) {
        if (!activeColumns.containsKey(parentHash)) {
          activeColumns[parentHash] = myCol;
        } else {
          final existingCol = activeColumns[parentHash]!;
          if (existingCol != myCol) {
            columnColors[existingCol] = columnColors[myCol] ?? _branchColors[0];
          }
        }
      }

      if (commit.parents.isEmpty) {
        columnColors.remove(myCol);
      }
    }

    return entries;
  }
}

final gitGraphServiceProvider = Provider((ref) => GitGraphService(ref));
