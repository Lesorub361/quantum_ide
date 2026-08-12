import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xt;

/// Bridge to native Android terminal selection overlay via MethodChannel.
class NativeTerminalSelectionBridge {
  static const MethodChannel _channel = MethodChannel('com.example.quantum_ide/selection');

  /// Callbacks from native
  Function(int start, int end)? onSelectionChanged;
  VoidCallback? onCopy;
  VoidCallback? onSelectAll;
  VoidCallback? onActionModeDestroyed;

  bool _listening = false;

  void startListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler(_onMethodCall);
  }

  void stopListening() {
    if (!_listening) return;
    _listening = false;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSelectionChanged':
        final args = call.arguments as Map;
        final start = args['start'] as int;
        final end = args['end'] as int;
        onSelectionChanged?.call(start, end);
        break;
      case 'onCopy':
        onCopy?.call();
        break;
      case 'onSelectAll':
        onSelectAll?.call();
        break;
      case 'onActionModeDestroyed':
        onActionModeDestroyed?.call();
        break;
    }
  }

  /// Show the native selection overlay.
  /// [text] is the full text to put in the overlay.
  /// [selectionStart] and [selectionEnd] are character indices in [text].
  /// [rect] is the global rect of the terminal text area in logical pixels.
  /// [fontSize] and [lineHeight] are in logical pixels (dp).
  /// [fontFamily] is the font family name.
  Future<void> show({
    required String text,
    required int selectionStart,
    required int selectionEnd,
    required Rect rect,
    required double fontSize,
    required double lineHeight,
    required String fontFamily,
  }) async {
    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    await _channel.invokeMethod('show', {
      'args': {
        'text': text,
        'start': selectionStart,
        'end': selectionEnd,
        'left': (rect.left * dpr).round(),
        'top': (rect.top * dpr).round(),
        'width': (rect.width * dpr).round(),
        'height': (rect.height * dpr).round(),
        'fontSizePx': fontSize * dpr,
        'lineHeightPx': lineHeight * dpr,
        'fontFamily': fontFamily,
      },
    });
  }

  Future<void> hide() async {
    await _channel.invokeMethod('hide', null);
  }

  /// Update only the overlay position/size (in logical pixels). Used while the
  /// overlay is already active so we follow scrolling without resetting the
  /// user's active selection/handles.
  Future<void> updatePosition(Rect rect) async {
    final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    await _channel.invokeMethod('updatePosition', {
      'args': {
        'left': (rect.left * dpr).round(),
        'top': (rect.top * dpr).round(),
        'width': (rect.width * dpr).round(),
        'height': (rect.height * dpr).round(),
      },
    });
  }

  Future<void> updateSelection(int start, int end) async {
    // Not implemented - native handles selection internally
    // Could be used if we need to programmatically set selection
  }
}

/// Maps between terminal buffer cell coordinates and character indices in the
/// native overlay text (which is built from visible lines).
class BufferTextMapper {
  final List<xt.BufferLine> _visibleLines;
  final int _firstVisibleLine;
  final List<int> _lineStarts; // character index where each visible line starts
  final String _fullText;

  BufferTextMapper({
    required xt.Terminal terminal,
    required int firstVisibleLine,
    required int lastVisibleLine,
  }) : _firstVisibleLine = firstVisibleLine,
       _visibleLines = _extractVisibleLines(terminal, firstVisibleLine, lastVisibleLine),
       _lineStarts = _computeLineStarts(terminal, firstVisibleLine, lastVisibleLine),
       _fullText = _buildFullText(terminal, firstVisibleLine, lastVisibleLine);

  static List<xt.BufferLine> _extractVisibleLines(
      xt.Terminal terminal, int first, int last) {
    final lines = <xt.BufferLine>[];
    for (var i = first; i <= last; i++) {
      lines.add(terminal.buffer.lines[i]);
    }
    return lines;
  }

  static List<int> _computeLineStarts(
      xt.Terminal terminal, int first, int last) {
    final starts = <int>[];
    final text = StringBuffer();
    for (var i = first; i <= last; i++) {
      starts.add(text.length);
      text.write(terminal.buffer.lines[i].getText());
      text.write('\n');
    }
    return starts;
  }

  static String _buildFullText(
      xt.Terminal terminal, int first, int last) {
    final text = StringBuffer();
    for (var i = first; i <= last; i++) {
      text.write(terminal.buffer.lines[i].getText());
      text.write('\n');
    }
    return text.toString();
  }

  String get fullText => _fullText;

  int get visibleLineCount => _visibleLines.length;

  /// Get character index in the overlay text for a given cell.
  int charIndexForCell(xt.CellOffset cell) {
    final lineIdx = cell.y - _firstVisibleLine;
    if (lineIdx < 0 || lineIdx >= _visibleLines.length) return -1;
    final base = _lineStarts[lineIdx];
    final line = _visibleLines[lineIdx];
    // line.getText(0, col) returns the text before column col
    return base + line.getText(0, cell.x).length;
  }

  /// Get cell for a given character index in the overlay text.
  xt.CellOffset? cellForCharIndex(int charIndex) {
    // Find which visible line this char index falls in
    int lineIdx = _visibleLines.length - 1;
    for (var i = 0; i < _lineStarts.length; i++) {
      if (i + 1 < _lineStarts.length && charIndex >= _lineStarts[i + 1]) {
        lineIdx = i + 1;
      } else if (charIndex < _lineStarts[i]) {
        lineIdx = i - 1;
        break;
      } else {
        lineIdx = i;
        break;
      }
    }
    lineIdx = lineIdx.clamp(0, _visibleLines.length - 1);

    final base = _lineStarts[lineIdx];
    final offset = charIndex - base;
    if (offset < 0) return xt.CellOffset(0, _firstVisibleLine + lineIdx);

    final line = _visibleLines[lineIdx];
    int col = 0;
    int count = 0;
    while (col < line.length && count < offset) {
      final width = line.getWidth(col);
      count++;
      col += width;
    }
    return xt.CellOffset(col.clamp(0, line.length - 1), _firstVisibleLine + lineIdx);
  }
}