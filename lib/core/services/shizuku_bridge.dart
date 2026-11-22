import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quantum_ide/core/services/log_service.dart';

class ShizukuBridge {
  static final ShizukuBridge instance = ShizukuBridge._();
  ShizukuBridge._();

  static const _channel = MethodChannel('com.example.quantum_ide/native');

  final ValueNotifier<int> statusVersion = ValueNotifier<int>(0);

  bool _handlerBound = false;
  bool _isAvailable = false;
  bool _permissionGranted = false;
  int _uid = -1;
  String? _lastError;

  bool get isAvailable => _isAvailable && _permissionGranted;
  bool get isBinderAlive => _isAvailable;
  bool get hasPermission => _permissionGranted;
  int get uid => _uid;
  String? get lastError => _lastError;

  void _notifyStatusChanged() {
    statusVersion.value++;
  }

  void _bindNativeCallback() {
    if (_handlerBound) return;
    _handlerBound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShizukuStatusChanged' && call.arguments is Map) {
        final status = Map<dynamic, dynamic>.from(call.arguments as Map);
        _applyStatusMap(status);
        _notifyStatusChanged();
      }
    });
  }

  void _applyStatusMap(Map<dynamic, dynamic> status) {
    _isAvailable = status['available'] == true;
    _permissionGranted = status['permissionGranted'] == true;
    _uid = (status['uid'] as num?)?.toInt() ?? -1;
    _lastError = status['error']?.toString();
    final msg =
        '[Shizuku] binder=$_isAvailable, permission=$_permissionGranted, uid=$_uid${_lastError != null && _lastError!.isNotEmpty ? ', err=$_lastError' : ''}';
    debugPrint(msg);
    try {
      LogService.log(msg);
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _isAvailable = false;
      _permissionGranted = false;
      _lastError = null;
      _notifyStatusChanged();
      return;
    }
    _bindNativeCallback();
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('shizukuStatus');
      if (status != null) {
        _applyStatusMap(status);
      }
    } catch (e) {
      debugPrint('Shizuku init error: $e');
      _isAvailable = false;
      _permissionGranted = false;
      _lastError = e.toString();
      try {
        LogService.log('[Shizuku] init error: $_lastError');
      } catch (_) {}
    }
    _notifyStatusChanged();
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted =
          await _channel.invokeMethod<bool>('shizukuRequestPermission') ?? false;
      await initialize();
      return granted && _permissionGranted;
    } catch (e) {
      debugPrint('Shizuku permission request error: $e');
      return false;
    }
  }

  Future<ProcessResult> execute(String executable, List<String> args) async {
    if (!Platform.isAndroid) {
      throw Exception('Shizuku is only supported on Android');
    }
    if (!isAvailable) {
      await initialize();
      if (!isAvailable) {
        throw Exception('Shizuku not available or permission not granted');
      }
    }

    final res = await _channel.invokeMapMethod<String, dynamic>('shizukuExec', {
      'executable': executable,
      'args': args,
    });

    final exitCode = (res?['exitCode'] as num?)?.toInt() ?? -1;
    final stdout = res?['stdout']?.toString() ?? '';
    final stderr = res?['stderr']?.toString() ?? '';

    return ProcessResult(0, exitCode, stdout, stderr);
  }

  Future<bool> trimBackgroundMemory() async {
    if (!isAvailable) return false;
    try {
      final res = await execute('sh', ['-c', 'am kill-all']);
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('Shizuku trimBackgroundMemory error: $e');
      return false;
    }
  }

  /// Boosts Android OS build performance via Shizuku before heavy compilation:
  /// 1. Disables Android 12+ Phantom Process Killer (32 child process limit)
  /// 2. Whitelists QuantumIDE from Doze & App Standby CPU/network throttling
  /// 3. If running as root (`uid == 0`), lowers swappiness
  /// (Avoids `am kill-all` / `drop_caches` so the soft IME keyboard and hot build cache stay alive.)
  Future<void> boostForBuild() async {
    if (!Platform.isAndroid) return;
    if (!isAvailable) {
      await initialize();
      if (!isAvailable) return;
    }
    try {
      final cmds = <String>[
        'device_config set_sync_disabled_for_tests persistent 2>/dev/null || true',
        'device_config put activity_manager max_phantom_processes 2147483647 2>/dev/null || true',
        'settings put global settings_enable_monitor_phantom_procs false 2>/dev/null || true',
        'dumpsys deviceidle whitelist +com.example.quantum_ide >/dev/null 2>&1 || true',
        'cmd appops set com.example.quantum_ide RUN_IN_BACKGROUND allow 2>/dev/null || true',
        'cmd appops set com.example.quantum_ide RUN_ANY_IN_BACKGROUND allow 2>/dev/null || true',
      ];
      if (_uid == 0) {
        cmds.add('sysctl -w vm.swappiness=20 >/dev/null 2>&1 || true');
      }
      await execute('sh', ['-c', cmds.join('; ')]);
    } catch (e) {
      debugPrint('Shizuku boostForBuild skipped: $e');
    }
  }
}
