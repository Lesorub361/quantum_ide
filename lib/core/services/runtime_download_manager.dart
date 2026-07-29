import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class RuntimePackage {
  final String id;
  final String name;
  final String description;
  final String version;
  final int sizeBytes;
  final String downloadUrl;
  final String? installCommand;
  final List<String> requiredBy;

  const RuntimePackage({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.sizeBytes,
    required this.downloadUrl,
    this.installCommand,
    this.requiredBy = const [],
  });
}

class RuntimeDownloadState {
  final bool isDownloading;
  final double progress;
  final String? error;
  final bool isInstalled;

  const RuntimeDownloadState({
    this.isDownloading = false,
    this.progress = 0,
    this.error,
    this.isInstalled = false,
  });
}

class RuntimeDownloadManager extends StateNotifier<Map<String, RuntimeDownloadState>> {
  final Dio _dio = Dio();

  static const List<RuntimePackage> availablePackages = [
    RuntimePackage(
      id: 'node',
      name: 'Node.js',
      description: 'JavaScript runtime for server-side development',
      version: '20.11.0',
      sizeBytes: 25000000,
      downloadUrl: 'https://nodejs.org/dist/v20.11.0/node-v20.11.0-linux-arm64.tar.xz',
      installCommand: 'tar -xf node-v20.11.0-linux-arm64.tar.xz',
    ),
    RuntimePackage(
      id: 'python',
      name: 'Python',
      description: 'Python programming language',
      version: '3.12.1',
      sizeBytes: 30000000,
      downloadUrl: 'https://www.python.org/ftp/python/3.12.1/Python-3.12.1.tar.xz',
      installCommand: './configure && make && make install',
    ),
    RuntimePackage(
      id: 'java',
      name: 'Java (OpenJDK)',
      description: 'Java Development Kit',
      version: '21.0.1',
      sizeBytes: 180000000,
      downloadUrl: 'https://download.java.net/java/GA/jdk21.0.1/64c1b2ef096c4c779acd492011f3629f/15/openjdk-21.0.1_linux-aarch64_bin.tar.gz',
    ),
    RuntimePackage(
      id: 'kotlin',
      name: 'Kotlin',
      description: 'Kotlin programming language',
      version: '1.9.22',
      sizeBytes: 120000000,
      downloadUrl: 'https://github.com/JetBrains/kotlin/releases/download/v1.9.22/kotlin-compiler-1.9.22.zip',
    ),
    RuntimePackage(
      id: 'clang',
      name: 'Clang/LLVM',
      description: 'C/C++/Objective-C compiler',
      version: '17.0.6',
      sizeBytes: 90000000,
      downloadUrl: '',
    ),
    RuntimePackage(
      id: 'dart',
      name: 'Dart SDK',
      description: 'Dart programming language SDK',
      version: '3.3.0',
      sizeBytes: 50000000,
      downloadUrl: 'https://storage.googleapis.com/dart-archive/channels/stable/release/3.3.0/sdk/dartsdk-linux-arm64-release.zip',
    ),
    RuntimePackage(
      id: 'rust',
      name: 'Rust',
      description: 'Rust programming language',
      version: '1.75.0',
      sizeBytes: 60000000,
      downloadUrl: 'https://static.rustup.org/dist/rustup/dist/aarch64-unknown-linux-gnu/rustup-init',
    ),
    RuntimePackage(
      id: 'go',
      name: 'Go',
      description: 'Go programming language',
      version: '1.21.5',
      sizeBytes: 80000000,
      downloadUrl: 'https://go.dev/dl/go1.21.5.linux-arm64.tar.gz',
    ),
    RuntimePackage(
      id: 'lua',
      name: 'Lua',
      description: 'Lua scripting language',
      version: '5.4.6',
      sizeBytes: 500000,
      downloadUrl: 'https://www.lua.org/ftp/lua-5.4.6.tar.gz',
      installCommand: 'make linux && make install',
    ),
  ];

  RuntimeDownloadManager() : super({});

  Future<String> _getInstallDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final runtimesDir = Directory(p.join(appDir.path, 'quantum_ide', 'runtimes'));
    if (!await runtimesDir.exists()) {
      await runtimesDir.create(recursive: true);
    }
    return runtimesDir.path;
  }

  bool isInstalled(String packageId) {
    return state[packageId]?.isInstalled ?? false;
  }

  Future<void> checkInstalled() async {
    final installDir = await _getInstallDir();
    final newState = Map<String, RuntimeDownloadState>.from(state);
    for (final pkg in availablePackages) {
      final pkgDir = Directory(p.join(installDir, pkg.id));
      newState[pkg.id] = RuntimeDownloadState(
        isInstalled: await pkgDir.exists(),
      );
    }
    state = newState;
  }

  Future<void> downloadAndInstall(RuntimePackage pkg) async {
    if (pkg.downloadUrl.isEmpty) {
      state = Map.from(state)..[pkg.id] = const RuntimeDownloadState(
        error: 'Manual installation required',
      );
      return;
    }

    state = Map.from(state)..[pkg.id] = const RuntimeDownloadState(isDownloading: true, progress: 0);

    try {
      final installDir = await _getInstallDir();
      final downloadPath = p.join(installDir, '${pkg.id}_download');

      await _dio.download(
        pkg.downloadUrl,
        downloadPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            state = Map.from(state)..[pkg.id] = RuntimeDownloadState(
              isDownloading: true,
              progress: received / total,
            );
          }
        },
      );

      if (pkg.installCommand != null) {
        await Process.run('bash', ['-c', pkg.installCommand!], workingDirectory: installDir);
      }

      state = Map.from(state)..[pkg.id] = const RuntimeDownloadState(isInstalled: true);
    } catch (e) {
      state = Map.from(state)..[pkg.id] = RuntimeDownloadState(error: e.toString());
    }
  }

  Future<void> uninstall(String packageId) async {
    final installDir = await _getInstallDir();
    final pkgDir = Directory(p.join(installDir, packageId));
    if (await pkgDir.exists()) {
      await pkgDir.delete(recursive: true);
    }
    state = Map.from(state)..[packageId] = const RuntimeDownloadState(isInstalled: false);
  }
}

final runtimeDownloadProvider = StateNotifierProvider<RuntimeDownloadManager, Map<String, RuntimeDownloadState>>((ref) {
  return RuntimeDownloadManager();
});
