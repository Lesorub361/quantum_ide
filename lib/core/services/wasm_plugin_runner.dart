import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

class WasmPluginRunner extends ChangeNotifier {
  InAppWebViewController? _webViewController;
  late final String _pluginsDir;
  final Map<String, bool> _loadedPlugins = {};
  final RuntimeService _runtime;

  WasmPluginRunner(this._runtime);

  bool get isReady => _webViewController != null;

  Future<void> init() async {
    try {
      final docDir = await getApplicationSupportDirectory();
      _pluginsDir = p.join(docDir.path, 'wasm_plugins');
      final dir = Directory(_pluginsDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (e) {
      debugPrint('WasmPluginRunner: init failed: $e');
    }
  }

  void setController(InAppWebViewController controller) {
    _webViewController = controller;
    _setupSandbox();
  }

  void _setupSandbox() {
    if (_webViewController == null) return;

    _webViewController!.addJavaScriptHandler(
      handlerName: 'read_file',
      callback: (args) async {
        final path = args[0] as String;
        try {
          final file = File(path);
          if (await file.exists()) {
            return {'success': true, 'content': await file.readAsString()};
          }
          return {'success': false, 'error': 'File not found: $path'};
        } catch (e) {
          return {'success': false, 'error': e.toString()};
        }
      },
    );

    _webViewController!.addJavaScriptHandler(
      handlerName: 'write_file',
      callback: (args) async {
        final path = args[0] as String;
        final content = args[1] as String;
        try {
          final file = File(path);
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
          return {'success': true};
        } catch (e) {
          return {'success': false, 'error': e.toString()};
        }
      },
    );

    _webViewController!.addJavaScriptHandler(
      handlerName: 'run_command',
      callback: (args) async {
        final command = args[0] as String;
        try {
          final result = await _runtime.runCommand(command);
          return {'success': true, 'output': result};
        } catch (e) {
          return {'success': false, 'error': e.toString()};
        }
      },
    );

    _webViewController!.addJavaScriptHandler(
      handlerName: 'log',
      callback: (args) {
        final message = args[0] as String;
        debugPrint('WASM Plugin: $message');
        return {'success': true};
      },
    );
  }

  Future<bool> loadPlugin(String pluginId, String wasmPath) async {
    if (_webViewController == null) {
      debugPrint('WasmPluginRunner: WebView not initialized');
      return false;
    }

    try {
      String base64Bytes;
      if (wasmPath.startsWith('base64:')) {
        base64Bytes = wasmPath.substring(7);
      } else {
        final file = File(wasmPath);
        if (!await file.exists()) {
          debugPrint('WasmPluginRunner: WASM file not found: $wasmPath');
          return false;
        }
        final bytes = await file.readAsBytes();
        base64Bytes = base64Encode(bytes);
      }

      final result = await _webViewController!.evaluateJavascript(
        source: 'window.loadWasmPlugin("$pluginId", "$base64Bytes");',
      );

      final success = result != null && (result['success'] == true);
      _loadedPlugins[pluginId] = success;
      return success;
    } catch (e) {
      debugPrint('WasmPluginRunner: loadPlugin failed: $e');
      _loadedPlugins[pluginId] = false;
      return false;
    }
  }

  Future<String> executePlugin(String pluginId, int actionId, String inputText) async {
    if (_webViewController == null) {
      throw StateError('WebView not initialized');
    }
    if (_loadedPlugins[pluginId] != true) {
      throw StateError('Plugin $pluginId is not loaded');
    }

    final result = await _webViewController!.evaluateJavascript(
      source: 'window.runWasmAction("$pluginId", $actionId, ${jsonEncode(inputText)});',
    );

    if (result == null) {
      throw StateError('No response from WASM sandbox');
    }
    return result.toString();
  }

  Future<void> unloadPlugin(String pluginId) async {
    if (_webViewController == null) return;

    try {
      await _webViewController!.evaluateJavascript(
        source: 'delete window.plugins["$pluginId"];',
      );
    } catch (e) {
      debugPrint('WasmPluginRunner: unloadPlugin failed: $e');
    }
    _loadedPlugins.remove(pluginId);
  }

  bool isPluginLoaded(String pluginId) => _loadedPlugins[pluginId] == true;

  String get pluginsDirectory => _pluginsDir;

  @override
  void dispose() {
    _loadedPlugins.clear();
    super.dispose();
  }
}

final wasmPluginRunnerProvider = ChangeNotifierProvider<WasmPluginRunner>((ref) {
  final runtime = ref.watch(runtimeServiceProvider);
  final runner = WasmPluginRunner(runtime);
  ref.onDispose(() => runner.dispose());
  return runner;
});
