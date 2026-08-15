import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

class SshConnection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String keyPath;
  final String? password;

  const SshConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.keyPath = '',
    this.password,
  });

  SshConnection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? keyPath,
    String? password,
  }) {
    return SshConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      keyPath: keyPath ?? this.keyPath,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'keyPath': keyPath,
        'password': password,
      };

  factory SshConnection.fromJson(Map<String, dynamic> json) {
    return SshConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String,
      keyPath: (json['keyPath'] as String?) ?? '',
      password: json['password'] as String?,
    );
  }
}

class SshRemoteFile {
  final String name;
  final bool isDirectory;
  final int size;
  final String permissions;

  const SshRemoteFile({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.permissions = '',
  });
}

class SshService extends ChangeNotifier {
  final Ref ref;

  SshService(this.ref);

  static const _prefsKey = 'ssh_connections';

  List<SshConnection> _connections = [];
  List<SshConnection> get connections => List.unmodifiable(_connections);

  SshConnection? _activeConnection;
  SshConnection? get activeConnection => _activeConnection;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _error;
  String? get error => _error;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _output = '';
  String get output => _output;

  Future<void> loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _connections = list
            .map((e) => SshConnection.fromJson(e as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load SSH connections: $e');
    }
  }

  Future<void> saveConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_connections.map((c) => c.toJson()).toList());
      await prefs.setString(_prefsKey, json);
    } catch (e) {
      debugPrint('Failed to save SSH connections: $e');
    }
  }

  Future<void> addConnection(SshConnection connection) async {
    _connections.add(connection);
    await saveConnections();
    notifyListeners();
  }

  Future<void> removeConnection(String id) async {
    _connections.removeWhere((c) => c.id == id);
    if (_activeConnection?.id == id) {
      _activeConnection = null;
      _isConnected = false;
    }
    await saveConnections();
    notifyListeners();
  }

  Future<void> updateConnection(SshConnection connection) async {
    final index = _connections.indexWhere((c) => c.id == connection.id);
    if (index >= 0) {
      _connections[index] = connection;
      if (_activeConnection?.id == connection.id) {
        _activeConnection = connection;
      }
      await saveConnections();
      notifyListeners();
    }
  }

  Future<bool> connect(SshConnection connection) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    try {
      final keyArg =
          connection.keyPath.isNotEmpty ? '-i "${connection.keyPath}"' : '';
      final testCmd =
          'ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no '
          '$keyArg -p ${connection.port} ${connection.username}@${connection.host} echo "connected"';

      final output = await runtime.runCommand(testCmd);
      if (output.trim().contains('connected')) {
        _activeConnection = connection;
        _isConnected = true;
        notifyListeners();
        return true;
      }
      _error = 'Connection test failed';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'SSH connection failed: $e';
      _isConnected = false;
      _isLoading = false;
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _activeConnection = null;
    _isConnected = false;
    _output = '';
    notifyListeners();
  }

  Future<String> executeCommand(String command) async {
    if (_activeConnection == null || !_isConnected) {
      throw StateError('No active SSH connection');
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    final conn = _activeConnection!;

    try {
      final keyArg = conn.keyPath.isNotEmpty ? '-i "${conn.keyPath}"' : '';
      final remoteCmd = 'ssh -o StrictHostKeyChecking=no '
          '$keyArg -p ${conn.port} ${conn.username}@${conn.host} '
          '"${command.replaceAll('"', '\\"')}"';

      final output = await runtime.runCommand(remoteCmd);
      _output = output;
      notifyListeners();
      return output;
    } catch (e) {
      _error = 'Command execution failed: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadFile(String localPath, String remotePath) async {
    if (_activeConnection == null || !_isConnected) {
      throw StateError('No active SSH connection');
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    final conn = _activeConnection!;

    try {
      final keyArg = conn.keyPath.isNotEmpty ? '-i "${conn.keyPath}"' : '';
      await runtime.runCommand(
        'scp -o StrictHostKeyChecking=no $keyArg '
        '-P ${conn.port} "$localPath" '
        '${conn.username}@${conn.host}:"$remotePath"',
      );
    } catch (e) {
      _error = 'Upload failed: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> downloadFile(String remotePath, String localPath) async {
    if (_activeConnection == null || !_isConnected) {
      throw StateError('No active SSH connection');
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final runtime = ref.read(runtimeServiceProvider);
    final conn = _activeConnection!;

    try {
      final keyArg = conn.keyPath.isNotEmpty ? '-i "${conn.keyPath}"' : '';
      await runtime.runCommand(
        'scp -o StrictHostKeyChecking=no $keyArg '
        '-P ${conn.port} '
        '${conn.username}@${conn.host}:"$remotePath" "$localPath"',
      );
    } catch (e) {
      _error = 'Download failed: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<SshRemoteFile>> listRemoteDirectory(String remotePath) async {
    if (_activeConnection == null || !_isConnected) {
      throw StateError('No active SSH connection');
    }

    final runtime = ref.read(runtimeServiceProvider);
    final conn = _activeConnection!;

    try {
      final keyArg = conn.keyPath.isNotEmpty ? '-i "${conn.keyPath}"' : '';
      final output = await runtime.runCommand(
        'ssh -o StrictHostKeyChecking=no $keyArg '
        '-p ${conn.port} ${conn.username}@${conn.host} '
        '"ls -la \\"$remotePath\\""',
      );

      final files = <SshRemoteFile>[];
      for (final line in output.split('\n')) {
        if (line.isEmpty || line.startsWith('total')) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 9) continue;

        final permissions = parts[0];
        final name = parts.sublist(8).join(' ');
        if (name == '.' || name == '..') continue;

        final isDirectory = permissions.startsWith('d');
        final size = isDirectory ? 0 : (int.tryParse(parts[4]) ?? 0);

        files.add(SshRemoteFile(
          name: name,
          isDirectory: isDirectory,
          size: size,
          permissions: permissions,
        ));
      }
      return files;
    } catch (e) {
      _error = 'Failed to list remote directory: $e';
      notifyListeners();
      rethrow;
    }
  }
}

final sshServiceProvider = Provider((ref) => SshService(ref));
