import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/optional_package.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/cli_installer_service.dart';

class PackageService extends StateNotifier<List<OptionalPackage>> {
  final Ref _ref;
  static const _key = 'installed_packages';
  Timer? _syncTimer;
  bool _isChecking = false;

  PackageService(this._ref) : super(defaultPackages) {
    _init();
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    // Poll every 120s instead of 30s to save CPU and battery
    _syncTimer = Timer.periodic(const Duration(seconds: 120), (_) {
      _checkActualInstallation();
    });
  }

  Future<void> checkActualInstallation() => _checkActualInstallation();

  Future<void> _init() async {
    await _loadState();
    await _checkActualInstallation();
  }

  List<String> _getBinarySearchDirs() {
    final home = Platform.environment['HOME'] ?? '/root';
    final pathEnv = Platform.environment['PATH'] ?? '';
    final dirs = <String>{
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/local/lib/nodejs/bin',
      '/opt/gradle/gradle-8.13/bin',
      p.join(home, '.local', 'bin'),
      p.join(home, '.cargo', 'bin'),
      p.join(home, '.bun', 'bin'),
      p.join(home, '.pub-cache', 'bin'),
      p.join(home, 'flutter', 'bin'),
      '/root/.local/bin',
      '/root/.cargo/bin',
      '/root/.bun/bin',
      '/root/.pub-cache/bin',
      '/root/flutter/bin',
      for (final part in pathEnv.split(':'))
        if (part.trim().isNotEmpty) part.trim(),
    };
    return dirs.toList();
  }

  Future<bool> _hasCommandAsync(String cmd, List<String> searchDirs) async {
    for (final dir in searchDirs) {
      try {
        if (await File(p.join(dir, cmd)).exists()) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<String> _getAndroidSdkPathAsync() async {
    if (await Directory('/root/android-sdk').exists()) {
      return '/root/android-sdk';
    }
    if (await Directory('/usr/lib/android-sdk').exists()) {
      return '/usr/lib/android-sdk';
    }
    final home = Platform.environment['HOME'] ?? '/root';
    final userSdk = p.join(home, 'Android', 'Sdk');
    if (await Directory(userSdk).exists()) {
      return userSdk;
    }
    final runtime = _ref.read(runtimeServiceProvider);
    if (Platform.isAndroid) {
      final prootCandidates = [
        if (runtime.filesDir.isNotEmpty) p.join(runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'android-sdk'),
        '/data/user/0/com.example.quantum_ide/files/rootfs/ubuntu/root/android-sdk',
        '/data/data/com.example.quantum_ide/files/rootfs/ubuntu/root/android-sdk',
      ];
      for (final candidate in prootCandidates) {
        if (await Directory(candidate).exists()) return candidate;
      }
    }
    return Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'] ??
        p.join(home, 'android-sdk');
  }

  String _translateCommandForPC(String cmd) {
    final isRoot = (Platform.environment['USER'] == 'root') || (Platform.environment['HOME'] == '/root');
    if (isRoot) {
      return cmd;
    }

    String translated = cmd;
    const lockMarker = 'ca-certificates 2>/dev/null || true ; ';
    if (translated.contains(lockMarker)) {
      final index = translated.indexOf(lockMarker);
      translated = translated.substring(index + lockMarker.length);
    } else if (translated.contains('kill -9 \$(pgrep')) {
      final parts = translated.split(' ; ');
      translated = parts
          .where((p) =>
              !p.contains('pgrep') &&
              !p.contains('/var/lib/') &&
              !p.contains('/var/cache/') &&
              !p.contains('dpkg --configure') &&
              !p.contains('export HOME=/root') &&
              !p.contains('export USER=root'))
          .join(' ; ');
    }

    translated = translated.replaceAll(
      'apt update',
      '(sudo apt-get update -o Acquire::Retries=1 2>/dev/null || sudo apt update 2>/dev/null || true)',
    );
    translated = translated.replaceAll('apt install', 'sudo apt install');

    translated = translated.replaceAll('/root/android-sdk', '~/Android/Sdk');
    translated = translated.replaceAll('/root/flutter', '~/flutter');
    translated = translated.replaceAll('/root/.bashrc', '~/.bashrc');
    translated = translated.replaceAll('/root/.profile', '~/.profile');
    translated = translated.replaceAll('/root/projects', '~/projects');
    translated = translated.replaceAll('/root/', '~/');

    final arch = Platform.version.toLowerCase();
    if (!arch.contains('arm') && !arch.contains('aarch64')) {
      translated = translated.replaceAll('arm64', 'x64');
    }

    translated = translated.replaceAll('npm install -g', 'sudo npm install -g');
    translated = translated.replaceAll('npm i -g', 'sudo npm i -g');

    translated = translated.replaceAll('| bash', '| sudo bash');
    translated = translated.replaceAll('cp bin/llama-server /usr/bin', 'sudo cp bin/llama-server /usr/bin');
    translated = translated.replaceAll('cp bin/llama-cli /usr/bin', 'sudo cp bin/llama-cli /usr/bin');
    translated = translated.replaceAll('cp {} /usr/bin/', 'sudo cp {} /usr/bin/');
    translated = translated.replaceAll('cp {} /usr/lib/', 'sudo cp {} /usr/lib/');
    translated = translated.replaceAll('cp -a {} /usr/lib/', 'sudo cp -a {} /usr/lib/');
    translated = translated.replaceAll('cp -a {} /usr/local/lib/', 'sudo cp -a {} /usr/local/lib/');
    translated = translated.replaceAll('mv /usr/share/', 'sudo mv /usr/share/');
    translated = translated.replaceAll('mv /tmp/aapt2_download/aapt2 /usr/bin/', 'sudo mv /tmp/aapt2_download/aapt2 /usr/bin/');
    translated = translated.replaceAll('chmod +x /usr/bin/', 'sudo chmod +x /usr/bin/');
    translated = translated.replaceAll('ln -sf /root/', 'sudo ln -sf ~/');
    translated = translated.replaceAll('ln -sf ', 'sudo ln -sf ');
    translated = translated.replaceAll('chown -R root:root', 'chown -R \$(id -u):\$(id -g)');

    return translated;
  }

  Future<void> markPackageInstalled(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (prefs.getStringList(_key) ?? []).toSet();
    current.add(id);
    await prefs.setStringList(_key, current.toList());
    state = [for (final p in state) if (p.id == id) p..isInstalled = true else p];

    try {
      if (id == 'antigravity-cli') await prefs.setString('cli_antigravity-version', '1.3.4');
      if (id == 'claude-code') await prefs.setString('cli_claude-version', '2.1.296');
      if (id == 'deepseek-harness') await prefs.setString('cli_dsh-version', '0.2.0-rc.2');
      _ref.read(cliInstallerProvider.notifier).refreshInstalledAgents();
    } catch (_) {}

    await _checkActualInstallation();
  }

  Future<void> _checkActualInstallation() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      final runtime = _ref.read(runtimeServiceProvider);
      final isAndroid = Platform.isAndroid;
      String rootfsPath = '';
      if (isAndroid) {
        final candidatePaths = [
          if (runtime.filesDir.isNotEmpty) p.join(runtime.filesDir, 'rootfs', 'ubuntu'),
          if (runtime.filesDir.isNotEmpty) runtime.filesDir,
          '/data/user/0/com.example.quantum_ide/files/rootfs/ubuntu',
          '/data/data/com.example.quantum_ide/files/rootfs/ubuntu',
          '/data/user/0/com.quantum.ide/files/rootfs/ubuntu',
          '/data/data/com.quantum.ide/files/rootfs/ubuntu',
        ];
        for (final cp in candidatePaths) {
          if (await Directory(cp).exists()) {
            rootfsPath = cp;
            break;
          }
        }
        if (rootfsPath.isEmpty && runtime.filesDir.isNotEmpty) {
          rootfsPath = p.join(runtime.filesDir, 'rootfs', 'ubuntu');
        }
        if (rootfsPath.isEmpty) return;
      }

      final prefs = await SharedPreferences.getInstance();
      final installedIds = prefs.getStringList(_key) ?? [];

      final updatedPackages = <OptionalPackage>[];
      final sdkPath = await _getAndroidSdkPathAsync();
      final searchDirs = _getBinarySearchDirs();
      final newlyInstalledIds = <String>{};

      Future<bool> hasCmd(String cmd) => _hasCommandAsync(cmd, searchDirs);
      Future<bool> hasRootfsEntity(String relPath) async {
        if (rootfsPath.isEmpty) return false;
        final fullPath = p.join(rootfsPath, relPath);
        final type = await FileSystemEntity.type(fullPath, followLinks: false);
        return type != FileSystemEntityType.notFound;
      }
      Future<bool> hasRootfsBin(String bin) async {
        return await hasRootfsEntity(p.join('usr', 'bin', bin)) ||
            await hasRootfsEntity(p.join('usr', 'local', 'bin', bin)) ||
            await hasRootfsEntity(p.join('bin', bin)) ||
            await hasRootfsEntity(p.join('usr', 'local', 'lib', 'nodejs', 'bin', bin)) ||
            await hasRootfsEntity(p.join('root', '.local', 'bin', bin)) ||
            await hasRootfsEntity(p.join('root', 'flutter', 'bin', bin)) ||
            await hasRootfsEntity(p.join('usr', 'lib', 'jvm', 'java-17-openjdk-arm64', 'bin', bin)) ||
            await hasRootfsEntity(p.join('usr', 'lib', 'jvm', 'java-21-openjdk-arm64', 'bin', bin));
      }

      for (final pkg in state) {
        bool exists = false;

        if (pkg.id.startsWith('platform-android-')) {
          final version = pkg.id.replaceFirst('platform-android-', '');
          exists = await Directory(p.join(sdkPath, 'platforms', 'android-$version')).exists() ||
              (isAndroid && await hasRootfsEntity(p.join('root', 'android-sdk', 'platforms', 'android-$version')));
        } else if (pkg.id.startsWith('build-tools-')) {
          final version = pkg.id.replaceFirst('build-tools-', '');
          exists = await Directory(p.join(sdkPath, 'build-tools', version)).exists() ||
              (isAndroid && await hasRootfsEntity(p.join('root', 'android-sdk', 'build-tools', version)));
        } else if (pkg.id.startsWith('cmake-')) {
          final version = pkg.id.replaceFirst('cmake-', '');
          final dirName = version == '3.6'
              ? '3.6.4111459'
              : (version == '3.10'
                  ? '3.10.2.4988404'
                  : (version == '3.18'
                      ? '3.18.1'
                      : (version == '3.22'
                          ? '3.22.1'
                          : (version == '3.31' ? '3.31.0' : version))));
          exists = await Directory(p.join(sdkPath, 'cmake', dirName)).exists() ||
              (isAndroid && await hasRootfsEntity(p.join('root', 'android-sdk', 'cmake', dirName))) ||
              (isAndroid ? await hasRootfsBin('cmake') : await hasCmd('cmake'));
        } else if (pkg.id.startsWith('ndk-')) {
          final version = pkg.id.replaceFirst('ndk-', '');
          final dirName = version == 'r21e'
              ? '21.4.7075529'
              : (version == 'r22b'
                  ? '22.1.7171670'
                  : (version == 'r23b'
                      ? '23.1.7779620'
                      : (version == 'r24'
                          ? '24.0.8215888'
                          : (version == 'r25c'
                              ? '25.1.8937393'
                              : (version == 'r26b'
                                  ? '26.1.10909125'
                                  : (version == 'r27b'
                                      ? '27.0.12077973'
                                      : (version == 'r28'
                                          ? '28.0.12433547'
                                          : (version == 'r29' ? '29.0.14206865' : version))))))));
          exists = await Directory(p.join(sdkPath, 'ndk', dirName)).exists() ||
              await Directory(p.join(sdkPath, 'ndk', version)).exists() ||
              await Directory(p.join(sdkPath, 'ndk', 'android-ndk-$version')).exists() ||
              (isAndroid &&
                  (await hasRootfsEntity(p.join('root', 'android-sdk', 'ndk', dirName)) ||
                      await hasRootfsEntity(p.join('root', 'android-sdk', 'ndk', version)) ||
                      await hasRootfsEntity(p.join('root', 'android-sdk', 'ndk', 'android-ndk-$version'))));
        } else if (!isAndroid) {
          switch (pkg.id) {
            case 'android-sdk-tools-arm64':
              exists = await hasCmd('aapt2') && await hasCmd('zipalign');
              break;
            case 'mold-linker':
              exists = await hasCmd('mold');
              break;
            case 'rust-arm64':
              exists = await hasCmd('rustc') || await hasCmd('cargo');
              break;
            case 'python':
              exists = await hasCmd('python3') || await hasCmd('python');
              break;
            case 'nodejs':
              exists = await hasCmd('node');
              break;
            case 'git':
              exists = await hasCmd('git');
              break;
            case 'git-lfs':
              exists = await hasCmd('git-lfs');
              break;
            case 'flutter':
              exists = await hasCmd('flutter');
              break;
            case 'antigravity-cli':
              exists = await hasCmd('agy') || await hasCmd('antigravity');
              break;
            case 'claude-code':
              exists = await hasCmd('claude') ||
                  await Directory('/usr/local/lib/nodejs/lib/node_modules/@anthropic-ai/claude-code').exists() ||
                  await Directory('/usr/local/lib/node_modules/@anthropic-ai/claude-code').exists();
              break;
            case 'deepseek-harness':
              exists = await hasCmd('dsh') ||
                  await hasCmd('deepseek-harness') ||
                  await Directory('/usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh').exists() ||
                  await Directory('/usr/local/lib/node_modules/@deepseek-ai/dsh').exists();
              break;
            case 'ollama-cli':
              exists = await hasCmd('ollama');
              break;
            case 'kilocode-cli':
              exists = await hasCmd('kilocode');
              break;
            case 'opencode-ai':
              exists = await hasCmd('opencode-ai') || await hasCmd('opencode');
              break;
            case 'build-essential':
              exists = await hasCmd('gcc') || await hasCmd('g++');
              break;
            case 'android-sdk':
              exists = await Directory(sdkPath).exists() || await hasCmd('sdkmanager');
              break;
            case 'openjdk-21':
              exists = await Directory('/usr/lib/jvm/java-21-openjdk-arm64').exists() ||
                  await Directory('/usr/lib/jvm/java-21-openjdk-amd64').exists();
              break;
            case 'gradle-8.13':
              exists = await Directory('/opt/gradle/gradle-8.13').exists() || await hasCmd('gradle');
              break;
            case 'apk-signing-tools':
              exists = await hasCmd('apksigner') && await hasCmd('zipalign');
              break;
            case 'protobuf-compiler':
              exists = await hasCmd('protoc');
              break;
            case 'sqlite-dev':
              exists = await hasCmd('sqlite3') &&
                  (await File('/usr/include/sqlite3.h').exists() || installedIds.contains('sqlite-dev'));
              break;
            case 'build-fix':
              final homeDir = Platform.environment['HOME'] ?? '/root';
              final marker = File(p.join(homeDir, '.quantum_build_fix_installed'));
              final rootMarker = File('/root/.quantum_build_fix_installed');
              final hasAapt = await hasCmd('aapt') || await hasCmd('aapt2');
              exists = await marker.exists() || await rootMarker.exists() || hasAapt || installedIds.contains('build-fix');
              break;
            case 'box64-emulator':
              exists = await hasCmd('box64') ||
                  await File('/usr/local/bin/box64').exists() ||
                  await File('/usr/bin/box64').exists() ||
                  installedIds.contains('box64-emulator');
              break;
            case 'vulkan-graphics':
              exists = await hasCmd('vulkaninfo') ||
                  await File('/usr/bin/vulkaninfo').exists() ||
                  installedIds.contains('vulkan-graphics');
              break;
            case 'build-clean':
              exists = installedIds.contains('build-clean');
              break;
            case 'clangd-lsp':
              exists = await hasCmd('clangd');
              break;
            case 'rust-lsp':
              exists = await hasCmd('rust-analyzer') || await hasCmd('rustc');
              break;
            case 'go-lsp':
              exists = await hasCmd('gopls') || await hasCmd('go');
              break;
            case 'ripgrep':
              exists = await hasCmd('rg');
              break;
            case 'gh-cli':
              exists = await hasCmd('gh');
              break;
            case 'java-lsp':
              exists = await hasCmd('jdtls') || await Directory('/usr/share/jdtls').exists();
              break;
            case 'kotlin-lsp':
              exists = await hasCmd('kotlin-language-server') || await Directory('/usr/share/kotlin-language-server').exists();
              break;
            case 'typescript-lsp':
              exists = await hasCmd('typescript-language-server');
              break;
            case 'html-css-lsp':
              exists = await hasCmd('html-languageserver') ||
                  await hasCmd('vscode-html-language-server') ||
                  await hasCmd('vscode-html-languageserver');
              break;
            case 'yaml-json-lsp':
              exists = await hasCmd('yaml-language-server');
              break;
            case 'markdown-lsp':
              exists = await hasCmd('marksman');
              break;
            case 'vue-lsp':
              exists = await hasCmd('vue-language-server');
              break;
            case 'php-lsp':
              exists = await hasCmd('intelephense');
              break;
            case 'python-lsp':
              exists = await hasCmd('pyright') || await hasCmd('pyright-langserver');
              break;
            case 'local-ai-qwen':
              exists = await hasCmd('llama-server') || await hasCmd('llama-cli');
              break;
            case 'uv':
              exists = await hasCmd('uv');
              break;
            case 'bun':
              exists = await hasCmd('bun');
              break;
            case 'pnpm':
              exists = await hasCmd('pnpm');
              break;
            case 'desktop-build-tools':
              exists = await hasCmd('clang') && await hasCmd('cmake') && await hasCmd('ninja');
              break;
            case 'flutter-distributor':
              exists = await hasCmd('flutter_distributor');
              break;
          }
        } else {
          // Android rootfs checks (100% async)
          switch (pkg.id) {
            case 'python':
              exists = await hasRootfsBin('python3') || await hasRootfsBin('python');
              break;
            case 'nodejs':
              exists = await hasRootfsBin('node');
              break;
            case 'git':
              exists = await hasRootfsBin('git');
              break;
            case 'git-lfs':
              exists = await hasRootfsBin('git-lfs');
              break;
            case 'flutter':
              exists = await File(p.join(rootfsPath, 'root', 'flutter', 'bin', 'flutter')).exists() ||
                  await hasRootfsBin('flutter');
              break;
            case 'antigravity-cli':
              exists = await hasRootfsBin('agy') || await hasRootfsBin('antigravity');
              break;
            case 'claude-code':
              exists = await hasRootfsBin('claude') ||
                  await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@anthropic-ai', 'claude-code')).exists() ||
                  await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'node_modules', '@anthropic-ai', 'claude-code')).exists();
              break;
            case 'deepseek-harness':
              exists = await hasRootfsBin('dsh') ||
                  await hasRootfsBin('deepseek-harness') ||
                  await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@deepseek-ai', 'dsh')).exists() ||
                  await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'node_modules', '@deepseek-ai', 'dsh')).exists();
              break;
            case 'ollama-cli':
              exists = await hasRootfsBin('ollama');
              break;
            case 'kilocode-cli':
              exists = await hasRootfsBin('kilocode');
              break;
            case 'opencode-ai':
              exists = await hasRootfsBin('opencode-ai') || await hasRootfsBin('opencode');
              break;
            case 'build-essential':
              exists = await hasRootfsBin('gcc') || await hasRootfsBin('g++');
              break;
            case 'android-sdk':
              final hasJava = await hasRootfsBin('java') ||
                  await hasRootfsEntity(p.join('usr', 'lib', 'jvm', 'java-17-openjdk-arm64')) ||
                  await hasRootfsEntity(p.join('usr', 'lib', 'jvm', 'java-21-openjdk-arm64')) ||
                  await hasRootfsEntity(p.join('root', 'jdk-17'));
              final hasSdkManager = await File(p.join(sdkPath, 'cmdline-tools', 'latest', 'bin', 'sdkmanager')).exists() ||
                  await hasRootfsEntity(p.join('root', 'android-sdk', 'cmdline-tools', 'latest', 'bin', 'sdkmanager')) ||
                  await hasRootfsBin('sdkmanager');
              exists = hasJava && hasSdkManager;
              break;
            case 'openjdk-21':
              exists = await Directory(p.join(rootfsPath, 'usr', 'lib', 'jvm', 'java-21-openjdk-arm64')).exists() ||
                  await Directory(p.join(rootfsPath, 'usr', 'lib', 'jvm', 'java-21-openjdk-amd64')).exists();
              break;
            case 'gradle-8.13':
              exists = await Directory(p.join(rootfsPath, 'opt', 'gradle', 'gradle-8.13')).exists() ||
                  await hasRootfsBin('gradle');
              break;
            case 'apk-signing-tools':
              exists = await hasRootfsBin('apksigner') && await hasRootfsBin('zipalign');
              break;
            case 'android-sdk-tools-arm64':
              exists = await hasRootfsBin('aapt2') && await hasRootfsBin('zipalign');
              break;
            case 'mold-linker':
              exists = await hasRootfsBin('mold');
              break;
            case 'rust-arm64':
              exists = await hasRootfsBin('rustc') ||
                  await File(p.join(rootfsPath, 'root', '.cargo', 'bin', 'rustc')).exists();
              break;
            case 'protobuf-compiler':
              exists = await hasRootfsBin('protoc');
              break;
            case 'sqlite-dev':
              exists = await hasRootfsBin('sqlite3') &&
                  await File(p.join(rootfsPath, 'usr', 'include', 'sqlite3.h')).exists();
              break;
            case 'build-fix':
              final marker = File(p.join(rootfsPath, 'root', '.quantum_build_fix_installed'));
              final hasAapt = await hasRootfsBin('aapt') || await hasRootfsBin('aapt2');
              exists = (await marker.exists()) || hasAapt || installedIds.contains('build-fix');
              break;
            case 'box64-emulator':
              exists = await hasRootfsBin('box64') ||
                  await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'box64')).exists() ||
                  await File(p.join(rootfsPath, 'usr', 'bin', 'box64')).exists() ||
                  installedIds.contains('box64-emulator');
              break;
            case 'vulkan-graphics':
              exists = await hasRootfsBin('vulkaninfo') ||
                  await File(p.join(rootfsPath, 'usr', 'bin', 'vulkaninfo')).exists() ||
                  installedIds.contains('vulkan-graphics');
              break;
            case 'build-clean':
              exists = installedIds.contains('build-clean');
              break;
            case 'clangd-lsp':
              exists = await hasRootfsBin('clangd');
              break;
            case 'rust-lsp':
              exists = await hasRootfsBin('rust-analyzer') ||
                  await File(p.join(rootfsPath, 'root', '.cargo', 'bin', 'rust-analyzer')).exists();
              break;
            case 'go-lsp':
              exists = await hasRootfsBin('gopls') ||
                  await File(p.join(rootfsPath, 'root', 'go', 'bin', 'gopls')).exists();
              break;
            case 'ripgrep':
              exists = await hasRootfsBin('rg');
              break;
            case 'gh-cli':
              exists = await hasRootfsBin('gh');
              break;
            case 'java-lsp':
              exists = await hasRootfsBin('jdtls') ||
                  await Directory(p.join(rootfsPath, 'usr', 'share', 'jdtls')).exists();
              break;
            case 'kotlin-lsp':
              exists = await hasRootfsBin('kotlin-language-server') ||
                  await Directory(p.join(rootfsPath, 'usr', 'share', 'kotlin-language-server')).exists();
              break;
            case 'typescript-lsp':
              exists = await hasRootfsBin('typescript-language-server');
              break;
            case 'html-css-lsp':
              exists = await hasRootfsBin('vscode-html-language-server') ||
                  await hasRootfsBin('vscode-html-languageserver');
              break;
            case 'yaml-json-lsp':
              exists = await hasRootfsBin('yaml-language-server');
              break;
            case 'markdown-lsp':
              exists = await hasRootfsBin('marksman');
              break;
            case 'vue-lsp':
              exists = await hasRootfsBin('vue-language-server');
              break;
            case 'php-lsp':
              exists = await hasRootfsBin('intelephense');
              break;
            case 'python-lsp':
              exists = await hasRootfsBin('pyright-langserver') || await hasRootfsBin('pyright');
              break;
            case 'local-ai-qwen':
              exists = await hasRootfsBin('llama-server') || await hasRootfsBin('llama-cli');
              break;
            case 'uv':
              exists = await hasRootfsBin('uv') ||
                  await File(p.join(rootfsPath, 'root', '.cargo', 'bin', 'uv')).exists();
              break;
            case 'bun':
              exists = await hasRootfsBin('bun') ||
                  await File(p.join(rootfsPath, 'root', '.bun', 'bin', 'bun')).exists();
              break;
            case 'pnpm':
              exists = await hasRootfsBin('pnpm');
              break;
            case 'desktop-build-tools':
              exists = await hasRootfsBin('clang') &&
                  await hasRootfsBin('cmake') &&
                  await hasRootfsBin('ninja');
              break;
            case 'flutter-distributor':
              exists = await File(p.join(rootfsPath, 'root', '.pub-cache', 'bin', 'flutter_distributor')).exists() ||
                  await hasRootfsBin('flutter_distributor');
              break;
          }
        }

        if (exists) {
          pkg.isInstalled = true;
          newlyInstalledIds.add(pkg.id);
        } else {
          if (installedIds.contains(pkg.id) &&
              (pkg.id == 'build-clean' ||
                  pkg.id == 'build-fix' ||
                  pkg.id == 'box64-emulator' ||
                  pkg.id == 'vulkan-graphics' ||
                  pkg.id == 'antigravity-cli' ||
                  pkg.id == 'claude-code' ||
                  pkg.id == 'deepseek-harness')) {
            pkg.isInstalled = true;
            newlyInstalledIds.add(pkg.id);
          } else {
            pkg.isInstalled = false;
          }
        }
        updatedPackages.add(pkg);
      }

      if (mounted) {
        state = updatedPackages;
      }
      await prefs.setStringList(_key, newlyInstalledIds.toList());
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final installedIds = prefs.getStringList(_key) ?? [];
    
    state = [
      for (final p in state)
        if (installedIds.contains(p.id))
          p..isInstalled = true
        else
          p
    ];
  }

  Future<void> installPackage(OptionalPackage package) async {
    final terminal = _ref.read(terminalTabsProvider.notifier);
    String command = package.command;
    if (!Platform.isAndroid) {
      command = _translateCommandForPC(command);
    }

    // Mark as installing — triggers animated spinner in the UI
    state = [for (final p in state) if (p.id == package.id) p..isInstalling = true else p];

    terminal.sendCommand(command);

    // After command dispatched to terminal, reset installing indicator
    // Actual installation status will be picked up by checkActualInstallation()
    await Future.delayed(const Duration(seconds: 3));
    state = [for (final p in state) if (p.id == package.id) p..isInstalling = false else p];
    await checkActualInstallation();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

final packageServiceProvider = StateNotifierProvider<PackageService, List<OptionalPackage>>((ref) {
  return PackageService(ref);
});
