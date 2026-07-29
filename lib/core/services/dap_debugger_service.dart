import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DapDebuggerState { disconnected, connecting, connected, paused, running, stopped, error }

enum StepType { over, into, out, continue_ }

class DapDebuggerBreakpoint {
  final String filePath;
  final int line;
  final int? column;
  final bool verified;
  final int? id;

  const DapDebuggerBreakpoint({
    required this.filePath,
    required this.line,
    this.column,
    this.verified = false,
    this.id,
  });

  DapDebuggerBreakpoint copyWith({bool? verified, int? id}) {
    return DapDebuggerBreakpoint(
      filePath: filePath,
      line: line,
      column: column,
      verified: verified ?? this.verified,
      id: id ?? this.id,
    );
  }
}

class DapDebuggerStackFrame {
  final int id;
  final String name;
  final String source;
  final int line;
  final int column;
  final String? moduleId;

  const DapDebuggerStackFrame({
    required this.id,
    required this.name,
    required this.source,
    required this.line,
    required this.column,
    this.moduleId,
  });
}

class DapDebuggerVariable {
  final int? variablesReference;
  final String name;
  final String value;
  final String type;
  final List<DapDebuggerVariable>? children;

  const DapDebuggerVariable({
    this.variablesReference,
    required this.name,
    required this.value,
    required this.type,
    this.children,
  });
}

class DapDebuggerException {
  final String description;
  final int? code;
  final String? details;

  const DapDebuggerException({required this.description, this.code, this.details});
}

class DapDebuggerEvent {
  final String type;
  final Map<String, dynamic> body;

  const DapDebuggerEvent({required this.type, required this.body});
}

class DapDebuggerService {
  WebSocket? _socket;
  int _msgId = 1;
  final Map<int, Completer<dynamic>> _pendingRequests = {};

  DapDebuggerState _state = DapDebuggerState.disconnected;
  final _stateController = StreamController<DapDebuggerState>.broadcast();
  final _eventsController = StreamController<DapDebuggerEvent>.broadcast();
  final _outputController = StreamController<String>.broadcast();

  final List<DapDebuggerBreakpoint> _breakpoints = [];
  final _breakpointsController = StreamController<List<DapDebuggerBreakpoint>>.broadcast();

  List<DapDebuggerStackFrame> _stackFrames = [];
  final _stackFramesController = StreamController<List<DapDebuggerStackFrame>>.broadcast();

  List<DapDebuggerVariable> _variables = [];
  final _variablesController = StreamController<List<DapDebuggerVariable>>.broadcast();

  DapDebuggerException? _lastException;

  DapDebuggerState get currentState => _state;
  Stream<DapDebuggerState> get stateStream => _stateController.stream;
  Stream<DapDebuggerEvent> get eventsStream => _eventsController.stream;
  Stream<String> get outputStream => _outputController.stream;
  List<DapDebuggerBreakpoint> get breakpoints => List.unmodifiable(_breakpoints);
  Stream<List<DapDebuggerBreakpoint>> get breakpointsStream => _breakpointsController.stream;
  List<DapDebuggerStackFrame> get stackFrames => List.unmodifiable(_stackFrames);
  Stream<List<DapDebuggerStackFrame>> get stackFramesStream => _stackFramesController.stream;
  List<DapDebuggerVariable> get variables => List.unmodifiable(_variables);
  Stream<List<DapDebuggerVariable>> get variablesStream => _variablesController.stream;
  DapDebuggerException? get lastException => _lastException;

  void _setState(DapDebuggerState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> connect(String vmServiceUri) async {
    if (_state == DapDebuggerState.connecting || _state == DapDebuggerState.connected) {
      await disconnect();
    }
    _setState(DapDebuggerState.connecting);
    try {
      _socket = await WebSocket.connect(vmServiceUri);
      _socket!.listen(
        _onMessage,
        onError: (error) {
          _outputController.add('WebSocket error: $error');
          _setState(DapDebuggerState.error);
        },
        onDone: () {
          _setState(DapDebuggerState.disconnected);
        },
      );
      _setState(DapDebuggerState.connected);
      _outputController.add('Connected to Dart VM at $vmServiceUri');
    } catch (e) {
      _setState(DapDebuggerState.error);
      _outputController.add('Failed to connect: $e');
    }
  }

  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    _pendingRequests.clear();
    _setState(DapDebuggerState.disconnected);
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = msg['id'] as int?;
      if (id != null && _pendingRequests.containsKey(id)) {
        _pendingRequests[id]!.complete(msg);
        _pendingRequests.remove(id);
      }
      final method = msg['method'] as String?;
      if (method != null) {
        _handleEvent(method, msg['params'] as Map<String, dynamic>? ?? {});
      }
    } catch (e) {
      _outputController.add('Error parsing message: $e');
    }
  }

  void _handleEvent(String method, Map<String, dynamic> params) {
    _eventsController.add(DapDebuggerEvent(type: method, body: params));
    switch (method) {
      case 'stopped':
        _setState(DapDebuggerState.paused);
        _fetchStackFrames();
        break;
      case 'continued':
        _setState(DapDebuggerState.running);
        break;
      case 'terminated':
        _setState(DapDebuggerState.stopped);
        break;
    }
  }

  Future<Map<String, dynamic>> _sendRequest(String method, Map<String, dynamic> params) async {
    final id = _msgId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;
    _socket?.add(jsonEncode({'id': id, 'method': method, 'arguments': params}));
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pendingRequests.remove(id);
        return {'error': 'Request timed out'};
      },
    );
  }

  Future<void> setBreakpoint(String filePath, int line, {int? column}) async {
    final bp = DapDebuggerBreakpoint(filePath: filePath, line: line, column: column);
    _breakpoints.add(bp);
    _breakpointsController.add(List.unmodifiable(_breakpoints));
    await _sendRequest('setBreakpoints', {
      'source': {'path': filePath},
      'breakpoints': [{'line': line, if (column != null) 'column': column}],
    });
  }

  Future<void> removeBreakpoint(String filePath, int line) async {
    _breakpoints.removeWhere((bp) => bp.filePath == filePath && bp.line == line);
    _breakpointsController.add(List.unmodifiable(_breakpoints));
    final remaining = _breakpoints.where((bp) => bp.filePath == filePath).toList();
    await _sendRequest('setBreakpoints', {
      'source': {'path': filePath},
      'breakpoints': remaining.map((bp) => {'line': bp.line, if (bp.column != null) 'column': bp.column}).toList(),
    });
  }

  void toggleBreakpoint(String filePath, int line) {
    final existing = _breakpoints.indexWhere((bp) => bp.filePath == filePath && bp.line == line);
    if (existing >= 0) {
      removeBreakpoint(filePath, line);
    } else {
      setBreakpoint(filePath, line);
    }
  }

  Future<void> step(StepType type) async {
    final method = switch (type) {
      StepType.over => 'next',
      StepType.into => 'stepIn',
      StepType.out => 'stepOut',
      StepType.continue_ => 'continue',
    };
    await _sendRequest(method, {'threadId': 1});
    if (type == StepType.continue_) _setState(DapDebuggerState.running);
  }

  Future<void> pause() async {
    await _sendRequest('pause', {'threadId': 1});
    _setState(DapDebuggerState.paused);
  }

  Future<void> resume() async {
    await step(StepType.continue_);
  }

  Future<void> restart() async {
    await _sendRequest('restart', {});
  }

  Future<void> terminate() async {
    await _sendRequest('terminate', {'restart': false});
    _setState(DapDebuggerState.stopped);
  }

  Future<void> _fetchStackFrames() async {
    final result = await _sendRequest('stackTrace', {'threadId': 1, 'startFrame': 0, 'levels': 50});
    final frames = (result['body']?['stackFrames'] as List<dynamic>?)
            ?.map((f) => DapDebuggerStackFrame(
                  id: f['id'] ?? 0,
                  name: f['name'] ?? '',
                  source: f['source']?['path'] ?? '',
                  line: f['line'] ?? 0,
                  column: f['column'] ?? 0,
                  moduleId: f['source']?['moduleId'],
                ))
            .toList() ??
        [];
    _stackFrames = frames;
    _stackFramesController.add(List.unmodifiable(_stackFrames));
  }

  Future<void> fetchVariables(int frameId) async {
    final result = await _sendRequest('scopes', {'frameId': frameId});
    final scopes = (result['body']?['scopes'] as List<dynamic>?) ?? [];
    final allVars = <DapDebuggerVariable>[];
    for (final scope in scopes) {
      final ref = scope['variablesReference'] as int? ?? 0;
      if (ref > 0) {
        final varsResult = await _sendRequest('variables', {'variablesReference': ref});
        final vars = (varsResult['body']?['variables'] as List<dynamic>?)
                ?.map((v) => DapDebuggerVariable(
                      variablesReference: v['variablesReference'] as int?,
                      name: v['name'] ?? '',
                      value: v['value'] ?? '',
                      type: v['type'] ?? 'unknown',
                    ))
                .toList() ??
            [];
        allVars.addAll(vars);
      }
    }
    _variables = allVars;
    _variablesController.add(List.unmodifiable(_variables));
  }

  Future<void> selectFrame(int frameId) async {
    await fetchVariables(frameId);
  }

  Future<String> evaluateExpression(String expression, {int? frameId}) async {
    final params = <String, dynamic>{
      'expression': expression,
      'context': 'watch',
    };
    if (frameId != null) params['frameId'] = frameId;
    final result = await _sendRequest('evaluate', params);
    final resultVal = result['body']?['result']?.toString();
    final error = result['body']?['error'];
    if (error != null) {
      return 'Error: $error';
    }
    return resultVal ?? 'null';
  }

  Future<String> evaluateInFrame(String expression, int frameId) async {
    return evaluateExpression(expression, frameId: frameId);
  }

  List<DapDebuggerBreakpoint> getBreakpointsForFile(String filePath) {
    return _breakpoints.where((bp) => bp.filePath == filePath).toList();
  }

  void clearAllBreakpoints() {
    _breakpoints.clear();
    _breakpointsController.add(List.unmodifiable(_breakpoints));
  }

  void dispose() {
    _socket?.close();
    _stateController.close();
    _eventsController.close();
    _outputController.close();
    _breakpointsController.close();
    _stackFramesController.close();
    _variablesController.close();
  }
}

final dapDebuggerServiceProvider = Provider<DapDebuggerService>((ref) {
  final service = DapDebuggerService();
  ref.onDispose(() => service.dispose());
  return service;
});
