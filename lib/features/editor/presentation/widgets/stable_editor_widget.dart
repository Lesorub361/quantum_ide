import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/ai_autocomplete_service.dart';
import 'package:quantum_ide/features/editor/presentation/handlers/autocomplete_handler.dart' hide CodeKeywordPrompt;
import 'package:quantum_ide/features/editor/presentation/handlers/snippet_prompt.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/diff_gutter_indicator.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/diagnostic_indicator.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/code_find_panel.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/services/diff_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/collaboration_painter.dart';
import 'package:quantum_ide/core/services/service_providers.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/editor_minimap.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';


class DiffBackgroundPainter extends CustomPainter {
  final CodeIndicatorValueNotifier? notifier;
  final List<DiffMarker> markers;

  DiffBackgroundPainter({required this.notifier, required this.markers}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final val = notifier?.value;
    if (val == null || markers.isEmpty) return;

    for (final paragraph in val.paragraphs) {
      final lineIndex = paragraph.index;
      final marker = markers.firstWhere(
        (m) => m.line == lineIndex,
        orElse: () => DiffMarker(line: -1, type: DiffType.added),
      );

      if (marker.line != -1) {
        final paint = Paint();
        switch (marker.type) {
          case DiffType.added:
            paint.color = Colors.green.withValues(alpha: 0.12);
            break;
          case DiffType.removed:
            paint.color = Colors.red.withValues(alpha: 0.12);
            break;
          case DiffType.modified:
            paint.color = Colors.orange.withValues(alpha: 0.12);
            break;
        }

        final rect = Rect.fromLTWH(
          0,
          paragraph.offset.dy,
          size.width,
          paragraph.paragraph.height,
        );
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DiffBackgroundPainter oldDelegate) {
    return oldDelegate.markers != markers || oldDelegate.notifier != notifier;
  }
}

// ─── Стабильный виджет редактора ─────────────────────────────────────────────
// Каждый открытый файл имеет СВОЙ постоянный StableEditorWidget.
// IndexedStack в EditorPage держит все экземпляры живыми одновременно —
// CodeEditor НИКОГДА не уничтожается и не пересоздаётся при смене вкладки.
// Это устраняет stale _CodeEditableState listener crash из re_editor.

/// Контроллер всплывающей панели выделения (Selection Toolbar).
/// Решает проблему зависания и дублирования контекстного меню "Копировать/Вставить":
/// 1. Гарантирует синглтон оверлея — в любой момент времени существует максимум 1 тулбар на весь экран.
/// 2. Оборачивает меню в TapRegion: тап в любое место за пределами тулбара мгновенно скрывает его.
/// 3. Реагирует на смену видимости selectionOverlayController и скрывается при снятии выделения.
class QuantumSelectionToolbarController implements SelectionToolbarController {
  final ToolbarMenuBuilder builder;
  static OverlayEntry? _activeEntry;
  static VoidCallback? _activeVisibilityListener;
  static ValueNotifier<bool>? _activeVisibility;

  QuantumSelectionToolbarController({required this.builder});

  static void dismissAll() {
    if (_activeVisibility != null && _activeVisibilityListener != null) {
      try {
        _activeVisibility!.removeListener(_activeVisibilityListener!);
      } catch (_) {}
      _activeVisibility = null;
      _activeVisibilityListener = null;
    }
    if (_activeEntry != null) {
      try {
        _activeEntry?.remove();
      } catch (_) {}
      _activeEntry = null;
    }
  }

  @override
  void hide(BuildContext context) {
    dismissAll();
  }

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    dismissAll();

    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    void onVisibilityChanged() {
      if (!visibility.value) {
        Future.microtask(() => dismissAll());
      }
    }

    visibility.addListener(onVisibilityChanged);
    _activeVisibility = visibility;
    _activeVisibilityListener = onVisibilityChanged;

    final entry = OverlayEntry(
      builder: (entryContext) {
        return CodeEditorTapRegion(
          child: Directionality(
            textDirection: Directionality.of(context),
            child: ValueListenableBuilder<bool>(
              valueListenable: visibility,
              builder: (ctx, isVisible, child) {
                if (!isVisible) return const SizedBox.shrink();
                return CompositedTransformFollower(
                  link: layerLink,
                  showWhenUnlinked: false,
                  offset: renderRect != null ? -renderRect.topLeft : Offset.zero,
                  child: CodeEditorTapRegion(
                    child: builder(
                      context: context,
                      anchors: anchors,
                      controller: controller,
                      onDismiss: () => dismissAll(),
                      onRefresh: () {
                        dismissAll();
                        show(
                          context: context,
                          controller: controller,
                          anchors: anchors,
                          renderRect: renderRect,
                          layerLink: layerLink,
                          visibility: visibility,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _activeEntry = entry;
  }
}

class StableEditorWidget extends ConsumerStatefulWidget {
  final EditorFile file;
  final SettingsState settings;

  const StableEditorWidget({
    super.key,
    required this.file,
    required this.settings,
  });

  @override
  ConsumerState<StableEditorWidget> createState() => StableEditorWidgetState();
}

class StableEditorWidgetState extends ConsumerState<StableEditorWidget> {
  late List<CodeDiagnostic> _diagnostics;
  late List<DiffMarker> _diffMarkers;
  late final CodeFindController _findController;
  late final SelectionToolbarController _toolbarController;
  List<AIAction> _pendingActions = [];

  final Map<int, Offset> _pinchPointers = {};
  double _pinchInitialDistance = 0.0;
  double _pinchInitialFontSize = 14.0;

  static final Map<String, String> _fontCache = {};
  static const int _autoCloseMaxLines = 500;

  String _getFontFamily(String fontName) {
    if (fontName == 'Monospace') return 'monospace';
    if (_fontCache.containsKey(fontName)) return _fontCache[fontName]!;
    try {
      final family = GoogleFonts.getFont(fontName).fontFamily ?? 'monospace';
      _fontCache[fontName] = family;
      return family;
    } catch (_) {
      return 'monospace';
    }
  }

  // Cached static resources — created once, never rebuilt
  static final CodeHighlightTheme _highlightTheme = CodeHighlightTheme(
    languages: {
      'dart': CodeHighlightThemeMode(mode: langDart),
      'json': CodeHighlightThemeMode(mode: langJson),
      'html': CodeHighlightThemeMode(mode: langXml),
      'xml': CodeHighlightThemeMode(mode: langXml),
      'js': CodeHighlightThemeMode(mode: langJavascript),
      'javascript': CodeHighlightThemeMode(mode: langJavascript),
      'yaml': CodeHighlightThemeMode(mode: langYaml),
      'markdown': CodeHighlightThemeMode(mode: langMarkdown),
      'py': CodeHighlightThemeMode(mode: langPython),
      'python': CodeHighlightThemeMode(mode: langPython),
      'cpp': CodeHighlightThemeMode(mode: langCpp),
      'java': CodeHighlightThemeMode(mode: langJava),
      'php': CodeHighlightThemeMode(mode: langPhp),
    },
    theme: atomOneDarkTheme,
  );

  CodeLineEditingValue? _previousValue;
  bool _isAutoClosing = false;

  void _setupControllerListener() {
    _previousValue = widget.file.controller.value;
    widget.file.controller.addListener(_handleControllerChange);
  }

  void _removeControllerListener() {
    widget.file.controller.removeListener(_handleControllerChange);
  }

  void _handleControllerChange() {
    if (_isAutoClosing) return;

    final controller = widget.file.controller;
    final currentValue = controller.value;
    final previousValue = _previousValue;
    _previousValue = currentValue;

    if (previousValue == null) return;

    final currentSelection = currentValue.selection;
    final previousSelection = previousValue.selection;

    if (!currentSelection.isCollapsed || !previousSelection.isCollapsed) return;
    if (currentSelection.extentIndex != previousSelection.extentIndex) return;
    if (currentValue.codeLines.length > _autoCloseMaxLines) return;

    final lineIndex = currentSelection.extentIndex;
    if (lineIndex >= currentValue.codeLines.length || lineIndex >= previousValue.codeLines.length) return;

    final currentOffset = currentSelection.extentOffset;
    final previousOffset = previousSelection.extentOffset;
    final currentLineText = currentValue.codeLines[lineIndex].text;
    final prevLineText = previousValue.codeLines[lineIndex].text;

    // 1. Backspace matching pair on the same line (O(1))
    if (currentLineText.length == prevLineText.length - 1 && currentOffset == previousOffset - 1) {
      if (currentOffset >= 0 && currentOffset < currentLineText.length &&
          previousOffset > 0 && previousOffset <= prevLineText.length) {
        final deletedChar = prevLineText[currentOffset];
        if (currentOffset + 1 < prevLineText.length) {
          final nextCharInPrev = prevLineText[currentOffset + 1];

          bool isPair = false;
          if ((deletedChar == '(' && nextCharInPrev == ')') ||
              (deletedChar == '{' && nextCharInPrev == '}') ||
              (deletedChar == '[' && nextCharInPrev == ']') ||
              (deletedChar == '"' && nextCharInPrev == '"') ||
              (deletedChar == "'" && nextCharInPrev == "'") ||
              (deletedChar == '`' && nextCharInPrev == '`')) {
            isPair = true;
          }

          if (isPair && currentOffset < currentLineText.length &&
              currentLineText[currentOffset] == nextCharInPrev) {
            _isAutoClosing = true;

            final newLineText = currentLineText.substring(0, currentOffset) +
                                currentLineText.substring(currentOffset + 1);

            final newLines = List<CodeLine>.generate(currentValue.codeLines.length, (i) {
              if (i == lineIndex) return CodeLine(newLineText);
              return currentValue.codeLines[i];
            });

            controller.value = CodeLineEditingValue(
              codeLines: CodeLines.of(newLines),
              selection: currentSelection,
            );

            _previousValue = controller.value;
            _isAutoClosing = false;
            return;
          }
        }
      }
    }

    // 2. Typing characters on the same line (O(1))
    if (currentLineText.length == prevLineText.length + 1 && currentOffset == previousOffset + 1) {
      if (currentOffset <= 0 || currentOffset > currentLineText.length) return;

      final typedChar = currentLineText[currentOffset - 1];

      // Step over closing character (overtype prevention)
      if (typedChar == ')' || typedChar == '}' || typedChar == ']' ||
          typedChar == '"' || typedChar == "'" || typedChar == '`') {
        if (previousOffset < prevLineText.length &&
            prevLineText[previousOffset] == typedChar) {
          _isAutoClosing = true;

          controller.value = previousValue.copyWith(
            selection: currentSelection,
          );

          _previousValue = controller.value;
          _isAutoClosing = false;
          return;
        }
      }

      // Auto-close opening character
      String? closingChar;
      switch (typedChar) {
        case '(':
          closingChar = ')';
          break;
        case '{':
          closingChar = '}';
          break;
        case '[':
          closingChar = ']';
          break;
        case '"':
          closingChar = '"';
          break;
        case "'":
          closingChar = "'";
          break;
        case '`':
          closingChar = '`';
          break;
      }

      if (closingChar != null) {
        // Don't auto-close quotes if the next character is already a letter, number, or quote
        if ((typedChar == '"' || typedChar == "'" || typedChar == '`') &&
            currentOffset < currentLineText.length) {
          final nextChar = currentLineText[currentOffset];
          final RegExp wordChar = RegExp(r'[a-zA-Z0-9_]');
          if (wordChar.hasMatch(nextChar) || nextChar == "'" || nextChar == '"' || nextChar == '`') {
            return;
          }
        }

        _isAutoClosing = true;

        final newLineText = currentLineText.substring(0, currentOffset) +
                            closingChar +
                            currentLineText.substring(currentOffset);

        final newLines = List<CodeLine>.generate(currentValue.codeLines.length, (i) {
          if (i == lineIndex) return CodeLine(newLineText);
          return currentValue.codeLines[i];
        });

        controller.value = CodeLineEditingValue(
          codeLines: CodeLines.of(newLines),
          selection: currentSelection,
        );

        _previousValue = controller.value;
        _isAutoClosing = false;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.file.diagnostics;
    _diffMarkers = widget.file.diffMarkers;
    _findController = CodeFindController(widget.file.controller);
    _toolbarController = QuantumSelectionToolbarController(builder: _buildToolbarMenu);
    _setupControllerListener();
  }

  @override
  void dispose() {
    QuantumSelectionToolbarController.dismissAll();
    _removeControllerListener();
    _findController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StableEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      QuantumSelectionToolbarController.dismissAll();
    }
    // Обновляем только диагностику и маркеры — не пересоздаём CodeEditor
    if (widget.file.diagnostics != oldWidget.file.diagnostics ||
        widget.file.diffMarkers != oldWidget.file.diffMarkers) {
      setState(() {
        _diagnostics = widget.file.diagnostics;
        _diffMarkers = widget.file.diffMarkers;
      });
    }
  }

  String _getSelectedText() {
    final controller = widget.file.controller;
    if (controller.selectedText.isNotEmpty) {
      return controller.selectedText;
    }
    final selection = controller.selection;
    if (selection.isCollapsed) return '';
    final lines = controller.codeLines;
    if (lines.isEmpty) return '';

    int startLine = selection.start.index;
    int startCol = selection.start.offset;
    int endLine = selection.end.index;
    int endCol = selection.end.offset;

    if (startLine > endLine || (startLine == endLine && startCol > endCol)) {
      final tL = startLine;
      final tC = startCol;
      startLine = endLine;
      startCol = endCol;
      endLine = tL;
      endCol = tC;
    }

    if (startLine < 0 || startLine >= lines.length) return '';
    if (endLine < 0 || endLine >= lines.length) return '';

    if (startLine == endLine) {
      final lineText = lines[startLine].text;
      final s = startCol.clamp(0, lineText.length);
      final e = endCol.clamp(0, lineText.length);
      if (s > e) return lineText.substring(e, s);
      return lineText.substring(s, e);
    }

    final buffer = StringBuffer();
    final firstLine = lines[startLine].text;
    buffer.writeln(firstLine.substring(startCol.clamp(0, firstLine.length)));

    for (int i = startLine + 1; i < endLine; i++) {
      buffer.writeln(lines[i].text);
    }

    final lastLine = lines[endLine].text;
    buffer.write(lastLine.substring(0, endCol.clamp(0, lastLine.length)));
    return buffer.toString();
  }

  void _showDesktopContextMenu(BuildContext context, Offset position) {
    final selectedText = _getSelectedText();
    final hasSelection = selectedText.isNotEmpty;
    final l10n = AppLocalizations.of(context)!;
    final controller = widget.file.controller;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1E2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        if (hasSelection) ...[
          PopupMenuItem(
            value: 'cut',
            child: Row(
              children: [
                const Icon(LucideIcons.scissors, size: 14, color: Colors.white70),
                const SizedBox(width: 8),
                Text(l10n.cut, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                const Icon(LucideIcons.copy, size: 14, color: Colors.white70),
                const SizedBox(width: 8),
                Text(l10n.copy, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        ],
        PopupMenuItem(
          value: 'paste',
          child: Row(
            children: [
              const Icon(LucideIcons.clipboard, size: 14, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.paste, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
          PopupMenuItem(
            value: 'selectAll',
            child: Row(
              children: [
                const Icon(LucideIcons.square, size: 14, color: Colors.white70),
                const SizedBox(width: 8),
                Text(l10n.selectAll, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        if (hasSelection)
          PopupMenuItem(
            value: 'aiHelp',
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles, size: 14, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                Text(
                  'AI Help',
                  style: GoogleFonts.inter(
                    color: Colors.purpleAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'aiExplain',
          child: Row(
            children: [
              const Icon(LucideIcons.brain, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                hasSelection ? 'Explain this code' : 'Explain file',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'aiRefactor',
          child: Row(
            children: [
              Icon(LucideIcons.wrench, size: 14, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text(
                'Refactor',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'goToDefinition',
          child: Row(
            children: [
              const Icon(LucideIcons.arrow_right, size: 14, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.goToDefinition, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'findUsages',
          child: Row(
            children: [
              const Icon(LucideIcons.search, size: 14, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.usages, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(LucideIcons.pencil, size: 14, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.rename, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'format',
          child: Row(
            children: [
              const Icon(LucideIcons.code, size: 14, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.format, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      
      switch (value) {
        case 'cut':
          final cutText = _getSelectedText();
          if (cutText.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: cutText));
            controller.replaceSelection('');
          }
          try { controller.cut(); } catch (_) {}
          break;
        case 'copy':
          final copyText = _getSelectedText();
          if (copyText.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: copyText));
          } else {
            final lineIdx = controller.selection.extentIndex;
            if (lineIdx >= 0 && lineIdx < controller.codeLines.length) {
              Clipboard.setData(ClipboardData(text: controller.codeLines[lineIdx].text));
            }
          }
          try { controller.copy(); } catch (_) {}
          break;
        case 'paste':
          Clipboard.getData(Clipboard.kTextPlain).then((data) {
            if (data?.text != null && data!.text!.isNotEmpty) {
              controller.replaceSelection(data.text!);
            } else {
              try { controller.paste(); } catch (_) {}
            }
          });
          break;
        case 'selectAll':
          if (controller.codeLines.isNotEmpty) {
            final lastIdx = controller.codeLines.length - 1;
            final lastLen = controller.codeLines[lastIdx].text.length;
            controller.selection = CodeLineSelection(
              baseIndex: 0,
              baseOffset: 0,
              extentIndex: lastIdx,
              extentOffset: lastLen,
            );
          }
          try { controller.selectAll(); } catch (_) {}
          break;
        case 'aiHelp':
        case 'aiExplain':
          _sendToAiChat(selectedText.isNotEmpty ? selectedText : controller.text, 'explain');
          break;
        case 'aiRefactor':
          _sendToAiChat(selectedText, 'refactor');
          break;
        case 'goToDefinition':
          ref.read(editorProvider.notifier).goToDefinition();
          break;
        case 'findUsages':
          _findUsages(context);
          break;
        case 'rename':
          _renameSymbol(context);
          break;
        case 'format':
          ref.read(editorProvider.notifier).formatActiveFile();
          break;
      }
    });
  }

  void _sendToAiChat(String code, String mode) {
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
    
    String prompt;
    if (mode == 'refactor') {
      prompt = 'Please refactor this code:\n\n```dart\n$code\n```';
    } else {
      prompt = 'Please explain this code:\n\n```dart\n$code\n```';
    }
    
    ref.read(aiProvider.notifier).askAI(prompt);
  }

  void _findUsages(BuildContext context) async {
    final locations = await ref.read(editorProvider.notifier).getReferences();
    if (locations.isNotEmpty && context.mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E2230),
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                AppLocalizations.of(context)!.usages,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                itemCount: locations.length,
                itemBuilder: (context, index) {
                  final loc = locations[index];
                  final fileName = p.basename(Uri.parse(loc.uri).toFilePath());
                  return ListTile(
                    title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(
                      'Line ${loc.range.start.line + 1}, Column ${loc.range.start.character + 1}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(editorProvider.notifier).openFile(
                        Uri.parse(loc.uri).toFilePath(),
                        line: loc.range.start.line,
                        column: loc.range.start.character,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    }
  }

  void _renameSymbol(BuildContext context) async {
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        title: Text(
          AppLocalizations.of(context)!.rename,
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.rename,
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      ref.read(editorProvider.notifier).rename(newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AIState>(aiProvider, (previous, current) {
      final pending = current.proposedActions
          .where((a) => a.path == widget.file.path && (a.type == 'edit' || a.type == 'create'))
          .toList();
      if (pending != _pendingActions) {
        if (mounted) {
          setState(() {
            _pendingActions = pending;
          });
        }
      }
    });

    final settings = widget.settings;
    final file = widget.file;

    final hasPendingAction = _pendingActions.isNotEmpty;

    if (file.isImage) {
      const sizeKb = '—';
      
      return Container(
        color: const Color(0xFF0F111A), // Sleek deep dark background
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161925),
                        border: Border.all(color: Colors.white10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InteractiveViewer(
                        maxScale: 5.0,
                        child: Center(
                          child: Hero(
                            tag: file.path,
                            child: Image.file(
                              File(file.path),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(LucideIcons.image_off, color: Colors.redAccent, size: 48),
                                      const SizedBox(height: 16),
                                      Text(
                                        AppLocalizations.of(context)!.imageLoadError,
                                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Info panel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF161925),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          file.path,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      '$sizeKb KB',
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final performanceService = ref.read(editorPerformanceServiceProvider);
    final applyHighlighting = performanceService.shouldApplySyntaxHighlighting(file.controller);
    if (performanceService.isLargeFile(file.controller)) {
      performanceService.optimizeForLargeFile(file.controller);
    }

    Widget editorWidget = CodeEditor(
      controller: file.controller,
      wordWrap: settings.wordWrap,
      chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
      findController: _findController,
      findBuilder: (context, controller, readOnly) => CodeFindPanelView(
        controller: controller,
        readOnly: readOnly,
      ),
      toolbarController: _toolbarController,
      indicatorBuilder: (context, controller, chunkController, notifier) {
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: DiffBackgroundPainter(
                    notifier: notifier,
                    markers: _diffMarkers,
                  ),
                  size: Size.zero,
                ),
              ),
            ),
            Row(
              children: [
                if (settings.lineNumbers) ...[
                  DefaultCodeLineNumber(controller: controller, notifier: notifier),
                  const SizedBox(width: 8),
                ],
                DefaultCodeChunkIndicator(width: 20, controller: chunkController, notifier: notifier),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DiagnosticIndicator(diagnostics: _diagnostics, notifier: notifier),
              ),
            ),
            Positioned(
              left: 0, top: 0, bottom: 0, width: 4,
              child: IgnorePointer(
                child: DiffGutterIndicator(
                  controller: controller,
                  markers: _diffMarkers,
                  notifier: notifier,
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CollaborationPainter(
                    notifier: notifier,
                    filePath: file.path,
                    ref: ref,
                  ),
                  size: Size.zero,
                ),
              ),
            ),
          ],
        );
      },
      style: CodeEditorStyle(
        fontSize: settings.fontSize,
        fontFamily: _getFontFamily(settings.editorFontFamily),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        codeTheme: applyHighlighting ? _highlightTheme : null,
      ),
    );

    editorWidget = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification || notification is ScrollUpdateNotification) {
          QuantumSelectionToolbarController.dismissAll();
        }
        return false;
      },
      child: editorWidget,
    );

    if (settings.minimap) {
      editorWidget = Row(
        children: [
          Expanded(child: editorWidget),
          EditorMinimap(controller: file.controller, width: 70),
        ],
      );
    }

    if (hasPendingAction) {
      final action = _pendingActions.first;
      final l10n = AppLocalizations.of(context)!;
      
      final hunks = DiffService.calculateHunks(file.originalContent, file.controller.text);
      int additions = 0;
      int deletions = 0;
      for (final hunk in hunks) {
        if (hunk.type == DiffType.added) {
          additions += (hunk.endLine - hunk.startLine + 1);
        } else if (hunk.type == DiffType.removed) {
          deletions += 1;
        } else if (hunk.type == DiffType.modified) {
          additions += (hunk.endLine - hunk.startLine + 1);
          deletions += (hunk.endLine - hunk.startLine + 1);
        }
      }

      editorWidget = Stack(
        children: [
          Positioned.fill(child: editorWidget),
          Positioned(
            right: 16,
            bottom: 16,
            width: 290,
            child: GlassContainer(
              blur: 24,
              opacity: 0.18,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25), width: 0.8),
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card Header
                    Row(
                      children: [
                        const Icon(LucideIcons.sparkles, color: Colors.purpleAccent, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.pendingDiff,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (additions > 0)
                          Text(
                            '+$additions',
                            style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        if (additions > 0 && deletions > 0) const SizedBox(width: 4),
                        if (deletions > 0)
                          Text(
                            '-$deletions',
                            style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(height: 0.5, color: Colors.white10),
                    const SizedBox(height: 6),
                    
                    // Contiguous hunks list
                    if (hunks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            l10n.noChanges,
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: SingleChildScrollView(
                          child: Column(
                            children: List.generate(hunks.length, (hIdx) {
                              final hunk = hunks[hIdx];
                              final String typeLabel = hunk.type == DiffType.added
                                  ? l10n.added
                                  : hunk.type == DiffType.removed
                                      ? l10n.removed
                                      : l10n.modified;
                              final Color typeColor = hunk.type == DiffType.added
                                  ? Colors.greenAccent
                                  : hunk.type == DiffType.removed
                                      ? Colors.redAccent
                                      : Colors.amberAccent;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  children: [
                                    Icon(LucideIcons.circle, size: 6, color: typeColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'L${hunk.startLine + 1}-${hunk.endLine + 1} $typeLabel',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Individual Hunk Keep Button
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        ref.read(editorProvider.notifier).applyHunkAction(file.path, hIdx, true);
                                      },
                                      child: Text(
                                        l10n.keep,
                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    // Individual Hunk Reject Button
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        ref.read(editorProvider.notifier).applyHunkAction(file.path, hIdx, false);
                                      },
                                      child: Text(
                                        l10n.reject,
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 8),
                    Container(height: 0.5, color: Colors.white10),
                    const SizedBox(height: 8),
                    
                    // Card Level Keep all / Reject all Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent.withValues(alpha: 0.12),
                              foregroundColor: Colors.greenAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3)),
                              ),
                            ),
                            onPressed: () {
                              ref.read(editorProvider.notifier).acceptProposedChanges(file.path, action);
                            },
                            child: Text(
                              l10n.keepAll,
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
                              foregroundColor: Colors.redAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                              ),
                            ),
                            onPressed: () {
                              ref.read(editorProvider.notifier).revertProposedChanges(file.path, action);
                            },
                            child: Text(
                              l10n.rejectAll,
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final aiState = ref.watch(aiAutocompleteServiceProvider);
    final hasAiSuggestion = aiState.suggestion != null &&
        aiState.suggestion!.trim().isNotEmpty &&
        aiState.filePath == file.path;

    if (hasAiSuggestion && !hasPendingAction) {
      editorWidget = Stack(
        children: [
          editorWidget,
          Positioned(
            bottom: 16,
            right: 16,
            child: _buildCopilotGhostTextBar(file, aiState),
          ),
        ],
      );
    }

    return Listener(
      onPointerDown: (e) {
        _pinchPointers[e.pointer] = e.position;
        if (_pinchPointers.length == 2) {
          final pts = _pinchPointers.values.toList();
          _pinchInitialDistance = (pts[0] - pts[1]).distance;
          _pinchInitialFontSize = widget.settings.fontSize;
        }
      },
      onPointerMove: (e) {
        _pinchPointers[e.pointer] = e.position;
        if (_pinchPointers.length == 2 && _pinchInitialDistance > 10) {
          final pts = _pinchPointers.values.toList();
          final currentDist = (pts[0] - pts[1]).distance;
          final scale = currentDist / _pinchInitialDistance;
          final target = (_pinchInitialFontSize * scale).clamp(11.0, 32.0);
          final rounded = (target * 2).round() / 2.0;
          if ((rounded - widget.settings.fontSize).abs() >= 0.5) {
            ref.read(settingsProvider.notifier).setFontSize(rounded);
          }
        }
      },
      onPointerUp: (e) {
        _pinchPointers.remove(e.pointer);
      },
      onPointerCancel: (e) {
        _pinchPointers.remove(e.pointer);
      },
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
          final delta = e.scrollDelta.dy < 0 ? 1.0 : -1.0;
          final newSize = (widget.settings.fontSize + delta).clamp(11.0, 32.0);
          ref.read(settingsProvider.notifier).setFontSize(newSize);
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.tab): () {
            if (hasAiSuggestion) {
              _applyAiSuggestion(file.controller, aiState.suggestion!, aiState.triggerWord);
              ref.read(aiAutocompleteServiceProvider.notifier).clear();
            }
          },
        },
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            _showDesktopContextMenu(context, details.globalPosition);
          },
          child: editorWidget,
        ),
      ),
    );
  }

  Widget _buildToolbarMenu({
    required BuildContext context,
    required TextSelectionToolbarAnchors anchors,
    required CodeLineEditingController controller,
    required VoidCallback onDismiss,
    required VoidCallback onRefresh,
  }) {
    final List<ContextMenuButtonItem> buttonItems = [];
    final l10n = AppLocalizations.of(context)!;

    if (!controller.selection.isCollapsed || controller.selectedText.isNotEmpty) {
      buttonItems.add(
        ContextMenuButtonItem(
          label: l10n.cut,
          onPressed: () async {
            final text = controller.selectedText.isNotEmpty
                ? controller.selectedText
                : _getSelectedText();
            if (text.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: text));
              controller.replaceSelection('');
            }
            try { controller.cut(); } catch (_) {}
            onDismiss();
          },
        ),
      );
      buttonItems.add(
        ContextMenuButtonItem(
          label: l10n.copy,
          onPressed: () async {
            final text = controller.selectedText.isNotEmpty
                ? controller.selectedText
                : _getSelectedText();
            if (text.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: text));
            } else {
              final lineIdx = controller.selection.extentIndex;
              if (lineIdx >= 0 && lineIdx < controller.codeLines.length) {
                await Clipboard.setData(ClipboardData(text: controller.codeLines[lineIdx].text));
              }
            }
            try { controller.copy(); } catch (_) {}
            onDismiss();
          },
        ),
      );
    }

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.paste,
        onPressed: () async {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data?.text != null && data!.text!.isNotEmpty) {
            controller.replaceSelection(data.text!);
          } else {
            try { controller.paste(); } catch (_) {}
          }
          onDismiss();
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.selectAll,
        onPressed: () {
          if (controller.codeLines.isNotEmpty) {
            final lastIdx = controller.codeLines.length - 1;
            final lastLen = controller.codeLines[lastIdx].text.length;
            controller.selection = CodeLineSelection(
              baseIndex: 0,
              baseOffset: 0,
              extentIndex: lastIdx,
              extentOffset: lastLen,
            );
          }
          try { controller.selectAll(); } catch (_) {}
          onRefresh();
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.goToDefinition,
        onPressed: () {
          onDismiss();
          ref.read(editorProvider.notifier).goToDefinition();
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.search,
        onPressed: () {
          onDismiss();
          _findController.findMode();
          _findController.focusOnFindInput();
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.info,
        onPressed: () async {
          onDismiss();
          final hover = await ref.read(editorProvider.notifier).getHover();
          if (hover != null && context.mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E2230),
                title: Text(l10n.documentation, style: const TextStyle(color: Colors.white, fontSize: 16)),
                content: SingleChildScrollView(
                  child: Text(
                    hover.contents,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.ok),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.usages,
        onPressed: () async {
          onDismiss();
          final locations = await ref.read(editorProvider.notifier).getReferences();
          if (locations.isNotEmpty && context.mounted) {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF1E2230),
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(l10n.usages, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: locations.length,
                      itemBuilder: (context, index) {
                        final loc = locations[index];
                        final fileName = p.basename(Uri.parse(loc.uri).toFilePath());
                        return ListTile(
                          title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: Text('${l10n.line} ${loc.range.start.line + 1}, ${l10n.column} ${loc.range.start.character + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          onTap: () {
                            Navigator.pop(context);
                            ref.read(editorProvider.notifier).openFile(Uri.parse(loc.uri).toFilePath(), line: loc.range.start.line, column: loc.range.start.character);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.rename,
        onPressed: () async {
          onDismiss();
          final renameCtrl = TextEditingController();
          final newName = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E2230),
              title: Text(l10n.rename, style: const TextStyle(color: Colors.white)),
              content: TextField(
                controller: renameCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: l10n.rename,
                  hintStyle: const TextStyle(color: Colors.white38),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                TextButton(onPressed: () => Navigator.pop(context, renameCtrl.text), child: Text(l10n.ok)),
              ],
            ),
          );
          if (newName != null && newName.isNotEmpty) {
            ref.read(editorProvider.notifier).rename(newName);
          }
        },
      ),
    );

    buttonItems.add(
      ContextMenuButtonItem(
        label: l10n.format,
        onPressed: () {
          onDismiss();
          ref.read(editorProvider.notifier).formatActiveFile();
        },
      ),
    );

    return CodeEditorTapRegion(
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: buttonItems,
      ),
    );
  }

  Widget _buildCopilotGhostTextBar(EditorFile file, AiAutocompleteState aiState) {
    final suggestion = aiState.suggestion!;
    final preview = suggestion.trim().split('\n').first;
    return Material(
      color: Colors.transparent,
      child: GlassContainer(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.45), width: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.sparkles, color: Colors.deepPurpleAccent, size: 14),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                preview,
                style: GoogleFonts.firaCode(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                _applyAiSuggestion(file.controller, suggestion, aiState.triggerWord);
                ref.read(aiAutocompleteServiceProvider.notifier).clear();
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.4), width: 0.5),
                ),
                child: Text(
                  'Tab ⇥',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 14, color: Colors.white38),
              onPressed: () => ref.read(aiAutocompleteServiceProvider.notifier).clear(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              splashRadius: 12,
            ),
          ],
        ),
      ),
    );
  }

  void _applyAiSuggestion(CodeLineEditingController controller, String suggestion, String? triggerWord) {
    var insertText = suggestion;
    if (triggerWord != null && triggerWord.isNotEmpty && insertText.startsWith(triggerWord)) {
      insertText = insertText.substring(triggerWord.length);
    }
    controller.replaceSelection(insertText);
  }
}



class ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;
  final Color? borderColor;
  final double size;
  final double iconSize;

  const ActionIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.backgroundColor,
    this.borderColor,
    this.size = 32,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Colors.white.withValues(alpha: 0.85);
    final isCustomColor = color != null && color != Colors.white70 && color != Colors.white;

    final effectiveBg = backgroundColor ??
        (isCustomColor
            ? color!.withValues(alpha: 0.12)
            : const Color(0xFF161922).withValues(alpha: 0.85));

    final effectiveBorder = borderColor ??
        (isCustomColor
            ? color!.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.08));

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: (color ?? Colors.cyanAccent).withValues(alpha: 0.2),
        highlightColor: (color ?? Colors.cyanAccent).withValues(alpha: 0.1),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: effectiveBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: effectiveBorder, width: 0.8),
            boxShadow: isCustomColor
                ? [
                    BoxShadow(
                      color: color!.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: effectiveColor,
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 350),
        child: button,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: button,
    );
  }
}



class QuantumAutocompleteView extends StatelessWidget implements PreferredSizeWidget {
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  const QuantumAutocompleteView({super.key, 
    required this.notifier,
    required this.onSelected,
  });

  @override
  Size get preferredSize => const Size(310, 240);

  IconData _getPromptIcon(CodePrompt prompt) {
    if (prompt is AiAutocompletePrompt) return LucideIcons.sparkles;
    if (prompt is CodeSnippetPrompt) return LucideIcons.boxes;
    if (prompt is LspCompletionPrompt) return LucideIcons.box;
    if (prompt is CodeKeywordPrompt) return LucideIcons.key_round;
    return LucideIcons.code;
  }

  Color _getPromptColor(CodePrompt prompt) {
    if (prompt is AiAutocompletePrompt) return Colors.purpleAccent;
    if (prompt is CodeSnippetPrompt) return Colors.amberAccent;
    if (prompt is LspCompletionPrompt) return Colors.cyanAccent;
    if (prompt is CodeKeywordPrompt) return Colors.blueAccent;
    return Colors.white70;
  }

  String _getPromptBadge(CodePrompt prompt) {
    if (prompt is AiAutocompletePrompt) return 'ИИ ✨';
    if (prompt is CodeSnippetPrompt) return 'сниппет';
    if (prompt is LspCompletionPrompt) return 'LSP';
    if (prompt is CodeKeywordPrompt) return 'ключ';
    return 'слово';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, child) {
        if (value.prompts.isEmpty) return const SizedBox();
        return Container(
          margin: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
          child: GlassContainer(
            blur: 40,
            opacity: 0.35,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25), width: 0.8),
            child: Container(
              width: 310,
              constraints: BoxConstraints(
                maxHeight: bottomInset > 0 ? 190 : 240,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0F121C).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.sparkles, size: 10, color: Colors.cyanAccent),
                        const SizedBox(width: 5),
                        Text(
                          'VS Code IntelliSense (${value.prompts.length})',
                          style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white54, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          'Tab / Нажмите',
                          style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white30),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: value.prompts.length,
                      itemBuilder: (context, index) {
                        final prompt = value.prompts[index];
                        final isSelected = value.index == index;
                        final icon = _getPromptIcon(prompt);
                        final color = _getPromptColor(prompt);
                        final badge = _getPromptBadge(prompt);

                        return InkWell(
                          onTap: () => onSelected(value.copyWith(index: index).autocomplete),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? color.withValues(alpha: 0.18)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3.5),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(icon, size: 12, color: color),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    prompt.word,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.jetBrainsMono(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontSize: 12.5,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    badge,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}



class FloatingCapsuleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const FloatingCapsuleButton({super.key, 
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF4CD7F6)),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 8,
                color: Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}




