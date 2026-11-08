import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/system_monitor_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';

class SystemStatusBar extends ConsumerWidget {
  const SystemStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(systemMonitorProvider);
    final stats = ref.watch(systemStatsProvider);
    final m = monitor.metrics;
    final cpuPct = (stats.cpuUsage * 100).clamp(1, 100).toStringAsFixed(0);

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (_) => const SystemDiagnosticsDialog(),
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0F141E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CPU
            const Icon(LucideIcons.cpu, size: 11, color: Color(0xFF60A5FA)),
            const SizedBox(width: 4),
            Text(
              '$cpuPct%',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),

            // RAM
            const Icon(LucideIcons.memory_stick, size: 11, color: Color(0xFFA78BFA)),
            const SizedBox(width: 4),
            Text(
              m.ramTotalGb > 0
                  ? '${m.ramUsedGb.toStringAsFixed(1)}/${m.ramTotalGb.toStringAsFixed(1)}G'
                  : 'RAM',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),

            // Battery
            Icon(
              m.isCharging ? LucideIcons.battery_charging : LucideIcons.battery,
              size: 11,
              color: m.batteryLevel < 20 ? Colors.redAccent : const Color(0xFF34D399),
            ),
            const SizedBox(width: 4),
            Text(
              '${m.batteryLevel}%',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class SystemDiagnosticsDialog extends ConsumerWidget {
  const SystemDiagnosticsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitor = ref.watch(systemMonitorProvider);
    final stats = ref.watch(systemStatsProvider);
    final m = monitor.metrics;

    return AlertDialog(
      backgroundColor: const Color(0xFF131722),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.gauge, color: Color(0xFFA78BFA), size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'Системные показатели',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMetricCard(
              title: 'Оперативная память (RAM)',
              value: m.ramTotalGb > 0
                  ? '${m.ramUsedGb.toStringAsFixed(2)} ГБ / ${m.ramTotalGb.toStringAsFixed(2)} ГБ (${m.ramUsagePercent.toStringAsFixed(0)}%)'
                  : 'Загрузка...',
              progress: m.ramUsagePercent / 100,
              progressColor: m.ramUsagePercent > 80 ? Colors.redAccent : const Color(0xFF8B5CF6),
              icon: LucideIcons.memory_stick,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Процессор (${stats.socName})',
              value: 'Нагрузка: ${(stats.cpuUsage * 100).toStringAsFixed(1)}% | IDE: ${stats.appCpuPercent.toStringAsFixed(1)}%',
              progress: stats.cpuUsage.clamp(0.0, 1.0),
              progressColor: const Color(0xFF3B82F6),
              icon: LucideIcons.cpu,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Накопитель (Диск)',
              value: m.diskTotalGb > 0
                  ? 'Свободно: ${m.diskFreeGb.toStringAsFixed(1)} ГБ из ${m.diskTotalGb.toStringAsFixed(1)} ГБ'
                  : 'Доступно на устройстве',
              progress: m.diskTotalGb > 0 ? (1 - (m.diskFreeGb / m.diskTotalGb)).clamp(0.0, 1.0) : 0.5,
              progressColor: const Color(0xFF10B981),
              icon: LucideIcons.hard_drive,
            ),
            const SizedBox(height: 10),
            _buildMetricCard(
              title: 'Батарея',
              value: '${m.batteryLevel}% ${m.isCharging ? "(Зарядка ⚡)" : "(От батареи)"}',
              progress: m.batteryLevel / 100,
              progressColor: m.isCharging ? Colors.amber : const Color(0xFF34D399),
              icon: m.isCharging ? LucideIcons.battery_charging : LucideIcons.battery,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0D14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Устройство: ${m.deviceModel}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 2),
                  if (m.androidVersion.isNotEmpty)
                    Text('ОС: ${m.androidVersion}', style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                  if (m.socInfo.isNotEmpty)
                    Text('Чипсет: ${m.socInfo}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть', style: TextStyle(color: Color(0xFFA78BFA))),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required double progress,
    required Color progressColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: progressColor),
              const SizedBox(width: 6),
              Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 5),
          Text(value, style: GoogleFonts.jetBrainsMono(color: Colors.white60, fontSize: 10.5)),
        ],
      ),
    );
  }
}
