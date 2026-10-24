import 'dart:async';
import 'dart:convert';
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

  // High-performance pre-built ARM64 Core rootfs (Ubuntu + Node.js 24 + Git + npm)
  static const List<String> _rootfsUrls = [
    'https://github.com/Lesorub361/quantum_ide/releases/download/v1.0.0/pocketdev-core-arm64-2026.09.5.tar.zst',
    'https://github.com/techjarves/Mobile-Harness/releases/download/runtime-2026.09.4/pocketdev-core-arm64-2026.09.5.tar.zst',
  ];

  bool _isInitializing = false;

  Future<bool> isBootstrapComplete() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final bool? complete = await _channel.invokeMethod('isBootstrapComplete');
        return complete ?? false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> init() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        _filesDir = await _channel.invokeMethod('getFilesDir');
        _nativeLibDir = await _channel.invokeMethod('getNativeLibDir');
        debugPrint('RuntimeService: filesDir=$_filesDir, nativeLibDir=$_nativeLibDir');

        // 1. Prepare base directories and config files first
        await _prepareFileSystem();

        // 2. Always update scripts to ensure they have the latest fixes
        await _ensureBinaries();

        final bool complete = await _channel.invokeMethod('isBootstrapComplete');
        if (complete) {
          _isInitialized = true;
          _status = 'Ready';
          _progress = 1.0;
          notifyListeners();
          return;
        }

        await _bootstrapRootfs();
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

  Future<String> runCommand(String command, {String? workingDirectory}) async {
    await _acquireCommandSlot();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (Platform.isAndroid) {
          final initHost = p.join(_filesDir, 'bin', 'init-host');
          if (await File(initHost).exists()) {
            final guestCwd = workingDirectory != null 
                ? PathMapper.mapToGuest(workingDirectory, _filesDir)
                : '/root';
            debugPrint('RuntimeService: Running command via init-host: $command in $guestCwd');
            final result = await Process.run('sh', [
              initHost,
              _filesDir,
              guestCwd,
              '/bin/bash',
              '-c',
              command,
            ]);
            
            final output = result.stdout.toString() + result.stderr.toString();
            if (result.exitCode != 0) {
              throw Exception('Command failed (exit code ${result.exitCode}): $output');
            }
            return output;
          }
        }
        return await _channel.invokeMethod('runCommand', {'command': command});
      } else {
        // Desktop platforms direct execution
        String execCommand = command;
        if (Platform.isWindows) {
          execCommand = execCommand
              .replaceAll('2>/dev/null', '2>nul')
              .replaceAll('>/dev/null', '>nul')
              .replaceAll('cd "', 'cd /d "');
        }
        debugPrint('RuntimeService: Running command natively: $execCommand in ${workingDirectory ?? 'current'}');
        final result = await Process.run(
          Platform.isWindows ? 'cmd' : 'bash',
          Platform.isWindows ? ['/c', execCommand] : ['-c', execCommand],
          workingDirectory: workingDirectory,
        );
        final output = result.stdout.toString() + result.stderr.toString();
        if (result.exitCode != 0) {
           throw Exception('Command failed (exit code ${result.exitCode}): $output');
        }
        return output;
      }
    } catch (e) {
      debugPrint('Command failed: $command, error: $e');

      rethrow;
    } finally {
      _releaseCommandSlot();
    }
  }

  /// Desktop environment with a PATH that also covers user-local tool dirs
  /// (~/.local/bin, any ~/.nvm or ~/.config/nvm Node version, ~/.npm-global, cargo).
  Map<String, String> get desktopEnv {
    final env = Map<String, String>.from(Platform.environment);
    final home = env['HOME'] ?? '';
    final extra = <String>[
      '$home/.local/bin',
      '$home/.npm-global/bin',
      '$home/.cargo/bin',
      '$home/bin',
      '/usr/local/lib/nodejs/bin',
      '/usr/local/bin',
      '/root/.local/bin',
    ];
    for (final nvmRoot in ['$home/.nvm/versions/node', '$home/.config/nvm/versions/node']) {
      try {
        final dir = Directory(nvmRoot);
        if (dir.existsSync()) {
          final versions = dir.listSync().whereType<Directory>().map((d) => d.path).toList()
            ..sort((a, b) => b.compareTo(a));
          for (final v in versions) {
            extra.add('$v/bin');
          }
        }
      } catch (_) {}
    }
    final current = env['PATH'] ?? '/usr/local/bin:/usr/bin:/bin';
    env['PATH'] = [...extra.where((e) => Directory(e).existsSync()), current].join(':');
    env['TERM'] = 'xterm-256color';
    env.putIfAbsent('LANG', () => 'C.UTF-8');
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
          ? PathMapper.mapToGuest(workingDirectory, _filesDir)
          : '/root';
      process = await Process.start('sh', [initHost, _filesDir, guestCwd, '/bin/bash', '-c', command]);
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
      // Ensure external project directory exists
      final externalDir = Directory('/storage/emulated/0/QuantumIDE');
      if (Platform.isAndroid && !await externalDir.exists()) {
        await externalDir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('Warning: Failed to create external QuantumIDE dir: $e');
    }

    try {
      // Ensure resolv.conf exists in tmp (most reliable location — used by init-host bind mount)
      // Always rewrite it to handle the broken-symlink case on every cold start.
      final tmpDir = Directory(p.join(_filesDir, 'tmp'));
      if (!await tmpDir.exists()) await tmpDir.create(recursive: true);
      await _writeResolvConf(p.join(tmpDir.path, 'resolv.conf'));
    } catch (e) {
      debugPrint('Warning: Failed to ensure resolv.conf in tmp: $e');
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
    } catch (e) {
      debugPrint('Warning: Failed to write setup-arm64.sh / quantum-patch-ndk: $e');
    }

    try {
      await _ensureAndroidLicenses();
    } catch (e) {
      debugPrint('Warning: Failed to ensure android licenses: $e');
    }

      // Enhanced .bashrc with robust PATH, Ubuntu prompt and greeting
      // Written if missing OR if version tag has changed (to push updates to users)
    final bashrc = File(
      p.join(_filesDir, 'rootfs', 'ubuntu', 'root', '.bashrc'),
    );

    // Version tag — increment this when you need to push bashrc updates to all users
    const bashrcVersion = '16';
    const bashrcVersionLine = '# BASHRC_VERSION=$bashrcVersion';

    bool needsWrite = true;
    if (await bashrc.exists()) {
      try {
        final firstLine = await bashrc
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        needsWrite = firstLine.trim() != bashrcVersionLine;
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
# BASHRC_VERSION=16
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
    if command -v flutter >/dev/null 2>&1; then
        flutter config --jdk-dir="$JAVA_HOME" >/dev/null 2>&1 || true
    fi
fi
export PATH=$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/usr/local/bin:/usr/local/lib/nodejs/bin:/root/.local/bin:$PATH
export TERM=xterm-256color
export COLORTERM=truecolor
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoredups:erasedups

# Zero-fork pure-bash git branch prompt (avoids expensive `git status` across 3000+ files in PRoot)
__git_info() {
    if [ -f ".git/HEAD" ]; then
        local head_ref
        read -r head_ref < ".git/HEAD" 2>/dev/null || return
        local branch="${head_ref#ref: refs/heads/}"
        printf " \001\033[35m\002git:(\001\033[1;31m\002%s\001\033[0m\033[35m\002)\001\033[0m\002" "$branch"
    fi
}
export PS1="\[\e[1;36m\]➜ \[\e[1;32m\]\W\[\e[0m\]\$(__git_info) \[\e[1;34m\]\$ \[\e[0m\]"

export FLUTTER_ALLOW_SU_ROOT=true
export FLUTTER_SUPPRESS_ANALYTICS=true

alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fb-apk="(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && flutter build apk --debug --android-skip-build-dependency-validation"
alias fb-apk-release="(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && flutter build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation --no-tree-shake-icons"
alias f-clean="flutter clean && flutter pub get"
alias f-get="flutter pub get"
alias check-android="flutter doctor -v | grep -A 5 'Android toolchain'"
alias cls='clear'

# gradlew wrapper to ensure ./gradlew runs even on SD card / noexec storage
gradlew() {
    if [ -f "./gradlew" ]; then
        bash ./gradlew "$@"
    else
        command gradlew "$@"
    fi
}

# Create which shim if missing (inside guest)
if ! command -v which > /dev/null 2>&1; then
    mkdir -p /usr/bin
    printf '#!/bin/sh\ncommand -v "$1"\n' > /usr/bin/which
    chmod 755 /usr/bin/which
fi

# Modern Responsive System Fetch
term_fetch() {
    local COLS=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
    [ -z "$COLS" ] && COLS=80

    local C_RESET="\033[0m"
    local C_BOLD="\033[1m"
    local C_DIM="\033[2m"
    local C_CYAN="\033[38;5;51m"
    local C_BLUE="\033[38;5;39m"
    local C_PURPLE="\033[38;5;141m"
    local C_MAGENTA="\033[38;5;201m"
    local C_PINK="\033[38;5;213m"
    local C_GREEN="\033[38;5;48m"
    local C_YELLOW="\033[38;5;220m"
    local C_ORANGE="\033[38;5;208m"
    local C_RED="\033[38;5;196m"
    local C_WHITE="\033[38;5;255m"
    local C_GRAY="\033[38;5;245m"
    local C_DARK="\033[38;5;238m"

    local OS_NAME=$(grep -oP '(?<=PRETTY_NAME=")[^"]*' /etc/os-release 2>/dev/null)
    [ -z "$OS_NAME" ] && OS_NAME="$(uname -s)"
    local ARCH=$(uname -m)
    local KERNEL=$(uname -r | cut -d'-' -f1-2)

    local HOST_MODEL=""
    if command -v getprop >/dev/null 2>&1; then
        local BRAND=$(getprop ro.product.brand 2>/dev/null)
        local MODEL=$(getprop ro.product.model 2>/dev/null)
        [ -n "$MODEL" ] && HOST_MODEL="$BRAND $MODEL"
    fi
    if [ -z "$HOST_MODEL" ] && [ -f /sys/devices/virtual/dmi/id/product_name ]; then
        HOST_MODEL=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
    fi
    [ -z "$HOST_MODEL" ] && HOST_MODEL="$(hostname 2>/dev/null || echo 'localhost')"

    local UPTIME_STR="unknown"
    if [ -f /proc/uptime ]; then
        local UP_SECS=$(cut -d. -f1 /proc/uptime)
        local DAYS=$((UP_SECS / 86400))
        local HOURS=$(( (UP_SECS % 86400) / 3600 ))
        local MINS=$(( (UP_SECS % 3600) / 60 ))
        UPTIME_STR=""
        [ $DAYS -gt 0 ] && UPTIME_STR="${DAYS}d "
        [ $HOURS -gt 0 ] && UPTIME_STR="${UPTIME_STR}${HOURS}h "
        UPTIME_STR="${UPTIME_STR}${MINS}m"
    fi

    local CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")
    local CPU_NAME=$(grep -m1 -E 'Hardware|model name|Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    [ -z "$CPU_NAME" ] && CPU_NAME="ARM64 Processor"

    local MEM_USED_MB=0 MEM_TOTAL_MB=0 MEM_PERCENT=0
    if [ -f /proc/meminfo ]; then
        local MEM_TOTAL_KB=$(grep 'MemTotal:' /proc/meminfo | awk '{print $2}')
        local MEM_AVAIL_KB=$(grep 'MemAvailable:' /proc/meminfo | awk '{print $2}')
        [ -z "$MEM_AVAIL_KB" ] && MEM_AVAIL_KB=$(grep 'MemFree:' /proc/meminfo | awk '{print $2}')
        local MEM_USED_KB=$((MEM_TOTAL_KB - MEM_AVAIL_KB))
        MEM_USED_MB=$((MEM_USED_KB / 1024))
        MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
        [ $MEM_TOTAL_KB -gt 0 ] && MEM_PERCENT=$((MEM_USED_KB * 100 / MEM_TOTAL_KB)) || MEM_PERCENT=0
    fi

    local DISK_INFO=$(df -h / 2>/dev/null | tail -1)
    local DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
    local DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
    local DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
    [ -z "$DISK_PERCENT" ] && DISK_PERCENT=0

    _q_bar() {
        local pct=$1 width=$2 bar=""
        [ -z "$width" ] && width=10
        local filled=$((pct * width / 100))
        local empty=$((width - filled))
        for ((i=0; i<filled; i++)); do bar="${bar}█"; done
        for ((i=0; i<empty; i++)); do bar="${bar}░"; done
        echo "$bar"
    }

    local RUNTIMES=""
    command -v flutter >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Flutter "
    command -v node >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Node.js "
    command -v python3 >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Python "
    command -v rustc >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Rust "
    command -v clang >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Clang "
    [ -z "$RUNTIMES" ] && RUNTIMES="Linux Core"

    if [ "$COLS" -ge 65 ]; then
        local RAM_BAR=$(_q_bar $MEM_PERCENT 10)
        local DISK_BAR=$(_q_bar $DISK_PERCENT 10)
        echo -e "${C_CYAN}  ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗████████╗██╗   ██╗███╗   ███╗${C_RESET}"
        echo -e "${C_BLUE} ██╔═══██╗██║   ██║██╔══██╗████╗  ██║╚══██╔══╝██║   ██║████╗ ████║${C_RESET}"
        echo -e "${C_PURPLE} ██║   ██║██║   ██║███████║██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║${C_RESET}"
        echo -e "${C_MAGENTA} ╚██████╔╝╚██████╔╝██║  ██║██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║${C_RESET}"
        echo -e "${C_MAGENTA}  ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝${C_RESET}"
        echo -e "         ${C_BOLD}${C_CYAN}Q U A N T U M   I D E${C_RESET} ${C_DARK}│${C_RESET} ${C_PURPLE}Next-Gen Mobile & Desktop Studio${C_RESET}"
        echo -e " ${C_DARK}────────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "  ${C_CYAN}◆ OS      ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${OS_NAME}${C_RESET} ${C_DIM}(${ARCH})${C_RESET}"
        echo -e "  ${C_BLUE}◆ Host    ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${HOST_MODEL}${C_RESET} ${C_DIM}[Kernel: ${KERNEL}]${C_RESET}"
        echo -e "  ${C_YELLOW}◆ CPU     ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${CPU_NAME}${C_RESET} ${C_CYAN}(${CPU_CORES} cores)${C_RESET}"
        echo -e "  ${C_GREEN}◆ RAM     ${C_RESET} ${C_GRAY}::${C_RESET} ${C_GREEN}${RAM_BAR}${C_RESET} ${C_WHITE}${MEM_USED_MB}MB / ${MEM_TOTAL_MB}MB${C_RESET} ${C_DIM}(${MEM_PERCENT}%)${C_RESET}"
        echo -e "  ${C_PURPLE}◆ Disk    ${C_RESET} ${C_GRAY}::${C_RESET} ${C_PURPLE}${DISK_BAR}${C_RESET} ${C_WHITE}${DISK_USED} / ${DISK_TOTAL}${C_RESET} ${C_DIM}(${DISK_PERCENT}%)${C_RESET}"
        echo -e "  ${C_PINK}◆ Uptime  ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${UPTIME_STR}${C_RESET}"
        echo -e "  ${C_MAGENTA}◆ Stack   ${C_RESET} ${C_GRAY}::${C_RESET} ${C_CYAN}${RUNTIMES}${C_RESET}"
        echo -e " ${C_DARK}────────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "  ${C_DIM}Colors  :${C_RESET} ${C_RED}● ${C_ORANGE}● ${C_YELLOW}● ${C_GREEN}● ${C_CYAN}● ${C_BLUE}● ${C_PURPLE}● ${C_MAGENTA}●${C_RESET}"
    else
        local RAM_BAR=$(_q_bar $MEM_PERCENT 7)
        local DISK_BAR=$(_q_bar $DISK_PERCENT 7)
        echo -e "  ${C_CYAN}╭───────╮${C_RESET}  ${C_BOLD}${C_CYAN}QUANTUM IDE${C_RESET} ${C_DARK}::${C_RESET} ${C_PURPLE}Dev Studio${C_RESET}"
        echo -e "  ${C_BLUE}│ ◈   ◈ │${C_RESET}  ${C_DARK}────────────────────────────────${C_RESET}"
        echo -e "  ${C_PURPLE}│   ◆   │${C_RESET}  ${C_CYAN}OS  :${C_RESET} ${C_WHITE}${OS_NAME}${C_RESET} ${C_DIM}(${ARCH})${C_RESET}"
        echo -e "  ${C_MAGENTA}│ ◈   ◈ │${C_RESET}  ${C_YELLOW}CPU :${C_RESET} ${C_WHITE}${CPU_CORES} cores${C_RESET} ${C_DIM}[${CPU_NAME:0:15}]${C_RESET}"
        echo -e "  ${C_PINK}╰───────╯${C_RESET}  ${C_GREEN}RAM :${C_RESET} ${C_GREEN}${RAM_BAR}${C_RESET} ${C_WHITE}${MEM_USED_MB}M/${MEM_TOTAL_MB}M${C_RESET}"
        echo -e "             ${C_PURPLE}Disk:${C_RESET} ${C_PURPLE}${DISK_BAR}${C_RESET} ${C_WHITE}${DISK_USED}/${DISK_TOTAL}${C_RESET}"
        echo -e "             ${C_PINK}Up  :${C_RESET} ${C_WHITE}${UPTIME_STR}${C_RESET}"
        echo -e "  ${C_DARK}────────────────────────────────────────${C_RESET}"
        echo -e "  ${C_RED}● ${C_ORANGE}● ${C_YELLOW}● ${C_GREEN}● ${C_CYAN}● ${C_BLUE}● ${C_PURPLE}● ${C_MAGENTA}●${C_RESET}"
    fi
    echo
}

# Ubuntu Greeting & Cyberpunk Banner
if [ -z "$VTE_VERSION" ]; then
    clear
    term_fetch
    echo -e '  \e[1;36m⚡ Quick Commands:\e[0m'
    echo -e '    \e[38;5;141mll\e[0m             → ls -la'
    echo -e '    \e[38;5;141mfb-apk\e[0m         → flutter build apk (debug)'
    echo -e '    \e[38;5;141mf-clean\e[0m        → flutter clean && pub get'
    echo -e '    \e[38;5;141mfetch\e[0m          → show system stats'
    echo
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
export PATH=$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/usr/local/bin:/usr/local/lib/nodejs/bin:/root/.local/bin:$PATH
export TERM=xterm-256color
export COLORTERM=truecolor
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
PROMPT='%F{green}boss@ubuntu%f:%F{blue}%~%f%F{yellow}${vcs_info_msg_0_}%f$ '

export FLUTTER_ALLOW_SU_ROOT=true
export FLUTTER_SUPPRESS_ANALYTICS=true

alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fb-apk="flutter build apk --debug --android-skip-build-dependency-validation"
alias fb-apk-release="flutter build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation --no-tree-shake-icons"
alias f-clean="flutter clean && flutter pub get"
alias f-get="flutter pub get"
alias check-android="flutter doctor -v | grep -A 5 'Android toolchain'"
alias cls='clear'
alias fetch="/usr/local/bin/term-fetch"

if [ -z "$VTE_VERSION" ]; then
    clear
    [ -x /usr/local/bin/term-fetch ] && /usr/local/bin/term-fetch
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
            if (!await inputrc.exists() && await inputrc.parent.exists()) {
              await inputrc.writeAsString('set input-meta on\nset output-meta on\nset convert-meta off\n');
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

  String _generateTermFetchScript() {
    return r'''#!/bin/bash
# ==============================================================================
# QuantumIDE Cyberpunk System Fetch (term-fetch)
# ==============================================================================

COLS=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")
[ -z "$COLS" ] && COLS=80

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
if [ -f /proc/uptime ]; then
    UP_SECS=$(cut -d. -f1 /proc/uptime)
    DAYS=$((UP_SECS / 86400))
    HOURS=$(( (UP_SECS % 86400) / 3600 ))
    MINS=$(( (UP_SECS % 3600) / 60 ))
    UPTIME_STR=""
    [ $DAYS -gt 0 ] && UPTIME_STR="${DAYS}d "
    [ $HOURS -gt 0 ] && UPTIME_STR="${UPTIME_STR}${HOURS}h "
    UPTIME_STR="${UPTIME_STR}${MINS}m"
else
    UPTIME_STR="unknown"
fi

# 4. CPU Info
CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")
CPU_NAME=$(grep -m1 -E 'Hardware|model name|Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
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
command -v python3 >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Python "
command -v rustc >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Rust "
command -v clang >/dev/null 2>&1 && RUNTIMES="${RUNTIMES}Clang "
[ -z "$RUNTIMES" ] && RUNTIMES="Linux Core"

# RENDER
if [ "$COLS" -ge 65 ]; then
    RAM_BAR=$(make_bar $MEM_PERCENT 10)
    DISK_BAR=$(make_bar $DISK_PERCENT 10)

    echo -e "${C_CYAN}  ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗████████╗██╗   ██╗███╗   ███╗${C_RESET}"
    echo -e "${C_BLUE} ██╔═══██╗██║   ██║██╔══██╗████╗  ██║╚══██╔══╝██║   ██║████╗ ████║${C_RESET}"
    echo -e "${C_PURPLE} ██║   ██║██║   ██║███████║██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║${C_RESET}"
    echo -e "${C_MAGENTA} ╚██████╔╝╚██████╔╝██║  ██║██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║${C_RESET}"
    echo -e "${C_MAGENTA}  ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝${C_RESET}"
    echo -e "         ${C_BOLD}${C_CYAN}Q U A N T U M   I D E${C_RESET} ${C_DARK}│${C_RESET} ${C_PURPLE}Next-Gen Mobile & Desktop Studio${C_RESET}"
    echo -e " ${C_DARK}────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_CYAN}◆ OS      ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${OS_NAME}${C_RESET} ${C_DIM}(${ARCH})${C_RESET}"
    echo -e "  ${C_BLUE}◆ Host    ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${HOST_MODEL}${C_RESET} ${C_DIM}[Kernel: ${KERNEL}]${C_RESET}"
    echo -e "  ${C_YELLOW}◆ CPU     ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${CPU_NAME}${C_RESET} ${C_CYAN}(${CPU_CORES} cores)${C_RESET}"
    echo -e "  ${C_GREEN}◆ RAM     ${C_RESET} ${C_GRAY}::${C_RESET} ${C_GREEN}${RAM_BAR}${C_RESET} ${C_WHITE}${MEM_USED_MB}MB / ${MEM_TOTAL_MB}MB${C_RESET} ${C_DIM}(${MEM_PERCENT}%)${C_RESET}"
    echo -e "  ${C_PURPLE}◆ Disk    ${C_RESET} ${C_GRAY}::${C_RESET} ${C_PURPLE}${DISK_BAR}${C_RESET} ${C_WHITE}${DISK_USED} / ${DISK_TOTAL}${C_RESET} ${C_DIM}(${DISK_PERCENT}%)${C_RESET}"
    echo -e "  ${C_PINK}◆ Uptime  ${C_RESET} ${C_GRAY}::${C_RESET} ${C_WHITE}${UPTIME_STR}${C_RESET}"
    echo -e "  ${C_MAGENTA}◆ Stack   ${C_RESET} ${C_GRAY}::${C_RESET} ${C_CYAN}${RUNTIMES}${C_RESET}"
    echo -e " ${C_DARK}────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_DIM}Colors  :${C_RESET} ${C_RED}● ${C_ORANGE}● ${C_YELLOW}● ${C_GREEN}● ${C_CYAN}● ${C_BLUE}● ${C_PURPLE}● ${C_MAGENTA}●${C_RESET}"
else
    RAM_BAR=$(make_bar $MEM_PERCENT 7)
    DISK_BAR=$(make_bar $DISK_PERCENT 7)

    echo -e "  ${C_CYAN}╭───────╮${C_RESET}  ${C_BOLD}${C_CYAN}QUANTUM IDE${C_RESET} ${C_DARK}::${C_RESET} ${C_PURPLE}Dev Studio${C_RESET}"
    echo -e "  ${C_BLUE}│ ◈   ◈ │${C_RESET}  ${C_DARK}────────────────────────────────${C_RESET}"
    echo -e "  ${C_PURPLE}│   ◆   │${C_RESET}  ${C_CYAN}OS  :${C_RESET} ${C_WHITE}${OS_NAME}${C_RESET} ${C_DIM}(${ARCH})${C_RESET}"
    echo -e "  ${C_MAGENTA}│ ◈   ◈ │${C_RESET}  ${C_YELLOW}CPU :${C_RESET} ${C_WHITE}${CPU_CORES} cores${C_RESET} ${C_DIM}[${CPU_NAME:0:15}]${C_RESET}"
    echo -e "  ${C_PINK}╰───────╯${C_RESET}  ${C_GREEN}RAM :${C_RESET} ${C_GREEN}${RAM_BAR}${C_RESET} ${C_WHITE}${MEM_USED_MB}M/${MEM_TOTAL_MB}M${C_RESET}"
    echo -e "             ${C_PURPLE}Disk:${C_RESET} ${C_PURPLE}${DISK_BAR}${C_RESET} ${C_WHITE}${DISK_USED}/${DISK_TOTAL}${C_RESET}"
    echo -e "             ${C_PINK}Up  :${C_RESET} ${C_WHITE}${UPTIME_STR}${C_RESET}"
    echo -e "  ${C_DARK}────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_RED}● ${C_ORANGE}● ${C_YELLOW}● ${C_GREEN}● ${C_CYAN}● ${C_BLUE}● ${C_PURPLE}● ${C_MAGENTA}●${C_RESET}"
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

# Create proc/sys fakes if missing to avoid proot warnings
mkdir -p "\$CONFIG/proc_fakes" "\$CONFIG/sys_fakes"
touch "\$CONFIG/proc_fakes/loadavg" "\$CONFIG/proc_fakes/stat" "\$CONFIG/proc_fakes/uptime" 
touch "\$CONFIG/proc_fakes/version" "\$CONFIG/proc_fakes/vmstat" "\$CONFIG/proc_fakes/cap_last_cap"
touch "\$CONFIG/proc_fakes/max_user_watches" "\$CONFIG/proc_fakes/fips_enabled"
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

# ONLY find gradlew files in QuantumIDE folder on SD card (much faster)
find "/storage/emulated/0/QuantumIDE" -maxdepth 4 -name "gradlew" 2>/dev/null | while read -r f; do
    [ -f "\$f" ] || continue
    # Skip paths containing spaces to prevent proot CLI option parsing crashes
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

mkdir -p "\$TMPDIR"
export PROOT_TMP_DIR="\$TMPDIR"
export PROOT_LOADER="\$PROOT_LIB_DIR/libprootloader.so"
export PROOT_LOADER_32="\$PROOT_LIB_DIR/libprootloader32.so"
export LD_LIBRARY_PATH="\$FILES_DIR/lib:\$PROOT_LIB_DIR"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/local/lib/nodejs/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.local/bin:\$PATH"

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

export FLUTTER_ALLOW_SU_ROOT=true
# Force IPv4 for Java/Gradle to fix UnknownHostException in Android PRoot
# (IPv6 socket routing is broken inside PRoot on Android)
export _JAVA_OPTIONS="-Djava.net.preferIPv4Stack=true"
if [ -f /usr/bin/aapt2 ]; then
    export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=/usr/bin/aapt2"
else
    BUILD_TOOLS_AAPT2=\$(find /root/android-sdk/build-tools -name "aapt2" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "\$BUILD_TOOLS_AAPT2" ]; then
        export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=\$BUILD_TOOLS_AAPT2"
    else
        export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false"
    fi
fi

# Auto-fix resolv.conf: if it is a broken symlink (e.g. -> stub-resolv.conf that
# does not exist on Android), replace it with a real file containing working DNS.
if [ -L "\$TMPDIR/resolv.conf" ] || [ ! -f "\$TMPDIR/resolv.conf" ]; then
    rm -f "\$TMPDIR/resolv.conf"
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "\$TMPDIR/resolv.conf"
fi

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
        --bind="\$CONFIG/proc_fakes/loadavg:/proc/loadavg" \\
        --bind="\$CONFIG/proc_fakes/stat:/proc/stat" \\
        --bind="\$CONFIG/proc_fakes/uptime:/proc/uptime" \\
        --bind="\$CONFIG/proc_fakes/version:/proc/version" \\
        --bind="\$CONFIG/proc_fakes/vmstat:/proc/vmstat" \\
        --bind="\$CONFIG/proc_fakes/cap_last_cap:/proc/sys/kernel/cap_last_cap" \\
        --bind="\$CONFIG/proc_fakes/max_user_watches:/proc/sys/fs/inotify/max_user_watches" \\
        --bind="\$CONFIG/proc_fakes/fips_enabled:/proc/sys/crypto/fips_enabled" \\
        --bind="\$CONFIG/sys_fakes/empty:/sys/fs/selinux" \\
        --bind="\$FILES_DIR/projects:/root/projects" \\
        --bind="/storage/emulated/0:/sdcard" \\
        --bind="/storage/emulated/0/QuantumIDE:/root/projects/external" \\
        --bind="\$FILES_DIR/tmp:/tmp" \\
        --bind="\$ROOTFS/tmp:/dev/shm" \\
        \$BIND_OVERLAYS -0 /usr/bin/env HOME=/root USER=root TMPDIR=/tmp TEMP=/tmp PATH="\$PATH" \\
        JAVA_HOME="\$JAVA_HOME" ANDROID_HOME="\$ANDROID_HOME" ANDROID_SDK_ROOT="\$ANDROID_SDK_ROOT" \\
        LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive \\
        FLUTTER_ALLOW_SU_ROOT=true GRADLE_OPTS="\$GRADLE_OPTS" _JAVA_OPTIONS="\$_JAVA_OPTIONS" \\
        LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/lib/aarch64-linux-gnu:/lib" \\
        "\$@"
else
    # Auto-setup ARM64 environment in background
    (
      sleep 2 # Wait for session to start
      "\$PROOT" \\
          --link2symlink -L \\
          --rootfs="\$ROOTFS" \\
          -0 /usr/bin/env PATH="\$PATH" \\
          /bin/bash /root/setup-arm64.sh
    ) >/dev/null 2>&1 &

    exec "\$PROOT" \\
        --link2symlink -L --kill-on-exit \\
        --rootfs="\$ROOTFS" --cwd="\$GUEST_CWD" \\
        --bind=/dev --bind=/proc --bind=/sys \\
        --bind=/dev/urandom:/dev/random \\
        \$FD_BINDS \$SYS_BINDS \\
        --bind="\$TMPDIR/resolv.conf:/etc/resolv.conf" \\
        --bind="\$CONFIG/proc_fakes/loadavg:/proc/loadavg" \\
        --bind="\$CONFIG/proc_fakes/stat:/proc/stat" \\
        --bind="\$CONFIG/proc_fakes/uptime:/proc/uptime" \\
        --bind="\$CONFIG/proc_fakes/version:/proc/version" \\
        --bind="\$CONFIG/proc_fakes/vmstat:/proc/vmstat" \\
        --bind="\$CONFIG/proc_fakes/cap_last_cap:/proc/sys/kernel/cap_last_cap" \\
        --bind="\$CONFIG/proc_fakes/max_user_watches:/proc/sys/fs/inotify/max_user_watches" \\
        --bind="\$CONFIG/proc_fakes/fips_enabled:/proc/sys/crypto/fips_enabled" \\
        --bind="\$CONFIG/sys_fakes/empty:/sys/fs/selinux" \\
        --bind="\$FILES_DIR/projects:/root/projects" \\
        --bind="/storage/emulated/0:/sdcard" \\
        --bind="/storage/emulated/0/QuantumIDE:/root/projects/external" \\
        --bind="\$FILES_DIR/tmp:/tmp" \\
        --bind="\$ROOTFS/tmp:/dev/shm" \\
        \$BIND_OVERLAYS -0 /usr/bin/env HOME=/root USER=root TMPDIR=/tmp TEMP=/tmp PATH="\$PATH" \\
        JAVA_HOME="\$JAVA_HOME" ANDROID_HOME="\$ANDROID_HOME" ANDROID_SDK_ROOT="\$ANDROID_SDK_ROOT" \\
        LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive \\
        FLUTTER_ALLOW_SU_ROOT=true GRADLE_OPTS="\$GRADLE_OPTS" _JAVA_OPTIONS="\$_JAVA_OPTIONS" \\
        LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/lib/aarch64-linux-gnu:/lib" \\
        /bin/bash --rcfile /root/.bashrc
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
          final entries = backupHomeDir.listSync(recursive: true);
          for (final entry in entries) {
            if (entry is File) {
              final rel = p.relative(entry.path, from: backupHomeDir.path);
              final targetFile = File(p.join(restoredHome.path, rel));
              await targetFile.parent.create(recursive: true);
              await entry.copy(targetFile.path);
            }
          }
          debugPrint('RuntimeService: Successfully restored preserved user files to /root');
          await backupHomeDir.delete(recursive: true);
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
    // Desktop: pass through the real system environment
    if (!Platform.isAndroid && !Platform.isIOS) {
      return {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        'LANG': Platform.environment['LANG'] ?? 'C.UTF-8',
        'LC_ALL': Platform.environment['LC_ALL'] ?? 'C.UTF-8',
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
          '/usr/local/sbin:/usr/local/bin:/usr/local/lib/nodejs/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/root/.local/bin',
      'JAVA_HOME': _detectedJavaHome,
      'FLUTTER_ROOT': '/root/flutter',
      'USER': 'root',
      'LANG': 'C.UTF-8',
      'LC_ALL': 'C.UTF-8',
      'FLUTTER_ALLOW_SU_ROOT': 'true',
      // Force IPv4 for Java/Gradle — Android PRoot routing of IPv6 sockets is broken
      '_JAVA_OPTIONS': '-Djava.net.preferIPv4Stack=true',
      'GRADLE_OPTS':
          '-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=$_detectedAapt2',
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
          if (await backupHomeDir.exists()) await backupHomeDir.delete(recursive: true);
          await backupHomeDir.create(recursive: true);
          final entries = homeDir.listSync(recursive: true);
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
      if (await rootfs.exists()) await rootfs.delete(recursive: true);

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
                printf "Pkg.BaseRevision = %s\nPkg.Desc = Android NDK\nPkg.Revision = %s\n" "$ver" "$ver" > "$TARGET_NDK/source.properties"
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
''';
  }

  String _generateSetupArm64Script() {
    return r'''#!/bin/bash
# setup-arm64.sh - Automatically configure ARM64 environment inside QuantumIDE
# This script is called by init-host in the background.

# Always run fast NDK & CMake wrapper heal on every invocation
if [ -x /usr/local/bin/quantum-patch-ndk ]; then
    /usr/local/bin/quantum-patch-ndk --fast 2>/dev/null || true
fi

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
touch "$DONE_FLAG"

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

# gen_snapshot fix:
# Flutter AOT compilation requires gen_snapshot for the HOST architecture.
# On ARM64 Android, Flutter looks for android-arm64-release/linux-arm64/gen_snapshot
# but only linux-x64 is shipped by default. Copy the linux-arm64 version.
FLUTTER_ENGINE="/root/flutter/bin/cache/artifacts/engine"
if [ -f "$FLUTTER_ENGINE/linux-arm64/gen_snapshot" ]; then
    for build_type in android-arm64-release android-arm64-profile; do
        TARGET_DIR="$FLUTTER_ENGINE/$build_type/linux-arm64"
        if [ ! -f "$TARGET_DIR/gen_snapshot" ]; then
            mkdir -p "$TARGET_DIR"
            cp "$FLUTTER_ENGINE/linux-arm64/gen_snapshot" "$TARGET_DIR/gen_snapshot"
            chmod +x "$TARGET_DIR/gen_snapshot"
            echo "[setup-arm64] Installed gen_snapshot for $build_type/linux-arm64"
        fi
    done
fi

# 2. Project Patching (Auto-fix common build issues on ARM64)
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 4 -name "gradle.properties" 2>/dev/null | while read f; do
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

# Ensure modern aapt2 wrapper via QEMU is present and functional (supports Android 35/36+)
if [ -f /usr/local/lib/aapt2-bin ] && [ -x /usr/bin/qemu-x86_64-static ]; then
    if [ ! -f /usr/bin/aapt2 ] || [ -L /usr/bin/aapt2 ] || ! grep -q "qemu-x86_64-static" /usr/bin/aapt2 2>/dev/null; then
        rm -f /usr/bin/aapt2
        cat << 'AAPT2_EOF' > /usr/bin/aapt2
#!/bin/sh
if [ "$1" = "version" ]; then
    exec /usr/bin/qemu-x86_64-static /usr/local/lib/aapt2-bin "$@" 2>&1
fi
exec /usr/bin/qemu-x86_64-static /usr/local/lib/aapt2-bin "$@"
AAPT2_EOF
        chmod +x /usr/bin/aapt2
    fi
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
  find /root/.gradle -name "aapt2" -exec cp /usr/bin/aapt2 {} \; 2>/dev/null || true
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
  update-ca-certificates -f >/dev/null 2>&1 || true
  if [ ! -f "/etc/ssl/certs/ca-certificates.crt" ] || [ ! -f "/etc/ca-certificates.conf" ]; then
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y --reinstall ca-certificates >/dev/null 2>&1 || true
    update-ca-certificates -f >/dev/null 2>&1 || true
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
# Symlink SDK build-tools to native tools on the fly
if [ -d "$SDK_ROOT/build-tools" ]; then
    for bt in "$SDK_ROOT/build-tools/"*; do
        if [ -d "$bt" ] && [ "$bt" != "$SDK_ROOT/build-tools/debian" ]; then
            [ -f /usr/bin/aapt2 ] && [ ! -L /usr/bin/aapt2 ] && ln -sf /usr/bin/aapt2 "$bt/aapt2"
            [ -f /usr/bin/aapt ] && [ ! -L /usr/bin/aapt ] && ln -sf /usr/bin/aapt "$bt/aapt"
            [ -f /usr/bin/zipalign ] && [ ! -L /usr/bin/zipalign ] && ln -sf /usr/bin/zipalign "$bt/zipalign"
            [ -f /usr/bin/apksigner ] && [ ! -L /usr/bin/apksigner ] && ln -sf /usr/bin/apksigner "$bt/apksigner"
        fi
    done
fi

# Symlink newly downloaded Gradle cached AAPT2 binaries
if [ -d "/root/.gradle" ] && [ -f "/usr/bin/aapt2" ]; then
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

# Patch Groovy build.gradle to force arm64-v8a abiFilters
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 5 -name "build.gradle" 2>/dev/null | while read -r f; do
    if grep -q "defaultConfig" "$f" 2>/dev/null; then
        if ! grep -q "abiFilters" "$f" 2>/dev/null; then
            python3 -c '
import sys
path = sys.argv[1]
with open(path, "r") as file:
    content = file.read()
if "defaultConfig {" in content and "abiFilters" not in content:
    patched = content.replace("defaultConfig {", "defaultConfig {\n        ndk {\n            abiFilters \x27arm64-v8a\x27\n        }")
    with open(path, "w") as file:
        file.write(patched)
' "$f" 2>/dev/null
        fi
    fi
done

# Patch Kotlin build.gradle.kts to force arm64-v8a abiFilters
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 5 -name "build.gradle.kts" 2>/dev/null | while read -r f; do
    if grep -q "defaultConfig" "$f" 2>/dev/null; then
        if ! grep -q "abiFilters" "$f" 2>/dev/null; then
            python3 -c '
import sys
path = sys.argv[1]
with open(path, "r") as file:
    content = file.read()
if "defaultConfig {" in content and "abiFilters" not in content:
    patched = content.replace("defaultConfig {", "defaultConfig {\n        ndk {\n            abiFilters += listOf(\"arm64-v8a\")\n        }")
    with open(path, "w") as file:
        file.write(patched)
' "$f" 2>/dev/null
        fi
    fi
done
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
