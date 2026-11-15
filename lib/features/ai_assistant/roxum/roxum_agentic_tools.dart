// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/mcp_service.dart';
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
        'codeOutline',
        'Extracts a compact AST/symbol outline (classes, methods, functions, widgets, providers, and #L line numbers) for a file or directory to save 85% tokens instead of reading full files.',
        {
          'path': {
            'type': 'string',
            'description': 'File or directory path (default ".").',
          },
        },
      ),
      _toolDef(
        'checkEnvironment',
        'Discovers all installed compilers, SDKs, and tools across the system (flutter, dart, java, gradle, aapt2, node, npm, python3, pip, git, cargo, gcc, go) with their exact executable paths and versions. ALWAYS call this before claiming a tool is missing or before installing SDKs.',
        {},
      ),
      _toolDef(
        'installPackages',
        'Automatically installs missing packages or dependencies using the appropriate package manager (pub, npm, pip, apt, cargo).',
        {
          'manager': {
            'type': 'string',
            'enum': ['auto', 'pub', 'npm', 'pip', 'apt', 'cargo'],
            'description': 'Package manager to use (or "auto" to detect from project).',
          },
          'packages': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'List of package names to install.',
          },
        },
        required: ['packages'],
      ),
      _toolDef(
        'runCommand',
        'Runs a shell command in the project workspace with full system PATH and SDK discovery.',
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

  static final Map<String, ({String server, String tool})> _mcpToolRegistry = {};

  static List<Map<String, dynamic>> buildMcpOpenAiTools(
    List<Map<String, dynamic>> mcpTools,
  ) {
    _mcpToolRegistry.clear();
    final out = <Map<String, dynamic>>[];
    for (final t in mcpTools) {
      final server = t['server']?.toString() ?? 'mcp';
      final tool = t['name']?.toString() ?? '';
      if (tool.isEmpty) continue;
      final safeName =
          'mcp__${server.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}__${tool.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
      _mcpToolRegistry[safeName] = (server: server, tool: tool);
      final schema = (t['inputSchema'] as Map?)?.cast<String, dynamic>() ??
          const {'type': 'object', 'properties': <String, dynamic>{}};
      out.add({
        'type': 'function',
        'function': {
          'name': safeName,
          'description': '[MCP:$server] ${t['description'] ?? tool}',
          'parameters': schema,
        },
      });
    }
    return out;
  }

  Future<RoxumToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      if (name.startsWith('mcp__')) {
        final target = _mcpToolRegistry[name];
        if (target == null) {
          return RoxumToolExecutionResult(
            success: false,
            output: 'MCP tool not registered: $name',
          );
        }
        final res = await _ref
            .read(mcpServiceProvider.notifier)
            .executeMcpTool(target.server, target.tool, args);
        return RoxumToolExecutionResult(
          success: res['isError'] != true,
          output: jsonEncode(res),
        );
      }
      switch (name) {
        case 'activeEditorFile':
          return _activeEditorFile();
        case 'currentlySelectedText':
          return _currentlySelectedText();
        case 'getLspDiagnostics':
          return await _getLspDiagnostics(args['filePath']?.toString());
        case 'readFile':
          return await _readFile(
            args['filePath']?.toString() ?? '',
            startLine: (args['startLine'] as num?)?.toInt(),
            endLine: (args['endLine'] as num?)?.toInt(),
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
        case 'codeOutline':
          return await _codeOutline(args['path']?.toString() ?? '');
        case 'checkEnvironment':
          return await _checkEnvironment();
        case 'installPackages':
          final pkgs = (args['packages'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [];
          return await _installPackages(
            pkgs,
            manager: args['manager']?.toString() ?? 'auto',
          );
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

  Future<RoxumToolExecutionResult> _getLspDiagnostics(String? filePath) async {
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
    if (items.isNotEmpty) {
      return RoxumToolExecutionResult(
        success: true,
        output: jsonEncode(items),
      );
    }

    // Fallback: Run real static analysis on the workspace or target file so
    // errors in unopened or newly created files are ALWAYS detected!
    final runtime = _ref.read(runtimeServiceProvider);
    final targetArg = target != null ? '"${_relativePath(target)}"' : '';
    final pubspec = File(p.join(workspacePath, 'pubspec.yaml'));
    final tsconfig = File(p.join(workspacePath, 'tsconfig.json'));
    if (await pubspec.exists()) {
      final res = await runtime.runCommandDetailed(
        '(dart analyze $targetArg 2>&1 || flutter analyze --no-pub $targetArg 2>&1)',
        workingDirectory: workspacePath,
        timeout: const Duration(seconds: 75),
      );
      final diagLines = res.combined
          .split('\n')
          .where(
            (l) =>
                l.contains('error •') ||
                l.contains('warning •') ||
                l.contains('info •') ||
                l.contains('Error:') ||
                l.contains('No issues found'),
          )
          .take(60)
          .toList();
      if (diagLines.isNotEmpty) {
        return RoxumToolExecutionResult(
          success: true,
          output: diagLines.join('\n'),
        );
      }
    } else if (await tsconfig.exists()) {
      final res = await runtime.runCommandDetailed(
        'npx tsc --noEmit 2>&1',
        workingDirectory: workspacePath,
        timeout: const Duration(seconds: 60),
      );
      if (res.combined.trim().isNotEmpty) {
        return RoxumToolExecutionResult(
          success: true,
          output: res.combined.length > 3500
              ? res.combined.substring(0, 3500)
              : res.combined,
        );
      }
    }

    return const RoxumToolExecutionResult(
      success: true,
      output: 'No diagnostics reported (0 errors, 0 warnings).',
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
    if (lines.isEmpty) {
      return RoxumToolExecutionResult(
        success: true,
        output: '[File: ${_relativePath(path)} #L1-1 (empty)]',
      );
    }
    final s = (startLine ?? 1).clamp(1, lines.length);
    // Cap default un-ranged reads to 320 lines to avoid blowing up context tokens
    final defaultEnd = (startLine == null && endLine == null && lines.length > 320)
        ? 320
        : lines.length;
    final e = (endLine ?? defaultEnd).clamp(s, lines.length);
    final buf = StringBuffer();
    buf.writeln(
      '[File: ${_relativePath(path)} #L$s-$e of ${lines.length} lines]',
    );
    for (int i = s; i <= e; i++) {
      buf.writeln('$i: ${lines[i - 1]}');
    }
    if (e < lines.length && endLine == null) {
      buf.writeln(
        '... [Showing lines $s-$e of ${lines.length}. Call readFile with startLine=${e + 1}, endLine=${(e + 320).clamp(e + 1, lines.length)} to read further, or use codeOutline.]',
      );
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

  Future<RoxumToolExecutionResult> _codeOutline(String rawPath) async {
    final targetPath = _resolvePath(rawPath);
    if (!_isInsideWorkspace(targetPath)) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Permission denied: path is outside workspace.',
      );
    }
    final symRegex = RegExp(
      r'^\s*(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|extension|typedef|def|function|interface|struct)\s+([A-Za-z0-9_]+)|^\s*(?:@override\s+)?(?:Future<[^>]+>|Stream<[^>]+>|Widget|State<[^>]+>|void|String|int|bool|double|dynamic)\s+([A-Za-z0-9_]+)\s*\(',
    );

    Future<String> outlineSingleFile(File f) async {
      final lines = await f.readAsLines();
      final rel = _relativePath(f.path);
      final items = <String>[];
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final m = symRegex.firstMatch(line);
        if (m != null) {
          final name = m.group(1) ?? m.group(2) ?? '';
          if (name.isNotEmpty &&
              !const {'if', 'for', 'while', 'switch', 'catch'}.contains(name)) {
            items.add('  #L${i + 1}: ${line.trim()}');
          }
        }
      }
      if (items.isEmpty) {
        return '$rel (${lines.length} lines): (no top-level classes/functions matched)';
      }
      return '$rel (#L1-${lines.length}):\n${items.take(60).join('\n')}';
    }

    if (await File(targetPath).exists()) {
      return RoxumToolExecutionResult(
        success: true,
        output: await outlineSingleFile(File(targetPath)),
      );
    }
    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Path not found: ${_relativePath(targetPath)}',
      );
    }
    final summaries = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = _relativePath(entity.path);
      if (rel.startsWith('.') ||
          rel.contains('/.') ||
          rel.contains('/build/') ||
          rel.contains('node_modules')) {
        continue;
      }
      final ext = p.extension(rel).toLowerCase();
      if (!const {
        '.dart',
        '.ts',
        '.tsx',
        '.js',
        '.jsx',
        '.py',
        '.rs',
        '.go',
        '.kt',
        '.java',
      }.contains(ext)) {
        continue;
      }
      try {
        summaries.add(await outlineSingleFile(entity));
        if (summaries.length >= 40) break;
      } catch (_) {}
    }
    return RoxumToolExecutionResult(
      success: true,
      output: summaries.isEmpty
          ? 'No source files found for outline.'
          : summaries.join('\n\n'),
    );
  }

  Future<RoxumToolExecutionResult> _checkEnvironment() async {
    final runtime = _ref.read(runtimeServiceProvider);
    const script = r'''
echo "=== QuantumIDE Environment & Toolchain Discovery ==="
echo "OS: $(uname -srm 2>/dev/null || echo unknown)"
echo "Mode: $([ -f "$HOME/config/native_root_mode.flag" ] && echo 'Native Root Kernel (uid=0)' || echo 'Standard Runtime')"
echo "PWD: $(pwd)"
for tool in flutter dart java javac gradle aapt2 node npm npx python3 pip git cargo rustc go gcc clang cmake ninja; do
  BIN_PATH=$(command -v "$tool" 2>/dev/null || true)
  if [ -z "$BIN_PATH" ]; then
    for d in "$HOME/flutter/bin" "$HOME/development/flutter/bin" "$HOME/dev/flutter/bin" "/opt/flutter/bin" "/snap/bin" "$HOME/snap/flutter/common/flutter/bin" "$HOME/.fvm/default/bin" "$HOME/fvm/default/bin" "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.pub-cache/bin" "/usr/local/bin" "/usr/bin"; do
      if [ -x "$d/$tool" ]; then
        BIN_PATH="$d/$tool"
        break
      fi
    done
  fi
  if [ -n "$BIN_PATH" ]; then
    VER=$("$BIN_PATH" --version 2>&1 | head -n 1 | cut -c1-80 || true)
    echo "[FOUND] $tool -> $BIN_PATH ($VER)"
  else
    echo "[MISSING] $tool"
  fi
done
''';
    final res = await runtime.runCommandDetailed(
      script,
      workingDirectory: workspacePath,
      timeout: const Duration(seconds: 45),
    );
    return RoxumToolExecutionResult(
      success: true,
      output: res.combined.trim(),
    );
  }

  Future<RoxumToolExecutionResult> _installPackages(
    List<String> packages, {
    String manager = 'auto',
  }) async {
    final cleanPkgs = packages
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && RegExp(r'^[a-zA-Z0-9_.\-@/:+]+$').hasMatch(e))
        .toList();
    if (cleanPkgs.isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'No valid package names provided.',
      );
    }

    var resolvedManager = manager.toLowerCase();
    if (resolvedManager == 'auto') {
      if (await File(p.join(workspacePath, 'pubspec.yaml')).exists()) {
        resolvedManager = 'pub';
      } else if (await File(p.join(workspacePath, 'package.json')).exists()) {
        resolvedManager = 'npm';
      } else if (await File(p.join(workspacePath, 'Cargo.toml')).exists()) {
        resolvedManager = 'cargo';
      } else if (await File(p.join(workspacePath, 'requirements.txt')).exists() ||
          await File(p.join(workspacePath, 'pyproject.toml')).exists()) {
        resolvedManager = 'pip';
      } else {
        resolvedManager = 'apt';
      }
    }

    final pkgArgs = cleanPkgs.join(' ');
    final String cmd = switch (resolvedManager) {
      'pub' =>
        '(flutter pub add $pkgArgs 2>&1 || dart pub add $pkgArgs 2>&1)',
      'npm' => 'npm install $pkgArgs 2>&1',
      'pip' =>
        '(pip3 install --break-system-packages $pkgArgs 2>&1 || pip3 install $pkgArgs 2>&1)',
      'cargo' => 'cargo add $pkgArgs 2>&1',
      _ =>
        'export DEBIAN_FRONTEND=noninteractive; (apt-get update -y && apt-get install -y --no-install-recommends $pkgArgs) 2>&1 || (pkg install $pkgArgs) 2>&1',
    };

    final runtime = _ref.read(runtimeServiceProvider);
    final res = await runtime.runCommandDetailed(
      cmd,
      workingDirectory: workspacePath,
      timeout: const Duration(seconds: 300),
    );
    final out = res.combined.length > 6000
        ? '${res.combined.substring(0, 6000)}\n... [truncated]'
        : res.combined;
    return RoxumToolExecutionResult(
      success: res.exitCode == 0,
      output: '[Manager: $resolvedManager | ExitCode: ${res.exitCode}]\n$out',
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
    final res = await runtime.runCommandDetailed(
      command,
      workingDirectory: workspacePath,
      timeout: const Duration(seconds: 180),
    );
    var combined = res.combined;
    if (combined.length > 6000) {
      combined =
          '${combined.substring(0, 2500)}\n... [middle truncated to save tokens] ...\n${combined.substring(combined.length - 2500)}';
    }
    if (res.exitCode != 0 &&
        (combined.contains('command not found') ||
            combined.contains('not found') ||
            res.exitCode == 127)) {
      combined +=
          '\n[Hint: Call checkEnvironment to locate installed SDK binaries on this machine, or call installPackages to install missing packages.]';
    }
    final header = res.exitCode == 0 ? '' : '[Exit code: ${res.exitCode}]\n';
    return RoxumToolExecutionResult(
      // Return success: true even on non-zero command exit codes unless the command timed out,
      // so the UI doesn't show a fatal tool crash when `grep`, `which`, or `analyze` finds issues.
      success: res.exitCode != 124,
      output: combined.trim().isEmpty
          ? '${header}(command completed with exit code ${res.exitCode} and no output)'
          : '$header$combined',
    );
  }
}
