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
import 'package:quantum_ide/l10n/app_localizations.dart';

// Используем ConsumerStatefulWidget, чтобы управлять подпиской на контроллер
// вручную — без ValueListenableBuilder, который вызывает setState во время
// фазы сборки (initState → delegate= → notifyListeners → ValueListenable._valueChanged → crash).
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
    // Откладываем setState на следующий фрейм, чтобы не конфликтовать
    // с фазой сборки (именно это и было причиной падения).
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

    // Обновляем подписку при смене активного файла (без setState —
    // если контроллер тот же, _switchController — no-op).
    _switchController(activeFile?.controller);

    final workspacePath = ref.watch(workspaceProvider).currentPath ?? '';
    final pos = _cursorValue?.selection.extent;

    return RepaintBoundary(
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF181A1F),
          border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
        ),
        child: Row(
          children: [
            // Git branch & Problems (Left Side)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (gitState.status != null) ...[
                      _StatusBarItem(
                        icon: LucideIcons.git_branch,
                        label: gitState.status!.currentBranch,
                        onTap: () {
                          ref
                              .read(panelProvider.notifier)
                              .selectTab(PanelTab.git);
                        },
                      ),
                      const SizedBox(width: 16),
                    ],
                    _StatusBarItem(
                      icon: LucideIcons.circle_alert,
                      label:
                          '${_getTotalErrors(editorState.allDiagnostics, workspacePath)}',
                      color: _getTotalErrors(editorState.allDiagnostics, workspacePath) > 0
                          ? Colors.redAccent
                          : Colors.white38,
                      onTap: () {
                        ref
                            .read(panelProvider.notifier)
                            .selectTab(PanelTab.problems);
                      },
                    ),
                  ],
                ),
              ),
            ),
  
            const SizedBox(width: 8),
  
            // File status, Cursor pos, Language (Right Side)
            if (activeFile != null) ...[
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (activeFile.isModified)
                        _StatusBarItem(
                          icon: LucideIcons.circle_alert,
                          label: AppLocalizations.of(context)!.unsaved,
                          color: Colors.amberAccent,
                        )
                      else
                        _StatusBarItem(
                          icon: LucideIcons.circle_check_big,
                          label: AppLocalizations.of(context)!.saved,
                          color: Colors.greenAccent,
                        ),
                      const SizedBox(width: 16),
  
                      // Cursor position — безопасно через State, не через
                      // ValueListenableBuilder (который падал во время initState).
                      _StatusBarItem(
                        label: pos != null
                            ? AppLocalizations.of(context)!.lineCol(pos.index + 1, pos.offset + 1)
                            : AppLocalizations.of(context)!.lineCol(1, 1),
                      ),
                      const SizedBox(width: 16),
  
                      // Language
                      _StatusBarItem(
                        label: _getLanguageName(activeFile.path),
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

  int _getTotalErrors(Map<String, List<dynamic>> allDiagnostics, String workspacePath) {
    int total = 0;
    allDiagnostics.forEach((filePath, list) {
      if (workspacePath.isNotEmpty && filePath.startsWith(workspacePath)) {
        total += list.length;
      }
    });
    return total;
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

class _StatusBarItem extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const _StatusBarItem({
    this.icon,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color ?? Colors.white54),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: color ?? Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
