// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';

class RoxumPendingEdit {
  final String filePath;
  final String originalContent;
  final String updatedContent;
  final bool existedBefore;
  final int addedLines;
  final int removedLines;

  const RoxumPendingEdit({
    required this.filePath,
    required this.originalContent,
    required this.updatedContent,
    required this.existedBefore,
    required this.addedLines,
    required this.removedLines,
  });
}

class RoxumToolExecutionResult {
  final bool success;
  final String output;

  const RoxumToolExecutionResult({
    required this.success,
    required this.output,
  });

  String toJsonString() => jsonEncode({
        'success': success,
        'output': output,
      });
}

class RoxumAgenticTools {
  final Ref _ref;
  final Map<String, RoxumPendingEdit> pendingEdits;
  final void Function(Map<String, RoxumPendingEdit>)? onPendingEditsChanged;

  RoxumAgenticTools(
    this._ref, {
    required this.pendingEdits,
    this.onPendingEditsChanged,
  });

  String get workspacePath =>
      _ref.read(workspaceProvider).currentPath ?? Directory.current.path;

  String _resolvePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return workspacePath;
    final resolved = p.isAbsolute(trimmed)
        ? trimmed
        : p.join(workspacePath, trimmed);
    return p.normalize(File(resolved).absolute.path);
  }

  bool _isInsideWorkspace(String canonicalPath) {
    final root = p.normalize(Directory(workspacePath).absolute.path);
    return canonicalPath == root || p.isWithin(root, canonicalPath);
  }

  String _relativePath(String canonicalPath) {
    final root = p.normalize(Directory(workspacePath).absolute.path);
    if (canonicalPath == root) return '.';
    return p.relative(canonicalPath, from: root);
  }

  static List<Map<String, dynamic>> buildOpenAiTools(
    Map<String, bool> selections,
  ) {
    final all = <Map<String, dynamic>>[
      _toolDef(
        'activeEditorFile',
        'Gets the path and language of the currently active editor file.',
        {},
      ),
      _toolDef(
        'currentlySelectedText',
        'Gets the currently selected text in the active editor.',
        {},
      ),
      _toolDef(
        'getLspDiagnostics',
        'Gets compiler/analyzer diagnostics for open files or a given file.',
        {
          'filePath': {'type': 'string', 'description': 'Optional file path.'},
        },
      ),
      _toolDef(
        'readFile',
        'Reads the contents of a file in the workspace.',
        {
          'filePath': {'type': 'string', 'description': 'Path to the file.'},
          'startLine': {'type': 'integer', 'description': '1-based start line.'},
          'endLine': {'type': 'integer', 'description': '1-based end line.'},
        },
        required: ['filePath'],
      ),
      _toolDef(
        'readFilesBatch',
        'Reads multiple files in one call.',
        {
          'filePaths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List of file paths.',
          },
        },
        required: ['filePaths'],
      ),
      _toolDef(
        'writeFile',
        'Writes or creates a file in the workspace with pending diff tracking.',
        {
          'filePath': {'type': 'string', 'description': 'Path to the file.'},
          'content': {'type': 'string', 'description': 'Full file content.'},
        },
        required: ['filePath', 'content'],
      ),
      _toolDef(
        'editFile',
        'Replaces an exact target snippet in a file with replacement text.',
        {
          'filePath': {'type': 'string', 'description': 'Path to the file.'},
          'oldText': {'type': 'string', 'description': 'Exact text to replace.'},
          'newText': {'type': 'string', 'description': 'Replacement text.'},
        },
        required: ['filePath', 'oldText', 'newText'],
      ),
      _toolDef(
        'insertAtLine',
        'Inserts text before or after a 1-based line number.',
        {
          'filePath': {'type': 'string'},
          'line': {'type': 'integer'},
          'text': {'type': 'string'},
          'position': {'type': 'string', 'enum': ['before', 'after']},
        },
        required: ['filePath', 'line', 'text'],
      ),
      _toolDef(
        'replaceAllInFile',
        'Replaces all occurrences of a string in a file.',
        {
          'filePath': {'type': 'string'},
          'search': {'type': 'string'},
          'replace': {'type': 'string'},
        },
        required: ['filePath', 'search', 'replace'],
      ),
      _toolDef(
        'deleteFile',
        'Deletes a file from the workspace.',
        {
          'filePath': {'type': 'string'},
        },
        required: ['filePath'],
      ),
      _toolDef(
        'renamePath',
        'Renames or moves a file or directory within the workspace.',
        {
          'oldPath': {'type': 'string'},
          'newPath': {'type': 'string'},
        },
        required: ['oldPath', 'newPath'],
      ),
      _toolDef(
        'listFiles',
        'Lists files and subdirectories inside a directory.',
        {
          'directoryPath': {'type': 'string', 'description': 'Relative or absolute path.'},
          'recursive': {'type': 'boolean'},
        },
      ),
      _toolDef(
        'globSearchFiles',
        'Finds workspace files matching a filename substring or glob pattern.',
        {
          'pattern': {'type': 'string'},
        },
        required: ['pattern'],
      ),
      _toolDef(
        'grepInFiles',
        'Searches workspace text files for a query string or regex.',
        {
          'query': {'type': 'string'},
          'directoryPath': {'type': 'string'},
        },
        required: ['query'],
      ),
      _toolDef(
        'getFileInfo',
        'Gets metadata about a file or directory.',
        {
          'filePath': {'type': 'string'},
        },
        required: ['filePath'],
      ),
      _toolDef(
        'getPendingEditsForFile',
        'Returns pending agent edits for a file or all modified files.',
        {
          'filePath': {'type': 'string'},
        },
      ),
      _toolDef(
        'gitStatus',
        'Runs git status --short in the workspace.',
        {},
      ),
      _toolDef(
        'gitDiff',
        'Runs git diff in the workspace.',
        {
          'filePath': {'type': 'string'},
        },
      ),
      _toolDef(
        'gitLog',
        'Returns recent git commits.',
        {
          'limit': {'type': 'integer'},
        },
      ),
      _toolDef(
        'runCommand',
        'Runs a shell command inside the Ubuntu PRoot environment.',
        {
          'command': {'type': 'string', 'description': 'Shell command to run.'},
        },
        required: ['command'],
      ),
    ];

    return filterAgenticToolsBySelection(all, selections);
  }

  static Map<String, dynamic> _toolDef(
    String name,
    String description,
    Map<String, dynamic> properties, {
    List<String> required = const [],
  }) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };
  }

  Future<RoxumToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case 'activeEditorFile':
          return _activeEditorFile();
        case 'currentlySelectedText':
          return _currentlySelectedText();
        case 'getLspDiagnostics':
          return _getLspDiagnostics(args['filePath']?.toString());
        case 'readFile':
          return await _readFile(
            args['filePath']?.toString() ?? '',
            startLine: args['startLine'] as int?,
            endLine: args['endLine'] as int?,
          );
        case 'readFilesBatch':
          final list = (args['filePaths'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [];
          return await _readFilesBatch(list);
        case 'writeFile':
          return await _writeFile(
            args['filePath']?.toString() ?? '',
            args['content']?.toString() ?? '',
          );
        case 'editFile':
          return await _editFile(
            args['filePath']?.toString() ?? '',
            args['oldText']?.toString() ?? '',
            args['newText']?.toString() ?? '',
          );
        case 'insertAtLine':
          return await _insertAtLine(
            args['filePath']?.toString() ?? '',
            (args['line'] as num?)?.toInt() ?? 1,
            args['text']?.toString() ?? '',
            position: args['position']?.toString() ?? 'after',
          );
        case 'replaceAllInFile':
          return await _replaceAllInFile(
            args['filePath']?.toString() ?? '',
            args['search']?.toString() ?? '',
            args['replace']?.toString() ?? '',
          );
        case 'deleteFile':
          return await _deleteFile(args['filePath']?.toString() ?? '');
        case 'renamePath':
        case 'rename':
          return await _renamePath(
            args['oldPath']?.toString() ?? '',
            args['newPath']?.toString() ?? '',
          );
        case 'listFiles':
          return await _listFiles(
            args['directoryPath']?.toString() ?? '',
            recursive: args['recursive'] == true,
          );
        case 'globSearchFiles':
          return await _globSearchFiles(args['pattern']?.toString() ?? '');
        case 'grepInFiles':
        case 'searchInFiles':
          return await _grepInFiles(
            args['query']?.toString() ?? '',
            directoryPath: args['directoryPath']?.toString(),
          );
        case 'getFileInfo':
          return await _getFileInfo(args['filePath']?.toString() ?? '');
        case 'getPendingEditsForFile':
          return _getPendingEdits(args['filePath']?.toString());
        case 'gitStatus':
          return await _runShell('git status --short');
        case 'gitDiff':
          final fp = args['filePath']?.toString();
          return await _runShell(
            fp != null && fp.isNotEmpty ? 'git diff -- "$fp"' : 'git diff',
          );
        case 'gitLog':
          final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 50);
          return await _runShell('git log -n $limit --oneline');
        case 'runCommand':
          return await _runShell(args['command']?.toString() ?? '');
        default:
          return RoxumToolExecutionResult(
            success: false,
            output: 'Unknown tool: $name',
          );
      }
    } catch (e) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Tool "$name" failed: $e',
      );
    }
  }

  EditorFile? _activeFile(EditorState editor) {
    if (editor.openFiles.isEmpty ||
        editor.activeTabIndex < 0 ||
        editor.activeTabIndex >= editor.openFiles.length) {
      return null;
    }
    return editor.openFiles[editor.activeTabIndex];
  }

  RoxumToolExecutionResult _activeEditorFile() {
    final editor = _ref.read(editorProvider);
    final active = _activeFile(editor);
    if (active == null) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'No file is currently open in the editor.',
      );
    }
    return RoxumToolExecutionResult(
      success: true,
      output: jsonEncode({
        'path': _relativePath(active.path),
        'absolutePath': active.path,
        'lineCount': active.controller.codeLines.length,
      }),
    );
  }

  RoxumToolExecutionResult _currentlySelectedText() {
    final editor = _ref.read(editorProvider);
    final active = _activeFile(editor);
    if (active == null) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'No active editor.',
      );
    }
    final selected = active.controller.selectedText;
    return RoxumToolExecutionResult(
      success: true,
      output: selected.isEmpty ? '(no text selected)' : selected,
    );
  }

  RoxumToolExecutionResult _getLspDiagnostics(String? filePath) {
    final editor = _ref.read(editorProvider);
    final target = filePath != null && filePath.isNotEmpty
        ? _resolvePath(filePath)
        : null;
    final items = <Map<String, dynamic>>[];
    for (final f in editor.openFiles) {
      if (target != null && p.normalize(f.path) != target) continue;
      for (final d in f.diagnostics) {
        items.add({
          'file': _relativePath(f.path),
          'line': d.range.index + 1,
          'severity': d.severity.name,
          'message': d.message,
        });
      }
    }
    return RoxumToolExecutionResult(
      success: true,
      output: items.isEmpty
          ? 'No diagnostics reported in open files.'
          : jsonEncode(items),
    );
  }

  Future<RoxumToolExecutionResult> _readFile(
    String rawPath, {
    int? startLine,
    int? endLine,
  }) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    final lines = await file.readAsLines();
    final s = (startLine ?? 1).clamp(1, lines.isEmpty ? 1 : lines.length);
    final e = (endLine ?? lines.length).clamp(s, lines.isEmpty ? 1 : lines.length);
    if (lines.isEmpty) {
      return const RoxumToolExecutionResult(success: true, output: '');
    }
    final buf = StringBuffer();
    for (int i = s; i <= e; i++) {
      buf.writeln('$i: ${lines[i - 1]}');
    }
    return RoxumToolExecutionResult(success: true, output: buf.toString());
  }

  Future<RoxumToolExecutionResult> _readFilesBatch(List<String> paths) async {
    final results = <String, String>{};
    for (final raw in paths.take(12)) {
      final res = await _readFile(raw);
      results[raw] = res.output;
    }
    return RoxumToolExecutionResult(success: true, output: jsonEncode(results));
  }

  Future<void> _recordAndWrite(
    String path,
    String newContent, {
    required bool existedBefore,
    required String originalContent,
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(newContent);

    final prevOriginal = pendingEdits[path]?.originalContent ?? originalContent;
    final prevExisted = pendingEdits[path]?.existedBefore ?? existedBefore;
    final counts = _computeDiffCounts(prevOriginal, newContent);

    pendingEdits[path] = RoxumPendingEdit(
      filePath: path,
      originalContent: prevOriginal,
      updatedContent: newContent,
      existedBefore: prevExisted,
      addedLines: counts.added,
      removedLines: counts.removed,
    );
    onPendingEditsChanged?.call(Map<String, RoxumPendingEdit>.from(pendingEdits));

    await _ref.read(editorProvider.notifier).reloadFileFromDisk(path);
  }

  static ({int added, int removed}) _computeDiffCounts(
    String before,
    String after,
  ) {
    final a = before.isEmpty ? <String>[] : before.split('\n');
    final b = after.isEmpty ? <String>[] : after.split('\n');
    final setA = a.toSet();
    final setB = b.toSet();
    final added = b.where((l) => !setA.contains(l)).length;
    final removed = a.where((l) => !setB.contains(l)).length;
    return (added: added, removed: removed);
  }

  Future<RoxumToolExecutionResult> _writeFile(
    String rawPath,
    String content,
  ) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final file = File(path);
    final existed = await file.exists();
    final original = existed ? await file.readAsString() : '';
    await _recordAndWrite(
      path,
      content,
      existedBefore: existed,
      originalContent: original,
    );
    return RoxumToolExecutionResult(
      success: true,
      output: 'Wrote ${_relativePath(path)} (${content.split('\n').length} lines).',
    );
  }

  Future<RoxumToolExecutionResult> _editFile(
    String rawPath,
    String oldText,
    String newText,
  ) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    final original = await file.readAsString();
    if (!original.contains(oldText)) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Target snippet not found in ${_relativePath(path)}.',
      );
    }
    final updated = original.replaceFirst(oldText, newText);
    await _recordAndWrite(
      path,
      updated,
      existedBefore: true,
      originalContent: original,
    );
    return RoxumToolExecutionResult(
      success: true,
      output: 'Updated ${_relativePath(path)}.',
    );
  }

  Future<RoxumToolExecutionResult> _insertAtLine(
    String rawPath,
    int line,
    String text, {
    String position = 'after',
  }) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    final original = await file.readAsString();
    final lines = original.split('\n');
    final idx = (line - 1).clamp(0, lines.length);
    final insertIdx = position == 'before' ? idx : (idx + 1).clamp(0, lines.length);
    lines.insertAll(insertIdx, text.split('\n'));
    await _recordAndWrite(
      path,
      lines.join('\n'),
      existedBefore: true,
      originalContent: original,
    );
    return RoxumToolExecutionResult(
      success: true,
      output: 'Inserted text at line $line ($position) in ${_relativePath(path)}.',
    );
  }

  Future<RoxumToolExecutionResult> _replaceAllInFile(
    String rawPath,
    String search,
    String replace,
  ) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    final original = await file.readAsString();
    if (!original.contains(search)) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'No occurrences of "$search" found in ${_relativePath(path)}.',
      );
    }
    final updated = original.replaceAll(search, replace);
    await _recordAndWrite(
      path,
      updated,
      existedBefore: true,
      originalContent: original,
    );
    return RoxumToolExecutionResult(
      success: true,
      output: 'Replaced all occurrences in ${_relativePath(path)}.',
    );
  }

  Future<RoxumToolExecutionResult> _deleteFile(String rawPath) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    await file.delete();
    return RoxumToolExecutionResult(
      success: true,
      output: 'Deleted ${_relativePath(path)}.',
    );
  }

  Future<RoxumToolExecutionResult> _renamePath(
    String oldRaw,
    String newRaw,
  ) async {
    final oldPath = _resolvePath(oldRaw);
    final newPath = _resolvePath(newRaw);
    if (!_isInsideWorkspace(oldPath) || !_isInsideWorkspace(newPath)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    if (await File(oldPath).exists()) {
      await File(newPath).parent.create(recursive: true);
      await File(oldPath).rename(newPath);
      return RoxumToolExecutionResult(
        success: true,
        output: 'Renamed ${_relativePath(oldPath)} -> ${_relativePath(newPath)}.',
      );
    }
    if (await Directory(oldPath).exists()) {
      await Directory(oldPath).rename(newPath);
      return RoxumToolExecutionResult(
        success: true,
        output: 'Renamed directory ${_relativePath(oldPath)} -> ${_relativePath(newPath)}.',
      );
    }
    return RoxumToolExecutionResult(
      success: false,
      output: 'Path not found: ${_relativePath(oldPath)}',
    );
  }

  Future<RoxumToolExecutionResult> _listFiles(
    String rawDir, {
    bool recursive = false,
  }) async {
    final dirPath = _resolvePath(rawDir);
    if (!_isInsideWorkspace(dirPath)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Directory not found: ${_relativePath(dirPath)}',
      );
    }
    final entries = <String>[];
    await for (final entity in dir.list(recursive: recursive, followLinks: false)) {
      final rel = _relativePath(entity.path);
      if (rel.startsWith('.git/') ||
          rel.contains('/.git/') ||
          rel.contains('/.dart_tool/') ||
          rel.contains('/build/')) {
        continue;
      }
      final suffix = entity is Directory ? '/' : '';
      entries.add('$rel$suffix');
      if (entries.length >= 250) break;
    }
    entries.sort();
    return RoxumToolExecutionResult(
      success: true,
      output: entries.isEmpty ? '(empty)' : entries.join('\n'),
    );
  }

  Future<RoxumToolExecutionResult> _globSearchFiles(String pattern) async {
    final root = Directory(workspacePath);
    if (!await root.exists()) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Workspace directory does not exist.',
      );
    }
    final regex = RegExp(
      '^${RegExp.escape(pattern).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
      caseSensitive: false,
    );
    final matches = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = _relativePath(entity.path);
      if (rel.startsWith('.git/') ||
          rel.contains('/.dart_tool/') ||
          rel.contains('/build/')) {
        continue;
      }
      if (regex.hasMatch(p.basename(rel)) || regex.hasMatch(rel)) {
        matches.add(rel);
        if (matches.length >= 120) break;
      }
    }
    return RoxumToolExecutionResult(
      success: true,
      output: matches.isEmpty ? 'No matching files.' : matches.join('\n'),
    );
  }

  Future<RoxumToolExecutionResult> _grepInFiles(
    String query, {
    String? directoryPath,
  }) async {
    if (query.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Query must not be empty.',
      );
    }
    final base = _resolvePath(directoryPath ?? '');
    if (!_isInsideWorkspace(base)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final dir = Directory(base);
    if (!await dir.exists()) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Directory not found.',
      );
    }
    final hits = <String>[];
    final lower = query.toLowerCase();
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = _relativePath(entity.path);
      if (rel.startsWith('.git/') ||
          rel.contains('/.dart_tool/') ||
          rel.contains('/build/')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.size > 512 * 1024) continue;
        final lines = await entity.readAsLines();
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].toLowerCase().contains(lower)) {
            hits.add('$rel:${i + 1}: ${lines[i].trim()}');
            if (hits.length >= 80) break;
          }
        }
      } catch (_) {}
      if (hits.length >= 80) break;
    }
    return RoxumToolExecutionResult(
      success: true,
      output: hits.isEmpty ? 'No matches found.' : hits.join('\n'),
    );
  }

  Future<RoxumToolExecutionResult> _getFileInfo(String rawPath) async {
    final path = _resolvePath(rawPath);
    if (!_isInsideWorkspace(path)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final stat = await FileStat.stat(path);
    if (stat.type == FileSystemEntityType.notFound) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Not found: ${_relativePath(path)}',
      );
    }
    return RoxumToolExecutionResult(
      success: true,
      output: jsonEncode({
        'path': _relativePath(path),
        'type': stat.type.toString(),
        'sizeBytes': stat.size,
        'modified': stat.modified.toIso8601String(),
      }),
    );
  }

  RoxumToolExecutionResult _getPendingEdits(String? rawPath) {
    final target = rawPath != null && rawPath.isNotEmpty
        ? _resolvePath(rawPath)
        : null;
    final list = pendingEdits.values
        .where((e) => target == null || e.filePath == target)
        .map((e) => {
              'file': _relativePath(e.filePath),
              'addedLines': e.addedLines,
              'removedLines': e.removedLines,
            })
        .toList();
    return RoxumToolExecutionResult(
      success: true,
      output: list.isEmpty ? 'No pending edits.' : jsonEncode(list),
    );
  }

  Future<RoxumToolExecutionResult> _runShell(String command) async {
    if (command.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Command must not be empty.',
      );
    }
    final runtime = _ref.read(runtimeServiceProvider);
    final out = await runtime.runCommand(
      command,
      workingDirectory: workspacePath,
    );
    final trimmed = out.length > 8000
        ? '${out.substring(0, 8000)}\n... [truncated]'
        : out;
    return RoxumToolExecutionResult(
      success: true,
      output: trimmed.isEmpty ? '(command completed with no output)' : trimmed,
    );
  }
}
