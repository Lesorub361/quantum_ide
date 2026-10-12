import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/optional_package.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

class PackageService extends StateNotifier<List<OptionalPackage>> {
  final Ref _ref;
  static const _key = 'installed_packages';
  Timer? _syncTimer;
  
  PackageService(this._ref) : super(defaultPackages) {
    _init();
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkActualInstallation();
    });
  }

  Future<void> checkActualInstallation() => _checkActualInstallation();

  Future<void> _init() async {
    await _loadState();
    await _checkActualInstallation();
  }

  bool _hasCommand(String cmd) {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty && File(p.join(home, '.local', 'bin', cmd)).existsSync()) {
        return true;
      }
      if (File('/usr/local/bin/$cmd').existsSync() ||
          File('/usr/bin/$cmd').existsSync() ||
          File('/usr/local/lib/nodejs/bin/$cmd').existsSync() ||
          File('/root/.local/bin/$cmd').existsSync()) {
        return true;
      }
      final res = Process.runSync('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _getAndroidSdkPath() {
    if (Directory('/root/android-sdk').existsSync()) {
      return '/root/android-sdk';
    }
    if (Directory('/usr/lib/android-sdk').existsSync()) {
      return '/usr/lib/android-sdk';
    }
    final home = Platform.environment['HOME'] ?? '/root';
    final userSdk = p.join(home, 'Android', 'Sdk');
    if (Directory(userSdk).existsSync()) {
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
        if (Directory(candidate).existsSync()) return candidate;
      }
    }
    return Platform.environment['ANDROID_HOME'] ?? 
           Platform.environment['ANDROID_SDK_ROOT'] ?? 
           p.join(home, 'android-sdk');
  }

  String _translateCommandForPC(String cmd) {
    // If running as root (e.g. inside Linux chroot/PRoot or root container), keep root paths and do not use sudo
    final isRoot = (Platform.environment['USER'] == 'root') || (Platform.environment['HOME'] == '/root');
    if (isRoot) {
      return cmd;
    }

    String translated = cmd;
    // 1. Strip Android-specific apt/dpkg lock clearing and root export prefix
    const lockMarker = 'ca-certificates 2>/dev/null || true ; ';
    if (translated.contains(lockMarker)) {
      final index = translated.indexOf(lockMarker);
      translated = translated.substring(index + lockMarker.length);
    } else if (translated.contains('kill -9 \$(pgrep')) {
      final parts = translated.split(' ; ');
      translated = parts.where((p) => 
        !p.contains('pgrep') && 
        !p.contains('/var/lib/') && 
        !p.contains('/var/cache/') && 
        !p.contains('dpkg --configure') &&
        !p.contains('export HOME=/root') &&
        !p.contains('export USER=root')
      ).join(' ; ');
    }
    
    // 2. Prepend sudo to apt commands with resilient fallback
    translated = translated.replaceAll('apt update', '(sudo apt-get update -o Acquire::Retries=1 2>/dev/null || sudo apt update 2>/dev/null || true)');
    translated = translated.replaceAll('apt install', 'sudo apt install');
    
    // 3. Replace paths /root/ with ~/ or appropriate home paths
    translated = translated.replaceAll('/root/android-sdk', '~/Android/Sdk');
    translated = translated.replaceAll('/root/flutter', '~/flutter');
    translated = translated.replaceAll('/root/.bashrc', '~/.bashrc');
    translated = translated.replaceAll('/root/.profile', '~/.profile');
    translated = translated.replaceAll('/root/projects', '~/projects');
    translated = translated.replaceAll('/root/', '~/');
    
    // 4. Adapt architectures only if on x86_64
    final arch = Platform.version.toLowerCase();
    if (!arch.contains('arm') && !arch.contains('aarch64')) {
      translated = translated.replaceAll('arm64', 'x64');
    }
    
    // 5. Prepend sudo to global npm installs if npm is used
    translated = translated.replaceAll('npm install -g', 'sudo npm install -g');
    translated = translated.replaceAll('npm i -g', 'sudo npm i -g');
    
    // 6. Prepend sudo to script pipes and moves in system paths
    translated = translated.replaceAll('| bash', '| sudo bash');
    translated = translated.replaceAll('cp bin/llama-server /usr/bin', 'sudo cp bin/llama-server /usr/bin');
    translated = translated.replaceAll('cp bin/llama-cli /usr/bin', 'sudo cp bin/llama-cli /usr/bin');
    translated = translated.replaceAll('cp {} /usr/bin/', 'sudo cp {} /usr/bin/');
    translated = translated.replaceAll('cp {} /usr/lib/', 'sudo cp {} /usr/lib/');
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
    await _checkActualInstallation();
  }

  Future<void> _checkActualInstallation() async {
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
        if (Directory(cp).existsSync()) {
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
    final sdkPath = _getAndroidSdkPath();
    final newlyInstalledIds = <String>{};
    
    for (final pkg in state) {
      bool exists = false;
      
      if (pkg.id.startsWith('platform-android-')) {
        final version = pkg.id.replaceFirst('platform-android-', '');
        exists = await Directory(p.join(sdkPath, 'platforms', 'android-$version')).exists();
      } else if (pkg.id.startsWith('build-tools-')) {
        final version = pkg.id.replaceFirst('build-tools-', '');
        exists = await Directory(p.join(sdkPath, 'build-tools', version)).exists();
      } else if (pkg.id.startsWith('cmake-')) {
        final version = pkg.id.replaceFirst('cmake-', '');
        final dirName = version == '3.6' ? '3.6.4111459'
            : (version == '3.10' ? '3.10.2.4988404'
            : (version == '3.18' ? '3.18.1'
            : (version == '3.22' ? '3.22.1'
            : (version == '3.31' ? '3.31.0' : version))));
        exists = await Directory(p.join(sdkPath, 'cmake', dirName)).exists() ||
                 _hasCommand('cmake');
      } else if (pkg.id.startsWith('ndk-')) {
        final version = pkg.id.replaceFirst('ndk-', '');
        final dirName = version == 'r21e' ? '21.4.7075529'
            : (version == 'r22b' ? '22.1.7171670'
            : (version == 'r23b' ? '23.1.7779620'
            : (version == 'r24' ? '24.0.8215888'
            : (version == 'r25c' ? '25.1.8937393'
            : (version == 'r26b' ? '26.1.10909125'
            : (version == 'r27b' ? '27.0.12077973'
            : (version == 'r28' ? '28.0.12433547'
            : (version == 'r29' ? '29.0.14206865' : version))))))));
        exists = await Directory(p.join(sdkPath, 'ndk', dirName)).exists();
      } else {
        if (!isAndroid) {
          // Check on PC / Container using PATH and host filesystem
          switch (pkg.id) {
            case 'python':
              exists = _hasCommand('python3') || _hasCommand('python');
              break;
            case 'nodejs':
              exists = _hasCommand('node') ||
                       File('/usr/local/lib/nodejs/bin/node').existsSync() ||
                       File('/usr/local/bin/node').existsSync() ||
                       File('/usr/bin/node').existsSync();
              break;
            case 'git':
              exists = _hasCommand('git');
              break;
            case 'flutter':
              exists = _hasCommand('flutter') ||
                       File(p.join(Platform.environment['HOME'] ?? '', 'flutter', 'bin', 'flutter')).existsSync() ||
                       File('/root/flutter/bin/flutter').existsSync();
              break;
            case 'antigravity-cli':
              exists = _hasCommand('agy') || _hasCommand('antigravity') ||
                       File('/usr/local/bin/agy').existsSync() ||
                       File('/usr/local/bin/antigravity').existsSync() ||
                       File('/usr/bin/agy').existsSync() ||
                       File('/usr/bin/antigravity').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/agy').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/antigravity').existsSync() ||
                       File(p.join(Platform.environment['HOME'] ?? '', '.local', 'bin', 'agy')).existsSync() ||
                       File(p.join(Platform.environment['HOME'] ?? '', '.local', 'bin', 'antigravity')).existsSync();
              break;
            case 'claude-code':
              exists = _hasCommand('claude') ||
                       File('/usr/local/bin/claude').existsSync() ||
                       File('/usr/bin/claude').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/claude').existsSync() ||
                       Directory('/usr/local/lib/nodejs/lib/node_modules/@anthropic-ai/claude-code').existsSync() ||
                       Directory('/usr/local/lib/node_modules/@anthropic-ai/claude-code').existsSync() ||
                       File(p.join(Platform.environment['HOME'] ?? '', '.local', 'bin', 'claude')).existsSync();
              break;
            case 'deepseek-harness':
              exists = _hasCommand('dsh') || _hasCommand('deepseek-harness') ||
                       File('/usr/local/bin/dsh').existsSync() ||
                       File('/usr/bin/dsh').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/dsh').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/deepseek-harness').existsSync() ||
                       Directory('/usr/local/lib/nodejs/lib/node_modules/@deepseek-ai/dsh').existsSync() ||
                       Directory('/usr/local/lib/node_modules/@deepseek-ai/dsh').existsSync() ||
                       File(p.join(Platform.environment['HOME'] ?? '', '.local', 'bin', 'dsh')).existsSync();
              break;
            case 'ollama-cli':
              exists = _hasCommand('ollama') ||
                       File('/usr/local/bin/ollama').existsSync() ||
                       File('/usr/bin/ollama').existsSync();
              break;
            case 'kilocode-cli':
              exists = _hasCommand('kilocode') ||
                       File('/usr/local/bin/kilocode').existsSync() ||
                       File('/usr/bin/kilocode').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/kilocode').existsSync() ||
                       Directory('/usr/local/lib/nodejs/lib/node_modules/@kilocode/cli').existsSync() ||
                       Directory('/usr/local/lib/node_modules/@kilocode/cli').existsSync();
              break;
            case 'opencode-ai':
              exists = _hasCommand('opencode-ai') || _hasCommand('opencode') ||
                       File('/usr/local/bin/opencode-ai').existsSync() ||
                       File('/usr/local/bin/opencode').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/opencode-ai').existsSync() ||
                       File('/usr/local/lib/nodejs/bin/opencode').existsSync() ||
                       Directory('/usr/local/lib/nodejs/lib/node_modules/opencode-ai').existsSync() ||
                       Directory('/usr/local/lib/node_modules/opencode-ai').existsSync();
              break;
            case 'build-essential':
              exists = _hasCommand('gcc') || _hasCommand('g++');
              break;
            case 'android-sdk':
              exists = await Directory(sdkPath).exists() || _hasCommand('sdkmanager');
              break;
            case 'build-fix':
              final homeDir = Platform.environment['HOME'] ?? '/root';
              final marker = File(p.join(homeDir, '.quantum_build_fix_installed'));
              final rootMarker = File('/root/.quantum_build_fix_installed');
              final gradleProp = File(p.join(homeDir, '.gradle', 'gradle.properties'));
              bool hasGradleFix = false;
              if (gradleProp.existsSync()) {
                try {
                  final text = gradleProp.readAsStringSync();
                  hasGradleFix = text.contains('aapt2.daemon=false') || text.contains('aapt2FromMavenOverride');
                } catch (_) {}
              }
              final hasAapt2 = _hasCommand('aapt2') || File('/usr/bin/aapt2').existsSync();
              exists = marker.existsSync() || rootMarker.existsSync() || (hasAapt2 && hasGradleFix);
              break;
            case 'build-clean':
              exists = installedIds.contains('build-clean');
              break;
            case 'clangd-lsp':
              exists = _hasCommand('clangd') || File('/usr/bin/clangd').existsSync();
              break;
            case 'rust-lsp':
              exists = _hasCommand('rust-analyzer') || _hasCommand('rustc') || File('/usr/bin/rust-analyzer').existsSync();
              break;
            case 'go-lsp':
              exists = _hasCommand('gopls') || _hasCommand('go') || File('/usr/bin/gopls').existsSync();
              break;
            case 'ripgrep':
              exists = _hasCommand('rg') || File('/usr/bin/rg').existsSync();
              break;
            case 'gh-cli':
              exists = _hasCommand('gh') || File('/usr/bin/gh').existsSync();
              break;
            case 'java-lsp':
              exists = _hasCommand('jdtls') || File('/usr/bin/jdtls').existsSync() || Directory('/usr/share/jdtls').existsSync();
              break;
            case 'kotlin-lsp':
              exists = _hasCommand('kotlin-language-server') || File('/usr/bin/kotlin-language-server').existsSync() || Directory('/usr/share/kotlin-language-server').existsSync();
              break;
            case 'typescript-lsp':
              exists = _hasCommand('typescript-language-server');
              break;
            case 'html-css-lsp':
              exists = _hasCommand('html-languageserver') || _hasCommand('vscode-html-language-server') || _hasCommand('vscode-html-languageserver');
              break;
            case 'yaml-json-lsp':
              exists = _hasCommand('yaml-language-server');
              break;
            case 'markdown-lsp':
              exists = _hasCommand('marksman') || File('/usr/bin/marksman').existsSync() || File('/usr/local/bin/marksman').existsSync();
              break;
            case 'vue-lsp':
              exists = _hasCommand('vue-language-server');
              break;
            case 'php-lsp':
              exists = _hasCommand('intelephense');
              break;
            case 'python-lsp':
              exists = _hasCommand('pyright') || _hasCommand('pyright-langserver');
              break;
            case 'local-ai-qwen':
              exists = _hasCommand('llama-server') || _hasCommand('llama-cli');
              break;
          }
        } else {
          // Check on Android inside rootfs
          switch (pkg.id) {
            case 'python':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'python3')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'python')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'python3')).exists();
              break;
            case 'nodejs':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'node')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'node')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'node')).exists();
              break;
            case 'git':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'git')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'git')).exists();
              break;
            case 'flutter':
              exists = await File(p.join(rootfsPath, 'root', 'flutter', 'bin', 'flutter')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'flutter')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'flutter')).exists();
              break;
            case 'antigravity-cli':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'agy')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'agy')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'agy')).exists() ||
                       await File(p.join(rootfsPath, 'root', '.local', 'bin', 'agy')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'antigravity')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'antigravity')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'antigravity')).exists() ||
                       await File(p.join(rootfsPath, 'root', '.local', 'bin', 'antigravity')).exists();
              break;
            case 'claude-code':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'claude')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'claude')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'claude')).exists() ||
                       await File(p.join(rootfsPath, 'root', '.local', 'bin', 'claude')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@anthropic-ai', 'claude-code')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'node_modules', '@anthropic-ai', 'claude-code')).exists();
              break;
            case 'deepseek-harness':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'dsh')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'dsh')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'dsh')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'deepseek-harness')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'deepseek-harness')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'deepseek-harness')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@deepseek-ai', 'dsh')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'node_modules', '@deepseek-ai', 'dsh')).exists();
              break;
            case 'ollama-cli':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'ollama')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'ollama')).exists();
              break;
            case 'kilocode-cli':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'kilocode')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'kilocode')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'kilocode')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', '@kilocode', 'cli')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'node_modules', '@kilocode', 'cli')).exists();
              break;
            case 'opencode-ai':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'opencode-ai')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'opencode-ai')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'opencode')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'opencode')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'opencode-ai')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'opencode')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'lib', 'node_modules', 'opencode-ai')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'local', 'lib', 'node_modules', 'opencode-ai')).exists();
              break;
            case 'build-essential':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'gcc')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'g++')).exists();
              break;
            case 'android-sdk':
              final jvmDir = Directory(p.join(rootfsPath, 'usr', 'lib', 'jvm'));
              bool hasJvm = false;
              if (jvmDir.existsSync()) {
                hasJvm = jvmDir.listSync().any((entity) =>
                    entity is Directory &&
                    p.basename(entity.path).startsWith('java-') &&
                    p.basename(entity.path).contains('-openjdk-'));
              }
              final hasJava = await File(p.join(rootfsPath, 'usr', 'bin', 'java')).exists() || hasJvm;
              final hasSdkManager = await File(p.join(sdkPath, 'cmdline-tools', 'latest', 'bin', 'sdkmanager')).exists() ||
                                   await File(p.join(sdkPath, 'cmdline-tools', 'bin', 'sdkmanager')).exists() ||
                                   await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'sdkmanager')).exists() ||
                                   await File(p.join(rootfsPath, 'usr', 'bin', 'sdkmanager')).exists();
              exists = hasJava && hasSdkManager;
              break;
            case 'build-fix':
              final marker = File(p.join(rootfsPath, 'root', '.quantum_build_fix_installed'));
              final gradleProp = File(p.join(rootfsPath, 'root', '.gradle', 'gradle.properties'));
              bool hasGradleFix = false;
              if (await gradleProp.exists()) {
                try {
                  final text = await gradleProp.readAsString();
                  hasGradleFix = text.contains('aapt2.daemon=false') || text.contains('aapt2FromMavenOverride');
                } catch (_) {}
              }
              final hasAapt2 = await File(p.join(rootfsPath, 'usr', 'bin', 'aapt2')).exists();
              exists = (await marker.exists()) || (hasAapt2 && hasGradleFix);
              break;
            case 'build-clean':
              exists = installedIds.contains('build-clean');
              break;
            case 'clangd-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'clangd')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'clangd')).exists();
              break;
            case 'rust-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'rust-analyzer')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'rust-analyzer')).exists() ||
                       await File(p.join(rootfsPath, 'root', '.cargo', 'bin', 'rust-analyzer')).exists();
              break;
            case 'go-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'gopls')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'gopls')).exists() ||
                       await File(p.join(rootfsPath, 'root', 'go', 'bin', 'gopls')).exists();
              break;
            case 'ripgrep':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'rg')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'rg')).exists();
              break;
            case 'gh-cli':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'gh')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'gh')).exists();
              break;
            case 'java-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'jdtls')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'jdtls')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'share', 'jdtls')).exists();
              break;
            case 'kotlin-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'kotlin-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'kotlin-language-server')).exists() ||
                       await Directory(p.join(rootfsPath, 'usr', 'share', 'kotlin-language-server')).exists();
              break;
            case 'typescript-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'typescript-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'typescript-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'typescript-language-server')).exists();
              break;
            case 'html-css-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'vscode-html-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'vscode-html-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'vscode-html-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'vscode-html-languageserver')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'vscode-html-languageserver')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'vscode-html-languageserver')).exists();
              break;
            case 'yaml-json-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'yaml-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'yaml-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'yaml-language-server')).exists();
              break;
            case 'markdown-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'marksman')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'marksman')).exists();
              break;
            case 'vue-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'vue-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'vue-language-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'vue-language-server')).exists();
              break;
            case 'php-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'intelephense')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'intelephense')).exists();
              break;
            case 'python-lsp':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'pyright-langserver')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'pyright-langserver')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'pyright-langserver')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'pyright')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'pyright')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'lib', 'nodejs', 'bin', 'pyright')).exists();
              break;
            case 'local-ai-qwen':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'llama-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'llama-server')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'llama-cli')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'llama-cli')).exists();
              break;
          }
        }
      }

      if (exists) {
        pkg.isInstalled = true;
        newlyInstalledIds.add(pkg.id);
      } else {
        if (installedIds.contains(pkg.id) && (pkg.id == 'build-clean' || pkg.id == 'build-fix')) {
          pkg.isInstalled = true;
          newlyInstalledIds.add(pkg.id);
        } else {
          pkg.isInstalled = false;
        }
      }
      updatedPackages.add(pkg);
    }
    
    state = updatedPackages;
    await prefs.setStringList(_key, newlyInstalledIds.toList());
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
