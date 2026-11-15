import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShizukuBridge {
  static final ShizukuBridge instance = ShizukuBridge._();
  ShizukuBridge._();

  static const _channel = MethodChannel('com.example.quantum_ide/native');

  final ValueNotifier<int> statusVersion = ValueNotifier<int>(0);

  bool _isAvailable = false;
  bool _permissionGranted = false;
  int _uid = -1;

  bool get isAvailable => _isAvailable && _permissionGranted;
  bool get isBinderAlive => _isAvailable;
  bool get hasPermission => _permissionGranted;
  int get uid => _uid;

  void _notifyStatusChanged() {
    statusVersion.value++;
  }

  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      _isAvailable = false;
      _permissionGranted = false;
      _notifyStatusChanged();
      return;
    }
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>('shizukuStatus');
      if (status != null) {
        _isAvailable = status['available'] == true;
        _permissionGranted = status['permissionGranted'] == true;
        _uid = (status['uid'] as num?)?.toInt() ?? -1;
        debugPrint(
          'Shizuku initialized: binder=$_isAvailable, permission=$_permissionGranted, uid=$_uid',
        );
      }
    } catch (e) {
      debugPrint('Shizuku init error: $e');
      _isAvailable = false;
      _permissionGranted = false;
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
}
