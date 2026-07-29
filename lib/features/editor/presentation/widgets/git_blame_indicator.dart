import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/git_blame_service.dart';

class GitBlameIndicator extends ConsumerWidget {
  final int lineNumber;
  final String filePath;

  const GitBlameIndicator({
    super.key,
    required this.lineNumber,
    required this.filePath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blameState = ref.watch(gitBlameProvider);
    
    if (blameState.isLoading) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white24),
      );
    }

    final line = blameState.lines.where((l) => l.lineNumber == lineNumber).firstOrNull;
    if (line == null) {
      return const SizedBox.shrink();
    }

    return Tooltip(
      message: '${line.author} • ${line.date}\n${line.message}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          line.author,
          style: GoogleFonts.inter(
            fontSize: 8,
            color: Colors.blueAccent.withValues(alpha: 0.6),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}