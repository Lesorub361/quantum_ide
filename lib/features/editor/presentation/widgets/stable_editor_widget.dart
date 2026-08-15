import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/ai_autocomplete_service.dart';
import 'package:quantum_ide/features/editor/presentation/handlers/autocomplete_handler.dart';
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
import 'package:quantum_ide/core/services/lsp_autocomplete_service.dart';
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

  String _getFontFamily(String fontName) {
    if (fontName == 'Monospace') return 'monospace';
    try {
      return GoogleFonts.getFont(fontName).fontFamily ?? 'monospace';
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

    // We only care about collapsed, single line selections
    if (!currentSelection.isCollapsed || !previousSelection.isCollapsed) return;
    if (currentSelection.extentIndex != previousSelection.extentIndex) return;

    final currentOffset = currentSelection.extentOffset;
    final previousOffset = previousSelection.extentOffset;
    final currentText = controller.text;
    final previousText = previousValue.codeLines.toString();

    // Backspace matching pair
    if (currentText.length == previousText.length - 1) {
      if (currentSelection.extentIndex == previousSelection.extentIndex &&
          currentOffset == previousOffset - 1) {
        final lineIndex = currentSelection.extentIndex;
        if (lineIndex < currentValue.codeLines.length) {
          final currentLineText = currentValue.codeLines[lineIndex].text;
          final prevLineText = previousValue.codeLines[lineIndex].text;

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
                
                final List<String> newLinesList = [];
                for (int i = 0; i < currentValue.codeLines.length; i++) {
                  if (i == lineIndex) {
                    newLinesList.add(newLineText);
                  } else {
                    newLinesList.add(currentValue.codeLines[i].text);
                  }
                }
                
                final newText = newLinesList.join('\n');
                
                controller.value = CodeLineEditingValue(
                  codeLines: CodeLines.fromText(newText),
                  selection: currentSelection,
                );
                
                _previousValue = controller.value;
                _isAutoClosing = false;
                return;
              }
            }
          }
        }
      }
    }

    // Check if exactly one character was added on the same line
    if (currentText.length == previousText.length + 1) {
      if (currentSelection.extentIndex == previousSelection.extentIndex &&
          currentOffset == previousOffset + 1) {
        final lineIndex = currentSelection.extentIndex;
        if (lineIndex >= currentValue.codeLines.length) return;

        final lineText = currentValue.codeLines[lineIndex].text;
        if (currentOffset <= 0 || currentOffset > lineText.length) return;

        final typedChar = lineText[currentOffset - 1];

        // Step over closing character (overtype prevention)
        if (typedChar == ')' || typedChar == '}' || typedChar == ']' ||
            typedChar == '"' || typedChar == "'" || typedChar == '`') {
          final prevLineText = previousValue.codeLines[lineIndex].text;
          if (previousOffset < prevLineText.length && 
              prevLineText[previousOffset] == typedChar) {
            _isAutoClosing = true;
            
            final List<String> oldLinesList = [];
            for (int i = 0; i < previousValue.codeLines.length; i++) {
              oldLinesList.add(previousValue.codeLines[i].text);
            }
            final revertedText = oldLinesList.join('\n');
            
            controller.value = CodeLineEditingValue(
              codeLines: CodeLines.fromText(revertedText),
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
              currentOffset < lineText.length) {
            final nextChar = lineText[currentOffset];
            final RegExp wordChar = RegExp(r'[a-zA-Z0-9_]');
            if (wordChar.hasMatch(nextChar) || nextChar == "'" || nextChar == '"' || nextChar == '`') {
              return;
            }
          }

          _isAutoClosing = true;

          final newLineText = lineText.substring(0, currentOffset) +
                              closingChar +
                              lineText.substring(currentOffset);

          final List<String> newLinesList = [];
          for (int i = 0; i < currentValue.codeLines.length; i++) {
            if (i == lineIndex) {
              newLinesList.add(newLineText);
            } else {
              newLinesList.add(currentValue.codeLines[i].text);
            }
          }

          final newText = newLinesList.join('\n');

          controller.value = CodeLineEditingValue(
            codeLines: CodeLines.fromText(newText),
            selection: currentSelection,
          );

          _previousValue = controller.value;
          _isAutoClosing = false;
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.file.diagnostics;
    _diffMarkers = widget.file.diffMarkers;
    _findController = CodeFindController(widget.file.controller);
    _setupControllerListener();

    ref.listen<AiAutocompleteState>(aiAutocompleteServiceProvider, (previous, current) {
      if (!current.isLoading && current.suggestion != null && current.suggestion!.isNotEmpty) {
        if (current.filePath == widget.file.path) {
          widget.file.controller.value = widget.file.controller.value;
        }
      }
    });
    ref.listen<LspAutocompleteState>(lspAutocompleteServiceProvider, (previous, current) {
      if (!current.isLoading && current.items.isNotEmpty) {
        if (current.filePath == widget.file.path) {
          widget.file.controller.value = widget.file.controller.value;
        }
      }
    });
  }

  @override
  void dispose() {
    _removeControllerListener();
    _findController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StableEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    final selection = controller.selection;
    if (selection.isCollapsed) return '';
    final text = controller.text;
    final lines = text.split('\n');
    final startLine = selection.start.index;
    final startCol = selection.start.offset;
    final endLine = selection.end.index;
    final endCol = selection.end.offset;

    if (startLine >= lines.length || endLine >= lines.length) return '';

    if (startLine == endLine) {
      return lines[startLine].substring(
        startCol.clamp(0, lines[startLine].length),
        endCol.clamp(0, lines[startLine].length),
      );
    }

    final buffer = StringBuffer();
    buffer.writeln(lines[startLine].substring(startCol.clamp(0, lines[startLine].length)));
    for (int i = startLine + 1; i < endLine; i++) {
      buffer.writeln(lines[i]);
    }
    buffer.write(lines[endLine].substring(0, endCol.clamp(0, lines[endLine].length)));
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
            value: 'aiRefactor',
            child: Row(
              children: [
                const Icon(LucideIcons.wrench, size: 14, color: Colors.orangeAccent),
                const SizedBox(width: 8),
                Text(
                  'Refactor',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
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
          controller.cut();
          break;
        case 'copy':
          controller.copy();
          break;
        case 'paste':
          controller.paste();
          break;
        case 'selectAll':
          controller.selectAll();
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
    final settings = widget.settings;
    final file = widget.file;

    final aiState = ref.watch(aiProvider);
    final List<AIAction> pendingActions = aiState.proposedActions.where((a) => a.path == file.path && (a.type == 'edit' || a.type == 'create')).toList();
    final hasPendingAction = pendingActions.isNotEmpty;

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
      toolbarController: MobileSelectionToolbarController(
        builder: ({
          required BuildContext context,
          required TextSelectionToolbarAnchors anchors,
          required CodeLineEditingController controller,
          required VoidCallback onDismiss,
          required VoidCallback onRefresh,
        }) {
          final List<ContextMenuButtonItem> buttonItems = [];
          final l10n = AppLocalizations.of(context)!;
          
          if (!controller.selection.isCollapsed) {
            buttonItems.add(
              ContextMenuButtonItem(
                label: l10n.cut,
                onPressed: () {
                  controller.cut();
                  onDismiss();
                },
              ),
            );
            buttonItems.add(
              ContextMenuButtonItem(
                label: l10n.copy,
                onPressed: () {
                  controller.copy();
                  onDismiss();
                },
              ),
            );
          }
          
          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.paste,
              onPressed: () {
                controller.paste();
                onDismiss();
              },
            ),
          );
          
          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.selectAll,
              onPressed: () {
                controller.selectAll();
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
                final controller = TextEditingController();
                final newName = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E2230),
                    title: Text(l10n.rename, style: const TextStyle(color: Colors.white)),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.rename,
                        hintStyle: const TextStyle(color: Colors.white38),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                      TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.ok)),
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

          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: anchors,
            buttonItems: buttonItems,
          );
        },
      ),
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

    if (settings.minimap) {
      editorWidget = Row(
        children: [
          Expanded(child: editorWidget),
          EditorMinimap(controller: file.controller, width: 70),
        ],
      );
    }

    if (hasPendingAction) {
      final action = pendingActions.first;
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

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showDesktopContextMenu(context, details.globalPosition);
      },
      child: editorWidget,
    );
  }
}



class ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;

  const ActionIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 15, color: color ?? Colors.white70),
      onPressed: onTap,
      tooltip: tooltip,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
  Size get preferredSize => const Size(300, 250);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, child) {
        if (value.prompts.isEmpty) return const SizedBox();
        return GlassContainer(
          blur: 40,
          opacity: 0.2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: value.prompts.length,
              itemBuilder: (context, index) {
                final prompt = value.prompts[index];
                final isSelected = value.index == index;
                final isAi = prompt is AiAutocompletePrompt;
                return InkWell(
                  onTap: () => onSelected(value.copyWith(index: index).autocomplete),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? (isAi 
                              ? Colors.deepPurpleAccent.withValues(alpha: 0.25)
                              : Colors.cyanAccent.withValues(alpha: 0.15))
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isAi
                                ? Colors.deepPurpleAccent.withValues(alpha: 0.15)
                                : Colors.cyanAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            isAi ? LucideIcons.sparkles : LucideIcons.code, 
                            size: 14, 
                            color: isAi ? Colors.deepPurpleAccent : Colors.cyanAccent
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            prompt.word,
                            style: TextStyle(
                              color: isSelected ? Colors.white : (isAi ? Colors.deepPurpleAccent : Colors.white70),
                              fontSize: 14,
                              fontWeight: (isSelected || isAi) ? FontWeight.w600 : FontWeight.w400,
                              fontStyle: isAi ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ),
                        if (isAi)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), width: 0.5),
                              ),
                              child: const Text(
                                'AI ✨',
                                style: TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (isSelected)
                          const Icon(LucideIcons.chevron_right, size: 14, color: Colors.white38),
                      ],
                    ),
                  ),
                );
              },
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




