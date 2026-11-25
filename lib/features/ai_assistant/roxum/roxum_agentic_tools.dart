// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/fast_syntax_engine.dart';
import 'package:quantum_ide/core/services/live_telemetry_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/workspace_path_resolver.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_tool_catalog.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';

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

  const RoxumToolExecutionResult({required this.success, required this.output});

  String toJsonString() => jsonEncode({'success': success, 'output': output});
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

  WorkspacePathResolver get _paths => WorkspacePathResolver(
    workspacePath,
    androidFilesDir: _ref.read(runtimeServiceProvider).filesDir,
  );

  String _resolvePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) return workspacePath;
    return _paths.toHostPath(trimmed);
    /*
    if (Platform.isAndroid && trimmed.startsWith('/root/')) {
      final hostCandidate = File(trimmed);
      if (!hostCandidate.existsSync() && !Directory(trimmed).existsSync()) {
        final wsNorm = p.normalize(workspacePath);
        const marker = '/projects/';
        final idx = wsNorm.indexOf(marker);
        if (idx > 0) {
          final filesDir = wsNorm.substring(0, idx);
          if (trimmed == '/root/projects' || trimmed.startsWith('/root/projects/')) {
            final rel = trimmed.length <= '/root/projects'.length
                ? ''
                : trimmed.substring('/root/projects/'.length);
            return p.normalize(
              rel.isEmpty ? p.join(filesDir, 'projects') : p.join(filesDir, 'projects', rel),
            );
          }
          return p.normalize(
            p.join(filesDir, 'rootfs', 'ubuntu', trimmed.substring(1)),
          );
        }
      }
    }
    final resolved = p.isAbsolute(trimmed)
        ? trimmed
        : p.join(workspacePath, trimmed);
    return p.normalize(File(resolved).absolute.path);*/
  }

  bool _isInsideWorkspace(String canonicalPath) {
    final root = p.normalize(Directory(workspacePath).absolute.path);
    return canonicalPath == root || p.isWithin(root, canonicalPath);
  }

  String _relativePath(String canonicalPath) {
    final root = p.normalize(Directory(workspacePath).absolute.path);
    if (canonicalPath == root) return '.';
    if (_isInsideWorkspace(canonicalPath)) {
      return p.relative(canonicalPath, from: root);
    }
    return canonicalPath;
  }

  void _refreshWorkspaceExplorer() {
    try {
      _ref.read(fileTreeRefreshProvider.notifier).state++;
      _ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
    } catch (_) {}
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
          'startLine': {
            'type': 'integer',
            'description': '1-based start line.',
          },
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
        'Replaces a UNIQUE target code snippet in a file with replacement text (supports flexible whitespace matching, rejects ambiguous multi-match snippets, and returns errors-only inline compiler diagnostics). Include 2-3 surrounding lines when a line could appear multiple times.',
        {
          'filePath': {'type': 'string', 'description': 'Path to the file.'},
          'oldText': {
            'type': 'string',
            'description': 'Unique target snippet with surrounding context.',
          },
          'newText': {'type': 'string', 'description': 'Replacement text.'},
        },
        required: ['filePath', 'oldText', 'newText'],
      ),
      _toolDef(
        'multiEditFile',
        'Applies multiple sequential edits to a single file in ONE atomic call (like OpenCode multiedit) and returns errors-only inline compiler diagnostics.',
        {
          'filePath': {'type': 'string', 'description': 'Path to the file.'},
          'edits': {
            'type': 'array',
            'description':
                'Native JSON array (NOT a JSON string) of {oldText, newText} objects.',
            'items': {
              'type': 'object',
              'properties': {
                'oldText': {
                  'type': 'string',
                  'description': 'Unique target snippet.',
                },
                'newText': {
                  'type': 'string',
                  'description': 'Replacement snippet.',
                },
              },
              'required': ['oldText', 'newText'],
            },
          },
        },
        required: ['filePath', 'edits'],
      ),
      _toolDef(
        'insertAtLine',
        'Inserts text before or after a 1-based line number.',
        {
          'filePath': {'type': 'string'},
          'line': {'type': 'integer'},
          'text': {'type': 'string'},
          'position': {
            'type': 'string',
            'enum': ['before', 'after'],
          },
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
        'replaceInProject',
        'Replaces text or a regular expression across matching workspace files in one call.',
        {
          'search': {'type': 'string'},
          'replace': {'type': 'string'},
          'isRegex': {'type': 'boolean'},
          'globPattern': {'type': 'string'},
          'directoryPath': {'type': 'string'},
          'dryRun': {'type': 'boolean'},
        },
        required: ['search', 'replace'],
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
          'directoryPath': {
            'type': 'string',
            'description': 'Relative or absolute path.',
          },
          'recursive': {'type': 'boolean'},
        },
      ),
      _toolDef(
        'globSearchFiles',
        'Finds workspace files matching a filename substring or glob pattern.',
        {
          'pattern': {'type': 'string'},
          'directoryPath': {'type': 'string'},
        },
        required: ['pattern'],
      ),
      _toolDef(
        'grepInFiles',
        'Searches workspace text files for a query string or regex.',
        {
          'query': {'type': 'string'},
          'directoryPath': {'type': 'string'},
          'isRegex': {'type': 'boolean'},
          'caseSensitive': {'type': 'boolean'},
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
      _toolDef('gitStatus', 'Runs git status --short in the workspace.', {}),
      _toolDef('gitDiff', 'Runs git diff in the workspace.', {
        'filePath': {'type': 'string'},
      }),
      _toolDef('gitLog', 'Returns recent git commits.', {
        'limit': {'type': 'integer'},
      }),
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
            'description':
                'Package manager to use (or "auto" to detect from project).',
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

  static final Map<String, ({String server, String tool})> _mcpToolRegistry =
      {};

  static List<Map<String, dynamic>> buildMcpOpenAiTools(
    List<Map<String, dynamic>> mcpTools,
  ) {
    _mcpToolRegistry.clear();
    final out = <Map<String, dynamic>>[];
    for (final t in mcpTools) {
      final server = t['server']?.toString() ?? 'mcp';
      final tool = t['name']?.toString() ?? '';
      if (tool.isEmpty) continue;
      var safeName =
          'mcp__${server.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}__${tool.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
      if (safeName.length > 64) {
        final hash = (server.hashCode ^ tool.hashCode).abs().toRadixString(36);
        final prefixMax = (63 - hash.length).clamp(16, 56);
        safeName = '${safeName.substring(0, prefixMax)}_$hash';
      }
      _mcpToolRegistry[safeName] = (server: server, tool: tool);
      final rawSchema = (t['inputSchema'] as Map?)?.cast<String, dynamic>();
      final schema = _normalizeMcpInputSchema(rawSchema);
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

  static Map<String, dynamic> _normalizeMcpInputSchema(
    Map<String, dynamic>? raw,
  ) {
    if (raw == null || raw.isEmpty) {
      return const {'type': 'object', 'properties': <String, dynamic>{}};
    }
    final cleaned = <String, dynamic>{
      'type': raw['type']?.toString() ?? 'object',
      'properties': (raw['properties'] is Map)
          ? Map<String, dynamic>.from(raw['properties'] as Map)
          : <String, dynamic>{},
      if (raw['required'] is List && (raw['required'] as List).isNotEmpty)
        'required': List<String>.from(
          (raw['required'] as List).map((e) => e.toString()),
        ),
    };
    return cleaned;
  }

  static String formatMcpResult(Map<String, dynamic> res) {
    final content = res['content'];
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map && item['text'] != null) {
          parts.add(item['text'].toString());
        } else {
          parts.add(jsonEncode(item));
        }
      }
      if (parts.isNotEmpty) return parts.join('\n');
    }
    if (res['diagnostics'] is String) {
      return res['diagnostics'] as String;
    }
    return jsonEncode(res);
  }

  Future<RoxumToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      if (args.containsKey('__parse_error__')) {
        return RoxumToolExecutionResult(
          success: false,
          output: args['__parse_error__']?.toString() ??
              'Tool arguments JSON could not be parsed.',
        );
      }
      if (name.startsWith('mcp__')) {
        // MCP tools are executed by PocketStrike's McpConnectionManager,
        // not by this legacy runner.
        return const RoxumToolExecutionResult(
          success: false,
          output: 'MCP tool must be executed through the PocketStrike MCP manager.',
        );
      }
      switch (name) {
        case 'activeEditorFile':
          return _activeEditorFile();
        case 'currentlySelectedText':
          return _currentlySelectedText();
        case 'getLspDiagnostics':
        case 'diagnostics':
          return await _getLspDiagnostics(
            (args['filePath'] ?? args['path'])?.toString(),
          );
        case 'readFile':
        case 'read':
        case 'read_file':
          return await _readFile(
            (args['filePath'] ?? args['path'])?.toString() ?? '',
            startLine: _parseInt(args['startLine'] ?? args['offset']),
            endLine: _parseInt(args['endLine']),
          );
        case 'readFilesBatch':
          final list =
              (args['filePaths'] as List?)?.map((e) => e.toString()).toList() ??
              const [];
          return await _readFilesBatch(list);
        case 'writeFile':
        case 'createFile':
        case 'write':
        case 'write_file':
          return await _writeFile(
            (args['filePath'] ?? args['path'])?.toString() ?? '',
            args['content']?.toString() ?? '',
          );
        case 'editFile':
        case 'edit':
        case 'edit_file':
          return await _editFile(
            (args['filePath'] ?? args['path'])?.toString() ?? '',
            (args['oldText'] ?? args['oldString'] ?? args['old_string'])
                    ?.toString() ??
                '',
            (args['newText'] ?? args['newString'] ?? args['new_string'])
                    ?.toString() ??
                '',
          );
        case 'multiEditFile':
        case 'multiEdit':
        case 'multiedit':
          return await _multiEditFile(
            (args['filePath'] ?? args['path'])?.toString() ?? '',
            args['edits'],
          );
        case 'insertAtLine':
          return await _insertAtLine(
            args['filePath']?.toString() ?? '',
            _parseInt(args['line']) ?? 1,
            args['text']?.toString() ?? '',
            position: args['position']?.toString() ?? 'after',
          );
        case 'replaceAllInFile':
          return await _replaceAllInFile(
            args['filePath']?.toString() ?? '',
            args['search']?.toString() ?? '',
            args['replace']?.toString() ?? '',
          );
        case 'replaceInProject':
          return await _replaceInProject(
            args['search']?.toString() ?? '',
            args['replace']?.toString() ?? '',
            isRegex: _parseBool(args['isRegex'], defaultValue: false),
            globPattern: args['globPattern']?.toString() ?? '**/*',
            directoryPath: args['directoryPath']?.toString(),
            dryRun: _parseBool(args['dryRun'], defaultValue: false),
          );
        case 'deleteFile':
          return await _deleteFile(
            (args['filePath'] ?? args['path'])?.toString() ?? '',
          );
        case 'renamePath':
        case 'rename':
          return await _renamePath(
            args['oldPath']?.toString() ?? '',
            args['newPath']?.toString() ?? '',
          );
        case 'listFiles':
        case 'list':
        case 'ls':
          return await _listFiles(
            (args['directoryPath'] ?? args['path'])?.toString() ?? '',
            recursive: _parseBool(args['recursive'], defaultValue: false),
          );
        case 'globSearchFiles':
        case 'glob':
          return await _globSearchFiles(
            args['pattern']?.toString() ?? '',
            directoryPath:
                (args['directoryPath'] ?? args['path'])?.toString(),
          );
        case 'grepInFiles':
        case 'searchInFiles':
        case 'grep':
          return await _grepInFiles(
            (args['query'] ?? args['pattern'])?.toString() ?? '',
            directoryPath:
                (args['directoryPath'] ?? args['path'])?.toString(),
            isRegex: _parseBool(args['isRegex'], defaultValue: false),
            caseSensitive: _parseBool(
              args['caseSensitive'],
              defaultValue: false,
            ),
          );
        case 'getFileInfo':
          return await _getFileInfo(args['filePath']?.toString() ?? '');
        case 'getPendingEditsForFile':
          return _getPendingEdits(args['filePath']?.toString());
        case 'gitStatus':
          return await _runGitCommand('git status --short');
        case 'gitDiff':
          final fp = args['filePath']?.toString();
          return await _runGitCommand(
            fp != null && fp.isNotEmpty ? 'git diff -- "$fp"' : 'git diff',
          );
        case 'gitLog':
          final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 50);
          return await _runGitCommand('git log -n $limit --oneline');
        case 'codeOutline':
          return await _codeOutline(args['path']?.toString() ?? '');
        case 'checkEnvironment':
          return await _checkEnvironment();
        case 'installPackages':
          final pkgs =
              (args['packages'] as List?)?.map((e) => e.toString()).toList() ??
              const [];
          return await _installPackages(
            pkgs,
            manager: args['manager']?.toString() ?? 'auto',
          );
        case 'runCommand':
        case 'bash':
        case 'run_command':
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
    final target = filePath != null && filePath.isNotEmpty
        ? _resolvePath(filePath)
        : null;

    // Run real static analysis first when pubspec.yaml / tsconfig.json exists so
    // unopened or freshly written files ALWAYS report accurate compiler errors.
    final runtime = _ref.read(runtimeServiceProvider);
    final relTarget = target != null ? _relativePath(target) : '';
    final safeTarget =
        relTarget.isNotEmpty &&
            relTarget != '.' &&
            !relTarget.contains(';') &&
            !relTarget.contains('`') &&
            !relTarget.contains(r'$')
        ? ' "$relTarget"'
        : '';
    final pubspec = File(p.join(workspacePath, 'pubspec.yaml'));
    final tsconfig = File(p.join(workspacePath, 'tsconfig.json'));
    if (await pubspec.exists()) {
      final res = await runtime.runCommandDetailed(
        'if command -v dart >/dev/null 2>&1; then '
        '  dart analyze$safeTarget 2>&1; '
        'elif [ -x "\$HOME/flutter/bin/dart" ]; then '
        '  "\$HOME/flutter/bin/dart" analyze$safeTarget 2>&1; '
        'else '
        '  flutter analyze --no-pub$safeTarget 2>&1; '
        'fi',
        workingDirectory: workspacePath,
        timeout: const Duration(seconds: 75),
      );
      final compact = McpService.formatCompactAnalyzerDiagnostics(
        res.combined,
        errorsOnly: true,
      );
      final withSnippets = await McpService.appendErrorSourceSnippets(
        workspacePath,
        compact,
      );
      if (withSnippets.trim().isNotEmpty) {
        return RoxumToolExecutionResult(success: true, output: withSnippets);
      }
    } else if (await tsconfig.exists()) {
      final res = await runtime.runCommandDetailed(
        'npx tsc --noEmit 2>&1',
        workingDirectory: workspacePath,
        timeout: const Duration(seconds: 60),
      );
      final compact = McpService.formatCompactAnalyzerDiagnostics(
        res.combined,
        errorsOnly: true,
      );
      return RoxumToolExecutionResult(
        success: true,
        output: compact.isEmpty ? 'Summary: 0 error(s). No issues found.' : compact,
      );
    }

    final editor = _ref.read(editorProvider);
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
      return RoxumToolExecutionResult(success: true, output: jsonEncode(items));
    }

    return const RoxumToolExecutionResult(
      success: true,
      output: 'Summary: 0 error(s), 0 warning(s), 0 info(s).\nNo issues found.',
    );
  }

  Future<RoxumToolExecutionResult> _readFile(
    String rawPath, {
    int? startLine,
    int? endLine,
  }) async {
    if (rawPath.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'filePath is required.',
      );
    }
    final path = _resolvePath(rawPath);
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
    // Keep tool observations small. Dumping a whole 1000+ line file into the
    // conversation burns the context window and makes the model think for
    // minutes. The agent should first read diagnostics, then request the exact
    // line range it needs.
    const maxWindow = 200;
    final defaultEnd =
        (startLine == null && endLine == null && lines.length > maxWindow)
        ? maxWindow
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
        '... [Showing lines $s-$e of ${lines.length}. Call readFile with startLine=${e + 1}, endLine=${(e + maxWindow).clamp(e + 1, lines.length)} to read further.]',
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

  Future<String> _recordAndWrite(
    String path,
    String newContent, {
    required bool existedBefore,
    required String originalContent,
    bool runAutoDiagnostics = true,
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
    onPendingEditsChanged?.call(
      Map<String, RoxumPendingEdit>.from(pendingEdits),
    );

    await _ref.read(editorProvider.notifier).reloadFileFromDisk(path);
    _refreshWorkspaceExplorer();
    try {
      await LiveTelemetryService.instance.onFileUpdated?.call(path);
    } catch (_) {}

    final notes = StringBuffer();
    try {
      final diags = FastSyntaxEngine.instance.analyze(path, newContent);
      if (diags.isNotEmpty) {
        final summary = diags
            .take(5)
            .map((d) => 'Line ${d.range.index + 1}: ${d.message}')
            .join('; ');
        notes.write(
          '\n[FastSyntaxEngine Warning: $summary — please verify brackets/quotes!]',
        );
      }
    } catch (_) {}

    // OpenCode-style inline diagnostics right inside writeFile / editFile / multiEditFile
    if (runAutoDiagnostics && _isInsideWorkspace(path)) {
      final ext = p.extension(path).toLowerCase();
      if (ext == '.dart') {
        final pubspec = File(p.join(workspacePath, 'pubspec.yaml'));
        if (await pubspec.exists()) {
          try {
            final rel = _relativePath(path);
            if (!rel.contains(';') && !rel.contains('`') && !rel.contains(r'$')) {
              final runtime = _ref.read(runtimeServiceProvider);
              final res = await runtime.runCommandDetailed(
                'if command -v dart >/dev/null 2>&1; then '
                '  dart analyze "$rel" 2>&1; '
                'elif [ -x "\$HOME/flutter/bin/dart" ]; then '
                '  "\$HOME/flutter/bin/dart" analyze "$rel" 2>&1; '
                'fi',
                workingDirectory: workspacePath,
                timeout: const Duration(seconds: 30),
              );
              if (res.combined.trim().isNotEmpty) {
                final compact = McpService.formatCompactAnalyzerDiagnostics(
                  res.combined,
                  errorsOnly: true,
                );
                final fullDiag = await McpService.appendErrorSourceSnippets(
                  workspacePath,
                  compact,
                  maxSnippets: 8,
                );
                notes.write('\n\n[Diagnostics for $rel]\n$fullDiag');
              }
            }
          } catch (_) {}
        }
      }
    }
    return notes.toString();
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

  Future<RoxumToolExecutionResult> _runGitCommand(String command) async {
    final ws = workspacePath.trim();
    if (ws.isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Not a git repository.',
      );
    }
    var dir = Directory(ws);
    var hasGit = false;
    for (int depth = 0; depth < 6; depth++) {
      final dotGitDir = Directory('${dir.path}${Platform.pathSeparator}.git');
      final dotGitFile = File('${dir.path}${Platform.pathSeparator}.git');
      if (await dotGitDir.exists() || await dotGitFile.exists()) {
        hasGit = true;
        break;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    if (!hasGit) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Not a git repository.',
      );
    }
    return await _runShell(command);
  }

  static final _lazyPlaceholderRe = RegExp(
    r'(//\s*\.\.\.\s*(existing|rest\s+of|remaining|unchanged|остальн|прежн|без\s+изменен)|/\*\s*\.\.\.\s*(existing|rest|остальн))',
    caseSensitive: false,
  );

  Future<RoxumToolExecutionResult> _writeFile(
    String rawPath,
    String content,
  ) async {
    if (rawPath.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'filePath is required for writeFile.',
      );
    }
    final path = _resolvePath(rawPath);
    final file = File(path);
    final existed = await file.exists();
    final original = existed ? await file.readAsString() : '';
    final originalLines = original.isEmpty ? 0 : original.split('\n').length;
    final rel = _relativePath(path);

    if (existed && originalLines > 30 && _lazyPlaceholderRe.hasMatch(content)) {
      return RoxumToolExecutionResult(
        success: false,
        output:
            'REJECTED: "$rel" already exists ($originalLines lines) and your content contains lazy placeholder comments (e.g. "// ... existing code"). '
            'Use `editFile` or `multiEditFile` to apply targeted replacements without deleting existing code!',
      );
    }

    final syntaxWarn = await _recordAndWrite(
      path,
      content,
      existedBefore: existed,
      originalContent: original,
    );
    final extraNotes = StringBuffer();
    if (existed && originalLines > 60) {
      extraNotes.write(
        '\n[TIP: "$rel" already existed ($originalLines lines). Prefer `editFile` or `multiEditFile` for incremental fixes.]',
      );
    }
    if (rel == 'pubspec.yaml' || rel.endsWith('/pubspec.yaml')) {
      extraNotes.write(
        '\n[ACTION REQUIRED: pubspec.yaml changed — run `flutter pub get` (or prefer `flutter pub add <package>`) to sync dependencies.]',
      );
    }
    return RoxumToolExecutionResult(
      success: true,
      output:
          'Wrote $rel (${content.split('\n').length} lines).$syntaxWarn${extraNotes.toString()}',
    );
  }

  /// OpenCode-style multi-stage matcher with ambiguity guard:
  /// 1) Exact match (rejects if >1 occurrence)
  /// 2) CRLF->LF normalized exact match (rejects if >1 occurrence)
  /// 3) Line-trimmed contiguous block match (tolerates indentation drift; rejects if >1 match)
  ({String? updated, String? error}) _applySmartReplacement(
    String source,
    String oldText,
    String newText,
  ) {
    if (oldText.isEmpty) {
      return (updated: null, error: 'oldText cannot be empty.');
    }

    List<int> findSubstringLines(String text, String needle) {
      final hits = <int>[];
      var pos = 0;
      while (true) {
        final idx = text.indexOf(needle, pos);
        if (idx < 0) break;
        final lineNum = '\n'.allMatches(text.substring(0, idx)).length + 1;
        hits.add(lineNum);
        pos = idx + needle.length;
        if (hits.length >= 6) break;
      }
      return hits;
    }

    final exactHits = findSubstringLines(source, oldText);
    if (exactHits.length == 1) {
      return (updated: source.replaceFirst(oldText, newText), error: null);
    }
    if (exactHits.length > 1) {
      return (
        updated: null,
        error:
            'Ambiguous oldText: matched ${exactHits.length}+ times (lines ${exactHits.join(', ')}). Include 2-3 surrounding lines for a unique match.',
      );
    }

    final normSource = source.replaceAll('\r\n', '\n');
    final normOld = oldText.replaceAll('\r\n', '\n');
    final normNew = newText.replaceAll('\r\n', '\n');
    final normHits = findSubstringLines(normSource, normOld);
    if (normHits.length == 1) {
      return (updated: normSource.replaceFirst(normOld, normNew), error: null);
    }
    if (normHits.length > 1) {
      return (
        updated: null,
        error:
            'Ambiguous oldText: matched ${normHits.length}+ times (lines ${normHits.join(', ')}). Include 2-3 surrounding lines for a unique match.',
      );
    }

    final srcLines = normSource.split('\n');
    final oldLines = normOld.split('\n');
    if (oldLines.length > 1 && oldLines.last.trim().isEmpty) {
      oldLines.removeLast();
    }
    if (oldLines.isEmpty || oldLines.length > srcLines.length) {
      return (updated: null, error: null);
    }

    final matchIndices = <int>[];
    for (var i = 0; i <= srcLines.length - oldLines.length; i++) {
      var allMatch = true;
      for (var j = 0; j < oldLines.length; j++) {
        if (srcLines[i + j].trim() != oldLines[j].trim()) {
          allMatch = false;
          break;
        }
      }
      if (allMatch) {
        matchIndices.add(i);
      }
    }

    if (matchIndices.length == 1) {
      final idx = matchIndices.first;
      final newLines = normNew.split('\n');
      final rebuilt = <String>[
        ...srcLines.sublist(0, idx),
        ...newLines,
        ...srcLines.sublist(idx + oldLines.length),
      ];
      return (updated: rebuilt.join('\n'), error: null);
    }
    if (matchIndices.length > 1) {
      final linesDesc = matchIndices.take(6).map((i) => i + 1).join(', ');
      return (
        updated: null,
        error:
            'Ambiguous oldText: matched ${matchIndices.length} times (lines $linesDesc). Include 2-3 surrounding lines for a unique match.',
      );
    }
    return (updated: null, error: null);
  }

  Future<RoxumToolExecutionResult> _editFile(
    String rawPath,
    String oldText,
    String newText,
  ) async {
    if (rawPath.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'filePath is required for editFile.',
      );
    }
    final path = _resolvePath(rawPath);
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    final original = await file.readAsString();
    final match = _applySmartReplacement(original, oldText, newText);
    if (match.updated == null) {
      if (match.error != null) {
        return RoxumToolExecutionResult(
          success: false,
          output: '${match.error} (${_relativePath(path)})',
        );
      }
      final hint = _closestLineHint(original, oldText);
      return RoxumToolExecutionResult(
        success: false,
        output: 'Target snippet not found in ${_relativePath(path)}.$hint',
      );
    }
    final syntaxWarn = await _recordAndWrite(
      path,
      match.updated!,
      existedBefore: true,
      originalContent: original,
    );
    final rel = _relativePath(path);
    final pubNote = (rel == 'pubspec.yaml' || rel.endsWith('/pubspec.yaml'))
        ? '\n[ACTION REQUIRED: pubspec.yaml changed — run `flutter pub get` to verify dependencies.]'
        : '';
    return RoxumToolExecutionResult(
      success: true,
      output: 'Updated $rel.$syntaxWarn$pubNote',
    );
  }

  List<dynamic> _parseMultiEditsArg(Object? rawEdits) {
    if (rawEdits is List) return rawEdits;
    if (rawEdits is Map) return [rawEdits];
    if (rawEdits is String) {
      final t = rawEdits.trim();
      if (t.isEmpty) return const [];
      for (final candidate in <String>[
        t,
        if (t.startsWith('[') && t.endsWith(')}'))
          '${t.substring(0, t.length - 2)}]',
        if (t.startsWith('[') && t.endsWith('}') && !t.endsWith('}]')) '$t]',
        if (t.startsWith('{') && t.endsWith('}')) '[$t]',
      ]) {
        try {
          final decoded = jsonDecode(candidate);
          if (decoded is List) return decoded;
          if (decoded is Map) return [decoded];
        } catch (_) {}
      }
    }
    return const [];
  }

  Future<RoxumToolExecutionResult> _multiEditFile(
    String rawPath,
    Object? rawEdits,
  ) async {
    if (rawPath.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'filePath is required for multiEditFile.',
      );
    }
    final path = _resolvePath(rawPath);
    final rel = _relativePath(path);
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: $rel',
      );
    }
    final editList = _parseMultiEditsArg(rawEdits);
    if (editList.isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output:
            'multiEditFile requires a native JSON array `edits` of {oldText, newText} objects (NOT a JSON string).',
      );
    }

    final original = await file.readAsString();
    var working = original;
    var appliedCount = 0;
    final failures = <String>[];

    for (var i = 0; i < editList.length; i++) {
      final item = editList[i];
      if (item is! Map) continue;
      final oldText =
          (item['oldText'] ?? item['oldString'] ?? item['old_string'])
              ?.toString() ??
          '';
      final newText =
          (item['newText'] ?? item['newString'] ?? item['new_string'])
              ?.toString() ??
          '';
      if (oldText.isEmpty) {
        failures.add('Edit #${i + 1}: oldText was empty.');
        continue;
      }
      final match = _applySmartReplacement(working, oldText, newText);
      if (match.updated != null) {
        working = match.updated!;
        appliedCount++;
      } else if (match.error != null) {
        failures.add('Edit #${i + 1} rejected: ${match.error}');
      } else {
        failures.add(
          'Edit #${i + 1} failed (snippet not found):${_closestLineHint(working, oldText)}',
        );
      }
    }

    if (appliedCount == 0) {
      return RoxumToolExecutionResult(
        success: false,
        output:
            'None of the ${editList.length} edits matched in $rel.\n${failures.join('\n')}',
      );
    }

    final syntaxWarn = await _recordAndWrite(
      path,
      working,
      existedBefore: true,
      originalContent: original,
    );
    final failSummary = failures.isEmpty
        ? ''
        : '\n[Partial warning: ${failures.length} edit(s) did not match:\n${failures.join('\n')}]';
    return RoxumToolExecutionResult(
      success: true,
      output:
          'Applied $appliedCount/${editList.length} edit(s) to $rel.$failSummary$syntaxWarn',
    );
  }

  Future<RoxumToolExecutionResult> _insertAtLine(
    String rawPath,
    int line,
    String text, {
    String position = 'after',
  }) async {
    final path = _resolvePath(rawPath);
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
    final insertIdx = position == 'before'
        ? idx
        : (idx + 1).clamp(0, lines.length);
    lines.insertAll(insertIdx, text.split('\n'));
    final syntaxWarn = await _recordAndWrite(
      path,
      lines.join('\n'),
      existedBefore: true,
      originalContent: original,
    );
    return RoxumToolExecutionResult(
      success: true,
      output:
          'Inserted text at line $line ($position) in ${_relativePath(path)}.$syntaxWarn',
    );
  }

  Future<RoxumToolExecutionResult> _replaceAllInFile(
    String rawPath,
    String search,
    String replace,
  ) async {
    final path = _resolvePath(rawPath);
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
    final syntaxWarn = await _recordAndWrite(
      path,
      updated,
      existedBefore: true,
      originalContent: original,
    );
    return RoxumToolExecutionResult(
      success: true,
      output: 'Replaced all occurrences in ${_relativePath(path)}.$syntaxWarn',
    );
  }

  String _closestLineHint(String content, String target) {
    if (target.trim().isEmpty) return '';
    final firstNonEmptyLine = target
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => target.trim());
    final targetWords = firstNonEmptyLine
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toSet();
    if (targetWords.isEmpty) return '';

    var best = 0.0;
    var bestLine = 0;
    final lines = content.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final words = lines[i]
          .trim()
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toSet();
      if (words.isEmpty) continue;
      final score =
          targetWords.intersection(words).length /
          targetWords.union(words).length;
      if (score > best) {
        best = score;
        bestLine = i + 1;
      }
    }
    if (best < 0.45 || bestLine == 0) return '';
    final winStart = (bestLine - 5).clamp(1, lines.length);
    final winEnd = (bestLine + 9).clamp(winStart, lines.length);
    final snippet = StringBuffer();
    for (var ln = winStart; ln <= winEnd; ln++) {
      snippet.writeln('$ln: ${lines[ln - 1]}');
    }
    return '\nClosest match near line $bestLine (#L$winStart-$winEnd — copy exact lines from here):\n${snippet.toString().trimRight()}';
  }

  Future<RoxumToolExecutionResult> _replaceInProject(
    String search,
    String replacement, {
    required bool isRegex,
    required String globPattern,
    String? directoryPath,
    required bool dryRun,
  }) async {
    if (search.isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Search must not be empty.',
      );
    }
    final root = _resolvePath(directoryPath ?? '.');
    final dir = Directory(root);
    if (!await dir.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Directory not found: ${_relativePath(root)}',
      );
    }
    final matcher = RegExp(
      '^${RegExp.escape(globPattern).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*').replaceAll(r'\?', '.')}\$',
      caseSensitive: false,
    );
    final pattern = isRegex ? RegExp(search) : null;
    final report = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || _isIgnored(entity.path)) continue;
      final rel = _relativePath(entity.path).replaceAll('\\', '/');
      if (!matcher.hasMatch(rel) && !matcher.hasMatch(p.basename(rel))) {
        continue;
      }
      try {
        final original = await entity.readAsString();
        final updated = pattern == null
            ? original.replaceAll(search, replacement)
            : original.replaceAllMapped(pattern, (_) => replacement);
        if (updated == original) continue;
        final count = pattern == null
            ? search.allMatches(original).length
            : pattern.allMatches(original).length;
        if (!dryRun) {
          await _recordAndWrite(
            entity.path,
            updated,
            existedBefore: true,
            originalContent: original,
            runAutoDiagnostics: false,
          );
        }
        report.add('$rel: $count replacement(s)${dryRun ? ' (dry-run)' : ''}');
      } catch (_) {}
    }
    return RoxumToolExecutionResult(
      success: true,
      output: report.isEmpty
          ? 'No matching files or occurrences.'
          : report.join('\n'),
    );
  }

  bool _isIgnored(String filePath) {
    final rel = _relativePath(filePath).replaceAll('\\', '/');
    const ignored = {
      '.git',
      'build',
      '.dart_tool',
      '.gradle',
      '.kotlin',
      'node_modules',
      'target',
      '.venv',
      '__pycache__',
      'dist',
      'ephemeral',
      '.idea',
      '.quantum',
    };
    return rel.split('/').any(ignored.contains);
  }

  Future<RoxumToolExecutionResult> _deleteFile(String rawPath) async {
    final path = _resolvePath(rawPath);
    final file = File(path);
    if (!await file.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'File not found: ${_relativePath(path)}',
      );
    }
    await file.delete();
    _refreshWorkspaceExplorer();
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
    if (await File(oldPath).exists()) {
      await File(newPath).parent.create(recursive: true);
      await File(oldPath).rename(newPath);
      _refreshWorkspaceExplorer();
      return RoxumToolExecutionResult(
        success: true,
        output:
            'Renamed ${_relativePath(oldPath)} -> ${_relativePath(newPath)}.',
      );
    }
    if (await Directory(oldPath).exists()) {
      await Directory(oldPath).rename(newPath);
      _refreshWorkspaceExplorer();
      return RoxumToolExecutionResult(
        success: true,
        output:
            'Renamed directory ${_relativePath(oldPath)} -> ${_relativePath(newPath)}.',
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
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return RoxumToolExecutionResult(
        success: false,
        output: 'Directory not found: ${_relativePath(dirPath)}',
      );
    }
    final entries = <String>[];
    await for (final entity in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      final rel = _relativePath(entity.path);
      if (recursive &&
          (rel.startsWith('.git/') ||
              rel.contains('/.git/') ||
              rel.contains('/.dart_tool/') ||
              rel.contains('/build/'))) {
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

  Future<RoxumToolExecutionResult> _globSearchFiles(
    String pattern, {
    String? directoryPath,
  }) async {
    final root = Directory(_resolvePath(directoryPath ?? '.'));
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
      if (_isIgnored(entity.path)) {
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
    bool isRegex = true,
    bool caseSensitive = false,
  }) async {
    if (query.trim().isEmpty) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Query must not be empty.',
      );
    }
    final base = _resolvePath(directoryPath ?? '');
    final dir = Directory(base);
    if (!await dir.exists()) {
      return const RoxumToolExecutionResult(
        success: false,
        output: 'Directory not found.',
      );
    }
    final hits = <String>[];
    RegExp? regex;
    try {
      regex = RegExp(query, caseSensitive: caseSensitive);
    } catch (_) {
      regex = RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
    }
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = _relativePath(entity.path);
      if (_isIgnored(entity.path)) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.size > 512 * 1024) continue;
        final lines = await entity.readAsLines();
        for (int i = 0; i < lines.length; i++) {
          if ((isRegex
              ? regex.hasMatch(lines[i])
              : (caseSensitive
                    ? lines[i].contains(query)
                    : lines[i].toLowerCase().contains(query.toLowerCase())))) {
            hits.add('$rel:${i + 1}: ${lines[i].trim()}');
            if (hits.length >= 100) break;
          }
        }
      } catch (_) {}
      if (hits.length >= 100) break;
    }
    return RoxumToolExecutionResult(
      success: true,
      output: hits.isEmpty
          ? 'No matches found.'
          : '${hits.join('\n')}${hits.length >= 100 ? '\n... and more matches. Narrow your directoryPath or pattern.' : ''}',
    );
  }

  bool _parseBool(Object? value, {required bool defaultValue}) {
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return defaultValue;
  }

  int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  Future<RoxumToolExecutionResult> _getFileInfo(String rawPath) async {
    final path = _resolvePath(rawPath);
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
        .map(
          (e) => {
            'file': _relativePath(e.filePath),
            'addedLines': e.addedLines,
            'removedLines': e.removedLines,
          },
        )
        .toList();
    return RoxumToolExecutionResult(
      success: true,
      output: list.isEmpty ? 'No pending edits.' : jsonEncode(list),
    );
  }

  Future<RoxumToolExecutionResult> _codeOutline(String rawPath) async {
    final targetPath = _resolvePath(rawPath);
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
    return RoxumToolExecutionResult(success: true, output: res.combined.trim());
  }

  Future<RoxumToolExecutionResult> _installPackages(
    List<String> packages, {
    String manager = 'auto',
  }) async {
    final cleanPkgs = packages
        .map((e) => e.trim())
        .where(
          (e) => e.isNotEmpty && RegExp(r'^[a-zA-Z0-9_.\-@/:+]+$').hasMatch(e),
        )
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
      } else if (await File(
            p.join(workspacePath, 'requirements.txt'),
          ).exists() ||
          await File(p.join(workspacePath, 'pyproject.toml')).exists()) {
        resolvedManager = 'pip';
      } else {
        resolvedManager = 'apt';
      }
    }

    final pkgArgs = cleanPkgs.join(' ');
    final String cmd = switch (resolvedManager) {
      'pub' => '(flutter pub add $pkgArgs 2>&1 || dart pub add $pkgArgs 2>&1)',
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
    _refreshWorkspaceExplorer();
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
    _refreshWorkspaceExplorer();
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
          ? '$header(command completed with exit code ${res.exitCode} and no output)'
          : '$header$combined',
    );
  }
}


/// Compatibility shim for the removed legacy MCP service. Diagnostics helpers
/// are pass-through now; MCP is handled by PocketStrike's manager.
class McpService {
  static String formatCompactAnalyzerDiagnostics(
    String text, {
    bool errorsOnly = false,
  }) =>
      text;
  static Future<String> appendErrorSourceSnippets(
    String workspacePath,
    String text, {
    int maxSnippets = 6,
  }) async =>
      text;
}
