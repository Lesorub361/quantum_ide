import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class GitBlameLine {
  final int lineNumber;
  final String commitHash;
  final String author;
  final String date;
  final String message;

  const GitBlameLine({
    required this.lineNumber,
    required this.commitHash,
    required this.author,
    required this.date,
    required this.message,
  });
}

class GitBlameState {
  final List<GitBlameLine> lines;
  final bool isLoading;
  final String? filePath;

  const GitBlameState({
    this.lines = const [],
    this.isLoading = false,
    this.filePath,
  });

  GitBlameState copyWith({
    List<GitBlameLine>? lines,
    bool? isLoading,
    String? filePath,
  }) {
    return GitBlameState(
      lines: lines ?? this.lines,
      isLoading: isLoading ?? this.isLoading,
      filePath: filePath ?? this.filePath,
    );
  }
}

class GitBlameService extends StateNotifier<GitBlameState> {
  final Ref ref;

  GitBlameService(this.ref) : super(const GitBlameState());

  Future<void> loadBlame(String filePath) async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    state = state.copyWith(isLoading: true, filePath: filePath, lines: []);

    try {
      final runtime = ref.read(runtimeServiceProvider);
      final guestWorkspace = PathMapper.mapToGuest(workspacePath, runtime.appDirectory);
      final relativePath = filePath.replaceFirst(workspacePath, '').replaceFirst(RegExp(r'^/'), '');

      final output = await runtime.runCommand(
        'cd "$guestWorkspace" && git blame --line-porcelain -- "$relativePath" 2>/dev/null',
      );

      if (output.trim().isEmpty || output.contains('fatal:')) {
        state = state.copyWith(isLoading: false, lines: []);
        return;
      }

      final parsedLines = <GitBlameLine>[];
      final rawLines = output.split('\n');

      String currentHash = '';
      int currentLineNo = 1;
      String author = '';
      String date = '';
      String summary = '';

      final headerRegex = RegExp(r'^([0-9a-f]{40})\s+(\d+)\s+(\d+)');

      for (final line in rawLines) {
        final headerMatch = headerRegex.firstMatch(line);
        if (headerMatch != null) {
          currentHash = headerMatch.group(1)!.substring(0, 7);
          currentLineNo = int.tryParse(headerMatch.group(3)!) ?? currentLineNo;
          continue;
        }
        if (line.startsWith('author ')) {
          author = line.substring(7).trim();
        } else if (line.startsWith('author-time ')) {
          final timestamp = int.tryParse(line.substring(12).trim()) ?? 0;
          if (timestamp > 0) {
            final dateObj = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
            date = '${dateObj.year}-${dateObj.month.toString().padLeft(2, '0')}-${dateObj.day.toString().padLeft(2, '0')}';
          }
        } else if (line.startsWith('summary ')) {
          summary = line.substring(8).trim();
        } else if (line.startsWith('\t')) {
          if (author.isNotEmpty) {
            parsedLines.add(GitBlameLine(
              lineNumber: currentLineNo,
              commitHash: currentHash,
              author: author,
              date: date,
              message: summary,
            ));
          }
          currentLineNo++;
        }
      }

      state = state.copyWith(isLoading: false, lines: parsedLines);
    } catch (e) {
      state = state.copyWith(isLoading: false, lines: []);
    }
  }

  void clear() {
    state = const GitBlameState();
  }
}

final gitBlameProvider = StateNotifierProvider<GitBlameService, GitBlameState>((ref) {
  return GitBlameService(ref);
});
