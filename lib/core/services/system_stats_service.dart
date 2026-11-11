import 'dart:async';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/live_telemetry_service.dart';

class SystemProcessItem {
  final int pid;
  final String name;
  final String description;
  final String category;
  final double cpuPercent;
  final int rssBytes;
  final String command;

  const SystemProcessItem({
    required this.pid,
    required this.name,
    required this.description,
    required this.category,
    required this.cpuPercent,
    required this.rssBytes,
    required this.command,
  });

  String get ramFormatted {
    final mb = rssBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class SystemStats {
  final double cpuUsage;
  /// Модель процессора / чипсета SoC (например, "Snapdragon 7s Gen 3 (8 Cores)")
  final String socName;
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
  /// Память, занимаемая активными инструментами сборки (Gradle, AAPT2, PRoot, Java, Clang) в МБ
  final int builderRamMB;
  /// Нагрузка процессора от процессов сборщика (% CPU)
  final double builderCpuPercent;
  /// Нагрузка процессора самим приложением IDE (% от ВСЕГО процессора устройства)
  final double appCpuPercent;
  /// Сколько ядер реально занято сборщиком (1.7 = 1.7 ядра из N)
  final double builderCores;
  /// Число логических ядер устройства
  final int cpuCores;
  /// Идёт ли сейчас сборка
  final bool isBuilding;
  /// Список активных процессов и пакетов (как в Диспетчере задач Windows)
  final List<SystemProcessItem> processes;

  SystemStats({
    this.cpuUsage = 0.0,
    this.socName = 'Snapdragon / ARM64',
    this.gpuUsage = 0.05,
    this.gpuName = 'GPU',
    this.ramUsage = 0.0,
    this.ramTotalGB = 8.0,
    this.ramUsedGB = 0.18,
    this.appRamUsedMB = 180,
    this.deviceRamAvailableGB = 4.0,
    this.deviceRamUsedGB = 4.0,
    this.deviceRamUsage = 0.5,
    this.builderRamMB = 0,
    this.builderCpuPercent = 0.0,
    this.appCpuPercent = 0.0,
    this.builderCores = 0.0,
    this.cpuCores = 8,
    this.isBuilding = false,
    this.processes = const [],
  });

  /// Нагрузка прочих процессов (всё, что не IDE и не сборщик), 0..100
  double get otherCpuPercent =>
      (cpuUsage * 100 - appCpuPercent - builderCpuPercent).clamp(0.0, 100.0);

  /// Единая подпись для всех экранов: "21% · сборка 17% · IDE 3%"
  String get cpuSummary {
    final total = '${(cpuUsage * 100).toStringAsFixed(0)}%';
    if (builderCpuPercent >= 1) {
      return '$total · сборка ${builderCpuPercent.toStringAsFixed(0)}% (${builderCores.toStringAsFixed(1)}/$cpuCores ядер)';
    }
    return total;
  }

  /// Удобное форматирование памяти приложения ("184 МБ" или "1.2 ГБ")
  String get appRamFormatted {
    if (appRamUsedMB < 1024) {
      return '$appRamUsedMB MB';
    }
    return '${(appRamUsedMB / 1024.0).toStringAsFixed(1)} GB';
  }

  /// Удобное форматирование памяти сборщика
  String get builderRamFormatted {
    if (builderRamMB < 1024) {
      return '$builderRamMB MB';
    }
    return '${(builderRamMB / 1024.0).toStringAsFixed(1)} GB';
  }

  SystemStats copyWith({
    double? cpuUsage,
    String? socName,
    double? gpuUsage,
    String? gpuName,
    double? ramUsage,
    double? ramTotalGB,
    double? ramUsedGB,
    int? appRamUsedMB,
    double? deviceRamAvailableGB,
    double? deviceRamUsedGB,
    double? deviceRamUsage,
    int? builderRamMB,
    double? builderCpuPercent,
    double? appCpuPercent,
    double? builderCores,
    int? cpuCores,
    bool? isBuilding,
    List<SystemProcessItem>? processes,
  }) {
    return SystemStats(
      cpuUsage: cpuUsage ?? this.cpuUsage,
      socName: socName ?? this.socName,
      gpuUsage: gpuUsage ?? this.gpuUsage,
      gpuName: gpuName ?? this.gpuName,
      ramUsage: ramUsage ?? this.ramUsage,
      ramTotalGB: ramTotalGB ?? this.ramTotalGB,
      ramUsedGB: ramUsedGB ?? this.ramUsedGB,
      appRamUsedMB: appRamUsedMB ?? this.appRamUsedMB,
      deviceRamAvailableGB: deviceRamAvailableGB ?? this.deviceRamAvailableGB,
      deviceRamUsedGB: deviceRamUsedGB ?? this.deviceRamUsedGB,
      deviceRamUsage: deviceRamUsage ?? this.deviceRamUsage,
      builderRamMB: builderRamMB ?? this.builderRamMB,
      builderCpuPercent: builderCpuPercent ?? this.builderCpuPercent,
      appCpuPercent: appCpuPercent ?? this.appCpuPercent,
      builderCores: builderCores ?? this.builderCores,
      cpuCores: cpuCores ?? this.cpuCores,
      isBuilding: isBuilding ?? this.isBuilding,
      processes: processes ?? this.processes,
    );
  }
}

class SystemStatsNotifier extends StateNotifier<SystemStats> {
  Timer? _timer;
  int _lastCpuTotal = 0;
  int _lastCpuIdle = 0;

  bool _procStatBlocked = Platform.isAndroid;
  bool _sysfsCpuBlocked = false;
  bool _gpuSysfsBlocked = false;

  int? _lastAppCpuTicks;
  DateTime? _lastAppCpuTime;
  final int _cpuCores = Platform.numberOfProcessors > 0 ? Platform.numberOfProcessors : 8;

  List<SystemProcessItem> _cachedProcesses = const [];

  // --- Мгновенная нагрузка процессов (дельта тиков /proc/<pid>/stat) ---
  // `ps %cpu` показывает среднее за всё время жизни процесса и в «ядрах» (170% = 1.7 ядра),
  // а общая загрузка считается от всего CPU (0..100%). Из-за этого цифры не совпадали.
  // Теперь ВСЁ считается в одной шкале: % от всего процессора устройства.
  static const int _clkTck = 100;
  Map<int, int> _prevTicks = {};
  Map<int, int> _newTicks = {};
  final Map<int, double> _lastProcCores = {};
  DateTime? _prevSampleAt;
  double _sampleDtSec = 0;
  bool _busy = false;
  double _lastTotalCores = 0;
  double _lastAppCpuFraction = 0.03;

  /// Загрузка процесса в ядрах (1.0 = одно ядро полностью). null — /proc недоступен.
  double? _coresFor(int procPid) {
    try {
      final stat = File('/proc/$procPid/stat').readAsStringSync();
      final rp = stat.lastIndexOf(')');
      if (rp < 0) return null;
      final f = stat.substring(rp + 2).split(' ');
      if (f.length < 13) return null;
      final ticks = (int.tryParse(f[11]) ?? 0) + (int.tryParse(f[12]) ?? 0);
      _newTicks[procPid] = ticks;
      final prev = _prevTicks[procPid];
      if (prev == null) return _lastProcCores[procPid];
      if (_sampleDtSec < 0.25) return _lastProcCores[procPid] ?? 0.02;
      final d = ticks - prev;
      if (d < 0) return _lastProcCores[procPid] ?? 0.0;
      final cores = (d / _clkTck) / _sampleDtSec;
      _lastProcCores[procPid] = cores;
      return cores;
    } catch (_) {
      return _lastProcCores[procPid];
    }
  }

  SystemStatsNotifier() : super(SystemStats()) {
    _startUpdates();
  }

  void _startUpdates() {
    _updateStats(fetchProcesses: false);
    // Адаптивный интервал: во время сборки обновляем каждые 2 с (точная нагрузка),
    // в простое — раз в 6 с, чтобы показатели всегда были свежими без лишней нагрузки.
    var tick = 0;
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      tick++;
      if (LiveTelemetryService.instance.isBuilding || tick % 3 == 0) {
        _updateStats(fetchProcesses: false);
      }
    });
  }

  Future<void> refreshNow({bool fetchProcesses = true}) => _updateStats(fetchProcesses: fetchProcesses);

  /// Обновляет полный список процессов (вызывается при открытии Диспетчера задач)
  Future<void> refreshProcesses() => _updateStats(fetchProcesses: true);

  /// Останавливает зависшие фоновые демоны сборки (AAPT2, Gradle, Kotlin, Java, Dart),
  /// которые могут держать гигабайты ОЗУ и грузить CPU в фоне после сборки APK.
  Future<void> freeBackgroundMemory({bool force = false}) async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    // Никогда не убиваем процессы сборки, если сейчас идёт сборка APK и пользователь не нажал очистку вручную!
    if (!force && LiveTelemetryService.instance.currentBuildStatus == 'Running') {
      return;
    }
    try {
      if (!Platform.isWindows) {
        await Process.run('sh', [
          '-c',
          'pkill -9 -f aapt2 2>/dev/null || true; '
              'pkill -9 -f GradleDaemon 2>/dev/null || true; '
              'pkill -9 -f KotlinCompileDaemon 2>/dev/null || true; '
              'pkill -9 -f "dart analysis_server" 2>/dev/null || true'
        ]);
      } else {
        await Process.run('taskkill', ['/F', '/IM', 'aapt2.exe']).catchError((_) => ProcessResult(0, 0, '', ''));
        await Process.run('taskkill', ['/F', '/IM', 'java.exe']).catchError((_) => ProcessResult(0, 0, '', ''));
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    await _updateStats(fetchProcesses: true);
  }

  /// Завершает выбранный процесс (по аналогии с Диспетчером задач Windows)
  Future<void> killProcess(int targetPid) async {
    try {
      if (!Platform.isWindows) {
        await Process.run('kill', ['-15', '$targetPid']).timeout(const Duration(seconds: 2));
        await Future.delayed(const Duration(milliseconds: 200));
        await Process.run('kill', ['-9', '$targetPid']).timeout(const Duration(seconds: 2));
      } else {
        await Process.run('taskkill', ['/F', '/PID', '$targetPid']).timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));
    await refreshProcesses();
  }

  Future<void> _updateStats({bool fetchProcesses = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      await _updateStatsImpl(fetchProcesses: fetchProcesses);
    } finally {
      _busy = false;
    }
  }

  Future<void> _updateStatsImpl({bool fetchProcesses = false}) async {
    double cpu = 0.0;
    final appCpu = await _parseAppCpuUsage();

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
          cpu = (1.0 - (diffIdle / diffTotal)).clamp(0.01, 1.0);
        }
      }
      _lastCpuTotal = total;
      _lastCpuIdle = idleTime;
    } else {
      // На Android 10+ /proc/stat закрыт SELinux: комбинируем точное время /proc/self/stat и частоты CPU sysfs
      final sysfsCpu = await _parseCpuUsageFromSysfs();
      final sysfsNormalized = sysfsCpu != null ? ((sysfsCpu - 0.35) / 0.65).clamp(0.02, 0.85) : 0.0;
      final baseApp = appCpu ?? _lastAppCpuFraction;
      cpu = (baseApp > sysfsNormalized * 0.5 ? baseApp : (baseApp + sysfsNormalized * 0.35)).clamp(0.02, 1.0);
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

    // 3. Измеряем нагрузку и параметры видеоускорителя GPU и процессора SoC
    final double gpu = await _parseGpuUsage(cpu);
    final String gpuName = await _detectGpuName();
    final String socName = await _detectSocName();

    // 4. Список активных процессов: только по запросу (Диспетчер задач) или во время активной сборки
    final isBuilding = LiveTelemetryService.instance.isBuilding;
    List<SystemProcessItem> processes = _cachedProcesses;
    if (fetchProcesses || isBuilding) {
      processes = await _fetchProcessList(appRssBytes, cpu);
      _cachedProcesses = processes;
    } else if (processes.isEmpty) {
      processes = [
        SystemProcessItem(
          pid: pid,
          name: 'Quantum IDE',
          description: 'Основное приложение IDE (Flutter UI & Engine)',
          category: 'IDE',
          cpuPercent: ((appCpu ?? cpu) * 100).clamp(1.0, 99.0),
          rssBytes: appRssBytes > 0 ? appRssBytes : 180 * 1024 * 1024,
          command: 'quantum_ide (PID: $pid)',
        )
      ];
      _cachedProcesses = processes;
    }

    // Вычисляем реальное потребление ОЗУ и CPU всеми дочерними процессами сборщика
    int builderRamMB = 0;
    double builderCpuPercent = 0.0;
    for (final p in processes) {
      if (p.pid != pid && (
          p.category == 'Сборка' ||
          p.category == 'Компилятор' ||
          p.category == 'Упаковка' ||
          p.category == 'Песочница' ||
          p.name.contains('Gradle') ||
          p.name.contains('Kotlin') ||
          p.name.contains('AAPT2') ||
          p.name.contains('PRoot') ||
          p.name.contains('Java')
      )) {
        builderRamMB += (p.rssBytes / (1024 * 1024)).round();
        builderCpuPercent += p.cpuPercent;
      }
    }

    // Единая шкала: общая нагрузка ВСЕГДА не меньше базового замера CPU и суммы IDE + сборщик.
    final appCpuPercent =
        processes.where((p) => p.pid == pid).fold<double>(0, (a, p) => a + p.cpuPercent);
    final visiblePercent = (_lastTotalCores / _cpuCores * 100.0);
    final baseCpuPercent = cpu * 100.0;
    final floorPercent = [
      baseCpuPercent,
      appCpuPercent + builderCpuPercent,
      visiblePercent,
    ].reduce((a, b) => a > b ? a : b);
    cpu = (floorPercent / 100.0).clamp(0.01, 1.0);
    builderCpuPercent = builderCpuPercent.clamp(0.0, 100.0);
    final builderCores = builderCpuPercent / 100.0 * _cpuCores;

    if (mounted) {
      state = SystemStats(
        cpuUsage: cpu,
        socName: socName,
        gpuUsage: gpu,
        gpuName: gpuName,
        ramUsage: appRamUsageRatio,
        ramTotalGB: deviceTotalGB,
        ramUsedGB: appRamGB,
        appRamUsedMB: appRamMB,
        deviceRamAvailableGB: deviceAvailableGB,
        deviceRamUsedGB: deviceUsedGB,
        deviceRamUsage: deviceUsage,
        builderRamMB: builderRamMB,
        builderCpuPercent: builderCpuPercent,
        appCpuPercent: appCpuPercent.clamp(0.5, 100.0),
        builderCores: builderCores,
        cpuCores: _cpuCores,
        isBuilding: isBuilding,
        processes: processes,
      );
    }

    try {
      LiveTelemetryService.instance.updateStats(
        cpu: cpu,
        gpu: gpu,
        gpuTitle: gpuName,
        appRam: appRamMB,
        builderRam: builderRamMB,
        freeRamGB: deviceAvailableGB,
        totalRamGB: deviceTotalGB,
      );
    } catch (_) {}
  }

  Future<List<SystemProcessItem>> _fetchProcessList(int appRssBytes, double totalCpu) async {
    final list = <SystemProcessItem>[];
    double ideCpu = 0.0;
    final sampleNow = DateTime.now();
    _sampleDtSec = _prevSampleAt == null
        ? 0
        : sampleNow.difference(_prevSampleAt!).inMilliseconds / 1000.0;
    _newTicks = {};
    double totalCores = 0;

    try {
      if (!Platform.isWindows) {
        final res = await Process.run('sh', [
          '-c',
          'ps -eo pid,%cpu,rss,args -ww 2>/dev/null || ps -o pid,%cpu,rss,args -ww 2>/dev/null || ps -eo pid,%cpu,rss,args 2>/dev/null',
        ]).timeout(const Duration(seconds: 3));

        if (res.exitCode == 0) {
          final lines = res.stdout.toString().split('\n');
          for (final line in lines.skip(1)) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            final parts = trimmed.split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final procPid = int.tryParse(parts[0]);
              final psCpu = double.tryParse(parts[1]) ?? 0.0;
              // Единая шкала: % от ВСЕХ ядер устройства
              final cores = _coresFor(procPid ?? -1);
              final cpuVal = (cores != null && cores > 0)
                  ? (cores / _cpuCores * 100.0)
                  : (psCpu / _cpuCores);
              if (cores != null && cores > 0) {
                totalCores += cores;
              } else if (psCpu > 0) {
                totalCores += (psCpu / 100.0);
              }
              final rssKb = int.tryParse(parts[2]) ?? 0;
              final fullArgs = parts.sublist(3).join(' ');

              if (procPid == null) continue;
              if (procPid == pid) {
                ideCpu = cpuVal;
                continue; // пропускаем добавление дубликата, добавим ниже
              }
              if (fullArgs.contains('ps -eo') || fullArgs.contains('ps -o')) continue; // пропускаем сам ps

              final parsed = _classifyProcess(procPid, cpuVal, rssKb * 1024, fullArgs);
              if (parsed != null) {
                list.add(parsed);
              }
            }
          }
        }
      }
    } catch (_) {}

    // Fallback: `ps` недоступен/не вернул процессы — читаем /proc асинхронно без блокировки UI
    if (list.isEmpty && !Platform.isWindows) {
      try {
        await for (final e in Directory('/proc').list(followLinks: false)) {
          final name = e.path.split('/').last;
          final procPid = int.tryParse(name);
          if (procPid == null || procPid == pid) continue;
          final cores = _coresFor(procPid);
          if (cores == null) continue;
          String args = '';
          int rss = 0;
          try {
            args = (await File('${e.path}/cmdline').readAsString()).replaceAll('\u0000', ' ').trim();
            final st = (await File('${e.path}/statm').readAsString()).split(' ');
            rss = (int.tryParse(st[1]) ?? 0) * 4096;
          } catch (_) {}
          if (args.isEmpty) continue;
          totalCores += cores;
          final parsed = _classifyProcess(procPid, cores / _cpuCores * 100.0, rss, args);
          if (parsed != null) list.add(parsed);
        }
      } catch (_) {}
    }
    if (ideCpu <= 0.1) {
      final c = _coresFor(pid);
      if (c != null && c > 0) {
        ideCpu = c / _cpuCores * 100.0;
        if (!_newTicks.containsKey(-pid)) totalCores += c;
      } else {
        ideCpu = (_lastAppCpuFraction * 100.0).clamp(1.0, 100.0);
        totalCores += _lastAppCpuFraction * _cpuCores;
      }
    }

    if (_sampleDtSec >= 0.25 || _prevSampleAt == null) {
      _prevTicks = _newTicks;
      _prevSampleAt = sampleNow;
      _lastTotalCores = totalCores;
    } else if (totalCores > _lastTotalCores) {
      _lastTotalCores = totalCores;
    }

    // 1. Всегда добавляем само приложение Quantum IDE с его РЕАЛЬНЫМ процентом CPU
    list.add(SystemProcessItem(
      pid: pid,
      name: 'Quantum IDE',
      description: 'Основное приложение IDE (Flutter UI & Engine)',
      category: 'IDE',
      cpuPercent: double.parse(ideCpu.clamp(0.5, 100.0).toStringAsFixed(1)),
      rssBytes: appRssBytes > 0 ? appRssBytes : 180 * 1024 * 1024,
      command: 'quantum_ide (PID: $pid)',
    ));

    // Консолидация спящих / фоновых оболочек (idle shells с <=0.2% CPU)
    final terminalSessions = list.where((p) => p.name == 'Terminal Session').toList();
    if (terminalSessions.length > 2) {
      final idleSessions = terminalSessions.where((p) => p.cpuPercent <= 0.2).toList();
      if (idleSessions.length > 1) {
        list.removeWhere((p) => p.name == 'Terminal Session' && p.cpuPercent <= 0.2);
        final totalIdleRss = idleSessions.fold<int>(0, (sum, p) => sum + p.rssBytes);
        list.add(SystemProcessItem(
          pid: idleSessions.first.pid,
          name: 'Фоновые оболочки (${idleSessions.length} шт.)',
          description: 'Спящие процессы оболочек Bash/SH в режиме ожидания',
          category: 'Терминал',
          cpuPercent: 0.0,
          rssBytes: totalIdleRss,
          command: 'bash/sh idle subshells (${idleSessions.length} total)',
        ));
      }
    }

    // Консолидация спящих демонов Gradle (idle daemons с <=0.5% CPU)
    final gradleDaemons = list.where((p) => p.name.contains('Gradle')).toList();
    if (gradleDaemons.length > 1) {
      final idleDaemons = gradleDaemons.where((p) => p.cpuPercent <= 0.5).toList();
      if (idleDaemons.length > 1) {
        list.removeWhere((p) => p.name.contains('Gradle') && p.cpuPercent <= 0.5);
        final totalIdleRss = idleDaemons.fold<int>(0, (sum, p) => sum + p.rssBytes);
        final totalCpu = idleDaemons.fold<double>(0.0, (sum, p) => sum + p.cpuPercent);
        list.add(SystemProcessItem(
          pid: idleDaemons.first.pid,
          name: 'Фоновые демоны сборщика (${idleDaemons.length} шт.)',
          description: 'Спящие процессы Gradle в режиме ожидания (не грузят систему)',
          category: 'Сборка',
          cpuPercent: double.parse(totalCpu.toStringAsFixed(1)),
          rssBytes: totalIdleRss,
          command: 'gradle idle daemons (${idleDaemons.length} total)',
        ));
      }
    }

    // Консолидация спящих процессов JVM
    final jvmProcesses = list.where((p) => p.name.contains('JVM') || p.name.contains('Java')).toList();
    if (jvmProcesses.length > 1) {
      final idleJvm = jvmProcesses.where((p) => p.cpuPercent <= 0.5).toList();
      if (idleJvm.length > 1) {
        list.removeWhere((p) => (p.name.contains('JVM') || p.name.contains('Java')) && p.cpuPercent <= 0.5);
        final totalIdleRss = idleJvm.fold<int>(0, (sum, p) => sum + p.rssBytes);
        final totalCpu = idleJvm.fold<double>(0.0, (sum, p) => sum + p.cpuPercent);
        list.add(SystemProcessItem(
          pid: idleJvm.first.pid,
          name: 'Среда исполнения Java (${idleJvm.length} шт.)',
          description: 'Фоновые процессы Java Virtual Machine в режиме ожидания',
          category: 'Среда выполнения',
          cpuPercent: double.parse(totalCpu.toStringAsFixed(1)),
          rssBytes: totalIdleRss,
          command: 'jvm idle instances (${idleJvm.length} total)',
        ));
      }
    }

    // Группировка параллельных сборщиков AAPT2 при сборке APK
    final aaptWorkers = list.where((p) => p.name == 'AAPT2 / Packaging Tool').toList();
    if (aaptWorkers.length > 2) {
      final totalAaptCpu = aaptWorkers.fold<double>(0.0, (sum, p) => sum + p.cpuPercent);
      final totalAaptRss = aaptWorkers.fold<int>(0, (sum, p) => sum + p.rssBytes);
      list.removeWhere((p) => p.name == 'AAPT2 / Packaging Tool');
      list.add(SystemProcessItem(
        pid: aaptWorkers.first.pid,
        name: 'AAPT2 Workers (${aaptWorkers.length} шт.)',
        description: 'Параллельные сборщики ресурсов Android AAPT2',
        category: 'Упаковка',
        cpuPercent: double.parse(totalAaptCpu.toStringAsFixed(1)),
        rssBytes: totalAaptRss,
        command: 'aapt2 parallel workers (${aaptWorkers.length})',
      ));
    }

    // Группировка подпроцессов гостевой среды PRoot
    final prootProcesses = list.where((p) => p.name == 'PRoot Container').toList();
    if (prootProcesses.length > 2) {
      final totalProotCpu = prootProcesses.fold<double>(0.0, (sum, p) => sum + p.cpuPercent);
      final totalProotRss = prootProcesses.fold<int>(0, (sum, p) => sum + p.rssBytes);
      list.removeWhere((p) => p.name == 'PRoot Container');
      list.add(SystemProcessItem(
        pid: prootProcesses.first.pid,
        name: 'PRoot Linux Sandbox (${prootProcesses.length} шт.)',
        description: 'Изолированные потоки гостевой среды Ubuntu / Linux rootfs',
        category: 'Песочница',
        cpuPercent: double.parse(totalProotCpu.toStringAsFixed(1)),
        rssBytes: totalProotRss,
        command: 'proot sub-processes (${prootProcesses.length})',
      ));
    }

    // Сортировка: сначала самые прожорливые по CPU, затем по памяти
    list.sort((a, b) {
      final cpuCmp = b.cpuPercent.compareTo(a.cpuPercent);
      if (cpuCmp != 0) return cpuCmp;
      return b.rssBytes.compareTo(a.rssBytes);
    });

    return list;
  }

  SystemProcessItem? _classifyProcess(int procPid, double cpu, int rssBytes, String args) {
    final lower = args.toLowerCase();

    if (lower.contains('gradledaemon') || lower.contains('gradlew') || lower.contains('gradle-launcher')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Gradle Daemon',
        description: 'Фоновый сборщик APK и пакетов Gradle',
        category: 'Сборка',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('kotlincompiledaemon') || lower.contains('kotlinc')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Kotlin Compiler Daemon',
        description: 'Компилятор Kotlin для сборщика Android',
        category: 'Компилятор',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('analysis_server') || (lower.contains('dart') && lower.contains('analysis'))) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Dart Analysis Server',
        description: 'Анализатор кода, автодополнение и линтер Dart/Flutter',
        category: 'Языковой сервер',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('flutter_tools') || (lower.contains('flutter') && lower.contains('build'))) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Flutter Build Tool',
        description: 'Утилита сборки и упаковки Flutter',
        category: 'Сборка',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('proot')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'PRoot Container',
        description: 'Гостевая изолированная среда Linux / Ubuntu rootfs',
        category: 'Песочница',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('java') || lower.contains('openjdk')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Java Virtual Machine (JVM)',
        description: 'Среда исполнения Java (Gradle / Android SDK)',
        category: 'Среда выполнения',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('aapt2') || lower.contains('zipalign') || lower.contains('apksigner')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'AAPT2 / Packaging Tool',
        description: 'Упаковщик ресурсов Android APK',
        category: 'Упаковка',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('clang') || lower.contains('gcc') || lower.contains('ninja') || lower.contains('cmake')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'C/C++ Build Tool (Clang/Ninja)',
        description: 'Компилятор нативного кода C/C++/NDK',
        category: 'Компилятор',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('agy') || lower.contains('antigravity')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Antigravity CLI Agent',
        description: 'Автономный агент Google Antigravity',
        category: 'ИИ / Агент',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('claude')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Claude Code CLI',
        description: 'Автономный агент Claude Code',
        category: 'ИИ / Агент',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('dsh') || lower.contains('deepseek')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'DeepSeek Harness CLI',
        description: 'Автономный агент DeepSeek Harness',
        category: 'ИИ / Агент',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('llama') || lower.contains('ollama')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Local AI Inference (Llama)',
        description: 'Локальная нейросеть / движок инференса',
        category: 'ИИ / Нейросеть',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('node') || lower.contains('npm') || lower.contains('npx')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Node.js Engine',
        description: 'Среда исполнения Node.js / NPM пакеты',
        category: 'Среда выполнения',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (lower.contains('python') || lower.contains('python3')) {
      return SystemProcessItem(
        pid: procPid,
        name: 'Python Runtime',
        description: 'Интерпретатор Python',
        category: 'Среда выполнения',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    final isShell = RegExp(r'(^|[\s/])(bash|zsh)(\s|$)|(^|[\s/])(sh|mksh|dash)(\s+[^-]|\s*$)').hasMatch(lower);
    if (isShell) {
      if (lower.contains('ps -e') ||
          lower.contains('ps -o') ||
          lower.contains('which') ||
          lower.contains('grep') ||
          lower.contains('pkill') ||
          lower.contains('getprop') ||
          lower.contains('cat /') ||
          lower.contains('kill ') ||
          lower.contains('find ') ||
          lower.contains('-c ')) {
        return null;
      }
      return SystemProcessItem(
        pid: procPid,
        name: 'Terminal Session',
        description: 'Интерактивная оболочка терминала (Bash/SH)',
        category: 'Терминал',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    if (cpu > 0.5 || rssBytes > 15 * 1024 * 1024) {
      final binaryName = args.split(' ').first.split('/').last;
      return SystemProcessItem(
        pid: procPid,
        name: binaryName,
        description: 'Системный фоновый процесс: $binaryName',
        category: 'Процесс',
        cpuPercent: cpu,
        rssBytes: rssBytes,
        command: args,
      );
    }

    return null;
  }

  String? _cachedSocName;

  Future<String> _detectSocName() async {
    if (_cachedSocName != null) return _cachedSocName!;

    String rawSoc = '';
    String platform = '';

    if (!Platform.isWindows && !Platform.isMacOS) {
      try {
        final resSoc = await Process.run('getprop', ['ro.soc.model']);
        rawSoc = resSoc.stdout.toString().trim();
      } catch (_) {}

      try {
        final resPlat = await Process.run('getprop', ['ro.board.platform']);
        platform = resPlat.stdout.toString().trim();
      } catch (_) {}

      if (rawSoc.isEmpty) {
        try {
          final resChip = await Process.run('getprop', ['ro.chipname']);
          rawSoc = resChip.stdout.toString().trim();
        } catch (_) {}
      }

      if (rawSoc.isEmpty) {
        try {
          final resHw = await Process.run('getprop', ['ro.hardware']);
          rawSoc = resHw.stdout.toString().trim();
        } catch (_) {}
      }
    } else if (Platform.isLinux) {
      try {
        final cpuInfo = await File('/proc/cpuinfo').readAsString();
        for (final line in cpuInfo.split('\n')) {
          if (line.startsWith('model name')) {
            final parts = line.split(':');
            if (parts.length > 1) {
              _cachedSocName = parts[1].trim();
              return _cachedSocName!;
            }
          }
        }
      } catch (_) {}
    }

    _cachedSocName = _formatSocName(rawSoc, platform, _cpuCores);
    return _cachedSocName!;
  }

  static String _formatSocName(String rawSoc, String platform, int cores) {
    final s = rawSoc.toUpperCase().trim();
    final p = platform.toLowerCase().trim();

    // Qualcomm Snapdragon models
    if (s.contains('SM7635') || p.contains('volcano')) return 'Snapdragon 7s Gen 3 · $cores ядер';
    if (s.contains('SM8750') || p.contains('sun')) return 'Snapdragon 8 Elite · $cores ядер';
    if (s.contains('SM8650') || p.contains('pineapple')) return 'Snapdragon 8 Gen 3 · $cores ядер';
    if (s.contains('SM8550') || p.contains('kalama')) return 'Snapdragon 8 Gen 2 · $cores ядер';
    if (s.contains('SM8475') || p.contains('cape')) return 'Snapdragon 8+ Gen 1 · $cores ядер';
    if (s.contains('SM8450') || p.contains('taro')) return 'Snapdragon 8 Gen 1 · $cores ядер';
    if (s.contains('SM7550') || p.contains('crow')) return 'Snapdragon 7 Gen 3 · $cores ядер';
    if (s.contains('SM7475')) return 'Snapdragon 7+ Gen 2 · $cores ядер';
    if (s.contains('SM7325') || p.contains('lahaina')) return 'Snapdragon 778G · $cores ядер';
    if (s.contains('SM6450')) return 'Snapdragon 6 Gen 1 · $cores ядер';
    if (s.contains('SM6375')) return 'Snapdragon 695 · $cores ядер';
    if (s.contains('SM4450')) return 'Snapdragon 4 Gen 2 · $cores ядер';
    if (s.contains('SM8350')) return 'Snapdragon 888 · $cores ядер';
    if (s.contains('SM8250') || p.contains('kona')) return 'Snapdragon 865 · $cores ядер';
    if (s.contains('SM8150')) return 'Snapdragon 855 · $cores ядер';
    if (s.contains('SDM845')) return 'Snapdragon 845 · $cores ядер';

    // MediaTek Dimensity / Helio
    if (s.contains('MT6991')) return 'Dimensity 9400 · $cores ядер';
    if (s.contains('MT6989')) return 'Dimensity 9300 · $cores ядер';
    if (s.contains('MT6985')) return 'Dimensity 9200 · $cores ядер';
    if (s.contains('MT6983')) return 'Dimensity 9000 · $cores ядер';
    if (s.contains('MT6895')) return 'Dimensity 8100 · $cores ядер';
    if (s.contains('MT6877')) return 'Dimensity 1080 · $cores ядер';
    if (s.contains('MT6789')) return 'Helio G99 · $cores ядер';
    if (s.contains('MT6769') || s.contains('MT6768')) return 'Helio G85 · $cores ядер';

    // Google Tensor
    if (p.contains('zumapro') || s.contains('G4')) return 'Google Tensor G4 · $cores ядер';
    if (p.contains('zuma') || s.contains('G3')) return 'Google Tensor G3 · $cores ядер';
    if (p.contains('bluejay') || p.contains('gs201')) return 'Google Tensor G2 · $cores ядер';
    if (p.contains('gs101')) return 'Google Tensor G1 · $cores ядер';

    // Samsung Exynos
    if (s.contains('S5E9945')) return 'Exynos 2400 · $cores ядер';
    if (s.contains('S5E9925')) return 'Exynos 2200 · $cores ядер';
    if (s.contains('S5E9840')) return 'Exynos 2100 · $cores ядер';
    if (s.contains('S5E8845')) return 'Exynos 1480 · $cores ядер';
    if (s.contains('S5E8835')) return 'Exynos 1380 · $cores ядер';

    if (rawSoc.isNotEmpty) {
      return '$rawSoc · $cores ядер';
    }
    if (platform.isNotEmpty && platform != 'unknown') {
      return '${platform.toUpperCase()} · $cores ядер';
    }
    return 'ARM64 · $cores ядер';
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
    if (!_gpuSysfsBlocked) {
      try {
        // 1. Qualcomm percentage file (normalized by driver)
        final kgslPct = File('/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage');
        if (await kgslPct.exists()) {
          final content = (await kgslPct.readAsString()).trim().replaceAll('%', '').trim();
          final pct = double.tryParse(content);
          if (pct != null) {
            double ratio = (pct / 100.0).clamp(0.0, 1.0);
            try {
              final curClkFile = File('/sys/class/kgsl/kgsl-3d0/gpuclk');
              final maxClkFile = File('/sys/class/kgsl/kgsl-3d0/max_gpuclk');
              if (await curClkFile.exists() && await maxClkFile.exists()) {
                final curClk = double.tryParse((await curClkFile.readAsString()).trim());
                final maxClk = double.tryParse((await maxClkFile.readAsString()).trim());
                if (curClk != null && maxClk != null && maxClk > 0) {
                  ratio = (ratio * (curClk / maxClk)).clamp(0.0, 1.0);
                }
              }
            } catch (_) {}
            return ratio;
          }
        }

        // 2. Qualcomm Adreno /sys/class/kgsl/kgsl-3d0/gpubusy (busy total at current clock)
        final kgslBusy = File('/sys/class/kgsl/kgsl-3d0/gpubusy');
        if (await kgslBusy.exists()) {
          final content = (await kgslBusy.readAsString()).trim();
          final parts = content.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
          if (parts.length >= 2) {
            final busy = double.tryParse(parts[0]) ?? 0.0;
            final total = double.tryParse(parts[1]) ?? 0.0;
            if (total > 0) {
              double ratio = (busy / total).clamp(0.0, 1.0);
              try {
                final curClkFile = File('/sys/class/kgsl/kgsl-3d0/gpuclk');
                final maxClkFile = File('/sys/class/kgsl/kgsl-3d0/max_gpuclk');
                if (await curClkFile.exists() && await maxClkFile.exists()) {
                  final curClk = double.tryParse((await curClkFile.readAsString()).trim());
                  final maxClk = double.tryParse((await maxClkFile.readAsString()).trim());
                  if (curClk != null && maxClk != null && maxClk > 0) {
                    ratio = (ratio * (curClk / maxClk)).clamp(0.0, 1.0);
                  }
                }
              } catch (_) {}
              return ratio;
            }
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
        _gpuSysfsBlocked = true;
      } catch (_) {
        _gpuSysfsBlocked = true;
      }
    }

    // 5. Fallback estimate dynamically correlated with system activity
    if (cpuLoad > 0.0) {
      return (cpuLoad * 0.35 + 0.02).clamp(0.01, 0.95);
    }
    return 0.02;
  }

  Future<List<int>?> _parseCpuStats() async {
    if (_procStatBlocked) return null;
    try {
      final file = File('/proc/stat');
      if (!await file.exists()) {
        _procStatBlocked = true;
        return null;
      }
      final lines = await file.readAsLines();
      if (lines.isEmpty) return null;
      final firstLine = lines.first;
      if (!firstLine.startsWith('cpu')) return null;
      final parts = firstLine.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).skip(1);
      return parts.map((p) => int.tryParse(p) ?? 0).toList();
    } catch (_) {
      _procStatBlocked = true;
      return null;
    }
  }

  /// Читает процессорное время самого процесса IDE (/proc/self/stat).
  /// Полностью легально в Android SELinux для непривилегированных приложений без root!
  Future<double?> _parseAppCpuUsage() async {
    try {
      final content = await File('/proc/self/stat').readAsString();
      final lastParen = content.lastIndexOf(')');
      if (lastParen == -1) return _lastAppCpuFraction;
      final rest = content.substring(lastParen + 2).split(' ');
      if (rest.length > 14) {
        final utime = int.tryParse(rest[11]) ?? 0;
        final stime = int.tryParse(rest[12]) ?? 0;
        final cutime = int.tryParse(rest[13]) ?? 0;
        final cstime = int.tryParse(rest[14]) ?? 0;
        final totalTicks = utime + stime + cutime + cstime;
        final now = DateTime.now();

        if (_lastAppCpuTicks != null && _lastAppCpuTime != null) {
          final elapsedSeconds = now.difference(_lastAppCpuTime!).inMilliseconds / 1000.0;
          if (elapsedSeconds < 0.25) {
            return _lastAppCpuFraction;
          }
          final ticksDiff = totalTicks - _lastAppCpuTicks!;
          if (elapsedSeconds >= 0.25 && ticksDiff >= 0) {
            final fraction = ((ticksDiff / 100.0) / (elapsedSeconds * _cpuCores)).clamp(0.01, 1.0);
            _lastAppCpuTicks = totalTicks;
            _lastAppCpuTime = now;
            _lastAppCpuFraction = fraction;
            return fraction;
          }
        }
        _lastAppCpuTicks = totalTicks;
        _lastAppCpuTime = now;
      }
    } catch (_) {}
    return _lastAppCpuFraction;
  }

  Future<double?> _parseCpuUsageFromSysfs() async {
    if (_sysfsCpuBlocked) return null;
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
      _sysfsCpuBlocked = true;
    } catch (_) {
      _sysfsCpuBlocked = true;
    }
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
