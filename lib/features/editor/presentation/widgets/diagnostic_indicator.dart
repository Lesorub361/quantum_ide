import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import '../../../../core/models/code_diagnostic.dart';

class DiagnosticIndicator extends StatelessWidget {
  final List<CodeDiagnostic> diagnostics;
  final CodeIndicatorValueNotifier? notifier;

  const DiagnosticIndicator({
    super.key,
    required this.diagnostics,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DiagnosticPainter(
        notifier: notifier,
        diagnostics: diagnostics,
      ),
      size: Size.zero,
    );
  }
}

class _DiagnosticPainter extends CustomPainter {
  final CodeIndicatorValueNotifier? notifier;
  final List<CodeDiagnostic> diagnostics;

  _DiagnosticPainter({required this.notifier, required this.diagnostics}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final val = notifier?.value;
    if (val == null || diagnostics.isEmpty) return;

    for (final paragraph in val.paragraphs) {
      final lineIndex = paragraph.index;
      final lineDiagnostics = diagnostics.where((d) => d.range.index == lineIndex).toList();

      for (final diagnostic in lineDiagnostics) {
        final start = diagnostic.range.start;
        final end = diagnostic.range.end;
        
        final baseColor = diagnostic.severity == CodeDiagnosticSeverity.error
            ? Colors.redAccent
            : (diagnostic.severity == CodeDiagnosticSeverity.warning ? Colors.orangeAccent : Colors.blueAccent);

        // Get character range rects to locate the error range precisely
        final rects = paragraph.paragraph.getRangeRects(
          TextRange(start: start, end: end),
        );

        for (final rect in rects) {
          final startX = paragraph.offset.dx + rect.left;
          final endX = paragraph.offset.dx + rect.right;
          final width = endX - startX;
          if (width <= 0) continue;

          // Draw glow
          _drawWavyLine(
            canvas,
            Offset(startX, paragraph.offset.dy + paragraph.paragraph.height - 2),
            width,
            baseColor.withValues(alpha: 0.3),
            isGlow: true,
          );

          // Draw main line
          _drawWavyLine(
            canvas,
            Offset(startX, paragraph.offset.dy + paragraph.paragraph.height - 2),
            width,
            baseColor,
          );
        }
      }
    }
  }

  void _drawWavyLine(Canvas canvas, Offset start, double width, Color color, {bool isGlow = false}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = isGlow ? 3.0 : 1.2
      ..maskFilter = isGlow ? const MaskFilter.blur(BlurStyle.normal, 2.0) : null;

    final path = Path();
    path.moveTo(start.dx, start.dy);

    const waveWidth = 4.0;
    const waveHeight = 1.5;
    final count = (width / waveWidth).floor();

    for (int i = 0; i < count; i++) {
      path.relativeQuadraticBezierTo(
        waveWidth / 4,
        (i % 2 == 0) ? -waveHeight : waveHeight,
        waveWidth / 2,
        0,
      );
      path.relativeQuadraticBezierTo(
        waveWidth / 4,
        (i % 2 == 0) ? waveHeight : -waveHeight,
        waveWidth / 2,
        0,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DiagnosticPainter oldDelegate) {
    return oldDelegate.diagnostics != diagnostics || oldDelegate.notifier != notifier;
  }
}
