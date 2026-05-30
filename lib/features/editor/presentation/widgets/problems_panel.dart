import 'package:flutter/material.dart';
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

class ProblemsPanel extends ConsumerWidget {
  const ProblemsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorProvider);
    final workspaceRoot = ref.watch(workspaceProvider).currentPath ?? '';
    final l10n = AppLocalizations.of(context)!;

    // Filter files that have diagnostics (only for files in current workspace)
    final diagnosticsMap = <String, List<CodeDiagnostic>>{};
    editorState.allDiagnostics.forEach((filePath, list) {
      if (list.isNotEmpty) {
        final isInWorkspace = workspaceRoot.isNotEmpty && filePath.startsWith(workspaceRoot);
        if (isInWorkspace) {
          diagnosticsMap[filePath] = list;
        }
      }
    });

    if (diagnosticsMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circle_check, size: 40, color: Colors.greenAccent.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              l10n.noProblemsFound,
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    // List of keys (files) sorted by name
    final filePaths = diagnosticsMap.keys.toList()
      ..sort((a, b) => p.basename(a).compareTo(p.basename(b)));


    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
          child: Row(
            children: [
              const Icon(LucideIcons.circle_alert, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                l10n.problemsList,
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (diagnosticsMap.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    final buffer = StringBuffer();
                    buffer.writeln(l10n.helpMeFixErrors);
                    diagnosticsMap.forEach((filePath, diags) {
                      final relPath = workspaceRoot.isNotEmpty && filePath.startsWith(workspaceRoot)
                          ? p.relative(filePath, from: workspaceRoot)
                          : filePath;
                      buffer.writeln('\n📄 File: $relPath');
                      for (final d in diags) {
                        final severity = d.severity.name.toUpperCase();
                        final line = d.range.index + 1;
                        final column = d.range.start + 1;
                        buffer.writeln('- [$severity] Line $line, Column $column: ${d.message}');
                      }
                    });
                    ref.read(aiProvider.notifier).askAI(buffer.toString());
                    ref.read(rightChatPanelOpenProvider.notifier).state = true;
                  },
                  icon: const Icon(LucideIcons.sparkles, size: 12, color: Colors.purpleAccent),
                  label: Text(
                    l10n.sendToAi,
                    style: const TextStyle(color: Colors.purpleAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.purpleAccent.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: filePaths.length,
            itemBuilder: (context, fileIndex) {
              final filePath = filePaths[fileIndex];
              final fileName = p.basename(filePath);
              final relPath = workspaceRoot.isNotEmpty && filePath.startsWith(workspaceRoot)
                  ? p.relative(filePath, from: workspaceRoot)
                  : filePath;
              
              final diagnostics = diagnosticsMap[filePath]!;
              
              // Sort diagnostics inside file: Errors first, then Warnings, then Info/Hints
              final sortedDiagnostics = List<CodeDiagnostic>.from(diagnostics)
                ..sort((a, b) => a.severity.index.compareTo(b.severity.index));

              return ExpansionTile(
                initiallyExpanded: true,
                title: Row(
                  children: [
                    Text(
                      fileName,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.dirname(relPath),
                        style: GoogleFonts.inter(color: Colors.white30, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${diagnostics.length}',
                        style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                iconColor: Colors.white30,
                collapsedIconColor: Colors.white30,
                children: sortedDiagnostics.map((diagnostic) {
                  final IconData icon;
                  final Color iconColor;
                  
                  switch (diagnostic.severity) {
                    case CodeDiagnosticSeverity.error:
                      icon = LucideIcons.circle_x;
                      iconColor = Colors.redAccent;
                      break;
                    case CodeDiagnosticSeverity.warning:
                      icon = LucideIcons.triangle_alert;
                      iconColor = Colors.orangeAccent;
                      break;
                    case CodeDiagnosticSeverity.hint:
                      icon = LucideIcons.info;
                      iconColor = Colors.cyanAccent;
                      break;
                  }

                  final line = diagnostic.range.index + 1;
                  final column = diagnostic.range.start + 1;

                  return InkWell(
                    onTap: () {
                      ref.read(editorProvider.notifier).openFile(
                        filePath,
                        line: diagnostic.range.index,
                        column: diagnostic.range.start,
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Icon(icon, size: 13, color: iconColor),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  diagnostic.message,
                                  style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.87), fontSize: 11.5),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.lineColumn(line, column),
                                  style: GoogleFonts.inter(color: Colors.white24, fontSize: 9.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
