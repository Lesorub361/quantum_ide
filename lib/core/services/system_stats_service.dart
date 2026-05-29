import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SystemStats {
  final double cpuUsage;
  final double ramUsage;
  final double ramTotalGB;
  final double ramUsedGB;

  SystemStats({
    this.cpuUsage = 0.0,
    this.ramUsage = 0.0,
    this.ramTotalGB = 0.0,
    this.ramUsedGB = 0.0,
  });

  SystemStats copyWith({
    double? cpuUsage,
    double? ramUsage,
    double? ramTotalGB,
    double? ramUsedGB,
  }) {
    return SystemStats(
      cpuUsage: cpuUsage ?? this.cpuUsage,
      ramUsage: ramUsage ?? this.ramUsage,
      ramTotalGB: ramTotalGB ?? this.ramTotalGB,
      ramUsedGB: ramUsedGB ?? this.ramUsedGB,
    );
  }
}

class SystemStatsNotifier extends StateNotifier<SystemStats> {
  Timer? _timer;
  int _lastCpuTotal = 0;
  int _lastCpuIdle = 0;
  final _random = Random();

  SystemStatsNotifier() : super(SystemStats()) {
    _startUpdates();
  }

  void _startUpdates() {
    _updateStats();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _updateStats();
    });
  }

  Future<void> _updateStats() async {
    double cpu = 0.0;
    double ramUsageVal = 0.0;
    double ramTotal = 8.0;
    double ramUsed = 4.0;

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
      // Mock fallback CPU usage (10% to 45%)
      cpu = 0.1 + _random.nextDouble() * 0.35;
    }

    final ramStats = await _parseRamStats();
    if (ramStats != null) {
      ramUsageVal = ramStats.ramUsage;
      ramTotal = ramStats.ramTotalGB;
      ramUsed = ramStats.ramUsedGB;
    } else {
      // Mock fallback RAM usage
      ramTotal = 8.0;
      ramUsed = 3.5 + _random.nextDouble() * 1.5;
      ramUsageVal = ramUsed / ramTotal;
    }

    if (mounted) {
      state = SystemStats(
        cpuUsage: cpu,
        ramUsage: ramUsageVal,
        ramTotalGB: ramTotal,
        ramUsedGB: ramUsed,
      );
    }
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

      return _RamStats(
        ramUsage: ramUsage,
        ramTotalGB: ramTotalGB,
        ramUsedGB: ramUsedGB,
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

  _RamStats({
    required this.ramUsage,
    required this.ramTotalGB,
    required this.ramUsedGB,
  });
}

final systemStatsProvider = StateNotifierProvider<SystemStatsNotifier, SystemStats>((ref) {
  return SystemStatsNotifier();
});
