import 'dart:io';
import 'dart:math' as math;

/// Target architectures and build formats for Android/Flutter builds.
enum BuildTargetType {
  arm64, // APK ARM64-v8a (64-bit) — Fastest, modern phones/tablets
  arm32, // APK ARMeabi-v7a (32-bit) — Legacy 32-bit phones
  x86_64, // APK x86_64 — PC Android emulators
  split, // Split APKs per ABI (separate APK files)
  aab, // Android App Bundle (Google Play Store)
  debug, // Debug APK (ARM64)
}

/// Performance tuning profile for Gradle and Dart compilation.
enum BuildPerformanceMode {
  turbo, // Maximum safe utilization of CPU cores & RAM
  balanced, // Recommended auto-balance: fast compilation without risking OOM
  safe, // Minimal resource consumption (low battery/memory)
}

/// Dynamic system hardware info and optimal resource configuration.
class SystemHardwareProfile {
  final int cpuCores;
  final int totalRamMb;
  final int availableRamMb;

  const SystemHardwareProfile({
    required this.cpuCores,
    required this.totalRamMb,
    required this.availableRamMb,
  });

  @override
  String toString() =>
      'CPU: $cpuCores cores, RAM: ${availableRamMb}MB avail / ${totalRamMb}MB total';
}

/// Resource calculation result for a build session.
class BuildResourceConfig {
  final int workers;
  final int jvmHeapMb;
  final int jvmMetaspaceMb;
  final int dartHeapMb;
  final bool parallel;

  const BuildResourceConfig({
    required this.workers,
    required this.jvmHeapMb,
    required this.jvmMetaspaceMb,
    required this.dartHeapMb,
    required this.parallel,
  });
}

/// Service that detects device hardware resources (CPU cores, RAM)
/// and provides adaptive auto-tuning for Flutter & Gradle builds.
class BuildResourceOptimizer {
  const BuildResourceOptimizer._();

  /// Detects real hardware resources from system files or Dart Platform API.
  static SystemHardwareProfile detectHardware() {
    final cores = Platform.numberOfProcessors;
    int totalRamMb = 4096;
    int availRamMb = 2048;

    try {
      final meminfo = File('/proc/meminfo');
      if (meminfo.existsSync()) {
        final lines = meminfo.readAsLinesSync();
        for (final line in lines) {
          if (line.startsWith('MemTotal:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]) ?? 0;
              if (kb > 0) totalRamMb = kb ~/ 1024;
            }
          } else if (line.startsWith('MemAvailable:')) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              final kb = int.tryParse(parts[1]) ?? 0;
              if (kb > 0) availRamMb = kb ~/ 1024;
            }
          }
        }
      }
    } catch (_) {
      // Fallback defaults on non-proc systems
    }

    return SystemHardwareProfile(
      cpuCores: math.max(1, cores),
      totalRamMb: totalRamMb,
      availableRamMb: availRamMb,
    );
  }

  /// Calculates optimal Gradle workers, JVM heap, and Dart heap for a given profile.
  static BuildResourceConfig computeResourceConfig({
    SystemHardwareProfile? hardware,
    BuildPerformanceMode mode = BuildPerformanceMode.balanced,
  }) {
    final hw = hardware ?? detectHardware();
    final cores = hw.cpuCores;
    final ram = hw.availableRamMb;

    int workers = 2;
    int jvmHeap = 1792;
    int jvmMeta = 448;
    int dartHeap = 1024;
    bool parallel = true;

    switch (mode) {
      case BuildPerformanceMode.turbo:
        // Turbo mode: utilize 50-75% of CPU cores if RAM permits
        if (ram >= 6000) {
          jvmHeap = 3072;
          jvmMeta = 640;
          dartHeap = 1536;
          workers = math.min(cores, 6);
        } else if (ram >= 3200) {
          jvmHeap = 2304;
          jvmMeta = 512;
          dartHeap = 1280;
          workers = math.min(cores, 4);
        } else if (ram >= 2000) {
          jvmHeap = 1792;
          jvmMeta = 448;
          dartHeap = 1024;
          workers = math.min(cores, 3);
        } else {
          jvmHeap = 1280;
          jvmMeta = 384;
          dartHeap = 768;
          workers = math.min(cores, 2);
        }
        break;

      case BuildPerformanceMode.balanced:
        // Balanced: optimal compilation speed without risking Android LMK
        if (ram >= 6000) {
          jvmHeap = 2560;
          jvmMeta = 512;
          dartHeap = 1280;
          workers = cores >= 8 ? 4 : math.min(cores, 3);
        } else if (ram >= 3200) {
          jvmHeap = 2048;
          jvmMeta = 512;
          dartHeap = 1024;
          workers = cores >= 8 ? 4 : (cores >= 6 ? 4 : math.min(cores, 3));
        } else if (ram >= 2000) {
          jvmHeap = 1600;
          jvmMeta = 448;
          dartHeap = 896;
          workers = math.min(cores, 2);
        } else if (ram >= 1400) {
          jvmHeap = 1280;
          jvmMeta = 384;
          dartHeap = 768;
          workers = 2;
          parallel = false;
        } else {
          jvmHeap = 1024;
          jvmMeta = 320;
          dartHeap = 640;
          workers = 1;
          parallel = false;
        }
        break;

      case BuildPerformanceMode.safe:
        // Safe mode: low memory & battery saver
        jvmHeap = math.min(1536, (ram * 0.4).toInt());
        jvmHeap = math.max(1024, jvmHeap);
        jvmMeta = 384;
        dartHeap = 768;
        workers = math.min(cores, 2);
        parallel = ram >= 2500;
        break;
    }

    return BuildResourceConfig(
      workers: math.max(1, workers),
      jvmHeapMb: jvmHeap,
      jvmMetaspaceMb: jvmMeta,
      dartHeapMb: dartHeap,
      parallel: parallel,
    );
  }

  /// Generates the complete terminal command for building the selected target.
  static String generateBuildCommand({
    required BuildTargetType target,
    BuildPerformanceMode mode = BuildPerformanceMode.balanced,
    int? customWorkers,
  }) {
    final config = computeResourceConfig(mode: mode);
    final workers = customWorkers ?? config.workers;

    const checkSdk =
        '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\\\.1[3-9].*/sdk: \\\\x27>=3.12.0 <4.0.0\\\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true)';

    final workerFlag = '-Porg.gradle.workers.max=$workers';

    switch (target) {
      case BuildTargetType.arm64:
        return '$checkSdk && flutter build apk --release --no-pub --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation $workerFlag && (cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./app-release.apk 2>/dev/null || true) && echo "✓ Release APK (ARM64 64-бит): ./app-release.apk"';

      case BuildTargetType.arm32:
        return '$checkSdk && flutter build apk --release --no-pub --target-platform android-arm --no-tree-shake-icons --android-skip-build-dependency-validation $workerFlag && (cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ./app-release-armv7.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-release.apk ./app-release-armv7.apk 2>/dev/null || true) && echo "✓ Release APK (ARMv7 32-бит): ./app-release-armv7.apk"';

      case BuildTargetType.x86_64:
        return '$checkSdk && flutter build apk --release --no-pub --target-platform android-x64 --no-tree-shake-icons --android-skip-build-dependency-validation $workerFlag && (cp build/app/outputs/flutter-apk/app-x86_64-release.apk ./app-release-x64.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-release.apk ./app-release-x64.apk 2>/dev/null || true) && echo "✓ Release APK (x86_64): ./app-release-x64.apk"';

      case BuildTargetType.split:
        return '$checkSdk && flutter build apk --release --no-pub --split-per-abi --no-tree-shake-icons --android-skip-build-dependency-validation $workerFlag && (for apk in build/app/outputs/flutter-apk/*.apk; do cp -f "\$apk" ./ 2>/dev/null; done) && echo "✓ Split APKs (arm64, armv7, x86_64) готовы в корне проекта"';

      case BuildTargetType.aab:
        return '$checkSdk && flutter build appbundle --release --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation $workerFlag && (cp -f build/app/outputs/bundle/release/app-release.aab ./app-release.aab 2>/dev/null || true) && echo "✓ Google Play Bundle (AAB): ./app-release.aab"';

      case BuildTargetType.debug:
        return '$checkSdk && flutter build apk --debug --no-pub --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation $workerFlag && (cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK (ARM64): ./app-debug.apk"';
    }
  }

  /// Short display title for terminal / UI buttons.
  static String getDisplayCommand(BuildTargetType target) {
    switch (target) {
      case BuildTargetType.arm64:
        return 'flutter build apk --release --target-platform android-arm64';
      case BuildTargetType.arm32:
        return 'flutter build apk --release --target-platform android-arm';
      case BuildTargetType.x86_64:
        return 'flutter build apk --release --target-platform android-x64';
      case BuildTargetType.split:
        return 'flutter build apk --release --split-per-abi';
      case BuildTargetType.aab:
        return 'flutter build appbundle --release';
      case BuildTargetType.debug:
        return 'flutter build apk --debug';
    }
  }
}
