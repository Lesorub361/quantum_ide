import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'runtime_service.dart';

class ToolStatus {
  final String name;
  final bool isInstalled;
  final String? version;
  final String? error;

  ToolStatus({
    required this.name,
    required this.isInstalled,
    this.version,
    this.error,
  });
}

class EnvironmentState {
  final List<ToolStatus> tools;
  final bool isChecking;

  EnvironmentState({this.tools = const [], this.isChecking = false});

  EnvironmentState copyWith({List<ToolStatus>? tools, bool? isChecking}) {
    return EnvironmentState(
      tools: tools ?? this.tools,
      isChecking: isChecking ?? this.isChecking,
    );
  }
}

class EnvironmentService extends StateNotifier<EnvironmentState> {
  final Ref _ref;
  EnvironmentService(this._ref) : super(EnvironmentState()) {
    checkEnvironment();
  }

  Future<void> checkEnvironment() async {
    final runtime = _ref.read(runtimeServiceProvider);
    if (!runtime.isInitialized) {
      return;
    }

    state = state.copyWith(isChecking: true);

    final tools = <ToolStatus>[];

    tools.add(await _checkTool(runtime, 'dart', '--version'));
    tools.add(await _checkTool(runtime, 'git', '--version'));
    tools.add(await _checkTool(runtime, 'flutter', '--version'));
    tools.add(await _checkTool(runtime, 'adb', '--version'));
    tools.add(await _checkTool(runtime, 'clang', '--version'));
    tools.add(await _checkTool(runtime, 'cmake', '--version'));
    tools.add(await _checkTool(runtime, 'ninja', '--version'));

    // Check Android SDK platform health
    tools.add(await _checkAndroidSdkHealth(runtime));

    if (Platform.isAndroid) {
      tools.add(ToolStatus(
        name: 'Фантомные процессы (Android 12/13+)',
        isInstalled: false,
        version: 'Требуется ADB-настройка для стабильной компиляции',
        error:
            'В Android 12+ системный убийца процессов (Phantom Process Killer) принудительно убивает сборки (Gradle/Java/Node/Dart), если лимит превышает 32 активных процесса.\n\nДля отключения выполните через ADB на ПК:\n\nadb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"\n\nadb shell "/system/bin/settings put global settings_enable_monitor_phantom_procs false"',
      ));
    }

    state = state.copyWith(tools: tools, isChecking: false);
  }

  /// Проверяет целостность android.jar для android-36 и android-35.
  Future<ToolStatus> _checkAndroidSdkHealth(RuntimeService runtime) async {
    try {
      // Проверяем android-36 сначала, потом android-35
      for (final api in ['android-36', 'android-35']) {
        final jarPath = '/root/android-sdk/platforms/$api/android.jar';
        // Используем unzip -t для проверки целостности jar (более надёжно чем python)
        final result = await runtime.runCommand(
          'unzip -t $jarPath > /dev/null 2>&1 && echo "OK $api" || echo "CORRUPT $api"',
        ).catchError((_) => 'CORRUPT $api');

        if (result.contains('CORRUPT')) {
          return ToolStatus(
            name: 'Android SDK ($api)',
            isInstalled: false,
            error:
                'android.jar повреждён ($api). Нажмите «Исправить окружение» для переустановки.',
          );
        }
      }

      return ToolStatus(
        name: 'Android SDK platforms',
        isInstalled: true,
        version: 'android-35 / android-36 — исправны',
      );
    } catch (e) {
      return ToolStatus(
        name: 'Android SDK platforms',
        isInstalled: false,
        error: 'Проверка не удалась: $e',
      );
    }
  }

  Future<void> fixEnvironment() async {
    final runtime = _ref.read(runtimeServiceProvider);
    if (!runtime.isInitialized) return;

    state = state.copyWith(isChecking: true);

    try {
      // 1. Установить необходимые пакеты
      await runtime.runCommand(
        'apt-get update && apt-get install -y '
        'adb aapt zipalign apksigner clang lld cmake ninja-build '
        'pkg-config libgtk-3-dev openjdk-21-jdk python3 curl wget unzip',
      );

      // 2. Запустить скрипт настройки ARM64
      await runtime.runCommand('/bin/bash /root/setup-arm64.sh');

      // 3. Починить повреждённые платформы Android SDK
      await fixAndroidSdk(runtime: runtime);

      await checkEnvironment();
    } catch (e) {
      debugPrint('Failed to fix environment: $e');
    } finally {
      state = state.copyWith(isChecking: false);
    }
  }

  /// Удаляет повреждённые платформы Android SDK и переустанавливает их.
  Future<void> fixAndroidSdk({RuntimeService? runtime}) async {
    final rt = runtime ?? _ref.read(runtimeServiceProvider);
    if (rt == null || !rt.isInitialized) return;

    debugPrint('[EnvironmentService] Reinstalling Android SDK platforms...');
    try {
      // 1. Удалить ОБЕ повреждённые платформы
      await rt.runCommand(
        'rm -rf /root/android-sdk/platforms/android-35 '
        '/root/android-sdk/platforms/android-36 2>/dev/null || true',
      );

      // 2. Принять лицензии и переустановить android-35 и android-36
      await rt.runCommand(
        'yes | sdkmanager --licenses > /dev/null 2>&1 || true && '
        'sdkmanager --install "platforms;android-35" "platforms;android-36" 2>&1 | tail -10',
      );

      debugPrint('[EnvironmentService] Android SDK platforms reinstalled.');
    } catch (e) {
      debugPrint('[EnvironmentService] fixAndroidSdk failed: $e');
    }
  }

  Future<ToolStatus> _checkTool(
    RuntimeService runtime,
    String name,
    String versionArgs,
  ) async {
    try {
      final result =
          await runtime.runCommand('$name $versionArgs').catchError((e) => '');
      if (result.isNotEmpty) {
        return ToolStatus(
          name: name,
          isInstalled: true,
          version: result.split('\n').first.trim(),
        );
      } else {
        return ToolStatus(
          name: name,
          isInstalled: false,
          error: 'Not found in PRoot',
        );
      }
    } catch (e) {
      return ToolStatus(
        name: name,
        isInstalled: false,
        error: 'Not installed',
      );
    }
  }
}

final environmentProvider =
    StateNotifierProvider<EnvironmentService, EnvironmentState>((ref) {
  // Use ref.listen to react to runtime changes without re-creating the service
  final service = EnvironmentService(ref);

  ref.listen<RuntimeService>(runtimeServiceProvider, (previous, next) {
    if (next.isInitialized && (previous == null || !previous.isInitialized)) {
      service.checkEnvironment();
    }
  }, fireImmediately: true);

  return service;
});
