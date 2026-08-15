import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

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

    state = state.copyWith(isLoading: true, filePath: filePath);

    try {
      final relativePath = filePath.replaceFirst(workspacePath, '').replaceFirst(RegExp(r'^/'), '');
      
      final result = await Process.run(
        'git',
        ['blame', '--porcelain', relativePath],
        workingDirectory: workspacePath,
      );

      if (result.exitCode != 0) {
        state = state.copyWith(isLoading: false, lines: []);
        return;
      }

      final output = result.stdout.toString();
      final blocks = output.split(RegExp(r'^[0-9a-f]{40} ', multiLine: true));

      int lineNumber = 1;
      for (final block in blocks) {
        if (block.trim().isEmpty) continue;

        final lines = block.split('\n');
        const String commitHash = '';
        String author = '';
        String date = '';
        String message = '';

        for (final line in lines) {
          if (line.startsWith('author ')) {
            author = line.substring(7);
          } else if (line.startsWith('author-time ')) {
            final timestamp = int.tryParse(line.substring(12)) ?? 0;
            final dateObj = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
            date = '${dateObj.year}-${dateObj.month.toString().padLeft(2, '0')}-${dateObj.day.toString().padLeft(2, '0')}';
          } else if (line.startsWith('summary ')) {
            message = line.substring(8);
          }
        }

        if (author.isNotEmpty) {
          state = state.copyWith(
            lines: [
              ...state.lines,
              GitBlameLine(
                lineNumber: lineNumber,
                commitHash: commitHash,
                author: author,
                date: date,
                message: message,
              ),
            ],
          );
        }
        lineNumber++;
      }

      state = state.copyWith(isLoading: false);
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