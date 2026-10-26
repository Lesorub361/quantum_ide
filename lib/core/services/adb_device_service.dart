import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/models/adb_device.dart';
import 'runtime_service.dart';

class AdbDeviceState {
  final bool isChecking;
  final bool isUsbHostSupported;
  final List<Map<String, dynamic>> rawUsbDevices;
  final List<AdbDevice> devices;
  final AdbDevice? selectedDevice;
  final String? lastError;
  final DateTime? lastChecked;

  const AdbDeviceState({
    this.isChecking = false,
    this.isUsbHostSupported = true,
    this.rawUsbDevices = const [],
    this.devices = const [],
    this.selectedDevice,
    this.lastError,
    this.lastChecked,
  });

  bool get hasConnectedDevice => selectedDevice != null && selectedDevice!.isOnline;
  bool get hasAnyDevices => devices.isNotEmpty;

  AdbDeviceState copyWith({
    bool? isChecking,
    bool? isUsbHostSupported,
    List<Map<String, dynamic>>? rawUsbDevices,
    List<AdbDevice>? devices,
    AdbDevice? selectedDevice,
    bool clearSelectedDevice = false,
    String? lastError,
    DateTime? lastChecked,
  }) {
    return AdbDeviceState(
      isChecking: isChecking ?? this.isChecking,
      isUsbHostSupported: isUsbHostSupported ?? this.isUsbHostSupported,
      rawUsbDevices: rawUsbDevices ?? this.rawUsbDevices,
      devices: devices ?? this.devices,
      selectedDevice: clearSelectedDevice ? null : (selectedDevice ?? this.selectedDevice),
      lastError: lastError,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

class AdbDeviceService extends StateNotifier<AdbDeviceState> {
  final Ref _ref;
  static const MethodChannel _nativeChannel = MethodChannel('com.example.quantum_ide/native');
  Timer? _pollingTimer;

  AdbDeviceService(this._ref) : super(const AdbDeviceState()) {
    init();
  }

  Future<void> init() async {
    await checkUsbHostSupport();
    await refreshDevices();
  }

  void startPolling({Duration interval = const Duration(seconds: 4)}) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => refreshDevices(silent: true));
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  /// Checks whether this device supports USB Host mode (OTG) and lists attached USB devices
  Future<void> checkUsbHostSupport({bool autoRequestPermission = true}) async {
    if (!Platform.isAndroid) {
      final usbDir = Directory('/dev/bus/usb');
      final supported = await usbDir.exists();
      state = state.copyWith(isUsbHostSupported: supported);
      return;
    }

    try {
      final bool? isSupported = await _nativeChannel.invokeMethod<bool>('isUsbHostSupported');
      final List<dynamic>? rawDevices = await _nativeChannel.invokeMethod<List<dynamic>>(
        'getConnectedUsbDevices',
        {'autoRequestPermission': autoRequestPermission},
      );

      final List<Map<String, dynamic>> parsedList = [];
      if (rawDevices != null) {
        for (final item in rawDevices) {
          if (item is Map) {
            parsedList.add(Map<String, dynamic>.from(item));
          }
        }
      }

      state = state.copyWith(
        isUsbHostSupported: isSupported ?? true,
        rawUsbDevices: parsedList,
      );
    } catch (e) {
      debugPrint('[AdbDeviceService] Error checking USB host: $e');
    }
  }

  /// Explicitly requests USB OTG permission and starts the native USB-to-ADB bridge
  Future<String> connectUsbOtg() async {
    if (!Platform.isAndroid) {
      await refreshDevices();
      return 'Проверка USB завершена';
    }
    try {
      final List<dynamic>? rawDevices = await _nativeChannel.invokeMethod<List<dynamic>>('connectUsbOtg');
      final List<Map<String, dynamic>> parsedList = [];
      if (rawDevices != null) {
        for (final item in rawDevices) {
          if (item is Map) {
            parsedList.add(Map<String, dynamic>.from(item));
          }
        }
      }
      state = state.copyWith(rawUsbDevices: parsedList);
      await refreshDevices();

      if (parsedList.isEmpty) {
        return 'Физические USB-устройства не обнаружены. Проверьте кабель Type-C и включите «Подключение OTG» в настройках.';
      }
      final adbCapable = parsedList.where((d) => d['hasAdbInterface'] == true).toList();
      if (adbCapable.isEmpty) {
        return 'Телефон подключен по USB, но «Отладка по USB» на втором телефоне выключена (режим только зарядки/MTP).';
      }
      final noPerm = adbCapable.where((d) => d['hasPermission'] != true).toList();
      if (noPerm.isNotEmpty) {
        return 'Подтвердите системное окно Android «Разрешить доступ к USB-устройству» и нажмите «Подключить USB» ещё раз.';
      }
      return 'USB-OTG мост активен! Подтвердите отладку (RSA-ключ) на экране второго телефона.';
    } catch (e) {
      return 'Ошибка USB OTG: $e';
    }
  }

  /// Refreshes ADB device list (`adb devices -l`)
  Future<void> refreshDevices({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isChecking: true, lastError: null);
    }

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      await checkUsbHostSupport(autoRequestPermission: !silent);

      // Ensure ADB server is running
      await runtime.runCommand('adb start-server 2>/dev/null || true');

      // Connect any active native USB-OTG bridges (e.g. 127.0.0.1:5556)
      for (final usbDev in state.rawUsbDevices) {
        final bridgeActive = usbDev['bridgeActive'] == true;
        final bridgeAddr = (usbDev['bridgeAddress'] ?? '').toString().trim();
        if (bridgeActive && bridgeAddr.isNotEmpty) {
          await runtime.runCommand('adb connect $bridgeAddr 2>/dev/null || true');
        }
      }

      final String output = await runtime.runCommand('adb devices -l').catchError((e) => '');
      final List<AdbDevice> parsed = [];

      final lines = output.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith('List of devices') ||
            trimmed.startsWith('* daemon')) {
          continue;
        }

        var device = AdbDevice.fromAdbLine(trimmed);
        if (device.id.isNotEmpty) {
          // Enrich USB-bridged device name from UsbManager metadata if model is not yet reported
          if (device.model.isEmpty) {
            final matchingUsb = state.rawUsbDevices.where((u) => u['bridgeAddress'] == device.id).toList();
            if (matchingUsb.isNotEmpty) {
              final mfg = (matchingUsb.first['manufacturer'] ?? '').toString().trim();
              final prod = (matchingUsb.first['product'] ?? '').toString().trim();
              final combined = '$mfg $prod'.trim();
              if (combined.isNotEmpty) {
                device = device.copyWith(model: combined);
              }
            }
          }
          parsed.add(device);
        }
      }

      // Check battery & android version for online devices in background
      final enriched = <AdbDevice>[];
      for (final dev in parsed) {
        if (dev.isOnline) {
          try {
            final versionOut = await runtime.runCommand('adb -s ${dev.id} shell getprop ro.build.version.release 2>/dev/null || true');
            final cleanVersion = versionOut.trim();
            final modelOut = dev.model.isEmpty
                ? (await runtime.runCommand('adb -s ${dev.id} shell getprop ro.product.model 2>/dev/null || true')).trim()
                : dev.model;
            final devWithVersion = dev.copyWith(
              model: modelOut.isNotEmpty ? modelOut : dev.model,
              androidVersion: cleanVersion.isNotEmpty ? 'Android $cleanVersion' : null,
            );
            enriched.add(devWithVersion);
          } catch (_) {
            enriched.add(dev);
          }
        } else {
          enriched.add(dev);
        }
      }

      AdbDevice? newSelected = state.selectedDevice;
      if (enriched.isNotEmpty) {
        // Keep current selected if still present, otherwise choose first online device
        final stillExists = enriched.any((d) => d.id == newSelected?.id);
        if (!stillExists) {
          newSelected = enriched.firstWhere(
            (d) => d.isOnline,
            orElse: () => enriched.first,
          );
        } else {
          newSelected = enriched.firstWhere((d) => d.id == newSelected?.id);
        }
      } else {
        newSelected = null;
      }

      state = state.copyWith(
        isChecking: false,
        devices: enriched,
        selectedDevice: newSelected,
        clearSelectedDevice: enriched.isEmpty,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        isChecking: false,
        lastError: e.toString(),
        lastChecked: DateTime.now(),
      );
    }
  }

  void selectDevice(AdbDevice? device) {
    state = state.copyWith(selectedDevice: device, clearSelectedDevice: device == null);
  }

  String _formatAdbError(String raw) {
    var clean = raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
    clean = clean.replaceFirst(RegExp(r'^Command failed \(exit code \d+\):\s*'), '');
    clean = clean.trim();

    if (clean.contains('protocol fault')) {
      return 'Сбой протокола ADB (protocol fault):\n'
          '1. Отключите VPN на телефоне (VPN на Android перехватывает локальный Wi-Fi трафик и ломает ADB сокеты).\n'
          '2. Для Android 11+ нужно сначала выполнить «2. Сопряжение по коду» (с кодом из 6 цифр).\n'
          '3. ADB сервер был автоматически перезапущен для восстановления.';
    }
    if (clean.contains('failed to connect') ||
        clean.contains('Connection refused') ||
        clean.contains('timed out') ||
        clean.contains('Connection reset')) {
      return 'Не удалось подключиться к $clean:\n'
          '1. Отключите VPN (VPN направляет трафик на удалённый сервер вместо локальной сети Wi-Fi).\n'
          '2. Убедитесь, что оба телефона в одной Wi-Fi сети (или раздайте Wi-Fi с одного телефона на другой).\n'
          '3. Проверьте, что на втором телефоне включен экран и активна «Беспроводная отладка» (порт мог измениться).';
    }
    return clean;
  }

  /// Connect to device via Wi-Fi ADB (e.g. `192.168.1.100:5555`)
  Future<String> connectWifi(String ipAndPort) async {
    final clean = ipAndPort.trim();
    if (clean.isEmpty) return 'Укажите IP и порт (например 192.168.1.15:5555)';

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb connect $clean 2>&1 || true');
      if (res.contains('connected to') || res.contains('already connected')) {
        await refreshDevices();
        return res.trim();
      }

      // Auto-heal on protocol fault or broken server
      if (res.contains('protocol fault') || res.contains('cannot connect') || res.contains('failed')) {
        await runtime.runCommand('adb kill-server 2>/dev/null; sleep 0.5; adb start-server 2>/dev/null || true');
        final retry = await runtime.runCommand('adb connect $clean 2>&1 || true');
        await refreshDevices();
        if (retry.contains('connected to') || retry.contains('already connected')) {
          return retry.trim();
        }
        return _formatAdbError(retry.trim().isNotEmpty ? retry : res);
      }
      await refreshDevices();
      return _formatAdbError(res.trim());
    } catch (e) {
      try {
        await runtime.runCommand('adb kill-server 2>/dev/null; sleep 0.5; adb start-server 2>/dev/null || true');
      } catch (_) {}
      return _formatAdbError(e.toString());
    }
  }

  /// Pair device via Wi-Fi ADB with pairing code (Android 11+)
  Future<String> pairWifi(String ipAndPort, String pairingCode) async {
    final cleanIp = ipAndPort.trim();
    final cleanCode = pairingCode.trim();
    if (cleanIp.isEmpty || cleanCode.isEmpty) {
      return 'Укажите IP:порт и код сопряжения (6 цифр)';
    }

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb pair $cleanIp $cleanCode 2>&1 || true');
      if (res.contains('Successfully paired') || res.contains('paired to')) {
        await refreshDevices();
        return '✅ Устройство успешно сопряжено! Теперь нажмите «Подключить» в блоке 1.';
      }
      if (res.contains('protocol fault') || res.contains('failed')) {
        await runtime.runCommand('adb kill-server 2>/dev/null; sleep 0.5; adb start-server 2>/dev/null || true');
        final retry = await runtime.runCommand('adb pair $cleanIp $cleanCode 2>&1 || true');
        await refreshDevices();
        if (retry.contains('Successfully paired') || retry.contains('paired to')) {
          return '✅ Устройство успешно сопряжено! Теперь нажмите «Подключить» в блоке 1.';
        }
        return _formatAdbError(retry.trim().isNotEmpty ? retry : res);
      }
      await refreshDevices();
      return _formatAdbError(res.trim());
    } catch (e) {
      try {
        await runtime.runCommand('adb kill-server 2>/dev/null; sleep 0.5; adb start-server 2>/dev/null || true');
      } catch (_) {}
      return _formatAdbError(e.toString());
    }
  }

  /// Disconnect Wi-Fi device
  Future<String> disconnectWifi(String target) async {
    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb disconnect $target 2>&1 || true');
      await refreshDevices();
      return res.trim();
    } catch (e) {
      return 'Ошибка: $e';
    }
  }

  /// Restarts ADB server
  Future<String> restartServer() async {
    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb kill-server 2>/dev/null; sleep 0.5; adb start-server 2>&1 || true');
      await refreshDevices();
      return res.trim().isNotEmpty ? res.trim() : 'ADB сервер успешно перезапущен';
    } catch (e) {
      return 'Ошибка перезапуска: $e';
    }
  }

  /// Installs APK to selected device and optionally starts the main activity
  Future<String> installAndRun({
    required String apkPath,
    String? packageName,
    String? activityName,
    String? deviceId,
  }) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) {
      return 'Целевое устройство не выбрано или не подключено';
    }

    final resolvedPkg = (packageName != null && packageName.isNotEmpty)
        ? packageName
        : await detectPackageNameForApk(apkPath);

    final runtime = _ref.read(runtimeServiceProvider);
    final cmd = StringBuffer('adb -s $targetId install -r "$apkPath"');
    if (resolvedPkg != null && resolvedPkg.isNotEmpty) {
      if (activityName != null && activityName.isNotEmpty) {
        cmd.write(' && adb -s $targetId shell am start -n "$resolvedPkg/$activityName"');
      } else {
        cmd.write(' && adb -s $targetId shell monkey -p "$resolvedPkg" -c android.intent.category.LAUNCHER 1');
      }
    }

    try {
      final output = await runtime.runCommand(cmd.toString());
      return output.trim();
    } catch (e) {
      return 'Ошибка установки: $e';
    }
  }

  /// Installs any compiled APK directly onto this phone (host device) via Android PackageInstaller
  Future<String> installApkOnHostPhone(String prootApkPath, {bool launchAfterInstall = true}) async {
    if (!Platform.isAndroid) {
      return 'Локальная установка APK поддерживается только на Android';
    }
    try {
      final filesDir = await _nativeChannel.invokeMethod<String>('getFilesDir') ??
          '/data/user/0/com.example.quantum_ide/files';
      String hostPath = prootApkPath;
      if (prootApkPath.startsWith('/root/projects/external/')) {
        hostPath = prootApkPath.replaceFirst('/root/projects/external/', '/storage/emulated/0/QuantumIDE/');
      } else if (prootApkPath.startsWith('/sdcard/')) {
        hostPath = prootApkPath.replaceFirst('/sdcard/', '/storage/emulated/0/');
      } else if (prootApkPath.startsWith('/root/projects/')) {
        hostPath = prootApkPath.replaceFirst('/root/projects/', '$filesDir/projects/');
      } else if (!prootApkPath.startsWith('/data/') && !prootApkPath.startsWith('/storage/')) {
        hostPath = '$filesDir/rootfs/ubuntu$prootApkPath';
      }

      await _nativeChannel.invokeMethod('installApk', {
        'apkPath': hostPath,
        'launchAfterInstall': launchAfterInstall,
      });
      return 'Запущен системный установщик Android для $prootApkPath';
    } catch (e) {
      return 'Ошибка локальной установки APK: $e';
    }
  }

  /// Finds all compiled .apk files in the current workspace and across `/root/projects/`
  Future<List<String>> findCompiledApks({String? workspacePath}) async {
    final results = <String>[];
    final seen = <String>{};

    void addIfExists(String path) {
      if (seen.contains(path)) return;
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 0) {
        seen.add(path);
        results.add(path);
      }
    }

    void scanProjectDir(String projectDir) {
      addIfExists('$projectDir/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk');
      addIfExists('$projectDir/build/app/outputs/flutter-apk/app-release.apk');
      addIfExists('$projectDir/build/app/outputs/flutter-apk/app-debug.apk');
      final flutterApkDir = Directory('$projectDir/build/app/outputs/flutter-apk');
      if (flutterApkDir.existsSync()) {
        try {
          for (final entity in flutterApkDir.listSync()) {
            if (entity is File && entity.path.endsWith('.apk')) {
              addIfExists(entity.path);
            }
          }
        } catch (_) {}
      }
      final gradleApkDir = Directory('$projectDir/app/build/outputs/apk');
      if (gradleApkDir.existsSync()) {
        try {
          for (final entity in gradleApkDir.listSync(recursive: true)) {
            if (entity is File && entity.path.endsWith('.apk')) {
              addIfExists(entity.path);
            }
          }
        } catch (_) {}
      }
    }

    if (workspacePath != null && workspacePath.isNotEmpty) {
      scanProjectDir(workspacePath);
    }

    final projectsRoot = Directory('/root/projects');
    if (projectsRoot.existsSync()) {
      try {
        for (final dir in projectsRoot.listSync()) {
          if (dir is Directory && !dir.path.endsWith('/external')) {
            scanProjectDir(dir.path);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  /// Automatically detects Android package name (applicationId) from a project or APK path
  Future<String?> detectPackageNameForApk(String apkOrProjectPath) async {
    String projectDir = apkOrProjectPath;
    final buildIdx = apkOrProjectPath.indexOf('/build/');
    if (buildIdx > 0) {
      projectDir = apkOrProjectPath.substring(0, buildIdx);
    } else {
      final appBuildIdx = apkOrProjectPath.indexOf('/app/build/');
      if (appBuildIdx > 0) {
        projectDir = apkOrProjectPath.substring(0, appBuildIdx);
      }
    }

    final candidates = [
      '$projectDir/android/app/build.gradle.kts',
      '$projectDir/android/app/build.gradle',
      '$projectDir/app/build.gradle.kts',
      '$projectDir/app/build.gradle',
    ];

    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) {
        try {
          final content = await f.readAsString();
          final match = RegExp(r'''applicationId\s*=?\s*["']([a-zA-Z0-9_.]+)["']''').firstMatch(content);
          if (match != null) return match.group(1);
        } catch (_) {}
      }
    }

    final manifests = [
      '$projectDir/android/app/src/main/AndroidManifest.xml',
      '$projectDir/app/src/main/AndroidManifest.xml',
    ];
    for (final path in manifests) {
      final f = File(path);
      if (f.existsSync()) {
        try {
          final content = await f.readAsString();
          final match = RegExp(r'''package\s*=\s*["']([a-zA-Z0-9_.]+)["']''').firstMatch(content);
          if (match != null) return match.group(1);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Takes screenshot from target device and copies it to local workspace
  Future<String> takeScreenshot({String? localDestPath, String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) throw Exception('Целевой телефон не подключен');

    final runtime = _ref.read(runtimeServiceProvider);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dest = localDestPath ?? '/root/projects/quantum_ide/scratch/screenshot_$timestamp.png';
    await File(dest).parent.create(recursive: true);

    final cmd = 'adb -s $targetId shell screencap -p /sdcard/quantum_screen.png && adb -s $targetId pull /sdcard/quantum_screen.png "$dest" && adb -s $targetId shell rm -f /sdcard/quantum_screen.png';
    await runtime.runCommand(cmd);

    if (!await File(dest).exists()) {
      throw Exception('Не удалось сохранить скриншот с устройства');
    }
    return dest;
  }

  /// Dumps UIAutomator XML from target device
  Future<String> dumpUiHierarchy({String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) throw Exception('Целевой телефон не подключен');

    final runtime = _ref.read(runtimeServiceProvider);
    final localPath = '/tmp/quantum_window_dump_${DateTime.now().millisecondsSinceEpoch}.xml';

    final cmd = 'adb -s $targetId shell uiautomator dump /sdcard/quantum_ui.xml && adb -s $targetId pull /sdcard/quantum_ui.xml "$localPath" && adb -s $targetId shell rm -f /sdcard/quantum_ui.xml';
    await runtime.runCommand(cmd);

    final f = File(localPath);
    if (await f.exists()) {
      final content = await f.readAsString();
      await f.delete().catchError((_) => f);
      return content;
    }
    throw Exception('Не удалось извлечь иерархию интерфейса (UI hierarchy)');
  }

  /// Sends tap at coordinate (x, y) on target device
  Future<void> sendTap(int x, int y, {String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) throw Exception('Целевой телефон не подключен');
    final runtime = _ref.read(runtimeServiceProvider);
    await runtime.runCommand('adb -s $targetId shell input tap $x $y');
  }

  /// Sends text to target device
  Future<void> sendText(String text, {String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) throw Exception('Целевой телефон не подключен');
    final runtime = _ref.read(runtimeServiceProvider);
    // Sanitize text for shell input
    final escaped = text.replaceAll(' ', '%s').replaceAll("'", "\\'");
    await runtime.runCommand("adb -s $targetId shell input text '$escaped'");
  }

  /// Sends swipe gesture
  Future<void> sendSwipe(int x1, int y1, int x2, int y2, {int durationMs = 300, String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) throw Exception('Целевой телефон не подключен');
    final runtime = _ref.read(runtimeServiceProvider);
    await runtime.runCommand('adb -s $targetId shell input swipe $x1 $y1 $x2 $y2 $durationMs');
  }

  /// Sends keyevent (e.g. 4 for Back, 3 for Home, 66 for Enter)
  Future<void> sendKeyEvent(int keyCode, {String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) throw Exception('Целевой телефон не подключен');
    final runtime = _ref.read(runtimeServiceProvider);
    await runtime.runCommand('adb -s $targetId shell input keyevent $keyCode');
  }

  /// Fetches recent error/crash logcat entries
  Future<String> getLogcatErrors({int lines = 80, String? deviceId}) async {
    final targetId = deviceId ?? state.selectedDevice?.id;
    if (targetId == null) return 'Телефон не подключен';
    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final out = await runtime.runCommand('adb -s $targetId logcat -d -t $lines *:E');
      return out.trim();
    } catch (e) {
      return 'Ошибка получения логов: $e';
    }
  }
}

final adbDeviceServiceProvider = StateNotifierProvider<AdbDeviceService, AdbDeviceState>((ref) {
  return AdbDeviceService(ref);
});
