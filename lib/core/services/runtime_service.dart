import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart' show TarDecoder, XZDecoder;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/utils/platform_utils.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class RuntimeService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.quantum_ide/native');

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String _status = 'Idle';
  String get status => _status;

  double _progress = 0;
  double get progress => _progress;

  String _filesDir = () {
    final desktopDir = Directory(PlatformUtils.desktopDataDir);
    if (!desktopDir.existsSync()) {
      try { desktopDir.createSync(recursive: true); } catch (_) {}
    }
    return desktopDir.path;
  }();
  String get filesDir => _filesDir;
  String _nativeLibDir = '';
  final _dio = Dio();

  static const int _maxConcurrentCommands = 3;
  int _runningCommands = 0;
  final List<Completer<void>> _commandQueue = [];

  // High-performance pre-built ARM64 Core rootfs (Ubuntu 24.04 + GLIBC 2.39 + Flutter 3.50.0)
  static const String ubuntu2404RootfsUrl =
      'https://github.com/Lesorub361/quantum_ide/releases/download/rootfs-v1/quantum-core-arm64-ubuntu2404.tar.zst';

  static const List<String> _rootfsUrls = [
    ubuntu2404RootfsUrl,
    'https://github.com/Lesorub361/quantum_ide/releases/download/v1.0.0/pocketdev-core-arm64-2026.09.5.tar.zst',
    'https://github.com/techjarves/Mobile-Harness/releases/download/runtime-2026.09.4/pocketdev-core-arm64-2026.09.5.tar.zst',
  ];

  bool _isInitializing = false;
  bool _useNativeRootMode = false;
  bool get useNativeRootMode => _useNativeRootMode;
  bool? _hasRootAccessCache;
  bool? get hasRootAccessCached => _hasRootAccessCache;

  String get _nativeRootFlagPath =>
      p.join(_filesDir, 'config', 'native_root_mode.flag');

  /// Checks whether the device has working root access (`su -c id` -> `uid=0`).
  Future<bool> checkRootAccess({bool forceRefresh = false}) async {
    if (!Platform.isAndroid) return false;
    if (!forceRefresh && _hasRootAccessCache != null) {
      return _hasRootAccessCache!;
    }
    for (final suBin in const [
      'su',
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/su/bin/su',
      '/data/adb/magisk/su',
      '/data/adb/ksu/bin/su',
      '/data/adb/ap/bin/su',
    ]) {
      try {
        final res = await Process.run(
          suBin,
          ['-c', 'id'],
        ).timeout(const Duration(seconds: 4));
        final out = '${res.stdout}${res.stderr}';
        if (res.exitCode == 0 && out.contains('uid=0')) {
          _hasRootAccessCache = true;
          notifyListeners();
          return true;
        }
      } catch (_) {}
    }
    _hasRootAccessCache = false;
    notifyListeners();
    return false;
  }

  /// Enables or disables running directly on the device kernel via Root (`su`)
  /// without downloading or using the Ubuntu PRoot container.
  Future<void> setUseNativeRootMode(bool enabled) async {
    _useNativeRootMode = enabled;
    try {
      if (Platform.isAndroid && _filesDir.contains('quantum_ide')) {
        // Ensure config dir exists
      } else if (Platform.isAndroid) {
        try {
          _filesDir = await _channel.invokeMethod('getFilesDir');
          _nativeLibDir = await _channel.invokeMethod('getNativeLibDir');
        } catch (_) {}
      }
      final flagFile = File(_nativeRootFlagPath);
      await flagFile.parent.create(recursive: true);
      if (enabled) {
        await flagFile.writeAsString('1\n', flush: true);
      } else if (await flagFile.exists()) {
        await flagFile.delete();
      }
      await _ensureBinaries();
      if (enabled) {
        _isInitialized = true;
        _status = 'Ready (Native Root Kernel)';
        _progress = 1.0;
      }
    } catch (e) {
      debugPrint('RuntimeService: Failed to toggle native root mode: $e');
    }
    notifyListeners();
  }

  Future<bool> isBootstrapComplete() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        if (_filesDir.isEmpty || !_filesDir.startsWith('/data')) {
          _filesDir = await _channel.invokeMethod('getFilesDir');
        }
        if (File(_nativeRootFlagPath).existsSync()) {
          _useNativeRootMode = true;
          return true;
        }
        final bool? complete = await _channel.invokeMethod('isBootstrapComplete');
        return complete ?? false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Inspects the current Linux rootfs (OS version, GLIBC, Flutter version, and
  /// whether an Ubuntu 24.04 migration is needed for Flutter 3.50+).
  Future<Map<String, String>> inspectEnvironment() async {
    try {
      final out = await runCommand(
        'OS=\$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d \'"\' || echo "Linux"); '
        'GLIBC=\$(ldd --version 2>/dev/null | head -n1 | grep -oE "[0-9]+\\.[0-9]+" | tail -n1 || echo "unknown"); '
        'FLUTTER=\$(flutter --version 2>/dev/null | head -n1 | awk \'{print \$2}\' || echo "not installed"); '
        'HAS234=\$(grep -qa "GLIBC_2.34" /lib/aarch64-linux-gnu/libc.so.6 /usr/lib/aarch64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/libc.so.6 2>/dev/null && echo "1" || echo "0"); '
        'echo "OS=\$OS"; echo "GLIBC=\$GLIBC"; echo "FLUTTER=\$FLUTTER"; echo "HAS234=\$HAS234"',
      );
      String os = 'Ubuntu Linux';
      String glibc = 'unknown';
      String flutter = '—';
      bool has234 = true;
      for (final line in out.split('\n')) {
        final t = line.trim();
        if (t.startsWith('OS=')) os = t.substring(3).trim();
        if (t.startsWith('GLIBC=')) glibc = t.substring(6).trim();
        if (t.startsWith('FLUTTER=')) {
          final v = t.substring(8).trim();
          if (v.isNotEmpty) flutter = v;
        }
        if (t.startsWith('HAS234=')) has234 = t.substring(7).trim() == '1';
      }
      return {
        'os': os,
        'glibc': glibc,
        'flutter': flutter,
        'needsUpgrade': (!has234).toString(),
      };
    } catch (_) {
      return {
        'os': 'Linux',
        'glibc': 'unknown',
        'flutter': '—',
        'needsUpgrade': 'false',
      };
    }
  }

  /// Safely migrates an existing Android PRoot rootfs to Ubuntu 24.04 + Flutter 3.50
  /// while preserving user projects, SSH keys, Git config, and AI CLI credentials.
  Future<void> migrateToUbuntu2404() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _isInitializing = true;
    _progress = 0.02;
    _status = 'Сохранение проектов и настроек (.ssh, .gitconfig, .gemini)…';
    notifyListeners();

    try {
      final rootfsHome = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root'));
      final backupHome = Directory(p.join(_filesDir, 'tmp', 'preserved_home'));
      if (FileSystemEntity.typeSync(backupHome.path, followLinks: false) != FileSystemEntityType.notFound) {
        await _forceDeleteDirectory(backupHome);
      }
      await backupHome.create(recursive: true);

      const itemsToPreserve = ['projects', '.ssh', '.gitconfig', '.gemini', '.config'];
      if (await rootfsHome.exists()) {
        for (final name in itemsToPreserve) {
          final srcDir = Directory(p.join(rootfsHome.path, name));
          final srcFile = File(p.join(rootfsHome.path, name));
          if (await srcDir.exists()) {
            await Process.run('cp', ['-a', srcDir.path, p.join(backupHome.path, name)]);
          } else if (await srcFile.exists()) {
            await srcFile.copy(p.join(backupHome.path, name));
          }
        }
      }

      _status = 'Очистка старого rootfs (Ubuntu 20.04)…';
      _progress = 0.08;
      notifyListeners();

      final rootfsDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu'));
      if (FileSystemEntity.typeSync(rootfsDir.path, followLinks: false) != FileSystemEntityType.notFound) {
        await _forceDeleteDirectory(rootfsDir);
      }

      _isInitialized = false;
      _isInitializing = false;
      await init();
      if (!_isInitialized) {
        throw Exception(_status.isNotEmpty ? _status : 'Не удалось инициализировать Ubuntu 24.04');
      }
    } catch (e) {
      _isInitializing = false;
      _status = 'Ошибка миграции: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Forcefully removes [dir] even when contained directories/files lack write bits
  /// (e.g. mode 0555/0444 in extracted Linux rootfs triggering errno 13 in Dart).
  Future<void> _forceDeleteDirectory(Directory dir) async {
    final rootType = FileSystemEntity.typeSync(dir.path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) return;

    if (rootType == FileSystemEntityType.link) {
      await Link(dir.path).delete();
      return;
    }

    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['-R', 'u+rwX', dir.path]);
        await Process.run('rm', ['-rf', dir.path]);
        if (FileSystemEntity.typeSync(dir.path, followLinks: false) == FileSystemEntityType.notFound) {
          return;
        }
      } catch (e) {
        debugPrint('RuntimeService: Native cleanup fallback for ${dir.path}: $e');
      }
    }

    Future<void> deleteEntity(FileSystemEntity entity) async {
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return;

      if (type == FileSystemEntityType.link) {
        Link(entity.path).deleteSync();
        return;
      }

      if (type == FileSystemEntityType.directory) {
        final subDir = Directory(entity.path);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['u+rwx', subDir.path]);
        }
        for (final child in subDir.listSync(followLinks: false)) {
          await deleteEntity(child);
        }
        try {
          subDir.deleteSync();
        } catch (_) {
          if (!Platform.isWindows) {
            await Process.run('chmod', ['u+rwx', subDir.parent.path, subDir.path]);
          }
          subDir.deleteSync();
        }
        return;
      }

      try {
        entity.deleteSync();
      } catch (_) {
        if (!Platform.isWindows) {
          await Process.run('chmod', ['u+rw', entity.path]);
        }
        entity.deleteSync();
      }
    }

    await deleteEntity(dir);
  }

  /// Ensures `$ROOTFS/etc/ssl/certs/ca-certificates.crt` is populated with both
  /// guest Mozilla CAs and Android host system CAs (e.g. APEX Conscrypt cacerts)
  /// so Go, curl, Node.js, Python, and Git verify HTTPS certificates reliably.
  Future<void> _repairCaCertificatesIfNeeded() async {
    try {
      final rootfsDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu'));
      if (!await rootfsDir.exists()) return;

      final caDir = Directory(p.join(rootfsDir.path, 'etc', 'ssl', 'certs'));
      final caBundleFile = File(p.join(caDir.path, 'ca-certificates.crt'));
      final syncMarker = File(p.join(rootfsDir.path, 'etc', 'ssl', '.quantum_ca_synced_v1'));

      var needsRepair = !await caBundleFile.exists() || !await syncMarker.exists();
      if (!needsRepair) {
        final len = await caBundleFile.length();
        if (len < 30 * 1024) {
          needsRepair = true;
        }
      }
      if (!needsRepair) return;

      final pemRegex = RegExp(
        r'-----BEGIN CERTIFICATE-----[\r\n]+[\s\S]*?-----END CERTIFICATE-----',
      );
      final uniqueCerts = <String>{};
      final androidOnlyCerts = <String>{};

      Future<void> collectFromFile(File file, {bool isAndroidHost = false}) async {
        try {
          final content = await file.readAsString();
          for (final match in pemRegex.allMatches(content)) {
            final block = match.group(0)?.trim();
            if (block != null && block.isNotEmpty) {
              uniqueCerts.add(block);
              if (isAndroidHost) {
                androidOnlyCerts.add(block);
              }
            }
          }
        } catch (_) {}
      }

      if (await caBundleFile.exists()) {
        await collectFromFile(caBundleFile);
      }

      for (final guestRelDir in [
        p.join('usr', 'share', 'ca-certificates'),
        p.join('usr', 'local', 'share', 'ca-certificates'),
      ]) {
        final dir = Directory(p.join(rootfsDir.path, guestRelDir));
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && entity.path.endsWith('.crt')) {
            await collectFromFile(entity);
          }
        }
      }

      for (final androidCaPath in const [
        '/apex/com.android.conscrypt/cacerts',
        '/system/etc/security/cacerts',
        '/data/misc/user/0/cacerts-added',
      ]) {
        final dir = Directory(androidCaPath);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            await collectFromFile(entity, isAndroidHost: true);
          }
        }
      }

      if (uniqueCerts.isEmpty) return;

      await caDir.create(recursive: true);
      await caBundleFile.writeAsString('${uniqueCerts.join('\n')}\n');

      if (androidOnlyCerts.isNotEmpty) {
        final localCaDir = Directory(
          p.join(rootfsDir.path, 'usr', 'local', 'share', 'ca-certificates'),
        );
        await localCaDir.create(recursive: true);
        final androidCaFile = File(p.join(localCaDir.path, 'android-system.crt'));
        await androidCaFile.writeAsString('${androidOnlyCerts.join('\n')}\n');
      }

      await syncMarker.writeAsString('v1\n');
      debugPrint('RuntimeService: Synced ${uniqueCerts.length} CA certificates to ${caBundleFile.path}');
    } catch (e) {
      debugPrint('RuntimeService: CA certificate repair skipped: $e');
    }
  }

  Future<void> _cleanupWithdrawnMigrationLeftovers() async {
    try {
      final f = File(p.join(_filesDir, 'tmp', 'rootfs.tar.zst'));
      if (await f.exists()) {
        await f.delete();
        debugPrint('RuntimeService: removed leftover rootfs.tar.zst');
      }
    } catch (e) {
      debugPrint('RuntimeService: cleanup skipped: $e');
    }
  }

  Future<void> init() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        _filesDir = await _channel.invokeMethod('getFilesDir');
        _nativeLibDir = await _channel.invokeMethod('getNativeLibDir');
        debugPrint('RuntimeService: filesDir=$_filesDir, nativeLibDir=$_nativeLibDir');

        // 0. Remove leftovers of the withdrawn v1.2.211 Ubuntu 24.04 migration
        //    (downloaded image archive). The installed system is left untouched.
        await _cleanupWithdrawnMigrationLeftovers();

        // 1. Prepare base directories and config files first
        await _prepareFileSystem();

        // 2. Always update scripts to ensure they have the latest fixes
        await _ensureBinaries();

        if (File(_nativeRootFlagPath).existsSync()) {
          _useNativeRootMode = true;
          _isInitialized = true;
          _status = 'Ready (Native Root Kernel)';
          _progress = 1.0;
          notifyListeners();
          return;
        }

        // 3. Self-heal a rootfs whose arm64 glibc / ELF interpreter was destroyed
        //    (e.g. an interrupted apt libc6 upgrade). Without it every PRoot start fails with
        //    `execve("/usr/bin/env"): Function not implemented`.
        await _repairGuestLibcIfBroken();

        // 4. Ensure terminfo databases are valid and symlinked before any terminal session starts
        await _repairTerminfoIfNeeded();

        // 5. Ensure CA certificate bundle includes Mozilla + Android system roots
        await _repairCaCertificatesIfNeeded();

        final bool complete = await _channel.invokeMethod('isBootstrapComplete');
        if (complete) {
          _isInitialized = true;
          _status = 'Ready';
          _progress = 1.0;
          notifyListeners();
          return;
        }

        await _bootstrapRootfs();

        // Fresh install: configure newly extracted rootfs immediately
        // so the very first terminal session starts fully patched.
        await _prepareFileSystem();
        await _ensureBinaries();
        await _repairTerminfoIfNeeded();
        await _repairCaCertificatesIfNeeded();
      } else {
        // Desktop platform — use a persistent directory in user home
        final desktopDataDir = Directory(PlatformUtils.desktopDataDir);
        if (!desktopDataDir.existsSync()) {
          desktopDataDir.createSync(recursive: true);
        }
        _filesDir = desktopDataDir.path;
        _nativeLibDir = '';
      }

      _isInitialized = true;
      _status = 'Ready';
      _progress = 1.0;
      notifyListeners();
    } catch (e) {
      _status = 'Error: $e';
      debugPrint('RuntimeService Error: $e');
      notifyListeners();
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _acquireCommandSlot() async {
    if (_runningCommands < _maxConcurrentCommands) {
      _runningCommands++;
      return;
    }
    final completer = Completer<void>();
    _commandQueue.add(completer);
    await completer.future;
    _runningCommands++;
  }

  void _releaseCommandSlot() {
    _runningCommands--;
    if (_commandQueue.isNotEmpty) {
      _commandQueue.removeAt(0).complete();
    }
  }

  /// Translates an Android host path to its PRoot guest path (`/root/projects/...`),
  /// or returns [hostPath] unchanged on Desktop or Native Root Kernel mode.
  String toProotPath(String hostPath) {
    if (!Platform.isAndroid || _useNativeRootMode || _filesDir.isEmpty) {
      return hostPath;
    }
    return PathMapper.mapToGuest(hostPath, _filesDir);
  }

  /// Translates any hardcoded Android host paths inside a shell command string
  /// (e.g. `/data/user/0/com.../files/projects/foo`) to their guest equivalents
  /// (`/root/projects/foo`) when running in PRoot mode.
  String translateCommandPaths(String command) {
    if (!Platform.isAndroid || _useNativeRootMode || _filesDir.isEmpty) {
      return command;
    }
    return command
        .replaceAll('$_filesDir/projects', '/root/projects')
        .replaceAll(
          RegExp('/data/(?:user/0|data)/[^/\\s"\']+/files/projects'),
          '/root/projects',
        );
  }

  /// Runs a command and returns structured exit code + stdout/stderr without throwing.
  Future<({int exitCode, String stdout, String stderr, String combined})>
      runCommandDetailed(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    await _acquireCommandSlot();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (Platform.isAndroid) {
          final initHost = p.join(_filesDir, 'bin', 'init-host');
          if (await File(initHost).exists()) {
            final guestCwd = workingDirectory != null
                ? (_useNativeRootMode
                    ? workingDirectory
                    : PathMapper.mapToGuest(workingDirectory, _filesDir))
                : (_useNativeRootMode ? _filesDir : '/root');
            final translatedCmd = translateCommandPaths(command);
            final result = await Process.run(
              'sh',
              [
                initHost,
                _filesDir,
                guestCwd,
                '/bin/bash',
                '-c',
                translatedCmd,
              ],
            ).timeout(
              timeout,
              onTimeout: () => ProcessResult(
                0,
                124,
                '',
                'Command timed out after ${timeout.inSeconds}s: $translatedCmd',
              ),
            );
            final outStr = result.stdout.toString();
            final errStr = result.stderr.toString();
            return (
              exitCode: result.exitCode,
              stdout: outStr,
              stderr: errStr,
              combined: '$outStr$errStr',
            );
          }
        }
        final out =
            await _channel.invokeMethod('runCommand', {'command': command});
        final str = out?.toString() ?? '';
        return (exitCode: 0, stdout: str, stderr: '', combined: str);
      } else {
        String execCommand = command;
        if (Platform.isWindows) {
          execCommand = execCommand
              .replaceAll('2>/dev/null', '2>nul')
              .replaceAll('>/dev/null', '>nul')
              .replaceAll('cd "', 'cd /d "');
        }
        final envMap = desktopEnv;
        final result = await Process.run(
          Platform.isWindows ? 'cmd' : 'bash',
          Platform.isWindows ? ['/c', execCommand] : ['-c', execCommand],
          workingDirectory: workingDirectory,
          environment: envMap,
        ).timeout(
          timeout,
          onTimeout: () => ProcessResult(
            0,
            124,
            '',
            'Command timed out after ${timeout.inSeconds}s: $command',
          ),
        );
        final outStr = result.stdout.toString();
        final errStr = result.stderr.toString();
        return (
          exitCode: result.exitCode,
          stdout: outStr,
          stderr: errStr,
          combined: '$outStr$errStr',
        );
      }
    } finally {
      _releaseCommandSlot();
    }
  }

  Future<String> runCommand(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 90),
    bool throwOnError = true,
  }) async {
    final res = await runCommandDetailed(
      command,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    if (throwOnError && res.exitCode != 0) {
      throw Exception(
        'Command failed (exit code ${res.exitCode}): ${res.combined}',
      );
    }
    return res.combined;
  }

  List<String>? _cachedDiscoveredSdkDirs;

  /// Automatically scans the host system (Linux, macOS, Windows) for installed
  /// Flutter, Dart, Antigravity (agy), Java, Gradle, Android SDK, Node, Python, Rust, and Go toolchains.
  List<String> _discoverDesktopSdkDirs(String home) {
    if (_cachedDiscoveredSdkDirs != null) return _cachedDiscoveredSdkDirs!;
    final sep = Platform.pathSeparator;
    final homes = <String>{
      if (home.isNotEmpty) home,
      ...PlatformUtils.candidateHomeDirs,
    };

    final candidates = <String>[
      ...PlatformUtils.commonBinaryDirs,
      '/opt/flutter/bin',
      '/usr/lib/flutter/bin',
      '/usr/local/flutter/bin',
      '/opt/antigravity/bin',
      '/opt/agy/bin',
      '/snap/bin',
      '/usr/local/go/bin',
      '/opt/android-sdk/cmdline-tools/latest/bin',
      '/opt/android-sdk/platform-tools',
      '/usr/local/lib/nodejs/bin',
      '/usr/local/sbin',
      '/usr/local/bin',
      '/usr/sbin',
      '/usr/bin',
      '/sbin',
      '/bin',
    ];

    for (final h in homes) {
      candidates.addAll([
        '$h$sep.local${sep}bin',
        '$h${sep}bin',
        '$h$sep.agy${sep}bin',
        '$h$sep.antigravity${sep}bin',
        '$h$sep.gemini${sep}antigravity${sep}bin',
        '$h$sep.gemini${sep}bin',
        '$h${sep}flutter${sep}bin',
        '$h${sep}development${sep}flutter${sep}bin',
        '$h${sep}dev${sep}flutter${sep}bin',
        '$h${sep}sdk${sep}flutter${sep}bin',
        '$h${sep}tools${sep}flutter${sep}bin',
        '$h${sep}fvm${sep}default${sep}bin',
        '$h$sep.fvm${sep}default${sep}bin',
        '$h$sep.local${sep}share${sep}flutter${sep}bin',
        '$h${sep}snap${sep}flutter${sep}common${sep}flutter${sep}bin',
        '$h$sep.pub-cache${sep}bin',
        '$h$sep.npm-global${sep}bin',
        '$h$sep.yarn${sep}bin',
        '$h$sep.local${sep}share${sep}pnpm',
        '$h$sep.cargo${sep}bin',
        '$h${sep}go${sep}bin',
        '$h$sep.bun${sep}bin',
        '$h$sep.volta${sep}bin',
        '$h$sep.pyenv${sep}shims',
        '$h$sep.sdkman${sep}candidates${sep}java${sep}current${sep}bin',
        '$h$sep.sdkman${sep}candidates${sep}gradle${sep}current${sep}bin',
        '$h${sep}Android${sep}Sdk${sep}cmdline-tools${sep}latest${sep}bin',
        '$h${sep}Android${sep}Sdk${sep}platform-tools',
        if (Platform.isWindows) ...[
          r'C:\src\flutter\bin',
          r'C:\flutter\bin',
          r'C:\tools\flutter\bin',
          '$h\\AppData\\Local\\Pub\\Cache\\bin',
          '$h\\AppData\\Local\\Android\\Sdk\\platform-tools',
          '$h\\AppData\\Local\\Android\\Sdk\\cmdline-tools\\latest\\bin',
          '$h\\AppData\\Roaming\\npm',
        ],
      ]);

      for (final nvmRoot in [
        '$h/.nvm/versions/node',
        '$h/.config/nvm/versions/node',
        '$h/.local/share/fnm/node-versions',
      ]) {
        try {
          final dir = Directory(nvmRoot);
          if (dir.existsSync()) {
            final versions = dir
                .listSync()
                .whereType<Directory>()
                .map((d) => d.path)
                .toList()
              ..sort((a, b) => b.compareTo(a));
            for (final v in versions) {
              candidates.add('$v/bin');
              candidates.add('$v/installation/bin');
            }
          }
        } catch (_) {}
      }

      // Scan 1 level deep in each home dir for custom folders containing flutter/bin or bin/agy
      try {
        final homeDir = Directory(h);
        if (homeDir.existsSync()) {
          for (final entity in homeDir.listSync(followLinks: false)) {
            if (entity is Directory) {
              final base = p.basename(entity.path);
              if (base.startsWith('.')) continue;
              final subFlutter = p.join(entity.path, 'flutter', 'bin');
              if (Directory(subFlutter).existsSync()) {
                candidates.insert(0, subFlutter);
              }
              final subBin = p.join(entity.path, 'bin');
              if (File(p.join(subBin, 'agy')).existsSync() ||
                  File(p.join(subBin, 'flutter')).existsSync()) {
                candidates.insert(0, subBin);
              }
            }
          }
        }
      } catch (_) {}
    }

    final seen = <String>{};
    final existing = <String>[];
    for (final dir in candidates) {
      if (dir.isNotEmpty && seen.add(dir) && Directory(dir).existsSync()) {
        existing.add(dir);
      }
    }
    _cachedDiscoveredSdkDirs = existing;
    return existing;
  }

  /// Desktop environment with a PATH that automatically includes all discovered
  /// Flutter, Dart, Antigravity (agy), Android SDK, Node, Python, Rust, and Go toolchains.
  Map<String, String> get desktopEnv {
    final env = Map<String, String>.from(Platform.environment);
    final home = env['HOME'] ?? env['USERPROFILE'] ?? PlatformUtils.userHomeDir;
    final extra = _discoverDesktopSdkDirs(home);
    final sep = Platform.isWindows ? ';' : ':';
    final current =
        env['PATH'] ?? (Platform.isWindows ? '' : '/usr/local/bin:/usr/bin:/bin');
    final currentParts = current.split(sep).where((e) => e.isNotEmpty).toList();
    final merged = <String>[
      ...extra,
      ...currentParts.where((c) => !extra.contains(c)),
    ];
    env['PATH'] = merged.join(sep);
    env['TERM'] = 'xterm-256color';
    env['COLORTERM'] = 'truecolor';
    env.putIfAbsent('LANG', () => 'C.UTF-8');
    env.putIfAbsent('LC_ALL', () => 'C.UTF-8');
    return env;
  }

  /// Runs [command] and streams its output line by line while it runs.
  ///
  /// [onLine] receives each line. `isError` is true for stderr; `replace` is
  /// true for progress updates (text after a carriage return) that should
  /// overwrite the previous progress line instead of being appended.
  /// [stdinData] (optional) is written to stdin right after start (e.g. sudo password).
  StreamingCommand runCommandStream(
    String command, {
    String? workingDirectory,
    required void Function(String line, {bool isError, bool replace}) onLine,
    String? stdinData,
  }) {
    final handle = StreamingCommand._();
    handle._exitCode = _startStreaming(handle, command, workingDirectory, onLine, stdinData);
    return handle;
  }

  Future<int> _startStreaming(
    StreamingCommand handle,
    String command,
    String? workingDirectory,
    void Function(String line, {bool isError, bool replace}) onLine,
    String? stdinData,
  ) async {
    Process process;
    if (Platform.isAndroid || Platform.isIOS) {
      final initHost = p.join(_filesDir, 'bin', 'init-host');
      if (!Platform.isAndroid || !await File(initHost).exists()) {
        // No PRoot launcher available: fall back to the blocking native channel.
        try {
          final String out = await _channel.invokeMethod('runCommand', {'command': command});
          for (final l in const LineSplitter().convert(out)) {
            onLine(l);
          }
          return 0;
        } catch (e) {
          onLine('$e', isError: true);
          return 1;
        }
      }
      final guestCwd = workingDirectory != null
          ? (_useNativeRootMode
              ? workingDirectory
              : PathMapper.mapToGuest(workingDirectory, _filesDir))
          : (_useNativeRootMode ? p.join(_filesDir, 'home') : '/root');
      final translatedCmd = translateCommandPaths(command);
      process = await Process.start(
        'sh',
        [initHost, _filesDir, guestCwd, '/bin/bash', '-c', translatedCmd],
      );
    } else {
      process = await Process.start(
        Platform.isWindows ? 'cmd' : 'bash',
        Platform.isWindows ? ['/c', command] : ['-c', command],
        workingDirectory: workingDirectory,
        environment: desktopEnv,
      );
    }
    handle._process = process;

    if (stdinData != null) {
      process.stdin.writeln(stdinData);
    }
    try {
      await process.stdin.flush();
      await process.stdin.close();
    } catch (_) {}

    final outDone = _pipeLines(process.stdout, (l, {bool replace = false}) => onLine(l, isError: false, replace: replace));
    final errDone = _pipeLines(process.stderr, (l, {bool replace = false}) => onLine(l, isError: true, replace: replace));
    final code = await process.exitCode;
    await Future.wait([outDone, errDone]).timeout(const Duration(seconds: 2), onTimeout: () => []);
    return code;
  }

  static final _ansiRegex = RegExp(r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07|[()][A-Za-z0-9])');

  /// Splits a byte stream into lines. Text following a lone `\r` (curl/apt/npm
  /// progress bars) is reported with `replace: true`.
  Future<void> _pipeLines(Stream<List<int>> stream, void Function(String, {bool replace}) emit) {
    final done = Completer<void>();
    var buffer = '';
    var lastWasProgress = false;
    stream.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
      buffer += chunk;
      while (true) {
        final nl = buffer.indexOf('\n');
        if (nl < 0) break;
        var line = buffer.substring(0, nl);
        buffer = buffer.substring(nl + 1);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        final cr = line.lastIndexOf('\r');
        if (cr >= 0) line = line.substring(cr + 1);
        if (line.isEmpty && lastWasProgress) {
          // The newline just finalizes the last progress line.
          lastWasProgress = false;
          continue;
        }
        emit(line.replaceAll(_ansiRegex, ''), replace: lastWasProgress);
        lastWasProgress = false;
      }
      final cr = buffer.lastIndexOf('\r');
      if (cr >= 0) {
        final progress = buffer.substring(cr + 1).replaceAll(_ansiRegex, '');
        final before = buffer.substring(0, cr);
        final prevCr = before.lastIndexOf('\r');
        final shown = progress.trim().isNotEmpty ? progress : before.substring(prevCr + 1);
        if (shown.trim().isNotEmpty) {
          emit(shown.replaceAll(_ansiRegex, ''), replace: lastWasProgress);
          lastWasProgress = true;
        }
        buffer = progress;
      }
    }, onDone: () {
      if (buffer.trim().isNotEmpty) emit(buffer.replaceAll(_ansiRegex, ''), replace: lastWasProgress);
      done.complete();
    }, onError: (_) {
      if (!done.isCompleted) done.complete();
    }, cancelOnError: false);
    return done.future;
  }

  /// Size of [guestPath] inside the rootfs, following symlinks as the *guest* sees them
  /// (absolute targets are resolved against the rootfs, not the Android filesystem).
  /// Returns -1 when the file is missing or the link chain is broken.
  int _guestFileSize(String rootfs, String guestPath) {
    var current = guestPath;
    for (var i = 0; i < 12; i++) {
      final host = p.join(rootfs, current.substring(1));
      final type = FileSystemEntity.typeSync(host, followLinks: false);
      if (type == FileSystemEntityType.link) {
        final target = Link(host).targetSync();
        current = target.startsWith('/')
            ? target
            : p.normalize(p.join(p.dirname(current), target));
        continue;
      }
      if (type == FileSystemEntityType.file) return File(host).lengthSync();
      return -1;
    }
    return -1;
  }

  bool _isGuestUbuntu2404(String rootfs) {
    final osRelease = File(p.join(rootfs, 'etc', 'os-release'));
    if (!osRelease.existsSync()) return false;
    try {
      final content = osRelease.readAsStringSync();
      return content.contains('24.04') || content.contains('noble');
    } catch (_) {
      return false;
    }
  }

  void _copyEntitySync(FileSystemEntity entity, String destPath) {
    if (entity is Link) {
      final existing = FileSystemEntity.typeSync(destPath, followLinks: false);
      if (existing == FileSystemEntityType.link) {
        Link(destPath).deleteSync();
      } else if (existing == FileSystemEntityType.file) {
        File(destPath).deleteSync();
      } else if (existing != FileSystemEntityType.notFound) {
        return;
      }
      Link(destPath).parent.createSync(recursive: true);
      Link(destPath).createSync(entity.targetSync());
    } else if (entity is File) {
      File(destPath).parent.createSync(recursive: true);
      if (FileSystemEntity.typeSync(destPath, followLinks: false) == FileSystemEntityType.link) {
        Link(destPath).deleteSync();
      }
      entity.copySync(destPath);
    } else if (entity is Directory) {
      final existing = FileSystemEntity.typeSync(destPath, followLinks: false);
      if (existing == FileSystemEntityType.link || existing == FileSystemEntityType.file) {
        return;
      }
      Directory(destPath).createSync(recursive: true);
      for (final child in entity.listSync(followLinks: false)) {
        _copyEntitySync(child, p.join(destPath, p.basename(child.path)));
      }
    }
  }

  /// True when the native arm64 glibc of the Ubuntu rootfs is unusable. PRoot then reports
  /// `execve("/usr/bin/env"): Function not implemented` or `version 'GLIBC_2.38' not found`.
  bool isGuestLibcBroken() {
    if (!Platform.isAndroid) return false;
    final rootfs = p.join(_filesDir, 'rootfs', 'ubuntu');
    if (!Directory(rootfs).existsSync()) return false;

    // Detect broken usrmerge `/lib -> usr/lib` symlink on Ubuntu 24.04+
    // (including when an earlier repair wrote Ubuntu 20.04 glibc 2.31 into a plain `/lib` dir).
    final libEntry = p.join(rootfs, 'lib');
    final usrLibc = File(p.join(rootfs, 'usr', 'lib', 'aarch64-linux-gnu', 'libc.so.6'));
    if (usrLibc.existsSync() &&
        FileSystemEntity.typeSync(libEntry, followLinks: false) != FileSystemEntityType.link) {
      return true;
    }

    if (_isGuestUbuntu2404(rootfs)) {
      if (FileSystemEntity.typeSync(p.join(rootfs, 'lib', 'ld-2.31.so'), followLinks: false) !=
              FileSystemEntityType.notFound ||
          FileSystemEntity.typeSync(
                  p.join(rootfs, 'lib', 'aarch64-linux-gnu', 'libc-2.31.so'),
                  followLinks: false) !=
              FileSystemEntityType.notFound) {
        return true;
      }
    }

    return _guestFileSize(rootfs, '/lib/ld-linux-aarch64.so.1') <= 0 ||
        _guestFileSize(rootfs, '/lib/aarch64-linux-gnu/libc.so.6') <= 0;
  }

  bool _libcRepairRunning = false;

  /// Restores `/lib` of the rootfs (usrmerge `/lib -> usr/lib` offline first on Ubuntu 24.04+,
  /// falling back to Ubuntu 20.04 arm64 `libc6` only on non-24.04 rootfs). Extraction is done on
  /// the Android side so it works even though nothing can execute inside the broken rootfs.
  Future<bool> _repairGuestLibcIfBroken() async {
    if (_libcRepairRunning) return false;
    try {
      if (!isGuestLibcBroken()) return true;
      _libcRepairRunning = true;
      final rootfs = p.join(_filesDir, 'rootfs', 'ubuntu');

      // Fast offline repair for usrmerged Ubuntu (24.04+): if dpkg -x of a legacy .deb
      // overwrote `/lib` symlink with a plain directory (or an older repair placed 2.31 inside `/lib`),
      // `/usr/lib/aarch64-linux-gnu` still holds the intact glibc 2.39 binaries.
      final usrLibAarch64 = Directory(p.join(rootfs, 'usr', 'lib', 'aarch64-linux-gnu'));
      final usrLibc = File(p.join(usrLibAarch64.path, 'libc.so.6'));
      final libEntry = p.join(rootfs, 'lib');
      final libType = FileSystemEntity.typeSync(libEntry, followLinks: false);
      if (await usrLibc.exists() && libType != FileSystemEntityType.link) {
        debugPrint('RuntimeService: repairing broken usrmerge /lib -> usr/lib symlink...');
        _status = 'Восстановление системных библиотек (/lib → usr/lib)…';
        notifyListeners();

        final usrLd = p.join(rootfs, 'usr', 'lib', 'ld-linux-aarch64.so.1');
        if (!File(usrLd).existsSync()) {
          final aarch64Ld = File(p.join(usrLibAarch64.path, 'ld-linux-aarch64.so.1'));
          if (await aarch64Ld.exists()) {
            final existingLdType = FileSystemEntity.typeSync(usrLd, followLinks: false);
            if (existingLdType == FileSystemEntityType.link) {
              await Link(usrLd).delete();
            } else if (existingLdType == FileSystemEntityType.file) {
              await File(usrLd).delete();
            }
            await Link(usrLd).create('aarch64-linux-gnu/ld-linux-aarch64.so.1');
          }
        }

        if (libType == FileSystemEntityType.directory) {
          for (final child in Directory(libEntry).listSync(followLinks: false)) {
            final name = p.basename(child.path);
            // Never copy downgraded 20.04 glibc 2.31 artifacts into /usr/lib
            if (name == 'aarch64-linux-gnu' ||
                name == 'ld-linux-aarch64.so.1' ||
                name.contains('2.31')) {
              continue;
            }
            final destPath = p.join(rootfs, 'usr', 'lib', name);
            if (name == 'x86_64-linux-gnu' ||
                FileSystemEntity.typeSync(destPath, followLinks: false) ==
                    FileSystemEntityType.notFound) {
              _copyEntitySync(child, destPath);
            }
          }
          await _forceDeleteDirectory(Directory(libEntry));
        } else if (libType == FileSystemEntityType.file) {
          await File(libEntry).delete();
        }

        await Link(libEntry).create('usr/lib');
        if (!isGuestLibcBroken()) {
          debugPrint('RuntimeService: offline /lib -> usr/lib repair succeeded');
          _status = 'Системные библиотеки восстановлены';
          notifyListeners();
          return true;
        }
      }

      if (_isGuestUbuntu2404(rootfs)) {
        debugPrint('RuntimeService: Ubuntu 24.04 glibc cannot be repaired with 20.04 libc6_2.31');
        _status = 'Повреждён glibc Ubuntu 24.04 — выполните сброс Ubuntu в настройках';
        notifyListeners();
        return false;
      }

      debugPrint('RuntimeService: guest glibc is broken, restoring libc6 (arm64)…');
      _status = 'Восстановление системных библиотек (glibc)…';
      notifyListeners();

      const debName = 'libc6_2.31-0ubuntu9.18_arm64.deb';
      final urls = [
        'http://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/$debName',
        'https://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/$debName',
        'http://mirrors.ustc.edu.cn/ubuntu-ports/pool/main/g/glibc/$debName',
        'http://mirror.yandex.ru/ubuntu-ports/pool/main/g/glibc/$debName',
      ];

      List<int>? deb;
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 3),
      ));
      for (final url in urls) {
        try {
          final res = await dio.get<List<int>>(
            url,
            options: Options(responseType: ResponseType.bytes),
          );
          if (res.statusCode == 200 && res.data != null && res.data!.length > 500000) {
            deb = res.data;
            break;
          }
        } catch (e) {
          debugPrint('RuntimeService: libc6 download failed from $url: $e');
        }
      }
      if (deb == null) {
        _status = 'Не удалось скачать libc6 (нужен интернет)';
        notifyListeners();
        return false;
      }

      // .deb = `ar` archive: "!<arch>\n" + [60-byte header + body (+1 pad byte if odd)]…
      List<int>? dataTarXz;
      var pos = 8;
      while (pos + 60 <= deb.length) {
        final name = ascii.decode(deb.sublist(pos, pos + 16), allowInvalid: true).trim();
        final size = int.parse(ascii.decode(deb.sublist(pos + 48, pos + 58)).trim());
        pos += 60;
        if (name.startsWith('data.tar.xz')) {
          dataTarXz = deb.sublist(pos, pos + size);
          break;
        }
        pos += size + (size & 1);
      }
      if (dataTarXz == null) {
        debugPrint('RuntimeService: data.tar.xz not found in $debName');
        return false;
      }

      final archive = TarDecoder().decodeBytes(XZDecoder().decodeBytes(dataTarXz));
      final libIsSymlink = FileSystemEntity.typeSync(libEntry, followLinks: false) == FileSystemEntityType.link;
      var restored = 0;
      for (final entry in archive) {
        var rel = entry.name.replaceFirst(RegExp(r'^\./'), '');
        if (!rel.startsWith('lib/') || rel.contains('..')) continue;
        if (libIsSymlink) {
          rel = 'usr/$rel';
        }
        final dest = p.join(rootfs, rel);
        if (!entry.isFile && !entry.isSymbolicLink) {
          await Directory(dest).create(recursive: true);
          continue;
        }
        await Directory(p.dirname(dest)).create(recursive: true);
        if (entry.isSymbolicLink) {
          final existing = FileSystemEntity.typeSync(dest, followLinks: false);
          if (existing == FileSystemEntityType.link) {
            await Link(dest).delete();
          } else if (existing == FileSystemEntityType.file) {
            await File(dest).delete();
          }
          await Link(dest).create(entry.symbolicLink!);
        } else {
          if (FileSystemEntity.typeSync(dest, followLinks: false) == FileSystemEntityType.link) {
            await Link(dest).delete();
          }
          await File(dest).writeAsBytes(entry.content as List<int>, flush: true);
          await Process.run('chmod', [(entry.mode & 0x40) != 0 ? '755' : '644', dest]);
        }
        restored++;
      }
      debugPrint('RuntimeService: restored $restored glibc entries');
      final ok = !isGuestLibcBroken();
      _status = ok ? 'Системные библиотеки восстановлены' : 'Не удалось восстановить glibc';
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint('RuntimeService: glibc repair failed: $e');
      return false;
    } finally {
      _libcRepairRunning = false;
    }
  }

  /// Public entry point (used by the "Repair environment" action).
  Future<bool> repairGuestLibc() => _repairGuestLibcIfBroken();

  Future<void> _prepareFileSystem() async {
    try {
      // 1. Ensure the root files directory exists
      final rootDir = Directory(_filesDir);
      if (!await rootDir.exists()) {
        await rootDir.create(recursive: true);
      }

      // 2. Create subdirectories one by one
      final dirs = ['bin', 'tmp', 'projects', 'config'];
      for (final name in dirs) {
        final dirPath = p.join(_filesDir, name);
        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          debugPrint('Creating directory: $dirPath');
          await dir.create(recursive: true);
        }
      }

      // 3. Create resolv.conf with atomic verification
      //    Must handle the case where resolv.conf is a broken symlink
      //    (e.g. -> ../run/systemd/resolve/stub-resolv.conf which doesn't exist in Android)
      final configDirPath = p.join(_filesDir, 'config');
      final configDir = Directory(configDirPath);
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      final resolvPath = p.join(configDirPath, 'resolv.conf');
      await _writeResolvConf(resolvPath);

      // Also ensure tmp/resolv.conf (used by init-host bind mount) is correct
      final tmpResolvPath = p.join(_filesDir, 'tmp', 'resolv.conf');
      await _writeResolvConf(tmpResolvPath);

      // 3b. Ensure /etc/hosts and /etc/nsswitch.conf provide localhost resolution
      //     (required by Go binaries like `agy` so they don't query `localhost` on 8.8.8.8:53).
      await _writeHostsFile(p.join(configDirPath, 'hosts'));
      await _writeHostsFile(p.join(_filesDir, 'tmp', 'hosts'));
      await _writeNsswitchConf(p.join(configDirPath, 'nsswitch.conf'));
      await _writeNsswitchConf(p.join(_filesDir, 'tmp', 'nsswitch.conf'));
      final guestEtcDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'etc'));
      if (await guestEtcDir.exists()) {
        await _writeHostsFile(p.join(guestEtcDir.path, 'hosts'), onlyIfMissingLocalhost: true);
        await _writeNsswitchConf(p.join(guestEtcDir.path, 'nsswitch.conf'), onlyIfMissingFiles: true);
      }

      // 4. Set permissions for tmp
      final tmpPath = p.join(_filesDir, 'tmp');
      if (await Directory(tmpPath).exists()) {
        await Process.run('chmod', [
          '777',
          tmpPath,
        ]).catchError((_) => ProcessResult(0, 0, '', ''));
      }
    } catch (e) {
      debugPrint('FileSystem Preparation error: $e');
    }
  }

  /// Writes a valid hosts file with `127.0.0.1 localhost`, replacing broken symlinks first.
  Future<void> _writeHostsFile(String path, {bool onlyIfMissingLocalhost = false}) async {
    try {
      final dir = Directory(p.dirname(path));
      if (!await dir.exists()) await dir.create(recursive: true);

      final isLink = FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.link;
      if (isLink) {
        await Link(path).delete();
      } else if (onlyIfMissingLocalhost && await File(path).exists()) {
        final existing = await File(path).readAsString().catchError((_) => '');
        if (RegExp(r'127\.0\.0\.1\s+localhost').hasMatch(existing)) {
          return;
        }
      }

      await File(path).writeAsString(
        '127.0.0.1 localhost localhost.localdomain quantum-ide\n'
        '::1 localhost ip6-localhost ip6-loopback\n',
        flush: true,
      );
      await Process.run('chmod', ['644', path]).catchError((_) => ProcessResult(0, 0, '', ''));
    } catch (e) {
      debugPrint('Warning: Failed to write hosts at $path: $e');
    }
  }

  /// Writes an nsswitch.conf that prefers `files` before `dns` so `localhost` resolves locally.
  Future<void> _writeNsswitchConf(String path, {bool onlyIfMissingFiles = false}) async {
    try {
      final dir = Directory(p.dirname(path));
      if (!await dir.exists()) await dir.create(recursive: true);

      final isLink = FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.link;
      if (isLink) {
        await Link(path).delete();
      } else if (onlyIfMissingFiles && await File(path).exists()) {
        final existing = await File(path).readAsString().catchError((_) => '');
        if (RegExp(r'^\s*hosts:\s*files\b', multiLine: true).hasMatch(existing)) {
          return;
        }
      }

      await File(path).writeAsString(
        'passwd: files\n'
        'group: files\n'
        'shadow: files\n'
        'hosts: files dns\n'
        'networks: files\n'
        'protocols: files\n'
        'services: files\n'
        'ethers: files\n'
        'rpc: files\n',
        flush: true,
      );
      await Process.run('chmod', ['644', path]).catchError((_) => ProcessResult(0, 0, '', ''));
    } catch (e) {
      debugPrint('Warning: Failed to write nsswitch.conf at $path: $e');
    }
  }

  /// Writes a correct resolv.conf, removing broken symlinks first.
  /// This is critical because Ubuntu rootfs may ship with a symlink to
  /// /run/systemd/resolve/stub-resolv.conf which doesn't exist on Android,
  /// causing all DNS resolution inside PRoot to fail silently.
  Future<void> _writeResolvConf(String path) async {
    try {
      final dir = Directory(p.dirname(path));
      if (!await dir.exists()) await dir.create(recursive: true);

      // If it's a symlink (broken or not), delete it first
      final link = Link(path);
      if (await link.exists() || FileSystemEntity.typeSync(path) == FileSystemEntityType.link) {
        await link.delete();
        debugPrint('resolv.conf: removed broken symlink at $path');
      }

      await File(path).writeAsString(
        'nameserver 8.8.8.8\nnameserver 1.1.1.1\n',
        flush: true,
      );
      debugPrint('resolv.conf: written at $path');
    } catch (e) {
      debugPrint('Warning: Failed to write resolv.conf at $path: $e');
    }
  }

  Future<void> _ensureBinaries() async {
    try {
      // Ensure resolv.conf, hosts, and nsswitch.conf exist in tmp (used by init-host bind mounts)
      // Always rewrite on cold start to heal broken symlinks or missing localhost mappings.
      final tmpDir = Directory(p.join(_filesDir, 'tmp'));
      if (!await tmpDir.exists()) await tmpDir.create(recursive: true);
      await _writeResolvConf(p.join(tmpDir.path, 'resolv.conf'));
      await _writeHostsFile(p.join(tmpDir.path, 'hosts'));
      await _writeNsswitchConf(p.join(tmpDir.path, 'nsswitch.conf'));
    } catch (e) {
      debugPrint('Warning: Failed to ensure resolv/hosts in tmp: $e');
    }

    try {
      final binDir = Directory(p.join(_filesDir, 'bin'));
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }

      final file = File(p.join(binDir.path, 'init-host'));
      await file.writeAsString(_generateInitHostScript().replaceAll('\r', ''));
      await Process.run('chmod', ['755', file.path]);
    } catch (e) {
      debugPrint('Warning: Failed to ensure init-host script: $e');
    }

    try {
      final setupFile =
          File(p.join(_filesDir, 'rootfs', 'ubuntu', 'root', 'setup-arm64.sh'));
      if (await setupFile.parent.exists()) {
        await setupFile.writeAsString(
          _generateSetupArm64Script().replaceAll('\r', ''),
        );
      }
      final patchNdkScript = _generateQuantumPatchNdkScript().replaceAll('\r', '');
      final patchNdkTargets = [
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'local', 'bin', 'quantum-patch-ndk'),
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'bin', 'quantum-patch-ndk'),
        '/usr/local/bin/quantum-patch-ndk',
        '/usr/bin/quantum-patch-ndk',
      ];
      for (final targetPath in patchNdkTargets) {
        try {
          final f = File(targetPath);
          if (await f.parent.exists()) {
            await f.writeAsString(patchNdkScript);
            await Process.run('chmod', ['755', targetPath]);
          }
        } catch (_) {}
      }
      final healX64Script = _generateQuantumHealX64Script().replaceAll('\r', '');
      final healX64Targets = [
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'local', 'bin', 'quantum-heal-x64'),
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'bin', 'quantum-heal-x64'),
        '/usr/local/bin/quantum-heal-x64',
        '/usr/bin/quantum-heal-x64',
      ];
      for (final targetPath in healX64Targets) {
        try {
          final f = File(targetPath);
          if (await f.parent.exists()) {
            await f.writeAsString(healX64Script);
            await Process.run('chmod', ['755', targetPath]);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Warning: Failed to write setup-arm64.sh / quantum-patch-ndk / quantum-heal-x64: $e');
    }

    try {
      await _ensureAndroidLicenses();
    } catch (e) {
      debugPrint('Warning: Failed to ensure android licenses: $e');
    }

    try {
      await _ensureBundledAapt2();
    } catch (e) {
      debugPrint('Warning: Failed to ensure bundled aapt2: $e');
    }

    try {
      await _ensureBundledRuri();
    } catch (e) {
      debugPrint('Warning: Failed to ensure bundled ruri: $e');
    }

      // Enhanced .bashrc with robust PATH, Ubuntu prompt and greeting
      // Written if missing OR if version tag has changed (to push updates to users)
    final bashrc = File(
      p.join(_filesDir, 'rootfs', 'ubuntu', 'root', '.bashrc'),
    );

    // Version tag — increment this when you need to push bashrc updates to all users
    const bashrcVersion = '36';
    const bashrcVersionLine = '# BASHRC_VERSION=$bashrcVersion';

    bool needsWrite = true;
    if (await bashrc.exists()) {
      try {
        final content = await bashrc.readAsString();
        needsWrite = !content.contains(bashrcVersionLine);
      } catch (_) {
        needsWrite = true;
      }
    }

    if (needsWrite) {
      final termFetchScript = _generateTermFetchScript().replaceAll('\r', '');

      // 1. Write standalone term-fetch executable
      final termFetchTargets = [
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'local', 'bin', 'term-fetch'),
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'bin', 'term-fetch'),
        '/usr/local/bin/term-fetch',
        '/usr/bin/term-fetch',
      ];
      for (final targetPath in termFetchTargets) {
        try {
          final f = File(targetPath);
          if (await f.parent.exists()) {
            await f.writeAsString(termFetchScript);
            await Process.run('chmod', ['755', targetPath]);
          }
        } catch (_) {}
      }

      const bashrcContent = r'''
# BASHRC_VERSION=36
export ANDROID_HOME=/root/android-sdk
export ANDROID_SDK_ROOT=/root/android-sdk
# Dynamically detect JAVA_HOME inside guest (prefer Java 17 / 21)
if [ -d "/root/jdk-17" ]; then
    export JAVA_HOME="/root/jdk-17"
elif [ -d "/usr/lib/jvm/java-17-openjdk-arm64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
elif [ -d "/usr/lib/jvm/java-21-openjdk-arm64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-arm64"
else
    DETECTED_JVM=$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | grep -E '17|21' | head -n 1)
    [ -z "$DETECTED_JVM" ] && DETECTED_JVM=$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)
    if [ -n "$DETECTED_JVM" ]; then
        export JAVA_HOME="$DETECTED_JVM"
    else
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
    fi
fi
if [ -d "$JAVA_HOME" ] && ! grep -q "$JAVA_HOME" /root/.config/flutter/settings 2>/dev/null; then
    mkdir -p /root/.config/flutter 2>/dev/null || true
    if [ ! -f /root/.config/flutter/settings ]; then
        printf '{"jdk-dir":"%s"}\n' "$JAVA_HOME" > /root/.config/flutter/settings 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import json; p='/root/.config/flutter/settings'; d=json.load(open(p)) if open(p).read().strip() else {}; d['jdk-dir']='$JAVA_HOME'; json.dump(d, open(p, 'w'))" 2>/dev/null || true
    fi
fi
export PATH=$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.bun/bin:/usr/local/bin:/usr/local/lib/nodejs/bin:/root/.local/bin:$PATH

# Auto-detect terminal capability and heal missing terminfo
[ -d /lib/terminfo ] && [ ! -d /usr/share/terminfo/x ] && ln -sf /lib/terminfo/* /usr/share/terminfo/ 2>/dev/null || true
[ -d /usr/share/terminfo ] && [ ! -d /lib/terminfo/x ] && ln -sf /usr/share/terminfo/* /lib/terminfo/ 2>/dev/null || true
export TERMINFO_DIRS=/usr/share/terminfo:/lib/terminfo:/etc/terminfo
if [ -e /usr/share/terminfo/x/xterm-256color ] || [ -e /lib/terminfo/x/xterm-256color ] || [ -e /etc/terminfo/x/xterm-256color ]; then
    export TERM=xterm-256color
elif [ -e /usr/share/terminfo/x/xterm ] || [ -e /lib/terminfo/x/xterm ] || [ -e /etc/terminfo/x/xterm ]; then
    export TERM=xterm
elif [ -e /usr/share/terminfo/l/linux ] || [ -e /lib/terminfo/l/linux ]; then
    export TERM=linux
else
    export TERM=xterm-256color
fi
export COLORTERM=truecolor
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
if [ -s /etc/ssl/certs/ca-certificates.crt ]; then
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
elif [ -s /etc/pki/tls/certs/ca-bundle.crt ]; then
    export SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
else
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
fi
export SSL_CERT_DIR=/etc/ssl/certs
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
export CURL_CA_BUNDLE="$SSL_CERT_FILE"
export NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE"
export GIT_SSL_CAINFO="$SSL_CERT_FILE"
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoredups:erasedups

# Ensure output newline translates to CR+NL, set UTF-8 TTY mode (iutf8 for proper Russian Backspace)
stty sane onlcr icrnl opost erase ^? iutf8 2>/dev/null || true
shopt -s checkwinsize 2>/dev/null || true

export EDITOR=nano
export VISUAL=nano
export PAGER=less

# Zero-fork pure-bash git branch prompt using PROMPT_COMMAND for 100% precise readline cursor tracking
__update_quantum_ps1() {
    local b=""
    if [ -f ".git/HEAD" ]; then
        local head_ref
        read -r head_ref < ".git/HEAD" 2>/dev/null
        b="${head_ref#ref: refs/heads/}"
    fi
    if [ -n "$b" ]; then
        PS1="\[\033[1;36m\]\W\[\033[0m\] \[\033[35m\]git:(\[\033[1;31m\]$b\[\033[35m\])\[\033[0m\] \[\033[1;34m\]\$ \[\033[0m\]"
    else
        PS1="\[\033[1;36m\]\W\[\033[0m\] \[\033[1;34m\]\$ \[\033[0m\]"
    fi
}
PROMPT_COMMAND="__update_quantum_ps1"

export FLUTTER_ALLOW_SU_ROOT=1
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
_JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
export _JAVA_OPTIONS
GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.enableJetifier=false"
export GRADLE_OPTS
export DART_VM_OPTIONS="--old_gen_heap_size=768"

alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias lg="lazygit"
export EDITOR=micro
export VISUAL=micro
alias fb-apk="flutter build apk --debug"
alias fb-apk-release="flutter build apk --release"
alias fb-bundle="flutter build appbundle --release"
alias fb-appbundle="flutter build appbundle --release"
alias build-apk="flutter build apk --release"
alias build-arm64="flutter build apk --release --target-platform android-arm64"
alias build-arm32="flutter build apk --release --target-platform android-arm"
alias build-x64="flutter build apk --release --target-platform android-x64"
alias build-aab="flutter build appbundle --release"
alias fb-arm64="flutter build apk --release --target-platform android-arm64"
alias fb-arm32="flutter build apk --release --target-platform android-arm"
alias fb-x64="flutter build apk --release --target-platform android-x64"
alias fb-aab="flutter build appbundle --release"
alias build-apk-split="flutter build apk --release --split-per-abi"
alias fb-apk-split="flutter build apk --release --split-per-abi"
alias build-apk-all="flutter build apk --release --split-per-abi"
alias build-app="flutter build apk --release"
alias build-bundle="flutter build appbundle --release"
alias f-clean="flutter clean && flutter pub get"
alias f-get="flutter pub get"
alias check-android="flutter doctor -v | grep -A 5 'Android toolchain'"
alias cls="printf '\033[2J\033[H'"
alias clear="printf '\033[2J\033[H'"
alias adb-devices="adb devices -l"
alias adb-install="adb install -r"
alias adb-wifi="adb tcpip 5555"
alias fastboot-devices="fastboot devices"
alias check-usb="lsusb"


# Shared hardware auto-tuner & build-doctor for Flutter, Java, Kotlin, and Gradle builds
_quantum_tune_gradle() {
    pkill -9 -f "dart.*language-server" 2>/dev/null || true
    pkill -9 -f "analysis_server" 2>/dev/null || true
    pkill -9 -f GradleDaemon 2>/dev/null || true
    pkill -9 -f KotlinCompileDaemon 2>/dev/null || true

    # Box64 + glibc anti-fasttop crash protection for x86_64 tools (e.g. Flutter gen_snapshot)
    export BOX64_DYNAREC_STRONGMEM=1
    export BOX64_DYNAREC_BIGBLOCK=0
    export BOX64_DYNAREC_SAFEFLAGS=2
    export BOX64_NOBANNER=1
    export MALLOC_ARENA_MAX=2
    export GLIBC_TUNABLES="glibc.malloc.tcache_count=0:glibc.malloc.arena_max=1"

    # Native C/C++/NDK acceleration (ccache + mold linker if installed)
    if command -v ccache >/dev/null 2>&1; then
        export CCACHE_DIR="/root/.ccache"
        export CMAKE_C_COMPILER_LAUNCHER="ccache"
        export CMAKE_CXX_COMPILER_LAUNCHER="ccache"
    fi
    if command -v mold >/dev/null 2>&1; then
        case " ${LDFLAGS:-} " in
            *"-fuse-ld=mold"*) ;;
            *) export LDFLAGS="${LDFLAGS:+$LDFLAGS }-fuse-ld=mold" ;;
        esac
    fi

    _qt_cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
    [ -z "$_qt_cores" ] || [ "$_qt_cores" -lt 1 ] && _qt_cores=4
    local mem_avail_kb=$(grep 'MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}')
    _qt_mem_mb=$(( ${mem_avail_kb:-2000000} / 1024 ))

    _qt_jvm="1280m"
    _qt_meta="384m"
    _qt_dart="768"
    _qt_workers=2
    _qt_parallel=true

    if [ "$_qt_mem_mb" -ge 6000 ]; then
        _qt_jvm="2560m"; _qt_meta="512m"; _qt_dart="1280"
        if [ "$_qt_cores" -ge 8 ]; then _qt_workers=6
        elif [ "$_qt_cores" -ge 6 ]; then _qt_workers=4
        elif [ "$_qt_cores" -ge 4 ]; then _qt_workers=3
        else _qt_workers=2; fi
    elif [ "$_qt_mem_mb" -ge 3200 ]; then
        _qt_jvm="2048m"; _qt_meta="512m"; _qt_dart="1024"
        if [ "$_qt_cores" -ge 6 ]; then _qt_workers=4
        elif [ "$_qt_cores" -ge 4 ]; then _qt_workers=3
        else _qt_workers=2; fi
    elif [ "$_qt_mem_mb" -ge 2000 ]; then
        _qt_jvm="1280m"; _qt_meta="320m"; _qt_dart="768"
        if [ "$_qt_cores" -ge 6 ]; then _qt_workers=3
        else _qt_workers=2; fi
    elif [ "$_qt_mem_mb" -ge 1400 ]; then
        _qt_jvm="1024m"; _qt_meta="320m"; _qt_dart="640"
        _qt_workers=2; _qt_parallel=false
    else
        _qt_jvm="896m"; _qt_meta="256m"; _qt_dart="512"
        _qt_workers=1; _qt_parallel=false
    fi

    if [ "$QUANTUM_BUILD_PROFILE" = "safe" ]; then
        _qt_jvm="1024m"; _qt_meta="256m"; _qt_dart="640"
        _qt_workers=1
        _qt_parallel=false
    elif [ "$QUANTUM_BUILD_PROFILE" = "turbo" ]; then
        _qt_parallel=true
        [ "$_qt_cores" -ge 4 ] && [ "$_qt_workers" -lt "$_qt_cores" ] && _qt_workers="$_qt_cores"
    fi

    if [ -n "$GRADLE_WORKERS_OVERRIDE" ]; then
        _qt_workers="$GRADLE_WORKERS_OVERRIDE"
    fi

    export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
    export DART_VM_OPTIONS="--old_gen_heap_size=${_qt_dart}"
    export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=${_qt_workers} -Dorg.gradle.parallel=${_qt_parallel} -Dorg.gradle.caching=true -Dkotlin.compiler.execution.strategy=in-process"

    /usr/local/bin/quantum-patch-ndk 2>/dev/null || true
    /usr/local/bin/quantum-heal-x64 2>/dev/null || true

    mkdir -p ~/.gradle /root/.gradle 2>/dev/null || true
    for gp in ~/.gradle/gradle.properties /root/.gradle/gradle.properties android/gradle.properties gradle.properties; do
        if [ -f "$gp" ] || [ "$gp" = ~/.gradle/gradle.properties ] || [ "$gp" = /root/.gradle/gradle.properties ]; then
            [ -d "$(dirname "$gp")" ] || continue
            touch "$gp" 2>/dev/null || continue
            [ -w "$gp" ] || continue
            sed -i '/extra-gen-snapshot-options/d;/org.gradle.jvmargs/d;/kotlin.compiler.execution.strategy/d;/org.gradle.caching/d;/org.gradle.parallel/d;/org.gradle.workers.max/d' "$gp" 2>/dev/null || true
            printf "org.gradle.jvmargs=-Xmx%s -XX:MaxMetaspaceSize=%s -Dfile.encoding=UTF-8\nkotlin.compiler.execution.strategy=in-process\norg.gradle.caching=true\norg.gradle.parallel=%s\norg.gradle.workers.max=%s\n" \
                "$_qt_jvm" "$_qt_meta" "$_qt_parallel" "$_qt_workers" >> "$gp"
            grep -q "org.gradle.daemon" "$gp" 2>/dev/null || echo "org.gradle.daemon=false" >> "$gp"
            grep -q "android.aapt2FromMaven" "$gp" 2>/dev/null || echo "android.aapt2FromMaven=false" >> "$gp"
            grep -q "android.aapt2FromMavenOverride" "$gp" 2>/dev/null || echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> "$gp"
            grep -q "android.aapt2.daemon" "$gp" 2>/dev/null || echo "android.aapt2.daemon=false" >> "$gp"
        fi
    done
}

# gradlew wrapper for Java / Kotlin / Android projects (noexec-safe + Build Doctor + RAM/CPU tuning)
gradlew() {
    _quantum_tune_gradle
    echo -e "\033[1;36m⚡ QuantumIDE Gradle:\033[0m RAM free=${_qt_mem_mb}MB, CPU=${_qt_cores} ядер → jvm=${_qt_jvm}, workers=${_qt_workers}, cache=on..."
    local gflags=(
        "--no-daemon"
        "-Dorg.gradle.caching=true"
        "-Pandroid.aapt2FromMaven=false"
        "-Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2"
        "-Pandroid.aapt2.daemon=false"
    )
    if [ -f "./gradlew" ]; then
        bash ./gradlew "${gflags[@]}" "$@"
    else
        command gradlew "${gflags[@]}" "$@"
    fi
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo -e "\033[1;33m[Build Doctor]\033[0m Проверяю целостность SDK/AAPT2/кэшей после ошибки..."
        /usr/local/bin/quantum-heal-x64 --doctor 2>/dev/null || true
    fi
    return $ret
}

# Flutter build wrapper to auto-ensure ARM64 target, disable daemon, use native aapt2, and auto-heal on crash
flutter() {
    if [ "$1" = "upgrade" ]; then
        if ! grep -qa "GLIBC_2.34" /lib/aarch64-linux-gnu/libc.so.6 /usr/lib/aarch64-linux-gnu/libc.so.6 2>/dev/null; then
            echo "ERROR: Flutter 3.50+ (Dart 3.14) requires GLIBC >= 2.34 (Ubuntu 22.04+/24.04 rootfs)."
            echo "Current rootfs has an older GLIBC; staying on Flutter 3.47.8 to keep SDK functional."
            return 1
        fi
    fi
    local proj_name="$(basename "$PWD")"
    for ext_root in "/sdcard/QuantumIDE/$proj_name" "/storage/emulated/0/QuantumIDE/$proj_name" "/root/projects/external/$proj_name"; do
        if [ -d "$ext_root" ] && [ "$PWD" != "$ext_root" ]; then
            if [ -d "$ext_root/lib" ]; then
                cp -ru "$ext_root/lib/." "./lib/" 2>/dev/null || true
            fi
            for rf in README.md devtools_options.yaml .gitignore pubspec.yaml analysis_options.yaml; do
                if [ -s "$ext_root/$rf" ] && ( [ ! -s "./$rf" ] || [ "$ext_root/$rf" -nt "./$rf" ] ); then
                    cp -f "$ext_root/$rf" "./$rf" 2>/dev/null || true
                fi
            done
            break
        fi
    done

    if [ "$1" = "build" ] && ( [ "$2" = "apk" ] || [ "$2" = "appbundle" ] ); then
        _quantum_tune_gradle

        local has_plat=false
        local has_val=false
        local has_tree=false
        local has_pub=false
        local has_workers=false
        local has_parallel=false
        local has_jvm=false
        local cleaned_args=()
        for a in "$@"; do
            case "$a" in
                -Dorg.gradle.jvmargs=*) has_jvm=true ;;
                *org.gradle.workers.max*) has_workers=true ;;
                *org.gradle.parallel*) has_parallel=true ;;
                *target-platform*|*--split-per-abi*) has_plat=true ;;
                *android-skip-build-dependency-validation*) has_val=true ;;
                *no-tree-shake-icons*) has_tree=true ;;
                *--pub*|*--no-pub*) has_pub=true ;;
            esac
            cleaned_args+=("$a")
        done

        local extra_flags=()
        if [ "$has_plat" = "false" ] && [ "$2" != "appbundle" ]; then
            extra_flags+=("--target-platform" "android-arm64")
        fi
        if [ "$has_val" = "false" ]; then
            extra_flags+=("--android-skip-build-dependency-validation")
        fi
        if [ "$has_tree" = "false" ]; then
            extra_flags+=("--no-tree-shake-icons")
        fi
        if [ "$has_pub" = "false" ] && [ -s ".dart_tool/package_config.json" ]; then
            extra_flags+=("--no-pub")
        fi

        extra_flags+=(
            "-Pandroid.aapt2FromMaven=false"
            "-Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2"
            "-Pandroid.aapt2.daemon=false"
            "-Pandroid.enableJetifier=false"
            "-Porg.gradle.caching=true"
            "-Dorg.gradle.caching=true"
            "-Pkotlin.compiler.execution.strategy=in-process"
            "-Dorg.gradle.daemon=false"
        )
        if [ "$has_workers" = "false" ]; then
            extra_flags+=("-Porg.gradle.workers.max=${_qt_workers}")
        fi
        if [ "$has_parallel" = "false" ]; then
            extra_flags+=("-Porg.gradle.parallel=${_qt_parallel}")
        fi
        if [ "$has_jvm" = "false" ]; then
            extra_flags+=("-Dorg.gradle.jvmargs=-Xmx${_qt_jvm} -XX:MaxMetaspaceSize=${_qt_meta}")
        fi

        echo -e "\033[1;36m⚡ QuantumIDE Engine:\033[0m сборка $2 (RAM free=${_qt_mem_mb}MB, CPU=${_qt_cores} ядер → dart=${_qt_dart}MB, jvm=${_qt_jvm}, workers=${_qt_workers}, cache=on)..."
        command flutter "${cleaned_args[@]}" "${extra_flags[@]}"
        local ret=$?

        if [ $ret -ne 0 ]; then
            echo -e "\033[1;33m[Build Doctor]\033[0m Ошибка сборки (код $ret). Запускаю авто-диагностику (SDK/AAPT2/Box64) и безопасный повтор..."
            /usr/local/bin/quantum-heal-x64 --doctor 2>/dev/null || true
            BOX64_DYNAREC=0 GLIBC_TUNABLES="glibc.malloc.tcache_count=0:glibc.malloc.arena_max=1" MALLOC_ARENA_MAX=1 command flutter "${cleaned_args[@]}" "${extra_flags[@]}"
            ret=$?
        fi

        if [ $ret -eq 0 ]; then
            if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
                cp -f "build/app/outputs/bundle/release/app-release.aab" ./app-release.aab 2>/dev/null || true
                echo -e "\033[1;32m✓ AppBundle (Google Play) готов:\033[0m ./app-release.aab"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-release.apk" ./app-release.apk 2>/dev/null || true
                if command -v unzip >/dev/null 2>&1 && ! unzip -l ./app-release.apk 2>/dev/null | grep -q "AndroidManifest.xml"; then
                    echo -e "\033[1;31m✗ ВНИМАНИЕ: ./app-release.apk собран без AndroidManifest.xml (сбросьте кэш: flutter clean && rm -rf build/ android/.gradle/).\033[0m"
                    rm -f ./app-release.apk
                    ret=1
                else
                    echo -e "\033[1;32m✓ APK готов:\033[0m ./app-release.apk"
                fi
            fi
            if [ -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ./app-release-arm64.apk 2>/dev/null || true
                cp -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ./app-release.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK (ARM64 64-бит) готов:\033[0m ./app-release-arm64.apk"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ./app-release-arm32.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK (ARMv7 32-бит) готов:\033[0m ./app-release-arm32.apk"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-x86_64-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-x86_64-release.apk" ./app-release-x64.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK (x86_64) готов:\033[0m ./app-release-x64.apk"
            fi
            local found_split=false
            for sapk in build/app/outputs/flutter-apk/app-*-release.apk; do
                if [ -f "$sapk" ]; then
                    local sname="$(basename "$sapk")"
                    cp -f "$sapk" "./$sname" 2>/dev/null || true
                    echo -e "\033[1;32m✓ Split APK готов:\033[0m ./$sname"
                    found_split=true
                fi
            done
            if [ "$found_split" = "false" ] && [ -f "build/app/outputs/flutter-apk/app-debug.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-debug.apk" ./app-debug.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ Debug APK готов:\033[0m ./app-debug.apk"
            fi
        else
            echo -e "\033[1;31m✗ Сборка завершилась с кодом $ret\033[0m"
        fi

        pkill -9 -x aapt2 2>/dev/null || true
        stty sane onlcr icrnl opost erase ^? 2>/dev/null || true
        return $ret
    fi
    command flutter "$@"
}

# Create which shim if missing (inside guest)
if ! command -v which > /dev/null 2>&1; then
    mkdir -p /usr/bin
    printf '#!/bin/sh\ncommand -v "$1"\n' > /usr/bin/which
    chmod 755 /usr/bin/which
fi

# Modern Responsive System Fetch (delegates to /usr/local/bin/term-fetch)
term_fetch() {
    if [ -x /usr/local/bin/term-fetch ]; then
        /usr/local/bin/term-fetch
    elif [ -x /usr/bin/term-fetch ]; then
        /usr/bin/term-fetch
    fi
}

# Ubuntu Greeting & System Fetch (shown cleanly once per session)
if [ -z "$VTE_VERSION" ] && [ -z "$_QUANTUM_GREETING_SHOWN" ]; then
    export _QUANTUM_GREETING_SHOWN=1
    printf '\033[2J\033[H'
    term_fetch 2>/dev/null || true
    if [ -f /tmp/setup_daemon.lock ]; then
        echo -e '  \e[1;33m⏳ Фоновая установка пакетов... (cat /tmp/setup_arm64.log)\e[0m\n'
    fi
fi

alias fetch="term_fetch"
alias fd="fdfind"
alias mem="free -m"
alias clean-apt="apt-get clean && apt-get autoremove -y"
alias kill-node="killall -9 node 2>/dev/null || true"
alias disk="df -h /"

# Starship prompt if available
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
''';
      try {
        final bashrcTargets = [
          bashrc,
          File('/root/.bashrc'),
          if (Platform.isLinux && Platform.environment['HOME'] != null)
            File(p.join(Platform.environment['HOME']!, '.bashrc')),
        ];
        for (final target in bashrcTargets) {
          try {
            if (await target.parent.exists()) {
              await target.writeAsString(bashrcContent.replaceAll('\r', ''));
            }
          } catch (_) {}
        }

        final zshrcTargets = [
          File('$_filesDir/rootfs/ubuntu/root/.zshrc'),
          File('/root/.zshrc'),
          if (Platform.isLinux && Platform.environment['HOME'] != null)
            File(p.join(Platform.environment['HOME']!, '.zshrc')),
        ];
        const zshrcContent = r'''
export ANDROID_HOME=/root/android-sdk
export ANDROID_SDK_ROOT=/root/android-sdk
# Dynamically detect JAVA_HOME inside guest (prefer Java 17 / 21)
if [ -d "/root/jdk-17" ]; then
    export JAVA_HOME="/root/jdk-17"
elif [ -d "/usr/lib/jvm/java-17-openjdk-arm64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
elif [ -d "/usr/lib/jvm/java-21-openjdk-arm64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-arm64"
else
    DETECTED_JVM=$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | grep -E '17|21' | head -n 1)
    [ -z "$DETECTED_JVM" ] && DETECTED_JVM=$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)
    if [ -n "$DETECTED_JVM" ]; then
        export JAVA_HOME="$DETECTED_JVM"
    else
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
    fi
fi
if command -v flutter >/dev/null 2>&1 && [ -d "$JAVA_HOME" ]; then
    flutter config --jdk-dir="$JAVA_HOME" >/dev/null 2>&1 || true
fi
export PATH=$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.bun/bin:/usr/local/bin:/usr/local/lib/nodejs/bin:/root/.local/bin:$PATH
export TERM=xterm-256color
export COLORTERM=truecolor
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
PROMPT='%F{green}boss@ubuntu%f:%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f$ '

export FLUTTER_ALLOW_SU_ROOT=1
export FLUTTER_SUPPRESS_ANALYTICS=true
export CI=true
_JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
export _JAVA_OPTIONS
GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.enableJetifier=false"
export GRADLE_OPTS

alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias lg="lazygit"
export EDITOR=micro
export VISUAL=micro
alias fb-apk="flutter build apk --debug"
alias fb-apk-release="flutter build apk --release"
alias fb-bundle="flutter build appbundle --release"
alias fb-appbundle="flutter build appbundle --release"
alias build-apk="flutter build apk --release"
alias build-arm64="flutter build apk --release --target-platform android-arm64"
alias build-arm32="flutter build apk --release --target-platform android-arm"
alias build-x64="flutter build apk --release --target-platform android-x64"
alias build-aab="flutter build appbundle --release"
alias fb-arm64="flutter build apk --release --target-platform android-arm64"
alias fb-arm32="flutter build apk --release --target-platform android-arm"
alias fb-x64="flutter build apk --release --target-platform android-x64"
alias fb-aab="flutter build appbundle --release"
alias build-apk-split="flutter build apk --release --split-per-abi"
alias fb-apk-split="flutter build apk --release --split-per-abi"
alias build-apk-all="flutter build apk --release --split-per-abi"
alias build-app="flutter build apk --release"
alias build-bundle="flutter build appbundle --release"
alias f-clean="flutter clean && flutter pub get"
alias f-get="flutter pub get"
alias check-android="flutter doctor -v | grep -A 5 'Android toolchain'"
alias cls='clear'
alias fetch="/usr/local/bin/term-fetch"


# gradlew wrapper to ensure ./gradlew runs even on SD card / noexec storage and modern AAPT2
gradlew() {
    if ! (/usr/bin/aapt2 compile --help 2>&1 | grep -q -- '--source-path'); then
        /usr/local/bin/quantum-heal-x64 2>/dev/null || true
    fi
    if [ -f "./gradlew" ]; then
        bash ./gradlew --no-daemon "$@"
    else
        command gradlew --no-daemon "$@"
    fi
}

# Flutter build wrapper to auto-ensure ARM64 target, disable daemon, and use native aapt2 on mobile Android PRoot
flutter() {
    if [ "$1" = "upgrade" ]; then
        if ! grep -qa "GLIBC_2.34" /lib/aarch64-linux-gnu/libc.so.6 /usr/lib/aarch64-linux-gnu/libc.so.6 2>/dev/null; then
            echo "ERROR: Flutter 3.50+ (Dart 3.14) requires GLIBC >= 2.34 (Ubuntu 22.04+/24.04 rootfs)."
            echo "Current rootfs has an older GLIBC; staying on Flutter 3.47.8 to keep SDK functional."
            return 1
        fi
    fi
    if [ "$1" = "build" ] && ( [ "$2" = "apk" ] || [ "$2" = "appbundle" ] ); then
        /usr/local/bin/quantum-patch-ndk 2>/dev/null || true
        /usr/local/bin/quantum-heal-x64 2>/dev/null || true

        # Dynamically auto-tune CPU workers, JVM heap and Dart heap based on real hardware (CPU cores + free RAM)
        local cpu_cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 4)
        [ -z "$cpu_cores" ] || [ "$cpu_cores" -lt 1 ] && cpu_cores=4

        local mem_avail_kb=$(grep 'MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}')
        local mem_avail_mb=$(( ${mem_avail_kb:-2000000} / 1024 ))

        local jvm_xmx="1280m"
        local jvm_meta="384m"
        local dart_heap="768"
        local gradle_workers=2
        local gradle_parallel=true

        if [ "$mem_avail_mb" -ge 6000 ]; then
            jvm_xmx="2560m"
            jvm_meta="512m"
            dart_heap="1280"
            if [ "$cpu_cores" -ge 8 ]; then
                gradle_workers=6
            elif [ "$cpu_cores" -ge 6 ]; then
                gradle_workers=4
            elif [ "$cpu_cores" -ge 4 ]; then
                gradle_workers=3
            else
                gradle_workers=2
            fi
        elif [ "$mem_avail_mb" -ge 3200 ]; then
            # Sweet spot for 4GB-8GB tablets/phones (e.g. 8 cores with ~3.9GB available RAM)
            jvm_xmx="2048m"
            jvm_meta="512m"
            dart_heap="1024"
            if [ "$cpu_cores" -ge 8 ]; then
                gradle_workers=4
            elif [ "$cpu_cores" -ge 6 ]; then
                gradle_workers=4
            elif [ "$cpu_cores" -ge 4 ]; then
                gradle_workers=3
            else
                gradle_workers=2
            fi
        elif [ "$mem_avail_mb" -ge 2000 ]; then
            jvm_xmx="1600m"
            jvm_meta="448m"
            dart_heap="896"
            if [ "$cpu_cores" -ge 6 ]; then
                gradle_workers=3
            else
                gradle_workers=2
            fi
        elif [ "$mem_avail_mb" -ge 1400 ]; then
            jvm_xmx="1280m"
            jvm_meta="384m"
            dart_heap="768"
            gradle_workers=2
            gradle_parallel=false
        else
            jvm_xmx="1024m"
            jvm_meta="320m"
            dart_heap="640"
            gradle_workers=1
            gradle_parallel=false
        fi

        if [ -n "$GRADLE_WORKERS_OVERRIDE" ]; then
            gradle_workers="$GRADLE_WORKERS_OVERRIDE"
        fi

        export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
        export DART_VM_OPTIONS="--old_gen_heap_size=${dart_heap}"
        export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=${gradle_workers} -Dorg.gradle.parallel=${gradle_parallel} -Dorg.gradle.caching=true -Dkotlin.compiler.execution.strategy=in-process"

        /usr/local/bin/quantum-patch-ndk 2>/dev/null || true
        /usr/local/bin/quantum-heal-x64 2>/dev/null || true

        mkdir -p ~/.gradle /root/.gradle 2>/dev/null || true
        for gp in ~/.gradle/gradle.properties /root/.gradle/gradle.properties android/gradle.properties; do
            if [ -f "$gp" ] || [ "$gp" = ~/.gradle/gradle.properties ] || [ "$gp" = /root/.gradle/gradle.properties ]; then
                [ -d "$(dirname "$gp")" ] || continue
                touch "$gp" 2>/dev/null || true
                [ -w "$gp" ] || continue
                sed -i '/extra-gen-snapshot-options/d' "$gp" 2>/dev/null || true
                sed -i '/org.gradle.jvmargs/d' "$gp" 2>/dev/null || true
                sed -i '/kotlin.compiler.execution.strategy/d' "$gp" 2>/dev/null || true
                sed -i '/org.gradle.caching/d' "$gp" 2>/dev/null || true
                sed -i '/org.gradle.parallel/d' "$gp" 2>/dev/null || true
                sed -i '/org.gradle.workers.max/d' "$gp" 2>/dev/null || true
                echo "org.gradle.jvmargs=-Xmx${jvm_xmx} -XX:MaxMetaspaceSize=${jvm_meta} -Dfile.encoding=UTF-8" >> "$gp"
                echo "kotlin.compiler.execution.strategy=in-process" >> "$gp"
                echo "org.gradle.caching=true" >> "$gp"
                echo "org.gradle.parallel=${gradle_parallel}" >> "$gp"
                echo "org.gradle.workers.max=${gradle_workers}" >> "$gp"
                grep -q "org.gradle.daemon" "$gp" 2>/dev/null || echo "org.gradle.daemon=false" >> "$gp"
                grep -q "android.aapt2FromMaven" "$gp" 2>/dev/null || echo "android.aapt2FromMaven=false" >> "$gp"
                grep -q "android.aapt2FromMavenOverride" "$gp" 2>/dev/null || echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> "$gp"
                grep -q "android.aapt2.daemon" "$gp" 2>/dev/null || echo "android.aapt2.daemon=false" >> "$gp"
            fi
        done

        local has_plat=false
        local has_val=false
        local has_tree=false
        local has_pub=false
        local has_workers=false
        local has_parallel=false
        local has_jvm=false
        local cleaned_args=()
        for a in "$@"; do
            case "$a" in
                -Dorg.gradle.jvmargs=*) has_jvm=true ;;
                *org.gradle.workers.max*) has_workers=true ;;
                *org.gradle.parallel*) has_parallel=true ;;
                *target-platform*|*--split-per-abi*) has_plat=true ;;
                *android-skip-build-dependency-validation*) has_val=true ;;
                *no-tree-shake-icons*) has_tree=true ;;
                *--pub*|*--no-pub*) has_pub=true ;;
            esac
            cleaned_args+=("$a")
        done

        local extra_flags=()
        if [ "$has_plat" = "false" ] && [ "$2" != "appbundle" ]; then
            extra_flags+=("--target-platform" "android-arm64")
        fi
        if [ "$has_val" = "false" ]; then
            extra_flags+=("--android-skip-build-dependency-validation")
        fi
        if [ "$has_tree" = "false" ]; then
            extra_flags+=("--no-tree-shake-icons")
        fi
        if [ "$has_pub" = "false" ] && [ -s ".dart_tool/package_config.json" ]; then
            extra_flags+=("--no-pub")
        fi

        extra_flags+=(
            "-Pandroid.aapt2FromMaven=false"
            "-Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2"
            "-Pandroid.aapt2.daemon=false"
            "-Pandroid.enableJetifier=false"
            "-Porg.gradle.caching=true"
            "-Dorg.gradle.caching=true"
            "-Pkotlin.compiler.execution.strategy=in-process"
            "-Dorg.gradle.daemon=false"
        )
        if [ "$has_workers" = "false" ]; then
            extra_flags+=("-Porg.gradle.workers.max=${gradle_workers}")
        fi
        if [ "$has_parallel" = "false" ]; then
            extra_flags+=("-Porg.gradle.parallel=${gradle_parallel}")
        fi
        if [ "$has_jvm" = "false" ]; then
            extra_flags+=("-Dorg.gradle.jvmargs=-Xmx${jvm_xmx} -XX:MaxMetaspaceSize=${jvm_meta}")
        fi

        echo -e "\033[1;36m⚡ QuantumIDE Engine:\033[0m сборка $2 (RAM free=${mem_avail_mb}MB, CPU=${cpu_cores} ядер → dart=${dart_heap}MB, jvm=${jvm_xmx}, workers=${gradle_workers}, cache=on)..."
        command flutter "${cleaned_args[@]}" "${extra_flags[@]}"
        local ret=$?

        if [ $ret -eq 0 ]; then
            if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
                cp -f "build/app/outputs/bundle/release/app-release.aab" ./app-release.aab 2>/dev/null || true
                echo -e "\033[1;32m✓ AppBundle (Google Play) готов:\033[0m ./app-release.aab"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-release.apk" ./app-release.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK готов:\033[0m ./app-release.apk"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ./app-release-arm64.apk 2>/dev/null || true
                cp -f "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ./app-release.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK (ARM64 64-бит) готов:\033[0m ./app-release-arm64.apk"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ./app-release-arm32.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK (ARMv7 32-бит) готов:\033[0m ./app-release-arm32.apk"
            fi
            if [ -f "build/app/outputs/flutter-apk/app-x86_64-release.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-x86_64-release.apk" ./app-release-x64.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ APK (x86_64) готов:\033[0m ./app-release-x64.apk"
            fi
            local found_split=false
            for sapk in build/app/outputs/flutter-apk/app-*-release.apk; do
                if [ -f "$sapk" ]; then
                    local sname="$(basename "$sapk")"
                    cp -f "$sapk" "./$sname" 2>/dev/null || true
                    echo -e "\033[1;32m✓ Split APK готов:\033[0m ./$sname"
                    found_split=true
                fi
            done
            if [ "$found_split" = "false" ] && [ -f "build/app/outputs/flutter-apk/app-debug.apk" ]; then
                cp -f "build/app/outputs/flutter-apk/app-debug.apk" ./app-debug.apk 2>/dev/null || true
                echo -e "\033[1;32m✓ Debug APK готов:\033[0m ./app-debug.apk"
            fi
        else
            echo -e "\033[1;31m✗ Сборка завершилась с кодом $ret\033[0m"
        fi

        pkill -9 -x aapt2 2>/dev/null || true
        stty sane onlcr icrnl opost erase ^? 2>/dev/null || true
        return $ret
    fi
    command flutter "$@"
}

if [ -z "$VTE_VERSION" ] && [ -z "$_QUANTUM_GREETING_SHOWN" ]; then
    export _QUANTUM_GREETING_SHOWN=1
    clear
    [ -x /usr/local/bin/term-fetch ] && /usr/local/bin/term-fetch
    if [ -f /tmp/setup_daemon.lock ]; then
        echo -e '  \e[1;33m⏳ Фоновая установка пакетов... (cat /tmp/setup_arm64.log)\e[0m\n'
    fi
fi
''';
        for (final target in zshrcTargets) {
          try {
            if (await target.parent.exists()) {
              await target.writeAsString(zshrcContent.replaceAll('\r', ''));
            }
          } catch (_) {}
        }

        final inputrcTargets = [
          File('$_filesDir/rootfs/ubuntu/root/.inputrc'),
          File('/root/.inputrc'),
          if (Platform.isLinux && Platform.environment['HOME'] != null)
            File(p.join(Platform.environment['HOME']!, '.inputrc')),
        ];
        for (final inputrc in inputrcTargets) {
          try {
            if (await inputrc.parent.exists()) {
              await inputrc.writeAsString('set input-meta on\nset output-meta on\nset convert-meta off\nset enable-bracketed-paste off\n"\\C-?": backward-delete-char\n"\\C-h": backward-delete-char\n"\\e[3~": delete-char\n');
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('Warning: Failed to write shell config files: $e');
      }
    }
  }

  Future<void> updateScripts() async {
    await _ensureBinaries();
    await _repairTerminfoIfNeeded();
  }

  Future<void> _repairTerminfoIfNeeded() async {
    try {
      final rootfs = p.join(_filesDir, 'rootfs', 'ubuntu');
      final libDir = Directory(p.join(rootfs, 'lib', 'terminfo'));
      final usrDir = Directory(p.join(rootfs, 'usr', 'share', 'terminfo'));

      if (!libDir.existsSync() && !usrDir.existsSync()) return;

      if (!libDir.existsSync()) {
        try {
          libDir.createSync(recursive: true);
        } catch (_) {}
      }
      if (!usrDir.existsSync()) {
        try {
          usrDir.createSync(recursive: true);
        } catch (_) {}
      }

      // Check for xterm in lib or usr
      final libXterm = File(p.join(rootfs, 'lib', 'terminfo', 'x', 'xterm'));
      final usrXterm = File(p.join(rootfs, 'usr', 'share', 'terminfo', 'x', 'xterm'));
      final sourceXterm = libXterm.existsSync() ? libXterm : (usrXterm.existsSync() ? usrXterm : null);

      if (sourceXterm != null) {
        Directory(p.join(rootfs, 'lib', 'terminfo', 'x')).createSync(recursive: true);
        Directory(p.join(rootfs, 'usr', 'share', 'terminfo', 'x')).createSync(recursive: true);

        // Ensure both directories have xterm
        if (!libXterm.existsSync()) {
          try {
            sourceXterm.copySync(libXterm.path);
          } catch (_) {}
        }
        if (!usrXterm.existsSync()) {
          try {
            sourceXterm.copySync(usrXterm.path);
          } catch (_) {}
        }

        // If xterm-256color is missing in either directory, copy xterm as fallback
        final lib256 = File(p.join(rootfs, 'lib', 'terminfo', 'x', 'xterm-256color'));
        final usr256 = File(p.join(rootfs, 'usr', 'share', 'terminfo', 'x', 'xterm-256color'));

        if (!lib256.existsSync()) {
          try {
            sourceXterm.copySync(lib256.path);
          } catch (_) {}
        }
        if (!usr256.existsSync()) {
          try {
            sourceXterm.copySync(usr256.path);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('RuntimeService: _repairTerminfoIfNeeded warning: $e');
    }
  }

  Future<void> _ensureAndroidLicenses() async {
    final licenseDirs = [
      Directory('/root/android-sdk/licenses'),
      Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'licenses')),
    ];

    const licenses = {
      'android-sdk-license': '24333f8a63b6825ea9c5514f83c2829b004d1fee\nd56f5187479451eabf01fb78af6dfcb131a6481e\n2fa2d150aa0a1204d10e5ed57ab8369e7b50077c\n',
      'android-sdk-preview-license': '84831b9409646a918e30573bab4c9c91346d8abd\n',
      'android-sdk-arm-dbt-license': '859f317696f67ef3d7f30a50a5560e7834b43903\n',
      'android-googletv-license': '601085b94cd77f0b54ff86406957099ebe79c4d6\n',
      'android-googlexr-license': 'ceff83576aac4f7f37cb98fe189e9fb3c49d3b81\n',
      'google-gdk-license': '33b6a2b64607f11b759f320ef9dff4ae5c47d97a\n',
      'microxr-sysimage-license': '3a7848b1d7366ca5cfa0be477627644ca73f47e3\n',
      'mips-android-sysimage-license': 'e9acab5b5fbb560a72cfaecce8946896ff6aab9d\n',
    };

    for (final dir in licenseDirs) {
      try {
        if (await dir.parent.exists()) {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          for (final entry in licenses.entries) {
            final file = File(p.join(dir.path, entry.key));
            if (!await file.exists()) {
              await file.writeAsString(entry.value);
            }
          }
        }
      } catch (_) {}
    }
  }

  /// Extracts the pre-bundled native ARM64 static aapt2 binary to the system
  /// and Android SDK build-tools to ensure AGP 8+ builds never fail with '--source-path'.
  Future<void> _ensureBundledAapt2() async {
    try {
      final aapt2Targets = [
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'bin', 'aapt2'),
        p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'local', 'bin', 'aapt2-arm64'),
        p.join(_filesDir, 'bin', 'aapt2'),
        '/usr/bin/aapt2',
        '/usr/local/bin/aapt2-arm64',
      ];

      final primaryAapt2 = File(aapt2Targets.first);
      bool needsExtract = true;
      if (await primaryAapt2.exists()) {
        try {
          final len = await primaryAapt2.length();
          if (len > 1000000) {
            needsExtract = false;
          }
        } catch (_) {}
      }

      if (needsExtract) {
        debugPrint('[AAPT2] Extracting bundled modern ARM64 aapt2 from assets...');
        final byteData = await rootBundle.load('assets/bin/aapt2-arm64.gz');
        final compressedBytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        final decompressedBytes = gzip.decode(compressedBytes);

        for (final targetPath in aapt2Targets) {
          try {
            final f = File(targetPath);
            if (await f.parent.exists()) {
              if (await f.exists()) await f.delete();
              await f.writeAsBytes(decompressedBytes, flush: true);
              await Process.run('chmod', ['755', targetPath]);
              debugPrint('[AAPT2] Installed modern aapt2 at $targetPath');
            }
          } catch (_) {}
        }

        final buildToolsDir = Directory(
          p.join(_filesDir, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'build-tools'),
        );
        if (await buildToolsDir.exists()) {
          await for (final entity in buildToolsDir.list()) {
            if (entity is Directory) {
              final btAapt2 = File(p.join(entity.path, 'aapt2'));
              try {
                if (await btAapt2.exists()) await btAapt2.delete();
                await btAapt2.writeAsBytes(decompressedBytes, flush: true);
                await Process.run('chmod', ['755', btAapt2.path]);
                debugPrint('[AAPT2] Updated build-tools aapt2 at ${btAapt2.path}');
              } catch (_) {}
            }
          }
        }

        final globalBuildTools = Directory('/root/android-sdk/build-tools');
        if (await globalBuildTools.exists()) {
          await for (final entity in globalBuildTools.list()) {
            if (entity is Directory) {
              final btAapt2 = File(p.join(entity.path, 'aapt2'));
              try {
                if (await btAapt2.exists()) await btAapt2.delete();
                await btAapt2.writeAsBytes(decompressedBytes, flush: true);
                await Process.run('chmod', ['755', btAapt2.path]);
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AAPT2] Warning: Failed to extract bundled aapt2: $e');
    }
  }

  /// Extracts the pre-bundled static ARM64 `ruri` (RuriOSS/ruri) container runtime
  /// into `$_filesDir/bin/ruri` so rooted devices can run Ubuntu 24.04 at native
  /// kernel speed without `libproot.so` ptrace overhead.
  Future<void> _ensureBundledRuri() async {
    if (!Platform.isAndroid) return;
    try {
      final binDir = Directory(p.join(_filesDir, 'bin'));
      if (!await binDir.exists()) {
        await binDir.create(recursive: true);
      }
      final targetFile = File(p.join(binDir.path, 'ruri'));
      if (await targetFile.exists() && await targetFile.length() > 100000) {
        await Process.run('chmod', ['755', targetFile.path]);
        return;
      }
      final byteData = await rootBundle.load('assets/bin/ruri-arm64');
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      if (await targetFile.exists()) await targetFile.delete();
      await targetFile.writeAsBytes(bytes, flush: true);
      await Process.run('chmod', ['755', targetFile.path]);
      debugPrint('[RURI] Installed static ruri-arm64 at ${targetFile.path}');
    } catch (e) {
      // Gracefully ignore in local dev builds where assets/bin/ruri-arm64 wasn't compiled
      debugPrint('[RURI] Bundled ruri-arm64 not available or skipped: $e');
    }
  }

  String _generateTermFetchScript() {
    return r'''#!/bin/bash
# ==============================================================================
# QuantumIDE Cyberpunk System Fetch (term-fetch)
# ==============================================================================

COLS=$(stty size 2>/dev/null | awk '{print $2}')
[ -z "$COLS" ] && COLS=$(tput cols 2>/dev/null)
[ -z "$COLS" ] && COLS="${COLUMNS}"
[ -z "$COLS" ] || [ "$COLS" -le 0 ] 2>/dev/null && COLS=50

# ANSI Escape Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"

# Cyberpunk Palette
C_CYAN="\033[38;5;51m"
C_BLUE="\033[38;5;39m"
C_PURPLE="\033[38;5;141m"
C_MAGENTA="\033[38;5;201m"
C_PINK="\033[38;5;213m"
C_GREEN="\033[38;5;48m"
C_YELLOW="\033[38;5;220m"
C_ORANGE="\033[38;5;208m"
C_RED="\033[38;5;196m"
C_WHITE="\033[38;5;255m"
C_GRAY="\033[38;5;245m"
C_DARK="\033[38;5;238m"

# 1. OS & Kernel
OS_NAME=$(grep -oP '(?<=PRETTY_NAME=")[^"]*' /etc/os-release 2>/dev/null)
[ -z "$OS_NAME" ] && OS_NAME="$(uname -s)"
ARCH=$(uname -m)
KERNEL=$(uname -r | cut -d'-' -f1-2)

# 2. Host / Device Model
HOST_MODEL=""
if command -v getprop >/dev/null 2>&1; then
    BRAND=$(getprop ro.product.brand 2>/dev/null)
    MODEL=$(getprop ro.product.model 2>/dev/null)
    [ -n "$MODEL" ] && HOST_MODEL="$BRAND $MODEL"
fi
if [ -z "$HOST_MODEL" ] && [ -f /sys/devices/virtual/dmi/id/product_name ]; then
    HOST_MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
fi
[ -z "$HOST_MODEL" ] && HOST_MODEL="$(hostname 2>/dev/null || echo 'localhost')"

# 3. Uptime
if [ -s /proc/uptime ]; then
    UP_SECS=$(cut -d. -f1 /proc/uptime 2>/dev/null)
    if [ -n "$UP_SECS" ] && [ "$UP_SECS" -eq "$UP_SECS" ] 2>/dev/null; then
        DAYS=$((UP_SECS / 86400))
        HOURS=$(( (UP_SECS % 86400) / 3600 ))
        MINS=$(( (UP_SECS % 3600) / 60 ))
        UPTIME_STR=""
        [ $DAYS -gt 0 ] && UPTIME_STR="${DAYS}d "
        [ $HOURS -gt 0 ] && UPTIME_STR="${UPTIME_STR}${HOURS}h "
        UPTIME_STR="${UPTIME_STR}${MINS}m"
    fi
else
    UPTIME_STR="unknown"
fi

# 4. CPU Info
CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")
CPU_NAME=$(grep -m1 -E 'Hardware|model name|Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
[ -z "$CPU_NAME" ] && CPU_NAME="ARM64 Processor"

# 5. RAM Usage
if [ -f /proc/meminfo ]; then
    MEM_TOTAL_KB=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
    MEM_AVAIL_KB=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
    [ -z "$MEM_AVAIL_KB" ] && MEM_AVAIL_KB=$(grep 'MemFree:' /proc/meminfo | awk '{print $2}')
    MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAIL_KB))
    MEM_USED_MB=$((MEM_USED_KB / 1024))
    MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
    [ $MEM_TOTAL_KB -gt 0 ] && MEM_PERCENT=$((MEM_USED_KB * 100 / MEM_TOTAL_KB)) || MEM_PERCENT=0
else
    MEM_USED_MB=0
    MEM_TOTAL_MB=0
    MEM_PERCENT=0
fi

# 6. Disk Usage
DISK_INFO=$(df -h / 2>/dev/null | tail -1)
DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
[ -z "$DISK_PERCENT" ] && DISK_PERCENT=0

# Progress bar generator
make_bar() {
    local pct=$1
    local width=$2
    [ -z "$width" ] && width=10
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    echo "$bar"
}

# 7. Detected Runtimes / Tools
RUNTIMES=""
command -v flutter >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Flutter "
command -v node >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Node.js "
command -v bun >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Bun "
command -v python3 >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Python "
command -v uv >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}uv "
command -v rustc >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Rust "
command -v clang >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Clang "
[ -z "$RUNTIMES" ] && RUNTIMES="Linux Core"

# RENDER (Authentic Ubuntu Neofetch style: Ubuntu logo left, device info right)
echo
if [ "$COLS" -ge 58 ]; then
    RAM_BAR=$(make_bar $MEM_PERCENT 8)
    DISK_BAR=$(make_bar $DISK_PERCENT 8)
    USER_HOST="${USER:-root}@quantum-ide"
    C_UBU="\033[38;5;202m"
    C_UBU2="\033[38;5;208m"

    echo -e "        ${C_UBU}.-/+oooo+/-.${C_RESET}          ${C_BOLD}${C_UBU2}${USER_HOST}${C_RESET}"
    echo -e "     ${C_UBU}\`:+ssssssssssss+:\`${C_RESET}       ${C_DARK}──────────────────────────────${C_RESET}"
    echo -e "   ${C_UBU}.+ssssssss${C_WHITE}yy${C_UBU}ssssssss+.${C_RESET}     ${C_BOLD}${C_UBU2}OS${C_RESET}      ${C_WHITE}${OS_NAME}${C_RESET} ${C_DIM}(${ARCH})${C_RESET}"
    echo -e "  ${C_UBU}/sssssssss${C_WHITE}dMMN${C_UBU}sssssssss/${C_RESET}    ${C_BOLD}${C_UBU2}Host${C_RESET}    ${C_WHITE}${HOST_MODEL}${C_RESET}"
    echo -e " ${C_UBU}/sssssssh${C_WHITE}NmyNMMMh${C_UBU}ssssssss/${C_RESET}   ${C_BOLD}${C_UBU2}Kernel${C_RESET}  ${C_WHITE}${KERNEL}${C_RESET}"
    echo -e "${C_UBU}.sssssssd${C_WHITE}MNhsymMMMd${C_UBU}ssssssss.${C_RESET}  ${C_BOLD}${C_UBU2}CPU${C_RESET}     ${C_WHITE}${CPU_NAME}${C_RESET} ${C_DIM}(${CPU_CORES}c)${C_RESET}"
    echo -e "${C_UBU}+sssshhyd${C_WHITE}MNssssNMMMy${C_UBU}sssssss+${C_RESET}  ${C_BOLD}${C_UBU2}RAM${C_RESET}     ${C_GREEN}${RAM_BAR}${C_RESET} ${C_WHITE}${MEM_USED_MB}M / ${MEM_TOTAL_MB}M${C_RESET} ${C_DIM}(${MEM_PERCENT}%)${C_RESET}"
    echo -e "${C_UBU}+sssshhyd${C_WHITE}MNssssNMMMy${C_UBU}sssssss+${C_RESET}  ${C_BOLD}${C_UBU2}Disk${C_RESET}    ${C_PURPLE}${DISK_BAR}${C_RESET} ${C_WHITE}${DISK_USED} / ${DISK_TOTAL}${C_RESET} ${C_DIM}(${DISK_PERCENT}%)${C_RESET}"
    echo -e "${C_UBU}.sssssssd${C_WHITE}MNhsymMMMd${C_UBU}ssssssss.${C_RESET}  ${C_BOLD}${C_UBU2}Uptime${C_RESET}  ${C_WHITE}${UPTIME_STR}${C_RESET}"
    echo -e " ${C_UBU}/sssssssh${C_WHITE}NmyNMMMh${C_UBU}ssssssss/${C_RESET}   ${C_BOLD}${C_UBU2}Stack${C_RESET}   ${C_CYAN}${RUNTIMES}${C_RESET}"
    echo -e "  ${C_UBU}/sssssssss${C_WHITE}dMMN${C_UBU}sssssssss/${C_RESET}    ${C_RED}● ${C_ORANGE}● ${C_YELLOW}● ${C_GREEN}● ${C_CYAN}● ${C_BLUE}● ${C_PURPLE}● ${C_MAGENTA}●${C_RESET}"
    echo -e "   ${C_UBU}.+ssssssss${C_WHITE}yy${C_UBU}ssssssss+.${C_RESET}"
    echo -e "     ${C_UBU}\`:+ssssssssssss+:\`${C_RESET}"
    echo -e "        ${C_UBU}.-/+oooo+/-.${C_RESET}"
else
    RAM_BAR=$(make_bar $MEM_PERCENT 6)
    DISK_BAR=$(make_bar $DISK_PERCENT 6)
    C_UBU="\033[38;5;202m"
    C_UBU2="\033[38;5;208m"

    echo -e "    ${C_UBU}.-/oooo\\-.${C_RESET}    ${C_BOLD}${C_UBU2}root@quantum-ide${C_RESET}"
    echo -e "  ${C_UBU}.+ssss${C_WHITE}yy${C_UBU}ssss+.${C_RESET}  ${C_UBU2}OS:${C_RESET} ${C_WHITE}${OS_NAME}${C_RESET}"
    echo -e " ${C_UBU}/ssss${C_WHITE}dMMNd${C_UBU}ssss/${C_RESET}  ${C_UBU2}CPU:${C_RESET} ${C_WHITE}${CPU_CORES} cores${C_RESET}"
    echo -e "${C_UBU}.sssy${C_WHITE}MNssNM${C_UBU}ysss.${C_RESET}  ${C_UBU2}RAM:${C_RESET} ${C_GREEN}${RAM_BAR}${C_RESET} ${C_WHITE}${MEM_USED_MB}M/${MEM_TOTAL_MB}M${C_RESET}"
    echo -e " ${C_UBU}\\ssss${C_WHITE}dMMNd${C_UBU}ssss\\${C_RESET}  ${C_UBU2}Disk:${C_RESET} ${C_PURPLE}${DISK_BAR}${C_RESET} ${C_WHITE}${DISK_USED}/${DISK_TOTAL}${C_RESET}"
    echo -e "  ${C_UBU}\`+ssss${C_WHITE}yy${C_UBU}ssss+'${C_RESET}  ${C_UBU2}Up:${C_RESET} ${C_WHITE}${UPTIME_STR}${C_RESET}"
    echo -e "    ${C_UBU}\`-\\oooo/-'${C_RESET}    ${C_RED}● ${C_ORANGE}● ${C_YELLOW}● ${C_GREEN}● ${C_CYAN}● ${C_BLUE}● ${C_PURPLE}●${C_RESET}"
fi
echo
''';
  }

  String _generateInitHostScript() {
    return '''#!/system/bin/sh
FILES_DIR="\$1"
GUEST_CWD="\$2"
if [ -z "\$FILES_DIR" ]; then FILES_DIR="$_filesDir"; fi
if [ -z "\$GUEST_CWD" ]; then GUEST_CWD="/root"; fi
PROOT_LIB_DIR="$_nativeLibDir"
PROOT="\$PROOT_LIB_DIR/libproot.so"
ROOTFS="\$FILES_DIR/rootfs/ubuntu"
TMPDIR="\$FILES_DIR/tmp"
CONFIG="\$FILES_DIR/config"

# ── Native Root Kernel Mode (Direct execution on device kernel without Ubuntu PRoot) ──
if [ -f "\$CONFIG/native_root_mode.flag" ]; then
    NATIVE_HOME="\$FILES_DIR/home"
    mkdir -p "\$NATIVE_HOME" "\$FILES_DIR/projects" "\$FILES_DIR/bin" "\$TMPDIR" 2>/dev/null || true
    case "\$GUEST_CWD" in
        /root/projects/*)
            REL_P="\${GUEST_CWD#/root/projects/}"
            NATIVE_CWD="\$FILES_DIR/projects/\$REL_P"
            mkdir -p "\$NATIVE_CWD" 2>/dev/null || true
            ;;
        /root/projects)
            NATIVE_CWD="\$FILES_DIR/projects"
            ;;
        /root)
            NATIVE_CWD="\$NATIVE_HOME"
            ;;
        /sdcard/*)
            REL_S="\${GUEST_CWD#/sdcard/}"
            NATIVE_CWD="/storage/emulated/0/\$REL_S"
            ;;
        *)
            NATIVE_CWD="\$GUEST_CWD"
            ;;
    esac
    [ ! -d "\$NATIVE_CWD" ] && NATIVE_CWD="\$NATIVE_HOME"
    NATIVE_PATH="\$NATIVE_HOME/flutter/bin:\$NATIVE_HOME/android-sdk/cmdline-tools/latest/bin:\$NATIVE_HOME/android-sdk/platform-tools:\$NATIVE_HOME/.bun/bin:\$NATIVE_HOME/.local/bin:\$FILES_DIR/bin:/data/data/com.termux/files/usr/bin:/data/user/0/com.termux/files/usr/bin:/data/user/0/com.agy/files/usr/bin:/data/local/tmp/bin:/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:/system/bin:/system/xbin:/sbin:/vendor/bin"
    SU_BIN=""
    for cand in su /system/bin/su /system/xbin/su /sbin/su /su/bin/su /debug_ramdisk/su /system_ext/bin/su /vendor/bin/su /data/adb/magisk/su /data/adb/ksu/bin/su /data/adb/ap/bin/su; do
        if command -v "\$cand" >/dev/null 2>&1 || [ -x "\$cand" ]; then
            SU_BIN="\$cand"
            break
        fi
    done
    SHELL_BIN="/system/bin/sh"
    for sh_cand in /data/data/com.termux/files/usr/bin/bash /data/user/0/com.termux/files/usr/bin/bash /data/user/0/com.agy/files/usr/bin/bash /bin/bash /system/bin/sh; do
        if [ -x "\$sh_cand" ]; then
            SHELL_BIN="\$sh_cand"
            break
        fi
    done
    RURI_BIN="\$FILES_DIR/bin/ruri"
    if [ -n "\$SU_BIN" ] && [ -x "\$RURI_BIN" ] && [ -x "\$ROOTFS/bin/bash" ]; then
        case "\$GUEST_CWD" in
            "\$FILES_DIR/projects"/*) RURI_CWD="/root/projects/\${GUEST_CWD#\$FILES_DIR/projects/}" ;;
            "\$FILES_DIR/projects")   RURI_CWD="/root/projects" ;;
            "\$FILES_DIR"*)           RURI_CWD="/root" ;;
            /storage/emulated/0/*)    RURI_CWD="/sdcard/\${GUEST_CWD#/storage/emulated/0/}" ;;
            /root*)                   RURI_CWD="\$GUEST_CWD" ;;
            /sdcard*)                 RURI_CWD="\$GUEST_CWD" ;;
            *)                        RURI_CWD="/root" ;;
        esac
        mkdir -p "\$FILES_DIR/projects" "\$TMPDIR" "\$ROOTFS/etc" "\$ROOTFS/sdcard" "\$ROOTFS/tmp" "\$ROOTFS/root/projects" 2>/dev/null || true
        [ ! -f "\$TMPDIR/resolv.conf" ] && printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "\$TMPDIR/resolv.conf" 2>/dev/null || true
        [ ! -f "\$TMPDIR/hosts" ] && printf '127.0.0.1 localhost localhost.localdomain quantum-ide\n::1 localhost ip6-localhost ip6-loopback\n' > "\$TMPDIR/hosts" 2>/dev/null || true
        [ ! -f "\$TMPDIR/nsswitch.conf" ] && printf 'passwd: files\ngroup: files\nshadow: files\nhosts: files dns\nnetworks: files\nprotocols: files\nservices: files\nethers: files\nrpc: files\n' > "\$TMPDIR/nsswitch.conf" 2>/dev/null || true
        RURI_MOUNTS="-m \\"\$FILES_DIR/projects\\" /root/projects -m /storage/emulated/0 /sdcard -m \\"\$TMPDIR/resolv.conf\\" /etc/resolv.conf -m \\"\$TMPDIR/hosts\\" /etc/hosts -m \\"\$TMPDIR/nsswitch.conf\\" /etc/nsswitch.conf -m \\"\$TMPDIR\\" /tmp"
        if [ -d "/storage/emulated/0/QuantumIDE" ]; then
            mkdir -p "\$ROOTFS/root/projects/external" 2>/dev/null || true
            RURI_MOUNTS="\$RURI_MOUNTS -m /storage/emulated/0/QuantumIDE /root/projects/external"
        fi
        for sys_dir in /system /apex /vendor /product; do
            if [ -d "\$sys_dir" ]; then
                mkdir -p "\$ROOTFS\$sys_dir" 2>/dev/null || true
                RURI_MOUNTS="\$RURI_MOUNTS -m \$sys_dir \$sys_dir"
            fi
        done
        RURI_ENV="-e HOME /root -e USER root -e TMPDIR /tmp -e TEMP /tmp -e TERM xterm-256color -e COLORTERM truecolor -e LANG C.UTF-8 -e LC_ALL C.UTF-8 -e DEBIAN_FRONTEND noninteractive -e FLUTTER_ALLOW_SU_ROOT true -e ANDROID_HOME /root/android-sdk -e ANDROID_SDK_ROOT /root/android-sdk -e PATH /usr/local/sbin:/usr/local/bin:/root/.bun/bin:/usr/local/lib/nodejs/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.local/bin"
        if [ \$# -gt 2 ]; then
            shift 2
            if [ "\$1" = "/bin/bash" ] && [ "\$2" = "-c" ]; then
                shift 2
            fi
            CMD_STR="\$*"
            RURI_SCRIPT="\$TMPDIR/.rc_\$\$.sh"
            printf '%s\n' "\$CMD_STR" > "\$RURI_SCRIPT"
            exec "\$SU_BIN" -c "\\"\$RURI_BIN\\" -w -W \\"\$RURI_CWD\\" \$RURI_MOUNTS \$RURI_ENV \\"\$ROOTFS\\" /bin/bash -c 'C=\\"\$(cat /tmp/.rc_\$\$.sh)\\"; rm -f /tmp/.rc_\$\$.sh; eval \\"\$C\\"' "
        else
            exec "\$SU_BIN" -c "\\"\$RURI_BIN\\" -w -W \\"\$RURI_CWD\\" \$RURI_MOUNTS \$RURI_ENV \\"\$ROOTFS\\" /bin/bash --login"
        fi
    fi

    if [ \$# -gt 2 ]; then
        shift 2
        if [ "\$1" = "/bin/bash" ] && [ "\$2" = "-c" ]; then
            shift 2
        fi
        CMD_STR="\$*"
        if [ -n "\$SU_BIN" ]; then
            exec "\$SU_BIN" -c "export PATH=\\"\$NATIVE_PATH:\\\$PATH\\" HOME=\\"\$NATIVE_HOME\\" TMPDIR=\\"\$TMPDIR\\" TEMP=\\"\$TMPDIR\\" ANDROID_HOME=\\"\$NATIVE_HOME/android-sdk\\" ANDROID_SDK_ROOT=\\"\$NATIVE_HOME/android-sdk\\" FLUTTER_ROOT=\\"\$NATIVE_HOME/flutter\\" TERM=xterm-256color; cd \\"\$NATIVE_CWD\\" 2>/dev/null || true; \$CMD_STR"
        else
            export PATH="\$NATIVE_PATH:\$PATH" HOME="\$NATIVE_HOME" TMPDIR="\$TMPDIR" TEMP="\$TMPDIR" ANDROID_HOME="\$NATIVE_HOME/android-sdk" ANDROID_SDK_ROOT="\$NATIVE_HOME/android-sdk" FLUTTER_ROOT="\$NATIVE_HOME/flutter" TERM=xterm-256color
            cd "\$NATIVE_CWD" 2>/dev/null || true
            exec "\$SHELL_BIN" -c "\$CMD_STR"
        fi
    else
        if [ -n "\$SU_BIN" ]; then
            exec "\$SU_BIN" -c "export PATH=\\"\$NATIVE_PATH:\\\$PATH\\" HOME=\\"\$NATIVE_HOME\\" TMPDIR=\\"\$TMPDIR\\" TEMP=\\"\$TMPDIR\\" ANDROID_HOME=\\"\$NATIVE_HOME/android-sdk\\" ANDROID_SDK_ROOT=\\"\$NATIVE_HOME/android-sdk\\" FLUTTER_ROOT=\\"\$NATIVE_HOME/flutter\\" TERM=xterm-256color COLORTERM=truecolor; cd \\"\$NATIVE_CWD\\" 2>/dev/null || true; echo '⚡ QuantumIDE Native Root Kernel Mode (uid=0)'; exec \\"\$SHELL_BIN\\""
        else
            export PATH="\$NATIVE_PATH:\$PATH" HOME="\$NATIVE_HOME" TMPDIR="\$TMPDIR" TEMP="\$TMPDIR" ANDROID_HOME="\$NATIVE_HOME/android-sdk" ANDROID_SDK_ROOT="\$NATIVE_HOME/android-sdk" FLUTTER_ROOT="\$NATIVE_HOME/flutter" TERM=xterm-256color COLORTERM=truecolor
            cd "\$NATIVE_CWD" 2>/dev/null || true
            echo "⚡ QuantumIDE Native Kernel Shell"
            exec "\$SHELL_BIN"
        fi
    fi
fi

# Create proc/sys fakes if missing or empty to avoid proot warnings and support ps/top/uptime
mkdir -p "\$CONFIG/proc_fakes" "\$CONFIG/sys_fakes"
if [ ! -s "\$CONFIG/proc_fakes/loadavg" ]; then
    echo "0.10 0.10 0.10 1/100 1000" > "\$CONFIG/proc_fakes/loadavg"
fi
if [ ! -s "\$CONFIG/proc_fakes/stat" ]; then
    printf "cpu  2255 34 2290 22625 150 0 0 0 0 0\\ncpu0 1132 17 1145 11312 75 0 0 0 0 0\\ncpu1 1123 17 1145 11313 75 0 0 0 0 0\\nbtime 1700000000\\nprocesses 1000\\nprocs_running 1\\nprocs_blocked 0\\n" > "\$CONFIG/proc_fakes/stat"
fi
if [ ! -s "\$CONFIG/proc_fakes/uptime" ]; then
    echo "3600.00 7200.00" > "\$CONFIG/proc_fakes/uptime"
fi
if [ ! -s "\$CONFIG/proc_fakes/version" ]; then
    echo "Linux version 6.1.0-quantum (root@localhost) (gcc version 11.4.0) #1 SMP PREEMPT 2026" > "\$CONFIG/proc_fakes/version"
fi
if [ ! -s "\$CONFIG/proc_fakes/vmstat" ]; then
    printf "nr_free_pages 100000\\nnr_active_anon 50000\\nnr_inactive_anon 50000\\n" > "\$CONFIG/proc_fakes/vmstat"
fi
if [ ! -s "\$CONFIG/proc_fakes/cap_last_cap" ]; then
    echo "40" > "\$CONFIG/proc_fakes/cap_last_cap"
fi
if [ ! -s "\$CONFIG/proc_fakes/max_user_watches" ]; then
    echo "1048576" > "\$CONFIG/proc_fakes/max_user_watches"
fi
if [ ! -s "\$CONFIG/proc_fakes/fips_enabled" ]; then
    echo "0" > "\$CONFIG/proc_fakes/fips_enabled"
fi
if [ ! -s "\$CONFIG/proc_fakes/statm" ]; then
    echo "100000 50000 10000 100 0 40000 0" > "\$CONFIG/proc_fakes/statm"
fi
touch "\$CONFIG/sys_fakes/empty"
CONFIG="\$FILES_DIR/config"

# Resolve group ID warnings by creating basic passwd/group files
mkdir -p "\$ROOTFS/etc"
if [ ! -f "\$ROOTFS/etc/passwd" ]; then
    echo "root:x:0:0:root:/root:/bin/bash" > "\$ROOTFS/etc/passwd"
fi
if [ ! -f "\$ROOTFS/etc/group" ]; then
    echo "root:x:0:" > "\$ROOTFS/etc/group"
    echo "render:x:3003:" >> "\$ROOTFS/etc/group"
    echo "everybody:x:9997:" >> "\$ROOTFS/etc/group"
    echo "aid_sdcard_rw:x:1015:" >> "\$ROOTFS/etc/group"
    echo "aid_media_rw:x:1023:" >> "\$ROOTFS/etc/group"
    echo "aid_graphics:x:1003:" >> "\$ROOTFS/etc/group"
    echo "aid_input:x:1004:" >> "\$ROOTFS/etc/group"
fi

# Map common and current Android GIDs to avoid warnings
for gid in \$(id -G 2>/dev/null) 1077 1078 1079 3003 9997; do
    if ! grep -q ":\$gid:" "\$ROOTFS/etc/group" 2>/dev/null; then
        echo "android_\$gid:x:\$gid:" >> "\$ROOTFS/etc/group"
    fi
done

# which shim is now handled inside .bashrc for better compatibility with PRoot

# Fix gradlew permissions by shadowing them in internal storage
SHADOW_DIR="\$TMPDIR/gradle_shadow"
mkdir -p "\$SHADOW_DIR"

# Clean old binds if they exist
rm -f "\$TMPDIR/proot_binds"

# Fast gradlew permissions fix: ONLY scan target project or shallow external dir
SHADOW_TARGET=""
case "\$GUEST_CWD" in
    /sdcard/*|/root/projects/external/*)
        HOST_PROJ=\$(echo "\$GUEST_CWD" | sed "s|/root/projects/external|/storage/emulated/0/QuantumIDE|g" | sed "s|/sdcard|/storage/emulated/0|g")
        if [ -d "\$HOST_PROJ" ]; then
            SHADOW_TARGET="\$HOST_PROJ"
        fi
        ;;
esac

if [ -n "\$SHADOW_TARGET" ]; then
    find "\$SHADOW_TARGET" -maxdepth 2 -name "gradlew" 2>/dev/null | while read -r f; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *" "*) continue ;;
        esac
        SAFE_NAME=\$(echo "\$f" | tr '/' '_')
        SHADOW_PATH="\$SHADOW_DIR/\$SAFE_NAME"
        cp "\$f" "\$SHADOW_PATH" 2>/dev/null
        chmod 755 "\$SHADOW_PATH" 2>/dev/null
        GUEST_F=\$(echo "\$f" | sed "s|/storage/emulated/0/QuantumIDE|/root/projects/external|g" | sed "s|/storage/emulated/0|/sdcard|g")
        echo "--bind=\$SHADOW_PATH:\$GUEST_F" >> "\$TMPDIR/proot_binds"
    done
elif [ -d "/storage/emulated/0/QuantumIDE" ]; then
    find "/storage/emulated/0/QuantumIDE" -maxdepth 2 -name "gradlew" 2>/dev/null | while read -r f; do
        [ -f "\$f" ] || continue
        case "\$f" in
            *" "*) continue ;;
        esac
        SAFE_NAME=\$(echo "\$f" | tr '/' '_')
        SHADOW_PATH="\$SHADOW_DIR/\$SAFE_NAME"
        cp "\$f" "\$SHADOW_PATH" 2>/dev/null
        chmod 755 "\$SHADOW_PATH" 2>/dev/null
        GUEST_F=\$(echo "\$f" | sed "s|/storage/emulated/0/QuantumIDE|/root/projects/external|g" | sed "s|/storage/emulated/0|/sdcard|g")
        echo "--bind=\$SHADOW_PATH:\$GUEST_F" >> "\$TMPDIR/proot_binds"
    done
fi

if [ -f "\$TMPDIR/proot_binds" ]; then
    BIND_OVERLAYS=\$(cat "\$TMPDIR/proot_binds" | tr '\n' ' ')
    rm -f "\$TMPDIR/proot_binds"
fi

if [ ! -f "\$PROOT" ]; then
    echo "ERROR: libproot.so not found at \$PROOT"
    exit 1
fi

# Fix CANNOT LINK EXECUTABLE ... libtalloc.so.2 not found
# Android strips version numbers from JNI libs, so we must recreate libtalloc.so.2
if [ ! -f "\$FILES_DIR/lib/libtalloc.so.2" ] && [ -f "\$PROOT_LIB_DIR/libtalloc.so" ]; then
    mkdir -p "\$FILES_DIR/lib"
    cp "\$PROOT_LIB_DIR/libtalloc.so" "\$FILES_DIR/lib/libtalloc.so.2"
fi

unset LD_PRELOAD
unset PROOT_NO_SECCOMP

mkdir -p "\$TMPDIR"
chmod 777 "\$TMPDIR" 2>/dev/null || true

if [ -z "\$PROOT_TMP_DIR" ] || [ ! -d "\$PROOT_TMP_DIR" ]; then
    PROOT_RUN_TMP="\$FILES_DIR/proot_tmp/p_\$\$"
    mkdir -p "\$PROOT_RUN_TMP"
    chmod 700 "\$PROOT_RUN_TMP" 2>/dev/null || true
    export PROOT_TMP_DIR="\$PROOT_RUN_TMP"
    trap 'rm -rf "\$PROOT_RUN_TMP" 2>/dev/null || true' EXIT INT TERM
fi
export PROOT_LOADER="\$PROOT_LIB_DIR/libprootloader.so"
export PROOT_LOADER_32="\$PROOT_LIB_DIR/libprootloader32.so"
export LD_LIBRARY_PATH="\$FILES_DIR/lib:\$PROOT_LIB_DIR"
export PATH="/usr/local/sbin:/usr/local/bin:/root/.bun/bin:/usr/local/lib/nodejs/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.local/bin:\$PATH"

# Prefer /root/jdk-17, Java 17, or Java 21 if available
if [ -d "\$ROOTFS/root/jdk-17" ]; then
    export JAVA_HOME="/root/jdk-17"
elif [ -d "\$ROOTFS/usr/lib/jvm/java-17-openjdk-arm64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
elif [ -d "\$ROOTFS/usr/lib/jvm/java-21-openjdk-arm64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-arm64"
else
    # Dynamically detect JVM folder inside \$ROOTFS/usr/lib/jvm/
    DETECTED_JVM=\$(ls -d "\$ROOTFS"/usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | grep -E '17|21' | head -n 1)
    [ -z "\$DETECTED_JVM" ] && DETECTED_JVM=\$(ls -d "\$ROOTFS"/usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)
    if [ -n "\$DETECTED_JVM" ]; then
        # Remove the \$ROOTFS prefix to get the path inside the guest
        export JAVA_HOME="\${DETECTED_JVM#\$ROOTFS}"
    else
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
    fi
fi
export ANDROID_HOME="/root/android-sdk"
export ANDROID_SDK_ROOT="/root/android-sdk"

FLUTTER_ALLOW_SU_ROOT=true
export FLUTTER_ALLOW_SU_ROOT
# Force IPv4 only in _JAVA_OPTIONS (never put -Xmx here, otherwise every child Java process reserves a huge heap)
_JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
export _JAVA_OPTIONS
export DART_VM_OPTIONS="--old_gen_heap_size=768"
if [ -f /usr/bin/aapt2 ]; then
    GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dkotlin.compiler.execution.strategy=in-process -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.enableJetifier=false -Dandroid.aapt2FromMavenOverride=/usr/bin/aapt2"
else
    BUILD_TOOLS_AAPT2=\$(find /root/android-sdk/build-tools -name "aapt2" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "\$BUILD_TOOLS_AAPT2" ]; then
        GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dkotlin.compiler.execution.strategy=in-process -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.enableJetifier=false -Dandroid.aapt2FromMavenOverride=\$BUILD_TOOLS_AAPT2"
    else
        GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dkotlin.compiler.execution.strategy=in-process -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.enableJetifier=false"
    fi
fi
export GRADLE_OPTS

# Auto-fix resolv.conf: if it is a broken symlink (e.g. -> stub-resolv.conf that
# does not exist on Android), replace it with a real file containing working DNS.
if [ -L "\$TMPDIR/resolv.conf" ] || [ ! -f "\$TMPDIR/resolv.conf" ]; then
    rm -f "\$TMPDIR/resolv.conf"
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "\$TMPDIR/resolv.conf"
fi

# Auto-fix hosts & nsswitch.conf so `localhost` resolves locally (required by Go CLI binaries like `agy`)
if [ -L "\$TMPDIR/hosts" ] || [ ! -f "\$TMPDIR/hosts" ] || ! grep -qE '127\.0\.0\.1[[:space:]]+localhost' "\$TMPDIR/hosts" 2>/dev/null; then
    rm -f "\$TMPDIR/hosts"
    printf '127.0.0.1 localhost localhost.localdomain quantum-ide\n::1 localhost ip6-localhost ip6-loopback\n' > "\$TMPDIR/hosts"
fi
if [ -L "\$TMPDIR/nsswitch.conf" ] || [ ! -f "\$TMPDIR/nsswitch.conf" ] || ! grep -qE '^[[:space:]]*hosts:[[:space:]]*files' "\$TMPDIR/nsswitch.conf" 2>/dev/null; then
    rm -f "\$TMPDIR/nsswitch.conf"
    printf 'passwd: files\ngroup: files\nshadow: files\nhosts: files dns\nnetworks: files\nprotocols: files\nservices: files\nethers: files\nrpc: files\n' > "\$TMPDIR/nsswitch.conf"
fi
mkdir -p "\$ROOTFS/etc" 2>/dev/null || true
for etc_f in hosts nsswitch.conf; do
    if [ -L "\$ROOTFS/etc/\$etc_f" ]; then
        rm -f "\$ROOTFS/etc/\$etc_f" 2>/dev/null || true
    fi
    if [ ! -f "\$ROOTFS/etc/\$etc_f" ]; then
        cp -f "\$TMPDIR/\$etc_f" "\$ROOTFS/etc/\$etc_f" 2>/dev/null || touch "\$ROOTFS/etc/\$etc_f" 2>/dev/null || true
    fi
done

# Android system & APEX mounts (required for Bionic linker64, aapt2, NDK, and devices running Android 10+)
SYS_BINDS=""
for sys_dir in /system /apex /vendor /product; do
    if [ -d "\$sys_dir" ]; then
        mkdir -p "\$ROOTFS\$sys_dir"
        SYS_BINDS="\$SYS_BINDS --bind=\$sys_dir"
    fi
done

# Proot handles stdio pipes automatically; avoid binding individual /proc/self/fd/0,1,2
# as Android PRoot cannot canonicalize them and outputs warnings
FD_BINDS=""
if [ -d /proc/self/fd ]; then
    FD_BINDS="--bind=/proc/self/fd:/dev/fd"
fi

# Ensure guest cwd exists on host or fallback to /root
if [ "\$GUEST_CWD" != "/root" ]; then
    case "\$GUEST_CWD" in
        /root/projects/*)
            REL_P="\${GUEST_CWD#/root/projects/}"
            mkdir -p "\$FILES_DIR/projects/\$REL_P" 2>/dev/null || true
            ;;
        /root/projects)
            mkdir -p "\$FILES_DIR/projects" 2>/dev/null || true
            ;;
        /sdcard/*)
            REL_S="\${GUEST_CWD#/sdcard/}"
            mkdir -p "/storage/emulated/0/\$REL_S" 2>/dev/null || true
            ;;
        /root/projects/external/*)
            REL_E="\${GUEST_CWD#/root/projects/external/}"
            mkdir -p "/storage/emulated/0/QuantumIDE/\$REL_E" 2>/dev/null || true
            ;;
        *)
            if [ ! -d "\$ROOTFS\$GUEST_CWD" ]; then
                GUEST_CWD="/root"
            fi
            ;;
    esac
fi

EXTERNAL_BIND=""
if [ -d "/storage/emulated/0/QuantumIDE" ]; then
    EXTERNAL_BIND="--bind=/storage/emulated/0/QuantumIDE:/root/projects/external"
fi

# shellcheck disable=SC2086
if [ \$# -gt 2 ]; then
    shift 2
    exec "\$PROOT" \\
        --link2symlink -L --kill-on-exit \\
        --rootfs="\$ROOTFS" --cwd="\$GUEST_CWD" \\
        --bind=/dev --bind=/proc --bind=/sys \\
        --bind=/dev/urandom:/dev/random \\
        \$FD_BINDS \$SYS_BINDS \\
        --bind="\$TMPDIR/resolv.conf:/etc/resolv.conf" \\
        --bind="\$TMPDIR/hosts:/etc/hosts" \\
        --bind="\$TMPDIR/nsswitch.conf:/etc/nsswitch.conf" \\
        --bind="\$CONFIG/proc_fakes/loadavg:/proc/loadavg" \\
        --bind="\$CONFIG/proc_fakes/stat:/proc/stat" \\
        --bind="\$CONFIG/proc_fakes/uptime:/proc/uptime" \\
        --bind="\$CONFIG/proc_fakes/version:/proc/version" \\
        --bind="\$CONFIG/proc_fakes/vmstat:/proc/vmstat" \\
        --bind="\$CONFIG/proc_fakes/cap_last_cap:/proc/sys/kernel/cap_last_cap" \\
        --bind="\$CONFIG/proc_fakes/max_user_watches:/proc/sys/fs/inotify/max_user_watches" \\
        --bind="\$CONFIG/proc_fakes/fips_enabled:/proc/sys/crypto/fips_enabled" \\
        --bind="\$CONFIG/proc_fakes/statm:/proc/self/statm" \\
        --bind="\$CONFIG/sys_fakes/empty:/sys/fs/selinux" \\
        --bind="\$FILES_DIR/projects:/root/projects" \\
        --bind="/storage/emulated/0:/sdcard" \\
        \$EXTERNAL_BIND \\
        --bind="\$FILES_DIR/tmp:/tmp" \\
        --bind="\$ROOTFS/tmp:/dev/shm" \\
        \$BIND_OVERLAYS -0 /bin/bash -c '
            export HOME=/root USER=root TMPDIR=/tmp TEMP=/tmp
            export PATH="\$1" JAVA_HOME="\$2" ANDROID_HOME="\$3" ANDROID_SDK_ROOT="\$4"
            export LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive
            export FLUTTER_ALLOW_SU_ROOT=true
            export BOX64_DYNAREC_STRONGMEM=1 BOX64_DYNAREC_BIGBLOCK=0 BOX64_DYNAREC_SAFEFLAGS=2 BOX64_NOBANNER=1 MALLOC_ARENA_MAX=2
            export CCACHE_DIR=/root/.ccache
            export LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/lib/aarch64-linux-gnu:/lib"
            export TERM=xterm-256color COLORTERM=truecolor
            export TERMINFO_DIRS=/usr/share/terminfo:/lib/terminfo:/etc/terminfo
            export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
            export SSL_CERT_DIR=/etc/ssl/certs
            export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
            export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
            export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
            export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
            stty sane onlcr icrnl opost erase ^? 2>/dev/null || true
            shift 4
            if [ "\$1" = "/bin/bash" ] && [ "\$2" = "-c" ]; then
                shift 2
                eval "\$*"
            else
                exec "\$@"
            fi
        ' dummy "\$PATH" "\$JAVA_HOME" "\$ANDROID_HOME" "\$ANDROID_SDK_ROOT" "\$@"
else
    # Auto-setup ARM64 environment in background (only once until done.flag is created)
    if [ ! -f "\$TMPDIR/setup_arm64_done.flag" ] && [ ! -f "\$ROOTFS/tmp/setup_arm64_done.flag" ]; then
        (
          sleep 2 # Wait for session to start
          "\$PROOT" \\
              --link2symlink -L \\
              --rootfs="\$ROOTFS" \\
              -0 /bin/bash -c 'PATH="\$1"; exec /bin/bash /root/setup-arm64.sh > /tmp/setup_arm64.log 2>&1' dummy "\$PATH"
        ) >/dev/null 2>&1 &
    fi

    exec "\$PROOT" \\
        --link2symlink -L --kill-on-exit \\
        --rootfs="\$ROOTFS" --cwd="\$GUEST_CWD" \\
        --bind=/dev --bind=/proc --bind=/sys \\
        --bind=/dev/urandom:/dev/random \\
        \$FD_BINDS \$SYS_BINDS \\
        --bind="\$TMPDIR/resolv.conf:/etc/resolv.conf" \\
        --bind="\$TMPDIR/hosts:/etc/hosts" \\
        --bind="\$TMPDIR/nsswitch.conf:/etc/nsswitch.conf" \\
        --bind="\$CONFIG/proc_fakes/loadavg:/proc/loadavg" \\
        --bind="\$CONFIG/proc_fakes/stat:/proc/stat" \\
        --bind="\$CONFIG/proc_fakes/uptime:/proc/uptime" \\
        --bind="\$CONFIG/proc_fakes/version:/proc/version" \\
        --bind="\$CONFIG/proc_fakes/vmstat:/proc/vmstat" \\
        --bind="\$CONFIG/proc_fakes/cap_last_cap:/proc/sys/kernel/cap_last_cap" \\
        --bind="\$CONFIG/proc_fakes/max_user_watches:/proc/sys/fs/inotify/max_user_watches" \\
        --bind="\$CONFIG/proc_fakes/fips_enabled:/proc/sys/crypto/fips_enabled" \\
        --bind="\$CONFIG/proc_fakes/statm:/proc/self/statm" \\
        --bind="\$CONFIG/sys_fakes/empty:/sys/fs/selinux" \\
        --bind="\$FILES_DIR/projects:/root/projects" \\
        --bind="/storage/emulated/0:/sdcard" \\
        \$EXTERNAL_BIND \\
        --bind="\$FILES_DIR/tmp:/tmp" \\
        --bind="\$ROOTFS/tmp:/dev/shm" \\
        \$BIND_OVERLAYS -0 /bin/bash -c '
            export HOME=/root USER=root TMPDIR=/tmp TEMP=/tmp
            export PATH="\$1" JAVA_HOME="\$2" ANDROID_HOME="\$3" ANDROID_SDK_ROOT="\$4"
            export LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive
            export FLUTTER_ALLOW_SU_ROOT=true
            export LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/lib/aarch64-linux-gnu:/lib"
            export TERM=xterm-256color COLORTERM=truecolor
            export TERMINFO_DIRS=/usr/share/terminfo:/lib/terminfo:/etc/terminfo
            export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
            export SSL_CERT_DIR=/etc/ssl/certs
            export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
            export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
            export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
            export GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
            stty sane onlcr icrnl opost erase ^? 2>/dev/null || true
            exec /bin/bash --rcfile /root/.bashrc -i
        ' dummy "\$PATH" "\$JAVA_HOME" "\$ANDROID_HOME" "\$ANDROID_SDK_ROOT"
fi
''';
  }

  Future<void> _bootstrapRootfs() async {
    _status = 'Downloading Ubuntu Core Runtime (ARM64)...';
    notifyListeners();

    final tmpDir = Directory(p.join(_filesDir, 'tmp'));
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);

    final archivePath = p.join(_filesDir, 'tmp', 'rootfs.tar.zst');
    final file = File(archivePath);
    if (await file.exists()) {
      await file.delete();
    }

    bool downloadSuccess = false;
    dynamic lastError;

    for (final url in _rootfsUrls) {
      try {
        debugPrint('RuntimeService: Attempting to download rootfs from $url');
        await _dio.download(
          url,
          archivePath,
          onReceiveProgress: (count, total) {
            final mb = (count / 1048576).toStringAsFixed(1);
            if (total > 0) {
              _progress = count / total * 0.7;
              final totalMb = (total / 1048576).toStringAsFixed(1);
              _status = 'Скачивание Ubuntu: $mb / $totalMb МБ (${(count * 100 / total).toStringAsFixed(0)}%)';
            } else {
              _status = 'Скачивание Ubuntu: $mb МБ';
            }
            notifyListeners();
          },
        );
        downloadSuccess = true;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('RuntimeService: Download from $url failed ($e), trying next fallback mirror...');
      }
    }

    if (!downloadSuccess) {
      throw Exception('Не удалось скачать базовый образ Ubuntu: $lastError');
    }

    _status = 'Распаковка Ubuntu (zstd)… это может занять 1–3 минуты';
    _progress = 0.7;
    notifyListeners();

    await _channel.invokeMethod('extractRootfs', {'tarPath': archivePath});

    // RootfsRepair: Restore preserved user files into rebuilt /root
    final backupHomeDir = Directory(p.join(_filesDir, 'tmp', 'preserved_home'));
    if (await backupHomeDir.exists()) {
      try {
        final restoredHome = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root'));
        if (await restoredHome.exists()) {
          final entries = backupHomeDir.listSync(recursive: true, followLinks: false);
          for (final entry in entries) {
            final rel = p.relative(entry.path, from: backupHomeDir.path);
            final targetPath = p.join(restoredHome.path, rel);
            if (entry is Link) {
              final target = entry.targetSync();
              final destLink = Link(targetPath);
              await destLink.parent.create(recursive: true);
              if (FileSystemEntity.typeSync(targetPath, followLinks: false) == FileSystemEntityType.notFound) {
                await destLink.create(target);
              }
            } else if (entry is File) {
              final targetFile = File(targetPath);
              await targetFile.parent.create(recursive: true);
              await entry.copy(targetFile.path);
            }
          }
          debugPrint('RuntimeService: Successfully restored preserved user files to /root');
          await _forceDeleteDirectory(backupHomeDir);
        }
      } catch (e) {
        debugPrint('RuntimeService: Error restoring preserved home: $e');
      }
    }

    _status = 'Finalizing...';
    _progress = 1.0;
    notifyListeners();
  }

  String get prootCommand => p.join(_filesDir, 'bin', 'init-host');
  String get appDirectory => _filesDir;
  /// On Android/iOS: returns the PRoot guest home (/root).
  /// On Desktop: returns the actual system HOME directory.
  String get workingDirectory {
    if (Platform.isAndroid || Platform.isIOS) return '/root';
    return PlatformUtils.userHomeDir;
  }

  String? _cachedJavaHome;
  String? _cachedAapt2;

  String get _detectedJavaHome {
    if (_cachedJavaHome != null) return _cachedJavaHome!;
    final jvmDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'lib', 'jvm'));
    if (jvmDir.existsSync()) {
      try {
        final entities = jvmDir.listSync();
        for (final entity in entities) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (name.startsWith('java-') && name.endsWith('-openjdk-arm64')) {
              _cachedJavaHome = '/usr/lib/jvm/$name';
              return _cachedJavaHome!;
            }
          }
        }
      } catch (_) {}
    }
    final rootJdk = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root', 'jdk-17'));
    if (rootJdk.existsSync()) {
      _cachedJavaHome = '/root/jdk-17';
      return _cachedJavaHome!;
    }
    _cachedJavaHome = '/usr/lib/jvm/java-17-openjdk-arm64';
    return _cachedJavaHome!;
  }

  String get _detectedAapt2 {
    if (_cachedAapt2 != null) return _cachedAapt2!;
    final usrBinAapt2 = File(p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'bin', 'aapt2'));
    if (usrBinAapt2.existsSync()) {
      _cachedAapt2 = '/usr/bin/aapt2';
      return _cachedAapt2!;
    }
    try {
      final buildToolsDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'build-tools'));
      if (buildToolsDir.existsSync()) {
        final entities = buildToolsDir.listSync();
        final dirs = entities
            .whereType<Directory>()
            .map((d) => p.basename(d.path))
            .toList();
        if (dirs.isNotEmpty) {
          dirs.sort((a, b) => b.compareTo(a));
          _cachedAapt2 = '/root/android-sdk/build-tools/${dirs.first}/aapt2';
          return _cachedAapt2!;
        }
      }
    } catch (_) {}
    _cachedAapt2 = '/usr/bin/aapt2';
    return _cachedAapt2!;
  }

  Map<String, String> get env {
    // Desktop: return desktopEnv with all discovered SDKs and user binary paths (agy, flutter, etc.)
    if (!Platform.isAndroid && !Platform.isIOS) {
      return desktopEnv;
    }
    if (Platform.isAndroid && _useNativeRootMode) {
      final nativeHome = p.join(_filesDir, 'home');
      final nativeTmp = p.join(_filesDir, 'tmp');
      final nativeBin = p.join(_filesDir, 'bin');
      return {
        'HOME': nativeHome,
        'TMPDIR': nativeTmp,
        'TEMP': nativeTmp,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        'ANDROID_HOME': p.join(nativeHome, 'android-sdk'),
        'ANDROID_SDK_ROOT': p.join(nativeHome, 'android-sdk'),
        'FLUTTER_ROOT': p.join(nativeHome, 'flutter'),
        'PATH':
            '$nativeHome/flutter/bin:$nativeHome/android-sdk/cmdline-tools/latest/bin:$nativeHome/android-sdk/platform-tools:$nativeHome/.bun/bin:$nativeHome/.local/bin:$nativeBin:/data/data/com.termux/files/usr/bin:/data/user/0/com.termux/files/usr/bin:/data/user/0/com.agy/files/usr/bin:/system/bin:/system/xbin:/sbin:/vendor/bin',
        'USER': 'root',
        'LANG': 'C.UTF-8',
        'LC_ALL': 'C.UTF-8',
        'FLUTTER_ALLOW_SU_ROOT': 'true',
      };
    }
    // Android/iOS: use PRoot-specific environment
    return {
      'HOME': '/root',
      'TERM': 'xterm-256color',
      'COLORTERM': 'truecolor',
      'ANDROID_HOME': '/root/android-sdk',
      'ANDROID_SDK_ROOT': '/root/android-sdk',
      'PATH':
          '/usr/local/sbin:/usr/local/bin:/root/.bun/bin:/usr/local/lib/nodejs/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.local/bin',
      'JAVA_HOME': _detectedJavaHome,
      'FLUTTER_ROOT': '/root/flutter',
      'USER': 'root',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
      'SSL_CERT_FILE': '/etc/ssl/certs/ca-certificates.crt',
      'SSL_CERT_DIR': '/etc/ssl/certs',
      'REQUESTS_CA_BUNDLE': '/etc/ssl/certs/ca-certificates.crt',
      'CURL_CA_BUNDLE': '/etc/ssl/certs/ca-certificates.crt',
      'NODE_EXTRA_CA_CERTS': '/etc/ssl/certs/ca-certificates.crt',
      'GIT_SSL_CAINFO': '/etc/ssl/certs/ca-certificates.crt',
      'FLUTTER_ALLOW_SU_ROOT': 'true',
      // Force IPv4 only (never put -Xmx in _JAVA_OPTIONS, otherwise every child Java process reserves a huge heap)
      '_JAVA_OPTIONS': '-Djava.net.preferIPv4Stack=true',
      'GRADLE_OPTS':
          '-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1 -Dkotlin.compiler.execution.strategy=in-process -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.enableJetifier=false -Dandroid.aapt2FromMavenOverride=$_detectedAapt2',
    };
  }

  Future<void> reset({bool preserveHome = true}) async {
    _isInitialized = false;
    _status = 'Resetting...';
    _progress = 0;
    notifyListeners();

    try {
      final homeDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root'));
      final backupHomeDir = Directory(p.join(_filesDir, 'tmp', 'preserved_home'));

      // RootfsRepair (Mobile-Harness): Preserve user's home files (.bashrc, .ssh, .gitconfig, tools)
      if (preserveHome && await homeDir.exists()) {
        try {
          if (FileSystemEntity.typeSync(backupHomeDir.path, followLinks: false) != FileSystemEntityType.notFound) {
            await _forceDeleteDirectory(backupHomeDir);
          }
          await backupHomeDir.create(recursive: true);
          final entries = homeDir.listSync(recursive: true, followLinks: false);
          for (final entry in entries) {
            if (entry is File) {
              final rel = p.relative(entry.path, from: homeDir.path);
              // Avoid preserving huge cache directories
              if (rel.startsWith('.cache/') || rel.startsWith('.npm/_cacache/') || rel.startsWith('.gradle/caches/')) {
                continue;
              }
              final targetFile = File(p.join(backupHomeDir.path, rel));
              await targetFile.parent.create(recursive: true);
              await entry.copy(targetFile.path);
            }
          }
          debugPrint('RuntimeService: Preserved user /root files before reset');
        } catch (e) {
          debugPrint('RuntimeService: Failed to backup /root: $e');
        }
      }

      final rootfs = Directory(p.join(_filesDir, 'rootfs'));
      if (FileSystemEntity.typeSync(rootfs.path, followLinks: false) != FileSystemEntityType.notFound) {
        await _forceDeleteDirectory(rootfs);
      }

      _status = 'Cleaned. Ready for init.';
      notifyListeners();
    } catch (e) {
      _status = 'Error during reset: $e';
      notifyListeners();
    }
  }

  String _generateQuantumPatchNdkScript() {
    return r'''#!/bin/bash
# quantum-patch-ndk: Auto-heals Android NDK & CMake on ARM64 Linux / PRoot so
# official x86_64 Google NDKs and native ARM64 NDKs work seamlessly with CMake/Gradle.

SDK_ROOT="${ANDROID_HOME:-/root/android-sdk}"
[ ! -d "$SDK_ROOT" ] && exit 0

CLANG_BIN=$(ls /usr/bin/clang-[0-9]* 2>/dev/null | sort -V | tail -n 1)
CLANGPP_BIN=$(ls /usr/bin/clang++-[0-9]* 2>/dev/null | sort -V | tail -n 1)
LLD_BIN=$(ls /usr/bin/ld.lld-[0-9]* 2>/dev/null | sort -V | tail -n 1)

if [ -z "$CLANG_BIN" ] && [ -x /usr/bin/clang ]; then CLANG_BIN="/usr/bin/clang"; fi
if [ -z "$CLANGPP_BIN" ] && [ -x /usr/bin/clang++ ]; then CLANGPP_BIN="/usr/bin/clang++"; fi
if [ -z "$LLD_BIN" ] && [ -x /usr/bin/ld.lld ]; then LLD_BIN="/usr/bin/ld.lld"; fi

if [ -z "$CLANG_BIN" ] && [ "$1" != "--fast" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends clang-18 lld-18 llvm-18 ninja-build >/dev/null 2>&1 || \
    apt-get install -y --no-install-recommends clang lld llvm ninja-build >/dev/null 2>&1 || true
    CLANG_BIN=$(ls /usr/bin/clang-[0-9]* 2>/dev/null | sort -V | tail -n 1)
    CLANGPP_BIN=$(ls /usr/bin/clang++-[0-9]* 2>/dev/null | sort -V | tail -n 1)
    LLD_BIN=$(ls /usr/bin/ld.lld-[0-9]* 2>/dev/null | sort -V | tail -n 1)
fi

[ -z "$CLANG_BIN" ] && exit 0
[ -z "$CLANGPP_BIN" ] && CLANGPP_BIN="$CLANG_BIN"

[ ! -e /usr/bin/clang ] && ln -sf "$CLANG_BIN" /usr/bin/clang 2>/dev/null || true
[ ! -e /usr/bin/clang++ ] && ln -sf "$CLANGPP_BIN" /usr/bin/clang++ 2>/dev/null || true
[ -n "$LLD_BIN" ] && [ ! -e /usr/bin/ld.lld ] && ln -sf "$LLD_BIN" /usr/bin/ld.lld 2>/dev/null || true

CLANG_RES_DIR=$("$CLANG_BIN" -print-resource-dir 2>/dev/null)

if [ -d "$SDK_ROOT/ndk" ]; then
    BASE_NDK=""
    for ndk in "$SDK_ROOT/ndk/"*; do
        [ -d "$ndk" ] || continue
        [ -L "$ndk" ] && continue

        if [ -d "$ndk/toolchains/llvm/prebuilt/linux-arm64" ]; then
            [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-x86_64" ] && ln -sfn linux-arm64 "$ndk/toolchains/llvm/prebuilt/linux-x86_64" 2>/dev/null || true
            [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-aarch64" ] && ln -sfn linux-arm64 "$ndk/toolchains/llvm/prebuilt/linux-aarch64" 2>/dev/null || true
            chmod +x "$ndk/ndk-build" "$ndk/toolchains/llvm/prebuilt/linux-arm64/bin/"* 2>/dev/null || true
            BASE_NDK="$ndk"
            continue
        fi
        if [ -d "$ndk/toolchains/llvm/prebuilt/linux-aarch64" ]; then
            [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-x86_64" ] && ln -sfn linux-aarch64 "$ndk/toolchains/llvm/prebuilt/linux-x86_64" 2>/dev/null || true
            [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-arm64" ] && ln -sfn linux-aarch64 "$ndk/toolchains/llvm/prebuilt/linux-arm64" 2>/dev/null || true
            chmod +x "$ndk/ndk-build" "$ndk/toolchains/llvm/prebuilt/linux-aarch64/bin/"* 2>/dev/null || true
            BASE_NDK="$ndk"
            continue
        fi

        PREBUILT="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
        [ -d "$PREBUILT" ] || continue
        BASE_NDK="$ndk"

        NDK_BIN="$PREBUILT/bin"
        SYSROOT="$PREBUILT/sysroot"
        mkdir -p "$NDK_BIN"

        NDK_RES_DIR=$(ls -d "$PREBUILT/lib/clang/"* 2>/dev/null | sort -V | tail -n 1)

        if [ -n "$CLANG_RES_DIR" ] && [ -n "$NDK_RES_DIR" ] && [ -d "$NDK_RES_DIR/lib/linux" ]; then
            mkdir -p "$CLANG_RES_DIR/lib" 2>/dev/null || true
            if [ ! -e "$CLANG_RES_DIR/lib/linux" ]; then
                ln -sfn "$NDK_RES_DIR/lib/linux" "$CLANG_RES_DIR/lib/linux" 2>/dev/null || true
            fi
        fi

        if [ -n "$NDK_RES_DIR" ] && [ -d "$NDK_RES_DIR/lib/linux" ]; then
            for pair in "aarch64:aarch64" "arm:arm" "i386:i686" "x86_64:x86_64"; do
                u_arch="${pair%:*}"
                rt_arch="${pair#*:}"
                if [ -d "$NDK_RES_DIR/lib/linux/$u_arch" ]; then
                    rm -f "$NDK_RES_DIR/lib/linux/$u_arch/libgcc.a" 2>/dev/null || true
                    echo "GROUP(../libclang_rt.builtins-${rt_arch}-android.a libunwind.a)" > "$NDK_RES_DIR/lib/linux/$u_arch/libgcc.a" 2>/dev/null || true
                fi
            done
        fi

        if [ -f "$NDK_BIN/.quantum_patched_v4" ]; then
            continue
        fi

        for target in clang clang-14 clang-15 clang-16 clang-17 clang-18 clang-19 clang-20 clang-21; do
            rm -f "$NDK_BIN/$target"
            cat << WRAP_EOF > "$NDK_BIN/$target"
#!/bin/bash
export PATH="$NDK_BIN:/usr/bin:\$PATH"
exec "$CLANG_BIN" -Qunused-arguments "\$@"
WRAP_EOF
            chmod +x "$NDK_BIN/$target"
        done

        rm -f "$NDK_BIN/clang++"
        cat << WRAP_EOF > "$NDK_BIN/clang++"
#!/bin/bash
export PATH="$NDK_BIN:/usr/bin:\$PATH"
exec "$CLANGPP_BIN" -Qunused-arguments "\$@"
WRAP_EOF
        chmod +x "$NDK_BIN/clang++"

        if [ -n "$LLD_BIN" ] && [ -x "$LLD_BIN" ]; then
            for ld_tool in ld ld.lld lld; do
                rm -f "$NDK_BIN/$ld_tool"
                printf '#!/bin/bash\nexec "%s" "$@"\n' "$LLD_BIN" > "$NDK_BIN/$ld_tool"
                chmod +x "$NDK_BIN/$ld_tool"
            done
        fi

        for tool in llvm-ar llvm-ranlib llvm-strip llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-readobj llvm-symbolizer llvm-strings llvm-cxxfilt llvm-as llvm-dis llvm-link llvm-cov llvm-profdata llvm-size llvm-rc llvm-ml llvm-lib llvm-dlltool; do
            SYS_TOOL=$(ls /usr/bin/${tool}-[0-9]* 2>/dev/null | sort -V | tail -n 1)
            [ -z "$SYS_TOOL" ] && SYS_TOOL="/usr/bin/$tool"
            if [ -x "$SYS_TOOL" ]; then
                rm -f "$NDK_BIN/$tool"
                printf '#!/bin/bash\nexec "%s" "$@"\n' "$SYS_TOOL" > "$NDK_BIN/$tool"
                chmod +x "$NDK_BIN/$tool"
            fi
        done

        LLVM_AR=$(ls /usr/bin/llvm-ar-[0-9]* 2>/dev/null | sort -V | tail -n 1)
        [ -z "$LLVM_AR" ] && LLVM_AR="/usr/bin/llvm-ar"
        if [ -x "$LLVM_AR" ] && [ -d "$SYSROOT" ]; then
            for triple in aarch64-linux-android arm-linux-androideabi x86_64-linux-android i686-linux-android; do
                abi_dir="$SYSROOT/usr/lib/$triple"
                [ -d "$abi_dir" ] || continue
                case "$triple" in
                    aarch64-linux-android) rt_arch="aarch64"; unwind_arch="aarch64" ;;
                    arm-linux-androideabi) rt_arch="arm";     unwind_arch="arm" ;;
                    i686-linux-android)    rt_arch="i686";    unwind_arch="i386" ;;
                    x86_64-linux-android)  rt_arch="x86_64";  unwind_arch="x86_64" ;;
                esac
                RT_FILE=""
                UNWIND_FILE=""
                ATOMIC_FILE=""
                if [ -n "$NDK_RES_DIR" ]; then
                    [ -f "$NDK_RES_DIR/lib/linux/libclang_rt.builtins-${rt_arch}-android.a" ] && RT_FILE="$NDK_RES_DIR/lib/linux/libclang_rt.builtins-${rt_arch}-android.a"
                    [ -f "$NDK_RES_DIR/lib/linux/$unwind_arch/libunwind.a" ] && UNWIND_FILE="$NDK_RES_DIR/lib/linux/$unwind_arch/libunwind.a"
                    [ -f "$NDK_RES_DIR/lib/linux/$unwind_arch/libatomic.a" ] && ATOMIC_FILE="$NDK_RES_DIR/lib/linux/$unwind_arch/libatomic.a"
                fi
                for dest_dir in "$abi_dir" "$abi_dir"/*/; do
                    [ -d "$dest_dir" ] || continue
                    if [ -n "$ATOMIC_FILE" ]; then
                        cp -f "$ATOMIC_FILE" "${dest_dir%/}/libatomic.a" 2>/dev/null || true
                    else
                        [ -f "${dest_dir%/}/libatomic.a" ] || "$LLVM_AR" rcs "${dest_dir%/}/libatomic.a" 2>/dev/null || true
                    fi
                    if [ -n "$UNWIND_FILE" ]; then
                        cp -f "$UNWIND_FILE" "${dest_dir%/}/libunwind.a" 2>/dev/null || true
                    fi
                    if [ -n "$RT_FILE" ]; then
                        cp -f "$RT_FILE" "${dest_dir%/}/libgcc_real.a" 2>/dev/null || true
                        if [ -f "${dest_dir%/}/libunwind.a" ]; then
                            echo "GROUP(libgcc_real.a libunwind.a)" > "${dest_dir%/}/libgcc.a"
                        else
                            cp -f "$RT_FILE" "${dest_dir%/}/libgcc.a" 2>/dev/null || true
                        fi
                    else
                        [ -f "${dest_dir%/}/libgcc.a" ] || "$LLVM_AR" rcs "${dest_dir%/}/libgcc.a" 2>/dev/null || true
                    fi
                done
            done
        fi

        if [ ! -f "$ndk/source.properties" ]; then
            NDK_VER=$(basename "$ndk")
            printf "Pkg.Desc = Android NDK\nPkg.Revision = %s\n" "$NDK_VER" > "$ndk/source.properties"
        fi

        touch "$NDK_BIN/.quantum_patched_v4"
    done

    if [ -n "$BASE_NDK" ] && [ -d "$BASE_NDK" ]; then
        BASE_VER=$(basename "$BASE_NDK")
        for ver in 25.1.8937393 26.1.10909125 26.3.11579264 27.0.12077973 28.0.12433547 28.2.13676358 29.0.14206865; do
            TARGET_NDK="$SDK_ROOT/ndk/$ver"
            if [ ! -d "$TARGET_NDK" ]; then
                mkdir -p "$TARGET_NDK"
                for item in "$BASE_NDK"/*; do
                    name=$(basename "$item")
                    if [ "$name" = "source.properties" ] || [ "$name" = "package.xml" ]; then
                        continue
                    fi
                    ln -sfn "$item" "$TARGET_NDK/$name" 2>/dev/null || true
                done
                printf "Pkg.Desc = Android NDK\nPkg.Revision = %s\nPkg.BaseRevision = %s\n" "$ver" "$ver" > "$TARGET_NDK/source.properties"
                if [ -f "$BASE_NDK/package.xml" ]; then
                    major=$(echo "$ver" | cut -d. -f1)
                    minor=$(echo "$ver" | cut -d. -f2)
                    micro=$(echo "$ver" | cut -d. -f3)
                    sed -e "s/ndk;$BASE_VER/ndk;$ver/g" \
                        -e "s/<major>[0-9]*<\/major>/<major>$major<\/major>/g" \
                        -e "s/<minor>[0-9]*<\/minor>/<minor>$minor<\/minor>/g" \
                        -e "s/<micro>[0-9]*<\/micro>/<micro>$micro<\/micro>/g" \
                        "$BASE_NDK/package.xml" > "$TARGET_NDK/package.xml" 2>/dev/null || true
                fi
            fi
        done
    fi
fi

REAL_CMAKE="/opt/cmake-3.22.1/bin/cmake"
[ ! -x "$REAL_CMAKE" ] && REAL_CMAKE="/usr/local/bin/cmake"
[ ! -x "$REAL_CMAKE" ] && REAL_CMAKE="/usr/bin/cmake"

if [ -x "$REAL_CMAKE" ]; then
    for cmver in 3.18.1 3.22.1 3.31.0; do
        CM_DIR="$SDK_ROOT/cmake/$cmver"
        mkdir -p "$CM_DIR/bin"
        if [ -L "$CM_DIR/bin/cmake" ] || ! grep -q "quantum-patch-ndk" "$CM_DIR/bin/cmake" 2>/dev/null; then
            rm -f "$CM_DIR/bin/cmake"
            cat << CM_EOF > "$CM_DIR/bin/cmake"
#!/bin/bash
/usr/local/bin/quantum-patch-ndk --fast 2>/dev/null || true
exec "$REAL_CMAKE" "\$@"
CM_EOF
            chmod +x "$CM_DIR/bin/cmake"
        fi
        command -v ninja >/dev/null 2>&1 && ln -sf "$(command -v ninja)" "$CM_DIR/bin/ninja" 2>/dev/null || true
        [ ! -f "$CM_DIR/source.properties" ] && printf "Pkg.Desc = CMake %s\nPkg.Revision = %s\n" "$cmver" "$cmver" > "$CM_DIR/source.properties"
    done
fi

# Auto-heal pub-cache plugins that reference Android 36 BAKLAVA / Java 21 APIs
# against SDK 34/35 platform stubs (e.g. sqflite_android >= 2.4.4)
for pub_dir in "${PUB_CACHE:-/root/.pub-cache}" "$HOME/.pub-cache"; do
    [ -d "$pub_dir/hosted/pub.dev" ] || continue
    for utils_java in "$pub_dir/hosted/pub.dev"/sqflite_android-*/android/src/main/java/com/tekartik/sqflite/Utils.java; do
        [ -f "$utils_java" ] || continue
        if grep -q "BAKLAVA" "$utils_java" 2>/dev/null; then
            python3 - "$utils_java" << 'PY_EOF' 2>/dev/null || true
import re, sys
p = sys.argv[1]
with open(p, 'r', encoding='utf-8') as f:
    s = f.read()
s = re.sub(
    r'static\s+Locale\s+localOf\s*\([^)]*\)\s*\{.*?\n    \}',
    'static Locale localOf(String language, String country, String variant) {\n        @SuppressWarnings("deprecation")\n        Locale locale = new Locale(language, country, variant);\n        return locale;\n    }',
    s,
    flags=re.DOTALL,
)
s = re.sub(
    r'public\s+static\s+long\s+getThreadId\s*\([^)]*\)\s*\{.*?\n    \}',
    'public static long getThreadId(Thread thread) {\n        @SuppressWarnings("deprecation")\n        long id = thread.getId();\n        return id;\n    }',
    s,
    flags=re.DOTALL,
)
with open(p, 'w', encoding='utf-8') as f:
    f.write(s)
PY_EOF
        fi
    done
done

# Auto-heal Flutter ARM64 host gen_snapshot for release/profile builds.
# Native Android requires 'product arm64 android compressed-pointers'.
# Box64 runs official Google x64 gen_snapshot with native dynarec on ARM64.
for fl_dir in "${FLUTTER_ROOT:-}" "/root/flutter" "$HOME/flutter" "/data/data/com.acside/files/home/flutter"; do
    [ -n "$fl_dir" ] && [ -d "$fl_dir/bin/cache/artifacts/engine" ] || continue
    FLUTTER_ENGINE="$fl_dir/bin/cache/artifacts/engine"
    ENGINE_HASH=$(cat "$fl_dir/bin/internal/engine.version" 2>/dev/null || true)
    for mode in release profile; do
        for arch in arm64 arm x64; do
            TARGET_PARENT="$FLUTTER_ENGINE/android-$arch-$mode"
            [ -d "$TARGET_PARENT" ] || mkdir -p "$TARGET_PARENT" 2>/dev/null || true
            ENGINE_DIR="$TARGET_PARENT/linux-arm64"
            X64_DIR="$TARGET_PARENT/linux-x64"
            mkdir -p "$ENGINE_DIR" "$X64_DIR" 2>/dev/null || true

            # Download official x64 gen_snapshot if neither real bin nor snapshot exists
            if [ ! -s "$X64_DIR/gen_snapshot.real" ] && [ ! -s "$X64_DIR/gen_snapshot" ] && [ -n "$ENGINE_HASH" ]; then
                TMP_DL="${TMPDIR:-/tmp}/x64-$arch-$mode-$$.zip"
                (
                    curl -k -fsSL --retry 2 "https://storage.googleapis.com/flutter_infra_release/flutter/$ENGINE_HASH/android-$arch-$mode/linux-x64.zip" -o "$TMP_DL" || \
                    wget --no-check-certificate -qO "$TMP_DL" "https://storage.googleapis.com/flutter_infra_release/flutter/$ENGINE_HASH/android-$arch-$mode/linux-x64.zip"
                ) 2>/dev/null || true
                if [ -s "$TMP_DL" ]; then
                    unzip -qo "$TMP_DL" gen_snapshot -d "$X64_DIR" 2>/dev/null || true
                    rm -f "$TMP_DL" 2>/dev/null || true
                fi
            fi

            # Check if gen_snapshot in X64_DIR or ENGINE_DIR is an ELF binary (not a script)
            # If so, preserve it as gen_snapshot.real
            for chk_dir in "$X64_DIR" "$ENGINE_DIR"; do
                if [ -f "$chk_dir/gen_snapshot" ] && [ ! -f "$chk_dir/gen_snapshot.real" ]; then
                    if head -c 4 "$chk_dir/gen_snapshot" 2>/dev/null | grep -q "ELF"; then
                        mv "$chk_dir/gen_snapshot" "$chk_dir/gen_snapshot.real"
                    fi
                fi
            done

            # Ensure gen_snapshot.real exists in at least one location
            if [ ! -f "$ENGINE_DIR/gen_snapshot.real" ] && [ -f "$X64_DIR/gen_snapshot.real" ]; then
                cp -f "$X64_DIR/gen_snapshot.real" "$ENGINE_DIR/gen_snapshot.real" 2>/dev/null || true
            elif [ -f "$ENGINE_DIR/gen_snapshot.real" ] && [ ! -f "$X64_DIR/gen_snapshot.real" ]; then
                cp -f "$ENGINE_DIR/gen_snapshot.real" "$X64_DIR/gen_snapshot.real" 2>/dev/null || true
            fi

            # Write the universal wrapper
            cat << 'WRAP_GS' > "$ENGINE_DIR/gen_snapshot"
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_BIN=""
if [ -f "$DIR/gen_snapshot.real" ]; then
    REAL_BIN="$DIR/gen_snapshot.real"
elif [ -f "$DIR/../linux-x64/gen_snapshot.real" ]; then
    REAL_BIN="$DIR/../linux-x64/gen_snapshot.real"
elif [ -f "$DIR/../linux-x64/gen_snapshot" ] && head -c 4 "$DIR/../linux-x64/gen_snapshot" 2>/dev/null | grep -q "ELF"; then
    REAL_BIN="$DIR/../linux-x64/gen_snapshot"
elif [ -f "$DIR/gen_snapshot" ] && head -c 4 "$DIR/gen_snapshot" 2>/dev/null | grep -q "ELF"; then
    REAL_BIN="$DIR/gen_snapshot"
fi

ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dedup_instructions|--dedup-instructions|--no-dedup_instructions|--no-dedup-instructions)
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

# 1. Box64 (Fastest, native Dynarec, built-in wrapped libc/libm/libdl)
if command -v box64 >/dev/null 2>&1 && [ -n "$REAL_BIN" ]; then
    export BOX64_NOBANNER=1
    export BOX64_DYNAREC=1
    export BOX64_MMAP32=1
    export BOX64_LOG=0
    chmod +x "$REAL_BIN" 2>/dev/null || true
    exec box64 "$REAL_BIN" "${ARGS[@]}"
fi

# 2. QEMU user static fallback
EMU=""
if [ -x /usr/bin/qemu-x86_64-static ]; then
    EMU="/usr/bin/qemu-x86_64-static"
elif [ -x /usr/local/bin/qemu-x86_64-static ]; then
    EMU="/usr/local/bin/qemu-x86_64-static"
elif [ -f /sdcard/qemu-x86_64-static ]; then
    EMU="/sdcard/qemu-x86_64-static"
fi

if [ -n "$EMU" ] && [ -n "$REAL_BIN" ]; then
    chmod +x "$REAL_BIN" 2>/dev/null || true
    export QEMU_LD_PREFIX=/
    exec "$EMU" -L / "$REAL_BIN" "${ARGS[@]}"
fi

# 3. Direct execution fallback (if running on x86_64 PC or native)
if [ -n "$REAL_BIN" ]; then
    chmod +x "$REAL_BIN" 2>/dev/null || true
    exec "$REAL_BIN" "${ARGS[@]}"
fi

echo "ERROR: Flutter Release build requires Box64 or QEMU x86_64 emulator to execute gen_snapshot on ARM64!" >&2
echo "Please install 'box64-emulator' or 'Flutter Release Build Engine' from the Packages tab in Quantum IDE." >&2
exit 1
WRAP_GS
            chmod +x "$ENGINE_DIR/gen_snapshot" 2>/dev/null || true
            if [ "$ENGINE_DIR" != "$X64_DIR" ] && [ ! -L "$TARGET_PARENT/linux-arm64" ]; then
                cp -f "$ENGINE_DIR/gen_snapshot" "$X64_DIR/gen_snapshot" 2>/dev/null || true
                chmod +x "$X64_DIR/gen_snapshot" 2>/dev/null || true
            fi
        done
    done
done

# Auto-heal AAPT2 daemons and force native aapt2 on ARM64 PRoot
mkdir -p ~/.gradle 2>/dev/null || true
if ! grep -q "android.aapt2.daemon=false" ~/.gradle/gradle.properties 2>/dev/null; then
    printf "\nandroid.aapt2.daemon=false\nandroid.aapt2FromMaven=false\nandroid.useAndroidX=true\nandroid.enableJetifier=true\n" >> ~/.gradle/gradle.properties 2>/dev/null || true
fi

if [ -x /usr/bin/aapt2 ]; then
    find ~/.gradle/caches -name "aapt2" -type f 2>/dev/null | while read -r maven_aapt2; do
        if [ ! -L "$maven_aapt2" ]; then
            ln -sf /usr/bin/aapt2 "$maven_aapt2" 2>/dev/null || true
        fi
    done
fi
''';

  }

  String _generateQuantumHealX64Script() {
    return r'''#!/bin/bash
# quantum-heal-x64: Auto-heals x86_64 glibc libraries and ld-linux-x86-64.so.2 dynamic linker
# on ARM64 Linux / PRoot so Box64 / QEMU can execute Flutter's official gen_snapshot for release APKs.

# 0. Self-heal usrmerge /lib -> usr/lib symlink if an earlier extraction replaced it
if [ ! -L /lib ] && [ -d /lib ] && [ -d /usr/lib/aarch64-linux-gnu ] && [ -f /usr/lib/aarch64-linux-gnu/libc.so.6 ]; then
    echo "[quantum-heal-x64] Repairing broken /lib -> usr/lib symlink..."
    if [ -d /lib/x86_64-linux-gnu ]; then
        mkdir -p /usr/lib/x86_64-linux-gnu 2>/dev/null || true
        cp -a /lib/x86_64-linux-gnu/. /usr/lib/x86_64-linux-gnu/ 2>/dev/null || true
    fi
    rm -rf /lib.broken 2>/dev/null || true
    mv /lib /lib.broken 2>/dev/null && ln -s usr/lib /lib 2>/dev/null || true
    rm -rf /lib.broken 2>/dev/null || true
    if [ ! -e /usr/lib/ld-linux-aarch64.so.1 ] && [ -f /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 ]; then
        ln -sf aarch64-linux-gnu/ld-linux-aarch64.so.1 /usr/lib/ld-linux-aarch64.so.1 2>/dev/null || true
    fi
fi

mkdir -p /lib64 2>/dev/null || true

# 1. Box64 provides full native glibc emulation out of the box
if command -v box64 >/dev/null 2>&1; then
    echo "[quantum-heal-x64] ✓ Box64 emulator is active with native glibc wrapping."
    touch /root/.quantum_flutter_release_fix_installed ~/.quantum_flutter_release_fix_installed 2>/dev/null || true
fi

# 2. Quick check: already functional?
if [ -f /lib/x86_64-linux-gnu/libc.so.6 ] && [ -f /lib64/ld-linux-x86-64.so.2 ]; then
    echo "[quantum-heal-x64] ✓ x86_64 dynamic linker and glibc runtime already configured."
    touch /root/.quantum_flutter_release_fix_installed ~/.quantum_flutter_release_fix_installed 2>/dev/null || true
else
    echo "[quantum-heal-x64] Setting up x86_64 dynamic linker & glibc runtime for Flutter release builds..."

    # 3. Try fast direct deb extraction of libc6:amd64 into a staging directory
    # CRITICAL: Never run `dpkg -x ... /` on usrmerge Ubuntu 24.04 because legacy debs replace /lib -> usr/lib!
    if [ ! -f /lib/x86_64-linux-gnu/libc.so.6 ]; then
        DEB_DIR="${TMPDIR:-/tmp}/libc6_x64_download_$$"
        mkdir -p "$DEB_DIR/pkg" 2>/dev/null || true
        X64_LIB_DEST="/lib/x86_64-linux-gnu"
        [ -L /lib ] && X64_LIB_DEST="/usr/lib/x86_64-linux-gnu"
        for deb_url in \
            "http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.39-0ubuntu8.3_amd64.deb" \
            "http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.39-0ubuntu8_amd64.deb" \
            "http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.35-0ubuntu3.8_amd64.deb" \
            "http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.31-0ubuntu9.18_amd64.deb" \
            "http://security.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.35-0ubuntu3_amd64.deb"; do
            if curl -fsSL --retry 2 "$deb_url" -o "$DEB_DIR/libc6.deb" 2>/dev/null || \
               wget -qO "$DEB_DIR/libc6.deb" "$deb_url" 2>/dev/null; then
                rm -rf "$DEB_DIR/pkg" && mkdir -p "$DEB_DIR/pkg" 2>/dev/null || true
                if dpkg -x "$DEB_DIR/libc6.deb" "$DEB_DIR/pkg" 2>/dev/null; then
                    mkdir -p "$X64_LIB_DEST" 2>/dev/null || true
                    if [ -d "$DEB_DIR/pkg/usr/lib/x86_64-linux-gnu" ]; then
                        cp -a "$DEB_DIR/pkg/usr/lib/x86_64-linux-gnu/." "$X64_LIB_DEST/" 2>/dev/null || true
                    fi
                    if [ -d "$DEB_DIR/pkg/lib/x86_64-linux-gnu" ]; then
                        cp -a "$DEB_DIR/pkg/lib/x86_64-linux-gnu/." "$X64_LIB_DEST/" 2>/dev/null || true
                    fi
                    if [ -f "$X64_LIB_DEST/libc.so.6" ]; then
                        rm -rf "$DEB_DIR" 2>/dev/null || true
                        break
                    fi
                fi
            fi
        done
        rm -rf "$DEB_DIR" 2>/dev/null || true
    fi

    # 4. Ensure Box64 or QEMU user static is installed
    if ! command -v box64 >/dev/null 2>&1 && [ ! -x /usr/bin/qemu-x86_64-static ]; then
        apt-get install -y --no-install-recommends box64 2>/dev/null || \
        apt-get install -y --no-install-recommends qemu-user-static 2>/dev/null || true
    fi
    if [ -x /usr/bin/qemu-x86_64-static ]; then
        ln -sf /usr/bin/qemu-x86_64-static /usr/local/bin/qemu-x86_64-static 2>/dev/null || true
    fi

    # 5. Fix symlinks for ld-linux-x86-64.so.2
    mkdir -p /lib64 2>/dev/null || true
    if [ -f /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]; then
        ln -sf /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    elif [ -f /lib/x86_64-linux-gnu/ld-2.31.so ]; then
        ln -sf /lib/x86_64-linux-gnu/ld-2.31.so /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 2>/dev/null || true
        ln -sf /lib/x86_64-linux-gnu/ld-2.31.so /lib64/ld-linux-x86-64.so.2 2>/dev/null || true
    fi

    if [ -f /lib64/ld-linux-x86-64.so.2 ] || command -v box64 >/dev/null 2>&1; then
        [ -f /lib64/ld-linux-x86-64.so.2 ] && ln -sf /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 2>/dev/null || true
        touch /root/.quantum_flutter_release_fix_installed ~/.quantum_flutter_release_fix_installed 2>/dev/null || true
        echo "[quantum-heal-x64] ✓ x86_64 AOT runtime successfully ready."
    else
        echo "[quantum-heal-x64] Warning: /lib64/ld-linux-x86-64.so.2 still missing."
    fi
fi

# 6. Auto-heal AAPT2 to modern ARM64 binary (supports --source-path; checks 36.x once on --doctor)
NEED_AAPT2_UPGRADE=0
if ! (/usr/bin/aapt2 compile --help 2>&1 | grep -q -- '--source-path'); then
    NEED_AAPT2_UPGRADE=1
elif [ "$1" = "--doctor" ] && [ -d /root/android-sdk/platforms/android-36 ] && ! (/usr/bin/aapt2 version 2>&1 | grep -qE '36\.|2\.19-1[2-9]'); then
    NEED_AAPT2_UPGRADE=1
fi

if [ "$NEED_AAPT2_UPGRADE" = "1" ]; then
    TMP_ZIP="${TMPDIR:-/tmp}/sdk-tools-$$.zip"
    TMP_DIR="${TMPDIR:-/tmp}/sdk_tools_$$"
    mkdir -p "$TMP_DIR" 2>/dev/null || true
    AAPT2_DONE=0
    for tools_url in \
        "https://github.com/lzhiyong/android-sdk-tools/releases/download/36.0.0/android-sdk-tools-static-aarch64.zip" \
        "https://github.com/lzhiyong/android-sdk-tools/releases/download/35.0.2/android-sdk-tools-static-aarch64.zip" \
        "https://github.com/Lesorub361/quantum_ide/releases/download/v1.2.32/android-sdk-tools-static-aarch64.zip"; do
        if curl -k -fsSL --connect-timeout 8 --max-time 45 --retry 2 "$tools_url" -o "$TMP_ZIP" 2>/dev/null || \
           wget --no-check-certificate -qO "$TMP_ZIP" "$tools_url" 2>/dev/null; then
            unzip -qo "$TMP_ZIP" "build-tools/aapt2" -d "$TMP_DIR" 2>/dev/null || unzip -qo "$TMP_ZIP" -d "$TMP_DIR" 2>/dev/null
            if [ -f "$TMP_DIR/build-tools/aapt2" ] && "$TMP_DIR/build-tools/aapt2" compile --help 2>&1 | grep -q -- '--source-path'; then
                cp -f "$TMP_DIR/build-tools/aapt2" /usr/bin/aapt2
                chmod +x /usr/bin/aapt2
                echo "[quantum-heal-x64] ✓ Modern AAPT2 installed ($tools_url)."
                AAPT2_DONE=1
                break
            fi
        fi
    done
    rm -rf "$TMP_ZIP" "$TMP_DIR" 2>/dev/null || true
    if [ "$AAPT2_DONE" = "0" ] && [ -x /usr/local/bin/aapt2-arm64 ] && (/usr/local/bin/aapt2-arm64 compile --help 2>&1 | grep -q -- '--source-path'); then
        cp -f /usr/local/bin/aapt2-arm64 /usr/bin/aapt2
        chmod +x /usr/bin/aapt2
        echo "[quantum-heal-x64] ✓ Modern AAPT2 restored from /usr/local/bin/aapt2-arm64."
    fi
fi

# Ensure SDK build-tools has working aapt2 (without downgrading existing 36+ aapt2)
if /usr/bin/aapt2 compile --help 2>&1 | grep -q -- '--source-path'; then
    for bt in /root/android-sdk/build-tools/*; do
        if [ -d "$bt" ]; then
            if [ -x "$bt/aapt2" ] && ("$bt/aapt2" version 2>&1 | grep -qE '36\.|2\.19-1[2-9]'); then
                continue
            fi
            cp -f /usr/bin/aapt2 "$bt/aapt2" 2>/dev/null || true
            chmod +x "$bt/aapt2" 2>/dev/null || true
        fi
    done
fi

# Auto-repair corrupted /usr/local/bin/apksigner and /usr/local/bin/bundletool wrappers
if [ -f /usr/local/bin/apksigner ] && grep -q "export HOME=" /usr/local/bin/apksigner 2>/dev/null; then
    if [ -f /usr/lib/android-sdk/build-tools/debian/apksigner.jar ]; then
        printf '#!/bin/sh\nexec java -jar /usr/lib/android-sdk/build-tools/debian/apksigner.jar "$@"\n' > /usr/local/bin/apksigner
        chmod 755 /usr/local/bin/apksigner
        echo "[quantum-heal-x64] ✓ Repaired /usr/local/bin/apksigner."
    fi
fi
if [ -f /usr/local/bin/bundletool ] && grep -q "export HOME=" /usr/local/bin/bundletool 2>/dev/null; then
    if [ -f /usr/local/bin/bundletool.jar ]; then
        printf '#!/bin/sh\nexec java -jar /usr/local/bin/bundletool.jar "$@"\n' > /usr/local/bin/bundletool
        chmod 755 /usr/local/bin/bundletool
        echo "[quantum-heal-x64] ✓ Repaired /usr/local/bin/bundletool."
    fi
fi

# 7. Box64 anti-fasttop profile for Flutter gen_snapshot (compatible with Box64 v0.2.6+)
if [ -f /etc/box64.box64rc ] && grep -q 'BOX64_MMAP32' /etc/box64.box64rc 2>/dev/null; then
    sed -i '/BOX64_MMAP32/d' /etc/box64.box64rc 2>/dev/null || true
fi
if [ ! -f /etc/box64.box64rc ] || ! grep -q '\[gen_snapshot\.x64\]' /etc/box64.box64rc 2>/dev/null; then
    mkdir -p /etc 2>/dev/null || true
    cat << 'EOF' >> /etc/box64.box64rc 2>/dev/null || true

[gen_snapshot]
BOX64_DYNAREC_STRONGMEM=1
BOX64_DYNAREC_BIGBLOCK=0
BOX64_DYNAREC_SAFEFLAGS=2

[gen_snapshot.x64]
BOX64_DYNAREC_STRONGMEM=1
BOX64_DYNAREC_BIGBLOCK=0
BOX64_DYNAREC_SAFEFLAGS=2
EOF
fi

# 7b. Wrap x86_64 Flutter gen_snapshot so a Box64 heap crash auto-recovers via QEMU in-place (no 7-min Gradle restart)
for gs in /root/flutter/bin/cache/artifacts/engine/android-*-release/linux-x64/gen_snapshot; do
    [ -e "$gs" ] || continue
    # Skip if already wrapped by QuantumIDE
    if head -c 4 "$gs" 2>/dev/null | grep -q $'\x7fELF'; then
        mv -f "$gs" "${gs}.x64" 2>/dev/null || continue
        chmod 755 "${gs}.x64" 2>/dev/null || true
        cat << 'WRAPPER_EOF' > "$gs"
#!/bin/sh
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
X64_BIN="$SELF_DIR/gen_snapshot.x64"
ARM64_BIN="/usr/local/bin/gen_snapshot-arm64"
ENGINE_VER_FILE="/root/flutter/bin/internal/engine.version"
ARM64_VER_FILE="/usr/local/bin/gen_snapshot-arm64.version"

# 1. Native ARM64 gen_snapshot if installed for this exact Flutter engine.version
if [ -x "$ARM64_BIN" ] && [ -f "$ENGINE_VER_FILE" ] && [ -f "$ARM64_VER_FILE" ]; then
    if [ "$(cat "$ENGINE_VER_FILE" 2>/dev/null)" = "$(cat "$ARM64_VER_FILE" 2>/dev/null)" ]; then
        exec "$ARM64_BIN" "$@"
    fi
fi

# 2. Safe mode: run directly under qemu-x86_64-static (avoids Box64 v0.2.6 native glibc wrapping heap corruption)
if [ "$QUANTUM_BUILD_PROFILE" = "safe" ] && [ -x /usr/bin/qemu-x86_64-static ]; then
    exec /usr/bin/qemu-x86_64-static "$X64_BIN" "$@"
fi

# 3. Auto/Turbo: try Box64 first; if it crashes (fasttop / prev_size), immediately fallback to QEMU in-place
if command -v box64 >/dev/null 2>&1; then
    box64 "$X64_BIN" "$@"
    rc=$?
    if [ $rc -ne 0 ] && [ -x /usr/bin/qemu-x86_64-static ]; then
        echo "[QuantumIDE] ⚠ Box64 gen_snapshot exited ($rc), retrying via qemu-x86_64-static..." >&2
        exec /usr/bin/qemu-x86_64-static "$X64_BIN" "$@"
    fi
    exit $rc
elif [ -x /usr/bin/qemu-x86_64-static ]; then
    exec /usr/bin/qemu-x86_64-static "$X64_BIN" "$@"
else
    exec "$X64_BIN" "$@"
fi
WRAPPER_EOF
        chmod 755 "$gs" 2>/dev/null || true
        echo "[quantum-heal-x64] ✓ Wrapped gen_snapshot with automatic QEMU crash-recovery."
    fi
done

# 8. Build Doctor (--doctor): verify android.jar integrity, clean stale Gradle locks, fix local.properties
if [ "$1" = "--doctor" ]; then
    # Clean stale Gradle lock files that can wedge builds after a crash
    find /root/.gradle -name "*.lock" -mmin +5 -delete 2>/dev/null || true
    [ -d .gradle ] && find .gradle -name "*.lock" -mmin +5 -delete 2>/dev/null || true

    # Auto-repair local.properties sdk.dir if inside an Android/Flutter project
    if [ -d /root/android-sdk ]; then
        for lp in android/local.properties local.properties; do
            if [ -d "$(dirname "$lp")" ] && ( [ -f android/build.gradle ] || [ -f android/build.gradle.kts ] || [ -f build.gradle ] || [ -f build.gradle.kts ] ); then
                if [ ! -f "$lp" ] || ! grep -q "sdk.dir=/root/android-sdk" "$lp" 2>/dev/null; then
                    touch "$lp" 2>/dev/null || true
                    sed -i '/^sdk\.dir=/d' "$lp" 2>/dev/null || true
                    echo "sdk.dir=/root/android-sdk" >> "$lp" 2>/dev/null || true
                fi
            fi
        done
    fi

    # Verify every installed android.jar with unzip -tq; reinstall if corrupted
    if command -v unzip >/dev/null 2>&1; then
        SDKMGR=""
        for cand in /root/android-sdk/cmdline-tools/latest/bin/sdkmanager /root/android-sdk/cmdline-tools/*/bin/sdkmanager; do
            [ -x "$cand" ] && SDKMGR="$cand" && break
        done
        for jar in /root/android-sdk/platforms/android-*/android.jar; do
            [ -e "$jar" ] || continue
            plat_dir="$(dirname "$jar")"
            plat_name="$(basename "$plat_dir")"
            jar_size=$(wc -c < "$jar" 2>/dev/null || echo 0)
            if [ "$jar_size" -lt 1000000 ] || ! unzip -tq "$jar" >/dev/null 2>&1; then
                echo "[Build Doctor] ⚠ Обнаружен повреждённый $plat_name/android.jar — переустанавливаю..."
                rm -rf "$plat_dir" 2>/dev/null || true
                if [ -n "$SDKMGR" ]; then
                    yes | "$SDKMGR" --sdk_root=/root/android-sdk "platforms;$plat_name" >/dev/null 2>&1 || true
                    if [ -f "$jar" ] && unzip -tq "$jar" >/dev/null 2>&1; then
                        echo "[Build Doctor] ✓ $plat_name успешно восстановлен."
                    fi
                fi
            fi
        done
    fi
fi
''';

  }

  String _generateSetupArm64Script() {
    return r'''#!/bin/bash
# setup-arm64.sh - Automatically configure ARM64 environment inside QuantumIDE
# This script is called by init-host in the background.

# Prevent multiple instances of setup-arm64.sh running at once or re-running unnecessarily
DONE_FLAG="/tmp/setup_arm64_done.flag"
if [ -f "$DONE_FLAG" ] && [ "$1" != "--force" ]; then
    exit 0
fi
LOCKFILE="/tmp/setup_daemon.lock"
if [ -f "$LOCKFILE" ]; then
    read -r last_pid < "$LOCKFILE"
    if [ -n "$last_pid" ] && kill -0 "$last_pid" 2>/dev/null; then
        echo "setup-arm64.sh is already running (PID: $last_pid). Exiting."
        exit 0
    fi
fi
echo "$$" > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# Always run fast NDK & CMake wrapper heal on initial setup
if [ -x /usr/local/bin/quantum-patch-ndk ]; then
    /usr/local/bin/quantum-patch-ndk --fast 2>/dev/null || true
fi

# Always auto-heal AAPT2 to modern binary with --source-path support
if ! (/usr/bin/aapt2 compile --help 2>&1 | grep -q -- '--source-path'); then
    if [ -x /usr/local/bin/aapt2-arm64 ] && (/usr/local/bin/aapt2-arm64 compile --help 2>&1 | grep -q -- '--source-path'); then
        cp -f /usr/local/bin/aapt2-arm64 /usr/bin/aapt2
        chmod +x /usr/bin/aapt2
    elif [ -x /usr/local/bin/quantum-heal-x64 ]; then
        /usr/local/bin/quantum-heal-x64 2>/dev/null || true
    fi
fi

# Always auto-heal terminfo database if missing xterm-256color or broken
if [ ! -e /lib/terminfo/x/xterm-256color ] && [ ! -e /usr/share/terminfo/x/xterm-256color ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || true
    apt-get install --reinstall -y ncurses-base ncurses-term >/dev/null 2>&1 || true
fi
if [ ! -e /lib/terminfo/x/xterm-256color ] && [ -e /lib/terminfo/x/xterm ]; then
    cp -f /lib/terminfo/x/xterm /lib/terminfo/x/xterm-256color 2>/dev/null || true
fi
if [ ! -e /usr/share/terminfo/x/xterm-256color ] && [ -e /usr/share/terminfo/x/xterm ]; then
    cp -f /usr/share/terminfo/x/xterm /usr/share/terminfo/x/xterm-256color 2>/dev/null || true
fi
if [ -d /usr/share/terminfo ] && [ ! -e /lib/terminfo/x ]; then
    mkdir -p /lib/terminfo 2>/dev/null || true
    ln -sf /usr/share/terminfo/* /lib/terminfo/ 2>/dev/null || true
fi
if [ -d /lib/terminfo ] && [ ! -e /usr/share/terminfo/x ]; then
    mkdir -p /usr/share/terminfo 2>/dev/null || true
    ln -sf /lib/terminfo/* /usr/share/terminfo/ 2>/dev/null || true
fi

# Ensure all essential terminal utilities, ADB/Fastboot, and firmware flashing tools are installed
if ! command -v jq >/dev/null 2>&1 || ! command -v tree >/dev/null 2>&1 || ! command -v vim >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1 || ! command -v pip3 >/dev/null 2>&1 || ! command -v rg >/dev/null 2>&1 || ! command -v fdfind >/dev/null 2>&1 || ! command -v batcat >/dev/null 2>&1 || ! command -v ccache >/dev/null 2>&1 || ! command -v mold >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends \
        ncurses-base ncurses-term ncurses-bin \
        readline-common libreadline8 \
        bash-completion \
        less nano vim micro tmux htop tree jq ncdu \
        procps psmisc \
        file ca-certificates \
        locales ripgrep fzf iproute2 iputils-ping net-tools lsof \
        android-tools-adb android-tools-fastboot \
        usbutils aria2 p7zip-full zstd brotli libusb-1.0-0 \
        python3-pip fd-find bat rsync ccache mold >/dev/null 2>&1 || true
    locale-gen en_US.UTF-8 ru_RU.UTF-8 >/dev/null 2>&1 || true
    update-locale LANG=ru_RU.UTF-8 LC_ALL=ru_RU.UTF-8 >/dev/null 2>&1 || true
    ln -sf /usr/bin/fdfind /usr/bin/fd 2>/dev/null || true
    ln -sf /usr/bin/batcat /usr/bin/bat 2>/dev/null || true
    corepack enable 2>/dev/null || true
    if ! command -v lazygit >/dev/null 2>&1; then
        (curl -sSL --connect-timeout 10 --max-time 60 "https://github.com/jesseduffield/lazygit/releases/download/v0.66.2/lazygit_0.66.2_linux_arm64.tar.gz" | tar -xz -C /tmp && mv /tmp/lazygit /usr/local/bin/lazygit && chmod +x /usr/local/bin/lazygit) 2>/dev/null || true
    fi
fi

# Ensure ultra-fast modern package managers: uv (Python), bun (JS/TS ARM64), and pnpm
if ! command -v uv >/dev/null 2>&1; then
    (
        curl -LsSf --connect-timeout 10 --max-time 60 https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
    ) >/dev/null 2>&1 || pip3 install --break-system-packages -q uv >/dev/null 2>&1 || true
    [ -x /root/.local/bin/uv ] && [ ! -e /usr/local/bin/uv ] && ln -sf /root/.local/bin/uv /usr/local/bin/uv 2>/dev/null || true
    [ -x /root/.local/bin/uvx ] && [ ! -e /usr/local/bin/uvx ] && ln -sf /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true
fi

if ! command -v bun >/dev/null 2>&1; then
    (
        export BUN_INSTALL=/root/.bun
        curl -fsSL --connect-timeout 10 --max-time 60 https://bun.sh/install | bash
    ) >/dev/null 2>&1 || true
    if [ -x /root/.bun/bin/bun ]; then
        ln -sf /root/.bun/bin/bun /usr/local/bin/bun 2>/dev/null || true
        ln -sf /root/.bun/bin/bun /usr/local/bin/bunx 2>/dev/null || true
    fi
fi

if ! command -v pnpm >/dev/null 2>&1; then
    if command -v corepack >/dev/null 2>&1; then
        corepack enable >/dev/null 2>&1 || true
        corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
    elif command -v npm >/dev/null 2>&1; then
        npm install -g pnpm >/dev/null 2>&1 || true
    fi
fi

# Ensure Python 3 standard library (ntpath, pathlib) is installed so generators/builds never fail
if ! python3 -c 'import ntpath, pathlib' 2>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends python3 python3-minimal libpython3-stdlib >/dev/null 2>&1 || true
fi

# Ensure native ARM64 CMake 3.22.1+ and Clang-18 / LLD-18 / LLVM-18 are installed for C++/NDK builds
if ! command -v clang >/dev/null 2>&1 && ! ls /usr/bin/clang-[0-9]* >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || true
    apt-get install -y --no-install-recommends clang-18 lld-18 llvm-18 ninja-build >/dev/null 2>&1 || \
    apt-get install -y --no-install-recommends clang lld llvm ninja-build >/dev/null 2>&1 || true
fi

if [ ! -x /opt/cmake-3.22.1/bin/cmake ]; then
    mkdir -p /opt/cmake-3.22.1
    if (curl -k -fL --retry 2 -o /tmp/cmake-3.22.1.tar.gz "https://github.com/Kitware/CMake/releases/download/v3.22.1/cmake-3.22.1-linux-aarch64.tar.gz" 2>/dev/null || \
        wget --no-check-certificate -qO /tmp/cmake-3.22.1.tar.gz "https://github.com/Kitware/CMake/releases/download/v3.22.1/cmake-3.22.1-linux-aarch64.tar.gz" 2>/dev/null); then
        tar -xzf /tmp/cmake-3.22.1.tar.gz --strip-components=1 -C /opt/cmake-3.22.1 2>/dev/null || true
        rm -f /tmp/cmake-3.22.1.tar.gz
        if [ -x /opt/cmake-3.22.1/bin/cmake ]; then
            ln -sf /opt/cmake-3.22.1/bin/cmake /usr/local/bin/cmake
            ln -sf /opt/cmake-3.22.1/bin/cmake /usr/bin/cmake
        fi
    fi
fi

if [ -x /usr/local/bin/quantum-patch-ndk ]; then
    /usr/local/bin/quantum-patch-ndk 2>/dev/null || true
fi

# 1. SDK Toolchain Symlinking & Licenses
SDK_ROOT="/root/android-sdk"
if [ -d "$SDK_ROOT" ]; then
    mkdir -p "$SDK_ROOT/licenses"
    [ ! -f "$SDK_ROOT/licenses/android-sdk-license" ] && printf "24333f8a63b6825ea9c5514f83c2829b004d1fee\nd56f5187479451eabf01fb78af6dfcb131a6481e\n2fa2d150aa0a1204d10e5ed57ab8369e7b50077c\n" > "$SDK_ROOT/licenses/android-sdk-license"
    [ ! -f "$SDK_ROOT/licenses/android-sdk-preview-license" ] && printf "84831b9409646a918e30573bab4c9c91346d8abd\n" > "$SDK_ROOT/licenses/android-sdk-preview-license"
    [ ! -f "$SDK_ROOT/licenses/android-sdk-arm-dbt-license" ] && printf "859f317696f67ef3d7f30a50a5560e7834b43903\n" > "$SDK_ROOT/licenses/android-sdk-arm-dbt-license"
    [ ! -f "$SDK_ROOT/licenses/android-googletv-license" ] && printf "601085b94cd77f0b54ff86406957099ebe79c4d6\n" > "$SDK_ROOT/licenses/android-googletv-license"
    [ ! -f "$SDK_ROOT/licenses/android-googlexr-license" ] && printf "ceff83576aac4f7f37cb98fe189e9fb3c49d3b81\n" > "$SDK_ROOT/licenses/android-googlexr-license"
    [ ! -f "$SDK_ROOT/licenses/google-gdk-license" ] && printf "33b6a2b64607f11b759f320ef9dff4ae5c47d97a\n" > "$SDK_ROOT/licenses/google-gdk-license"
    [ ! -f "$SDK_ROOT/licenses/microxr-sysimage-license" ] && printf "3a7848b1d7366ca5cfa0be477627644ca73f47e3\n" > "$SDK_ROOT/licenses/microxr-sysimage-license"
    [ ! -f "$SDK_ROOT/licenses/mips-android-sysimage-license" ] && printf "e9acab5b5fbb560a72cfaecce8946896ff6aab9d\n" > "$SDK_ROOT/licenses/mips-android-sysimage-license"

    mkdir -p "$SDK_ROOT/platform-tools"
    [ ! -L "$SDK_ROOT/platform-tools/adb" ] && ln -sf /usr/bin/adb "$SDK_ROOT/platform-tools/adb"

    # Build tools: ensure 35.0.0 / 35.0.1 / 36.0.0 have d8, core-lambda-stubs.jar, lib/, source.properties from 34.0.0
    if [ -d "$SDK_ROOT/build-tools/34.0.0/lib" ]; then
        for ver in 35.0.0 35.0.1 36.0.0; do
            if [ -d "$SDK_ROOT/build-tools/$ver" ] && [ ! -f "$SDK_ROOT/build-tools/$ver/core-lambda-stubs.jar" ]; then
                cp -rn "$SDK_ROOT/build-tools/34.0.0/"* "$SDK_ROOT/build-tools/$ver/" 2>/dev/null || true
                printf "Pkg.UserSrc=false\nPkg.Revision=%s\n" "$ver" > "$SDK_ROOT/build-tools/$ver/source.properties"
                if [ -f "$SDK_ROOT/build-tools/34.0.0/package.xml" ]; then
                    major=$(echo "$ver" | cut -d. -f1)
                    minor=$(echo "$ver" | cut -d. -f2)
                    micro=$(echo "$ver" | cut -d. -f3)
                    sed -e "s/build-tools;34.0.0/build-tools;$ver/g" \
                        -e "s/<major>34<\/major>/<major>$major<\/major>/g" \
                        -e "s/<minor>0<\/minor>/<minor>$minor<\/minor>/g" \
                        -e "s/<micro>0<\/micro>/<micro>$micro<\/micro>/g" \
                        "$SDK_ROOT/build-tools/34.0.0/package.xml" > "$SDK_ROOT/build-tools/$ver/package.xml"
                fi
            fi
        done
    fi

    for bt in "$SDK_ROOT/build-tools/"*; do
        if [ -d "$bt" ] && [ "$bt" != "$SDK_ROOT/build-tools/debian" ]; then
            [ -f /usr/bin/aapt ] && [ ! -L /usr/bin/aapt ] && ln -sf /usr/bin/aapt "$bt/aapt"
            [ -f /usr/bin/aapt2 ] && [ ! -L /usr/bin/aapt2 ] && ln -sf /usr/bin/aapt2 "$bt/aapt2"
            [ -f /usr/bin/zipalign ] && [ ! -L /usr/bin/zipalign ] && ln -sf /usr/bin/zipalign "$bt/zipalign"
            [ -f /usr/bin/apksigner ] && [ ! -L /usr/bin/apksigner ] && [ ! -f "$bt/apksigner" ] && ln -sf /usr/bin/apksigner "$bt/apksigner"
            chmod +x "$bt/"* 2>/dev/null || true
        fi
    done

    # Ensure Android 35 & 36 platform stubs exist if Android 34 is installed
    if [ -f "$SDK_ROOT/platforms/android-34/android.jar" ]; then
        for api in 35 36; do
            if [ ! -f "$SDK_ROOT/platforms/android-$api/android.jar" ]; then
                mkdir -p "$SDK_ROOT/platforms/android-$api"
                cp -rn "$SDK_ROOT/platforms/android-34/"* "$SDK_ROOT/platforms/android-$api/" 2>/dev/null || true
                sed -i "s/AndroidVersion.ApiLevel=34/AndroidVersion.ApiLevel=$api/g; s/Platform.Version=14/Platform.Version=$((api - 20))/g" "$SDK_ROOT/platforms/android-$api/source.properties" 2>/dev/null || true
                sed -i "s/ro.build.version.sdk=34/ro.build.version.sdk=$api/g" "$SDK_ROOT/platforms/android-$api/build.prop" 2>/dev/null || true
                if [ -f "$SDK_ROOT/platforms/android-34/package.xml" ]; then
                    sed -e "s/platforms;android-34/platforms;android-$api/g" \
                        -e "s/<api-level>34<\/api-level>/<api-level>$api<\/api-level>/g" \
                        "$SDK_ROOT/platforms/android-34/package.xml" > "$SDK_ROOT/platforms/android-$api/package.xml"
                fi
            fi
        done
    fi

    # CMake & Ninja auto-provisioning
    if command -v cmake >/dev/null 2>&1; then
        for cmver in 3.22.1 3.31.0; do
            mkdir -p "$SDK_ROOT/cmake/$cmver/bin"
            ln -sf "$(command -v cmake)" "$SDK_ROOT/cmake/$cmver/bin/cmake"
            command -v ninja >/dev/null 2>&1 && ln -sf "$(command -v ninja)" "$SDK_ROOT/cmake/$cmver/bin/ninja"
            [ ! -f "$SDK_ROOT/cmake/$cmver/source.properties" ] && printf "Pkg.Desc = CMake %s\nPkg.Revision = %s\n" "$cmver" "$cmver" > "$SDK_ROOT/cmake/$cmver/source.properties"
        done
    fi

    # NDK Clang/LLVM fixes
    # If a native ARM64 NDK is installed, ensure AGP symlinks exist and preserve binaries.
    # If the official Google x86_64 NDK is installed, intercept calls via system clang.
    for ndk in "$SDK_ROOT/ndk/"*; do
        if [ -d "$ndk" ]; then
            if [ -d "$ndk/toolchains/llvm/prebuilt/linux-arm64" ]; then
                [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-x86_64" ] && ln -sfn linux-arm64 "$ndk/toolchains/llvm/prebuilt/linux-x86_64" 2>/dev/null || true
                [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-aarch64" ] && ln -sfn linux-arm64 "$ndk/toolchains/llvm/prebuilt/linux-aarch64" 2>/dev/null || true
                chmod +x "$ndk/ndk-build" "$ndk/toolchains/llvm/prebuilt/linux-arm64/bin/"* 2>/dev/null || true
                continue
            fi
            if [ -d "$ndk/toolchains/llvm/prebuilt/linux-aarch64" ]; then
                [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-x86_64" ] && ln -sfn linux-aarch64 "$ndk/toolchains/llvm/prebuilt/linux-x86_64" 2>/dev/null || true
                [ ! -e "$ndk/toolchains/llvm/prebuilt/linux-arm64" ] && ln -sfn linux-aarch64 "$ndk/toolchains/llvm/prebuilt/linux-arm64" 2>/dev/null || true
                chmod +x "$ndk/ndk-build" "$ndk/toolchains/llvm/prebuilt/linux-aarch64/bin/"* 2>/dev/null || true
                continue
            fi

            NDK_BIN="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
            SYSROOT="$ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
            mkdir -p "$NDK_BIN"

            # Find versioned system clang (prefer versioned for stability)
            CLANG_BIN=$(ls /usr/bin/clang-[0-9]* 2>/dev/null | sort -V | tail -1)
            CLANGPP_BIN=$(ls /usr/bin/clang++-[0-9]* 2>/dev/null | sort -V | tail -1)
            [ -z "$CLANG_BIN" ] && CLANG_BIN=/usr/bin/clang
            [ -z "$CLANGPP_BIN" ] && CLANGPP_BIN=/usr/bin/clang++

            # Replace clang (and clang-XX which is what the wrapper scripts call)
            for target in clang clang-19 clang-18 clang-17; do
                if [ ! -f "$NDK_BIN/$target" ] || \
                   [ "$(head -1 "$NDK_BIN/$target" 2>/dev/null)" != '#!/bin/bash' ]; then
                    rm -f "$NDK_BIN/$target"
                    printf '#!/bin/bash\nexec %s "$@"\n' "$CLANG_BIN" > "$NDK_BIN/$target"
                    chmod +x "$NDK_BIN/$target"
                fi
            done
            # clang++
            if [ ! -f "$NDK_BIN/clang++" ] || \
               [ "$(head -1 "$NDK_BIN/clang++" 2>/dev/null)" != '#!/bin/bash' ]; then
                rm -f "$NDK_BIN/clang++"
                printf '#!/bin/bash\nexec %s "$@"\n' "$CLANGPP_BIN" > "$NDK_BIN/clang++"
                chmod +x "$NDK_BIN/clang++"
            fi

            # llvm tools — same pattern: shell wrappers
            for tool in llvm-ar llvm-ranlib llvm-strip llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-readobj; do
                SYS_TOOL=$(ls /usr/bin/${tool}-[0-9]* 2>/dev/null | sort -V | tail -1)
                [ -z "$SYS_TOOL" ] && SYS_TOOL="/usr/bin/$tool"
                [ -x "$SYS_TOOL" ] || continue
                if [ ! -f "$NDK_BIN/$tool" ] || \
                   [ "$(head -1 "$NDK_BIN/$tool" 2>/dev/null)" != '#!/bin/bash' ]; then
                    rm -f "$NDK_BIN/$tool"
                    printf '#!/bin/bash\nexec %s "$@"\n' "$SYS_TOOL" > "$NDK_BIN/$tool"
                    chmod +x "$NDK_BIN/$tool"
                fi
            done

            # ld.lld wrapper
            LLD=$(ls /usr/bin/ld.lld-[0-9]* 2>/dev/null | sort -V | tail -1)
            [ -z "$LLD" ] && LLD=/usr/bin/ld.lld
            if [ -x "$LLD" ]; then
                if [ ! -f "$NDK_BIN/ld.lld" ] || \
                   [ "$(head -1 "$NDK_BIN/ld.lld" 2>/dev/null)" != '#!/bin/bash' ]; then
                    rm -f "$NDK_BIN/ld.lld" "$NDK_BIN/ld"
                    printf '#!/bin/bash\nexec %s "$@"\n' "$LLD" > "$NDK_BIN/ld.lld"
                    chmod +x "$NDK_BIN/ld.lld"
                    printf '#!/bin/bash\nexec %s "$@"\n' "$LLD" > "$NDK_BIN/ld"
                    chmod +x "$NDK_BIN/ld"
                fi
            fi

            # libatomic.a + libgcc.a EMPTY STUBS in NDK sysroot
            # NDK 28+ removed libatomic and libgcc; old toolchain cmake files still
            # pass -latomic and -lgcc linker flags, causing link failures.
            # An empty archive satisfies the linker without breaking anything.
            LLVM_AR=$(ls /usr/bin/llvm-ar-[0-9]* 2>/dev/null | sort -V | tail -1)
            [ -z "$LLVM_AR" ] && LLVM_AR=/usr/bin/llvm-ar
            if [ -x "$LLVM_AR" ] && [ -d "$SYSROOT" ]; then
                for abi_dir in \
                    "$SYSROOT/usr/lib/aarch64-linux-android" \
                    "$SYSROOT/usr/lib/arm-linux-androideabi" \
                    "$SYSROOT/usr/lib/x86_64-linux-android" \
                    "$SYSROOT/usr/lib/i686-linux-android"; do
                    [ -d "$abi_dir" ] || continue
                    # Root-level stubs
                    [ -f "$abi_dir/libatomic.a" ] || "$LLVM_AR" rcs "$abi_dir/libatomic.a" 2>/dev/null
                    [ -f "$abi_dir/libgcc.a" ] || "$LLVM_AR" rcs "$abi_dir/libgcc.a" 2>/dev/null
                    # Per-API-level stubs
                    for api_dir in "$abi_dir"/*/; do
                        [ -d "$api_dir" ] || continue
                        [ -f "${api_dir}libatomic.a" ] || "$LLVM_AR" rcs "${api_dir}libatomic.a" 2>/dev/null
                        [ -f "${api_dir}libgcc.a" ] || "$LLVM_AR" rcs "${api_dir}libgcc.a" 2>/dev/null
                    done
                done
            fi

            for lib_clang in "$ndk/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/"*; do
                if [ -d "$lib_clang/lib/linux" ]; then
                    mkdir -p "$lib_clang/lib/linux/aarch64"
                    [ ! -f "$lib_clang/lib/linux/aarch64/libgcc.a" ] && \
                        ln -sf ../libclang_rt.builtins-aarch64-android.a "$lib_clang/lib/linux/aarch64/libgcc.a" 2>/dev/null || true
                    mkdir -p "$lib_clang/lib/linux/arm"
                    [ ! -f "$lib_clang/lib/linux/arm/libgcc.a" ] && \
                        ln -sf ../libclang_rt.builtins-arm-android.a "$lib_clang/lib/linux/arm/libgcc.a" 2>/dev/null || true
                fi
            done

            # Fix missing source.properties (CXX1101 error)
            if [ ! -f "$ndk/source.properties" ]; then
                NDK_VER=$(basename "$ndk")
                echo "Pkg.Desc = Android NDK\nPkg.Revision = $NDK_VER" > "$ndk/source.properties"
            fi
        fi
    done
fi

# Flutter Version Pinning & Auto-Healing
# Uses 3.50.0 on Ubuntu 22.04+/24.04 rootfs (GLIBC >= 2.34), or pins 3.47.8 on
# older rootfs (GLIBC 2.31) where Dart 3.14 fails with GLIBC_2.34 not found.
TARGET_FLUTTER_TAG="3.47.8"
if grep -qa "GLIBC_2.34" /lib/aarch64-linux-gnu/libc.so.6 /usr/lib/aarch64-linux-gnu/libc.so.6 2>/dev/null; then
    TARGET_FLUTTER_TAG="3.50.0"
fi
if [ -d "/root/flutter/.git" ]; then
    rm -f /root/flutter/.git/*.lock 2>/dev/null || true
    git -C /root/flutter config --global --add safe.directory /root/flutter 2>/dev/null || true
    CURRENT_TAG=$(cd /root/flutter && git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || true)
    if [ "$CURRENT_TAG" != "$TARGET_FLUTTER_TAG" ]; then
        echo "[setup-arm64] Flutter version mismatch ($CURRENT_TAG != $TARGET_FLUTTER_TAG). Auto-healing..."
        (
            cd /root/flutter && \
            git fetch --depth 1 origin tag "$TARGET_FLUTTER_TAG" 2>/dev/null || git fetch --tags origin 2>/dev/null || true
            git checkout "$TARGET_FLUTTER_TAG" -f 2>/dev/null || true
            /root/flutter/bin/flutter precache --android 2>/dev/null || true
        ) &
    fi
fi

# Ensure QEMU user static & x86_64 glibc dynamic linker are available for Flutter release builds
if [ -x /usr/local/bin/quantum-heal-x64 ]; then
    /usr/local/bin/quantum-heal-x64 2>/dev/null || true
elif [ ! -x /usr/bin/qemu-x86_64-static ] && ! command -v box64 >/dev/null 2>&1; then
    (apt-get update -y && apt-get install -y qemu-user-static) 2>/dev/null || true
fi
if [ -x /usr/local/bin/quantum-patch-ndk ]; then
    /usr/local/bin/quantum-patch-ndk --fast 2>/dev/null || true
fi

# Auto-configure Vulkan drivers and host GPU passthrough
if [ -f "/system/lib64/libvulkan.so" ] && [ ! -f /usr/lib/aarch64-linux-gnu/libvulkan.so.1 ]; then
    mkdir -p /usr/lib/aarch64-linux-gnu 2>/dev/null || true
    ln -sf /system/lib64/libvulkan.so /usr/lib/aarch64-linux-gnu/libvulkan.so.1 2>/dev/null || true
    ln -sf /system/lib64/libvulkan.so /usr/lib/aarch64-linux-gnu/libvulkan.so 2>/dev/null || true
    ln -sf /system/lib64/libvulkan.so /usr/lib/libvulkan.so 2>/dev/null || true
fi

# 2. Project Patching (Auto-fix common build issues on ARM64)
sed -i '/extra-gen-snapshot-options/d' /root/.gradle/gradle.properties 2>/dev/null || true
sed -i '/extra-gen-snapshot-options/d' ~/.gradle/gradle.properties 2>/dev/null || true
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 4 -name "gradle.properties" 2>/dev/null | while read f; do
    sed -i '/extra-gen-snapshot-options/d' "$f" 2>/dev/null || true
    if ! grep -q "android.aapt2.daemon" "$f"; then
        echo "android.aapt2.daemon=false" >> "$f"
        echo "android.aapt2FromMaven=false" >> "$f"
        echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> "$f"
        echo "org.gradle.daemon=false" >> "$f"
        echo "org.gradle.parallel=false" >> "$f"
        echo "org.gradle.workers.max=1" >> "$f"
    fi
done

# Patch settings.gradle.kts and settings.gradle to upgrade AGP to 8.11.1 and Kotlin to 2.2.20
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 4 \( -name "settings.gradle.kts" -o -name "settings.gradle" \) 2>/dev/null | while read f; do
    # Replace com.android.application version with 8.11.1
    sed -i -E 's/id\("com.android.application"\)\s*version\s*"[^"]+"/id("com.android.application") version "8.11.1"/g' "$f"
    sed -i -E "s/id\('com.android.application'\)\s*version\s*'[^']+'/id('com.android.application') version '8.11.1'/g" "$f"
    sed -i -E 's/id\s+"com.android.application"\s+version\s+"[^"]+"/id "com.android.application" version "8.11.1"/g' "$f"
    sed -i -E "s/id\s+'com.android.application'\s+version\s+'[^']+'/id 'com.android.application' version '8.11.1'/g" "$f"

    # Replace org.jetbrains.kotlin.android version with 2.2.20
    sed -i -E 's/id\("org.jetbrains.kotlin.android"\)\s*version\s*"[^"]+"/id("org.jetbrains.kotlin.android") version "2.2.20"/g' "$f"
    sed -i -E "s/id\('org.jetbrains.kotlin.android'\)\s*version\s*'[^']+'/id('org.jetbrains.kotlin.android') version '2.2.20'/g" "$f"
    sed -i -E 's/id\s+"org.jetbrains.kotlin.android"\s+version\s+"[^"]+"/id "org.jetbrains.kotlin.android" version "2.2.20"/g' "$f"
    sed -i -E "s/id\s+'org.jetbrains.kotlin.android'\s+version\s+'[^']+'/id 'org.jetbrains.kotlin.android' version '2.2.20'/g" "$f"
done

# Ensure modern ARM64 aapt2 or universal compatibility wrapper for AGP 8.x
# 1. Preserve real binary if /usr/bin/aapt2 is not already a wrapper
if [ -f /usr/bin/aapt2 ] && [ ! -L /usr/bin/aapt2 ]; then
    if ! head -n 1 /usr/bin/aapt2 2>/dev/null | grep -q "^#!"; then
        cp -f /usr/bin/aapt2 /usr/bin/aapt2-real 2>/dev/null || true
    fi
fi

# 2. In background, download modern ARM64 native aapt2 (supports Android 35/36 & AGP 8.x --source-path)
if [ ! -s /usr/local/bin/aapt2-arm64 ]; then
    (
        curl -sSL -o /tmp/aapt2-arm64 "https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a" 2>/dev/null && \
        chmod +x /tmp/aapt2-arm64 && \
        mv -f /tmp/aapt2-arm64 /usr/local/bin/aapt2-arm64 2>/dev/null
    ) &
fi

# 3. Create or update smart wrapper at /usr/bin/aapt2
if [ ! -f /usr/bin/aapt2 ] || [ -L /usr/bin/aapt2 ] || ! grep -q "AAPT2_UNIVERSAL_WRAPPER" /usr/bin/aapt2 2>/dev/null; then
    rm -f /usr/bin/aapt2
    cat << 'AAPT2_EOF' > /usr/bin/aapt2
#!/bin/bash
# AAPT2_UNIVERSAL_WRAPPER - Quantum IDE AAPT2 Universal Compatibility Wrapper

REAL_EXEC=()
if [ -x /usr/local/bin/aapt2-arm64 ]; then
    REAL_EXEC=("/usr/local/bin/aapt2-arm64")
elif [ -f /usr/local/lib/aapt2-bin ] && [ -x /usr/bin/qemu-x86_64-static ]; then
    REAL_EXEC=("/usr/bin/qemu-x86_64-static" "/usr/local/lib/aapt2-bin")
elif [ -x /usr/bin/aapt2-real ]; then
    REAL_EXEC=("/usr/bin/aapt2-real")
elif [ -x /usr/bin/aapt2.orig ]; then
    REAL_EXEC=("/usr/bin/aapt2.orig")
fi

if [ ${#REAL_EXEC[@]} -eq 0 ]; then
    echo "ERROR: AAPT2 executable not found in container!" >&2
    exit 1
fi

SUPPORTS_SOURCE_PATH=0
if [ -x /usr/local/bin/aapt2-arm64 ] && [ "${REAL_EXEC[0]}" = "/usr/local/bin/aapt2-arm64" ]; then
    SUPPORTS_SOURCE_PATH=1
elif "${REAL_EXEC[@]}" compile -h 2>&1 | grep -q -- "--source-path"; then
    SUPPORTS_SOURCE_PATH=1
fi

if [ "$SUPPORTS_SOURCE_PATH" -eq 1 ]; then
    if [ "$1" = "version" ]; then
        exec "${REAL_EXEC[@]}" "$@" 2>&1
    fi
    exec "${REAL_EXEC[@]}" "$@"
fi

# Filter out --source-path and its argument for legacy AAPT2
ARGS=()
SKIP_NEXT=0
for arg in "$@"; do
    if [ "$SKIP_NEXT" -eq 1 ]; then
        SKIP_NEXT=0
        continue
    fi
    if [ "$arg" = "--source-path" ]; then
        SKIP_NEXT=1
        continue
    fi
    case "$arg" in
        --source-path=*)
            continue
            ;;
    esac
    ARGS+=("$arg")
done

if [ "$1" = "version" ]; then
    exec "${REAL_EXEC[@]}" "${ARGS[@]}" 2>&1
fi
exec "${REAL_EXEC[@]}" "${ARGS[@]}"
AAPT2_EOF
    chmod +x /usr/bin/aapt2
fi

# Ensure apksigner wrapper is present
if [ -f /usr/lib/android-sdk/build-tools/debian/apksigner.jar ]; then
    if [ ! -f /usr/bin/apksigner ] || [ -L /usr/bin/apksigner ] || ! grep -q "apksigner.jar" /usr/bin/apksigner 2>/dev/null; then
        rm -f /usr/bin/apksigner
        cat << 'APKSIGNER_EOF' > /usr/bin/apksigner
#!/bin/sh
exec /usr/lib/jvm/java-17-openjdk-arm64/bin/java -jar /usr/lib/android-sdk/build-tools/debian/apksigner.jar "$@"
APKSIGNER_EOF
        chmod +x /usr/bin/apksigner
    fi
fi

# 3. AAPT2 background overwrite (for those in .gradle cache)
if [ -f /usr/bin/aapt2 ]; then
  find /root/.gradle -name "aapt2" -exec cp -f /usr/bin/aapt2 {} \; 2>/dev/null || true
fi

# 4. Precache Flutter Engine components in the background
if command -v flutter >/dev/null 2>&1; then
  flutter precache --android >/dev/null 2>&1 &
fi

# 5. Environment Self-Healing (Auto-repair missing ca-certificates and java.security)
# Check and restore missing /etc/apt/sources.list (crucial for apt to operate)
if [ ! -f "/etc/apt/sources.list" ] || [ ! -s "/etc/apt/sources.list" ]; then
  echo "Restoring missing /etc/apt/sources.list..."
  mkdir -p "/etc/apt"
  echo "deb http://ports.ubuntu.com/ubuntu-ports noble main restricted universe multiverse" > "/etc/apt/sources.list"
  echo "deb http://ports.ubuntu.com/ubuntu-ports noble-updates main restricted universe multiverse" >> "/etc/apt/sources.list"
  echo "deb http://ports.ubuntu.com/ubuntu-ports noble-security main restricted universe multiverse" >> "/etc/apt/sources.list"
  rm -rf /var/lib/apt/lists/*
fi

# Check if ca-certificates bundle or configuration is missing
if [ ! -f "/etc/ssl/certs/ca-certificates.crt" ] || [ ! -s "/etc/ssl/certs/ca-certificates.crt" ] || [ ! -f "/etc/ca-certificates.conf" ]; then
  echo "Healing SSL ca-certificates..."
  mkdir -p "/etc/ssl/certs"
  if [ -f "/etc/ca-certificates.conf" ]; then
    update-ca-certificates -f >/dev/null 2>&1 || true
  fi
  if [ ! -f "/etc/ssl/certs/ca-certificates.crt" ] || [ ! -s "/etc/ssl/certs/ca-certificates.crt" ] || [ ! -f "/etc/ca-certificates.conf" ]; then
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y --reinstall ca-certificates >/dev/null 2>&1 || true
    update-ca-certificates -f >/dev/null 2>&1 || true
  fi
  if [ ! -s "/etc/ssl/certs/ca-certificates.crt" ]; then
    find /usr/share/ca-certificates /usr/local/share/ca-certificates -type f -name '*.crt' -exec cat {} + > /etc/ssl/certs/ca-certificates.crt 2>/dev/null || true
  fi
fi

# Check if java-17 security is missing or broken symlink
if [ -d "/usr/lib/jvm/java-17-openjdk-arm64" ]; then
  CONF_17="/usr/lib/jvm/java-17-openjdk-arm64/conf/security/java.security"
  if [ ! -f "$CONF_17" ] || [ ! -s "$CONF_17" ] || ! readlink -f "$CONF_17" >/dev/null 2>&1; then
    echo "Healing Java 17 security config..."
    mkdir -p "/etc/java-17-openjdk/security"
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y --reinstall -o Dpkg::Options::="--force-confmiss" openjdk-17-jre-headless ca-certificates-java >/dev/null 2>&1 || true
  fi
fi

# Check if java-21 security is missing or broken symlink
if [ -d "/usr/lib/jvm/java-21-openjdk-arm64" ]; then
  CONF_21="/usr/lib/jvm/java-21-openjdk-arm64/conf/security/java.security"
  if [ ! -f "$CONF_21" ] || [ ! -s "$CONF_21" ] || ! readlink -f "$CONF_21" >/dev/null 2>&1; then
    echo "Healing Java 21 security config..."
    mkdir -p "/etc/java-21-openjdk/security"
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y --reinstall -o Dpkg::Options::="--force-confmiss" openjdk-21-jre-headless ca-certificates-java >/dev/null 2>&1 || true
  fi
fi

# 6. Global Gradle settings configuration
mkdir -p /root/.gradle
cat << 'EOF' > /root/.gradle/gradle.properties
android.aapt2.daemon=false
android.aapt2FromMaven=false
android.aapt2FromMavenOverride=/usr/bin/aapt2
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.workers.max=1
EOF
if [ -d "/usr/lib/jvm/java-17-openjdk-arm64" ]; then
    echo "org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-arm64" >> /root/.gradle/gradle.properties
elif [ -d "/usr/lib/jvm/java-21-openjdk-arm64" ]; then
    echo "org.gradle.java.home=/usr/lib/jvm/java-21-openjdk-arm64" >> /root/.gradle/gradle.properties
fi

# 7. Run one-time auto-heal for AAPT2 / SDK toolchain binaries & patch projects
SDK_ROOT="/root/android-sdk"
# Symlink SDK build-tools to native tools on the fly only if aapt2 supports modern flags
if [ -d "$SDK_ROOT/build-tools" ]; then
    for bt in "$SDK_ROOT/build-tools/"*; do
        if [ -d "$bt" ] && [ "$bt" != "$SDK_ROOT/build-tools/debian" ]; then
            if [ -f /usr/bin/aapt2 ] && [ ! -L /usr/bin/aapt2 ] && (/usr/bin/aapt2 compile --help 2>&1 | grep -q -- '--source-path'); then
                ln -sf /usr/bin/aapt2 "$bt/aapt2"
            fi
            [ -f /usr/bin/aapt ] && [ ! -L /usr/bin/aapt ] && ln -sf /usr/bin/aapt "$bt/aapt"
            [ -f /usr/bin/zipalign ] && [ ! -L /usr/bin/zipalign ] && ln -sf /usr/bin/zipalign "$bt/zipalign"
            [ -f /usr/bin/apksigner ] && [ ! -L /usr/bin/apksigner ] && ln -sf /usr/bin/apksigner "$bt/apksigner"
        fi
    done
fi

# Symlink newly downloaded Gradle cached AAPT2 binaries
if [ -d "/root/.gradle" ] && [ -f "/usr/bin/aapt2" ] && (/usr/bin/aapt2 compile --help 2>&1 | grep -q -- '--source-path'); then
    find /root/.gradle -name "aapt2" 2>/dev/null | while read -r gp; do
        if [ -f "$gp" ] && [ ! -L "$gp" ]; then
            cp -f /usr/bin/aapt2 "$gp" 2>/dev/null
        fi
    done
fi

# Patch newly created projects' gradle.properties
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 4 -name "gradle.properties" 2>/dev/null | while read -r f; do
    if ! grep -q "android.aapt2.daemon" "$f"; then
        echo "android.aapt2.daemon=false" >> "$f"
        echo "android.aapt2FromMaven=false" >> "$f"
        echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> "$f"
        echo "org.gradle.daemon=false" >> "$f"
        echo "org.gradle.parallel=false" >> "$f"
        echo "org.gradle.workers.max=1" >> "$f"
    fi
    if ! grep -q "org.gradle.java.home" "$f"; then
        if [ -d "/usr/lib/jvm/java-17-openjdk-arm64" ]; then
            echo "org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-arm64" >> "$f"
        elif [ -d "/usr/lib/jvm/java-21-openjdk-arm64" ]; then
            echo "org.gradle.java.home=/usr/lib/jvm/java-21-openjdk-arm64" >> "$f"
        fi
    fi
done

# Project build files retain user/default ABI configuration (allowing --split-per-abi & AppBundle)

# Setup completed successfully
touch "$DONE_FLAG"
rm -f "$LOCKFILE"
echo "=== QuantumIDE ARM64 Environment Configuration Finished ==="
''';
  }

  Future<void> startForegroundSession({String title = 'Quantum IDE', String content = 'Терминал и сессия активны в фоне'}) async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('startForegroundSession', {
          'title': title,
          'content': content,
        });
      } catch (e) {
        debugPrint('startForegroundSession error: $e');
      }
    }
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable error: $e');
    }
  }

  Future<void> stopForegroundSession() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('stopForegroundSession');
      } catch (e) {
        debugPrint('stopForegroundSession error: $e');
      }
    }
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable error: $e');
    }
  }

  /// Scans common cache and temporary directories inside the Linux environment
  /// and returns categories with their sizes in kilobytes.
  Future<List<CleanupCategory>> scanSystemJunk({String? activeProjectGuestPath}) async {
    final categories = <CleanupCategory>[
      const CleanupCategory(
        id: 'gradle_caches',
        title: 'Кэш сборок Gradle',
        subtitle: '~/.gradle/caches, ~/.gradle/.tmp (перекачается при сборке)',
        paths: ['/root/.gradle/caches', '/root/.gradle/.tmp', '/root/.gradle/daemon'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'gradle_wrapper',
        title: 'Дистрибутивы Gradle Wrapper',
        subtitle: '~/.gradle/wrapper (старые версии Gradle)',
        paths: ['/root/.gradle/wrapper'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'dart_server',
        title: 'Кэш анализатора Dart',
        subtitle: '~/.dartServer (пересоздаётся автоматически)',
        paths: ['/root/.dartServer'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'npm_cache',
        title: 'Кэш npm / Node.js',
        subtitle: '~/.npm',
        paths: ['/root/.npm'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'apt_cache',
        title: 'Архивы пакетов APT',
        subtitle: '/var/cache/apt/archives (*.deb)',
        paths: ['/var/cache/apt/archives'],
        isAptClean: true,
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'tmp_junk',
        title: 'Временные файлы и остатки сборок',
        subtitle: '/tmp/*, ~/rootfs-build, ~/.cache',
        paths: ['/root/rootfs-build', '/root/.cache'],
        isTmpClean: true,
        defaultSelected: true,
      ),
      if (activeProjectGuestPath != null && activeProjectGuestPath.isNotEmpty)
        CleanupCategory(
          id: 'project_build',
          title: 'Артефакты сборки проекта (build/)',
          subtitle: '$activeProjectGuestPath/build',
          paths: ['$activeProjectGuestPath/build'],
          defaultSelected: true,
        ),
      const CleanupCategory(
        id: 'pub_cache',
        title: 'Кэш пакетов Dart / Flutter (.pub-cache)',
        subtitle: '~/.pub-cache (потребуется flutter pub get)',
        paths: ['/root/.pub-cache'],
        defaultSelected: false,
      ),
    ];

    final scriptLines = <String>[];
    for (final cat in categories) {
      if (cat.isTmpClean) {
        scriptLines.add(
          'KB_${cat.id}=\$(du -sk /tmp /root/rootfs-build /root/.cache 2>/dev/null | awk \'{s+=\$1} END {print s+0}\'); '
          'echo "${cat.id}=\$KB_${cat.id}"',
        );
      } else {
        final quoted = cat.paths.map((p) => '"$p"').join(' ');
        scriptLines.add(
          'KB_${cat.id}=\$(du -sk $quoted 2>/dev/null | awk \'{s+=\$1} END {print s+0}\'); '
          'echo "${cat.id}=\$KB_${cat.id}"',
        );
      }
    }

    final out = await runCommand(scriptLines.join('; '));
    final sizes = <String, int>{};
    for (final line in out.split('\n')) {
      final parts = line.trim().split('=');
      if (parts.length == 2) {
        sizes[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }

    return categories
        .map((c) => c.copyWith(sizeKb: sizes[c.id] ?? 0))
        .toList();
  }

  /// Deletes the selected [CleanupCategory] items and returns total freed KB.
  Future<int> cleanSystemJunk(List<CleanupCategory> selected) async {
    int freedKb = 0;
    final cmds = <String>[];

    for (final cat in selected) {
      if (cat.sizeKb <= 0) continue;
      freedKb += cat.sizeKb;
      if (cat.isAptClean) {
        cmds.add('apt-get clean 2>/dev/null || rm -rf /var/cache/apt/archives/*.deb');
      } else if (cat.isTmpClean) {
        cmds.add(
          'rm -rf /root/rootfs-build /root/.cache '
          '/tmp/box64 /tmp/llama.cpp /tmp/yandex_* /tmp/.bun-* '
          '/tmp/flutter_tools.* /tmp/kotlin-daemon.* /tmp/kotlin-compiler-* '
          '/tmp/dsh-spill-* /tmp/preserved_home /tmp/pubspec*.bak '
          '/tmp/dart_analyze_output*.txt /tmp/analyze.txt /tmp/q_frame_*.png '
          '/tmp/tmp.* /tmp/aapt2 /tmp/gradle_shadow /tmp/opencode /tmp/kilo '
          '/tmp/node-compile-cache /tmp/v8-compile-cache-0 2>/dev/null || true',
        );
      } else {
        final quoted = cat.paths.map((p) => '"$p"').join(' ');
        cmds.add('rm -rf $quoted 2>/dev/null || true');
      }
    }

    if (cmds.isNotEmpty) {
      await runCommand(cmds.join(' && '));
    }
    return freedKb;
  }
}

/// Represents a cleanable cache/temp category in the Linux environment.
class CleanupCategory {
  final String id;
  final String title;
  final String subtitle;
  final List<String> paths;
  final int sizeKb;
  final bool defaultSelected;
  final bool isAptClean;
  final bool isTmpClean;

  const CleanupCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.paths,
    this.sizeKb = 0,
    this.defaultSelected = true,
    this.isAptClean = false,
    this.isTmpClean = false,
  });

  CleanupCategory copyWith({int? sizeKb}) {
    return CleanupCategory(
      id: id,
      title: title,
      subtitle: subtitle,
      paths: paths,
      sizeKb: sizeKb ?? this.sizeKb,
      defaultSelected: defaultSelected,
      isAptClean: isAptClean,
      isTmpClean: isTmpClean,
    );
  }
}

final runtimeServiceProvider = ChangeNotifierProvider(
  (ref) => RuntimeService(),
);

/// Handle returned by [RuntimeService.runCommandStream].
class StreamingCommand {
  StreamingCommand._();

  Process? _process;
  late final Future<int> _exitCode;
  bool _cancelled = false;

  /// Completes with the process exit code (130 if cancelled).
  Future<int> get exitCode => _exitCode.then((c) => _cancelled ? 130 : c);

  bool get isCancelled => _cancelled;

  /// Alias for cancel()
  Future<void> kill() => cancel();

  /// Stops the command, including child processes (apt, npm, curl…).
  Future<void> cancel() async {
    _cancelled = true;
    final proc = _process;
    if (proc == null) return;
    final tree = Platform.isWindows ? <int>[] : await _descendants(proc.pid);
    for (final pid in tree.reversed) {
      Process.killPid(pid, ProcessSignal.sigterm);
    }
    proc.kill(ProcessSignal.sigterm);
    await Future.delayed(const Duration(milliseconds: 600));
    for (final pid in tree.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    proc.kill(ProcessSignal.sigkill);
  }

  static Future<List<int>> _descendants(int pid) async {
    final result = <int>[];
    try {
      final r = await Process.run('pgrep', ['-P', '$pid']);
      for (final s in r.stdout.toString().split(RegExp(r'\s+'))) {
        final child = int.tryParse(s);
        if (child != null) {
          result.add(child);
          result.addAll(await _descendants(child));
        }
      }
    } catch (_) {}
    return result;
  }
}
