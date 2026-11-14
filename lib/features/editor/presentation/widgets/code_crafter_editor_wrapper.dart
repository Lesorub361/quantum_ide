import 'package:flutter/material.dart';
import 'package:flutter_code_crafter/code_crafter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/code_crafter_ai_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
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
  bool _isSyncingFromReEditor = false;
  bool _isSyncingFromCrafter = false;

  @override
  void initState() {
    super.initState();
    _crafterController = CodeCrafterController()
      ..text = widget.file.controller.text;
    _crafterController.addListener(_onCrafterChanged);
    widget.file.controller.addListener(_onReEditorChanged);
  }

  @override
  void didUpdateWidget(covariant CodeCrafterEditorWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.file.controller != widget.file.controller) {
      oldWidget.file.controller.removeListener(_onReEditorChanged);
      widget.file.controller.addListener(_onReEditorChanged);
      _isSyncingFromReEditor = true;
      _crafterController.text = widget.file.controller.text;
      _isSyncingFromReEditor = false;
    }
  }

  @override
  void dispose() {
    widget.file.controller.removeListener(_onReEditorChanged);
    _crafterController.removeListener(_onCrafterChanged);
    _crafterController.dispose();
    super.dispose();
  }

  void _onCrafterChanged() {
    if (_isSyncingFromReEditor) return;
    final nextText = _crafterController.text;
    if (widget.file.controller.text != nextText) {
      _isSyncingFromCrafter = true;
      widget.file.controller.text = nextText;
      _isSyncingFromCrafter = false;
    }
  }

  void _onReEditorChanged() {
    if (_isSyncingFromCrafter) return;
    final nextText = widget.file.controller.text;
    if (_crafterController.text != nextText) {
      _isSyncingFromReEditor = true;
      _crafterController.text = nextText;
      _isSyncingFromReEditor = false;
    }
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

    return Container(
      color: bgColor,
      child: CodeCrafter(
        controller: _crafterController,
        initialText: widget.file.controller.text,
        wrapLines: settings.wordWrap,
        enableBreakPoints: isCode,
        enableFolding: isCode,
        enableGutterDivider: true,
        enableRulerLines: true,
        enableSuggestions: settings.autoCompletion,
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
