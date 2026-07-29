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
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final lines = text.split('\n');
    final totalLines = lines.length;

    if (totalLines == 0) {
      return const SizedBox.shrink();
    }

    final maxLineLength = lines.map((l) => l.length).fold(0, (a, b) => max(a, b)).clamp(20, 200);
    final lineHeight = max(1.5, widget.width / maxLineLength);
    final totalHeight = totalLines * lineHeight;

    final selection = widget.controller.selection;
    final currentLine = selection.isCollapsed ? selection.start.index : -1;

    final viewportTop = currentLine >= 0 
        ? (currentLine * lineHeight).clamp(0.0, max(0.0, totalHeight - 20)).toDouble()
        : 0.0;

    return Container(
      width: widget.width,
      color: widget.backgroundColor,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: widget.scrollController,
            child: CustomPaint(
              size: Size(widget.width, totalHeight),
              painter: _MinimapPainter(
                lines: lines,
                lineHeight: lineHeight,
                currentLine: currentLine,
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
  final List<String> lines;
  final double lineHeight;
  final int currentLine;

  _MinimapPainter({
    required this.lines,
    required this.lineHeight,
    required this.currentLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;

      final y = i * lineHeight;
      final indent = line.length - line.trimLeft().length;
      final contentLength = line.trim().length;

      final indentWidth = indent * 0.5;
      final contentWidth = max(1.0, contentLength * 0.3);

      Color lineColor = Colors.white.withValues(alpha: 0.3);

      if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('#') || line.trimLeft().startsWith('/*')) {
        lineColor = Colors.green.withValues(alpha: 0.4);
      } else if (line.trimLeft().startsWith('import ') || line.trimLeft().startsWith('from ') || line.trimLeft().startsWith('use ')) {
        lineColor = Colors.purpleAccent.withValues(alpha: 0.5);
      } else if (line.trimLeft().startsWith('class ') || line.trimLeft().startsWith('struct ') || line.trimLeft().startsWith('fn ') || line.trimLeft().startsWith('def ') || line.trimLeft().startsWith('function ')) {
        lineColor = Colors.cyanAccent.withValues(alpha: 0.6);
      } else if (line.trimLeft().startsWith('return ') || line.trimLeft().startsWith('yield ')) {
        lineColor = Colors.orangeAccent.withValues(alpha: 0.5);
      } else if (line.contains('=') && !line.trimLeft().startsWith('//')) {
        lineColor = Colors.blueAccent.withValues(alpha: 0.35);
      }

      if (i == currentLine) {
        lineColor = Colors.white.withValues(alpha: 0.8);
      }

      paint.color = lineColor;
      canvas.drawRect(
        Rect.fromLTWH(indentWidth, y, min(contentWidth, size.width - indentWidth), max(lineHeight - 0.5, 0.5)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.lineHeight != lineHeight ||
        oldDelegate.currentLine != currentLine;
  }
}
