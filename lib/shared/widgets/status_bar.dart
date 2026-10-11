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
        child: Row(
          children: [
            // Left Side: Git & Diagnostics & CPU/RAM
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (gitState.status != null) ...[
                      _StatusBarPill(
                        icon: LucideIcons.git_branch,
                        label: gitState.status!.currentBranch,
                        color: Colors.cyanAccent,
                        onTap: () {
                          ref.read(panelProvider.notifier).selectTab(PanelTab.git);
                        },
                      ),
                      const SizedBox(width: 8),
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
                            const SizedBox(width: 6),
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
                            if (hintsCount > 0) ...[
                              const SizedBox(width: 6),
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
                    const SizedBox(width: 8),
                    // CPU & RAM: Icons and numbers only (🔲 cpu%  💾 ram)
                    Consumer(
                      builder: (context, ref, _) {
                        final stats = ref.watch(systemStatsProvider);
                        final cpuPercent = (stats.cpuUsage * 100).toStringAsFixed(0);
                        final ramGB = stats.ramUsedGB.toStringAsFixed(1);
                        final isHigh = stats.cpuUsage > 0.85 || stats.ramUsage > 0.85;
                        final isMed = stats.cpuUsage > 0.6 || stats.ramUsage > 0.6;
                        final color = isHigh ? const Color(0xFFFF6B6B) : (isMed ? Colors.amberAccent : Colors.cyanAccent);
                        return InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            ref.read(panelProvider.notifier).selectTab(PanelTab.run);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(3.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.cpu, size: 10, color: color),
                                const SizedBox(width: 3),
                                Text(
                                  '$cpuPercent%',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(LucideIcons.server, size: 10, color: color),
                                const SizedBox(width: 3),
                                Text(
                                  '${ramGB}G',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Right Side: File status, Cursor pos, Language & Encoding
            if (activeFile != null) ...[
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
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
                      const SizedBox(width: 10),

                      _StatusBarPill(
                        icon: LucideIcons.navigation,
                        label: pos != null
                            ? AppLocalizations.of(context)!.lineCol(pos.index + 1, pos.offset + 1)
                            : AppLocalizations.of(context)!.lineCol(1, 1),
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 10),

                      const _StatusBarPill(
                        label: 'UTF-8',
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 10),

                      // Language pill with genuine file/language icon from FileIconHelper
                      Builder(
                        builder: (context) {
                          final fileInfo = FileIconHelper.getIconInfo(p.basename(activeFile.path), false);
                          return _StatusBarPill(
                            icon: fileInfo.icon,
                            label: _getLanguageName(activeFile.path),
                            color: fileInfo.color,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
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

class _StatusBarPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const _StatusBarPill({
    this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: color ?? Colors.white60,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
