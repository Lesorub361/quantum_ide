import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/foundation.dart';

enum DiffType { added, removed, modified }

class DiffMarker {
  final int line;
  final DiffType type;

  DiffMarker({required this.line, required this.type});
}

class DiffHunk {
  final int index; // Index of the diff block in the diffs list
  final DiffType type;
  final String text;
  final int startLine; // 0-indexed line in currentText
  final int endLine;   // 0-indexed line in currentText

  DiffHunk({
    required this.index,
    required this.type,
    required this.text,
    required this.startLine,
    required this.endLine,
  });
}

class DiffService {
  Future<List<DiffMarker>> calculateDiff(String original, String current) async {
    if (original == current) return [];
    
    // Large files should be processed in an isolate to keep UI smooth
    if (original.length > 10000 || current.length > 10000) {
      return compute(_calculateDiffStatic, _DiffInput(original, current));
    }
    return _calculateDiffStatic(_DiffInput(original, current));
  }

  static List<DiffMarker> _calculateDiffStatic(_DiffInput input) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(input.original, input.current);
    dmp.diffCleanupSemantic(diffs);

    final markers = <DiffMarker>[];
    int currentLine = 0;

    for (final d in diffs) {
      final lines = d.text.split('\n');
      final lineCount = lines.length - 1;

      if (d.operation == DIFF_EQUAL) {
        currentLine += lineCount;
      } else if (d.operation == DIFF_INSERT) {
        for (int i = 0; i <= lineCount; i++) {
          markers.add(DiffMarker(line: currentLine + i, type: DiffType.added));
        }
        currentLine += lineCount;
      } else if (d.operation == DIFF_DELETE) {
        markers.add(DiffMarker(line: currentLine, type: DiffType.removed));
      }
    }

    final Map<int, DiffMarker> uniqueMarkers = {};
    for (final marker in markers) {
      if (!uniqueMarkers.containsKey(marker.line) || 
          (marker.type == DiffType.added && uniqueMarkers[marker.line]!.type != DiffType.added)) {
        uniqueMarkers[marker.line] = marker;
      }
    }

    return uniqueMarkers.values.toList();
  }

  static List<DiffHunk> calculateHunks(String original, String current) {
    if (original == current) return [];
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(original, current);
    dmp.diffCleanupSemantic(diffs);

    final hunks = <DiffHunk>[];
    int currentLine = 0;

    for (int i = 0; i < diffs.length; i++) {
      final d = diffs[i];
      final lines = d.text.split('\n');
      final lineCount = lines.length - 1;

      if (d.operation == DIFF_EQUAL) {
        currentLine += lineCount;
      } else if (d.operation == DIFF_INSERT) {
        hunks.add(DiffHunk(
          index: i,
          type: DiffType.added,
          text: d.text,
          startLine: currentLine,
          endLine: currentLine + lineCount,
        ));
        currentLine += lineCount;
      } else if (d.operation == DIFF_DELETE) {
        hunks.add(DiffHunk(
          index: i,
          type: DiffType.removed,
          text: d.text,
          startLine: currentLine,
          endLine: currentLine, // Deletion is located at the current line
        ));
      }
    }
    return hunks;
  }
}

class _DiffInput {
  final String original;
  final String current;
  _DiffInput(this.original, this.current);
}

