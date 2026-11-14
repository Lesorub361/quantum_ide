import 'dart:async';
import 'dart:io';
import '../LSP/lsp.dart';
import '../utils/utils.dart';
import '../utils/shared.dart';
import '../gutter/gutter.dart';
import '../AI_completion/ai.dart';
import '../gutter/gutter_style.dart';
import '../LSP/suggestion_style.dart';
import './code_crafter_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';

class CodeCrafter extends StatefulWidget {
  /// The controller for the CodeCrafter widget.
  final CodeCrafterController controller;

  /// The initial text to be displayed in the [CodeCrafter] widget.
  ///
  /// > Note: If both [initialText] and [filePath] are provided, an exception will be thrown.
  final String? initialText;

  /// Optional but if provided, it will be used to load the initial text from a file.
  ///
  /// > Note: If both [initialText] and [filePath] are provided, an exception will be thrown.
  /// > Note: If [filePath] is provided, the [lspConfig] must also have the same file path. Otherwise, an exception will be thrown.
  final String? filePath;

  /// The text style to be applied to the text in the [CodeCrafter] widget.
  final TextStyle? textStyle;

  /// The text style to be applied to the AI completion text in the [CodeCrafter] widget.
  final TextStyle? aiCompletionTextStyle;

  /// The color of the cursor in the [CodeCrafter] widget.
  final Color? cursorColor;

  /// The color of the selection in the [CodeCrafter] widget.
  final Color? selectionColor;

  /// The color of the selection handle in the [CodeCrafter] widget.
  final Color? selectionHandleColor;

  /// The theme for the editor, which can be used to customize the appearance of the [CodeCrafter] widget.
  ///
  /// Use [flutter_highlight](https://pub.dev/packages/flutter_highlight) package to get prebuilt themes.
  /// > Note: If not provided, syntax highlighting will not work.
  final Map<String, TextStyle>? editorTheme;

  /// tab size for the [CodeCrafter] widget.
  ///
  /// Defaults to 3.
  /// `" " * tabSize` spaces will be inserted when the user presses the tab key.
  /// This value us also used for indentation in the [CodeCrafter] widget.
  final int tabSize;

  /// The inner padding of the editable area inside the [CodeCrafter] widget.
  ///
  /// Controls the spacing between the text content and the edges of the editor.
  /// Defaults to [EdgeInsets.all(0)] if not provided.
  final EdgeInsets innerPadding;

  /// The style for the gutter in the [CodeCrafter] widget.
  final GutterStyle? gutterStyle;

  /// Whether to enable breakpoints in the [CodeCrafter] widget.
  final bool enableBreakPoints;

  /// Whether to enable folding in the [CodeCrafter] widget.
  final bool enableFolding;

  /// Whether to enable auto focus on the [CodeCrafter] widget.
  final bool autoFocus;

  /// Whether the [CodeCrafter] widget is read-only.
  final bool readOnly;

  /// Whether to wrap lines in the [CodeCrafter] widget.
  /// Defaults to false.
  final bool wrapLines;

  /// Whether to enable ruler lines in the [CodeCrafter] widget.
  /// Defaults to true.
  final bool enableRulerLines;

  /// Whether to enable suggestions in the [CodeCrafter] widget.
  /// Defaults to true.
  /// Not AI suggestions, but the suggestions from LSP or based on the text in the editor.
  final bool enableSuggestions;

  /// whether to enable the vertical divider line between gutter and editor
  final bool enableGutterDivider;

  /// Focus node for the underlying [TextField] in the [CodeCrafter] widget.
  final FocusNode? focusNode;

  /// The [CodeCrafter] widget uses [TextField] under the hood,
  /// So the properties given to this [EditorField] class gets passed to the undelying [TextField] of [CodeCrafter].
  ///
  /// Example:
  /// ```dart
  /// CodeCrafter(
  ///  editorField: EditorField(
  ///   onTap: () {
  ///    print('Tapped on CodeCrafter');
  ///  },
  /// ),
  /// ```
  final EditorField? editorField;

  /// AI completion configuration for the [CodeCrafter] widget.
  ///
  /// Documentation for [AiCompletion] can be found [here](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/AICompletion.md).
  final AiCompletion? aiCompletion;

  /// LSP configuration for the [CodeCrafter] widget.
  ///
  /// Documentation for [LspConfig] can be found [here](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/LSPClient.md)
  final LspConfig? lspConfig;

  /// The style for the LSP suggestions overlay.
  final OverlayStyle? suggestionStyle;

  /// The style for the LSP hover details overlay.
  final OverlayStyle? hoverDetailsStyle;
  const CodeCrafter({
    super.key,
    required this.controller,
    this.initialText,
    this.filePath,
    this.focusNode,
    this.textStyle,
    this.gutterStyle,
    this.editorTheme,
    this.aiCompletion,
    this.aiCompletionTextStyle,
    this.lspConfig,
    this.suggestionStyle,
    this.hoverDetailsStyle,
    this.selectionHandleColor,
    this.selectionColor,
    this.cursorColor,
    this.enableBreakPoints = true,
    this.enableFolding = true,
    this.enableRulerLines = true,
    this.enableSuggestions = true,
    this.enableGutterDivider = false,
    this.wrapLines = false,
    this.autoFocus = false,
    this.readOnly = false,
    this.tabSize = 3,
    this.innerPadding = EdgeInsets.zero,
    this.editorField,
  });

  @override
  State<CodeCrafter> createState() => _CodeCrafterState();
}

class _CodeCrafterState extends State<CodeCrafter> {
  late final FocusNode _keyboardFocus, _codeFocus, _suggestionFocus;
  late final ScrollController _hoverHorizontalScroll, _hoverVerticalSCroll;
  double gutterWidth = Shared().gutterWidth;
  Map<String, String> cachedResponse = {};
  Timer? _debounceTimer;
  String _value = '', _hoverDetails = '';
  int _selected = 0;
  OverlayEntry? _suggestionOverlay, _detailsOverlay;
  List<dynamic> _suggestions = [];
  List<LspErrors> _diagnostics = [];
  bool _suggestionShown = false, _aiSuggestion = false;
  Rect _caretRect = Rect.zero;
  TextEditingValue? _previousValue;
  bool _lspReady = false;
  String? content;

  @override
  void initState() {
    _keyboardFocus = FocusNode();
    _suggestionFocus = FocusNode();
    _codeFocus = widget.focusNode ?? FocusNode();
    _hoverHorizontalScroll = ScrollController();
    _hoverVerticalSCroll = ScrollController();
    if (widget.initialText != null) {
      widget.controller.text = widget.initialText!;
    }
    widget.controller.manualAiCompletion = getManualAiSuggestion;
    if (widget.lspConfig != null) {
      widget.lspConfig!.responses.listen((data) {
        if (data['method'] == 'textDocument/publishDiagnostics') {
          final diagnostics = data['params']['diagnostics'] as List;
          _diagnostics.clear();
          Shared().diagnostics.clear();
          if (diagnostics.isNotEmpty) {
            final List<LspErrors> errors = [];
            for (final (item as Map<String, dynamic>) in diagnostics) {
              errors.add(
                LspErrors(
                  severity: (() {
                    if (item['severity'] == 1 &&
                        widget.lspConfig!.disableError) {
                      return 0;
                    }
                    if (item['severity'] == 2 &&
                        widget.lspConfig!.disableWarning) {
                      return 0;
                    }
                    return item['severity'];
                  })(),
                  range: item['range'],
                  message: item['message'],
                ),
              );
            }
            _diagnostics = List.from(errors);
            Shared().diagnostics = _diagnostics;
          }
        }
      });
    }
    if (kIsWeb) {
      if (widget.filePath != null) {
        throw PlatformException(
          code: "\nERROR\n",
          message:
              "The parameter filePath is not supported on web. Please remove it.\n",
        );
      }
      if (widget.lspConfig != null) {
        throw PlatformException(
          code: "\nERROR\n",
          message:
              "LSP is not supported on web in the current version; support may be added in the future\n",
        );
      }
    }
    if (widget.filePath != null) {
      (() async {
        content = await File(widget.filePath!).readAsString();
        widget.controller.value = TextEditingValue(
          text: content ?? '',
          selection: TextSelection.collapsed(offset: content?.length ?? 0),
        );
      })();
    }
    if (widget.initialText != null && widget.filePath != null) {
      throw Exception(
        'Initial text and file path cannot be both provided. Please provide either initialText or filePath.',
      );
    }
    if (widget.lspConfig != null) {
      if ((widget.lspConfig!.filePath != widget.filePath) ||
          widget.filePath == null) {
        throw Exception(
          'File path in LspConfig does not match the provided filePath in CodeCrafter.',
        );
      }
      (() async {
        try {
          if (widget.lspConfig is LspSocketConfig) {
            await (widget.lspConfig as LspSocketConfig).connect();
          }
          await widget.lspConfig!.initialize();
          await Future.delayed(const Duration(milliseconds: 300));
          await widget.lspConfig!.openDocument();
          setState(() {
            _lspReady = true;
          });
        } catch (e) {
          debugPrint('Error initializing LSP: $e');
        }
      })();
    }

    Shared().theme = widget.editorTheme ?? {};
    Shared().textStyle = widget.textStyle;
    Shared().aiOverlayStyle = widget.aiCompletionTextStyle;
    Shared().controller = widget.controller;
    Shared().tabSize = widget.tabSize;
    Shared().enableRulerLines = widget.enableRulerLines;
    _value = widget.controller.text;
    widget.controller.addListener(() {
      final cursorOffset = widget.controller.selection.baseOffset;
      if (cursorOffset < 0) return;
      final currentText = widget.controller.text;
      final lines = currentText.substring(0, cursorOffset).split('\n');
      final line = lines.length - 1;
      final prefix = _getCurrentWordPrefix(currentText, cursorOffset);
      final character = lines.isNotEmpty ? lines.last.length : 0;
      final currentValue = widget.controller.value;
      final prevValue = _previousValue ?? currentValue;
      bool isTyping = false;
      if (currentValue.text.length == prevValue.text.length + 1 &&
          currentValue.selection.baseOffset ==
              prevValue.selection.baseOffset + 1) {
        final insertedChar = currentValue.text.substring(
          prevValue.selection.baseOffset,
          currentValue.selection.baseOffset,
        );
        isTyping =
            insertedChar.isNotEmpty &&
            RegExp(r'[a-zA-Z]').hasMatch(insertedChar);
      }
      _previousValue = currentValue;

      if (_aiSuggestion && Shared().aiResponse == null) {
        setState(() {
          _aiSuggestion = false;
        });
      }
      if (widget.lspConfig == null) {
        final RegExp regExp = RegExp(r'\b\w+\b');
        final List<String> words = regExp
            .allMatches(widget.controller.text)
            .map((m) => m.group(0)!)
            .toList();
        String currentWord = '';
        if (widget.controller.text.isNotEmpty) {
          final match = RegExp(r'\w+$').firstMatch(widget.controller.text);
          if (match != null) {
            currentWord = match.group(0)!;
          }
        }
        _suggestions.clear();
        for (var i in words) {
          if (!_suggestions.contains(i) && i != currentWord) {
            _suggestions.add(i);
          }
        }
        if (prefix.isNotEmpty) {
          _suggestions = _suggestions
              .where((s) => s.startsWith(prefix))
              .toList();
        }

        if (isTyping &&
            _suggestions.isNotEmpty &&
            cursorOffset > 0 &&
            widget.enableSuggestions &&
            prefix.isNotEmpty) {
          _sortSuggestions(prefix);
          final triggerChar = currentText[cursorOffset - 1];
          if (!RegExp(r'[a-zA-Z]').hasMatch(triggerChar)) {
            _hideSuggestionOverlay();
            return;
          }
          if (mounted) {
            _showSuggestionOverlay();
          }
        } else {
          _hideSuggestionOverlay();
        }
      }
      if (widget.lspConfig != null &&
          widget.controller.selection.baseOffset > 0 &&
          widget.enableSuggestions &&
          _lspReady) {
        (() async {
          await widget.lspConfig!.updateDocument(widget.controller.text);
          final List<LspCompletion> suggestion = await widget.lspConfig!
              .getCompletions(line, character);
          _hoverDetails = await widget.lspConfig!.getHover(line, character);
          if (isTyping &&
              suggestion.isNotEmpty &&
              cursorOffset > 0 &&
              prefix.isNotEmpty) {
            _suggestions = suggestion;
            _selected = 0;
            _sortSuggestions(prefix);
            final triggerChar = currentText[cursorOffset - 1];
            if (!RegExp(r'[a-zA-Z._$]').hasMatch(triggerChar)) {
              _hideSuggestionOverlay();
              return;
            }
            if (mounted) _showSuggestionOverlay();
          } else {
            _hideSuggestionOverlay();
          }
        })();
      }

      if (gutterWidth != Shared().gutterWidth) {
        setState(() => gutterWidth = Shared().gutterWidth);
      }

      if (_value != widget.controller.text &&
          (widget.aiCompletion?.enableCompletion ?? false)) {
        final String text = widget.controller.text;
        final int cursorPosition = widget.controller.selection.baseOffset;
        final String codeToSend =
            "${text.substring(0, cursorPosition)}<|CURSOR|>${text.substring(cursorPosition)}";

        _debounceTimer?.cancel();

        if (widget.aiCompletion?.completionType == CompletionType.auto ||
            widget.aiCompletion?.completionType == CompletionType.mixed) {
          _debounceTimer = Timer(
            Duration(milliseconds: widget.aiCompletion!.debounceTime),
            () async {
              Shared().aiResponse = await _getCachedResponse(codeToSend);
              Shared().lastCursorPosition =
                  widget.controller.selection.baseOffset;
              setState(() => _aiSuggestion = true);
            },
          );
        }
        _value = widget.controller.text;
      }
    });
    super.initState();
  }

  @override
  void didUpdateWidget(covariant CodeCrafter oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.textStyle != oldWidget.textStyle) {
      Shared().textStyle = widget.textStyle;
    }

    if (widget.editorTheme != oldWidget.editorTheme) {
      Shared().theme = widget.editorTheme ?? {};
    }
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    _suggestionFocus.dispose();
    _codeFocus.dispose();
    _hoverHorizontalScroll.dispose();
    _hoverVerticalSCroll.dispose();
    _debounceTimer?.cancel();
    widget.lspConfig?.closeDocument();
    widget.lspConfig?.dispose();
    super.dispose();
  }

  String _getCurrentWordPrefix(String text, int offset) {
    final beforeCursor = text.substring(0, offset);
    final match = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)$').firstMatch(beforeCursor);
    return match?.group(0) ?? '';
  }

  void _sortSuggestions(String prefix) {
    _suggestions.sort((a, b) {
      final aStartsWith = a is LspCompletion
          ? a.label.toLowerCase().startsWith(prefix.toLowerCase())
          : a.toLowerCase().startsWith(prefix.toLowerCase());
      final bStartsWith = b is LspCompletion
          ? b.label.toLowerCase().startsWith(prefix.toLowerCase())
          : b.toLowerCase().startsWith(prefix.toLowerCase());
      if (aStartsWith && !bStartsWith) return -1;
      if (!aStartsWith && bStartsWith) return 1;

      return a is LspCompletion ? b.label.compareTo(a.label) : b.compareTo(a);
    });
  }

  void _insertAiSuggestion(String suggestion) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    final newText = text.replaceRange(cursorPos, cursorPos, suggestion);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPos + suggestion.length),
    );
  }

  void _insertSuggestion(String suggestion) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    int start = cursorPos - 1;
    while (start >= 0 && !_isWordBoundary(text[start])) {
      start--;
    }
    start++;
    final newText = text.replaceRange(start, cursorPos, suggestion);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + suggestion.length),
    );
  }

  bool _isWordBoundary(String char) {
    return char == ' ' ||
        char == '\n' ||
        char == '\t' ||
        char == '(' ||
        char == ')' ||
        char == '{' ||
        char == '}' ||
        char == ';' ||
        char == ',' ||
        char == '.' ||
        char == '"' ||
        char == '\'';
  }

  void _hideSuggestionOverlay() {
    _suggestionShown = false;
    _suggestionFocus.unfocus();
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  void _hideDetailsOverlay() {
    _detailsOverlay?.remove();
    _detailsOverlay = null;
  }

  RenderEditable? _findRenderEditable(BuildContext root) {
    RenderEditable? result;
    void visitor(Element element) {
      if (result != null) return;
      final ro = element.renderObject;
      if (ro is RenderEditable) {
        result = ro;
        return;
      }
      if (!root.mounted) return;
      element.visitChildElements(visitor);
    }

    root.visitChildElements(visitor);
    return result;
  }

  Rect _globalCaretRect({bool global = false}) {
    final ctx = _codeFocus.context;
    if (ctx == null) return Rect.zero;
    if (!mounted) return Rect.zero;

    final RenderEditable? renderEditable = _findRenderEditable(ctx);
    if (renderEditable == null) {
      return Rect.zero;
    }

    final Rect caret = renderEditable.getLocalRectForCaret(
      TextPosition(offset: widget.controller.selection.baseOffset),
    );

    if (global) {
      final Offset caretTopLeftGlobal = renderEditable.localToGlobal(
        caret.topLeft,
      );
      return Rect.fromLTWH(
        caretTopLeftGlobal.dx,
        caretTopLeftGlobal.dy,
        caret.width,
        caret.height,
      );
    } else {
      final RenderBox? ancestorBox = context.findRenderObject() as RenderBox?;
      if (ancestorBox == null) return Rect.zero;
      final Offset caretTopLeftGlobal = renderEditable.localToGlobal(
        caret.topLeft,
      );
      final Offset caretTopLeftLocal = ancestorBox.globalToLocal(
        caretTopLeftGlobal,
      );
      return Rect.fromLTWH(
        caretTopLeftLocal.dx,
        caretTopLeftLocal.dy,
        caret.width,
        caret.height,
      );
    }
  }

  void _showSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionShown = true;
    final OverlayState overlay = Overlay.of(context);
    final Rect caretGlobal = _globalCaretRect(global: true);
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double overlayWidth = 250.0, maxOverlayHeight = 300.0;
    const int gap = 4;
    final bool showAbove =
        caretGlobal.bottom + gap + maxOverlayHeight > screenHeight;
    final bool showLeft = caretGlobal.left + overlayWidth > screenWidth;

    final double top = showAbove
        ? caretGlobal.top - gap - maxOverlayHeight
        : caretGlobal.bottom + gap;

    final double left = showLeft
        ? caretGlobal.left - overlayWidth + caretGlobal.width
        : caretGlobal.left;

    _suggestionOverlay = OverlayEntry(
      builder: (ctx) => Positioned(
        left: left,
        top: top,
        width: overlayWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxOverlayHeight),
          child: Card(
            elevation: widget.suggestionStyle?.elevation ?? 6,
            color:
                widget.suggestionStyle?.backgroundColor ??
                widget.editorTheme?['root']?.backgroundColor?.withAlpha(220) ??
                Colors.black87,
            shape:
                widget.suggestionStyle?.shape ??
                BeveledRectangleBorder(
                  side: BorderSide(
                    color: Shared().theme['root']?.color ?? Colors.white,
                    width: 0.2,
                  ),
                ),
            child: Focus(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemExtent: (widget.textStyle?.fontSize ?? 14) + 5,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  return InkWell(
                    autofocus: true,
                    focusNode: _selected == i ? _suggestionFocus : null,
                    focusColor:
                        widget.suggestionStyle?.focusColor ??
                        Colors.blueAccent.withAlpha(50),
                    hoverColor:
                        widget.suggestionStyle?.hoverColor ??
                        Colors.grey.withAlpha(15),
                    splashColor:
                        widget.suggestionStyle?.splashColor ??
                        Colors.blueAccent.withAlpha(50),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Row(
                        children: [
                          _suggestions[i] is LspCompletion
                              ? _suggestions[i].icon
                              : const SizedBox(),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _suggestions[i] is LspCompletion
                                  ? _suggestions[i].label
                                  : _suggestions[i],
                              overflow: TextOverflow.ellipsis,
                              style:
                                  widget.suggestionStyle?.textStyle ??
                                  TextStyle(
                                    color:
                                        widget.editorTheme?['root']?.color ??
                                        Colors.white,
                                    fontSize:
                                        (widget.textStyle?.fontSize ?? 14) - 2,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    onTap: () {
                      _insertSuggestion(
                        _suggestions[i] is LspCompletion
                            ? _suggestions[i].label
                            : _suggestions[i],
                      );
                      _selected = i;
                      _hideSuggestionOverlay();
                      _codeFocus.requestFocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_suggestionOverlay!);
  }

  void _showDetailsOverlay() {
    _hideDetailsOverlay();
    if (_hoverDetails.isEmpty && _codeFocus.hasFocus) return;
    final OverlayState overlay = Overlay.of(context);
    final Rect caretGlobal = _globalCaretRect(global: true);
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double overlayWidth = 250.0, maxOverlayHeight = 300.0;
    const int gap = 4;
    final bool showAbove =
        caretGlobal.bottom + gap + maxOverlayHeight > screenHeight;
    final bool showLeft = caretGlobal.left + overlayWidth > screenWidth;

    final Map<String, int> cursorInfo = widget.controller
        .getCursorLineAndChar();
    final int cursorLine = cursorInfo['line']!;
    final int cursorChar = cursorInfo['character']!;

    final error = _getErrorAtPosition(cursorLine, cursorChar);

    final double top = showAbove
        ? caretGlobal.top - gap - maxOverlayHeight
        : caretGlobal.bottom + gap;

    final double left = showLeft
        ? caretGlobal.left - overlayWidth + caretGlobal.width
        : caretGlobal.left;

    _detailsOverlay = OverlayEntry(
      builder: (ctx) => Positioned(
        left: left,
        top: top,
        width: overlayWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxOverlayHeight),
          child: Card(
            elevation: widget.hoverDetailsStyle?.elevation ?? 6,
            color:
                widget.hoverDetailsStyle?.backgroundColor ??
                widget.editorTheme?['root']?.backgroundColor?.withAlpha(220) ??
                Colors.black87,
            shape:
                widget.hoverDetailsStyle?.shape ??
                BeveledRectangleBorder(
                  side: BorderSide(
                    color: widget.editorTheme?['root']?.color ?? Colors.white,
                    width: 0.2,
                  ),
                ),
            child: RawScrollbar(
              thumbVisibility: true,
              thumbColor: (widget.editorTheme?['root']?.color ?? Colors.white)
                  .withAlpha(35),
              controller: _hoverHorizontalScroll,
              child: SingleChildScrollView(
                controller: _hoverHorizontalScroll,
                scrollDirection: Axis.horizontal,
                child: RawScrollbar(
                  thumbVisibility: true,
                  controller: _hoverVerticalSCroll,
                  child: SingleChildScrollView(
                    controller: _hoverVerticalSCroll,
                    scrollDirection: Axis.vertical,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        error == null ? _hoverDetails : error.message,
                        style:
                            widget.hoverDetailsStyle?.textStyle ??
                            TextStyle(
                              color:
                                  Shared().theme['root']?.color ?? Colors.white,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_detailsOverlay!);
  }

  LspErrors? _getErrorAtPosition(int line, int character) {
    for (final error in _diagnostics) {
      final start = error.range['start'];
      final end = error.range['end'];
      final startLine = start['line'] as int;
      final startChar = start['character'] as int;
      final endLine = end['line'] as int;
      final endChar = end['character'] as int;

      final inRange =
          (line > startLine || (line == startLine && character >= startChar)) &&
          (line < endLine || (line == endLine && character < endChar));
      if (inRange) {
        return error;
      }
    }
    return null;
  }

  Future<String> _getCachedResponse(String codeToSend) async {
    final String key = codeToSend.hashCode.toString();
    if (cachedResponse.containsKey(key)) {
      return cachedResponse[key]!;
    }
    final String aiResponse = await widget.aiCompletion!.model
        .completionResponse(codeToSend);
    cachedResponse[key] = aiResponse;
    return aiResponse;
  }

  Future<void> getManualAiSuggestion() async {
    if (widget.aiCompletion?.completionType == CompletionType.manual ||
        widget.aiCompletion?.completionType == CompletionType.mixed) {
      final String text = widget.controller.text;
      final int cursorPosition = widget.controller.selection.baseOffset;
      final String codeToSend =
          "${text.substring(0, cursorPosition)}<|CURSOR|>${text.substring(cursorPosition)}";
      Shared().aiResponse = await _getCachedResponse(codeToSend);
      Shared().lastCursorPosition = widget.controller.selection.baseOffset;
      setState(() => _aiSuggestion = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EditorField? editorField = widget.editorField?.copyWith(
      onTap: () {
        if (widget.lspConfig == null) return;
        _showDetailsOverlay();
        widget.editorField?.onTap?.call();
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final rect = _globalCaretRect();
          if (rect != _caretRect) setState(() => _caretRect = rect);
        });
        return Container(
          height: constraints.maxHeight,
          width: constraints.maxWidth,
          padding: widget.innerPadding,
          color: widget.editorTheme?['root']?.backgroundColor ?? Colors.black,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => _codeFocus.requestFocus(),
                child: Container(
                  color:
                      widget.editorTheme?['root']?.backgroundColor ??
                      Colors.black,
                ),
              ),
              SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Gutter(
                      widget.gutterStyle ??
                          GutterStyle(
                            foldedIconColor:
                                widget.editorTheme?['root']?.color ??
                                Colors.grey,
                            unfoldedIconColor:
                                widget.editorTheme?['root']?.color ??
                                Colors.grey,
                          ),
                      widget.enableBreakPoints,
                      widget.enableFolding,
                    ),
                    widget.enableGutterDivider
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: SizedBox(
                              height: constraints.maxHeight,
                              child: VerticalDivider(
                                color:
                                    widget.gutterStyle?.dividerColor ??
                                    widget.editorTheme?['root']?.color ??
                                    Colors.white,
                                width: 0,
                                thickness:
                                    widget.gutterStyle?.dividerThickness ?? 0.3,
                              ),
                            ),
                          )
                        : SizedBox.shrink(),
                    Expanded(
                      child: KeyboardListener(
                        focusNode: _keyboardFocus,
                        onKeyEvent: (value) {
                          if (value is KeyDownEvent) {
                            if (value.logicalKey == LogicalKeyboardKey.escape) {
                              if (_suggestionShown) {
                                _suggestionFocus.unfocus();
                                _hideSuggestionOverlay();
                                _codeFocus.requestFocus();
                              }
                            }

                            if (value.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              if (_suggestionShown) {
                                setState(() => _selected--);
                                _suggestionFocus.requestFocus();
                              }
                            }

                            if (value.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              if (_suggestionShown) {
                                setState(() => _selected++);
                                _suggestionFocus.requestFocus();
                              }
                            }

                            if (value.logicalKey == LogicalKeyboardKey.enter) {
                              if (_suggestionShown) {
                                _suggestionFocus.requestFocus();
                              }
                            }

                            if (value.logicalKey == LogicalKeyboardKey.tab) {
                              if (!widget.wrapLines) {
                                _codeFocus.requestFocus();
                                return;
                              }
                              int cursorPosition =
                                  widget.controller.selection.baseOffset;
                              String currText = widget.controller.text;
                              _keyboardFocus.previousFocus();
                              widget.controller.value = TextEditingValue(
                                text: currText.replaceRange(
                                  cursorPosition,
                                  cursorPosition,
                                  ' ' * widget.tabSize,
                                ),
                                selection: TextSelection.collapsed(
                                  offset: cursorPosition + widget.tabSize,
                                ),
                              );
                              return;
                            }
                          }
                        },
                        child: Theme(
                          data: ThemeData(
                            textSelectionTheme: TextSelectionThemeData(
                              selectionColor: widget.selectionColor,
                              selectionHandleColor: widget.selectionHandleColor,
                            ),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: widget.wrapLines
                                  ? constraints.maxWidth - gutterWidth
                                  : double.maxFinite,
                              child:
                                  editorField?.build(
                                    controller: widget.controller,
                                    focusNode: _codeFocus,
                                    autofocus: widget.autoFocus,
                                    readOnly: widget.readOnly,
                                    fallbackStyle: widget.textStyle,
                                    fallbackCursorColor: widget.cursorColor,
                                    editorTheme: widget.editorTheme,
                                  ) ??
                                  TextField(
                                    key: widget.controller.textKey,
                                    onTap: () {
                                      if (widget.lspConfig == null) {
                                        return;
                                      }
                                      _showDetailsOverlay();
                                    },
                                    controller: widget.controller,
                                    focusNode: _codeFocus,
                                    autofocus: widget.autoFocus,
                                    readOnly: widget.readOnly,
                                    scrollPhysics:
                                        const NeverScrollableScrollPhysics(),
                                    keyboardType: TextInputType.multiline,
                                    decoration: const InputDecoration(
                                      isCollapsed: true,
                                      border: InputBorder.none,
                                    ),
                                    maxLines: null,
                                    showCursor: true,
                                    style:
                                        widget.textStyle ??
                                        const TextStyle(
                                          height: 1.5,
                                          fontSize: 14,
                                        ),
                                    cursorHeight:
                                        widget.textStyle?.fontSize ?? 14,
                                    cursorColor:
                                        widget.cursorColor ??
                                        widget.editorTheme?['root']?.color ??
                                        Colors.white,
                                    cursorWidth: 2,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.aiCompletion != null &&
                  widget.aiCompletion!.enableCompletion &&
                  Shared().aiResponse != null &&
                  Shared().aiResponse!.isNotEmpty &&
                  _aiSuggestion)
                Positioned(
                  left: _caretRect.left,
                  right: _caretRect.right,
                  top:
                      _caretRect.top +
                      _caretRect.height +
                      ((Shared().aiResponse!.split('\n').length + 1.5) *
                          (widget.textStyle?.fontSize ?? 14)),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 55,
                        height: _caretRect.height,
                        child: InkWell(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              border: Border.all(
                                width: 0.2,
                                color: Colors.white,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              "Accept",
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              if (Shared().aiResponse == null) return;
                              _insertAiSuggestion(Shared().aiResponse!);
                              Future.delayed(Duration.zero);
                              Shared().aiResponse = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 55,
                        height: _caretRect.height,
                        child: InkWell(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: Colors.redAccent,
                              border: Border.all(
                                color: Colors.white,
                                width: 0.2,
                              ),
                            ),
                            child: const Text(
                              "Reject",
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onTap: () => setState(() {
                            if (Shared().aiResponse == null) return;
                            Shared().aiResponse = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
