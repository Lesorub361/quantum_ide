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
  Future<void> checkUsbHostSupport() async {
    if (!Platform.isAndroid) {
      final usbDir = Directory('/dev/bus/usb');
      final supported = await usbDir.exists();
      state = state.copyWith(isUsbHostSupported: supported);
      return;
    }

    try {
      final bool? isSupported = await _nativeChannel.invokeMethod<bool>('isUsbHostSupported');
      final List<dynamic>? rawDevices = await _nativeChannel.invokeMethod<List<dynamic>>('getConnectedUsbDevices');

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

  /// Refreshes ADB device list (`adb devices -l`)
  Future<void> refreshDevices({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isChecking: true, lastError: null);
    }

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      // Ensure ADB server is running
      await runtime.runCommand('adb start-server 2>/dev/null || true');

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

        final device = AdbDevice.fromAdbLine(trimmed);
        if (device.id.isNotEmpty) {
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
            final devWithVersion = dev.copyWith(
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

      await checkUsbHostSupport();

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

  /// Connect to device via Wi-Fi ADB (e.g. `192.168.1.100:5555`)
  Future<String> connectWifi(String ipAndPort) async {
    final clean = ipAndPort.trim();
    if (clean.isEmpty) return 'Укажите IP и порт (например 192.168.1.15:5555)';

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb connect $clean');
      await refreshDevices();
      return res.trim();
    } catch (e) {
      return 'Ошибка подключения: $e';
    }
  }

  /// Pair device via Wi-Fi ADB with pairing code (Android 11+)
  Future<String> pairWifi(String ipAndPort, String pairingCode) async {
    final cleanIp = ipAndPort.trim();
    final cleanCode = pairingCode.trim();
    if (cleanIp.isEmpty || cleanCode.isEmpty) {
      return 'Укажите IP:порт и код сопряжения';
    }

    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb pair $cleanIp $cleanCode');
      await refreshDevices();
      return res.trim();
    } catch (e) {
      return 'Ошибка сопряжения: $e';
    }
  }

  /// Disconnect Wi-Fi device
  Future<String> disconnectWifi(String target) async {
    final runtime = _ref.read(runtimeServiceProvider);
    try {
      final res = await runtime.runCommand('adb disconnect $target');
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
      final res = await runtime.runCommand('adb kill-server && adb start-server');
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

    final runtime = _ref.read(runtimeServiceProvider);
    final cmd = StringBuffer('adb -s $targetId install -r "$apkPath"');
    if (packageName != null && packageName.isNotEmpty) {
      if (activityName != null && activityName.isNotEmpty) {
        cmd.write(' && adb -s $targetId shell am start -n "$packageName/$activityName"');
      } else {
        cmd.write(' && adb -s $targetId shell monkey -p "$packageName" -c android.intent.category.LAUNCHER 1');
      }
    }

    try {
      final output = await runtime.runCommand(cmd.toString());
      return output.trim();
    } catch (e) {
      return 'Ошибка установки: $e';
    }
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
