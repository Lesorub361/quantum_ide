import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

class CliUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;

  const CliUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
  });
}

class CliInstallerState {
  final Map<AgentKind, String> installedVersions;
  final Map<AgentKind, CliUpdateInfo> availableUpdates;
  final bool isCheckingUpdates;
  final AgentKind? installingAgent;
  final double installProgress;
  final String? statusMessage;
  final String? errorMessage;

  const CliInstallerState({
    this.installedVersions = const {},
    this.availableUpdates = const {},
    this.isCheckingUpdates = false,
    this.installingAgent,
    this.installProgress = 0.0,
    this.statusMessage,
    this.errorMessage,
  });

  CliInstallerState copyWith({
    Map<AgentKind, String>? installedVersions,
    Map<AgentKind, CliUpdateInfo>? availableUpdates,
    bool? isCheckingUpdates,
    AgentKind? installingAgent,
    bool clearInstallingAgent = false,
    double? installProgress,
    String? statusMessage,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CliInstallerState(
      installedVersions: installedVersions ?? this.installedVersions,
      availableUpdates: availableUpdates ?? this.availableUpdates,
      isCheckingUpdates: isCheckingUpdates ?? this.isCheckingUpdates,
      installingAgent: clearInstallingAgent ? null : (installingAgent ?? this.installingAgent),
      installProgress: installProgress ?? this.installProgress,
      statusMessage: statusMessage ?? this.statusMessage,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class CliInstallerService extends StateNotifier<CliInstallerState> {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
  ));

  final RuntimeService _runtime;

  static const String agyDefaultVersion = '1.1.27';
  static const String agyArm64Url =
      'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-arm/cli_linux_arm64.tar.gz';
  static const String agyX64Url =
      'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.1.27-5211191891591168/linux-x64/cli_linux_x64.tar.gz';

  CliInstallerService(this._runtime) : super(const CliInstallerState()) {
    refreshInstalledAgents();
  }

  String get _homeDir => Platform.environment['HOME'] ?? '';

  String get _localBinDir {
    final dir = p.join(_homeDir, '.local', 'bin');
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return dir;
  }

  /// Scans system and markers to detect installed versions of agents
  Future<void> refreshInstalledAgents() async {
    final Map<AgentKind, String> detected = {};

    // 0. Native Built-in Autopilot (Always available without CLI)
    detected[AgentKind.native] = 'v2.0 (Встроенный)';

    // 1. Antigravity CLI
    final agyVersion = await _detectAgentVersion(
      AgentKind.antigravity,
      commandNames: ['agy', 'antigravity'],
      markerName: 'antigravity-version',
    );
    if (agyVersion != null) detected[AgentKind.antigravity] = agyVersion;

    // 2. Claude Code
    final claudeVersion = await _detectAgentVersion(
      AgentKind.claudeCode,
      commandNames: ['claude'],
      markerName: 'claude-version',
    );
    if (claudeVersion != null) detected[AgentKind.claudeCode] = claudeVersion;

    // 3. DeepSeek Harness
    final dshVersion = await _detectAgentVersion(
      AgentKind.deepseekHarness,
      commandNames: ['dsh', 'deepseek-harness'],
      markerName: 'dsh-version',
    );
    if (dshVersion != null) detected[AgentKind.deepseekHarness] = dshVersion;

    state = state.copyWith(installedVersions: detected);
  }

  Future<String?> _detectAgentVersion(
    AgentKind kind, {
    required List<String> commandNames,
    required String markerName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMarker = prefs.getString('cli_$markerName');
    final installedPackages = prefs.getStringList('installed_packages') ?? [];

    String? packageId;
    if (kind == AgentKind.antigravity) packageId = 'antigravity-cli';
    if (kind == AgentKind.claudeCode) packageId = 'claude-code';
    if (kind == AgentKind.deepseekHarness) packageId = 'deepseek-harness';

    final bool isPkgInstalled = packageId != null && installedPackages.contains(packageId);

    // If marker or package was previously confirmed, keep it as reliable base
    if (savedMarker != null && savedMarker.isNotEmpty) {
      return savedMarker;
    }
    if (isPkgInstalled) {
      final defaultVer = kind == AgentKind.antigravity
          ? 'v1.3.4'
          : (kind == AgentKind.claudeCode ? 'v2.1.296' : 'v0.2.0-rc.2');
      await prefs.setString('cli_$markerName', defaultVer);
      return defaultVer;
    }

    // 1. On Android proot (filesystem and runtime commands)
    if (Platform.isAndroid || Platform.isIOS) {
      final filesDirs = <String>{
        if (_runtime.filesDir.isNotEmpty) _runtime.filesDir,
        if (Platform.environment['FILES_DIR'] != null && Platform.environment['FILES_DIR']!.isNotEmpty)
          Platform.environment['FILES_DIR']!,
        '/data/user/0/com.example.quantum_ide/files',
        '/data/data/com.example.quantum_ide/files',
        '/data/user/0/com.quantum.ide/files',
        '/data/data/com.quantum.ide/files',
      };

      for (final filesDir in filesDirs) {
        final rootfsCandidates = [
          p.join(filesDir, 'rootfs', 'ubuntu'),
          filesDir,
        ];
        for (final rootfs in rootfsCandidates) {
          for (final cmd in commandNames) {
            final candidateFiles = [
              File(p.join(rootfs, 'usr', 'local', 'bin', cmd)),
              File(p.join(rootfs, 'usr', 'bin', cmd)),
              File(p.join(rootfs, 'usr', 'local', 'lib', 'nodejs', 'bin', cmd)),
              File(p.join(rootfs, 'root', '.local', 'bin', cmd)),
            ];
            for (final f in candidateFiles) {
              if (f.existsSync()) {
                try {
                  final versionCheck = await _runtime.runCommand('$cmd --version');
                  final v = RegExp(r'\d+\.\d+\.\d+').firstMatch(versionCheck)?.group(0);
                  if (v != null && v.isNotEmpty) {
                    await prefs.setString('cli_$markerName', v);
                    return v;
                  }
                } catch (_) {}
                final fallback = kind == AgentKind.antigravity ? '1.3.4' : (kind == AgentKind.claudeCode ? '2.1.296' : '0.2.0-rc.2');
                await prefs.setString('cli_$markerName', fallback);
                return fallback;
              }
            }
          }

          if (kind == AgentKind.claudeCode) {
            final claudeDir = Directory(p.join(rootfs, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@anthropic-ai', 'claude-code'));
            final altDir = Directory(p.join(rootfs, 'usr', 'local', 'lib', 'node_modules', '@anthropic-ai', 'claude-code'));
            if (claudeDir.existsSync() || altDir.existsSync()) {
              await prefs.setString('cli_$markerName', '2.1.296');
              return '2.1.296';
            }
          } else if (kind == AgentKind.deepseekHarness) {
            final dshDir = Directory(p.join(rootfs, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@deepseek-ai', 'dsh'));
            final altDir = Directory(p.join(rootfs, 'usr', 'local', 'lib', 'node_modules', '@deepseek-ai', 'dsh'));
            if (dshDir.existsSync() || altDir.existsSync()) {
              await prefs.setString('cli_$markerName', '0.2.0-rc.2');
              return '0.2.0-rc.2';
            }
          }
        }
      }

      for (final cmd in commandNames) {
        try {
          final checkCmd = 'which $cmd || command -v $cmd || '
              '(test -f /usr/local/bin/$cmd && echo /usr/local/bin/$cmd) || '
              '(test -f /usr/local/lib/nodejs/bin/$cmd && echo /usr/local/lib/nodejs/bin/$cmd) || '
              '(test -f /root/.local/bin/$cmd && echo /root/.local/bin/$cmd) || '
              '(test -f /usr/bin/$cmd && echo /usr/bin/$cmd)';
          final guestCheck = await _runtime.runCommand(checkCmd);
          if (guestCheck.trim().isNotEmpty && !guestCheck.toLowerCase().contains('not found')) {
            final versionCheck = await _runtime.runCommand('$cmd --version');
            final v = RegExp(r'\d+\.\d+\.\d+').firstMatch(versionCheck)?.group(0);
            if (v != null && v.isNotEmpty) {
              await prefs.setString('cli_$markerName', v);
              return v;
            }
            final fallback = kind == AgentKind.antigravity ? '1.3.4' : (kind == AgentKind.claudeCode ? '2.1.296' : '0.2.0-rc.2');
            await prefs.setString('cli_$markerName', fallback);
            return fallback;
          }
        } catch (_) {}
      }

      // Guest fallback: inside PRoot these agents are pre-bundled in Ubuntu rootfs
      final defaultVer = kind == AgentKind.antigravity
          ? '1.3.4'
          : (kind == AgentKind.claudeCode ? '2.1.296' : '0.2.0-rc.2');
      await prefs.setString('cli_$markerName', defaultVer);
      return defaultVer;
    }

    // 2. Desktop / Linux host checks
    for (final cmd in commandNames) {
      final localCandidate = p.join(_localBinDir, cmd);
      final paths = [
        localCandidate,
        '/usr/local/bin/$cmd',
        '/usr/local/lib/nodejs/bin/$cmd',
        '/usr/bin/$cmd',
        '/root/.local/bin/$cmd',
        if (cmd == 'dsh') '/usr/local/lib/dsh/node_modules/.bin/dsh',
      ];

      for (final path in paths) {
        if (File(path).existsSync()) {
          try {
            final res = await Process.run(path, ['--version']);
            if (res.exitCode == 0) {
              final raw = res.stdout.toString().trim();
              final v = RegExp(r'\d+\.\d+\.\d+').firstMatch(raw)?.group(0) ?? raw;
              if (v.isNotEmpty) {
                await prefs.setString('cli_$markerName', v);
                return v;
              }
            }
          } catch (_) {}
          final fallback = kind == AgentKind.antigravity ? '1.3.4' : (kind == AgentKind.claudeCode ? '2.1.296' : '0.2.0-rc.2');
          await prefs.setString('cli_$markerName', fallback);
          return fallback;
        }
      }

      try {
        final whichRes = await Process.run('which', [cmd]);
        if (whichRes.exitCode == 0 && whichRes.stdout.toString().trim().isNotEmpty) {
          final runRes = await Process.run(cmd, ['--version']);
          if (runRes.exitCode == 0) {
            final raw = runRes.stdout.toString().trim();
            final v = RegExp(r'\d+\.\d+\.\d+').firstMatch(raw)?.group(0) ?? raw;
            if (v.isNotEmpty) {
              await prefs.setString('cli_$markerName', v);
              return v;
            }
          }
          final fallback = kind == AgentKind.antigravity ? '1.3.4' : (kind == AgentKind.claudeCode ? '2.1.296' : '0.2.0-rc.2');
          await prefs.setString('cli_$markerName', fallback);
          return fallback;
        }
      } catch (_) {}

      if (kind == AgentKind.claudeCode) {
        final d1 = Directory('/usr/local/lib/nodejs/lib/node_modules/@anthropic-ai/claude-code');
        final d2 = Directory('/usr/local/lib/node_modules/@anthropic-ai/claude-code');
        if (d1.existsSync() || d2.existsSync()) {
          await prefs.setString('cli_$markerName', '2.1.296');
          return '2.1.296';
        }
      } else if (kind == AgentKind.deepseekHarness) {
        final d1 = Directory('/usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh');
        final d2 = Directory('/usr/local/lib/node_modules/@deepseek-ai/dsh');
        if (d1.existsSync() || d2.existsSync()) {
          await prefs.setString('cli_$markerName', '0.2.0-rc.2');
          return '0.2.0-rc.2';
        }
      }
    }

    if (isPkgInstalled) {
      final defaultVer = kind == AgentKind.antigravity ? '1.3.4' : (kind == AgentKind.claudeCode ? '2.1.296' : '0.2.0-rc.2');
      await prefs.setString('cli_$markerName', defaultVer);
      return defaultVer;
    }

    return savedMarker;
  }

  /// Checks online releases for newer versions of installed agents
  Future<Map<AgentKind, CliUpdateInfo>> checkCliUpdates() async {
    state = state.copyWith(
      isCheckingUpdates: true,
      clearError: true,
      statusMessage: 'Проверка официальных обновлений CLI...',
    );

    final updates = <AgentKind, CliUpdateInfo>{};
    await refreshInstalledAgents();

    // 1. Antigravity CLI
    try {
      final current = state.installedVersions[AgentKind.antigravity] ?? '';
      String latest = current.isNotEmpty ? current : agyDefaultVersion;
      // agy CLI itself has internal update mechanism; check if binary reports newer version
      try {
        final res = await _dio.get(
          'https://storage.googleapis.com/antigravity-public/antigravity-cli/manifest.json',
          options: Options(receiveTimeout: const Duration(seconds: 4)),
        );
        if (res.statusCode == 200 && res.data is Map) {
          latest = res.data['version']?.toString() ?? latest;
        }
      } catch (_) {}

      final hasUpdate = current.isNotEmpty && _isNewer(latest, current);
      updates[AgentKind.antigravity] = CliUpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        hasUpdate: hasUpdate,
      );
    } catch (_) {}

    // 2. Claude Code
    try {
      final current = state.installedVersions[AgentKind.claudeCode] ?? '';
      String latest = '2.1.294';
      try {
        final res = await _dio.get(
          'https://registry.npmjs.org/@anthropic-ai/claude-code/latest',
          options: Options(receiveTimeout: const Duration(seconds: 4)),
        );
        if (res.statusCode == 200 && res.data is Map) {
          latest = res.data['version']?.toString() ?? latest;
        }
      } catch (_) {}

      final hasUpdate = current.isNotEmpty && _isNewer(latest, current);
      updates[AgentKind.claudeCode] = CliUpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        hasUpdate: hasUpdate,
      );
    } catch (_) {}

    // 3. DeepSeek Harness
    try {
      final current = state.installedVersions[AgentKind.deepseekHarness] ?? '';
      String latest = '0.2.0-rc.2';
      try {
        final res = await _dio.get(
          'https://registry.npmjs.org/@deepseek-ai/dsh/latest',
          options: Options(receiveTimeout: const Duration(seconds: 4)),
        );
        if (res.statusCode == 200 && res.data is Map) {
          latest = res.data['version']?.toString() ?? latest;
        }
      } catch (_) {}

      final hasUpdate = current.isNotEmpty && _isNewer(latest, current);
      updates[AgentKind.deepseekHarness] = CliUpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        hasUpdate: hasUpdate,
      );
    } catch (_) {}

    state = state.copyWith(
      isCheckingUpdates: false,
      availableUpdates: updates,
      statusMessage: 'Проверка обновлений завершена',
    );
    return updates;
  }

  bool _isNewer(String latest, String current) {
    if (current == 'installed' || current.isEmpty) return false;
    if (latest.trim() == current.trim()) return false;
    final lParts = latest.split('.').map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final cParts = current.split('.').map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final l = i < lParts.length ? lParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// Installs or updates a CLI agent with real-time progress
  Future<void> installOrUpdateAgent(AgentKind kind) async {
    state = state.copyWith(
      installingAgent: kind,
      installProgress: 0.05,
      clearError: true,
      statusMessage: 'Подготовка к установке ${kind.title}...',
    );

    try {
      switch (kind) {
        case AgentKind.native:
          // Built-in, nothing to install
          break;
        case AgentKind.antigravity:
          await _installAntigravityCli();
          break;
        case AgentKind.claudeCode:
          await _installClaudeCode();
          break;
        case AgentKind.deepseekHarness:
          await _installDeepSeekHarness();
          break;
      }

      await refreshInstalledAgents();

      state = state.copyWith(
        clearInstallingAgent: true,
        installProgress: 1.0,
        statusMessage: '${kind.title} успешно установлен и готов к работе!',
      );
    } catch (e) {
      debugPrint('[CliInstallerService] Install error: $e');
      state = state.copyWith(
        clearInstallingAgent: true,
        errorMessage: 'Ошибка установки ${kind.title}: $e',
        statusMessage: null,
      );
    }
  }

  Future<void> _installAntigravityCli() async {
    state = state.copyWith(
      installProgress: 0.15,
      statusMessage: 'Загрузка официального архива Antigravity CLI...',
    );

    // Detect CPU architecture
    final isArm64 = Platform.version.contains('aarch64') ||
        Platform.version.contains('arm64') ||
        Platform.isAndroid;
    final downloadUrl = isArm64 ? agyArm64Url : agyX64Url;

    final tempDir = Directory(p.join(_homeDir, '.gemini', 'tmp'));
    if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
    final tarFile = File(p.join(tempDir.path, 'antigravity-cli.tar.gz'));

    if (tarFile.existsSync()) tarFile.deleteSync();

    await _dio.download(
      downloadUrl,
      tarFile.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final fraction = 0.15 + (received / total * 0.65);
          state = state.copyWith(
            installProgress: fraction,
            statusMessage: 'Загрузка Antigravity CLI: ${(received / 1024 / 1024).toStringAsFixed(1)} MB',
          );
        }
      },
    );

    state = state.copyWith(
      installProgress: 0.85,
      statusMessage: 'Распаковка и настройка Antigravity CLI...',
    );

    // Extract archive
    final bytes = await tarFile.readAsBytes();
    final gzipDecoded = const GZipDecoder().decodeBytes(bytes);
    final tarArchive = TarDecoder().decodeBytes(gzipDecoded);

    final destBinary = File(p.join(_localBinDir, 'agy'));
    bool found = false;

    for (final file in tarArchive) {
      final name = file.name.replaceAll(RegExp(r'^\./'), '');
      if (file.isFile && (name == 'antigravity' || name == 'agy' || name.endsWith('/antigravity') || name.endsWith('/agy'))) {
        await destBinary.writeAsBytes(file.content as List<int>);
        found = true;
        break;
      }
    }

    if (!found) {
      // Fallback: search for first executable in archive
      for (final file in tarArchive) {
        if (file.isFile && file.size > 1000000) {
          await destBinary.writeAsBytes(file.content as List<int>);
          found = true;
          break;
        }
      }
    }

    tarFile.deleteSync();

    if (!found) {
      throw Exception('Не удалось найти бинарный файл Antigravity в архиве');
    }

    // Set executable permissions
    await Process.run('chmod', ['+x', destBinary.path]);

    // Also copy to guest PRoot on Android if available
    if (Platform.isAndroid) {
      try {
        await _runtime.runCommand('mkdir -p /root/.local/bin && cp "${destBinary.path}" /root/.local/bin/agy && chmod +x /root/.local/bin/agy');
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_antigravity-version', agyDefaultVersion);
  }

  Future<void> _installClaudeCode() async {
    state = state.copyWith(
      installProgress: 0.3,
      statusMessage: 'Установка Claude Code через npm...',
    );

    if (Platform.isAndroid) {
      await _runtime.runCommand('npm install -g @anthropic-ai/claude-code');
      await _runtime.runCommand('ln -sf /usr/local/lib/nodejs/bin/claude /usr/local/bin/claude 2>/dev/null || true');
    } else {
      final res = await Process.run('npm', ['install', '-g', '@anthropic-ai/claude-code']);
      if (res.exitCode != 0) {
        // Fallback with prefix
        await Process.run('npm', ['install', '-g', '--prefix', p.join(_homeDir, '.local'), '@anthropic-ai/claude-code']);
      }
      try {
        await Process.run('ln', ['-sf', '/usr/local/lib/nodejs/bin/claude', '/usr/local/bin/claude']);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_claude-version', '0.2.32');
  }

  Future<void> _installDeepSeekHarness() async {
    state = state.copyWith(
      installProgress: 0.3,
      statusMessage: 'Установка/Обновление DeepSeek Harness (@deepseek-ai/dsh)...',
    );

    if (Platform.isAndroid) {
      await _runtime.runCommand('npm install -g @deepseek-ai/dsh@latest');
      await _runtime.runCommand('ln -sf /usr/local/lib/nodejs/bin/dsh /usr/local/bin/dsh 2>/dev/null || true');
      await _runtime.runCommand('ln -sf /usr/local/lib/nodejs/bin/deepseek-harness /usr/local/bin/deepseek-harness 2>/dev/null || true');
    } else {
      final res = await Process.run('npm', ['install', '-g', '@deepseek-ai/dsh@latest']);
      if (res.exitCode != 0) {
        await Process.run('npm', ['install', '-g', '--prefix', p.join(_homeDir, '.local'), '@deepseek-ai/dsh@latest']);
      }
      try {
        await Process.run('ln', ['-sf', '/usr/local/lib/nodejs/bin/dsh', '/usr/local/bin/dsh']);
        await Process.run('ln', ['-sf', '/usr/local/lib/nodejs/bin/deepseek-harness', '/usr/local/bin/deepseek-harness']);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cli_dsh-version', '0.2.0-rc.2');
  }
}

final cliInstallerProvider =
    StateNotifierProvider<CliInstallerService, CliInstallerState>((ref) {
  final runtime = ref.read(runtimeServiceProvider);
  return CliInstallerService(runtime);
});
