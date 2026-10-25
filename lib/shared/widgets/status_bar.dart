import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/shared/widgets/device_selector_pill.dart';

class StatusBar extends ConsumerStatefulWidget {
  const StatusBar({super.key});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  CodeLineEditingController? _subscribedController;
  CodeLineEditingValue? _cursorValue;
  bool _pendingUpdate = false;

  @override
  void dispose() {
    _subscribedController?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (!_pendingUpdate) {
      _pendingUpdate = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pendingUpdate = false;
        setState(() {
          _cursorValue = _subscribedController?.value;
        });
      });
    }
  }

  void _switchController(CodeLineEditingController? newController) {
    if (newController == _subscribedController) return;
    _subscribedController?.removeListener(_onControllerChanged);
    _subscribedController = newController;
    _cursorValue = newController?.value;
    newController?.addListener(_onControllerChanged);
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorProvider);
    final gitState = ref.watch(gitProvider);

    final activeFile = editorState.openFiles.isNotEmpty &&
            editorState.activeTabIndex >= 0 &&
            editorState.activeTabIndex < editorState.openFiles.length
        ? editorState.openFiles[editorState.activeTabIndex]
        : null;

    _switchController(activeFile?.controller);

    final workspacePath = ref.watch(workspaceProvider).currentPath ?? '';
    final pos = _cursorValue?.selection.extent;
    final (errorsCount, warningsCount, hintsCount) = _getDiagnosticsCounts(editorState.allDiagnostics, workspacePath);

    return RepaintBoundary(
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF090B10),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final isUltraNarrow = constraints.maxWidth < 370;
            final lineNum = (pos?.index ?? 0) + 1;
            final colNum = (pos?.offset ?? 0) + 1;
            final cursorLabel = isNarrow
                ? 'Стр $lineNum:$colNum'
                : AppLocalizations.of(context)!.lineCol(lineNum, colNum);

            return Row(
              children: [
                // Left Side: Git & Diagnostics & CPU/RAM
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (gitState.status != null) ...[
                          _StatusBarPill(
                            icon: LucideIcons.git_branch,
                            label: gitState.status!.currentBranch,
                            color: Colors.cyanAccent,
                            maxWidth: isNarrow ? 72 : 140,
                            onTap: () {
                              ref.read(panelProvider.notifier).selectTab(PanelTab.git);
                            },
                          ),
                          SizedBox(width: isNarrow ? 5 : 8),
                        ],
                        // Problems: Icons and numbers only (❌ errors, ⚠️ warnings)
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            ref.read(panelProvider.notifier).selectTab(PanelTab.problems);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (errorsCount > 0
                                      ? const Color(0xFFFF6B6B)
                                      : (warningsCount > 0 ? Colors.amberAccent : Colors.white54))
                                  .withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(3.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.circle_x,
                                  size: 10,
                                  color: errorsCount > 0 ? const Color(0xFFFF6B6B) : Colors.white38,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$errorsCount',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: errorsCount > 0 ? const Color(0xFFFF6B6B) : Colors.white60,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Icon(
                                  LucideIcons.triangle_alert,
                                  size: 10,
                                  color: warningsCount > 0 ? Colors.amberAccent : Colors.white38,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$warningsCount',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: warningsCount > 0 ? Colors.amberAccent : Colors.white60,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (hintsCount > 0 && !isUltraNarrow) ...[
                                  const SizedBox(width: 5),
                                  const Icon(
                                    LucideIcons.info,
                                    size: 10,
                                    color: Colors.cyanAccent,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$hintsCount',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: Colors.cyanAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: isNarrow ? 5 : 8),
                        // CPU & RAM: adaptive (mini bars on PC, compact on phone) → tap opens system sheet
                        _SystemStatsChip(compact: isNarrow, ultraCompact: isUltraNarrow),
                        SizedBox(width: isNarrow ? 5 : 8),
                        DeviceSelectorPill(compact: isNarrow),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // Right Side: File status, Cursor pos, Language & Encoding
                if (activeFile != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isNarrow) ...[
                        if (activeFile.isModified)
                          const _StatusBarPill(
                            icon: LucideIcons.circle_alert,
                            label: 'Не сохранено',
                            color: Colors.amberAccent,
                          )
                        else
                          const _StatusBarPill(
                            icon: LucideIcons.circle_check_big,
                            label: 'Сохранено',
                            color: Colors.greenAccent,
                          ),
                        const SizedBox(width: 8),
                      ] else if (activeFile.isModified) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.amberAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],

                      _StatusBarPill(
                        icon: isNarrow ? null : LucideIcons.navigation,
                        label: cursorLabel,
                        color: Colors.white70,
                      ),
                      SizedBox(width: isNarrow ? 5 : 8),

                      if (!isNarrow) ...[
                        const _StatusBarPill(
                          label: 'UTF-8',
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 8),
                      ],

                      // Language pill with genuine file/language icon from FileIconHelper
                      Builder(
                        builder: (context) {
                          final fileInfo = FileIconHelper.getIconInfo(p.basename(activeFile.path), false);
                          return _StatusBarPill(
                            icon: fileInfo.icon,
                            label: _getLanguageName(activeFile.path),
                            color: fileInfo.color,
                            maxWidth: isNarrow ? 68 : null,
                          );
                        },
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  (int, int, int) _getDiagnosticsCounts(Map<String, List<CodeDiagnostic>> allDiagnostics, String workspacePath) {
    int errors = 0;
    int warnings = 0;
    int hints = 0;
    allDiagnostics.forEach((filePath, list) {
      if (workspacePath.isEmpty || filePath.startsWith(workspacePath)) {
        for (final diag in list) {
          switch (diag.severity) {
            case CodeDiagnosticSeverity.error:
              errors++;
              break;
            case CodeDiagnosticSeverity.warning:
              warnings++;
              break;
            case CodeDiagnosticSeverity.hint:
              hints++;
              break;
          }
        }
      }
    });
    return (errors, warnings, hints);
  }

  String _getLanguageName(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.dart':
        return 'Dart';
      case '.js':
        return 'JavaScript';
      case '.ts':
        return 'TypeScript';
      case '.py':
        return 'Python';
      case '.json':
        return 'JSON';
      case '.yaml':
      case '.yml':
        return 'YAML';
      case '.md':
        return 'Markdown';
      case '.html':
        return 'HTML';
      case '.css':
        return 'CSS';
      default:
        return ext.isEmpty ? 'Plain Text' : ext.substring(1).toUpperCase();
    }
  }
}

class _SystemStatsChip extends ConsumerWidget {
  final bool compact;
  final bool ultraCompact;
  const _SystemStatsChip({required this.compact, required this.ultraCompact});

  static Color loadColor(double v) {
    if (v < 0.6) return Colors.cyanAccent;
    if (v < 0.85) return Colors.amberAccent;
    return const Color(0xFFFF6B6B);
  }

  Widget _miniBar(double value, Color color) {
    return Container(
      width: 26,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.02, 1.0),
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(systemStatsProvider);
    final cpuColor = loadColor(stats.cpuUsage);
    final gpuColor = loadColor(stats.gpuUsage);
    final ramColor = loadColor(stats.ramUsage);
    final worst = (stats.cpuUsage >= stats.ramUsage && stats.cpuUsage >= stats.gpuUsage)
        ? cpuColor
        : (stats.gpuUsage >= stats.ramUsage ? gpuColor : ramColor);
    final textStyle = GoogleFonts.jetBrainsMono(fontSize: 9.5, fontWeight: FontWeight.w600);

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _showSystemSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: worst.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(3.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.cpu, size: 10, color: cpuColor),
            const SizedBox(width: 3),
            Text('${(stats.cpuUsage * 100).toStringAsFixed(0)}%', style: textStyle.copyWith(color: cpuColor)),
            if (!compact) ...[
              const SizedBox(width: 4),
              _miniBar(stats.cpuUsage, cpuColor),
            ],
            if (!ultraCompact) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.zap, size: 10, color: gpuColor),
              const SizedBox(width: 3),
              Text('${(stats.gpuUsage * 100).toStringAsFixed(0)}%', style: textStyle.copyWith(color: gpuColor)),
              if (!compact) ...[
                const SizedBox(width: 4),
                _miniBar(stats.gpuUsage, gpuColor),
              ],
              const SizedBox(width: 6),
              Icon(LucideIcons.memory_stick, size: 10, color: ramColor),
              const SizedBox(width: 3),
              Text(
                stats.appRamFormatted,
                style: textStyle.copyWith(color: ramColor),
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                _miniBar(stats.ramUsage, ramColor),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showSystemSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12141B),
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _SystemSheet(),
    );
  }
}

class _SystemSheet extends ConsumerWidget {
  const _SystemSheet();

  Widget _row(String label, String value, double usage, IconData icon) {
    final color = _SystemStatsChip.loadColor(usage);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(value, style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usage.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(systemStatsProvider);
    final high = stats.cpuUsage > 0.85 || stats.ramUsage > 0.85;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(LucideIcons.activity, size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text('Ресурсы и Память', style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await ref.read(systemStatsProvider.notifier).freeBackgroundMemory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Фоновые демоны (Gradle/Kotlin/Analysis) остановлены, память очищена'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.sparkles, size: 13, color: Colors.cyanAccent),
                  label: Text(
                    'Очистить ОЗУ',
                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _row('Процессор (CPU)', '${(stats.cpuUsage * 100).toStringAsFixed(0)}%', stats.cpuUsage, LucideIcons.cpu),
            _row(
              'Видеоускоритель (${stats.gpuName})',
              '${(stats.gpuUsage * 100).toStringAsFixed(0)}%',
              stats.gpuUsage,
              LucideIcons.zap,
            ),
            _row(
              'Память Quantum IDE (App RAM)',
              stats.appRamFormatted,
              stats.ramUsage,
              LucideIcons.memory_stick,
            ),
            _row(
              'Память устройства (Свободно / Всего)',
              'Свободно ${stats.deviceRamAvailableGB.toStringAsFixed(1)} / ${stats.ramTotalGB.toStringAsFixed(1)} GB',
              stats.deviceRamUsage,
              LucideIcons.hard_drive,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (high ? const Color(0xFFFF6B6B) : Colors.greenAccent).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(high ? LucideIcons.triangle_alert : LucideIcons.circle_check,
                      size: 14, color: high ? const Color(0xFFFF6B6B) : Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      high
                          ? 'Высокая нагрузка. Нажмите «Очистить ОЗУ» выше, чтобы остановить фоновые демоны сборки Gradle/Kotlin.'
                          : 'Quantum IDE потребляет всего ${stats.appRamFormatted}. Остальная память занята системой Android и другими приложениями.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBarPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final double? maxWidth;

  const _StatusBarPill({
    this.icon,
    required this.label,
    this.color,
    this.onTap,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        fontSize: 10,
        color: color ?? Colors.white60,
        fontWeight: FontWeight.w500,
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
        decoration: BoxDecoration(
          color: (color ?? Colors.white54).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(3.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 9.5, color: color ?? Colors.white54),
              const SizedBox(width: 3),
            ],
            if (maxWidth != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth!),
                child: textWidget,
              )
            else
              textWidget,
          ],
        ),
      ),
    );
  }
}
