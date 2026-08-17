import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/ai_tool_definitions.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:dio/dio.dart';

final aiToolExecutorProvider = Provider<AIToolExecutor>((ref) {
  return AIToolExecutor(ref);
});

class AIToolExecutor {
  final Ref ref;
  final Dio _dio = Dio();

  AIToolExecutor(this.ref);

  String get workspacePath => ref.read(workspaceProvider).currentPath ?? '';

  Future<AIToolResult> executeTool(AIToolCall toolCall) async {
    try {
      switch (toolCall.name) {
        case 'read_file':
          return await _readFile(toolCall);
        case 'write_file':
          return await _writeFile(toolCall);
        case 'edit_file':
          return await _editFile(toolCall);
        case 'create_file':
          return await _createFile(toolCall);
        case 'delete_file':
          return await _deleteFile(toolCall);
        case 'run_command':
          return await _runCommand(toolCall);
        case 'search_code':
          return await _searchCode(toolCall);
        case 'semantic_search':
          return await _semanticSearch(toolCall);
        case 'list_directory':
          return await _listDirectory(toolCall);
        case 'search_web':
          return await _searchWeb(toolCall);
        case 'fetch_url':
          return await _fetchUrl(toolCall);
        case 'git_status':
          return await _gitStatus(toolCall);
        case 'git_diff':
          return await _gitDiff(toolCall);
        case 'git_commit':
          return await _gitCommit(toolCall);
        case 'git_log':
          return await _gitLog(toolCall);
        case 'apply_diff':
          return await _applyDiff(toolCall);
        default:
          return AIToolResult(
            toolCallId: toolCall.id,
            content: 'Unknown tool: ${toolCall.name}',
            isError: true,
          );
      }
    } catch (e) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'Error executing ${toolCall.name}: $e',
        isError: true,
      );
    }
  }

  String _resolvePath(String relativePath) {
    if (p.isAbsolute(relativePath)) return relativePath;
    return p.join(workspacePath, relativePath);
  }

  Future<AIToolResult> _readFile(AIToolCall toolCall) async {
    final path = _resolvePath(toolCall.arguments['path'] as String);
    final file = File(path);
    if (!await file.exists()) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'File not found: ${toolCall.arguments['path']}',
        isError: true,
      );
    }
    final content = await file.readAsString();
    final lines = content.split('\n');
    if (lines.length > 500) {
      final truncated = lines.take(500).join('\n');
      return AIToolResult(
        toolCallId: toolCall.id,
        content: '$truncated\n\n... (${lines.length - 500} more lines)',
      );
    }
    return AIToolResult(toolCallId: toolCall.id, content: content);
  }

  Future<AIToolResult> _writeFile(AIToolCall toolCall) async {
    final path = _resolvePath(toolCall.arguments['path'] as String);
    final content = toolCall.arguments['content'] as String;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File written successfully: ${toolCall.arguments['path']}',
    );
  }

  Future<AIToolResult> _editFile(AIToolCall toolCall) async {
    final path = _resolvePath(toolCall.arguments['path'] as String);
    final oldString = toolCall.arguments['old_string'] as String;
    final newString = toolCall.arguments['new_string'] as String;
    final file = File(path);
    if (!await file.exists()) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'File not found: ${toolCall.arguments['path']}',
        isError: true,
      );
    }
    var content = await file.readAsString();
    if (!content.contains(oldString)) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'old_string not found in file. Make sure it matches exactly.',
        isError: true,
      );
    }
    content = content.replaceFirst(oldString, newString);
    await file.writeAsString(content);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File edited successfully: ${toolCall.arguments['path']}',
    );
  }

  Future<AIToolResult> _createFile(AIToolCall toolCall) async {
    final path = _resolvePath(toolCall.arguments['path'] as String);
    final content = toolCall.arguments['content'] as String;
    final file = File(path);
    if (await file.exists()) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'File already exists: ${toolCall.arguments['path']}. Use edit_file to modify.',
        isError: true,
      );
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File created successfully: ${toolCall.arguments['path']}',
    );
  }

  Future<AIToolResult> _deleteFile(AIToolCall toolCall) async {
    final path = _resolvePath(toolCall.arguments['path'] as String);
    final file = File(path);
    if (!await file.exists()) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'File not found: ${toolCall.arguments['path']}',
        isError: true,
      );
    }
    await file.delete();
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'File deleted: ${toolCall.arguments['path']}',
    );
  }

  Future<AIToolResult> _runCommand(AIToolCall toolCall) async {
    final command = toolCall.arguments['command'] as String;
    final workingDir = toolCall.arguments['working_directory'] as String?;
    final cwd = workingDir != null ? _resolvePath(workingDir) : workspacePath;
    
    final runtimeService = ref.read(runtimeServiceProvider);
    final output = await runtimeService.runCommand(command, workingDirectory: cwd);
    
    return AIToolResult(
      toolCallId: toolCall.id,
      content: output,
      isError: output.toLowerCase().contains('error'),
    );
  }

  Future<AIToolResult> _searchCode(AIToolCall toolCall) async {
    final query = toolCall.arguments['query'] as String;
    final filePattern = toolCall.arguments['file_pattern'] as String?;
    
    final results = <String>[];
    final dir = Directory(workspacePath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final filePath = entity.path;
      if (filePattern != null && !filePath.endsWith(filePattern.replaceAll('*', ''))) {
        continue;
      }
      if (filePath.contains('.git') || filePath.contains('node_modules')) continue;
      
      try {
        final content = await entity.readAsString();
        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains(query)) {
            final relativePath = p.relative(filePath, from: workspacePath);
            results.add('$relativePath:${i + 1}: ${lines[i].trim()}');
            if (results.length >= 50) break;
          }
        }
        if (results.length >= 50) break;
      } catch (_) {}
    }
    
    if (results.isEmpty) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'No matches found for "$query"',
      );
    }
    
    return AIToolResult(
      toolCallId: toolCall.id,
      content: 'Found ${results.length} matches:\n${results.join('\n')}',
    );
  }

  Future<AIToolResult> _semanticSearch(AIToolCall toolCall) async {
    final query = toolCall.arguments['query'] as String;
    final symbolIndexer = ref.read(symbolIndexerProvider.notifier);
    final results = await symbolIndexer.semanticSearch(query, limit: 20);

    if (results.isEmpty) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'No semantic matches found for "$query"',
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('Semantic search results for: $query');
    buffer.writeln('');

    for (final result in results) {
      final relPath = p.isAbsolute(result.path)
          ? p.relative(result.path, from: workspacePath)
          : result.path;
      buffer.writeln('[${result.type.toUpperCase()}] ${result.title}');
      buffer.writeln('  Path: $relPath:${result.lineNumber}');
      buffer.writeln('  ${result.subtitle}');
      buffer.writeln('');
    }

    return AIToolResult(
      toolCallId: toolCall.id,
      content: buffer.toString().trim(),
    );
  }

  Future<AIToolResult> _listDirectory(AIToolCall toolCall) async {
    final pathArg = toolCall.arguments['path'] as String;
    final dirPath = _resolvePath(pathArg);
    final dir = Directory(dirPath);
    
    if (!await dir.exists()) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'Directory not found: $pathArg',
        isError: true,
      );
    }
    
    final entries = <String>[];
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final isDir = entity is Directory;
      entries.add('${isDir ? "[DIR]" : "     "} $name');
    }
    
    entries.sort();
    return AIToolResult(
      toolCallId: toolCall.id,
      content: entries.isEmpty ? 'Empty directory' : entries.join('\n'),
    );
  }

  Future<AIToolResult> _searchWeb(AIToolCall toolCall) async {
    final query = toolCall.arguments['query'] as String;
    try {
      final response = await _dio.get(
        'https://html.duckduckgo.com/html/',
        queryParameters: {'q': query},
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; QuantumIDE/1.0)',
          },
        ),
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
        final snippet = i < snippets.length 
            ? (snippets.elementAt(i).group(1)?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '')
            : '';
        results.add('${i + 1}. $title\n   $url\n   $snippet');
        i++;
      }
      
      return AIToolResult(
        toolCallId: toolCall.id,
        content: results.isEmpty ? 'No results found' : results.join('\n\n'),
      );
    } catch (e) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'Search failed: $e',
        isError: true,
      );
    }
  }

  Future<AIToolResult> _fetchUrl(AIToolCall toolCall) async {
    final url = toolCall.arguments['url'] as String;
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; QuantumIDE/1.0)',
          },
          responseType: ResponseType.plain,
        ),
      );
      
      var content = response.data as String;
      
      content = content.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '');
      content = content.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '');
      content = content.replaceAll(RegExp(r'<[^>]*>'), ' ');
      content = content.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      if (content.length > 5000) {
        content = '${content.substring(0, 5000)}\n\n... (truncated)';
      }
      
      return AIToolResult(toolCallId: toolCall.id, content: content);
    } catch (e) {
      return AIToolResult(
        toolCallId: toolCall.id,
        content: 'Failed to fetch URL: $e',
        isError: true,
      );
    }
  }

  Future<AIToolResult> _gitStatus(AIToolCall toolCall) async {
    try {
      final result = await Process.run('git', ['status', '--porcelain'], workingDirectory: workspacePath);
      final output = result.stdout.toString().trim();
      return AIToolResult(
        toolCallId: toolCall.id,
        content: output.isEmpty ? 'Working tree clean' : output,
      );
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
      return AIToolResult(
        toolCallId: toolCall.id,
        content: output.isEmpty ? 'No changes' : output.length > 5000 ? '${output.substring(0, 5000)}\n... (truncated)' : output,
      );
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git diff error: $e', isError: true);
    }
  }

  Future<AIToolResult> _gitCommit(AIToolCall toolCall) async {
    try {
      final message = toolCall.arguments['message'] as String;
      await Process.run('git', ['add', '-A'], workingDirectory: workspacePath);
      final result = await Process.run('git', ['commit', '-m', message], workingDirectory: workspacePath);
      final output = '${result.stdout}\n${result.stderr}'.trim();
      return AIToolResult(toolCallId: toolCall.id, content: output);
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git commit error: $e', isError: true);
    }
  }

  Future<AIToolResult> _gitLog(AIToolCall toolCall) async {
    try {
      final count = toolCall.arguments['count'] as int? ?? 10;
      final result = await Process.run(
        'git', ['log', '--oneline', '-n', count.toString()],
        workingDirectory: workspacePath,
      );
      return AIToolResult(toolCallId: toolCall.id, content: result.stdout.toString().trim());
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Git log error: $e', isError: true);
    }
  }

  Future<AIToolResult> _applyDiff(AIToolCall toolCall) async {
    try {
      final filePath = _resolvePath(toolCall.arguments['file_path'] as String);
      final diff = toolCall.arguments['diff'] as String;
      final file = File(filePath);
      if (!await file.exists()) {
        return AIToolResult(toolCallId: toolCall.id, content: 'File not found: $filePath', isError: true);
      }
      final patchProcess = await Process.start('patch', [filePath], workingDirectory: workspacePath);
      patchProcess.stdin.write(diff);
      await patchProcess.stdin.close();
      final exitCode = await patchProcess.exitCode;
      if (exitCode == 0) {
        return AIToolResult(toolCallId: toolCall.id, content: 'Patch applied successfully');
      }
      final stderr = await patchProcess.stderr.transform(const SystemEncoding().decoder).join();
      return AIToolResult(toolCallId: toolCall.id, content: 'Patch failed: $stderr', isError: true);
    } catch (e) {
      return AIToolResult(toolCallId: toolCall.id, content: 'Apply diff error: $e', isError: true);
    }
  }
}
