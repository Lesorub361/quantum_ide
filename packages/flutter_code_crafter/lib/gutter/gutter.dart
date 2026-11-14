import 'dart:math';
import './gutter_style.dart';
import '../utils/utils.dart';
import '../utils/shared.dart';
import '../code_crafter/code_crafter_controller.dart';
import 'package:flutter/material.dart';

/// A widget that displays a gutter with line numbers, breakpoints, and folding icons.
/// Managed internally by the [CodeCrafterController].
class Gutter extends StatefulWidget {
  final bool enableBreakPoints, enableFolding;
  final GutterStyle gutterStyle;
  const Gutter(
    this.gutterStyle,
    this.enableBreakPoints,
    this.enableFolding, {
    super.key,
  });

  @override
  State<Gutter> createState() => _GutterState();
}

class _GutterState extends State<Gutter> {
  final CodeCrafterController _controller = Shared().controller;
  late ValueNotifier<List<LineState>> _lineStates;
  late final void Function() _listenerFunction;
  TextPainter _textPainter = TextPainter();
  int lineNumber = 0;
  double? _gutterWidth;
  int prevLineOffset = -1;

  void _updateLineStatesAndFolds() {
    _textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: _controller.text),
    )..layout();
    final oldStates = _lineStates.value;
    final updatedStates = List.generate(
      _textPainter.computeLineMetrics().length,
      (index) {
        if (index < oldStates.length) {
          return oldStates[index];
        } else {
          return LineState(lineNumber: index + 1);
        }
      },
    );
    lineNumber = _textPainter.computeLineMetrics().length;
    _lineStates.value = updatedStates;
    Shared().lineStates = _lineStates;
    if (widget.enableFolding) _getFoldRanges(_controller.text, _lineStates);
    int digitCount = max(3, lineNumber.toString().length);
    TextPainter gutterPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: List.filled(digitCount, "8").join(),
        style:
            Shared().textStyle?.copyWith(height: 1.5) ?? TextStyle(height: 1.5),
      ),
    )..layout();
    _gutterWidth = widget.gutterStyle.gutterWidth ?? gutterPainter.width * 2.1;
    Shared().gutterWidth = _gutterWidth ?? 65;
    setState(() {});
  }

  bool _foldAt(int index) {
    if (!mounted) return false;
    final line = _lineStates.value[index - 1];
    if (line.foldRange == null) return false;

    setState(() {
      line.foldRange!.isFolded = !line.foldRange!.isFolded;
      _controller.refresh();
    });
    return true;
  }

  @override
  void initState() {
    final lineMetrics = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: _controller.text),
    )..layout();
    lineNumber = lineMetrics.computeLineMetrics().length;

    _lineStates = ValueNotifier(
      List.generate(lineNumber, (index) => LineState(lineNumber: index + 1)),
    );

    _listenerFunction = _updateLineStatesAndFolds;
    _controller.addListener(_listenerFunction);
    _controller.setFoldAtCallback(_foldAt);

    _updateLineStatesAndFolds();
    super.initState();
  }

  @override
  void dispose() {
    _controller.removeListener(_listenerFunction);
    _lineStates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gutterWidth ?? 65,
      child: ValueListenableBuilder<List<LineState>>(
        valueListenable: _lineStates,
        builder: (context, lines, _) {
          List<bool> visibleLines = List.filled(lines.length, true);
          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.foldRange != null &&
                line.foldRange!.isFolded &&
                widget.enableFolding) {
              for (
                int j = line.foldRange!.startLine;
                j < line.foldRange!.endLine;
                j++
              ) {
                if (j < visibleLines.length) visibleLines[j] = false;
              }
            }
          }
          List<Widget> gutters = [];
          for (int i = 0; i < lines.length; i++) {
            if (!visibleLines[i]) continue;
            final line = lines[i];
            gutters.add(
              GutterItem(
                lineNumberStyle: widget.gutterStyle.lineNumberStyle,
                onTap: () {
                  final index = line.lineNumber - 1;
                  final updated = List<LineState>.from(_lineStates.value);
                  updated[index] = LineState(
                    lineNumber: updated[index].lineNumber,
                    hasBreakpoint: !updated[index].hasBreakpoint,
                  )..foldRange = updated[index].foldRange;
                  _lineStates.value = updated;
                },
                leftItem: widget.enableBreakPoints
                    ? GestureDetector(
                        onTap: () {
                          final index = line.lineNumber - 1;
                          final updated = List<LineState>.from(
                            _lineStates.value,
                          );
                          updated[index] = LineState(
                            lineNumber: updated[index].lineNumber,
                            hasBreakpoint: !updated[index].hasBreakpoint,
                          )..foldRange = updated[index].foldRange;
                          _lineStates.value = updated;
                        },
                        child: Icon(
                          line.hasBreakpoint
                              ? widget.gutterStyle.breakpointIcon
                              : widget.gutterStyle.unfilledBreakpointIcon,
                          size: (() {
                            if (widget.gutterStyle.breakpointSize != null) {
                              return widget.gutterStyle.breakpointSize;
                            } else if (widget
                                    .gutterStyle
                                    .lineNumberStyle
                                    ?.fontSize !=
                                null) {
                              double? breakpointSize =
                                  widget.gutterStyle.lineNumberStyle!.fontSize;
                              if (breakpointSize != null) {
                                return breakpointSize * 0.4;
                              }
                            } else if (Shared().textStyle?.fontSize != null) {
                              return Shared().textStyle!.fontSize! * 0.6;
                            } else {
                              return 14 * 0.6;
                            }
                          })(),
                          color: line.hasBreakpoint
                              ? widget.gutterStyle.breakpointColor
                              : widget.gutterStyle.unfilledBreakpointColor,
                        ),
                      )
                    : SizedBox.shrink(),
                line.lineNumber,
                rightItem: (line.foldRange != null && widget.enableFolding)
                    ? GestureDetector(
                        onTap: () {
                          setState(() {
                            line.foldRange!.isFolded =
                                !line.foldRange!.isFolded;
                            _controller.refresh();
                          });
                        },
                        child: Icon(
                          !line.foldRange!.isFolded
                              ? widget.gutterStyle.unfoldedIcon
                              : widget.gutterStyle.foldedIcon,
                          color: !line.foldRange!.isFolded
                              ? widget.gutterStyle.unfoldedIconColor
                              : widget.gutterStyle.foldedIconColor,
                          size:
                              widget.gutterStyle.foldingIconSize ??
                              (widget.gutterStyle.lineNumberStyle?.fontSize ??
                                      Shared().textStyle?.fontSize ??
                                      14) *
                                  1.2,
                        ),
                      )
                    : SizedBox.shrink(),
              ),
            );
          }
          return Column(
            children: _lineStates.value.isEmpty ? [GutterItem(1)] : gutters,
          );
        },
      ),
    );
  }
}

class GutterItem extends StatelessWidget {
  final Widget leftItem;
  final Widget rightItem;
  final int linNumber;
  final TextStyle? lineNumberStyle;
  final VoidCallback? onTap;
  const GutterItem(
    this.linNumber, {
    super.key,
    this.lineNumberStyle,
    this.leftItem = const SizedBox(),
    this.rightItem = const SizedBox(),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: leftItem),
        GestureDetector(
          onTap: onTap,
          child: Text(
            linNumber.toString(),
            style: (() {
              if (lineNumberStyle != null) {
                return lineNumberStyle!.copyWith(
                  color:
                      lineNumberStyle?.color ?? Shared().theme['root']?.color,
                  height: 1.5,
                );
              } else if (Shared().textStyle != null) {
                return Shared().textStyle!.copyWith(
                  color:
                      Shared().textStyle?.color ??
                      Shared().theme['root']?.color,
                  height: 1.5,
                );
              } else {
                return TextStyle(
                  color: Shared().theme.isNotEmpty
                      ? Shared().theme['root']?.color
                      : Colors.white,
                  height: 1.5,
                );
              }
            })(),
          ),
        ),
        Expanded(child: rightItem),
      ],
    );
  }
}

void _getFoldRanges(String code, ValueNotifier<List<LineState>> lineStates) {
  final List<String> lines = code.split('\n');
  final lineStateCopy = lineStates.value
      .map(
        (e) =>
            LineState(lineNumber: e.lineNumber, hasBreakpoint: e.hasBreakpoint),
      )
      .toList();
  Map<String, List<int>> stacks = {"{": [], "[": [], "(": [], "<": []};
  const matchingBrackets = {"{": "}", "[": "]", "(": ")", "<": ">"};
  for (final openBracket in matchingBrackets.keys) {
    final closeBracket = matchingBrackets[openBracket]!;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains(openBracket)) stacks[openBracket]!.add(i);
      if (lines[i].contains(closeBracket)) {
        if (stacks[openBracket]!.isNotEmpty) {
          int start = stacks[openBracket]!.removeLast();
          if (i > start + 1 && i + 1 <= lineStateCopy.length) {
            bool previouslyFolded =
                lineStates.value[start].foldRange?.isFolded ?? false;
            lineStateCopy[start] =
                LineState(
                    lineNumber: lineStateCopy[start].lineNumber,
                    hasBreakpoint: lineStateCopy[start].hasBreakpoint,
                  )
                  ..foldRange = FoldRange(
                    start + 1,
                    i + 1,
                    isFolded: previouslyFolded,
                  );
          }
        }
      }
    }
  }
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || !line.trim().endsWith(':')) continue;
    final startIndent = line.length - line.trimLeft().length;
    int j = i + 1;
    while (j < lines.length) {
      final next = lines[j];
      if (next.trim().isEmpty) {
        j++;
        continue;
      }
      final nextIndent = next.length - next.trimLeft().length;
      if (nextIndent <= startIndent) break;
      j++;
    }
    if (j > i + 1 && j <= lines.length) {
      bool previouslyFolded = lineStates.value[i].foldRange?.isFolded ?? false;
      lineStateCopy[i] = LineState(
        lineNumber: lineStateCopy[i].lineNumber,
        hasBreakpoint: lineStateCopy[i].hasBreakpoint,
      )..foldRange = FoldRange(i + 1, j, isFolded: previouslyFolded);
    }
  }
  lineStates.value = lineStateCopy;
}
