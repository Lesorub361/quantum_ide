import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// High-performance Rope-backed code editor widget powered by `code_forge`
/// for large files that would lag under standard text controllers.
class CodeForgeEditorWidget extends ConsumerStatefulWidget {
  final EditorFile file;

  const CodeForgeEditorWidget({super.key, required this.file});

  @override
  ConsumerState<CodeForgeEditorWidget> createState() =>
      _CodeForgeEditorWidgetState();
}

class _CodeForgeEditorWidgetState
    extends ConsumerState<CodeForgeEditorWidget> {
  late final CodeForgeController _forgeController;
  late final UndoRedoController _undoController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _forgeController = CodeForgeController();
    _undoController = UndoRedoController();
    _forgeController.text = widget.file.controller.text;
    _forgeController.addListener(_onForgeChanged);
    widget.file.controller.addListener(_onParentChanged);
  }

  void _onForgeChanged() {
    if (_isSyncing) return;
    final newText = _forgeController.text;
    if (newText == widget.file.controller.text) return;
    _isSyncing = true;
    try {
      widget.file.controller.text = newText;
    } finally {
      _isSyncing = false;
    }
  }

  void _onParentChanged() {
    if (_isSyncing) return;
    final parentText = widget.file.controller.text;
    if (parentText == _forgeController.text) return;
    _isSyncing = true;
    try {
      _forgeController.text = parentText;
    } finally {
      _isSyncing = false;
    }
  }

  @override
  void didUpdateWidget(covariant CodeForgeEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      oldWidget.file.controller.removeListener(_onParentChanged);
      widget.file.controller.addListener(_onParentChanged);
      _isSyncing = true;
      try {
        _forgeController.text = widget.file.controller.text;
      } finally {
        _isSyncing = false;
      }
    }
  }

  @override
  void dispose() {
    _forgeController.removeListener(_onForgeChanged);
    widget.file.controller.removeListener(_onParentChanged);
    _forgeController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  Mode? _resolveLanguage(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.dart':
        return langDart;
      case '.json':
      case '.arb':
        return langJson;
      case '.js':
      case '.jsx':
      case '.ts':
      case '.tsx':
      case '.mjs':
        return langJavascript;
      case '.yaml':
      case '.yml':
        return langYaml;
      case '.md':
      case '.markdown':
        return langMarkdown;
      case '.py':
        return langPython;
      case '.cpp':
      case '.cc':
      case '.c':
      case '.h':
      case '.hpp':
        return langCpp;
      case '.java':
      case '.kt':
      case '.kts':
        return langJava;
      case '.xml':
      case '.html':
      case '.svg':
        return langXml;
      case '.php':
        return langPhp;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(settingsProvider.select((s) => s.fontSize));
    final fontFamily = ref.watch(settingsProvider.select((s) => s.fontFamily));

    return CodeForge(
      controller: _forgeController,
      undoController: _undoController,
      language: _resolveLanguage(widget.file.path),
      editorTheme: atomOneDarkTheme,
      textStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: 1.45,
      ),
    );
  }
}
