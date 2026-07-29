import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:path/path.dart' as p;

final dapServiceProvider = Provider<DapService>((ref) {
  final runtimeService = ref.watch(runtimeServiceProvider);
  final dap = DapService(
    ref,
    runtimeService.appDirectory,
    runtimeService.prootCommand,
  );
  ref.onDispose(() => dap.stop());
  return dap;
});

enum DapState { idle, launching, running, stopped, error }

class DapBreakpoint {
  final String fileUri;
  final int line;
  final int? column;
  final bool verified;
  final int? id;

  const DapBreakpoint({
    required this.fileUri,
    required this.line,
    this.column,
    this.verified = false,
    this.id,
  });

  DapBreakpoint copyWith({bool? verified, int? id}) {
    return DapBreakpoint(
      fileUri: fileUri,
      line: line,
      column: column,
      verified: verified ?? this.verified,
      id: id ?? this.id,
    );
  }
}

class DapStackFrame {
  final int id;
  final String name;
  final String source;
  final int line;
  final int column;

  const DapStackFrame({
    required this.id,
    required this.name,
    required this.source,
    required this.line,
    required this.column,
  });
}

class DapVariable {
  final String name;
  final String value;
  final String type;

  const DapVariable({
    required this.name,
    required this.value,
    required this.type,
  });
}

class DapService {
  final Ref ref;
  final String appDirectory;
  final String prootCommand;
  Process? _process;
  final Map<String, String> _stdoutBuffers = {};
  int _id = 1;
  final Map<int, Completer> _pendingRequests = {};

  DapState _state = DapState.idle;
  final _stateController = StreamController<DapState>.broadcast();
  final _eventsController = StreamController<DapEvent>.broadcast();
  final _outputController = StreamController<String>.broadcast();

  final List<DapBreakpoint> _breakpoints = [];
  final _breakpointsController = StreamController<List<DapBreakpoint>>.broadcast();

  Stream<DapState> get stateStream => _stateController.stream;
  DapState get currentState => _state;
  Stream<DapEvent> get eventsStream => _eventsController.stream;
  Stream<String> get outputStream => _outputController.stream;
  Stream<List<DapBreakpoint>> get breakpointsStream => _breakpointsController.stream;
  List<DapBreakpoint> get breakpoints => List.unmodifiable(_breakpoints);

  DapService(this.ref, this.appDirectory, this.prootCommand);

  void _setState(DapState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> start({
    required String program,
    List<String> args = const [],
    String? cwd,
    Map<String, String>? env,
  }) async {
    if (_state == DapState.running || _state == DapState.launching) {
      await stop();
    }

    _setState(DapState.launching);

    try {
      final workspacePath = ref.read(workspaceProvider).currentPath ?? appDirectory;
      final guestWorkspacePath = PathMapper.mapToGuest(workspacePath, appDirectory);

      final debugArgs = [
        'debug',
        '--machine',
        '--start-paused',
        p.join(guestWorkspacePath, program),
        ...args,
      ];

      final process = await Process.start(
        'dart',
        debugArgs,
        workingDirectory: guestWorkspacePath,
        environment: env,
      );

      _process = process;
      _setState(DapState.running);

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _handleOutput('stdout', line));
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _handleOutput('stderr', line));

      process.exitCode.then((exitCode) {
        _setState(DapState.stopped);
        _eventsController.add(DapEvent(
          type: 'terminated',
          body: {'exitCode': exitCode},
        ));
      });

      _eventsController.add(const DapEvent(type: 'started', body: {}));
    } catch (e) {
      _setState(DapState.error);
      _outputController.add('Error starting debugger: $e');
    }
  }

  Future<void> stop() async {
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    _setState(DapState.stopped);
    _pendingRequests.clear();
  }

  Future<void> continue_() async {
    await _sendRequest('continue', {'threadId': 1});
  }

  Future<void> stepOver() async {
    await _sendRequest('next', {'threadId': 1});
  }

  Future<void> stepIn() async {
    await _sendRequest('stepIn', {'threadId': 1});
  }

  Future<void> stepOut() async {
    await _sendRequest('stepOut', {'threadId': 1});
  }

  Future<void> pause() async {
    await _sendRequest('pause', {'threadId': 1});
  }

  Future<void> restart() async {
    await _sendRequest('restart', {});
  }

  Future<void> setBreakpoint(String fileUri, int line, {int? column}) async {
    final bpMap = <String, dynamic>{'line': line};
    if (column != null) bpMap['column'] = column;
    final result = await _sendRequest('setBreakpoints', {
      'source': {'path': fileUri},
      'breakpoints': [bpMap],
    });

    if (result != null && result is Map) {
      final bps = result['breakpoints'] as List?;
      if (bps != null && bps.isNotEmpty) {
        final bp = bps[0] as Map;
        final id = bp['id'] as int?;
        final verified = bp['verified'] as bool? ?? false;

        final existingIndex = _breakpoints.indexWhere(
          (b) => b.fileUri == fileUri && b.line == line,
        );

        if (existingIndex >= 0) {
          _breakpoints[existingIndex] = _breakpoints[existingIndex].copyWith(
            verified: verified,
            id: id,
          );
        } else {
          _breakpoints.add(DapBreakpoint(
            fileUri: fileUri,
            line: line,
            column: column,
            verified: verified,
            id: id,
          ));
        }
        _breakpointsController.add(List.unmodifiable(_breakpoints));
      }
    }
  }

  Future<void> removeBreakpoint(String fileUri, int line) async {
    _breakpoints.removeWhere((b) => b.fileUri == fileUri && b.line == line);
    _breakpointsController.add(List.unmodifiable(_breakpoints));

    await _sendRequest('setBreakpoints', {
      'source': {'path': fileUri},
      'breakpoints': [],
    });
  }

  void toggleBreakpoint(String fileUri, int line) {
    final exists = _breakpoints.any((b) => b.fileUri == fileUri && b.line == line);
    if (exists) {
      removeBreakpoint(fileUri, line);
    } else {
      setBreakpoint(fileUri, line);
    }
  }

  Future<List<DapStackFrame>> getStackTrace() async {
    final result = await _sendRequest('stackTrace', {'threadId': 1});
    if (result == null || result is! Map) return [];

    final frames = result['stackFrames'] as List? ?? [];
    return frames.map((f) {
      final source = f['source'] as Map? ?? {};
      return DapStackFrame(
        id: f['id'] as int? ?? 0,
        name: f['name'] as String? ?? '',
        source: source['path'] as String? ?? '',
        line: (f['line'] as int?) ?? 0,
        column: (f['column'] as int?) ?? 0,
      );
    }).toList();
  }

  Future<List<DapVariable>> getVariables(int frameId) async {
    final scopesResult = await _sendRequest('scopes', {'frameId': frameId});
    if (scopesResult == null || scopesResult is! Map) return [];

    final scopes = scopesResult['scopes'] as List? ?? [];
    final allVars = <DapVariable>[];

    for (final scope in scopes) {
      final variablesReference = scope['variablesReference'] as int? ?? 0;
      if (variablesReference == 0) continue;

      final varsResult = await _sendRequest('variables', {
        'variablesReference': variablesReference,
      });

      if (varsResult != null && varsResult is Map) {
        final variables = varsResult['variables'] as List? ?? [];
        for (final v in variables) {
          allVars.add(DapVariable(
            name: v['name'] as String? ?? '',
            value: v['value'] as String? ?? '',
            type: v['type'] as String? ?? 'unknown',
          ));
        }
      }
    }

    return allVars;
  }

  Future<dynamic> _sendRequest(String method, Map<String, dynamic> params) {
    final id = _id++;
    final completer = Completer();
    _pendingRequests[id] = completer;

    final message = jsonEncode({
      'seq': id,
      'type': 'request',
      'command': method,
      'arguments': params,
    });

    try {
      _process?.stdin.write('Content-Length: ${utf8.encode(message).length}\r\n\r\n$message');
    } catch (e) {
      debugPrint('DAP: Failed to write request: $e');
      completer.complete(null);
    }

    return completer.future;
  }

  void _handleOutput(String stream, String line) {
    if (line.startsWith('Content-Length:')) {
      final lengthStr = line.substring(15).trim();
      final contentLength = int.tryParse(lengthStr);
      if (contentLength != null) {
        _stdoutBuffers[stream] = '';
        return;
      }
    }

    final buffer = _stdoutBuffers[stream] ?? '';
    _stdoutBuffers[stream] = buffer + line;

    if (line.isEmpty) {
      final content = _stdoutBuffers[stream] ?? '';
      _stdoutBuffers[stream] = '';
      _parseMessage(stream, content);
    }
  }

  void _parseMessage(String stream, String content) {
    try {
      final json = jsonDecode(content);
      if (json is Map<String, dynamic>) {
        final type = json['type'] as String?;

        if (type == 'response') {
          final seq = json['seq'] as int?;
          if (seq != null) {
            final completer = _pendingRequests.remove(seq);
            if (completer != null && !completer.isCompleted) {
              completer.complete(json['body']);
            }
          }
        } else if (type == 'event') {
          final event = json['event'] as String?;
          final body = json['body'] as Map<String, dynamic>? ?? {};
          _eventsController.add(DapEvent(type: event ?? '', body: body));

          if (event == 'output') {
            final output = body['output'] as String? ?? '';
            _outputController.add(output);
          }
        }
      }
    } catch (e) {
      debugPrint('DAP: Failed to parse message: $e');
    }
  }

  void dispose() {
    stop();
    _stateController.close();
    _eventsController.close();
    _outputController.close();
    _breakpointsController.close();
  }
}

class DapEvent {
  final String type;
  final Map<String, dynamic> body;

  const DapEvent({required this.type, required this.body});
}
