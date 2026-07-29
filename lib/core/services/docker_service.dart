import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String status;
  final String state;

  const DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.state,
  });

  bool get isRunning => state == 'running';
}

class DockerService extends ChangeNotifier {
  final Ref ref;

  DockerService(this.ref);

  bool _isDockerInstalled = false;
  bool get isDockerInstalled => _isDockerInstalled;

  String? _engine; // 'docker' or 'podman'
  String? get engine => _engine;

  bool _isChecking = false;
  bool get isChecking => _isChecking;

  String? _error;
  String? get error => _error;

  List<DockerContainer> _containers = [];
  List<DockerContainer> get containers => _containers;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> checkDocker() async {
    if (_isChecking) return;
    _isChecking = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    try {
      final dockerOutput = await runtime.runCommand('which docker 2>/dev/null');
      if (dockerOutput.trim().isNotEmpty) {
        _isDockerInstalled = true;
        _engine = 'docker';
      } else {
        final podmanOutput = await runtime.runCommand('which podman 2>/dev/null');
        if (podmanOutput.trim().isNotEmpty) {
          _isDockerInstalled = true;
          _engine = 'podman';
        } else {
          _isDockerInstalled = false;
          _engine = null;
        }
      }
    } catch (e) {
      _isDockerInstalled = false;
      _engine = null;
      _error = 'Failed to check Docker: $e';
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<bool> installDocker() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    try {
      await runtime.runCommand('apt-get update -qq');
      await runtime.runCommand('DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io');
      await checkDocker();
      return _isDockerInstalled;
    } catch (e) {
      _error = 'Docker installation failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String get _cmd => _engine ?? 'docker';

  Future<void> listContainers({bool all = true}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    try {
      final flags = all ? '-a' : '';
      final output = await runtime.runCommand(
        '$_cmd ps $flags --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.State}}"',
      );

      _containers = output
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
        final parts = line.split('|');
        if (parts.length < 5) return null;
        return DockerContainer(
          id: parts[0].trim(),
          name: parts[1].trim(),
          image: parts[2].trim(),
          status: parts[3].trim(),
          state: parts[4].trim(),
        );
      }).whereType<DockerContainer>().toList();
    } catch (e) {
      _error = 'Failed to list containers: $e';
      _containers = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> createContainer({
    required String name,
    required String image,
    List<String>? volumes,
    Map<String, String>? environment,
    bool autoRemove = false,
  }) async {
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    final args = StringBuffer('$_cmd create --name "$name"');

    if (autoRemove) args.write(' --rm');
    if (volumes != null) {
      for (final v in volumes) {
        args.write(' -v "$v"');
      }
    }
    if (environment != null) {
      for (final entry in environment.entries) {
        args.write(' -e "${entry.key}=${entry.value}"');
      }
    }

    args.write(' "$image"');

    try {
      final output = await runtime.runCommand(args.toString().trim());
      final containerId = output.trim();
      await listContainers();
      return containerId;
    } catch (e) {
      _error = 'Failed to create container: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startContainer(String containerIdOrName) async {
    _error = null;
    final runtime = ref.read(runtimeServiceProvider);
    try {
      await runtime.runCommand('$_cmd start "$containerIdOrName"');
      await listContainers();
    } catch (e) {
      _error = 'Failed to start container: $e';
      notifyListeners();
    }
  }

  Future<void> stopContainer(String containerIdOrName) async {
    _error = null;
    final runtime = ref.read(runtimeServiceProvider);
    try {
      await runtime.runCommand('$_cmd stop "$containerIdOrName"');
      await listContainers();
    } catch (e) {
      _error = 'Failed to stop container: $e';
      notifyListeners();
    }
  }

  Future<void> removeContainer(String containerIdOrName, {bool force = false}) async {
    _error = null;
    final runtime = ref.read(runtimeServiceProvider);
    try {
      final flags = force ? '-f' : '';
      await runtime.runCommand('$_cmd rm $flags "$containerIdOrName"');
      await listContainers();
    } catch (e) {
      _error = 'Failed to remove container: $e';
      notifyListeners();
    }
  }

  Future<String> execInContainer(String containerIdOrName, String command) async {
    _error = null;
    final runtime = ref.read(runtimeServiceProvider);
    try {
      final output = await runtime.runCommand(
        '$_cmd exec "$containerIdOrName" bash -c "${command.replaceAll('"', '\\"')}"',
      );
      return output;
    } catch (e) {
      _error = 'Failed to exec in container: $e';
      notifyListeners();
      rethrow;
    }
  }

  String getAndroidStorageVolumes() {
    final runtime = ref.read(runtimeServiceProvider);
    final filesDir = runtime.appDirectory;
    return '$filesDir/data:/data:rw';
  }

  @override
  void dispose() {
    super.dispose();
  }
}

final dockerServiceProvider = Provider((ref) => DockerService(ref));
