import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SystemStats {
  final double cpuUsage;
  /// Доля использования видеоускорителя GPU (0.0 .. 1.0)
  final double gpuUsage;
  /// Модель или наименование графического чипа GPU (например, "Adreno 810" или "Mali")
  final String gpuName;
  /// Доля памяти, занимаемая самим приложением Quantum IDE относительно доступного лимита
  final double ramUsage;
  final double ramTotalGB;
  /// Память процесса Quantum IDE в ГБ (для обратной совместимости)
  final double ramUsedGB;
  /// Реальное потребление ОЗУ процессом Quantum IDE (RSS в МБ)
  final int appRamUsedMB;
  /// Свободная оперативная память на всём устройстве (ГБ)
  final double deviceRamAvailableGB;
  /// Занятая оперативная память всей ОС Android/Linux (ГБ)
  final double deviceRamUsedGB;
  /// Доля занятой памяти всей системы (0.0 .. 1.0)
  final double deviceRamUsage;

  SystemStats({
    this.cpuUsage = 0.0,
    this.gpuUsage = 0.05,
    this.gpuName = 'GPU',
    this.ramUsage = 0.0,
    this.ramTotalGB = 8.0,
    this.ramUsedGB = 0.18,
    this.appRamUsedMB = 180,
    this.deviceRamAvailableGB = 4.0,
    this.deviceRamUsedGB = 4.0,
    this.deviceRamUsage = 0.5,
  });

  /// Удобное форматирование памяти приложения ("184 МБ" или "1.2 ГБ")
  String get appRamFormatted {
    if (appRamUsedMB < 1024) {
      return '$appRamUsedMB MB';
    }
    return '${(appRamUsedMB / 1024.0).toStringAsFixed(1)} GB';
  }

  SystemStats copyWith({
    double? cpuUsage,
    double? gpuUsage,
    String? gpuName,
    double? ramUsage,
    double? ramTotalGB,
    double? ramUsedGB,
    int? appRamUsedMB,
    double? deviceRamAvailableGB,
    double? deviceRamUsedGB,
    double? deviceRamUsage,
  }) {
    return SystemStats(
      cpuUsage: cpuUsage ?? this.cpuUsage,
      gpuUsage: gpuUsage ?? this.gpuUsage,
      gpuName: gpuName ?? this.gpuName,
      ramUsage: ramUsage ?? this.ramUsage,
      ramTotalGB: ramTotalGB ?? this.ramTotalGB,
      ramUsedGB: ramUsedGB ?? this.ramUsedGB,
      appRamUsedMB: appRamUsedMB ?? this.appRamUsedMB,
      deviceRamAvailableGB: deviceRamAvailableGB ?? this.deviceRamAvailableGB,
      deviceRamUsedGB: deviceRamUsedGB ?? this.deviceRamUsedGB,
      deviceRamUsage: deviceRamUsage ?? this.deviceRamUsage,
    );
  }
}

class SystemStatsNotifier extends StateNotifier<SystemStats> {
  Timer? _timer;
  int _lastCpuTotal = 0;
  int _lastCpuIdle = 0;

  SystemStatsNotifier() : super(SystemStats()) {
    _startUpdates();
  }

  void _startUpdates() {
    _updateStats();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _updateStats();
    });
  }

  Future<void> refreshNow() => _updateStats();

  /// Останавливает зависшие фоновые демоны сборки (Gradle, Kotlin, Java),
  /// которые могут держать гигабайты ОЗУ в фоне после сборки APK.
  Future<void> freeBackgroundMemory() async {
    try {
      if (!Platform.isWindows) {
        await Process.run('sh', [
          '-c',
          'pkill -f GradleDaemon 2>/dev/null || true; '
              'pkill -f KotlinCompileDaemon 2>/dev/null || true; '
              'pkill -f "dart analysis_server" 2>/dev/null || true'
        ]);
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    await _updateStats();
  }

  Future<void> _updateStats() async {
    double cpu = 0.0;

    final cpuStats = await _parseCpuStats();
    if (cpuStats != null) {
      final user = cpuStats[0];
      final nice = cpuStats[1];
      final system = cpuStats[2];
      final idle = cpuStats[3];
      final iowait = cpuStats.length > 4 ? cpuStats[4] : 0;
      final irq = cpuStats.length > 5 ? cpuStats[5] : 0;
      final softirq = cpuStats.length > 6 ? cpuStats[6] : 0;
      final steal = cpuStats.length > 7 ? cpuStats[7] : 0;

      final total = user + nice + system + idle + iowait + irq + softirq + steal;
      final idleTime = idle + iowait;

      if (_lastCpuTotal > 0) {
        final diffTotal = total - _lastCpuTotal;
        final diffIdle = idleTime - _lastCpuIdle;
        if (diffTotal > 0) {
          cpu = 1.0 - (diffIdle / diffTotal);
          if (cpu < 0.0) cpu = 0.0;
          if (cpu > 1.0) cpu = 1.0;
        }
      }
      _lastCpuTotal = total;
      _lastCpuIdle = idleTime;
    } else {
      final sysfsCpu = await _parseCpuUsageFromSysfs();
      if (sysfsCpu != null) {
        final normalized = ((sysfsCpu - 0.40) / 0.60).clamp(0.03, 0.85);
        cpu = normalized;
      } else {
        cpu = 0.04;
      }
    }

    // 1. Измеряем реальную память самого приложения Quantum IDE (RSS процесса в байтах)
    int appRssBytes = 0;
    try {
      appRssBytes = ProcessInfo.currentRss;
    } catch (_) {}
    final appRamMB = (appRssBytes > 0 ? (appRssBytes / (1024 * 1024)).round() : 160).clamp(32, 65536);
    final appRamGB = appRamMB / 1024.0;

    // 2. Измеряем общую и свободную память устройства из /proc/meminfo
    final ramStats = await _parseRamStats();
    final double deviceTotalGB = ramStats?.ramTotalGB ?? 8.0;
    final double deviceAvailableGB = ramStats?.ramAvailableGB ?? (deviceTotalGB - appRamGB).clamp(1.0, deviceTotalGB);
    final double deviceUsedGB = ramStats?.ramUsedGB ?? (deviceTotalGB - deviceAvailableGB);
    final double deviceUsage = ramStats?.ramUsage ?? (deviceUsedGB / deviceTotalGB).clamp(0.0, 1.0);

    // Доля ОЗУ, используемая самим приложением относительно общего объёма ОЗУ устройства
    final double appRamUsageRatio = (appRamGB / deviceTotalGB).clamp(0.01, 1.0);

    // 3. Измеряем нагрузку и параметры видеоускорителя GPU
    final double gpu = await _parseGpuUsage(cpu);
    final String gpuName = await _detectGpuName();

    if (mounted) {
      state = SystemStats(
        cpuUsage: cpu,
        gpuUsage: gpu,
        gpuName: gpuName,
        ramUsage: appRamUsageRatio,
        ramTotalGB: deviceTotalGB,
        ramUsedGB: appRamGB,
        appRamUsedMB: appRamMB,
        deviceRamAvailableGB: deviceAvailableGB,
        deviceRamUsedGB: deviceUsedGB,
        deviceRamUsage: deviceUsage,
      );
    }
  }

  String? _cachedGpuName;

  Future<String> _detectGpuName() async {
    if (_cachedGpuName != null) return _cachedGpuName!;
    try {
      final modelFile = File('/sys/class/kgsl/kgsl-3d0/gpu_model');
      if (await modelFile.exists()) {
        final raw = (await modelFile.readAsString()).trim();
        if (raw.isNotEmpty) {
          final match = RegExp(r'([A-Za-z]+)(\d+)(.*)').firstMatch(raw);
          if (match != null) {
            _cachedGpuName = '${match.group(1)} ${match.group(2)}';
            return _cachedGpuName!;
          }
          _cachedGpuName = raw;
          return _cachedGpuName!;
        }
      }
    } catch (_) {}

    try {
      if (!Platform.isWindows) {
        final res = await Process.run('getprop', ['ro.hardware.egl']);
        final egl = res.stdout.toString().trim().toLowerCase();
        if (egl.contains('adreno')) {
          _cachedGpuName = 'Adreno GPU';
          return _cachedGpuName!;
        } else if (egl.contains('mali')) {
          _cachedGpuName = 'Mali GPU';
          return _cachedGpuName!;
        } else if (egl.contains('powervr')) {
          _cachedGpuName = 'PowerVR';
          return _cachedGpuName!;
        }
      }
    } catch (_) {}

    _cachedGpuName = 'GPU';
    return _cachedGpuName!;
  }

  Future<double> _parseGpuUsage(double cpuLoad) async {
    try {
      // 1. Qualcomm Adreno /sys/class/kgsl/kgsl-3d0/gpubusy (busy total)
      final kgslBusy = File('/sys/class/kgsl/kgsl-3d0/gpubusy');
      if (await kgslBusy.exists()) {
        final content = (await kgslBusy.readAsString()).trim();
        final parts = content.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        if (parts.length >= 2) {
          final busy = double.tryParse(parts[0]) ?? 0.0;
          final total = double.tryParse(parts[1]) ?? 0.0;
          if (total > 0) {
            return (busy / total).clamp(0.0, 1.0);
          }
        }
      }

      // 2. Qualcomm percentage file
      final kgslPct = File('/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage');
      if (await kgslPct.exists()) {
        final content = (await kgslPct.readAsString()).trim();
        final pct = double.tryParse(content);
        if (pct != null) {
          return (pct / 100.0).clamp(0.0, 1.0);
        }
      }

      // 3. ARM Mali utilization (0..100 or 0..255)
      for (final path in [
        '/sys/class/misc/mali0/device/utilization',
        '/sys/devices/platform/13040000.mali/utilization',
        '/sys/devices/platform/gpu/utilization',
      ]) {
        final maliFile = File(path);
        if (await maliFile.exists()) {
          final content = (await maliFile.readAsString()).trim();
          final val = double.tryParse(content);
          if (val != null) {
            final ratio = val > 100 ? (val / 255.0) : (val / 100.0);
            return ratio.clamp(0.0, 1.0);
          }
        }
      }

      // 4. Linux DRM GPU busy percent
      final drmFile = File('/sys/class/drm/card0/device/gpu_busy_percent');
      if (await drmFile.exists()) {
        final content = (await drmFile.readAsString()).trim();
        final val = double.tryParse(content);
        if (val != null) {
          return (val / 100.0).clamp(0.0, 1.0);
        }
      }
    } catch (_) {}

    // 5. Fallback estimate dynamically correlated with system activity
    if (cpuLoad > 0.0) {
      return (cpuLoad * 0.45 + 0.04).clamp(0.02, 0.95);
    }
    return 0.05;
  }

  Future<List<int>?> _parseCpuStats() async {
    try {
      final file = File('/proc/stat');
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      if (lines.isEmpty) return null;
      final firstLine = lines.first;
      if (!firstLine.startsWith('cpu')) return null;
      final parts = firstLine.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).skip(1);
      return parts.map((p) => int.tryParse(p) ?? 0).toList();
    } catch (_) {
      return null;
    }
  }

  Future<double?> _parseCpuUsageFromSysfs() async {
    try {
      double totalRatio = 0.0;
      int count = 0;
      for (int i = 0; i < 8; i++) {
        final curFile = File('/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq');
        final maxFile = File('/sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq');
        if (await curFile.exists() && await maxFile.exists()) {
          final curStr = (await curFile.readAsString()).trim();
          final maxStr = (await maxFile.readAsString()).trim();
          final cur = int.tryParse(curStr);
          final max = int.tryParse(maxStr);
          if (cur != null && max != null && max > 0) {
            totalRatio += (cur / max).clamp(0.0, 1.0);
            count++;
          }
        }
      }
      if (count > 0) {
        return totalRatio / count;
      }
    } catch (_) {}
    return null;
  }

  Future<_RamStats?> _parseRamStats() async {
    try {
      final file = File('/proc/meminfo');
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      int memTotal = 0;
      int memAvailable = 0;
      int memFree = 0;
      int buffers = 0;
      int cached = 0;

      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          memTotal = _parseMeminfoValue(line);
        } else if (line.startsWith('MemAvailable:')) {
          memAvailable = _parseMeminfoValue(line);
        } else if (line.startsWith('MemFree:')) {
          memFree = _parseMeminfoValue(line);
        } else if (line.startsWith('Buffers:')) {
          buffers = _parseMeminfoValue(line);
        } else if (line.startsWith('Cached:')) {
          cached = _parseMeminfoValue(line);
        }
      }

      if (memTotal == 0) return null;

      if (memAvailable == 0) {
        memAvailable = memFree + buffers + cached;
      }

      final used = memTotal - memAvailable;
      final ramUsage = used / memTotal;
      final ramTotalGB = memTotal / (1024 * 1024);
      final ramUsedGB = used / (1024 * 1024);
      final ramAvailableGB = memAvailable / (1024 * 1024);

      return _RamStats(
        ramUsage: ramUsage,
        ramTotalGB: ramTotalGB,
        ramUsedGB: ramUsedGB,
        ramAvailableGB: ramAvailableGB,
      );
    } catch (_) {
      return null;
    }
  }

  int _parseMeminfoValue(String line) {
    final match = RegExp(r'\d+').firstMatch(line);
    if (match != null) {
      return int.tryParse(match.group(0) ?? '') ?? 0;
    }
    return 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _RamStats {
  final double ramUsage;
  final double ramTotalGB;
  final double ramUsedGB;
  final double ramAvailableGB;

  _RamStats({
    required this.ramUsage,
    required this.ramTotalGB,
    required this.ramUsedGB,
    required this.ramAvailableGB,
  });
}

final systemStatsProvider = StateNotifierProvider<SystemStatsNotifier, SystemStats>((ref) {
  return SystemStatsNotifier();
});
