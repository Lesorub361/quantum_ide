import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

class EditorMinimap extends StatefulWidget {
  final CodeLineEditingController controller;
  final ScrollController? scrollController;
  final double width;
  final Color backgroundColor;
  final Color viewportColor;

  const EditorMinimap({
    super.key,
    required this.controller,
    this.scrollController,
    this.width = 80,
    this.backgroundColor = const Color(0xFF1A1D27),
    this.viewportColor = const Color(0x30FFFFFF),
  });

  @override
  State<EditorMinimap> createState() => _EditorMinimapState();
}

class _EditorMinimapState extends State<EditorMinimap> {
  Timer? _debounce;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(EditorMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() => _revision++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final codeLines = widget.controller.codeLines;
    final totalLines = codeLines.length;

    if (totalLines == 0) {
      return const SizedBox.shrink();
    }

    var maxLineLength = 20;
    final sampleStep = max(1, totalLines ~/ 200);
    for (int i = 0; i < totalLines; i += sampleStep) {
      final len = codeLines[i].length;
      if (len > maxLineLength) maxLineLength = len;
    }
    maxLineLength = maxLineLength.clamp(20, 200);

    final lineHeight = max(1.5, widget.width / maxLineLength);
    final totalHeight = totalLines * lineHeight;

    final selection = widget.controller.selection;
    final currentLine = selection.isCollapsed ? selection.start.index : -1;

    final viewportTop = currentLine >= 0
        ? (currentLine * lineHeight)
            .clamp(0.0, max(0.0, totalHeight - 20))
            .toDouble()
        : 0.0;

    return Container(
      width: widget.width,
      color: widget.backgroundColor,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: widget.scrollController,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(widget.width, totalHeight),
                painter: _MinimapPainter(
                  codeLines: codeLines,
                  lineHeight: lineHeight,
                  currentLine: currentLine,
                  revision: _revision,
                ),
              ),
            ),
          ),
          if (currentLine >= 0)
            Positioned(
              top: viewportTop,
              left: 0,
              right: 0,
              height: 20,
              child: Container(
                color: widget.viewportColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final CodeLines codeLines;
  final double lineHeight;
  final int currentLine;
  final int revision;

  _MinimapPainter({
    required this.codeLines,
    required this.lineHeight,
    required this.currentLine,
    required this.revision,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final total = codeLines.length;
    final stride = max(1, total ~/ 600);
    final rectHeight = max(lineHeight * stride - 0.5, 0.5);

    for (int i = 0; i < total; i += stride) {
      final line = codeLines[i].text;
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) continue;

      final y = i * lineHeight;
      final indent = line.length - trimmed.length;
      final contentLength = trimmed.trimRight().length;

      final indentWidth = indent * 0.5;
      final contentWidth = max(1.0, contentLength * 0.3);

      Color lineColor = Colors.white.withValues(alpha: 0.3);

      if (trimmed.startsWith('//') ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('/*')) {
        lineColor = Colors.green.withValues(alpha: 0.4);
      } else if (trimmed.startsWith('import ') ||
          trimmed.startsWith('from ') ||
          trimmed.startsWith('use ')) {
        lineColor = Colors.purpleAccent.withValues(alpha: 0.5);
      } else if (trimmed.startsWith('class ') ||
          trimmed.startsWith('struct ') ||
          trimmed.startsWith('fn ') ||
          trimmed.startsWith('def ') ||
          trimmed.startsWith('function ')) {
        lineColor = Colors.cyanAccent.withValues(alpha: 0.6);
      } else if (trimmed.startsWith('return ') || trimmed.startsWith('yield ')) {
        lineColor = Colors.orangeAccent.withValues(alpha: 0.5);
      } else if (trimmed.contains('=')) {
        lineColor = Colors.blueAccent.withValues(alpha: 0.35);
      }

      if (i == currentLine) {
        lineColor = Colors.white.withValues(alpha: 0.85);
      }

      paint.color = lineColor;
      canvas.drawRect(
        Rect.fromLTWH(
          indentWidth,
          y,
          min(contentWidth, size.width - indentWidth),
          rectHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.currentLine != currentLine;
  }
}
