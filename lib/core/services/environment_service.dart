import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/providers/locale_provider.dart';
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
    final l10n = _ref.read(localizationsProvider);

    final tools = <ToolStatus>[];

    tools.add(await _checkTool(runtime, 'dart', '--version'));
    tools.add(await _checkTool(runtime, 'git', '--version'));
    tools.add(await _checkTool(runtime, 'flutter', '--version'));
    tools.add(await _checkTool(runtime, 'adb', '--version'));
    tools.add(await _checkTool(runtime, 'clang', '--version'));
    tools.add(await _checkTool(runtime, 'cmake', '--version'));
    tools.add(await _checkTool(runtime, 'ninja', '--version'));

    // Check Android SDK platform health
    tools.add(await _checkAndroidSdkHealth(runtime, l10n));

    if (Platform.isAndroid) {
      tools.add(ToolStatus(
        name: l10n.phantomProcessesTitle,
        isInstalled: false,
        version: l10n.phantomProcessesVersion,
        error: l10n.phantomProcessesError,
      ));
    }

    state = state.copyWith(tools: tools, isChecking: false);
  }

  /// Проверяет целостность android.jar для android-36 и android-35.
  Future<ToolStatus> _checkAndroidSdkHealth(RuntimeService runtime, AppLocalizations l10n) async {
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
            error: l10n.androidJarCorruptError(api),
          );
        }
      }

      return ToolStatus(
        name: 'Android SDK platforms',
        isInstalled: true,
        version: l10n.androidSdkPlatformsHealthy,
      );
    } catch (e) {
      return ToolStatus(
        name: 'Android SDK platforms',
        isInstalled: false,
        error: l10n.checkFailed(e.toString()),
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
        'mkdir -p /root/android-sdk/licenses && '
        'printf "24333f8a63b6825ea9c5514f83c2829b004d1fee\\nd56f5187479451eabf01fb78af6dfcb131a6481e\\n2fa2d150aa0a1204d10e5ed57ab8369e7b50077c\\n" > /root/android-sdk/licenses/android-sdk-license && '
        'printf "84831b9409646a918e30573bab4c9c91346d8abd\\n" > /root/android-sdk/licenses/android-sdk-preview-license && '
        'printf "859f317696f67ef3d7f30a50a5560e7834b43903\\n" > /root/android-sdk/licenses/android-sdk-arm-dbt-license && '
        'printf "601085b94cd77f0b54ff86406957099ebe79c4d6\\n" > /root/android-sdk/licenses/android-googletv-license && '
        'printf "ceff83576aac4f7f37cb98fe189e9fb3c49d3b81\\n" > /root/android-sdk/licenses/android-googlexr-license && '
        'printf "33b6a2b64607f11b759f320ef9dff4ae5c47d97a\\n" > /root/android-sdk/licenses/google-gdk-license && '
        'printf "3a7848b1d7366ca5cfa0be477627644ca73f47e3\\n" > /root/android-sdk/licenses/microxr-sysimage-license && '
        'printf "e9acab5b5fbb560a72cfaecce8946896ff6aab9d\\n" > /root/android-sdk/licenses/mips-android-sysimage-license && '
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
