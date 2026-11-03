import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SystemMetrics {
  final double ramUsedGb;
  final double ramTotalGb;
  final double ramUsagePercent;
  final double cpuLoad1m;
  final int cpuCores;
  final double diskFreeGb;
  final double diskTotalGb;
  final int batteryLevel;
  final bool isCharging;
  final String deviceModel;
  final String androidVersion;
  final String socInfo;

  const SystemMetrics({
    this.ramUsedGb = 0.0,
    this.ramTotalGb = 0.0,
    this.ramUsagePercent = 0.0,
    this.cpuLoad1m = 0.0,
    this.cpuCores = 1,
    this.diskFreeGb = 0.0,
    this.diskTotalGb = 0.0,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.deviceModel = 'Android Device',
    this.androidVersion = '',
    this.socInfo = '',
  });
}

class SystemMonitorService extends ChangeNotifier {
  final Battery _battery = Battery();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  SystemMetrics _metrics = const SystemMetrics();
  SystemMetrics get metrics => _metrics;

  Timer? _timer;
  String _cachedModel = '';
  String _cachedAndroidVer = '';
  String _cachedSoc = '';
  bool _initializedStatic = false;

  DateTime? _lastDiskCheck;
  DateTime? _lastBatteryCheck;
  double _cachedDiskFree = 0.0;
  double _cachedDiskTotal = 0.0;
  int _cachedBatteryLevel = 100;
  bool _cachedIsCharging = false;

  SystemMonitorService() {
    _initStaticInfo();
    _updateMetrics();
    // 15-second interval instead of 3s to minimize battery usage and CPU wakeups
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _updateMetrics());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initStaticInfo() async {
    if (_initializedStatic) return;
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        _cachedModel = '${info.manufacturer} ${info.model}';
        _cachedAndroidVer = 'Android ${info.version.release} (API ${info.version.sdkInt})';
        _cachedSoc = info.hardware;
      } else {
        _cachedModel = Platform.operatingSystem;
        _cachedAndroidVer = Platform.operatingSystemVersion;
      }
      _initializedStatic = true;
    } catch (_) {
      _cachedModel = 'Android Device';
    }
  }

  Future<void> _updateMetrics() async {
    double ramUsed = 0.0;
    double ramTotal = 0.0;
    double ramPercent = 0.0;
    double cpuLoad = 0.0;
    int cpuCores = Platform.numberOfProcessors;
    double diskFree = 0.0;
    double diskTotal = 0.0;
    int batteryLevel = 100;
    bool isCharging = false;

    // 1. RAM via /proc/meminfo
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        final memFile = File('/proc/meminfo');
        if (await memFile.exists()) {
          final lines = await memFile.readAsLines();
          double totalKb = 0;
          double availKb = 0;
          for (final line in lines) {
            if (line.startsWith('MemTotal:')) {
              totalKb = _parseMemKb(line);
            } else if (line.startsWith('MemAvailable:')) {
              availKb = _parseMemKb(line);
            }
          }
          if (totalKb > 0) {
            ramTotal = totalKb / (1024 * 1024);
            final usedKb = totalKb - availKb;
            ramUsed = usedKb / (1024 * 1024);
            ramPercent = (usedKb / totalKb) * 100;
          }
        }
      }
    } catch (_) {}

    // 2. CPU load via /proc/loadavg
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        final loadFile = File('/proc/loadavg');
        if (await loadFile.exists()) {
          final text = await loadFile.readAsString();
          final parts = text.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) {
            cpuLoad = double.tryParse(parts[0]) ?? 0.0;
          }
        }
      }
    } catch (_) {}

    // 3. Disk space via df (cached for 60 seconds to avoid spawning processes every tick)
    final now = DateTime.now();
    if (_lastDiskCheck == null || now.difference(_lastDiskCheck!) > const Duration(seconds: 60)) {
      try {
        if (Platform.isAndroid || Platform.isLinux) {
          final result = await Process.run('df', ['-k', '/data']).timeout(const Duration(seconds: 2));
          if (result.exitCode == 0) {
            final lines = (result.stdout as String).trim().split('\n');
            if (lines.length > 1) {
              final cols = lines[1].trim().split(RegExp(r'\s+'));
              if (cols.length >= 4) {
                final totalK = double.tryParse(cols[1]) ?? 0;
                final availK = double.tryParse(cols[3]) ?? 0;
                _cachedDiskTotal = totalK / (1024 * 1024);
                _cachedDiskFree = availK / (1024 * 1024);
                _lastDiskCheck = now;
              }
            }
          }
        }
      } catch (_) {}
    }
    diskTotal = _cachedDiskTotal;
    diskFree = _cachedDiskFree;

    // 4. Battery (cached for 30 seconds to minimize Platform Channel / JNI invocations)
    if (_lastBatteryCheck == null || now.difference(_lastBatteryCheck!) > const Duration(seconds: 30)) {
      try {
        _cachedBatteryLevel = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        _cachedIsCharging = state == BatteryState.charging || state == BatteryState.full;
        _lastBatteryCheck = now;
      } catch (_) {}
    }
    batteryLevel = _cachedBatteryLevel;
    isCharging = _cachedIsCharging;

    final newMetrics = SystemMetrics(
      ramUsedGb: ramUsed,
      ramTotalGb: ramTotal,
      ramUsagePercent: ramPercent,
      cpuLoad1m: cpuLoad,
      cpuCores: cpuCores,
      diskFreeGb: diskFree,
      diskTotalGb: diskTotal,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      deviceModel: _cachedModel.isNotEmpty ? _cachedModel : 'Android Device',
      androidVersion: _cachedAndroidVer,
      socInfo: _cachedSoc,
    );

    // Only notify if meaningful change occurred
    final shouldNotify = (_metrics.ramUsagePercent - ramPercent).abs() > 0.5 ||
        (_metrics.cpuLoad1m - cpuLoad).abs() > 0.1 ||
        _metrics.batteryLevel != batteryLevel ||
        _metrics.isCharging != isCharging;

    _metrics = newMetrics;

    if (shouldNotify) {
      notifyListeners();
    }
  }

  double _parseMemKb(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return double.tryParse(parts[1]) ?? 0;
    }
    return 0;
  }
}

final systemMonitorProvider = ChangeNotifierProvider<SystemMonitorService>((ref) {
  return SystemMonitorService();
});
