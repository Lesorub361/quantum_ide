import 'dart:convert';
import 'dart:io';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Pre-compiled base64 encoded plugin.wasm bytes for default Text Transformer
const String demoWasmBase64 = 'AGFzbQEAAAABEgNgAn9/AGABfwF/YAN/f38BfgIQAQNlbnYIaG9zdF9sb2cAAAMEAwEAAgUDAQADBggBfwFBsIgICwcpBAZtZW1vcnkCAAVhbGxvYwABB2RlYWxsb2MAAgpydW5fcGx1Z2luAAMKtgcDMwEBf0EAQQBBACgCoIiAgAAiASABIABqQYCABEobIgEgAGo2AqCIgIAAIAFBsIiAgABqCwIAC/wGAQd/IAEgAmoiA0EAOgAAQYCIgIAAQRkQgICAgABBAEEAQQAoAqCIgIAAIgQgBCACQQFqIgVqQYCABEobIgYgBWo2AqCIgIAAIAZBsIiAgABqIQQCQAJAAkACQAJAIABBf2oOAwIBAAMLIAJBAUgNAyACQQNxIQdBACEAAkAgAkEESQ0AIAJB/P///wdxIQggA0F/aiEJQQAhAANAIAQgAGoiBSAJLQAAOgAAIAVBAWogAyAAQX5zai0AADoAACAFQQJqIAMgAEF9c2otAAA6AAAgBUEDaiADIABBfHNqLQAAOgAAIAlBfGohCSAIIABBBGoiAEcNAAsLIAdFDQMgBiAAakGwiICAAGohBSABIABBf3MgAmpqIQADQCAFIAAtAAA6AAAgAEF/aiEAIAVBAWohBSAHQX9qIgcNAAwECwsgAkEBSA0CIAJBAXEhCEEAIQACQCACQQFGDQAgAkH+////B3EhB0EAIQADQCAEIABqIgMgASAAaiIJLQAAIgVBIHIgBSAFQb9/akH/AXFBGkkbOgAAIANBAWogCUEBai0AACIFQSByIAUgBUG/f2pB/wFxQRpJGzoAACAHIABBAmoiAEcNAAsLIAhFDQIgBCAAaiABIABqLQAAIgBBIHIgACAAQb9/akH/AXFBGkkbOgAADAILIAJBAUgNASACQQFxIQhBACEAAkAgAkEBRg0AIAJB/v///wdxIQdBACEAA0AgBCAAaiIDIAEgAGoiCS0AACIFQWBqIAUgBUGff2pB/wFxQRpJGzoAACADQQFqIAlBAWotAAAiBUFgaiAFIAVBn39qQf8BcUEaSRs6AAAgByAAQQJqIgBHDQALCyAIRQ0BIAQgAGogASAAai0AACIAQWBqIAAgAEGff2pB/wFxQRpJGzoAAAwBCyACQQFIDQAgAkEDcSEJQQAhAAJAIAJBBEkNACACQfz///8HcSEHQQAhAANAIAQgAGoiBSABIABqIgMtAAA6AAAgBUEBaiADQQFqLQAAOgAAIAVBAmogA0ECai0AADoAACAFQQNqIANBA2otAAA6AAAgByAAQQRqIgBHDQALCyAJRQ0AIAEgAGohBSAGIABqQbCIgIAAaiEAA0AgACAFLQAAOgAAIAVBAWohBSAAQQFqIQAgCUF/aiIJDQALCyAEIAJqQQA6AAAgBK1CIIYgAqyECwshAQBBgAgLGkluc幻Input processed by pluginAAFwEbmFtZQAMC3BsdWdpbi53YXNtAScEAAhob3N0X2xvZwEFYWxsb2MCB2RlYWxsb2MDCnJ1bl9wbHVnaW4HEgEAD19fc3RhY2tfcG9pbnRlcgkKAQAHLnJvZGF0YQA4CXByb2R1Y2VycwEMcHJvY2Vzc2VkLWJ5AQxVYnVudHUgY2xhbmcRMTguMS4zICgxdWJ1bnR1MSkALA90YXJnZXRfZmVhdHVyZXMCKw9tdXRhYmxlLWdsb2JhbHMrCHNpZ24tZXh0';

class WasmPluginAction {
  final int id;
  final String name;
  final String description;

  WasmPluginAction({
    required this.id,
    required this.name,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
  };

  factory WasmPluginAction.fromJson(Map<String, dynamic> json) => WasmPluginAction(
    id: json['id'],
    name: json['name'],
    description: json['description'],
  );
}

class WasmPlugin {
  final String id;
  final String name;
  final String description;
  final String wasmPath;
  final List<WasmPluginAction> actions;
  final bool isEnabled;
  final List<String> logs;

  WasmPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.wasmPath,
    required this.actions,
    this.isEnabled = true,
    this.logs = const [],
  });

  WasmPlugin copyWith({
    String? name,
    String? description,
    bool? isEnabled,
    List<WasmPluginAction>? actions,
    List<String>? logs,
  }) {
    return WasmPlugin(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      wasmPath: wasmPath,
      actions: actions ?? this.actions,
      isEnabled: isEnabled ?? this.isEnabled,
      logs: logs ?? this.logs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'wasmPath': wasmPath,
    'isEnabled': isEnabled,
    'actions': actions.map((a) => a.toJson()).toList(),
  };

  factory WasmPlugin.fromJson(Map<String, dynamic> json) {
    return WasmPlugin(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      wasmPath: json['wasmPath'],
      isEnabled: json['isEnabled'] ?? true,
      actions: (json['actions'] as List?)?.map((a) => WasmPluginAction.fromJson(a)).toList() ?? [],
      logs: [],
    );
  }
}

class WasmPluginState {
  final List<WasmPlugin> plugins;
  final bool isInitialized;
  final String? error;

  WasmPluginState({
    this.plugins = const [],
    this.isInitialized = false,
    this.error,
  });

  WasmPluginState copyWith({
    List<WasmPlugin>? plugins,
    bool? isInitialized,
    String? error,
  }) {
    return WasmPluginState(
      plugins: plugins ?? this.plugins,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error,
    );
  }
}

class WasmPluginService extends StateNotifier<WasmPluginState> {
  InAppWebViewController? _webViewController;
  late final String _pluginsDir;
  late final String _configFile;

  WasmPluginService() : super(WasmPluginState()) {
    _initStorage();
  }

  Future<void> _initStorage() async {
    try {
      final docDir = await getApplicationSupportDirectory();
      _pluginsDir = p.join(docDir.path, 'wasm_plugins');
      final dir = Directory(_pluginsDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      _configFile = p.join(_pluginsDir, 'plugins.json');
      await _loadConfig();
    } catch (e) {
      state = state.copyWith(error: 'Failed to init plugin storage: $e');
    }
  }

  Future<void> _loadConfig() async {
    final file = File(_configFile);
    if (!file.existsSync()) {
      // Setup default Text Transformer Demo
      final defaultList = [
        WasmPlugin(
          id: 'text_transformer_demo',
          name: 'Text Transformer',
          description: 'Transforms text to UPPERCASE, lowercase, or reverses it using WebAssembly.',
          wasmPath: 'embedded_demo',
          actions: [
            WasmPluginAction(id: 1, name: 'Uppercase', description: 'Converts text to UPPERCASE'),
            WasmPluginAction(id: 2, name: 'Lowercase', description: 'Converts text to lowercase'),
            WasmPluginAction(id: 3, name: 'Reverse', description: 'Reverses text characters'),
          ],
          isEnabled: true,
        )
      ];
      await _saveConfig(defaultList);
      state = state.copyWith(plugins: defaultList, isInitialized: true);
      return;
    }

    try {
      final content = await file.readAsString();
      final List list = jsonDecode(content);
      final plugins = list.map((item) => WasmPlugin.fromJson(item)).toList();
      state = state.copyWith(plugins: plugins, isInitialized: true);
    } catch (e) {
      state = state.copyWith(error: 'Failed to parse plugins config: $e', isInitialized: true);
    }
  }

  Future<void> _saveConfig(List<WasmPlugin> list) async {
    final file = File(_configFile);
    final jsonList = list.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  void setController(InAppWebViewController controller) {
    _webViewController = controller;
    _setupJavaScriptHandlers();
    _loadAllActivePluginsInWebView();
  }

  void _setupJavaScriptHandlers() {
    if (_webViewController == null) return;

    _webViewController!.addJavaScriptHandler(
      handlerName: 'onPluginLog',
      callback: (args) {
        final data = args[0] as Map;
        final pluginId = data['pluginId'] as String;
        final message = data['message'] as String;
        _appendLog(pluginId, message);
      },
    );
  }

  void _appendLog(String pluginId, String message) {
    state = state.copyWith(
      plugins: state.plugins.map((p) {
        if (p.id == pluginId) {
          final timestamp = DateTime.now().toLocal().toString().substring(11, 19);
          return p.copyWith(
            logs: [...p.logs, '[$timestamp] $message'],
          );
        }
        return p;
      }).toList(),
    );
  }

  void clearLogs(String pluginId) {
    state = state.copyWith(
      plugins: state.plugins.map((p) {
        if (p.id == pluginId) {
          return p.copyWith(logs: []);
        }
        return p;
      }).toList(),
    );
  }

  Future<void> _loadAllActivePluginsInWebView() async {
    if (_webViewController == null) return;
    for (final plugin in state.plugins) {
      if (plugin.isEnabled) {
        await _loadPluginInWebView(plugin);
      }
    }
  }

  Future<bool> _loadPluginInWebView(WasmPlugin plugin) async {
    if (_webViewController == null) return false;
    try {
      String base64Bytes = '';
      if (plugin.wasmPath == 'embedded_demo') {
        base64Bytes = demoWasmBase64;
      } else {
        final file = File(plugin.wasmPath);
        if (!file.existsSync()) {
          _appendLog(plugin.id, 'Error: WASM file not found at ${plugin.wasmPath}');
          return false;
        }
        final bytes = await file.readAsBytes();
        base64Bytes = base64Encode(bytes);
      }

      final dynamic result = await _webViewController!.evaluateJavascript(
        source: 'window.loadWasmPlugin("${plugin.id}", "$base64Bytes");',
      );

      final success = result != null && (result['success'] == true);
      if (success) {
        _appendLog(plugin.id, 'Loaded successfully in sandbox.');
      } else {
        final err = result != null ? result['error'] : 'Unknown JS error';
        _appendLog(plugin.id, 'Load Error: $err');
      }
      return success;
    } catch (e) {
      _appendLog(plugin.id, 'Bridge Error: $e');
      return false;
    }
  }

  Future<void> togglePlugin(String pluginId, bool enable) async {
    final updated = state.plugins.map((p) {
      if (p.id == pluginId) {
        return p.copyWith(isEnabled: enable);
      }
      return p;
    }).toList();

    await _saveConfig(updated);
    state = state.copyWith(plugins: updated);

    final plugin = updated.firstWhere((p) => p.id == pluginId);
    if (enable) {
      await _loadPluginInWebView(plugin);
    } else {
      if (_webViewController != null) {
        await _webViewController!.evaluateJavascript(
          source: 'delete window.plugins["$pluginId"];',
        );
      }
      _appendLog(pluginId, 'Disabled and unloaded from sandbox.');
    }
  }

  Future<void> installPlugin(String name, String description, String filePath, List<WasmPluginAction> actions) async {
    final id = 'wasm_plugin_${DateTime.now().millisecondsSinceEpoch}';
    final destination = p.join(_pluginsDir, '$id.wasm');

    final sourceFile = File(filePath);
    if (!sourceFile.existsSync()) {
      throw Exception('Source file does not exist.');
    }

    await sourceFile.copy(destination);

    final newPlugin = WasmPlugin(
      id: id,
      name: name,
      description: description,
      wasmPath: destination,
      actions: actions,
      isEnabled: true,
    );

    final updated = [...state.plugins, newPlugin];
    await _saveConfig(updated);
    state = state.copyWith(plugins: updated);

    await _loadPluginInWebView(newPlugin);
  }

  Future<void> deletePlugin(String pluginId) async {
    final plugin = state.plugins.firstWhere((p) => p.id == pluginId);
    if (plugin.wasmPath != 'embedded_demo') {
      final file = File(plugin.wasmPath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }

    final updated = state.plugins.where((p) => p.id != pluginId).toList();
    await _saveConfig(updated);
    state = state.copyWith(plugins: updated);

    if (_webViewController != null) {
      await _webViewController!.evaluateJavascript(
        source: 'delete window.plugins["$pluginId"];',
      );
    }
  }

  Future<void> resetToDefaults() async {
    for (final plugin in state.plugins) {
      if (plugin.wasmPath != 'embedded_demo') {
        final file = File(plugin.wasmPath);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
      }
      if (_webViewController != null) {
        await _webViewController!.evaluateJavascript(
          source: 'delete window.plugins["${plugin.id}"];',
        );
      }
    }

    final file = File(_configFile);
    if (file.existsSync()) {
      file.deleteSync();
    }

    await _loadConfig();
    await _loadAllActivePluginsInWebView();
  }

  Future<String> executeAction(String pluginId, int actionId, String inputText) async {
    final plugin = state.plugins.firstWhere((p) => p.id == pluginId);
    if (!plugin.isEnabled) {
      throw Exception('Plugin is disabled.');
    }
    if (_webViewController == null) {
      throw Exception('Sandbox not initialized.');
    }

    final dynamic result = await _webViewController!.evaluateJavascript(
      source: 'window.runWasmAction("$pluginId", $actionId, ${jsonEncode(inputText)});',
    );

    if (result == null) {
      throw Exception('Failed to receive response from WASM sandbox.');
    }

    return result.toString();
  }
}

final wasmPluginServiceProvider = StateNotifierProvider<WasmPluginService, WasmPluginState>((ref) {
  return WasmPluginService();
});
