import 'dart:math' show max, min;

import 'package:conduit_vt/src/core/buffer/cell_offset.dart';
import 'package:conduit_vt/src/core/buffer/line.dart';
import 'package:conduit_vt/src/core/buffer/range_line.dart';
import 'package:conduit_vt/src/core/buffer/range.dart';
import 'package:conduit_vt/src/core/charset.dart';
import 'package:conduit_vt/src/core/cursor.dart';
import 'package:conduit_vt/src/core/reflow.dart';
import 'package:conduit_vt/src/core/state.dart';
import 'package:conduit_vt/src/utils/circular_buffer.dart';
import 'package:conduit_vt/src/utils/unicode_v11.dart';

class Buffer {
  final TerminalState terminal;

  final int maxLines;

  final bool isAltBuffer;

  /// Characters that break selection when calling [getWordBoundary]. If null,
  /// defaults to [defaultWordSeparators].
  final Set<int>? wordSeparators;

  Buffer(
    this.terminal, {
    required this.maxLines,
    required this.isAltBuffer,
    this.wordSeparators,
  }) {
    for (int i = 0; i < terminal.viewHeight; i++) {
      lines.push(_newEmptyLine());
    }

    resetVerticalMargins();
  }

  int _cursorX = 0;

  int _cursorY = 0;

  late int _marginTop;

  late int _marginBottom;

  var _savedCursorX = 0;

  var _savedCursorY = 0;

  final _savedCursorStyle = CursorStyle();

  final charset = Charset();

  /// Width of the viewport in columns. Also the index of the last column.
  int get viewWidth => terminal.viewWidth;

  /// Height of the viewport in rows. Also the index of the last line.
  int get viewHeight => terminal.viewHeight;

  /// lines of the buffer. the length of [lines] should always be equal or
  /// greater than [viewHeight].
  late final lines = IndexAwareCircularBuffer<BufferLine>(maxLines);

  /// Total number of lines in the buffer. Always equal or greater than
  /// [viewHeight].
  int get height => lines.length;

  /// Horizontal position of the cursor relative to the top-left cornor of the
  /// screen, starting from 0.
  int get cursorX => _cursorX.clamp(0, terminal.viewWidth - 1);

  /// Vertical position of the cursor relative to the top-left cornor of the
  /// screen, starting from 0.
  int get cursorY => _cursorY;

  /// Index of the first line in the scroll region.
  int get marginTop => _marginTop;

  /// Index of the last line in the scroll region.
  int get marginBottom => _marginBottom;

  /// The number of lines above the viewport.
  int get scrollBack => height - viewHeight;

  /// Vertical position of the cursor relative to the top of the buffer,
  /// starting from 0.
  int get absoluteCursorY => _cursorY + scrollBack;

  /// Absolute index of the first line in the scroll region.
  int get absoluteMarginTop => _marginTop + scrollBack;

  /// Absolute index of the last line in the scroll region.
  int get absoluteMarginBottom => _marginBottom + scrollBack;

  /// Writes data to the _terminal. Terminal sequences or special characters are
  /// not interpreted and directly added to the buffer.
  ///
  /// See also: [Terminal.write]
  void write(String text) {
    for (var char in text.runes) {
      writeChar(char);
    }
  }

  /// Writes a single character to the _terminal. Escape sequences or special
  /// characters are not interpreted and directly added to the buffer.
  ///
  /// See also: [Terminal.writeChar]
  void writeChar(int codePoint) {
    codePoint = charset.translate(codePoint);

    final cellWidth = unicodeV11.wcwidth(codePoint);
    if (_cursorX >= terminal.viewWidth) {
      index();
      setCursorX(0);
      if (terminal.autoWrapMode) {
        currentLine.isWrapped = true;
      }
    }

    final line = currentLine;
    line.setCell(_cursorX, codePoint, cellWidth, terminal.cursor);

    if (_cursorX < viewWidth) {
      _cursorX++;
    }

    if (cellWidth == 2) {
      writeChar(0);
    }
  }

  /// The line at the current cursor position.
  BufferLine get currentLine {
    return lines[absoluteCursorY];
  }

  void backspace() {
    if (_cursorX == 0 && currentLine.isWrapped) {
      currentLine.isWrapped = false;
      moveCursor(viewWidth - 1, -1);
    } else if (_cursorX == viewWidth) {
      moveCursor(-2, 0);
    } else {
      moveCursor(-1, 0);
    }
  }

  /// Erases the viewport from the cursor position to the end of the buffer,
  /// including the cursor position.
  void eraseDisplayFromCursor() {
    eraseLineFromCursor();

    for (var i = absoluteCursorY + 1; i < height; i++) {
      final line = lines[i];
      line.isWrapped = false;
      line.eraseRange(0, viewWidth, terminal.cursor);
    }
  }

  /// Erases the viewport from the top-left corner to the cursor, including the
  /// cursor.
  void eraseDisplayToCursor() {
    eraseLineToCursor();

    for (var i = 0; i < _cursorY; i++) {
      final line = lines[i + scrollBack];
      line.isWrapped = false;
      line.eraseRange(0, viewWidth, terminal.cursor);
    }
  }

  /// Erases the whole viewport.
  void eraseDisplay() {
    for (var i = 0; i < viewHeight; i++) {
      final line = lines[i + scrollBack];
      line.isWrapped = false;
      line.eraseRange(0, viewWidth, terminal.cursor);
    }
  }

  /// Erases the line from the cursor to the end of the line, including the
  /// cursor position.
  void eraseLineFromCursor() {
    currentLine.isWrapped = false;
    currentLine.eraseRange(_cursorX, viewWidth, terminal.cursor);
  }

  /// Erases the line from the start of the line to the cursor, including the
  /// cursor.
  void eraseLineToCursor() {
    currentLine.isWrapped = false;
    currentLine.eraseRange(0, _cursorX, terminal.cursor);
  }

  /// Erases the line at the current cursor position.
  void eraseLine() {
    currentLine.isWrapped = false;
    currentLine.eraseRange(0, viewWidth, terminal.cursor);
  }

  /// Erases [count] cells starting at the cursor position.
  void eraseChars(int count) {
    final start = _cursorX;
    currentLine.eraseRange(start, start + count, terminal.cursor);
  }

  void scrollDown(int lines) {
    for (var i = absoluteMarginBottom; i >= absoluteMarginTop; i--) {
      if (i >= absoluteMarginTop + lines) {
        this.lines[i] = this.lines[i - lines];
      } else {
        this.lines[i] = _newEmptyLine();
      }
    }
  }

  void scrollUp(int lines) {
    for (var i = absoluteMarginTop; i <= absoluteMarginBottom; i++) {
      if (i <= absoluteMarginBottom - lines) {
        this.lines[i] = this.lines[i + lines];
      } else {
        this.lines[i] = _newEmptyLine();
      }
    }
  }

  /// https://vt100.net/docs/vt100-ug/chapter3.html#IND IND – Index
  ///
  /// ESC D
  ///
  /// [index] causes the active position to move downward one line without
  /// changing the column position. If the active position is at the bottom
  /// margin, a scroll up is performed.
  void index() {
    if (isInVerticalMargin) {
      if (_cursorY == _marginBottom) {
        if (marginTop == 0 && !isAltBuffer) {
          lines.insert(absoluteMarginBottom + 1, _newEmptyLine());
        } else {
          scrollUp(1);
        }
      } else {
        moveCursorY(1);
      }
      return;
    }

    // the cursor is not in the scrollable region
    if (_cursorY >= viewHeight - 1) {
      // we are at the bottom
      if (isAltBuffer) {
        scrollUp(1);
      } else {
        lines.push(_newEmptyLine());
      }
    } else {
      // there're still lines so we simply move cursor down.
      moveCursorY(1);
    }
  }

  void lineFeed() {
    index();
    if (terminal.lineFeedMode) {
      setCursorX(0);
    }
  }

  /// https://terminalguide.namepad.de/seq/a_esc_cm/
  void reverseIndex() {
    if (isInVerticalMargin) {
      if (_cursorY == _marginTop) {
        scrollDown(1);
      } else {
        moveCursorY(-1);
      }
    } else {
      moveCursorY(-1);
    }
  }

  void cursorGoForward() {
    _cursorX = min(_cursorX + 1, viewWidth);
  }

  void setCursorX(int cursorX) {
    _cursorX = cursorX.clamp(0, viewWidth - 1);
  }

  void setCursorY(int cursorY) {
    _cursorY = cursorY.clamp(0, viewHeight - 1);
  }

  void moveCursorX(int offset) {
    setCursorX(_cursorX + offset);
  }

  void moveCursorY(int offset) {
    setCursorY(_cursorY + offset);
  }

  void setCursor(int cursorX, int cursorY) {
    var maxCursorY = viewHeight - 1;

    if (terminal.originMode) {
      cursorY += _marginTop;
      maxCursorY = _marginBottom;
    }

    _cursorX = cursorX.clamp(0, viewWidth - 1);
    _cursorY = cursorY.clamp(0, maxCursorY);
  }

  void moveCursor(int offsetX, int offsetY) {
    final cursorX = _cursorX + offsetX;
    final cursorY = _cursorY + offsetY;
    setCursor(cursorX, cursorY);
  }

  /// Save cursor position, charmap and text attributes.
  void saveCursor() {
    _savedCursorX = _cursorX;
    _savedCursorY = _cursorY;
    _savedCursorStyle.foreground = terminal.cursor.foreground;
    _savedCursorStyle.background = terminal.cursor.background;
    _savedCursorStyle.attrs = terminal.cursor.attrs;
    charset.save();
  }

  /// Restore cursor position, charmap and text attributes.
  void restoreCursor() {
    _cursorX = _savedCursorX;
    _cursorY = _savedCursorY;
    terminal.cursor.foreground = _savedCursorStyle.foreground;
    terminal.cursor.background = _savedCursorStyle.background;
    terminal.cursor.attrs = _savedCursorStyle.attrs;
    charset.restore();
  }

  /// Sets the vertical scrolling margin to [top] and [bottom].
  /// Both values must be between 0 and [viewHeight] - 1.
  void setVerticalMargins(int top, int bottom) {
    _marginTop = top.clamp(0, viewHeight - 1);
    _marginBottom = bottom.clamp(0, viewHeight - 1);

    _marginTop = min(_marginTop, _marginBottom);
    _marginBottom = max(_marginTop, _marginBottom);
  }

  bool get isInVerticalMargin {
    return _cursorY >= _marginTop && _cursorY <= _marginBottom;
  }

  void resetVerticalMargins() {
    setVerticalMargins(0, viewHeight - 1);
  }

  void deleteChars(int count) {
    final start = _cursorX.clamp(0, viewWidth);
    count = min(count, viewWidth - start);
    currentLine.removeCells(start, count, terminal.cursor);
  }

  /// Remove all lines above the top of the viewport.
  void clearScrollback() {
    if (height <= viewHeight) {
      return;
    }

    lines.trimStart(scrollBack);
  }

  /// Clears the viewport and scrollback buffer. Then fill with empty lines.
  void clear() {
    lines.clear();
    for (int i = 0; i < viewHeight; i++) {
      lines.push(_newEmptyLine());
    }
  }

  void insertBlankChars(int count) {
    currentLine.insertCells(_cursorX, count, terminal.cursor);
  }

  void insertLines(int count) {
    if (!isInVerticalMargin) {
      return;
    }

    setCursorX(0);

    // Number of lines from the cursor to the bottom of the scrollable region
    // including the cursor itself.
    final linesBelow = absoluteMarginBottom - absoluteCursorY + 1;

    // Number of empty lines to insert.
    final linesToInsert = min(count, linesBelow);

    // Number of lines to move up.
    final linesToMove = linesBelow - linesToInsert;

    for (var i = 0; i < linesToMove; i++) {
      final index = absoluteMarginBottom - i;
      lines[index] = lines.swap(index - linesToInsert, _newEmptyLine());
    }

    for (var i = linesToMove; i < linesToInsert; i++) {
      lines[absoluteCursorY + i] = _newEmptyLine();
    }
  }

  /// Remove [count] lines starting at the current cursor position. Lines below
  /// the removed lines are shifted up. This only affects the scrollable region.
  /// Lines outside the scrollable region are not affected.
  void deleteLines(int count) {
    if (!isInVerticalMargin) {
      return;
    }

    setCursorX(0);

    count = min(count, absoluteMarginBottom - absoluteCursorY + 1);

    final linesToMove = absoluteMarginBottom - absoluteCursorY + 1 - count;

    for (var i = 0; i < linesToMove; i++) {
      final index = absoluteCursorY + i;
      lines[index] = lines[index + count];
    }

    for (var i = 0; i < count; i++) {
      lines[absoluteMarginBottom - i] = _newEmptyLine();
    }
  }

  void resize(int oldWidth, int oldHeight, int newWidth, int newHeight) {
    final initialAbsCursorY = absoluteCursorY.clamp(0, lines.length - 1);
    final cursorAnchor = lines[initialAbsCursorY].createAnchor(
      _cursorX.clamp(0, oldWidth),
    );

    // Trim trailing blank viewport lines below the cursor before reflow so
    // wrapped lines expand into unused bottom rows instead of pushing top lines
    // into scrollback or desynchronizing cursorY.
    while (lines.length > initialAbsCursorY + 1) {
      final lastLine = lines[lines.length - 1];
      if (!lastLine.isWrapped &&
          lastLine.anchors.isEmpty &&
          lastLine.getTrimmedLength(oldWidth) == 0) {
        lines.pop();
      } else {
        break;
      }
    }

    if (newWidth != oldWidth) {
      if (terminal.reflowEnabled && !isAltBuffer) {
        final reflowResult = reflow(lines, oldWidth, newWidth);

        while (reflowResult.length < newHeight) {
          reflowResult.add(_newEmptyLine(newWidth));
        }

        lines.replaceWith(reflowResult);
      } else {
        lines.forEach((item) => item.resize(newWidth));
        while (lines.length < newHeight) {
          lines.push(_newEmptyLine(newWidth));
        }
      }
    } else {
      while (lines.length < newHeight) {
        lines.push(_newEmptyLine(newWidth));
      }
    }

    var newAbsCursorY = -1;
    final anchoredLine = cursorAnchor.line;
    if (anchoredLine != null) {
      for (var i = lines.length - 1; i >= 0; i--) {
        if (identical(lines[i], anchoredLine)) {
          newAbsCursorY = i;
          break;
        }
      }
    }

    if (newAbsCursorY != -1) {
      // If there are trailing blank lines after the cursor and lines.length > newHeight,
      // pop excess blank lines so the cursor stays at its natural viewport row.
      while (lines.length > newHeight && lines.length > newAbsCursorY + 1) {
        final tail = lines[lines.length - 1];
        if (!tail.isWrapped &&
            tail.anchors.isEmpty &&
            tail.getTrimmedLength(newWidth) == 0) {
          lines.pop();
        } else {
          break;
        }
      }
      final newBaseY = (lines.length - newHeight).clamp(0, lines.length);
      _cursorY = (newAbsCursorY - newBaseY).clamp(0, newHeight - 1);
      _cursorX = cursorAnchor.x.clamp(0, newWidth - 1);
    } else {
      _cursorX = _cursorX.clamp(0, newWidth - 1);
      _cursorY = _cursorY.clamp(0, newHeight - 1);
    }

    cursorAnchor.dispose();
  }

  /// Create a new [CellAnchor] at the specified [x] and [y] coordinates.
  CellAnchor createAnchor(int x, int y) {
    return lines[y].createAnchor(x);
  }

  /// Create a new [CellAnchor] at the specified [x] and [y] coordinates.
  CellAnchor createAnchorFromOffset(CellOffset offset) {
    return lines[offset.y].createAnchor(offset.x);
  }

  CellAnchor createAnchorFromCursor() {
    return createAnchor(cursorX, absoluteCursorY);
  }

  /// Create a new empty [BufferLine] with the current [viewWidth] if [width]
  /// is not specified.
  BufferLine _newEmptyLine([int? width]) {
    final line = BufferLine(width ?? viewWidth);
    return line;
  }

  static final defaultWordSeparators = <int>{
    0,
    r' '.codeUnitAt(0),
    r'	'.codeUnitAt(0),
    r'"'.codeUnitAt(0),
    r"'".codeUnitAt(0),
    r'('.codeUnitAt(0),
    r')'.codeUnitAt(0),
    r'['.codeUnitAt(0),
    r']'.codeUnitAt(0),
    r'{'.codeUnitAt(0),
    r'}'.codeUnitAt(0),
    r'<'.codeUnitAt(0),
    r'>'.codeUnitAt(0),
    r','.codeUnitAt(0),
    r';'.codeUnitAt(0),
  };

  static bool _isUrlCodePoint(int code) {
    if (code <= 0x20 || code >= 0x7f) return false;
    switch (code) {
      case 0x22: // "
      case 0x27: // '
      case 0x3c: // <
      case 0x3e: // >
      case 0x60: // `
      case 0x28: // (
      case 0x29: // )
      case 0x5b: // [
      case 0x5d: // ]
      case 0x7b: // {
      case 0x7d: // }
        return false;
      default:
        return true;
    }
  }

  bool _isSoftUrlContinuation(int prevRow, int nextRow) {
    if (prevRow < 0 || nextRow >= lines.length) return false;
    final prevLine = lines[prevRow];
    final nextLine = lines[nextRow];
    if (nextLine.isWrapped) return true;

    final prevLen = prevLine.getTrimmedLength(viewWidth);
    final nextLen = nextLine.getTrimmedLength(viewWidth);
    if (prevLen < (viewWidth - 6).clamp(1, viewWidth) || nextLen == 0) {
      return false;
    }
    final lastChar = prevLine.getCodePoint(prevLen - 1);
    final firstChar = nextLine.getCodePoint(0);
    return _isUrlCodePoint(lastChar) && _isUrlCodePoint(firstChar);
  }

  static final RegExp _bufferUrlRegex = RegExp(
    r'https?:\/\/[^\s<>\"\x27`\)\]\x00-\x1f]+',
    caseSensitive: false,
  );

  /// Finds the multi-line [BufferRangeLine] of a URL at [position], if any.
  BufferRangeLine? findUrlRangeAt(CellOffset position) {
    if (position.y < 0 || position.y >= lines.length) return null;

    var startRow = position.y;
    while (startRow > 0 &&
        position.y - startRow < 14 &&
        _isSoftUrlContinuation(startRow - 1, startRow)) {
      startRow--;
    }

    var endRow = position.y;
    while (endRow + 1 < lines.length &&
        endRow - position.y < 14 &&
        _isSoftUrlContinuation(endRow, endRow + 1)) {
      endRow++;
    }

    final combined = StringBuffer();
    final offsets = <CellOffset>[];

    for (var r = startRow; r <= endRow; r++) {
      final line = lines[r];
      final len = line.getTrimmedLength(viewWidth);
      final maxCol = len > 0 ? len : 0;
      for (var c = 0; c < maxCol; c++) {
        final cp = line.getCodePoint(c);
        combined.writeCharCode(cp == 0 ? 0x20 : cp);
        offsets.add(CellOffset(c, r));
      }
    }

    if (offsets.isEmpty) return null;
    final text = combined.toString();

    for (final match in _bufferUrlRegex.allMatches(text)) {
      var mStart = match.start;
      var mEnd = match.end;
      while (mEnd > mStart) {
        final ch = text.codeUnitAt(mEnd - 1);
        if (ch == 0x2e || // .
            ch == 0x2c || // ,
            ch == 0x3b || // ;
            ch == 0x3a || // :
            ch == 0x29 || // )
            ch == 0x5d) {
          mEnd--;
        } else {
          break;
        }
      }
      if (mEnd <= mStart) continue;

      bool hitsPosition = false;
      for (var idx = mStart; idx < mEnd; idx++) {
        final cell = offsets[idx];
        if (cell.y == position.y && (cell.x - position.x).abs() <= 1) {
          hitsPosition = true;
          break;
        }
      }

      if (hitsPosition) {
        final first = offsets[mStart];
        final last = offsets[mEnd - 1];
        return BufferRangeLine(
          first,
          CellOffset((last.x + 1).clamp(0, viewWidth), last.y),
        );
      }
    }

    return null;
  }

  /// Extracts the full unbroken URL string at [position], stitching wrapped lines.
  String? getUrlAt(CellOffset position) {
    final range = findUrlRangeAt(position);
    if (range == null) return null;
    final raw = getText(range).replaceAll('\n', '').replaceAll('\r', '').trim();
    return raw.isEmpty ? null : raw;
  }

  BufferRangeLine? getWordBoundary(CellOffset position) {
    if (position.y < 0 || position.y >= lines.length) {
      return null;
    }

    // 1. If the user tapped or long-pressed on a URL (including multi-line wrapped URLs),
    // select the entire URL automatically.
    final urlRange = findUrlRangeAt(position);
    if (urlRange != null) {
      return urlRange;
    }

    final separators = wordSeparators ?? defaultWordSeparators;
    final line = lines[position.y];
    final clampedX = position.x.clamp(0, (viewWidth - 1).clamp(0, viewWidth));
    var start = clampedX;
    var end = clampedX;

    do {
      if (start == 0) {
        break;
      }
      final char = line.getCodePoint(start - 1);
      if (separators.contains(char)) {
        break;
      }
      start--;
    } while (true);

    do {
      if (end >= viewWidth) {
        break;
      }
      final char = line.getCodePoint(end);
      if (separators.contains(char)) {
        break;
      }
      end++;
    } while (true);

    if (start == end) {
      return BufferRangeLine(
        CellOffset(clampedX, position.y),
        CellOffset((clampedX + 1).clamp(0, viewWidth), position.y),
      );
    }

    return BufferRangeLine(
      CellOffset(start, position.y),
      CellOffset(end, position.y),
    );
  }

  /// Get the plain text content of the buffer including the scrollback.
  /// Accepts an optional [range] to get a specific part of the buffer.
  String getText([BufferRange? range]) {
    range ??= BufferRangeLine(
      CellOffset(0, 0),
      CellOffset(viewWidth - 1, height - 1),
    );

    range = range.normalized;

    final builder = StringBuffer();
    int? prevLineIndex;

    for (var segment in range.toSegments()) {
      if (segment.line < 0 || segment.line >= height) {
        continue;
      }
      final line = lines[segment.line];
      final isContinuation = prevLineIndex != null &&
          segment.line == prevLineIndex + 1 &&
          (line.isWrapped || _isSoftUrlContinuation(prevLineIndex, segment.line));
      if (!(segment.line == range.begin.y ||
          segment.line == 0 ||
          isContinuation)) {
        builder.write("\n");
      }
      builder.write(line.getText(segment.start, segment.end));
      prevLineIndex = segment.line;
    }

    return builder.toString();
  }

  /// Returns a debug representation of the buffer.
  @override
  String toString() {
    final builder = StringBuffer();
    final lineNumberLength = lines.length.toString().length;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      builder.write('${i.toString().padLeft(lineNumberLength)}: |${lines[i]}|');

      if (line.isWrapped) {
        builder.write(' (⏎)');
      }

      builder.write('\n');
    }

    return builder.toString();
  }
}
