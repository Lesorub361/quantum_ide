import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:quantum_ide/core/utils/path_mapper.dart';

class RuntimeService extends ChangeNotifier {
  static const _channel = MethodChannel('com.example.quantum_ide/native');

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String _status = 'Idle';
  String get status => _status;

  double _progress = 0;
  double get progress => _progress;

  late String _filesDir;
  String get filesDir => _filesDir;
  late String _nativeLibDir;
  final _dio = Dio();

  // URL for rootfs (Ubuntu 24.04.4 Noble Numbat)
  static const _rootfsUrl =
      'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.4-base-arm64.tar.gz';

  bool _isInitializing = false;

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
        // Desktop platform — use a persistent directory in HOME
        final homeDir = Platform.environment['HOME'] ?? Directory.current.path;
        final desktopDataDir = Directory(p.join(homeDir, '.quantum_ide'));
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

  Future<String> runCommand(String command, {String? workingDirectory}) async {
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
        debugPrint('RuntimeService: Running command natively: $command in ${workingDirectory ?? 'current'}');
        final result = await Process.run(
          Platform.isWindows ? 'cmd' : 'bash',
          Platform.isWindows ? ['/c', command] : ['-c', command],
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
    }
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
    } catch (e) {
      debugPrint('Warning: Failed to write setup-arm64.sh: $e');
    }

      // Enhanced .bashrc with robust PATH, Ubuntu prompt and greeting
      // Written if missing OR if version tag has changed (to push updates to users)
    final bashrc = File(
      p.join(_filesDir, 'rootfs', 'ubuntu', 'root', '.bashrc'),
    );

    // Version tag — increment this when you need to push bashrc updates to all users
    const bashrcVersion = '3';
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
      const bashrcContent = r'''
# BASHRC_VERSION=3
export ANDROID_HOME=/root/android-sdk
export ANDROID_SDK_ROOT=/root/android-sdk
# Dynamically detect JAVA_HOME inside guest
if [ -d "/root/jdk-17" ]; then
    export JAVA_HOME="/root/jdk-17"
else
    DETECTED_JVM=$(ls -d /usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)
    if [ -n "$DETECTED_JVM" ]; then
        export JAVA_HOME="$DETECTED_JVM"
    else
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-arm64"
    fi
fi
export PATH=$JAVA_HOME/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin:/usr/local/bin:/root/.local/bin:$PATH
export TERM=xterm-256color
export COLORTERM=truecolor
export HISTSIZE=5000
export HISTFILESIZE=10000
export HISTCONTROL=ignoredups:erasedups

# Show git branch in prompt
__git_branch() {
    git branch 2>/dev/null | grep '^*' | sed 's/* //'
}
export PS1="\[\e[1;32m\]boss@ubuntu\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\[\e[1;33m\]\$(__git_branch_str)\[\e[0m\]\$ "
__git_branch_str() {
    local b=$(__git_branch)
    [ -n "$b" ] && echo " ($b)"
}

export FLUTTER_ALLOW_SU_ROOT=true
export FLUTTER_SUPPRESS_ANALYTICS=true

alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fb-apk="flutter build apk --debug --android-skip-build-dependency-validation"
alias fb-apk-release="flutter build apk --release --android-skip-build-dependency-validation"
alias f-clean="flutter clean && flutter pub get"
alias f-get="flutter pub get"
alias check-android="flutter doctor -v | grep -A 5 'Android toolchain'"
alias cls='clear'

# Create which shim if missing (inside guest)
if ! command -v which > /dev/null 2>&1; then
    mkdir -p /usr/bin
    printf '#!/bin/sh\ncommand -v "$1"\n' > /usr/bin/which
    chmod 755 /usr/bin/which
fi

# Ubuntu Greeting
if [ -z "$VTE_VERSION" ]; then
    clear
    echo -e "\e[1;36m ██████   ██    ██   █████   ███    ██  ████████  ██    ██  ███    ███ \e[0m"
    echo -e "\e[1;36m██    ██  ██    ██  ██   ██  ████   ██     ██     ██    ██  ████  ████ \e[0m"
    echo -e "\e[1;36m██    ██  ██    ██  ███████  ██ ██  ██     ██     ██    ██  ██ ████ ██ \e[0m"
    echo -e "\e[1;36m██ ▄▄ ██  ██    ██  ██   ██  ██  ██ ██     ██     ██    ██  ██  ██  ██ \e[0m"
    echo -e "\e[1;36m ██████    ██████   ██   ██  ██   ████     ██      ██████   ██      ██ \e[0m"
    echo -e "\e[1;36m    ▀▀                                                                 \e[0m"
    echo -e "\e[1;34m                      ██████  ██████  ███████                          \e[0m"
    echo -e "\e[1;34m                        ██    ██   ██ ██                               \e[0m"
    echo -e "\e[1;34m                        ██    ██   ██ █████                            \e[0m"
    echo -e "\e[1;34m                        ██    ██   ██ ██                               \e[0m"
    echo -e "\e[1;34m                      ██████  ██████  ███████                          \e[0m"
    echo
    echo -e '\e[1;35mWelcome to Ubuntu 24.04 LTS (Quantum Edition v3)\e[0m'
    echo -e '\e[1;32mPowered by Quantum IDE — Your Mobile Dev Environment\e[0m'
    echo
    echo -e '\e[1;34m  Useful aliases:\e[0m'
    echo -e '\e[0;37m    ll           = ls -la\e[0m'
    echo -e '\e[0;37m    fb-apk       = flutter build apk --debug\e[0m'
    echo -e '\e[0;37m    fb-apk-release = flutter build apk --release\e[0m'
    echo -e '\e[0;37m    f-clean      = flutter clean && pub get\e[0m'
    echo
    echo -e '\e[1;31m  TIP:\e[0m If "Permission denied" on gradlew: move project to /root/projects'
    echo
fi
''';
      try {
        if (await bashrc.parent.exists()) {
          await bashrc.writeAsString(bashrcContent.replaceAll('\r', ''));
        }
      } catch (e) {
        debugPrint('Warning: Failed to write .bashrc: $e');
      }
    }
  }

  Future<void> updateScripts() async {
    await _ensureBinaries();
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

# Map common Android GIDs to avoid warnings
for gid in 1077 1078 1079 3003 9997 20487 50487; do
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
find "/storage/emulated/0/QuantumIDE" -maxdepth 4 -name "gradlew" 2>/dev/null | while read f; do
    SAFE_NAME=\$(echo "\$f" | tr '/' '_')
    SHADOW_PATH="\$SHADOW_DIR/\$SAFE_NAME"
    cp "\$f" "\$SHADOW_PATH"
    chmod 755 "\$SHADOW_PATH"
    GUEST_F=\$(echo "\$f" | sed "s|/storage/emulated/0/QuantumIDE|/root/projects/external|g" | sed "s|/storage/emulated/0|/sdcard|g")
    echo "--bind=\$SHADOW_PATH:\$GUEST_F" >> "\$TMPDIR/proot_binds"
done

if [ -f "\$TMPDIR/proot_binds" ]; then
    BIND_OVERLAYS=\$(cat "\$TMPDIR/proot_binds" | tr '\n' ' ')
    rm "\$TMPDIR/proot_binds"
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
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin:/root/flutter/bin:\$PATH"

# Prefer /root/jdk-17 if available
if [ -d "\$ROOTFS/root/jdk-17" ]; then
    export JAVA_HOME="/root/jdk-17"
else
    # Dynamically detect JVM folder inside \$ROOTFS/usr/lib/jvm/
    DETECTED_JVM=\$(ls -d "\$ROOTFS"/usr/lib/jvm/java-*-openjdk-arm64 2>/dev/null | head -n 1)
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
    export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=/usr/bin/aapt2"
else
    BUILD_TOOLS_AAPT2=\$(find /root/android-sdk/build-tools -name "aapt2" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "\$BUILD_TOOLS_AAPT2" ]; then
        export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=\$BUILD_TOOLS_AAPT2"
    else
        export GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false"
    fi
fi

# Auto-fix resolv.conf: if it is a broken symlink (e.g. -> stub-resolv.conf that
# does not exist on Android), replace it with a real file containing working DNS.
if [ -L "\$TMPDIR/resolv.conf" ] || [ ! -f "\$TMPDIR/resolv.conf" ]; then
    rm -f "\$TMPDIR/resolv.conf"
    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "\$TMPDIR/resolv.conf"
fi

# shellcheck disable=SC2086
if [ \$# -gt 2 ]; then
    shift 2
    exec "\$PROOT" \\
        --link2symlink -L --kill-on-exit \\
        --rootfs="\$ROOTFS" --cwd="\$GUEST_CWD" \\
        --bind=/dev --bind=/proc --bind=/sys \\
        --bind=/dev/urandom:/dev/random \\
        --bind=/proc/self/fd:/dev/fd \\
        --bind=/proc/self/fd/0:/dev/stdin \\
        --bind=/proc/self/fd/1:/dev/stdout \\
        --bind=/proc/self/fd/2:/dev/stderr \\
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
        \$BIND_OVERLAYS -0 /usr/bin/env TMPDIR=/tmp TEMP=/tmp PATH="\$PATH" \\
        JAVA_HOME="\$JAVA_HOME" ANDROID_HOME="\$ANDROID_HOME" ANDROID_SDK_ROOT="\$ANDROID_SDK_ROOT" \\
        FLUTTER_ALLOW_SU_ROOT=true GRADLE_OPTS="\$GRADLE_OPTS" _JAVA_OPTIONS="\$_JAVA_OPTIONS" \\
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
        --bind=/proc/self/fd:/dev/fd \\
        --bind=/proc/self/fd/0:/dev/stdin \\
        --bind=/proc/self/fd/1:/dev/stdout \\
        --bind=/proc/self/fd/2:/dev/stderr \\
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
        \$BIND_OVERLAYS -0 /usr/bin/env TMPDIR=/tmp TEMP=/tmp PATH="\$PATH" \\
        JAVA_HOME="\$JAVA_HOME" ANDROID_HOME="\$ANDROID_HOME" ANDROID_SDK_ROOT="\$ANDROID_SDK_ROOT" \\
        FLUTTER_ALLOW_SU_ROOT=true GRADLE_OPTS="\$GRADLE_OPTS" _JAVA_OPTIONS="\$_JAVA_OPTIONS" \\
        /bin/bash --rcfile /root/.bashrc
fi
''';
  }

  Future<void> _bootstrapRootfs() async {
    _status = 'Downloading Ubuntu 24.04...';
    notifyListeners();

    final tmpDir = Directory(p.join(_filesDir, 'tmp'));
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);

    final archivePath = p.join(_filesDir, 'tmp', 'rootfs.tar.gz');
    await _dio.download(
      _rootfsUrl,
      archivePath,
      onReceiveProgress: (count, total) {
        if (total > 0) {
          _progress = count / total * 0.7;
          notifyListeners();
        }
      },
    );

    _status = 'Extracting system (Native)...';
    _progress = 0.7;
    notifyListeners();

    await _channel.invokeMethod('extractRootfs', {'tarPath': archivePath});

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
    return Platform.environment['HOME'] ?? Directory.current.path;
  }

  String get _detectedJavaHome {
    final jvmDir = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'lib', 'jvm'));
    if (jvmDir.existsSync()) {
      try {
        final entities = jvmDir.listSync();
        for (final entity in entities) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (name.startsWith('java-') && name.endsWith('-openjdk-arm64')) {
              return '/usr/lib/jvm/$name';
            }
          }
        }
      } catch (_) {}
    }
    // Check if jdk-17 exists inside rootfs root
    final rootJdk = Directory(p.join(_filesDir, 'rootfs', 'ubuntu', 'root', 'jdk-17'));
    if (rootJdk.existsSync()) {
      return '/root/jdk-17';
    }
    return '/usr/lib/jvm/java-17-openjdk-arm64';
  }

  String get _detectedAapt2 {
    final usrBinAapt2 = File(p.join(_filesDir, 'rootfs', 'ubuntu', 'usr', 'bin', 'aapt2'));
    if (usrBinAapt2.existsSync()) {
      return '/usr/bin/aapt2';
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
          return '/root/android-sdk/build-tools/${dirs.first}/aapt2';
        }
      }
    } catch (_) {}
    return '/usr/bin/aapt2';
  }

  Map<String, String> get env {
    // Desktop: pass through the real system environment
    if (!Platform.isAndroid && !Platform.isIOS) {
      return {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      };
    }
    // Android/iOS: use PRoot-specific environment
    return {
      'HOME': '/root',
      'TERM': 'xterm-256color',
      'ANDROID_HOME': '/root/android-sdk',
      'ANDROID_SDK_ROOT': '/root/android-sdk',
      'PATH':
          '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/android-sdk/cmdline-tools/latest/bin:/root/android-sdk/platform-tools:/root/flutter/bin',
      'JAVA_HOME': _detectedJavaHome,
      'FLUTTER_ROOT': '/root/flutter',
      'USER': 'root',
      'LANG': 'C.UTF-8',
      'FLUTTER_ALLOW_SU_ROOT': 'true',
      // Force IPv4 for Java/Gradle — Android PRoot routing of IPv6 sockets is broken
      '_JAVA_OPTIONS': '-Djava.net.preferIPv4Stack=true',
      'GRADLE_OPTS':
          '-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dandroid.aapt2.daemon=false -Dandroid.aapt2FromMaven=false -Dandroid.aapt2FromMavenOverride=$_detectedAapt2',
    };
  }

  Future<void> reset() async {
    _isInitialized = false;
    _status = 'Resetting...';
    _progress = 0;
    notifyListeners();

    try {
      final rootfs = Directory(p.join(_filesDir, 'rootfs'));
      if (await rootfs.exists()) await rootfs.delete(recursive: true);

      final tmp = Directory(p.join(_filesDir, 'tmp'));
      if (await tmp.exists()) await tmp.delete(recursive: true);

      _status = 'Cleaned. Ready for init.';
      notifyListeners();
    } catch (e) {
      _status = 'Error during reset: $e';
      notifyListeners();
    }
  }

  String _generateSetupArm64Script() {
    return r'''#!/bin/bash
# setup-arm64.sh - Automatically configure ARM64 environment inside QuantumIDE
# This script is called by init-host in the background.

# Prevent multiple instances of setup-arm64.sh running at once
LOCKFILE="/tmp/setup_daemon.lock"
if [ -f "$LOCKFILE" ]; then
    read -r last_pid < "$LOCKFILE"
    if [ -n "$last_pid" ] && kill -0 "$last_pid" 2>/dev/null; then
        echo "setup-arm64.sh is already running (PID: $last_pid). Exiting."
        exit 0
    fi
fi
echo "$$" > "$LOCKFILE"

# 1. SDK Toolchain Symlinking (Redirect x86_64 to native ARM64 tools)
SDK_ROOT="/root/android-sdk"
if [ -d "$SDK_ROOT" ]; then
    mkdir -p "$SDK_ROOT/platform-tools"
    [ ! -L "$SDK_ROOT/platform-tools/adb" ] && ln -sf /usr/bin/adb "$SDK_ROOT/platform-tools/adb"

    # Build tools
    for bt in "$SDK_ROOT/build-tools/"*; do
        if [ -d "$bt" ]; then
            [ ! -L "$bt/aapt" ] && ln -sf /usr/bin/aapt "$bt/aapt"
            [ ! -L "$bt/aapt2" ] && ln -sf /usr/bin/aapt2 "$bt/aapt2"
            [ ! -L "$bt/zipalign" ] && ln -sf /usr/bin/zipalign "$bt/zipalign"
            [ ! -L "$bt/apksigner" ] && ln -sf /usr/bin/apksigner "$bt/apksigner"
        fi
    done

    # CMake & Ninja
    for cm in "$SDK_ROOT/cmake/"*; do
        if [ -d "$cm/bin" ]; then
            [ ! -L "$cm/bin/cmake" ] && ln -sf /usr/bin/cmake "$cm/bin/cmake"
            [ ! -L "$cm/bin/ninja" ] && ln -sf /usr/bin/ninja "$cm/bin/ninja"
        fi
    done

    # NDK Clang/LLVM fixes
    # IMPORTANT: We use shell WRAPPER SCRIPTS, not symlinks.
    # Symlinks to ARM64 ELFs do not work for x86_64 ELF binaries.
    # The NDK ships x86_64 binaries; on ARM64 Android we must intercept
    # all calls and redirect them to the system ARM64 clang/llvm tools.
    for ndk in "$SDK_ROOT/ndk/"*; do
        if [ -d "$ndk" ]; then
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

# Patch build.gradle.kts and build.gradle inside app module to force compileSdk and targetSdk to 35
find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 5 \( -name "build.gradle.kts" -o -name "build.gradle" \) 2>/dev/null | while read f; do
    if [[ "$f" == *"/app/build.gradle"* ]]; then
        # Force compileSdk to 35 if it is set to flutter.compileSdkVersion or 36 or greater
        sed -i -E 's/compileSdk\s*=\s*(flutter\.compileSdkVersion|[3-9][6-9])/compileSdk = 35/g' "$f"
        sed -i -E 's/compileSdkVersion\s+(flutter\.compileSdkVersion|[3-9][6-9])/compileSdkVersion 35/g' "$f"
        sed -i -E 's/compileSdkVersion\s*=\s*(flutter\.compileSdkVersion|[3-9][6-9])/compileSdkVersion = 35/g' "$f"
        
        # Force targetSdk to 35 if it is set to flutter.targetSdkVersion or 36 or greater
        sed -i -E 's/targetSdk\s*=\s*(flutter\.targetSdkVersion|[3-9][6-9])/targetSdk = 35/g' "$f"
        sed -i -E 's/targetSdkVersion\s+(flutter\.targetSdkVersion|[3-9][6-9])/targetSdkVersion 35/g' "$f"
        sed -i -E 's/targetSdkVersion\s*=\s*(flutter\.targetSdkVersion|[3-9][6-9])/targetSdkVersion = 35/g' "$f"
    fi
done

# Upgrade aapt2 to a modern statically-linked arm64 binary if it is the old Debian package version.
# This prevents RES_TABLE_TYPE_TYPE resource table errors on compileSdk >= 35.
if [ -f /usr/bin/aapt2 ] && /usr/bin/aapt2 version 2>/dev/null | grep -q "debian"; then
    echo "Upgrading aapt2 to modern ARM64 binary..."
    mkdir -p /tmp/aapt2_download
    if curl -L -o /tmp/aapt2_download/aapt2 https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a; then
        chmod +x /tmp/aapt2_download/aapt2
        mv /tmp/aapt2_download/aapt2 /usr/bin/aapt2
        echo "aapt2 successfully upgraded."
    elif wget -O /tmp/aapt2_download/aapt2 https://github.com/ReVanced/aapt2/releases/download/v1.1.0/aapt2-arm64-v8a; then
        chmod +x /tmp/aapt2_download/aapt2
        mv /tmp/aapt2_download/aapt2 /usr/bin/aapt2
        echo "aapt2 successfully upgraded."
    else
        echo "Warning: Failed to download modern aapt2. Project builds using compileSdk >= 35 may fail."
    fi
    rm -rf /tmp/aapt2_download
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

# 7. Persistent background daemon to auto-heal AAPT2 / SDK toolchain binaries & patch newly created projects
(
  SDK_ROOT="/root/android-sdk"
  LOCKFILE="/tmp/setup_daemon_loop.lock"
  if [ -f "$LOCKFILE" ]; then
      read -r last_pid < "$LOCKFILE"
      if [ -n "$last_pid" ] && kill -0 "$last_pid" 2>/dev/null; then
          exit 0
      fi
  fi
  echo "$$" > "$LOCKFILE"

  while true; do
    # Symlink SDK build-tools to native tools on the fly
    if [ -d "$SDK_ROOT/build-tools" ]; then
        for bt in "$SDK_ROOT/build-tools/"*; do
            if [ -d "$bt" ]; then
                if [ -f "$bt/aapt2" ] && [ ! -L "$bt/aapt2" ]; then
                    rm -f "$bt/aapt2"
                    ln -sf /usr/bin/aapt2 "$bt/aapt2"
                fi
                if [ -f "$bt/aapt" ] && [ ! -L "$bt/aapt" ]; then
                    rm -f "$bt/aapt"
                    ln -sf /usr/bin/aapt "$bt/aapt"
                fi
                if [ -f "$bt/zipalign" ] && [ ! -L "$bt/zipalign" ]; then
                    rm -f "$bt/zipalign"
                    ln -sf /usr/bin/zipalign "$bt/zipalign"
                fi
                if [ -f "$bt/apksigner" ] && [ ! -L "$bt/apksigner" ]; then
                    rm -f "$bt/apksigner"
                    ln -sf /usr/bin/apksigner "$bt/apksigner"
                fi
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

    # Patch newly created projects' gradle.properties on the fly
    find "/root/projects" "/sdcard/QuantumIDE" -maxdepth 4 -name "gradle.properties" 2>/dev/null | while read -r f; do
        if ! grep -q "android.aapt2.daemon" "$f"; then
            echo "android.aapt2.daemon=false" >> "$f"
            echo "android.aapt2FromMaven=false" >> "$f"
            echo "android.aapt2FromMavenOverride=/usr/bin/aapt2" >> "$f"
            echo "org.gradle.daemon=false" >> "$f"
            echo "org.gradle.parallel=false" >> "$f"
            echo "org.gradle.workers.max=1" >> "$f"
        fi
    done

    # Patch Groovy build.gradle on the fly to force arm64-v8a abiFilters
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

    # Patch Kotlin build.gradle.kts on the fly to force arm64-v8a abiFilters
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

    sleep 300
  done
) >/dev/null 2>&1 &
''';
  }
}

final runtimeServiceProvider = ChangeNotifierProvider(
  (ref) => RuntimeService(),
);
