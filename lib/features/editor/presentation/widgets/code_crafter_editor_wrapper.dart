import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_crafter/code_crafter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/services/code_crafter_ai_service.dart';
import 'package:quantum_ide/core/services/lsp_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';
import 'package:re_editor/re_editor.dart';

/// Wraps [CodeCrafter] from `flutter_code_crafter` and keeps it synchronized
/// two-way with QuantumIDE's [CodeLineEditingController] inside [OpenFile].
class CodeCrafterEditorWrapper extends ConsumerStatefulWidget {
  final EditorFile file;

  const CodeCrafterEditorWrapper({super.key, required this.file});

  @override
  ConsumerState<CodeCrafterEditorWrapper> createState() =>
      _CodeCrafterEditorWrapperState();
}

class _CodeCrafterEditorWrapperState
    extends ConsumerState<CodeCrafterEditorWrapper> {
  late final CodeCrafterController _crafterController;
  LspBridgeConfig? _lspBridge;
  StreamSubscription<FileDiagnostics>? _diagSubscription;
  bool _isSyncingFromReEditor = false;
  bool _isSyncingFromCrafter = false;
  String _lastSyncedText = '';
  CodeLines? _lastReEditorCodeLines;

  @override
  void initState() {
    super.initState();
    final initialText = widget.file.controller.text;
    _lastSyncedText = initialText;
    _lastReEditorCodeLines = widget.file.controller.codeLines;
    _crafterController = CodeCrafterController()
      ..text = initialText
      ..language = _resolveLanguage(widget.file.path);
    _crafterController.addListener(_onCrafterChanged);
    widget.file.controller.addListener(_onReEditorChanged);
    _initLspBridge();
  }

  String _resolveLanguageId(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.dart' => 'dart',
      '.js' || '.mjs' || '.cjs' => 'javascript',
      '.ts' || '.tsx' || '.jsx' => 'typescript',
      '.py' => 'python',
      '.json' => 'json',
      '.yaml' || '.yml' => 'yaml',
      '.html' || '.htm' => 'html',
      '.css' || '.scss' => 'css',
      '.md' || '.markdown' => 'markdown',
      '.c' || '.h' => 'c',
      '.cpp' || '.hpp' || '.cc' => 'cpp',
      '.rs' => 'rust',
      '.go' => 'go',
      '.java' => 'java',
      '.kt' || '.kts' => 'kotlin',
      _ => 'plaintext',
    };
  }

  List<Map<String, dynamic>> _mapDiagnostics(List<CodeDiagnostic> items) {
    return items.map((d) {
      final severity = switch (d.severity) {
        CodeDiagnosticSeverity.error => 1,
        CodeDiagnosticSeverity.warning => 2,
        CodeDiagnosticSeverity.hint => 3,
      };
      return <String, dynamic>{
        'severity': severity,
        'message': d.message,
        'range': {
          'start': {'line': d.range.index, 'character': d.range.start},
          'end': {'line': d.range.index, 'character': d.range.end},
        },
      };
    }).toList();
  }

  void _initLspBridge() {
    _diagSubscription?.cancel();
    _lspBridge?.dispose();

    final lspService = ref.read(lspServiceProvider);
    final workspacePath =
        ref.read(workspaceProvider).currentPath ?? p.dirname(widget.file.path);
    final filePath = widget.file.path;

    late final LspBridgeConfig bridge;
    bridge = LspBridgeConfig(
      filePath: filePath,
      workspacePath: workspacePath,
      languageId: _resolveLanguageId(filePath),
      onOpen: () async {
        // EditorNotifier already sends didOpen to LspService on openFile;
        // just push any existing diagnostics into CodeCrafter.
        if (widget.file.diagnostics.isNotEmpty) {
          bridge.pushDiagnostics(_mapDiagnostics(widget.file.diagnostics));
        }
      },
      onUpdate: (content) async {
        // EditorNotifier already notifies LspService via the synced controller listener.
      },
      onCompletion: (line, character) async {
        final items = await lspService.getCompletions(
          filePath,
          line,
          character,
        );
        return items
            .map(
              (item) => LspCompletion(
                label: item.label,
                itemType: CompletionItemType.values.firstWhere(
                  (t) => t.value == item.kind,
                  orElse: () => CompletionItemType.text,
                ),
              ),
            )
            .toList();
      },
      onHover: (line, character) async {
        final hover = await lspService.getHover(filePath, line, character);
        return hover?.contents ?? '';
      },
    );

    _lspBridge = bridge;
    _diagSubscription = lspService.diagnosticsStream.listen((fileDiags) {
      if (fileDiags.path == filePath) {
        bridge.pushDiagnostics(_mapDiagnostics(fileDiags.diagnostics));
      }
    });

    if (widget.file.diagnostics.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          bridge.pushDiagnostics(_mapDiagnostics(widget.file.diagnostics));
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CodeCrafterEditorWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.file.controller != widget.file.controller) {
      oldWidget.file.controller.removeListener(_onReEditorChanged);
      widget.file.controller.addListener(_onReEditorChanged);
      _isSyncingFromReEditor = true;
      final nextText = widget.file.controller.text;
      _lastSyncedText = nextText;
      _lastReEditorCodeLines = widget.file.controller.codeLines;
      _crafterController.language = _resolveLanguage(widget.file.path);
      _crafterController.text = nextText;
      _isSyncingFromReEditor = false;
      _initLspBridge();
    } else if (oldWidget.file.diagnostics != widget.file.diagnostics) {
      _lspBridge?.pushDiagnostics(_mapDiagnostics(widget.file.diagnostics));
    }
  }

  @override
  void dispose() {
    _diagSubscription?.cancel();
    _lspBridge?.dispose();
    widget.file.controller.removeListener(_onReEditorChanged);
    _crafterController.removeListener(_onCrafterChanged);
    _crafterController.dispose();
    super.dispose();
  }

  void _onCrafterChanged() {
    if (_isSyncingFromReEditor) return;
    final nextText = _crafterController.text;
    // Fast-path: ignore cursor/selection-only notifications without touching re_editor
    if (nextText == _lastSyncedText) return;
    _lastSyncedText = nextText;
    _isSyncingFromCrafter = true;
    widget.file.controller.text = nextText;
    _lastReEditorCodeLines = widget.file.controller.codeLines;
    _isSyncingFromCrafter = false;
  }

  void _onReEditorChanged() {
    if (_isSyncingFromCrafter) return;
    // Fast-path O(1): ignore cursor/selection-only changes when CodeLines reference is unchanged
    final currentLines = widget.file.controller.codeLines;
    if (identical(currentLines, _lastReEditorCodeLines)) return;
    _lastReEditorCodeLines = currentLines;
    final nextText = widget.file.controller.text;
    if (nextText == _lastSyncedText) return;
    _lastSyncedText = nextText;
    _isSyncingFromReEditor = true;
    _crafterController.text = nextText;
    _isSyncingFromReEditor = false;
  }

  dynamic _resolveLanguage(String filePath) {
    final baseName = p.basename(filePath).toLowerCase();
    final ext = p.extension(filePath).toLowerCase();
    final key = switch (baseName) {
      'pubspec.lock' || 'podfile.lock' => 'yaml',
      'dockerfile' || 'containerfile' => 'dockerfile',
      'makefile' => 'makefile',
      _ => switch (ext) {
        '.dart' => 'dart',
        '.js' || '.mjs' || '.cjs' => 'javascript',
        '.ts' || '.tsx' || '.jsx' => 'typescript',
        '.py' => 'python',
        '.json' || '.arb' => 'json',
        '.yaml' || '.yml' => 'yaml',
        '.html' || '.htm' => 'xml',
        '.xml' || '.svg' || '.plist' => 'xml',
        '.css' || '.scss' => 'css',
        '.md' || '.markdown' => 'markdown',
        '.sh' || '.bash' || '.zsh' => 'bash',
        '.c' || '.h' => 'cpp',
        '.cpp' || '.hpp' || '.cc' => 'cpp',
        '.rs' => 'rust',
        '.go' => 'go',
        '.java' => 'java',
        '.kt' || '.kts' => 'kotlin',
        '.sql' => 'sql',
        '.properties' => 'properties',
        '.ini' || '.cfg' || '.conf' || '.toml' || '.env' => 'ini',
        '.gradle' || '.groovy' => 'groovy',
        '.dockerfile' => 'dockerfile',
        _ => null,
      },
    };
    return key != null ? allLanguages[key] : null;
  }

  Map<String, TextStyle> _buildEditorTheme({
    required Color bgColor,
    required Color fgColor,
    required Color accentColor,
    required Color mutedColor,
  }) {
    final isDark =
        ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark;
    return {
      'root': TextStyle(backgroundColor: bgColor, color: fgColor),
      'comment': TextStyle(
        color: mutedColor.withValues(alpha: 0.78),
        fontStyle: FontStyle.italic,
      ),
      'quote': TextStyle(
        color: mutedColor.withValues(alpha: 0.78),
        fontStyle: FontStyle.italic,
      ),
      'keyword': TextStyle(
        color: isDark ? const Color(0xFFC678DD) : const Color(0xFF9333EA),
        fontWeight: FontWeight.w600,
      ),
      'selector-tag': TextStyle(
        color: isDark ? const Color(0xFFC678DD) : const Color(0xFF9333EA),
      ),
      'string': TextStyle(
        color: isDark ? const Color(0xFF98C379) : const Color(0xFF15803D),
      ),
      'title': TextStyle(
        color: accentColor,
        fontWeight: FontWeight.w600,
      ),
      'section': TextStyle(
        color: accentColor,
        fontWeight: FontWeight.w600,
      ),
      'type': TextStyle(
        color: isDark ? const Color(0xFFE5C07B) : const Color(0xFFB45309),
      ),
      'built_in': TextStyle(
        color: isDark ? const Color(0xFF56B6C2) : const Color(0xFF0284C7),
      ),
      'literal': TextStyle(
        color: isDark ? const Color(0xFFD19A66) : const Color(0xFFC2410C),
      ),
      'number': TextStyle(
        color: isDark ? const Color(0xFFD19A66) : const Color(0xFFC2410C),
      ),
      'attr': TextStyle(
        color: isDark ? const Color(0xFFD19A66) : const Color(0xFFB45309),
      ),
      'attribute': TextStyle(
        color: isDark ? const Color(0xFFD19A66) : const Color(0xFFB45309),
      ),
      'variable': TextStyle(
        color: isDark ? const Color(0xFFE06C75) : const Color(0xFFDC2626),
      ),
      'params': TextStyle(color: fgColor),
      'meta': TextStyle(color: accentColor),
      'tag': TextStyle(
        color: isDark ? const Color(0xFFE06C75) : const Color(0xFFDC2626),
      ),
      'name': TextStyle(
        color: isDark ? const Color(0xFFE06C75) : const Color(0xFFDC2626),
      ),
      'symbol': TextStyle(color: accentColor),
      'addition': TextStyle(
        color: isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D),
      ),
      'deletion': TextStyle(
        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
      ),
    };
  }

  AiCompletion? _buildAiCompletion(SettingsState settings) =>
      CodeCrafterAiService.buildCompletionConfig(settings);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final palette = settings.syncAppWithTerminalPalette
        ? resolveConduitPalette(settings.terminalTheme)
        : null;
    final bgColor = palette?.canvas ?? const Color(0xFF090B12);
    final fgColor = palette?.foreground ?? const Color(0xFFE2E8F0);
    final mutedColor = palette?.mutedForeground ?? const Color(0xFF64748B);
    final accentColor = palette?.accent ?? Colors.cyanAccent;
    final borderColor = palette?.border ?? const Color(0xFF1E293B);

    final ext = p.extension(widget.file.path).toLowerCase();
    final isCode = const {
      '.dart',
      '.js',
      '.ts',
      '.tsx',
      '.jsx',
      '.py',
      '.json',
      '.yaml',
      '.yml',
      '.html',
      '.css',
      '.c',
      '.cpp',
      '.rs',
      '.go',
      '.java',
      '.kt',
      '.sh',
    }.contains(ext);

    final baseStyle = GoogleFonts.jetBrainsMono(
      fontSize: settings.fontSize,
      height: 1.4,
      color: fgColor,
    );
    final editorTheme = _buildEditorTheme(
      bgColor: bgColor,
      fgColor: fgColor,
      accentColor: accentColor,
      mutedColor: mutedColor,
    );

    return Container(
      color: bgColor,
      child: CodeCrafter(
        controller: _crafterController,
        initialText: widget.file.controller.text,
        filePath: widget.file.path,
        lspConfig: _lspBridge,
        editorTheme: editorTheme,
        wrapLines: settings.wordWrap,
        enableBreakPoints: isCode,
        enableFolding: isCode,
        enableGutterDivider: true,
        enableRulerLines: true,
        enableSuggestions: settings.autoCompletion,
        suggestionStyle: SuggestionStyle(
          elevation: 8,
          backgroundColor:
              palette?.panelElevated ?? palette?.panel ?? const Color(0xFF141824),
          focusColor: accentColor.withValues(alpha: 0.20),
          hoverColor: fgColor.withValues(alpha: 0.08),
          splashColor: accentColor.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderColor, width: 1),
          ),
          textStyle: baseStyle.copyWith(
            fontSize: (settings.fontSize * 0.90).clamp(11.5, 16.0),
            height: 1.2,
            color: fgColor,
          ),
        ),
        hoverDetailsStyle: HoverDetailsStyle(
          elevation: 8,
          backgroundColor:
              palette?.panelElevated ?? palette?.panel ?? const Color(0xFF141824),
          focusColor: accentColor.withValues(alpha: 0.20),
          hoverColor: fgColor.withValues(alpha: 0.08),
          splashColor: accentColor.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: borderColor, width: 1),
          ),
          textStyle: baseStyle.copyWith(
            fontSize: (settings.fontSize * 0.86).clamp(11.0, 15.0),
            color: fgColor,
          ),
        ),
        cursorColor: accentColor,
        selectionColor: accentColor.withValues(alpha: 0.25),
        selectionHandleColor: accentColor,
        textStyle: baseStyle,
        aiCompletionTextStyle: baseStyle.copyWith(
          color: mutedColor.withValues(alpha: 0.65),
          fontStyle: FontStyle.italic,
        ),
        aiCompletion: _buildAiCompletion(settings),
        gutterStyle: GutterStyle(
          lineNumberStyle: baseStyle.copyWith(
            fontSize: (settings.fontSize * 0.88).clamp(11.0, 20.0),
            color: mutedColor,
          ),
          dividerColor: borderColor,
          foldedIconColor: mutedColor,
          unfoldedIconColor: accentColor,
          breakpointColor: Colors.redAccent,
        ),
      ),
    );
  }
}
