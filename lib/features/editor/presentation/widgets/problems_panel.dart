import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';

/// Compact, IDE-style problems list (sidebar version).
class ProblemsPanel extends ConsumerStatefulWidget {
  const ProblemsPanel({super.key});

  @override
  ConsumerState<ProblemsPanel> createState() => _ProblemsPanelState();
}

class _ProblemsPanelState extends ConsumerState<ProblemsPanel> {
  CodeDiagnosticSeverity? _filter;
  final Set<String> _collapsed = {};

  static (IconData, Color) _severityStyle(CodeDiagnosticSeverity s) {
    switch (s) {
      case CodeDiagnosticSeverity.error:
        return (LucideIcons.circle_x, const Color(0xFFFF6B6B));
      case CodeDiagnosticSeverity.warning:
        return (LucideIcons.triangle_alert, Colors.amberAccent);
      case CodeDiagnosticSeverity.hint:
        return (LucideIcons.info, Colors.cyanAccent);
    }
  }

  void _sendAllToAi(Map<String, List<CodeDiagnostic>> diagnosticsMap, String workspaceRoot) {
    final editorState = ref.read(editorProvider);
    final activePath = editorState.activeFilePath;
    final activeContent = activePath != null &&
            editorState.openFiles.isNotEmpty &&
            editorState.activeTabIndex < editorState.openFiles.length
        ? editorState.openFiles[editorState.activeTabIndex].controller.text
        : '';

    final buffer = StringBuffer();
    buffer.writeln('⚠️ **ОБНАРУЖЕНЫ ОШИБКИ В ПРОЕКТЕ. ПОЖАЛУЙСТА, ИСПРАВЬ ИХ И ОБНОВИ ФАЙЛЫ:**\n');
    diagnosticsMap.forEach((filePath, diags) {
      final relPath = filePath.startsWith(workspaceRoot) ? p.relative(filePath, from: workspaceRoot) : filePath;
      buffer.writeln('📄 Файл: `$relPath`');
      for (final d in diags) {
        buffer.writeln('- [${d.severity.name.toUpperCase()}] Стр ${d.range.index + 1}, Кол ${d.range.start + 1}: ${d.message}');
      }
    });
    if (activePath != null && activeContent.isNotEmpty) {
      final relActive = activePath.startsWith(workspaceRoot) ? p.relative(activePath, from: workspaceRoot) : activePath;
      buffer.writeln('\n### ТЕКУЩИЙ КОД ФАЙЛА (`$relActive`):\n```dart\n$activeContent\n```');
    }
    buffer.writeln('\n🔧 **ИНСТРУКЦИЯ**: Напиши ПОЛНЫЙ ИСПРАВЛЕННЫЙ КОД для данного файла и предложи изменения, чтобы полностью устранить все ошибки!');

    ref.read(aiProvider.notifier).askAI(buffer.toString());
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
  }

  void _fixOneWithAi(String relPath, CodeDiagnostic d) {
    ref.read(aiProvider.notifier).askAI(
          'Исправь ошибку в файле `$relPath` (стр ${d.range.index + 1}, кол ${d.range.start + 1}):\n'
          '[${d.severity.name.toUpperCase()}] ${d.message}',
        );
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final allDiagnostics = ref.watch(editorProvider.select((s) => s.allDiagnostics));
    final workspaceRoot = ref.watch(workspaceProvider.select((s) => s.currentPath ?? ''));
    final l10n = AppLocalizations.of(context)!;

    final diagnosticsMap = <String, List<CodeDiagnostic>>{};
    int errors = 0, warnings = 0, hints = 0;
    allDiagnostics.forEach((filePath, list) {
      if (list.isEmpty || workspaceRoot.isEmpty || !filePath.startsWith(workspaceRoot)) return;
      for (final d in list) {
        switch (d.severity) {
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
      final filtered = _filter == null ? list : list.where((d) => d.severity == _filter).toList();
      if (filtered.isNotEmpty) {
        diagnosticsMap[filePath] = List<CodeDiagnostic>.from(filtered)
          ..sort((a, b) {
            final s = a.severity.index.compareTo(b.severity.index);
            return s != 0 ? s : a.range.index.compareTo(b.range.index);
          });
      }
    });

    final total = errors + warnings + hints;
    final filePaths = diagnosticsMap.keys.toList()..sort((a, b) => p.basename(a).compareTo(p.basename(b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              const Icon(LucideIcons.circle_alert, size: 13, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                l10n.problemsList,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$total', style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.white60)),
                ),
              const Spacer(),
              if (diagnosticsMap.isNotEmpty)
                Tooltip(
                  message: l10n.sendToAi,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _sendAllToAi(diagnosticsMap, workspaceRoot),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.25), width: 0.6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.sparkles, size: 11, color: Colors.purpleAccent),
                          const SizedBox(width: 4),
                          Text('AI фикс',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Filter pills
        SizedBox(
          height: 28,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            children: [
              _pill('Все', total, null, Colors.white70),
              _pill('Ошибки', errors, CodeDiagnosticSeverity.error, const Color(0xFFFF6B6B)),
              _pill('Предупр.', warnings, CodeDiagnosticSeverity.warning, Colors.amberAccent),
              _pill('Инфо', hints, CodeDiagnosticSeverity.hint, Colors.cyanAccent),
            ],
          ),
        ),
        Divider(color: Colors.white.withValues(alpha: 0.06), height: 8),
        Expanded(
          child: diagnosticsMap.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.circle_check, size: 30, color: Colors.greenAccent.withValues(alpha: 0.45)),
                      const SizedBox(height: 8),
                      Text(
                        l10n.noProblemsFound,
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: filePaths.length,
                  itemBuilder: (context, i) {
                    final filePath = filePaths[i];
                    final diags = diagnosticsMap[filePath]!;
                    final relPath = p.relative(filePath, from: workspaceRoot);
                    final dir = p.dirname(relPath);
                    final isCollapsed = _collapsed.contains(filePath);
                    final iconInfo = FileIconHelper.getIconInfo(p.basename(filePath), false);
                    final fileErrors = diags.where((d) => d.severity == CodeDiagnosticSeverity.error).length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InkWell(
                          onTap: () => setState(() {
                            isCollapsed ? _collapsed.remove(filePath) : _collapsed.add(filePath);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Icon(isCollapsed ? LucideIcons.chevron_right : LucideIcons.chevron_down,
                                    size: 12, color: Colors.white38),
                                const SizedBox(width: 4),
                                Icon(iconInfo.icon, size: 13, color: iconInfo.color),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    p.basename(filePath),
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (dir != '.') ...[
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(dir,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white30)),
                                  ),
                                ] else
                                  const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: (fileErrors > 0 ? const Color(0xFFFF6B6B) : Colors.amberAccent)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${diags.length}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: fileErrors > 0 ? const Color(0xFFFF6B6B) : Colors.amberAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (!isCollapsed) ...diags.map((d) => _diagRow(filePath, relPath, d)),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _pill(String label, int count, CodeDiagnosticSeverity? severity, Color color) {
    final selected = _filter == severity;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _filter = severity),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.06),
              width: 0.7,
            ),
          ),
          child: Text(
            '$label $count',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: selected ? color : Colors.white54,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _diagRow(String filePath, String relPath, CodeDiagnostic d) {
    final (icon, color) = _severityStyle(d.severity);
    final line = d.range.index + 1;
    final col = d.range.start + 1;
    return InkWell(
      onTap: () => ref.read(editorProvider.notifier).openFile(filePath, line: d.range.index, column: d.range.start),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 3, 4, 3),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color.withValues(alpha: 0.5), width: 2)),
        ),
        margin: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Icon(icon, size: 11.5, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                d.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.85), height: 1.25),
              ),
            ),
            const SizedBox(width: 4),
            Text('$line:$col', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white30)),
            _miniIcon(LucideIcons.copy, 'Копировать', () {
              Clipboard.setData(ClipboardData(text: '$relPath:$line:$col  ${d.message}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скопировано'), duration: Duration(milliseconds: 900)),
              );
            }),
            _miniIcon(LucideIcons.sparkles, 'Исправить с AI', () => _fixOneWithAi(relPath, d), color: Colors.purpleAccent),
          ],
        ),
      ),
    );
  }

  Widget _miniIcon(IconData icon, String tooltip, VoidCallback onTap, {Color color = Colors.white38}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}
