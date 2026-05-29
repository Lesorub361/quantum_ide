import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import '../models/code_diagnostic.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';

final lspServiceProvider = Provider<LspService>((ref) {
  final runtimeService = ref.watch(runtimeServiceProvider);
  final lsp = LspService(
    ref,
    p.join(runtimeService.appDirectory, 'projects'),
    runtimeService.prootCommand,
    runtimeService.appDirectory,
  );
  // Start the server
  lsp.start();
  
  ref.onDispose(() {
    lsp.stop();
  });
  
  return lsp;
});

class FileDiagnostics {
  final String path;
  final List<CodeDiagnostic> diagnostics;
  FileDiagnostics(this.path, this.diagnostics);
}

class LspService {
  final Ref ref;
  final String fallbackProjectPath;
  final String initHostPath;
  final String filesDirPath;
  final Map<String, Process?> _processes = {};
  final Map<String, Future<void>?> _startingServers = {};
  final Map<String, String> _runningProjectPaths = {};
  final Map<String, String> _stdoutBuffers = {};
  final Map<String, bool> _binaryAvailabilityCache = {};
  int _id = 1;
  final Map<int, Completer> _pendingRequests = {};
  final StreamController<FileDiagnostics> _diagnosticController = StreamController.broadcast();

  final Map<String, int> _serverVersions = {};

  LspService(this.ref, this.fallbackProjectPath, this.initHostPath, this.filesDirPath);

  Stream<FileDiagnostics> get diagnosticsStream => _diagnosticController.stream;

  String get activeProjectPath => ref.read(workspaceProvider).currentPath ?? fallbackProjectPath;

  Future<bool> _isBinaryAvailable(String command) async {
    if (_binaryAvailabilityCache.containsKey(command)) {
      return _binaryAvailabilityCache[command]!;
    }

    // Check inside guest directories on host filesystem
    final searchDirs = [
      p.join(filesDirPath, 'rootfs', 'ubuntu', 'usr', 'bin'),
      p.join(filesDirPath, 'rootfs', 'ubuntu', 'usr', 'local', 'bin'),
      p.join(filesDirPath, 'rootfs', 'ubuntu', 'bin'),
      p.join(filesDirPath, 'rootfs', 'ubuntu', 'sbin'),
      p.join(filesDirPath, 'rootfs', 'ubuntu', 'root', 'flutter', 'bin'),
      p.join(filesDirPath, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'platform-tools'),
    ];

    for (final dir in searchDirs) {
      if (await File(p.join(dir, command)).exists()) {
        _binaryAvailabilityCache[command] = true;
        return true;
      }
    }

    // Also check if it's available on host PATH (for dart/flutter if they are there)
    try {
      final result = await Process.run('which', [command]);
      if (result.exitCode == 0) {
        _binaryAvailabilityCache[command] = true;
        return true;
      }
    } catch (_) {}

    _binaryAvailabilityCache[command] = false;
    return false;
  }

  String _getServerKey(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (ext == 'dart') return 'dart';
    if (ext == 'js' || ext == 'ts' || ext == 'jsx' || ext == 'tsx') return 'ts';
    if (ext == 'html') return 'html';
    if (ext == 'css') return 'css';
    if (ext == 'yaml' || ext == 'yml') return 'yaml';
    if (ext == 'json') return 'json';
    if (ext == 'md' || ext == 'markdown') return 'markdown';
    if (ext == 'java') return 'java';
    if (ext == 'kt' || ext == 'kotlin') return 'kotlin';
    if (ext == 'vue') return 'vue';
    if (ext == 'php') return 'php';
    if (ext == 'py') return 'python';
    return 'dart'; // fallback
  }

  Future<void> start() async {
    // Start dart server by default to maintain backward compatibility
    await _ensureServerStarted('dart');
  }

  Future<void> _ensureServerStarted(String key) async {
    // If server is already starting, wait for it
    if (_startingServers.containsKey(key)) {
      await _startingServers[key];
      return;
    }

    final currentActivePath = activeProjectPath;
    if (_processes.containsKey(key) && _processes[key] != null) {
      if (_runningProjectPaths[key] == currentActivePath) {
        return;
      }
      debugPrint('LSP: Workspace changed from ${_runningProjectPaths[key]} to $currentActivePath. Restarting $key server...');
      _processes[key]?.kill();
      _processes[key] = null;
    }

    final completer = Completer<void>();
    _startingServers[key] = completer.future;

    try {
      _runningProjectPaths[key] = currentActivePath;
      final guestActivePath = PathMapper.mapToGuest(currentActivePath, filesDirPath);

      final List<String> commandArgs;
      if (key == 'ts') {
        commandArgs = ['typescript-language-server', '--stdio'];
      } else if (key == 'html') {
        commandArgs = ['vscode-html-language-server', '--stdio'];
      } else if (key == 'css') {
        commandArgs = ['vscode-css-language-server', '--stdio'];
      } else if (key == 'yaml') {
        commandArgs = ['yaml-language-server', '--stdio'];
      } else if (key == 'json') {
        commandArgs = ['vscode-json-language-server', '--stdio'];
      } else if (key == 'markdown') {
        commandArgs = ['marksman', 'server'];
      } else if (key == 'java') {
        commandArgs = ['jdtls'];
      } else if (key == 'kotlin') {
        commandArgs = ['kotlin-language-server'];
      } else if (key == 'vue') {
        commandArgs = ['vue-language-server', '--stdio'];
      } else if (key == 'php') {
        commandArgs = ['intelephense', '--stdio'];
      } else if (key == 'python') {
        commandArgs = ['pyright-langserver', '--stdio'];
      } else {
        commandArgs = ['dart', 'language-server'];
      }

      if (!await _isBinaryAvailable(commandArgs[0])) {
        debugPrint('LSP [$key]: Binary ${commandArgs[0]} not found in rootfs. Skipping start.');
        completer.complete();
        _startingServers.remove(key);
        return;
      }

      Process process;
      if (initHostPath.isNotEmpty && File(initHostPath).existsSync()) {
        debugPrint('LSP: Starting $key server via init-host at $initHostPath for $guestActivePath');
        process = await Process.start('sh', [initHostPath, filesDirPath, guestActivePath, ...commandArgs]);
      } else {
        debugPrint('LSP: Starting direct $key server: ${commandArgs.join(' ')}');
        process = await Process.start(commandArgs[0], commandArgs.sublist(1));
      }

      _processes[key] = process;

      process.stdout.transform(utf8.decoder).listen((data) => _handleOutputForServer(key, data));
      process.stderr.transform(utf8.decoder).listen((error) {
        debugPrint('LSP [$key] Error: $error');
      });

      await _sendRequestForServer(key, 'initialize', {
        'processId': pid,
        'rootUri': Uri.file(guestActivePath).toString(),
        'capabilities': {},
      });

      _sendNotificationForServer(key, 'initialized', {});
      debugPrint('LSP [$key]: Started and initialized');
      completer.complete();
    } catch (e) {
      debugPrint('LSP [$key]: Failed to start: $e');
      completer.completeError(e);
    } finally {
      _startingServers.remove(key);
    }
  }

  void _handleOutputForServer(String key, String data) {
    _stdoutBuffers[key] = (_stdoutBuffers[key] ?? '') + data;
    _processBuffer(key);
  }

  void _processBuffer(String key) {
    var buffer = _stdoutBuffers[key] ?? '';
    if (buffer.isEmpty) return;

    while (true) {
      final headerEndIndex = buffer.indexOf('\r\n\r\n');
      if (headerEndIndex == -1) break;

      final header = buffer.substring(0, headerEndIndex);
      final contentLengthIndex = header.indexOf('Content-Length:');
      
      if (contentLengthIndex == -1) {
        // Skip junk
        buffer = buffer.substring(headerEndIndex + 4);
        continue;
      }

      final lengthStr = header.substring(contentLengthIndex + 15).trim().split('\r\n').first;
      final contentLength = int.tryParse(lengthStr);
      
      if (contentLength == null) {
        buffer = buffer.substring(headerEndIndex + 4);
        continue;
      }

      final contentStartIndex = headerEndIndex + 4;
      if (buffer.length < contentStartIndex + contentLength) break;

      final jsonContent = buffer.substring(contentStartIndex, contentStartIndex + contentLength);
      buffer = buffer.substring(contentStartIndex + contentLength);
      _stdoutBuffers[key] = buffer;

      // Offload JSON decoding to a microtask or compute if it was huge, 
      // but here microtask is usually enough for the event loop.
      try {
        final json = jsonDecode(jsonContent);
        if (json is Map<String, dynamic>) {
          _handleMessage(json);
        }
      } catch (e) {
        debugPrint('LSP [$key]: Failed to parse JSON-RPC content: $e');
      }
    }
    _stdoutBuffers[key] = buffer;
  }

  void _handleMessage(Map<String, dynamic> json) {
    if (json.containsKey('id')) {
      final id = json['id'] as int;
      final completer = _pendingRequests.remove(id);
      if (completer != null) {
        completer.complete(json['result']);
      }
    } else if (json.containsKey('method')) {
      final method = json['method'] as String;
      if (method == 'textDocument/publishDiagnostics') {
        _handleDiagnostics(json['params']);
      }
    }
  }

  void _handleDiagnostics(Map<String, dynamic> params) {
    final uriStr = params['uri'] as String;
    final guestUri = Uri.parse(uriStr);
    final guestPath = guestUri.toFilePath();
    
    // Map back to host path
    final hostPath = PathMapper.mapToHost(guestPath, filesDirPath, activeWorkspacePath: activeProjectPath);

    final diagnosticsJson = params['diagnostics'] as List;
    
    final diagnostics = diagnosticsJson.map((d) {
      final start = d['range']['start'];
      final end = d['range']['end'];
      final severity = d['severity'] as int;
      
      return CodeDiagnostic(
        range: CodeLineRange(
          index: start['line'] as int,
          start: start['character'] as int,
          end: end['character'] as int,
        ),
        message: d['message'] as String,
        severity: _mapSeverity(severity),
      );
    }).toList();

    _diagnosticController.add(FileDiagnostics(hostPath, diagnostics));
  }

  CodeDiagnosticSeverity _mapSeverity(int severity) {
    switch (severity) {
      case 1: return CodeDiagnosticSeverity.error;
      case 2: return CodeDiagnosticSeverity.warning;
      default: return CodeDiagnosticSeverity.hint;
    }
  }

  Future<dynamic> _sendRequestForServer(String key, String method, Map<String, dynamic> params) {
    final id = _id++;
    final completer = Completer();
    _pendingRequests[id] = completer;

    final message = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    final process = _processes[key];
    if (process != null) {
      process.stdin.write('Content-Length: ${message.length}\r\n\r\n$message');
    } else {
      completer.complete(null);
    }
    return completer.future;
  }

  void _sendNotificationForServer(String key, String method, Map<String, dynamic> params) {
    final message = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });

    final process = _processes[key];
    process?.stdin.write('Content-Length: ${message.length}\r\n\r\n$message');
  }

  String _getLanguageId(String key) {
    switch (key) {
      case 'ts': return 'typescript';
      case 'html': return 'html';
      case 'css': return 'css';
      case 'yaml': return 'yaml';
      case 'json': return 'json';
      case 'markdown': return 'markdown';
      case 'vue': return 'vue';
      case 'php': return 'php';
      case 'python': return 'python';
      case 'java': return 'java';
      case 'kotlin': return 'kotlin';
      default: return 'dart';
    }
  }

  Future<void> onFileOpened(String path, String content) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    _serverVersions[path] = 1;
    _sendNotificationForServer(key, 'textDocument/didOpen', {
      'textDocument': {
        'uri': Uri.file(guestPath).toString(),
        'languageId': _getLanguageId(key),
        'version': _serverVersions[path],
        'text': content,
      }
    });
  }

  Future<void> onFileChanged(String path, String content) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    _serverVersions[path] = (_serverVersions[path] ?? 1) + 1;
    _sendNotificationForServer(key, 'textDocument/didChange', {
      'textDocument': {
        'uri': Uri.file(guestPath).toString(),
        'version': _serverVersions[path],
      },
      'contentChanges': [
        {'text': content}
      ]
    });
  }

  Future<List<Location>> getDefinition(String path, int line, int column) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    final result = await _sendRequestForServer(key, 'textDocument/definition', {
      'textDocument': {'uri': Uri.file(guestPath).toString()},
      'position': {'line': line, 'character': column},
    });

    if (result == null) return [];
    
    List<Location> locations = [];
    if (result is List) {
      locations = result.map((l) => _parseLocation(l)).toList();
    } else {
      locations = [_parseLocation(result)];
    }

    return locations.map((loc) {
      final guestUri = Uri.parse(loc.uri);
      if (guestUri.scheme == 'file') {
        final hostPath = PathMapper.mapToHost(guestUri.toFilePath(), filesDirPath, activeWorkspacePath: activeProjectPath);
        return Location(
          uri: Uri.file(hostPath).toString(),
          range: loc.range,
        );
      }
      return loc;
    }).toList();
  }

  Future<List<CompletionItem>> getCompletions(String path, int line, int column) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    final result = await _sendRequestForServer(key, 'textDocument/completion', {
      'textDocument': {'uri': Uri.file(guestPath).toString()},
      'position': {'line': line, 'character': column},
    });

    if (result == null) return [];

    List<dynamic> items = [];
    if (result is List) {
      items = result;
    } else if (result is Map && result.containsKey('items')) {
      items = result['items'] as List;
    }

    return items.map((item) {
      final map = item as Map<String, dynamic>;
      String? documentation;
      if (map['documentation'] is String) {
        documentation = map['documentation'];
      } else if (map['documentation'] is Map) {
        documentation = (map['documentation'] as Map)['value'];
      }

      return CompletionItem(
        label: map['label'] as String,
        insertText: map['insertText'] as String?,
        kind: map['kind'] as int?,
        detail: map['detail'] as String?,
        documentation: documentation,
      );
    }).toList();
  }

  Future<Hover?> getHover(String path, int line, int column) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    final result = await _sendRequestForServer(key, 'textDocument/hover', {
      'textDocument': {'uri': Uri.file(guestPath).toString()},
      'position': {'line': line, 'character': column},
    });

    if (result == null || result is! Map) return null;

    final map = result as Map<String, dynamic>;
    String contents = '';
    
    final rawContents = map['contents'];
    if (rawContents is String) {
      contents = rawContents;
    } else if (rawContents is List) {
      contents = rawContents.map((c) {
        if (c is String) return c;
        if (c is Map && c.containsKey('value')) return c['value'];
        return '';
      }).join('\n');
    } else if (rawContents is Map && rawContents.containsKey('value')) {
      contents = rawContents['value'];
    }

    Range? range;
    if (map.containsKey('range')) {
      range = Range(
        start: Position(
          line: map['range']['start']['line'],
          character: map['range']['start']['character'],
        ),
        end: Position(
          line: map['range']['end']['line'],
          character: map['range']['end']['character'],
        ),
      );
    }

    return Hover(contents: contents, range: range);
  }

  Future<List<Location>> getReferences(String path, int line, int column) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    final result = await _sendRequestForServer(key, 'textDocument/references', {
      'textDocument': {'uri': Uri.file(guestPath).toString()},
      'position': {'line': line, 'character': column},
      'context': {'includeDeclaration': true},
    });

    if (result == null || result is! List) return [];

    return result.map((l) {
      final loc = _parseLocation(l as Map<String, dynamic>);
      final guestUri = Uri.parse(loc.uri);
      if (guestUri.scheme == 'file') {
        final hostPath = PathMapper.mapToHost(guestUri.toFilePath(), filesDirPath, activeWorkspacePath: activeProjectPath);
        return Location(
          uri: Uri.file(hostPath).toString(),
          range: loc.range,
        );
      }
      return loc;
    }).toList();
  }

  /// Apply workspace edits (used by rename and format operations)
  Future<void> applyWorkspaceEdit(Map<String, dynamic> workspaceEdit) async {
    final changes = workspaceEdit['changes'] as Map<String, dynamic>?;
    if (changes != null) {
      for (final entry in changes.entries) {
        final uriStr = entry.key;
        final guestUri = Uri.parse(uriStr);
        final guestPath = guestUri.toFilePath();
        final hostPath = PathMapper.mapToHost(guestPath, filesDirPath, activeWorkspacePath: activeProjectPath);
        
        final edits = entry.value as List;
        _applyTextEdits(hostPath, edits);
      }
    }

    final documentChanges = workspaceEdit['documentChanges'] as List?;
    if (documentChanges != null) {
      for (final change in documentChanges) {
        final changeMap = change as Map<String, dynamic>;
        if (changeMap.containsKey('textDocument')) {
          final textDocument = changeMap['textDocument'] as Map<String, dynamic>;
          final uri = textDocument['uri'] as String;
          final guestUri = Uri.parse(uri);
          final guestPath = guestUri.toFilePath();
          final hostPath = PathMapper.mapToHost(guestPath, filesDirPath, activeWorkspacePath: activeProjectPath);
          
          if (changeMap.containsKey('edits')) {
            final edits = changeMap['edits'] as List;
            _applyTextEdits(hostPath, edits);
          }
        }
      }
    }
  }

  void _applyTextEdits(String filePath, List<dynamic> edits) {
    // Notify editor to apply these edits
    final editor = ref.read(editorProvider.notifier);
    editor.applyLSPEdits(filePath, edits);
  }

  Future<void> rename(String path, int line, int column, String newName) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    final result = await _sendRequestForServer(key, 'textDocument/rename', {
      'textDocument': {'uri': Uri.file(guestPath).toString()},
      'position': {'line': line, 'character': column},
      'newName': newName,
    });

    if (result == null) return;
    await applyWorkspaceEdit(result as Map<String, dynamic>);
    debugPrint('LSP: Rename completed for $newName');
  }

  Future<List<TextEdit>> format(String path) async {
    final key = _getServerKey(path);
    await _ensureServerStarted(key);

    final guestPath = PathMapper.mapToGuest(path, filesDirPath);

    final result = await _sendRequestForServer(key, 'textDocument/formatting', {
      'textDocument': {'uri': Uri.file(guestPath).toString()},
      'options': {
        'tabSize': 2,
        'insertSpaces': true,
      },
    });

    if (result == null || result is! List) return [];
    
    final edits = result.map((edit) {
      final map = edit as Map<String, dynamic>;
      return TextEdit(
        range: Range(
          start: Position(
            line: map['range']['start']['line'] as int,
            character: map['range']['start']['character'] as int,
          ),
          end: Position(
            line: map['range']['end']['line'] as int,
            character: map['range']['end']['character'] as int,
          ),
        ),
        newText: map['newText'] as String,
      );
    }).toList();

    _applyTextEdits(path, edits.map((e) => {
      'range': {
        'start': {'line': e.range.start.line, 'character': e.range.start.character},
        'end': {'line': e.range.end.line, 'character': e.range.end.character},
      },
      'newText': e.newText,
    }).toList());
    
    debugPrint('LSP: Formatting applied ${edits.length} edits');
    return edits;
  }

  Location _parseLocation(Map<String, dynamic> json) {
    return Location(
      uri: json['uri'],
      range: Range(
        start: Position(
          line: json['range']['start']['line'],
          character: json['range']['start']['character'],
        ),
        end: Position(
          line: json['range']['end']['line'],
          character: json['range']['end']['character'],
        ),
      ),
    );
  }

  Future<List<CodeDiagnostic>> getDiagnostics(String path) async {
    return [];
  }

  void stop() {
    for (final process in _processes.values) {
      process?.kill();
    }
    _processes.clear();
    _startingServers.clear();
    _runningProjectPaths.clear();
    _stdoutBuffers.clear();
  }
}

class Position {
  final int line;
  final int character;
  const Position({required this.line, required this.character});
}

class Range {
  final Position start;
  final Position end;
  const Range({required this.start, required this.end});
}

class TextEdit {
  final Range range;
  final String newText;
  const TextEdit({required this.range, required this.newText});
}

class Location {
  final String uri;
  final Range range;
  const Location({required this.uri, required this.range});
}

class CompletionItem {
  final String label;
  final String? insertText;
  final int? kind;
  final String? detail;
  final String? documentation;

  CompletionItem({
    required this.label,
    this.insertText,
    this.kind,
    this.detail,
    this.documentation,
  });
}

class Hover {
  final String contents;
  final Range? range;
  Hover({required this.contents, this.range});
}

class TextDocumentIdentifier {
  final String uri;
  const TextDocumentIdentifier({required this.uri});
}
