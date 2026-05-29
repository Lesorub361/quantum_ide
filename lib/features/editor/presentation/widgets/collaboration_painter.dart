import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/collaboration_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class CombinedListenable extends ChangeNotifier {
  CombinedListenable(List<Listenable> listenables) {
    for (final listenable in listenables) {
      listenable.addListener(notifyListeners);
    }
  }
}

class CollaborationPainter extends CustomPainter {
  final CodeIndicatorValueNotifier notifier;
  final String filePath;
  final WidgetRef ref;

  CollaborationPainter({
    required this.notifier,
    required this.filePath,
    required this.ref,
  }) : super(repaint: CombinedListenable([notifier, ref.read(collaborationProvider.notifier).cursorRepaintNotifier]));

  @override
  void paint(Canvas canvas, Size size) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    
    // Convert current file path to a relative path consistent across nodes
    final relativePath = p.relative(filePath, from: workspacePath);

    final collabState = ref.read(collaborationProvider);
    if (!collabState.isConnected) return;

    final val = notifier.value;
    if (val == null) return;

    for (final user in collabState.users.values) {
      if (user.activeFile != relativePath) continue;

      final sl = user.selectionStartLine;
      final sc = user.selectionStartCol;
      final el = user.selectionEndLine;
      final ec = user.selectionEndCol;

      final hasSelection = sl != -1 && sc != -1 && el != -1 && ec != -1 && !(sl == el && sc == ec);

      for (final paragraph in val.paragraphs) {
        final lineIndex = paragraph.index;

        // 1. Paint Selection Area
        if (hasSelection) {
          final minL = min(sl, el);
          final maxL = max(sl, el);

          if (lineIndex >= minL && lineIndex <= maxL) {
            int startCol = 0;
            int endCol = paragraph.paragraph.length;

            if (lineIndex == minL) {
              startCol = sl < el ? sc : ec;
            }
            if (lineIndex == maxL) {
              endCol = sl < el ? ec : sc;
            }
            if (lineIndex == minL && lineIndex == maxL) {
              startCol = min(sc, ec);
              endCol = max(sc, ec);
            }

            final lineLen = paragraph.paragraph.length;
            if (startCol < endCol && startCol < lineLen) {
              final range = TextRange(
                start: startCol.clamp(0, lineLen),
                end: endCol.clamp(0, lineLen),
              );
              final rects = paragraph.paragraph.getRangeRects(range);
              final selectionPaint = Paint()..color = user.color.withValues(alpha: 0.25);

              for (final rect in rects) {
                final drawRect = Rect.fromLTWH(
                  paragraph.offset.dx + rect.left,
                  paragraph.offset.dy + rect.top,
                  rect.width,
                  paragraph.paragraph.height,
                );
                canvas.drawRect(drawRect, selectionPaint);
              }
            }
          }
        }

        // 2. Paint Cursor Caret & Name Tag
        if (lineIndex == user.cursorLine) {
          final col = user.cursorCol;
          final cursorX = _getCursorX(paragraph.paragraph, col) + paragraph.offset.dx;
          final cursorY = paragraph.offset.dy;
          final lineHeight = paragraph.paragraph.height;

          // Caret line
          final cursorPaint = Paint()
            ..color = user.color
            ..strokeWidth = 2.0
            ..style = PaintingStyle.stroke;
          canvas.drawLine(
            Offset(cursorX, cursorY),
            Offset(cursorX, cursorY + lineHeight),
            cursorPaint,
          );

          // Caret name flag
          _drawNameTag(canvas, user.name, user.color, cursorX, cursorY, lineHeight);
        }
      }
    }
  }

  double _getCursorX(dynamic codeParagraph, int col) {
    if (col <= 0) {
      final rects = codeParagraph.getRangeRects(const TextRange(start: 0, end: 1));
      if (rects.isNotEmpty) return rects.first.left;
      return 0.0;
    } else {
      final length = codeParagraph.length as int;
      final targetCol = col.clamp(0, length);
      if (targetCol == 0) return 0.0;

      final rects = codeParagraph.getRangeRects(TextRange(start: targetCol - 1, end: targetCol));
      if (rects.isNotEmpty) return rects.first.right;
      
      final firstRects = codeParagraph.getRangeRects(const TextRange(start: 0, end: 1));
      if (firstRects.isNotEmpty) return firstRects.first.left;
      return 0.0;
    }
  }

  void _drawNameTag(Canvas canvas, String name, Color color, double cursorX, double cursorY, double lineHeight) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'Outfit',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final tagHeight = textPainter.height + 4;
    final tagWidth = textPainter.width + 10;
    final tagX = cursorX - tagWidth / 2;
    final tagY = cursorY - tagHeight - 3;

    // Outer rounded box
    final rect = Rect.fromLTWH(tagX, tagY, tagWidth, tagHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    final boxPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, boxPaint);

    // Connected caret indicator arrow
    final arrowPath = Path()
      ..moveTo(cursorX, cursorY - 3)
      ..lineTo(cursorX - 3, cursorY - 6)
      ..lineTo(cursorX + 3, cursorY - 6)
      ..close();
    canvas.drawPath(arrowPath, boxPaint);

    // Text label
    textPainter.paint(canvas, Offset(tagX + 5, tagY + 2));
  }

  @override
  bool shouldRepaint(covariant CollaborationPainter oldDelegate) {
    return oldDelegate.notifier != notifier || oldDelegate.filePath != filePath;
  }
}
