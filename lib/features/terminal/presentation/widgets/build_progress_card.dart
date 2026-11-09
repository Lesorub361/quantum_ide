import 'package:flutter/material.dart';

import '../../../../core/services/build_progress_tracker.dart';
import 'build_completion_dialog.dart';

/// Compact live card: stage chips, progress bar, timer, heartbeat, errors.
class BuildProgressCard extends StatelessWidget {
  const BuildProgressCard({super.key, this.onInstall});

  final VoidCallback? onInstall;

  static const _stages = [
    (BuildStage.pubGet, 'pub get'),
    (BuildStage.gradle, 'Gradle'),
    (BuildStage.compile, 'Compile'),
    (BuildStage.packaging, 'APK'),
  ];

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tracker = BuildProgressTracker.instance;
    return ValueListenableBuilder<BuildProgress>(
      valueListenable: tracker.progress,
      builder: (context, p, _) {
        if (p.stage == BuildStage.idle) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final failed = p.stage == BuildStage.failed;
        final done = p.stage == BuildStage.done;
        final color = failed
            ? cs.error
            : (done ? Colors.greenAccent.shade400 : cs.primary);
        final idx = _stages.indexWhere((e) => e.$1 == p.stage);
        return Container(
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline
                        : (done
                              ? Icons.check_circle
                              : Icons.build_circle_outlined),
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      failed
                          ? 'Сборка не удалась'
                          : (done ? 'Сборка готова' : 'Идёт сборка…'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  Text(
                    _fmt(p.elapsed),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (!p.active)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: const Icon(Icons.close),
                      onPressed: tracker.dismiss,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: done ? 1 : (failed ? 1 : p.fraction),
                color: color,
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _stages.length; i++)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      label: Text(
                        _stages[i].$2,
                        style: const TextStyle(fontSize: 11),
                      ),
                      avatar: Icon(
                        done || (idx > i)
                            ? Icons.check
                            : (idx == i && p.active
                                  ? Icons.sync
                                  : Icons.circle_outlined),
                        size: 12,
                      ),
                    ),
                ],
              ),
              if (p.message.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontFamily: 'firaCode'),
                ),
              ],
              if (p.active && p.sinceLastOutput.inSeconds >= 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Gradle работает, нет вывода ${p.sinceLastOutput.inSeconds} с — это нормально для долгих этапов',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              if (failed && p.errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    p.errors.take(3).join('\n'),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.error),
                  ),
                ),
              if (done && p.apkPath != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (onInstall != null)
                        TextButton.icon(
                          onPressed: onInstall,
                          icon: const Icon(Icons.install_mobile, size: 16),
                          label: const Text('Установить'),
                        ),
                      TextButton.icon(
                        onPressed: () => BuildCompletionDialog.show(
                          context,
                          artifactPath: p.apkPath!,
                          elapsed: p.elapsed,
                        ),
                        icon: const Icon(Icons.pie_chart_outline, size: 16),
                        label: const Text('Инспектор размера'),
                      ),
                    ],
                  ),
                )
              else if (done && onInstall != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onInstall,
                    icon: const Icon(Icons.install_mobile, size: 18),
                    label: const Text('Установить APK'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
