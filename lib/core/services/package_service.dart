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
    _syncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
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
      final res = Process.runSync('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _getAndroidSdkPath() {
    final runtime = _ref.read(runtimeServiceProvider);
    if (Platform.isAndroid) {
      return p.join(runtime.filesDir, 'rootfs', 'ubuntu', 'root', 'android-sdk');
    }
    return Platform.environment['ANDROID_HOME'] ?? 
           Platform.environment['ANDROID_SDK_ROOT'] ?? 
           p.join(Platform.environment['HOME'] ?? '/home/lesorub', 'Android', 'Sdk');
  }

  String _translateCommandForPC(String cmd) {
    String translated = cmd;
    // Strip Android-specific apt/dpkg lock clearing prefix
    if (translated.contains('pgrep -x "apt|apt-get|dpkg|dpkg-deb"')) {
      final index = translated.indexOf(' ; ');
      if (index != -1 && index + 3 < translated.length) {
        translated = translated.substring(index + 3);
      }
    }
    
    // 2. Prepend sudo to apt commands
    translated = translated.replaceAll('apt update', 'sudo apt update');
    translated = translated.replaceAll('apt install', 'sudo apt install');
    
    // 3. Replace paths /root/ with ~/ or appropriate home paths
    translated = translated.replaceAll('/root/android-sdk', '~/Android/Sdk');
    translated = translated.replaceAll('/root/flutter', '~/flutter');
    translated = translated.replaceAll('/root/.bashrc', '~/.bashrc');
    translated = translated.replaceAll('/root/projects', '~/projects');
    translated = translated.replaceAll('/root/', '~/');
    
    // 4. Adapt architectures
    translated = translated.replaceAll('arm64', 'x64');
    
    // 5. Prepend sudo to global npm installs if npm is used
    translated = translated.replaceAll('npm install -g', 'sudo npm install -g');
    translated = translated.replaceAll('npm i -g', 'sudo npm i -g');
    
    // 6. Prepend sudo to script pipes and moves in system paths
    translated = translated.replaceAll('| bash', '| sudo bash');
    translated = translated.replaceAll('cp bin/llama-server /usr/bin', 'sudo cp bin/llama-server /usr/bin');
    translated = translated.replaceAll('cp bin/llama-cli /usr/bin', 'sudo cp bin/llama-cli /usr/bin');
    translated = translated.replaceAll('mv /usr/share/', 'sudo mv /usr/share/');
    translated = translated.replaceAll('mv /tmp/aapt2_download/aapt2 /usr/bin/', 'sudo mv /tmp/aapt2_download/aapt2 /usr/bin/');
    translated = translated.replaceAll('chmod +x /usr/bin/', 'sudo chmod +x /usr/bin/');
    
    return translated;
  }

  Future<void> _checkActualInstallation() async {
    final runtime = _ref.read(runtimeServiceProvider);
    final isAndroid = Platform.isAndroid;
    final filesDir = runtime.filesDir;
    if (isAndroid && filesDir.isEmpty) return;

    final updatedPackages = <OptionalPackage>[];
    final rootfsPath = isAndroid ? p.join(filesDir, 'rootfs', 'ubuntu') : '';
    final sdkPath = _getAndroidSdkPath();
    
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
        exists = await Directory(p.join(sdkPath, 'cmake', dirName)).exists();
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
          // Check on PC using PATH
          switch (pkg.id) {
            case 'python':
              exists = _hasCommand('python3') || _hasCommand('python');
              break;
            case 'nodejs':
              exists = _hasCommand('node');
              break;
            case 'git':
              exists = _hasCommand('git');
              break;
            case 'flutter':
              exists = _hasCommand('flutter');
              break;
            case 'gemini-cli':
              exists = _hasCommand('gemini');
              break;
            case 'kilocode-cli':
              exists = _hasCommand('kilocode');
              break;
            case 'opencode-ai':
              exists = _hasCommand('opencode-ai');
              break;
            case 'build-essential':
              exists = _hasCommand('gcc') || _hasCommand('g++');
              break;
            case 'android-sdk':
              exists = await Directory(sdkPath).exists() || _hasCommand('sdkmanager');
              break;
            case 'java-lsp':
              exists = _hasCommand('jdtls');
              break;
            case 'kotlin-lsp':
              exists = _hasCommand('kotlin-language-server');
              break;
            case 'typescript-lsp':
              exists = _hasCommand('typescript-language-server');
              break;
            case 'html-css-lsp':
              exists = _hasCommand('html-languageserver') || _hasCommand('vscode-html-language-server');
              break;
            case 'yaml-json-lsp':
              exists = _hasCommand('yaml-language-server');
              break;
            case 'markdown-lsp':
              exists = _hasCommand('marksman');
              break;
            case 'vue-lsp':
              exists = _hasCommand('vue-language-server');
              break;
            case 'php-lsp':
              exists = _hasCommand('intelephense');
              break;
            case 'python-lsp':
              exists = _hasCommand('pyright');
              break;
          }
        } else {
          // Check on Android inside rootfs
          switch (pkg.id) {
            case 'python':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'python3')).exists();
              break;
            case 'nodejs':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'node')).exists();
              break;
            case 'git':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'git')).exists();
              break;
            case 'flutter':
              exists = await File(p.join(rootfsPath, 'root', 'flutter', 'bin', 'flutter')).exists();
              break;
            case 'gemini-cli':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'gemini')).exists() ||
                       await File(p.join(rootfsPath, 'usr', 'bin', 'gemini')).exists();
              break;
            case 'kilocode-cli':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'kilocode')).exists();
              break;
            case 'opencode-ai':
              exists = await File(p.join(rootfsPath, 'usr', 'local', 'bin', 'opencode-ai')).exists();
              break;
            case 'build-essential':
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'gcc')).exists();
              break;
            case 'android-sdk':
              final jvmDir = Directory(p.join(rootfsPath, 'usr', 'lib', 'jvm'));
              bool hasJvm = false;
              if (jvmDir.existsSync()) {
                hasJvm = jvmDir.listSync().any((entity) =>
                    entity is Directory &&
                    p.basename(entity.path).startsWith('java-') &&
                    p.basename(entity.path).endsWith('-openjdk-arm64'));
              }
              exists = await File(p.join(rootfsPath, 'usr', 'bin', 'java')).exists() || hasJvm;
              break;
          }
        }
      }

      if (exists) {
        updatedPackages.add(pkg..isInstalled = true);
      } else {
        updatedPackages.add(pkg);
      }
    }
    
    state = updatedPackages;
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
    terminal.sendCommand(command);
    
    // Update state to marked as installed (or keep as is if already installed)
    state = [
      for (final p in state)
        if (p.id == package.id)
          p..isInstalled = true
        else
          p
    ];

    final prefs = await SharedPreferences.getInstance();
    final installedIds = state
        .where((p) => p.isInstalled)
        .map((p) => p.id)
        .toList();
    await prefs.setStringList(_key, installedIds);
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
