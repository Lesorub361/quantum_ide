import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import '../../../../core/services/diff_service.dart';

class DiffGutterIndicator extends StatelessWidget {
  final CodeLineEditingController controller;
  final List<DiffMarker> markers;
  final CodeIndicatorValueNotifier? notifier;

  const DiffGutterIndicator({
    super.key,
    required this.controller,
    required this.markers,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DiffPainter(
        notifier: notifier,
        markers: markers,
      ),
      size: Size.zero,
    );
  }
}

class _DiffPainter extends CustomPainter {
  final CodeIndicatorValueNotifier? notifier;
  final List<DiffMarker> markers;

  _DiffPainter({required this.notifier, required this.markers}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final val = notifier?.value;
    if (val == null) return;

    for (final paragraph in val.paragraphs) {
      final lineIndex = paragraph.index;
      final marker = markers.firstWhere(
        (m) => m.line == lineIndex,
        orElse: () => DiffMarker(line: -1, type: DiffType.added), // Dummy
      );

      if (marker.line != -1) {
        final paint = Paint();
        switch (marker.type) {
          case DiffType.added:
            paint.color = Colors.greenAccent.withValues(alpha: 0.6);
            break;
          case DiffType.removed:
            paint.color = Colors.redAccent.withValues(alpha: 0.6);
            break;
          case DiffType.modified:
            paint.color = Colors.orangeAccent.withValues(alpha: 0.6);
            break;
        }

        final rect = Rect.fromLTWH(
          0,
          paragraph.offset.dy,
          3, 
          paragraph.paragraph.height,
        );
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DiffPainter oldDelegate) {
    return oldDelegate.markers != markers || oldDelegate.notifier != notifier;
  }
}
