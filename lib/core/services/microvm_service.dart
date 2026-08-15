import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

enum MicroVMState { unavailable, available, starting, running, stopping, stopped, error }

class MicroVMService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.quantum_ide/native');

  RuntimeService? _runtime;
  MicroVMState _state = MicroVMState.unavailable;
  bool _kvmAvailable = false;
  String _statusMessage = '';
  String? _vmId;
  String _error = '';

  MicroVMService(this._runtime);

  void setRuntime(RuntimeService runtime) {
    _runtime = runtime;
    notifyListeners();
  }

  RuntimeService get runtime => _runtime!;

  MicroVMState get state => _state;
  bool get kvmAvailable => _kvmAvailable;
  bool get isRunning => _state == MicroVMState.running;
  String get statusMessage => _statusMessage;
  String? get vmId => _vmId;
  String get error => _error;

  Future<void> checkKvmAvailability() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<bool>('checkKvmAvailable');
        _kvmAvailable = result ?? false;
      } else if (Platform.isLinux) {
        _kvmAvailable = await File('/dev/kvm').exists();
      } else {
        _kvmAvailable = false;
      }
      notifyListeners();
    } catch (e) {
      _kvmAvailable = false;
      debugPrint('MicroVMService: KVM check failed: $e');
      notifyListeners();
    }
  }

  Future<void> startVm({String? rootfs, int memoryMb = 512, int cpus = 2}) async {
    if (_state == MicroVMState.running || _state == MicroVMState.starting) return;

    _state = MicroVMState.starting;
    _statusMessage = 'Starting microVM...';
    _error = '';
    notifyListeners();

    try {
      if (!_kvmAvailable) {
        await checkKvmAvailability();
        if (!_kvmAvailable) {
          _state = MicroVMState.unavailable;
          _statusMessage = 'KVM not available, using PRoot fallback';
          _error = 'KVM unavailable';
          notifyListeners();
          return;
        }
      }

      final result = await _channel.invokeMethod<Map>('startMicroVm', {
        'rootfs': rootfs,
        'memoryMb': memoryMb,
        'cpus': cpus,
      });

      if (result != null && result['success'] == true) {
        _vmId = result['vmId'] as String?;
        _state = MicroVMState.running;
        _statusMessage = 'VM running';
      } else {
        _state = MicroVMState.error;
        _statusMessage = 'Failed to start VM';
        _error = result?['error']?.toString() ?? 'Unknown error';
      }
    } catch (e) {
      _state = MicroVMState.error;
      _statusMessage = 'Error starting VM';
      _error = e.toString();
      debugPrint('MicroVMService: startVm failed: $e');
    }
    notifyListeners();
  }

  Future<void> stopVm() async {
    if (_state != MicroVMState.running) return;

    _state = MicroVMState.stopping;
    _statusMessage = 'Stopping VM...';
    notifyListeners();

    try {
      await _channel.invokeMethod('stopMicroVm', {'vmId': _vmId});
      _state = MicroVMState.stopped;
      _statusMessage = 'VM stopped';
      _vmId = null;
    } catch (e) {
      _state = MicroVMState.error;
      _statusMessage = 'Error stopping VM';
      _error = e.toString();
      debugPrint('MicroVMService: stopVm failed: $e');
    }
    notifyListeners();
  }

  Future<String> executeInVm(String command) async {
    if (_state != MicroVMState.running || _vmId == null) {
      throw StateError('VM is not running');
    }

    try {
      final result = await _channel.invokeMethod<String>('executeInMicroVm', {
        'vmId': _vmId,
        'command': command,
      });
      return result ?? '';
    } catch (e) {
      debugPrint('MicroVMService: executeInVm failed: $e');
      rethrow;
    }
  }

  Future<String> runCommand(String command, {String? workingDirectory}) async {
    if (isRunning) {
      return await executeInVm(command);
    }
    return runtime.runCommand(command, workingDirectory: workingDirectory);
  }

  void resetError() {
    _error = '';
    if (_state == MicroVMState.error) {
      _state = _kvmAvailable ? MicroVMState.stopped : MicroVMState.unavailable;
    }
    notifyListeners();
  }
}

final microvmServiceProvider = ChangeNotifierProvider<MicroVMService>((ref) {
  final service = MicroVMService(null);
  ref.onDispose(() => service.dispose());

  ref.listen<RuntimeService>(runtimeServiceProvider, (previous, next) {
    if (next.isInitialized && (previous == null || !previous.isInitialized)) {
      service.setRuntime(next);
    }
  });

  return service;
});
