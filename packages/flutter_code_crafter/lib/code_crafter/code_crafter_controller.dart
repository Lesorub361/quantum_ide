import '../utils/utils.dart';
import '../utils/shared.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart';

class CodeCrafterController extends TextEditingController {
  VoidCallback? manualAiCompletion;

  Mode? _language;

  final textKey = GlobalKey();

  bool Function(int) foldAt = (_) {
    return false;
  };

  /// The language mode used for syntax highlighting.
  ///
  /// This is a [Mode] object from the [highlight](https://pub.dev/packages/highlight) package.
  Mode? get language => _language;

  String? _langId;
  // int? _lastCursorPosition;
  final Map<int, Set<int>> _highlightIndex = {};
  TextStyle? _highlightStyle;

  set language(Mode? language) {
    if (language == _language) return;
    if (language != null) {
      _langId = language.hashCode.toString();
      highlight.registerLanguage(_langId!, language);
    }
    _language = language;
    notifyListeners();
  }

  Map<String, TextStyle> get editorTheme => Shared().theme;
  TextStyle? get textStyle => Shared().textStyle;

  @override
  set value(TextEditingValue newValue) {
    final TextEditingValue oldValue = super.value;
    const pairs = {'(': ')', '{': '}', '[': ']', '"': '"', "'": "'"};
    final openers = pairs.keys.toSet();
    final closers = pairs.values.toSet();

    if (newValue.text.length == oldValue.text.length + 1 &&
        newValue.selection.baseOffset > 0) {
      final cursorPos = newValue.selection.baseOffset;
      final inserted = newValue.text[cursorPos - 1];

      if (openers.contains(inserted)) {
        final closing = pairs[inserted]!;
        final before = newValue.text.substring(0, cursorPos);
        final after = newValue.text.substring(cursorPos);

        super.value = TextEditingValue(
          text: '$before$closing$after',
          selection: TextSelection.collapsed(offset: cursorPos),
        );
        return;
      }

      if (closers.contains(inserted)) {
        final oldCursorPos = oldValue.selection.baseOffset;
        if (oldCursorPos < oldValue.text.length) {
          final charAfterCursor = oldValue.text[oldCursorPos];
          if (charAfterCursor == inserted) {
            super.value = TextEditingValue(
              text: oldValue.text,
              selection: TextSelection.collapsed(offset: oldCursorPos + 1),
            );
            return;
          }
        }
      }
    }

    if (newValue.text.length > oldValue.text.length &&
        newValue.selection.baseOffset > 0 &&
        newValue.text
            .substring(0, newValue.selection.baseOffset)
            .endsWith('\n')) {
      final cursorPosition = newValue.selection.baseOffset;
      final textBeforeCursor = newValue.text.substring(0, cursorPosition);
      final textAfterCursor = newValue.text.substring(cursorPosition);

      final lines = textBeforeCursor.split('\n');
      if (lines.length < 2) {
        super.value = newValue;
        return;
      }
      final prevLine = lines[lines.length - 2];
      final indentMatch = RegExp(r'^\s*').firstMatch(prevLine);
      final prevIndent = indentMatch?.group(0) ?? '';
      final shouldIndent = RegExp(r'[:{[(]\s*$').hasMatch(prevLine);
      final extraIndent = shouldIndent ? ' ' * Shared().tabSize : '';
      final indent = prevIndent + extraIndent;
      final openToClose = {'{': '}', '(': ')', '[': ']'};
      final trimmedPrev = prevLine.trimRight();
      final lastChar = trimmedPrev.isNotEmpty
          ? trimmedPrev[trimmedPrev.length - 1]
          : null;
      final trimmedNext = textAfterCursor.trimLeft();
      final nextChar = trimmedNext.isNotEmpty ? trimmedNext[0] : null;
      final isBracketOpen = openToClose.containsKey(lastChar);
      final isNextClosing = isBracketOpen && openToClose[lastChar] == nextChar;
      String newText;
      int newOffset;
      if (isBracketOpen && isNextClosing) {
        newText = '$textBeforeCursor$indent\n$prevIndent$textAfterCursor';
        newOffset = cursorPosition + indent.length;
      } else {
        newText = '$textBeforeCursor$indent$textAfterCursor';
        newOffset = cursorPosition + indent.length;
      }

      super.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newOffset),
      );
      return;
    }

    super.value = newValue;
  }

  void setFoldAtCallback(bool Function(int index) callback) {
    foldAt = callback;
  }

  Set<int> _findUnmatchedBrackets(String text) {
    final stack = <int>[];
    final unmatched = <int>{};
    const pairs = {'(': ')', '{': '}', '[': ']', "'": "'", '"': '"'};
    const openers = {'(', '{', '[', "'", '"'};
    const closers = {')', '}', ']', "'", '"'};
    String? currentStringQuote;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (char == '"' || char == "'") {
        if (currentStringQuote == null) {
          currentStringQuote = char;
        } else if (currentStringQuote == char) {
          currentStringQuote = null;
        }
        continue;
      }

      if (currentStringQuote != null) continue;

      if (openers.contains(char)) {
        stack.add(i);
      } else if (closers.contains(char)) {
        if (stack.isEmpty) {
          unmatched.add(i);
        } else {
          final lastOpen = stack.last;
          final openChar = text[lastOpen];
          if (pairs[openChar] == char) {
            stack.removeLast();
          } else {
            unmatched.add(i);
          }
        }
      }
    }

    unmatched.addAll(stack);
    return unmatched;
  }

  int? _findMatchingBracket(String text, int pos) {
    const Map<String, String> pairs = {
      '(': ')',
      '{': '}',
      '[': ']',
      ')': '(',
      '}': '{',
      ']': '[',
    };
    const String openers = '({[';

    if (pos < 0 || pos >= text.length) return null;

    final char = text[pos];
    if (!pairs.containsKey(char)) return null;

    final match = pairs[char]!;
    final isForward = openers.contains(char);

    int depth = 0;
    if (isForward) {
      for (int i = pos + 1; i < text.length; i++) {
        if (text[i] == char) depth++;
        if (text[i] == match) {
          if (depth == 0) return i;
          depth--;
        }
      }
    } else {
      for (int i = pos - 1; i >= 0; i--) {
        if (text[i] == char) depth++;
        if (text[i] == match) {
          if (depth == 0) return i;
          depth--;
        }
      }
    }
    return null;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    TextStyle baseStyle = TextStyle(
      color: editorTheme['root']?.color,
      height: 1.5,
    );

    if (textStyle != null) {
      baseStyle = baseStyle.merge(textStyle);
    }

    final int cursorPosition = selection.baseOffset;
    int? bracket1, bracket2;

    if (Shared().aiResponse != null &&
        text.isNotEmpty &&
        Shared().aiResponse!.isNotEmpty) {
      final String textBeforeCursor = text.substring(0, cursorPosition);
      final String textAfterCursor = text.substring(cursorPosition);

      final bool atLineEnd =
          textAfterCursor.isEmpty ||
          textAfterCursor.startsWith('\n') ||
          textAfterCursor.trim().isEmpty;

      if (!atLineEnd) {
        return TextSpan(text: text, style: baseStyle);
      }
      final String lastTypedChar = textBeforeCursor.isNotEmpty
          ? textBeforeCursor[textBeforeCursor.length - 1].replaceAll("\n", '')
          : '';
      final List<Node>? beforeCursorNodes = highlight
          .parse(textBeforeCursor, language: _langId)
          .nodes;

      if (Shared().lastCursorPosition != null &&
          cursorPosition != Shared().lastCursorPosition) {
        final movedCursor =
            (cursorPosition != Shared().lastCursorPosition! + 1);
        final mismatch =
            lastTypedChar.trim().isNotEmpty &&
            (Shared().aiResponse == null ||
                Shared().aiResponse!.isEmpty ||
                Shared().aiResponse![0] != lastTypedChar);
        if (movedCursor || mismatch) {
          Shared().aiResponse = null;
        }
      }

      if (Shared().aiResponse != null &&
          Shared().aiResponse!.isNotEmpty &&
          Shared().aiResponse![0] == lastTypedChar) {
        Shared().aiResponse = Shared().aiResponse!.substring(1);
      }

      Shared().lastCursorPosition = cursorPosition;

      TextSpan aiOverlay = TextSpan(
        text: Shared().aiResponse,
        style:
            Shared().aiOverlayStyle ??
            TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
      final List<Node>? afterCursorNodes = highlight
          .parse(textAfterCursor, language: _langId)
          .nodes;

      if (beforeCursorNodes != null) {
        if (cursorPosition != selection.baseOffset) {
          Shared().aiResponse = null;
        }
        return TextSpan(
          style: baseStyle,
          children: [
            ..._convert(beforeCursorNodes),
            aiOverlay,
            ..._convert(afterCursorNodes ?? <Node>[]),
          ],
        );
      }
    }

    final List<String> lines = text.isNotEmpty ? text.split("\n") : [];

    if (cursorPosition >= 0 && cursorPosition <= text.length) {
      final String? before = cursorPosition > 0
          ? text[cursorPosition - 1]
          : null;
      final String? after = cursorPosition < text.length
          ? text[cursorPosition]
          : null;
      final int? pos = (before != null && '{}[]()'.contains(before))
          ? cursorPosition - 1
          : (after != null && '{}[]()'.contains(after))
          ? cursorPosition
          : null;

      if (pos != null) {
        final match = _findMatchingBracket(text, pos);
        if (match != null) {
          bracket1 = pos;
          bracket2 = match;
        }
      }
    }

    final List<FoldRange> foldedRanges = Shared().lineStates.value
        .where((line) => line.foldRange?.isFolded == true)
        .map((line) => line.foldRange!)
        .toList();

    foldedRanges.sort((a, b) => a.startLine.compareTo(b.startLine));
    final filteredFolds = <FoldRange>[];
    for (final FoldRange fold in foldedRanges) {
      bool isNested = filteredFolds.any(
        (parent) =>
            fold.startLine >= parent.startLine &&
            fold.endLine <= parent.endLine,
      );
      if (!isNested) filteredFolds.add(fold);
    }
    filteredFolds.sort((a, b) => b.startLine.compareTo(a.startLine));

    for (final fold in filteredFolds) {
      int start = fold.startLine - 1;
      int end = fold.endLine;
      if (start >= 0 && end <= lines.length && start < end) {
        lines[start] =
            "${lines[start]}...${'\u200D' * ((lines.sublist(start + 1, end).join('\n').length) - 2)}";
        lines.removeRange(start + 1, end);
      }
    }

    final newText = lines.join('\n');

    final List<Node>? nodes = highlight.parse(newText, language: _langId).nodes;
    final Set<int> unmatchedBrackets = _findUnmatchedBrackets(text);
    if (nodes != null && editorTheme.isNotEmpty) {
      return TextSpan(
        style: baseStyle,
        children: _convert(nodes, 0, bracket1, bracket2, unmatchedBrackets),
      );
    } else {
      return TextSpan(text: newText, style: textStyle);
    }
  }

  List<TextSpan> _convert(
    List<Node> nodes, [
    int startOffset = 0,
    int? b1,
    int? b2,
    Set<int> unmatched = const {},
  ]) {
    List<TextSpan> spans = [];
    int offset = startOffset;

    for (final node in nodes) {
      if (node.value != null) {
        final nodeLines = node.value!.split('\n');
        for (int lineIdx = 0; lineIdx < nodeLines.length; lineIdx++) {
          final line = nodeLines[lineIdx];
          final startOfLineOffset = offset;
          final lineChars = line.characters;
          offset +=
              lineChars.length + (lineIdx == nodeLines.length - 1 ? 0 : 1);

          final match = RegExp(r'^(\s*)').firstMatch(line);
          final leading = match?.group(0) ?? '';
          final indentLen = leading.length;
          final indentLvl = indentLen ~/ Shared().tabSize;
          final Set<int> guideCols = {
            for (int k = 0; k < indentLvl; k++) k * Shared().tabSize,
          };

          String accumulatedText = '';
          TextStyle? currentStyle;

          for (int col = 0; col < lineChars.length; col++) {
            final globalIdx = startOfLineOffset + col;
            String ch = lineChars.elementAt(col);
            if (ch == ' ' && guideCols.contains(col)) ch = '│';

            final bool isMatch = globalIdx == b1 || globalIdx == b2;
            final bool isUnmatched = unmatched.contains(globalIdx);

            TextStyle? charStyle = editorTheme[node.className ?? ''];

            if (ch == '│') {
              charStyle = TextStyle(
                color: Shared().enableRulerLines
                    ? Colors.grey
                    : Colors.transparent,
                fontSize: Shared().textStyle?.fontSize ?? 14,
              );
            }

            if (Shared().diagnostics.isNotEmpty) {
              for (final item in Shared().diagnostics) {
                if (lineIdx == item.range['start']['line']) {
                  final int start = item.range['start']['character'] as int;
                  final int end = item.range['end']['character'] as int;
                  if (col >= start && col < end) {
                    charStyle = TextStyle(
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.wavy,
                      decorationThickness: 2,
                      decorationColor: (() {
                        switch (item.severity) {
                          case 1:
                            return Colors.red;
                          case 2:
                            return Colors.amber;
                          case 3:
                            return Colors.blueAccent;
                          default:
                            return editorTheme['root']?.backgroundColor ??
                                Colors.black;
                        }
                      })(),
                    ).merge(Shared().textStyle);
                  }
                }
              }
            }

            if (isUnmatched) {
              charStyle = (charStyle ?? const TextStyle()).merge(
                const TextStyle(
                  color: Colors.red,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.wavy,
                ),
              );
            } else if (isMatch) {
              charStyle = (charStyle ?? const TextStyle()).merge(
                TextStyle(
                  background: Paint()
                    ..style = PaintingStyle.stroke
                    ..color = editorTheme['root']?.color ?? Colors.white,
                ),
              );
            }

            if (_highlightIndex.isNotEmpty) {
              for (final entry in _highlightIndex.entries) {
                final wordLen = entry.key;
                for (final startIdx in entry.value) {
                  if (globalIdx >= startIdx && globalIdx < startIdx + wordLen) {
                    charStyle = (charStyle ?? const TextStyle()).merge(
                      _highlightStyle ??
                          TextStyle(
                            backgroundColor: Colors.amberAccent.withAlpha(80),
                          ),
                    );
                  }
                }
              }
            }

            if (currentStyle == charStyle && accumulatedText.isNotEmpty) {
              accumulatedText += ch;
            } else {
              if (accumulatedText.isNotEmpty) {
                spans.add(TextSpan(text: accumulatedText, style: currentStyle));
              }
              accumulatedText = ch;
              currentStyle = charStyle;
            }
          }

          if (accumulatedText.isNotEmpty) {
            spans.add(TextSpan(text: accumulatedText, style: currentStyle));
          }

          if (lineIdx != nodeLines.length - 1) {
            spans.add(const TextSpan(text: '\n'));
          }
        }
      } else if (node.children != null) {
        final inner = _convert(node.children!, offset, b1, b2, unmatched);
        spans.add(
          TextSpan(children: inner, style: editorTheme[node.className ?? '']),
        );
        offset += _textLengthFromSpans(inner);
      }
    }
    return spans;
  }

  int _textLengthFromSpans(List<InlineSpan> spans) {
    int length = 0;
    for (final span in spans) {
      if (span is TextSpan && span.text != null) {
        length += span.text!.length;
      }
      if (span is TextSpan && span.children != null) {
        length += _textLengthFromSpans(span.children!);
      }
    }
    return length;
  }

  /// Finds all occurrences of the given word in the text and highlights them.
  ///
  /// The [word] parameter is a [Stirng] and it is the word to search for.
  /// The [highlightStyle] parameter is an optional [TextStyle] to apply to the highlighted words.
  /// Defaults to
  /// ```dart
  /// TextStyle(backgroundColor: Colors.amberAccent.withAlpha(80))
  /// ```
  void findWord(String word, {TextStyle? highlightStyle}) {
    _highlightStyle = highlightStyle;
    _highlightIndex.clear();
    if (word.isNotEmpty) {
      final regExp = RegExp('\\b$word\\b');
      for (final match in regExp.allMatches(text)) {
        _highlightIndex
            .putIfAbsent(word.length, () => <int>{})
            .add(match.start);
      }
    }
  }

  /// Returns the current cursor position as a map with 'line' and 'character' keys.
  ///
  /// The 'line' key is zero-based, and the 'character' key is also zero-based.
  /// If the cursor is at the start of the text, it returns {'line': 0, 'character': 0}.
  Map<String, int> getCursorLineAndChar() {
    final int offset = selection.baseOffset;
    if (offset < 0) selection = TextSelection.collapsed(offset: 0);
    if (offset > text.length) {
      selection = TextSelection.collapsed(offset: text.length);
    }

    final lines = text.substring(0, offset).split('\n');
    final line = lines.length - 1;
    final character = lines.isNotEmpty ? lines.last.length : 0;
    return {'line': line, 'character': character};
  }

  /// Callback to show Ai suggestion manually when the [AiCompletion.completionType] is [CompletionType.manual] or [CompletionType.mixed].
  void getManualAiSuggestion() {
    manualAiCompletion?.call();
  }

  /// Refreshes the controller, notifying all listeners.
  void refresh() {
    notifyListeners();
  }

  // The methods below are borrowed (with gratitude) from the code_text_field package:
  // https://github.com/BertrandBev/code_field

  /// Sets a specific cursor position in the text
  void setCursor(int offset) {
    selection = TextSelection.collapsed(offset: offset);
  }

  /// Replaces the current [selection] by [str]
  void insertStr(String str) {
    final sel = selection;
    text = text.replaceRange(selection.start, selection.end, str);
    final len = str.length;

    selection = sel.copyWith(
      baseOffset: sel.start + len,
      extentOffset: sel.start + len,
    );
  }

  /// Remove the char just before the cursor or the selection
  void removeChar() {
    if (selection.start < 1) {
      return;
    }

    final sel = selection;
    text = text.replaceRange(selection.start - 1, selection.start, '');

    selection = sel.copyWith(
      baseOffset: sel.start - 1,
      extentOffset: sel.start - 1,
    );
  }

  /// Remove the selected text
  void removeSelection() {
    final sel = selection;
    text = text.replaceRange(selection.start, selection.end, '');

    selection = sel.copyWith(baseOffset: sel.start, extentOffset: sel.start);
  }

  /// Remove the selection or last char if the selection is empty
  void backspace() {
    if (selection.start < selection.end) {
      removeSelection();
    } else {
      removeChar();
    }
  }
}
