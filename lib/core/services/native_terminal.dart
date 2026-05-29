import 'dart:async';
import 'package:flutter/services.dart';

class NativeTerminal {
  static const MethodChannel _channel = MethodChannel('com.example.quantum_ide/terminal');
  static final Map<String, NativeTerminal> _instances = {};

  final String id;
  final Function(String) onData;
  final Function(int) onExit;
  final Function(String) onError;

  NativeTerminal({
    required this.id,
    required this.onData,
    required this.onExit,
    required this.onError,
  }) {
    _instances[id] = this;
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<void> start({
    required String scriptPath,
    Map<String, String> env = const {},
  }) async {
    await _channel.invokeMethod('startTerminal', {
      'id': id,
      'scriptPath': scriptPath,
      'env': env,
    });
  }

  Future<void> write(String data) async {
    await _channel.invokeMethod('write', {
      'id': id,
      'data': data,
    });
  }

  Future<void> terminate() async {
    await _channel.invokeMethod('terminate', {
      'id': id,
    });
    _instances.remove(id);
  }

  static Future<void> _handleMethod(MethodCall call) async {
    final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
    final String? id = args['id'];
    if (id == null) return;

    final instance = _instances[id];
    if (instance == null) return;

    switch (call.method) {
      case 'onData':
        instance.onData(args['data'] as String);
        break;
      case 'onExit':
        instance.onExit(args['exitCode'] as int);
        break;
      case 'onError':
        instance.onError(args['message'] as String);
        break;
    }
  }
}
