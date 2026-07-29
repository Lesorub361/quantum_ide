import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:diff_match_patch/diff_match_patch.dart' show DiffMatchPatch, patchMake;
import 'package:quantum_ide/core/services/ai_tool_definitions.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/agent_markers.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:dio/dio.dart';

class PendingEdit {
  final String filePath;
  final String oldText;
  final List<String> diffLines;

  PendingEdit({
    required this.filePath,
    required this.oldText,
    required this.diffLines,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'diffLines': diffLines,
  };
}

class EnhancedAIToolExecutor {
  final Ref ref;
  final Dio _dio = Dio();
  final Map<String, PendingEdit> _pendingEdits = {};

  EnhancedAIToolExecutor(this.ref);

  String get workspacePath => ref.read(workspaceProvider).currentPath ?? '';

  List<String> get pendingFiles => _pendingEdits.keys.toList();

  PendingEdit? getPendingEdit(String filePath) => _pendingEdits[filePath];

  void clearPendingEdit(String filePath) => _pendingEdits.remove(filePath);

  void _refreshFileExplorer(String filePath) {
    final ws = ref.read(workspaceProvider).currentPath;
    if (ws == null) return;
    
    final parentDir = p.dirname(filePath);
    if (parentDir == ws || parentDir.startsWith(ws)) {
      ref.read(fileExplorerProvider.notifier).scanDirectory(parentDir);
    }
    
    if (filePath.startsWith(ws)) {
      ref.read(fileExplorerProvider.notifier).scanDirectory(ws);
    }
  }

  String _resolvePath(String relativePath) {
    if (p.isAbsolute(relativePath)) return relativePath;
    return p.join(workspacePath, relativePath);
  }

  bool _isInsideWorkspace(String path) {
    final canonical = Directory(path).absolute.path;
    final canonicalWs = Directory(workspacePath).absolute.path;
    return canonical == canonicalWs || p.isWithin(canonicalWs, canonical);
  }

  Future<void> _trackPendingDiff(String canonicalPath, String oldContent, String newContent) async {
    if (oldContent == newContent) return;
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(oldContent, newContent);
    final patches = patchMake(oldContent, b: diffs);
    if (patches.isEmpty) return;
    final patchTexts = patches.map((patch) => patch.toString()).toList();
    _pendingEdits[canonicalPath] = PendingEdit(
      filePath: canonicalPath,
      oldText: oldContent,
      diffLines: patchTexts,
    );
  }

  List<AIToolDefinition> getTools({bool readAccessOnly = false}) {
    return [
      const AIToolDefinition(
        name: 'read_file',
        description: 'Read the contents of a file. Use before editing when you need current content.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'File path relative to workspace root'},
          },
          'required': ['path'],
        },
        risk: AIToolRisk.low,
      ),
      if (!readAccessOnly)
        const AIToolDefinition(
          name: 'write_file',
          description: 'Create or completely replace a file with new content. Creates pending diff.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'File path relative to workspace root'},
              'content': {'type': 'string', 'description': 'Full file content to write'},
            },
            'required': ['path', 'content'],
          },
          risk: AIToolRisk.medium,
        ),
      if (!readAccessOnly)
        const AIToolDefinition(
          name: 'edit_file',
          description: 'Apply a search-and-replace edit to a file with pending diff tracking.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'File path relative to workspace root'},
              'old_string': {'type': 'string', 'description': 'Exact text to find'},
              'new_string': {'type': 'string', 'description': 'Replacement text'},
            },
            'required': ['path', 'old_string', 'new_string'],
          },
          risk: AIToolRisk.medium,
        ),
      if (!readAccessOnly)
        const AIToolDefinition(
          name: 'create_file',
          description: 'Create a new file with the given content.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'File path relative to workspace root'},
              'content': {'type': 'string', 'description': 'File content'},
            },
            'required': ['path', 'content'],
          },
          risk: AIToolRisk.medium,
        ),
      if (!readAccessOnly)
        const AIToolDefinition(
          name: 'delete_file',
          description: 'Delete a file. This action cannot be undone.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'File path relative to workspace root'},
            },
            'required': ['path'],
          },
          risk: AIToolRisk.high,
        ),
      if (!readAccessOnly)
        const AIToolDefinition(
          name: 'insert_at_line',
          description: 'Insert text before or after a specific 1-indexed line with pending diff tracking.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'File path'},
              'line': {'type': 'integer', 'description': '1-indexed line number'},
              'text': {'type': 'string', 'description': 'Text to insert'},
              'position': {'type': 'string', 'description': 'before or after (default before)'},
            },
            'required': ['path', 'line', 'text'],
          },
          risk: AIToolRisk.medium,
        ),
      if (!readAccessOnly)
        const AIToolDefinition(
          name: 'replace_all_in_file',
          description: 'Replace all matching text in a file with pending diff tracking.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'File path'},
              'old_text': {'type': 'string', 'description': 'Text to find'},
              'new_text': {'type': 'string', 'description': 'Replacement text'},
              'case_sensitive': {'type': 'boolean', 'description': 'Case sensitive (default true)'},
            },
            'required': ['path', 'old_text', 'new_text'],
          },
          risk: AIToolRisk.medium,
        ),
      const AIToolDefinition(
        name: 'read_files_batch',
        description: 'Read multiple files in one call with optional line ranges.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'files': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                  'start_line': {'type': 'integer'},
                  'end_line': {'type': 'integer'},
                },
                'required': ['path'],
              },
            },
          },
          'required': ['files'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'glob_search',
        description: 'Find files by glob pattern (e.g. "**/*.dart", "src/**/*.ts").',
        inputSchema: {
          'type': 'object',
          'properties': {
            'pattern': {'type': 'string', 'description': 'Glob pattern to match'},
            'directory': {'type': 'string', 'description': 'Optional root directory'},
            'recursive': {'type': 'boolean', 'description': 'Search recursively (default true)'},
            'max_results': {'type': 'integer', 'description': 'Max results'},
          },
          'required': ['pattern'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'grep_in_files',
        description: 'Search files and return matching lines with before/after context lines.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Search query'},
            'file_pattern': {'type': 'string', 'description': 'Glob pattern to filter files'},
            'case_sensitive': {'type': 'boolean', 'description': 'Case sensitive (default false)'},
            'use_regex': {'type': 'boolean', 'description': 'Use regex (default false)'},
            'before': {'type': 'integer', 'description': 'Context lines before match (default 2)'},
            'after': {'type': 'integer', 'description': 'Context lines after match (default 2)'},
            'max_results': {'type': 'integer', 'description': 'Max results'},
          },
          'required': ['query'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'search_code',
        description: 'Search for text patterns across the codebase.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Search query'},
            'file_pattern': {'type': 'string', 'description': 'Glob pattern to filter files'},
          },
          'required': ['query'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'list_directory',
        description: 'List files and subdirectories in a directory.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Directory path'},
          },
          'required': ['path'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'get_file_info',
        description: 'Get file/directory metadata: size, modification time, whether it exists.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'File or directory path'},
          },
          'required': ['path'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'get_pending_edits',
        description: 'Get pending agentic diff hunks for a file.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'File path'},
          },
          'required': ['path'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'active_editor_file',
        description: 'Get the path of the currently active/opened editor file.',
        inputSchema: {'type': 'object', 'properties': {}},
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'run_command',
        description: 'Execute a shell command. Returns stdout and stderr.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'command': {'type': 'string', 'description': 'Shell command to execute'},
            'working_directory': {'type': 'string', 'description': 'Working directory (optional)'},
          },
          'required': ['command'],
        },
        risk: AIToolRisk.medium,
      ),
      const AIToolDefinition(
        name: 'search_web',
        description: 'Search the web for information.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'Search query'},
          },
          'required': ['query'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'fetch_url',
        description: 'Fetch content from a URL.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': 'URL to fetch'},
          },
          'required': ['url'],
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'git_status',
        description: 'Get the current git status.',
        inputSchema: {'type': 'object', 'properties': {}},
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'git_diff',
        description: 'Show git diff for staged or unstaged changes.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'file_path': {'type': 'string', 'description': 'Optional file path'},
            'staged': {'type': 'boolean', 'description': 'Staged changes'},
          },
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'git_log',
        description: 'Show recent git commit history.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'count': {'type': 'integer', 'description': 'Number of commits'},
          },
        },
        risk: AIToolRisk.low,
      ),
      const AIToolDefinition(
        name: 'git_commit',
        description: 'Stage all changes and create a git commit.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'message': {'type': 'string', 'description': 'Commit message'},
          },
          'required': ['message'],
        },
        risk: AIToolRisk.medium,
      ),
    ];
  }

  Future<AIToolResult> executeTool(AIToolCall toolCall) async {
    try {
      switch (toolCall.name) {
        case 'read_file': return await _readFile(toolCall);
        case 'write_file': return await _writeFile(toolCall);
        case 'edit_file': return await _editFile(toolCall);
        case 'create_file': return await _createFile(toolCall);
        case 'delete_file': return await _deleteFile(toolCall);
        case 'insert_at_line': return await _insertAtLine(toolCall);
        case 'replace_all_in_file': return await _replaceAllInFile(toolCall);
        case 'read_files_batch': return await _readFilesBatch(toolCall);
        case 'glob_search': return await _globSearch(toolCall);
        case 'grep_in_files': return await _grepInFiles(toolCall);
        case 'search_code': return await _searchCode(toolCall);
        case 'list_directory': return await _listDirectory(toolCall);
        case 'get_file_info': return await _getFileInfo(toolCall);
        case 'get_pending_edits': return await _getPendingEdits(toolCall);
        case 'active_editor_file': return _activeEditorFile(toolCall);
        case 'run_command': return await _runCommand(toolCall);
        case 'search_web': return await _searchWeb(toolCall);
        case 'fetch_url': return await _fetchUrl(toolCall);
        case 'git_status': return await _gitStatus(toolCall);
        case 'git_diff': return await _gitDiff(toolCall);
        case 'git_log': return await _gitLog(toolCall);
        case 'git_commit': return await _gitCommit(toolCall);
        default:
          return AIToolResult(toolCallId: toolCall.id, content: 'Unknown tool: ${toolCall.name}', isError: true);
      }
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Error executing ${toolCall.name}: $e', isError: true);
    }
  }

  Future<AIToolResult> _readFile(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final startLine = toolCall.arguments['start_line'] as int?;
    final endLine = toolCall.arguments['end_line'] as int?;
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied: file is outside workspace', isError: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'File not found: ${toolCall.arguments['path']}', isError: true);
    }
    final content = await file.readAsString();
    if (startLine == null && endLine == null) {
      final lines = content.split('\n');
      if (lines.length > 500) {
        return AIToolResult(toolCallId: toolCall.id, content: '${lines.take(500).join('\n')}\n\n... (${lines.length - 500} more lines)');
      }
      return AIToolResult(toolCallId: toolCall.id, content: content);
    }
    final allLines = content.split('\n');
    final start = (startLine ?? 1) - 1;
    final end = endLine ?? allLines.length;
    final sliced = allLines.sublist(start.clamp(0, allLines.length), end.clamp(0, allLines.length));
    return AIToolResult(toolCallId: toolCall.id, content: sliced.join('\n'));
  }

  Future<AIToolResult> _writeFile(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final content = toolCall.arguments['content'] as String;
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied', isError: true);
    }
    final file = File(filePath);
    String? oldContent;
    if (await file.exists()) {
      oldContent = await file.readAsString();
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    await _trackPendingDiff(filePath, oldContent ?? '', content);
    _refreshFileExplorer(filePath);
    final added = lineCount(content);
    final removed = lineCount(oldContent);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File written successfully: ${toolCall.arguments['path']}\n[QUANTUM_EDIT_MARKER:+$added/-$removed]',
    );
  }

  Future<AIToolResult> _editFile(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final oldString = toolCall.arguments['old_string'] as String;
    final newString = toolCall.arguments['new_string'] as String;
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied', isError: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'File not found: ${toolCall.arguments['path']}', isError: true);
    }
    final oldContent = await file.readAsString();
    if (!oldContent.contains(oldString)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'old_string not found in file', isError: true);
    }
    final newContent = oldContent.replaceFirst(oldString, newString);
    await file.writeAsString(newContent);
    await _trackPendingDiff(filePath, oldContent, newContent);
    _refreshFileExplorer(filePath);
    final added = lineCount(newString);
    final removed = lineCount(oldString);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File edited successfully: ${toolCall.arguments['path']}\n[QUANTUM_EDIT_MARKER:+$added/-$removed]',
    );
  }

  Future<AIToolResult> _createFile(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final content = toolCall.arguments['content'] as String;
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied', isError: true);
    }
    final file = File(filePath);
    if (await file.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'File already exists: ${toolCall.arguments['path']}', isError: true);
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    await _trackPendingDiff(filePath, '', content);
    _refreshFileExplorer(filePath);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File created: ${toolCall.arguments['path']}\n[QUANTUM_EDIT_MARKER:+${lineCount(content)}/-0]',
    );
  }

  Future<AIToolResult> _deleteFile(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied', isError: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'File not found', isError: true);
    }
    final oldContent = await file.readAsString();
    await file.delete();
    _pendingEdits.remove(filePath);
    _refreshFileExplorer(filePath);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File deleted: ${toolCall.arguments['path']}\n[QUANTUM_EDIT_MARKER:+0/-${lineCount(oldContent)}]',
    );
  }

  Future<AIToolResult> _insertAtLine(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final line = toolCall.arguments['line'] as int;
    final text = toolCall.arguments['text'] as String;
    final position = (toolCall.arguments['position'] as String?) ?? 'before';
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied', isError: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'File not found', isError: true);
    }
    final oldContent = await file.readAsString();
    final lines = oldContent.split('\n');
    final insertLines = text.split('\n');
    final insertIndex = position == 'before' ? (line - 1).clamp(0, lines.length) : line.clamp(0, lines.length);
    lines.insertAll(insertIndex, insertLines);
    final newContent = lines.join('\n');
    await file.writeAsString(newContent);
    await _trackPendingDiff(filePath, oldContent, newContent);
    _refreshFileExplorer(filePath);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'Text inserted at line $line\n[QUANTUM_EDIT_MARKER:+${lineCount(text)}/-0]',
    );
  }

  Future<AIToolResult> _replaceAllInFile(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final oldText = toolCall.arguments['old_text'] as String;
    final newText = toolCall.arguments['new_text'] as String;
    final caseSensitive = toolCall.arguments['case_sensitive'] as bool? ?? true;
    if (!_isInsideWorkspace(filePath)) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Permission denied', isError: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'File not found', isError: true);
    }
    final oldContent = await file.readAsString();
    final regex = RegExp(RegExp.escape(oldText), caseSensitive: caseSensitive);
    final matches = regex.allMatches(oldContent).length;
    if (matches == 0) {
      return AIToolResult(toolCallId: toolCall.id, content: 'No matches found', isError: true);
    }
    final newContent = oldContent.replaceAll(regex, newText);
    await file.writeAsString(newContent);
    await _trackPendingDiff(filePath, oldContent, newContent);
    _refreshFileExplorer(filePath);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'Replaced $matches occurrences\n[QUANTUM_EDIT_MARKER:+${lineCount(newText) * matches}/-${lineCount(oldText) * matches}]',
    );
  }

  Future<AIToolResult> _readFilesBatch(AIToolCall toolCall) async {
    final files = (toolCall.arguments['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final results = <String, String>{};
    for (final file in files) {
      final path = file['path'] as String;
      final resolvedPath = _resolvePath(path);
      final startLine = file['start_line'] as int?;
      final endLine = file['end_line'] as int?;
      try {
        final f = File(resolvedPath);
        if (!await f.exists()) {
          results[path] = 'File not found';
          continue;
        }
        final content = await f.readAsString();
        if (startLine != null || endLine != null) {
          final allLines = content.split('\n');
          final start = ((startLine ?? 1) - 1).clamp(0, allLines.length);
          final end = (endLine ?? allLines.length).clamp(0, allLines.length);
          results[path] = allLines.sublist(start, end).join('\n');
        } else {
          results[path] = content.length > 10000 ? '${content.substring(0, 10000)}\n... (truncated)' : content;
        }
      } catch (e) {
        results[path] = 'Error: $e';
      }
    }
    return AIToolResult(toolCallId: toolCall.id, content: jsonEncode(results));
  }

  Future<AIToolResult> _globSearch(AIToolCall toolCall) async {
    final pattern = toolCall.arguments['pattern'] as String;
    final directory = toolCall.arguments['directory'] as String?;
    final maxResults = toolCall.arguments['max_results'] as int? ?? 100;
    final searchDir = directory != null ? _resolvePath(directory) : workspacePath;
    final regex = _globToRegex(pattern);
    final results = <String>[];
    try {
      final dir = Directory(searchDir);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = p.relative(entity.path, from: workspacePath);
        if (regex.hasMatch(relativePath)) {
          results.add(relativePath);
          if (results.length >= maxResults) break;
        }
      }
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Glob search error: $e', isError: true);
    }
    return AIToolResult(toolCallId: toolCall.id, content: results.isEmpty ? 'No matches' : results.join('\n'));
  }

  Future<AIToolResult> _grepInFiles(AIToolCall toolCall) async {
    final query = toolCall.arguments['query'] as String;
    final filePattern = toolCall.arguments['file_pattern'] as String?;
    final caseSensitive = toolCall.arguments['case_sensitive'] as bool? ?? false;
    final useRegex = toolCall.arguments['use_regex'] as bool? ?? false;
    final before = toolCall.arguments['before'] as int? ?? 2;
    final after = toolCall.arguments['after'] as int? ?? 2;
    final maxResults = toolCall.arguments['max_results'] as int? ?? 50;
    final results = <String>[];
    try {
      final dir = Directory(workspacePath);
      final regex = useRegex ? RegExp(query, caseSensitive: caseSensitive) : RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final filePath = entity.path;
        if (filePath.contains('.git') || filePath.contains('node_modules')) continue;
        if (filePattern != null && !p.basename(filePath).contains(RegExp(filePattern))) continue;
        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');
          final relativePath = p.relative(filePath, from: workspacePath);
          for (int i = 0; i < lines.length; i++) {
            if (regex.hasMatch(lines[i])) {
              final startIdx = (i - before).clamp(0, lines.length);
              final endIdx = (i + after + 1).clamp(0, lines.length);
              final numbered = <String>[];
              for (int j = startIdx; j < endIdx; j++) {
                final marker = j == i ? '>' : ' ';
                numbered.add('$relativePath:${j + 1}:$marker ${lines[j]}');
              }
              results.add(numbered.join('\n'));
              if (results.length >= maxResults) break;
            }
          }
          if (results.length >= maxResults) break;
        } catch (_) {}
      }
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Grep error: $e', isError: true);
    }
    return AIToolResult(toolCallId: toolCall.id, content: results.isEmpty ? 'No matches' : results.join('\n\n'));
  }

  Future<AIToolResult> _searchCode(AIToolCall toolCall) async {
    final query = toolCall.arguments['query'] as String;
    final filePattern = toolCall.arguments['file_pattern'] as String?;
    final results = <String>[];
    final dir = Directory(workspacePath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final filePath = entity.path;
      if (filePattern != null && !filePath.endsWith(filePattern.replaceAll('*', ''))) continue;
      if (filePath.contains('.git') || filePath.contains('node_modules')) continue;
      try {
        final content = await entity.readAsString();
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains(query)) {
            results.add('${p.relative(filePath, from: workspacePath)}:${i + 1}: ${lines[i].trim()}');
            if (results.length >= 50) break;
          }
        }
        if (results.length >= 50) break;
      } catch (_) {}
    }
    return AIToolResult(toolCallId: toolCall.id, content: results.isEmpty ? 'No matches for "$query"' : 'Found ${results.length} matches:\n${results.join('\n')}');
  }

  Future<AIToolResult> _listDirectory(AIToolCall toolCall) async {
    final dirPath = _resolvePath(toolCall.arguments['path'] as String);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Directory not found: ${toolCall.arguments['path']}', isError: true);
    }
    final entries = <String>[];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      entries.add('${entity is Directory ? "[DIR]" : "     "} $name');
    }
    entries.sort();
    return AIToolResult(toolCallId: toolCall.id, content: entries.isEmpty ? 'Empty directory' : entries.join('\n'));
  }

  Future<AIToolResult> _getFileInfo(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final file = File(filePath);
    final dir = Directory(filePath);
    try {
      if (await file.exists()) {
        final stat = await file.stat();
        return AIToolResult(toolCallId: toolCall.id, content: jsonEncode({
          'path': toolCall.arguments['path'],
          'exists': true,
          'isDirectory': false,
          'size': stat.size,
          'modified': stat.modified.toIso8601String(),
          'extension': p.extension(filePath),
        }));
      }
      if (await dir.exists()) {
        final stat = await dir.stat();
        int fileCount = 0;
        await for (final _ in dir.list()) { fileCount++; }
        return AIToolResult(toolCallId: toolCall.id, content: jsonEncode({
          'path': toolCall.arguments['path'],
          'exists': true,
          'isDirectory': true,
          'fileCount': fileCount,
          'modified': stat.modified.toIso8601String(),
        }));
      }
      return AIToolResult(toolCallId: toolCall.id, content: jsonEncode({'path': toolCall.arguments['path'], 'exists': false}));
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Error: $e', isError: true);
    }
  }

  Future<AIToolResult> _getPendingEdits(AIToolCall toolCall) async {
    final filePath = _resolvePath(toolCall.arguments['path'] as String);
    final pending = _pendingEdits[filePath];
    if (pending == null) {
      return AIToolResult(toolCallId: toolCall.id, content: 'No pending edits');
    }
    return AIToolResult(toolCallId: toolCall.id, content: jsonEncode(pending.toJson()));
  }

  AIToolResult _activeEditorFile(AIToolCall toolCall) {
    // Return the currently open/active file path, not the workspace root.
    final editorState = ref.read(editorProvider);
    final activeFile = editorState.activeFilePath;
    if (activeFile == null || activeFile.isEmpty) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'No file is currently open in the editor',
        isError: true,
      );
    }
    return AIToolResult(toolCallId: toolCall.id, content: activeFile);
  }

  Future<AIToolResult> _runCommand(AIToolCall toolCall) async {
    final command = toolCall.arguments['command'] as String;
    final workingDir = toolCall.arguments['working_directory'] as String?;
    final cwd = workingDir != null ? _resolvePath(workingDir) : workspacePath;
    try {
      final result = await Process.run('bash', ['-c', command], workingDirectory: cwd);
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      final exitCode = result.exitCode;
      final output = StringBuffer();
      if (stdout.isNotEmpty) output.write(stdout);
      if (stderr.isNotEmpty) output.write('\n$stderr');
      output.write('\nExit code: $exitCode');
      return AIToolResult(
        toolCallId: toolCall.id,
        content: output.toString().trim(),
        isError: exitCode != 0,
      );
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Command failed: $e', isError: true);
    }
  }

  Future<AIToolResult> _searchWeb(AIToolCall toolCall) async {
    final query = toolCall.arguments['query'] as String;
    try {
      final response = await _dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
        options: Options(headers: {'User-Agent': 'Mozilla/5.0 (compatible; QuantumIDE/1.0)'}),
      );
      final html = response.data as String;
      final results = <String>[];
      final linkRegex = RegExp(r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>');
      final snippetRegex = RegExp(r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>');
      final links = linkRegex.allMatches(html).take(5);
      final snippets = snippetRegex.allMatches(html).take(5);
      int i = 0;
      for (final link in links) {
        final url = link.group(1) ?? '';
        final title = link.group(2)?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '';
        final snippet = i < snippets.length ? (snippets.elementAt(i).group(1)?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '') : '';
        results.add('${i + 1}. $title\n   $url\n   $snippet');
        i++;
      }
      return AIToolResult(toolCallId: toolCall.id, content: results.isEmpty ? 'No results' : results.join('\n\n'));
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Search failed: $e', isError: true);
    }
  }

  Future<AIToolResult> _fetchUrl(AIToolCall toolCall) async {
    final url = toolCall.arguments['url'] as String;
    try {
      final response = await _dio.get(url, options: Options(
        headers: {'User-Agent': 'Mozilla/5.0 (compatible; QuantumIDE/1.0)'},
        responseType: ResponseType.plain,
      ));
      var content = response.data as String;
      content = content.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
      content = content.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
      content = content.replaceAll(RegExp(r'<[^>]*>'), ' ');
      content = content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (content.length > 5000) content = '${content.substring(0, 5000)}\n... (truncated)';
      return AIToolResult(toolCallId: toolCall.id, content: content);
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Failed: $e', isError: true);
    }
  }

  Future<AIToolResult> _gitStatus(AIToolCall toolCall) async {
    try {
      final result = await Process.run('git', ['status', '--porcelain'], workingDirectory: workspacePath);
      final output = result.stdout.toString().trim();
      return AIToolResult(toolCallId: toolCall.id, content: output.isEmpty ? 'Working tree clean' : output);
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git error: $e', isError: true);
    }
  }

  Future<AIToolResult> _gitDiff(AIToolCall toolCall) async {
    try {
      final filePath = toolCall.arguments['file_path'] as String?;
      final staged = toolCall.arguments['staged'] as bool? ?? false;
      final args = ['diff'];
      if (staged) args.add('--staged');
      if (filePath != null) args.add(filePath);
      final result = await Process.run('git', args, workingDirectory: workspacePath);
      final output = result.stdout.toString().trim();
      return AIToolResult(toolCallId: toolCall.id, content: output.isEmpty ? 'No changes' : (output.length > 5000 ? '${output.substring(0, 5000)}\n... (truncated)' : output));
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git diff error: $e', isError: true);
    }
  }

  Future<AIToolResult> _gitLog(AIToolCall toolCall) async {
    try {
      final count = toolCall.arguments['count'] as int? ?? 10;
      final result = await Process.run('git', ['log', '--oneline', '-n', count.toString()], workingDirectory: workspacePath);
      return AIToolResult(toolCallId: toolCall.id, content: result.stdout.toString().trim());
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git log error: $e', isError: true);
    }
  }

  Future<AIToolResult> _gitCommit(AIToolCall toolCall) async {
    try {
      final message = toolCall.arguments['message'] as String;
      await Process.run('git', ['add', '-A'], workingDirectory: workspacePath);
      final result = await Process.run('git', ['commit', '-m', message], workingDirectory: workspacePath);
      return AIToolResult(toolCallId: toolCall.id, content: '${result.stdout}\n${result.stderr}'.trim());
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git commit error: $e', isError: true);
    }
  }

  RegExp _globToRegex(String glob) {
    final regexStr = glob
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.');
    return RegExp('^$regexStr\$', dotAll: true);
  }
}

final enhancedAIToolExecutorProvider = Provider<EnhancedAIToolExecutor>((ref) {
  return EnhancedAIToolExecutor(ref);
});
