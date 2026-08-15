import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

class MultiCursorService extends ChangeNotifier {
  final List<Offset> _cursors = <Offset>[];
  final List<Offset> _selections = <Offset>[];
  bool _isActive = false;

  List<Offset> get cursors => List.unmodifiable(_cursors);
  List<Offset> get selections => List.unmodifiable(_selections);
  bool get isActive => _isActive;

  void addCursor(int line, int offset) {
    _cursors.add(Offset(line.toDouble(), offset.toDouble()));
    _isActive = true;
    notifyListeners();
  }

  void removeCursor(int index) {
    if (index >= 0 && index < _cursors.length) {
      _cursors.removeAt(index);
      if (_cursors.isEmpty) {
        _isActive = false;
      }
      notifyListeners();
    }
  }

  void clearCursors() {
    _cursors.clear();
    _selections.clear();
    _isActive = false;
    notifyListeners();
  }

  void moveAllCursors(int lineDelta, int offsetDelta) {
    for (int i = 0; i < _cursors.length; i++) {
      _cursors[i] = Offset(
        _cursors[i].dx + lineDelta,
        _cursors[i].dy + offsetDelta,
      );
    }
    notifyListeners();
  }

  void selectAllOccurrences(CodeLineEditingController controller, String word) {
    if (word.isEmpty) return;

    _cursors.clear();
    final text = controller.text;
    final lines = text.split('\n');

    for (int line = 0; line < lines.length; line++) {
      int startIdx = 0;
      while (true) {
        final foundIdx = lines[line].indexOf(word, startIdx);
        if (foundIdx == -1) break;

        _cursors.add(Offset(line.toDouble(), foundIdx.toDouble()));
        startIdx = foundIdx + 1;
      }
    }

    _isActive = _cursors.length > 1;
    notifyListeners();
  }

  void deleteLineAtEachCursor(CodeLineEditingController controller) {
    if (_cursors.isEmpty) return;

    final text = controller.text;
    final lines = text.split('\n');
    final linesToDelete = _cursors
        .map((c) => c.dx.toInt())
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    for (final lineIdx in linesToDelete) {
      if (lineIdx >= 0 && lineIdx < lines.length) {
        lines.removeAt(lineIdx);
      }
    }

    controller.text = lines.join('\n');
    clearCursors();
  }

  void insertTextAtEachCursor(CodeLineEditingController controller, String text) {
    if (_cursors.isEmpty || text.isEmpty) return;

    final controllerText = controller.text;
    final lines = controllerText.split('\n');
    final sortedCursors = List<Offset>.from(_cursors)
      ..sort((a, b) => b.dx != a.dx
          ? b.dx.compareTo(a.dx)
          : b.dy.compareTo(a.dy));

    for (final cursor in sortedCursors) {
      final lineIdx = cursor.dx.toInt();
      final offset = cursor.dy.toInt();

      if (lineIdx >= 0 && lineIdx < lines.length) {
        final currentLine = lines[lineIdx];
        final safeOffset = offset.clamp(0, currentLine.length);
        lines[lineIdx] = currentLine.substring(0, safeOffset) +
            text +
            currentLine.substring(safeOffset);
      }
    }

    controller.text = lines.join('\n');
    clearCursors();
  }
}

final multiCursorProvider = ChangeNotifierProvider<MultiCursorService>((ref) {
  return MultiCursorService();
});
