import 'dart:ui';

/// A transient visual cell painted over the terminal buffer without mutating it.
///
/// Rows are absolute buffer rows, matching `terminal.buffer.absoluteCursorY`.
/// Columns are zero-based viewport columns.
class TerminalCellOverlay {
  const TerminalCellOverlay({
    required this.row,
    required this.column,
    required this.text,
    this.foreground,
    this.background,
    this.opacity = 1,
    this.erase = false,
  });

  final int row;
  final int column;
  final String text;
  final Color? foreground;
  final Color? background;
  final double opacity;
  final bool erase;
}
