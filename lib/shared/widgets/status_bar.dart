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
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12141B),
      constraints: BoxConstraints(
        maxWidth: 680,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => const _SystemSheet(),
    );
  }
}

class _SystemSheet extends ConsumerStatefulWidget {
  const _SystemSheet();

  @override
  ConsumerState<_SystemSheet> createState() => _SystemSheetState();
}

class _SystemSheetState extends ConsumerState<_SystemSheet> {
  int _selectedTab = 0; // 0: Процессы и пакеты, 1: Производительность
  String _selectedCategory = 'Все';

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'IDE':
        return LucideIcons.code;
      case 'Сборка':
        return LucideIcons.package;
      case 'Компилятор':
        return LucideIcons.binary;
      case 'Языковой сервер':
        return LucideIcons.file_code;
      case 'Песочница':
        return LucideIcons.box;
      case 'Среда выполнения':
        return LucideIcons.cpu;
      case 'ИИ / Агент':
      case 'ИИ / Нейросеть':
        return LucideIcons.sparkles;
      case 'Терминал':
        return LucideIcons.terminal;
      case 'Упаковка':
        return LucideIcons.archive;
      default:
        return LucideIcons.activity;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'IDE':
        return Colors.cyanAccent;
      case 'Сборка':
        return Colors.amberAccent;
      case 'Компилятор':
        return Colors.orangeAccent;
      case 'Языковой сервер':
        return Colors.lightBlueAccent;
      case 'Песочница':
        return Colors.purpleAccent;
      case 'Среда выполнения':
        return Colors.greenAccent;
      case 'ИИ / Агент':
      case 'ИИ / Нейросеть':
        return Colors.pinkAccent;
      case 'Терминал':
        return Colors.tealAccent;
      default:
        return Colors.white70;
    }
  }

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
  Widget build(BuildContext context) {
    final stats = ref.watch(systemStatsProvider);
    final high = stats.cpuUsage > 0.85 || stats.ramUsage > 0.85;

    // Filter processes by category
    final processes = stats.processes.where((p) {
      if (_selectedCategory == 'Все') return true;
      return p.category == _selectedCategory;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
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
            const SizedBox(height: 12),

            // ── Header (Windows Task Manager style) ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.activity, size: 18, color: Colors.cyanAccent),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Диспетчер задач Quantum IDE',
                      style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Мониторинг процессов и пакетов в реальном времени',
                      style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white38),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Обновить данные',
                  onPressed: () => ref.read(systemStatsProvider.notifier).refreshNow(),
                  icon: const Icon(LucideIcons.refresh_cw, size: 15, color: Colors.white70),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await ref.read(systemStatsProvider.notifier).freeBackgroundMemory();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Фоновые демоны сборки (Gradle/Kotlin/Dart) остановлены, ОЗУ очищено'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.sparkles, size: 13, color: Colors.cyanAccent),
                  label: Text(
                    'Очистить ОЗУ',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Navigation Tabs: Процессы и пакеты | Производительность ──
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _selectedTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0 ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.list,
                              size: 14,
                              color: _selectedTab == 0 ? Colors.cyanAccent : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Процессы и пакеты (${stats.processes.length})',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: _selectedTab == 0 ? FontWeight.bold : FontWeight.w500,
                                color: _selectedTab == 0 ? Colors.white : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1 ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.gauge,
                              size: 14,
                              color: _selectedTab == 1 ? Colors.cyanAccent : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Производительность',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: _selectedTab == 1 ? FontWeight.bold : FontWeight.w500,
                                color: _selectedTab == 1 ? Colors.white : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Content View ──
            if (_selectedTab == 0) ...[
              // Quick category chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'Все',
                    'Сборка',
                    'Компилятор',
                    'Языковой сервер',
                    'ИИ / Агент',
                    'Песочница',
                    'Терминал',
                  ].map((cat) {
                    final isSel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSel ? Colors.cyanAccent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSel ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            cat,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: isSel ? Colors.cyanAccent : Colors.white60,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),

              // Table header (Windows Task Manager style)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text('ИМЯ ПРОЦЕССА / ПАКЕТА', style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white38, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('ЦП (CPU)', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white38, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('ПАМЯТЬ', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white38, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(width: 24), // Space for action button
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Processes List
              Flexible(
                child: processes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Нет активных процессов в данной категории',
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: processes.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.04)),
                        itemBuilder: (context, idx) {
                          final proc = processes[idx];
                          final isSelf = proc.pid == pid;
                          final catColor = _getCategoryColor(proc.category);
                          final catIcon = _getCategoryIcon(proc.category);
                          final cpuColor = _SystemStatsChip.loadColor(proc.cpuPercent / 100.0);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: Row(
                              children: [
                                // Process Icon
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(catIcon, size: 14, color: catColor),
                                ),
                                const SizedBox(width: 10),

                                // Process Name & Description
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              proc.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (isSelf) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.cyanAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text('Это приложение', style: GoogleFonts.inter(fontSize: 8, color: Colors.cyanAccent)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        proc.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white38),
                                      ),
                                    ],
                                  ),
                                ),

                                // CPU Column
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${proc.cpuPercent.toStringAsFixed(1)}%',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: cpuColor,
                                    ),
                                  ),
                                ),

                                // RAM Column
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    proc.ramFormatted,
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // End Task Action Button
                                if (!isSelf)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () async {
                                      await ref.read(systemStatsProvider.notifier).killProcess(proc.pid);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Процесс ${proc.name} (PID: ${proc.pid}) завершен'),
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(LucideIcons.x, size: 13, color: Colors.redAccent),
                                    ),
                                  )
                                else
                                  const SizedBox(width: 23),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ] else ...[
              // Tab 1: Производительность (Hardware gauges)
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
                            ? 'Высокая нагрузка на процессор или память. Перейдите во вкладку «Процессы и пакеты» выше, чтобы увидеть или завершить нагружающий процесс.'
                            : 'Система работает стабильно. Quantum IDE потребляет всего ${stats.appRamFormatted}. Остальная память распределена между ОС Android и системными сервисами.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
