import 'package:flutter/material.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';

/// Single, consistent CPU meter used everywhere (explorer, drawer, status bar).
///
/// One scale for everything: percent of the WHOLE device CPU. The bar is
/// stacked: IDE + build + other, so the total always equals the sum of parts.
class UnifiedLoadMeter extends StatelessWidget {
  const UnifiedLoadMeter({super.key, required this.stats, this.compact = false});

  final SystemStats stats;
  final bool compact;

  static const _ideColor = Color(0xFF4FC3F7);
  static const _buildColor = Color(0xFFFFB74D);
  static const _otherColor = Color(0xFF78909C);

  @override
  Widget build(BuildContext context) {
    final total = (stats.cpuUsage * 100).clamp(0.0, 100.0);
    final ide = stats.appCpuPercent.clamp(0.0, total);
    final build = stats.builderCpuPercent.clamp(0.0, total - ide);
    final other = (total - ide - build).clamp(0.0, 100.0);

    int flex(double v) => (v * 10).round().clamp(0, 1000);
    final rest = (1000 - flex(ide) - flex(build) - flex(other)).clamp(0, 1000);

    final label = stats.isBuilding || build >= 1
        ? 'CPU ${total.toStringAsFixed(0)}% · сборка ${build.toStringAsFixed(0)}% · IDE ${ide.toStringAsFixed(0)}%'
        : 'CPU ${total.toStringAsFixed(0)}% · IDE ${ide.toStringAsFixed(0)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: compact ? 10 : 11, fontWeight: FontWeight.w600, color: Colors.white70),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: compact ? 3 : 5,
            child: Row(children: [
              if (flex(ide) > 0) Expanded(flex: flex(ide), child: Container(color: _ideColor)),
              if (flex(build) > 0) Expanded(flex: flex(build), child: Container(color: _buildColor)),
              if (flex(other) > 0) Expanded(flex: flex(other), child: Container(color: _otherColor)),
              Expanded(flex: rest == 0 && total == 0 ? 1 : rest, child: Container(color: Colors.white.withValues(alpha: 0.06))),
            ]),
          ),
        ),
        if (!compact && (stats.isBuilding || build >= 1))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Сборка занимает ${stats.builderCores.toStringAsFixed(1)} из ${stats.cpuCores} ядер · RAM ${stats.builderRamFormatted}',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ),
      ],
    );
  }
}
