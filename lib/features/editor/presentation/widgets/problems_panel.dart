import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/analysis_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/lsp_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
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

  static String _getRussianErrorExplanation(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('undefined name') || lower.contains("isn't defined")) {
      return 'Переменная, метод или класс не найдены. Возможно, не подключен нужный import или допущена опечатка в названии.';
    }
    if (lower.contains("expected to find ';'") || (lower.contains('expected to find') && lower.contains(';'))) {
      return 'Синтаксическая ошибка: пропущена точка с запятой «;» в конце инструкции.';
    }
    if (lower.contains('the named parameter') && lower.contains('is required')) {
      return 'Пропущен обязательный именованный параметр. Конструктор этого виджета требует передачи всех обязательных полей.';
    }
    if (lower.contains("can't be assigned to the parameter type") || lower.contains('type mismatch')) {
      return 'Несоответствие типов: передан аргумент другого типа данных. Проверьте ожидаемый тип в сигнатуре функции/виджета.';
    }
    if (lower.contains('dead code')) {
      return 'Мёртвый код: этот блок кода никогда не выполнится (например, он расположен после оператора return, break или throw).';
    }
    if (lower.contains('unused import')) {
      return 'Лишний импорт: этот файл или библиотека подключены, но нигде не используются в коде.';
    }
    if (lower.contains('cannot be null') || lower.contains('null safety') || lower.contains('nullable')) {
      return 'Ошибка Null Safety: значение может оказаться null, хотя тип ожидает гарантированное значение (используйте ? или проверку if != null).';
    }
    if (lower.contains('must be initialized') || lower.contains('not initialized')) {
      return 'Переменная не инициализирована: добавьте начальное значение или пометьте её как late.';
    }
    if (lower.contains('too many positional arguments') || lower.contains('too few positional arguments')) {
      return 'Неверное количество позиционных аргументов: функции или конструктору передано больше или меньше параметров, чем объявлено.';
    }
    return 'Компилятор Dart/Flutter обнаружил несоответствие в коде. Нажмите «Исправить с AI», чтобы автоматически применить корректное точечное исправление.';
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
    buffer.writeln('⚠️ **ОБНАРУЖЕНЫ ОШИБКИ В ПРОЕКТЕ. ПОЖАЛУЙСТА, ИСПРАВЬ ИХ ТОЧЕЧНО:**\n');
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
    buffer.writeln('\n🔧 **ИНСТРУКЦИЯ**: Используй блоки точечной замены SEARCH/REPLACE (<<<<<<< SEARCH ... ======= ... >>>>>>>), чтобы устранить ошибки!');

    ref.read(aiProvider.notifier).askAI(buffer.toString());
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
  }

  void _fixOneWithAi(String filePath, String relPath, CodeDiagnostic d) {
    String contextLines = '';
    try {
      final f = File(filePath);
      if (f.existsSync()) {
        final lines = f.readAsLinesSync();
        final errLine = d.range.index;
        final startLine = (errLine - 4).clamp(0, lines.length);
        final endLine = (errLine + 5).clamp(0, lines.length);
        contextLines = lines.sublist(startLine, endLine).join('\n');
      }
    } catch (_) {}

    final buffer = StringBuffer();
    buffer.writeln('Исправь точечно ошибку в файле `$relPath` (строка ${d.range.index + 1}, колонка ${d.range.start + 1}):');
    buffer.writeln('Тип ошибки: [${d.severity.name.toUpperCase()}] ${d.message}');
    if (contextLines.isNotEmpty) {
      buffer.writeln('\nКонтекст кода вокруг строки ошибки:');
      buffer.writeln('```dart\n$contextLines\n```');
    }
    buffer.writeln('\nОБЯЗАТЕЛЬНО используй точечную замену кода через блок SEARCH/REPLACE:');
    buffer.writeln('<<<<<<< SEARCH');
    buffer.writeln('// точный фрагмент текущего кода');
    buffer.writeln('=======');
    buffer.writeln('// исправленный фрагмент');
    buffer.writeln('>>>>>>>');

    ref.read(aiProvider.notifier).askAI(buffer.toString());
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
  }

  void _showErrorQuickFixDialog(BuildContext context, String filePath, String relPath, CodeDiagnostic d) {
    final (icon, color) = _severityStyle(d.severity);
    final explanation = _getRussianErrorExplanation(d.message);
    final line = d.range.index + 1;
    final col = d.range.start + 1;

    String errorLineCode = '';
    try {
      final f = File(filePath);
      if (f.existsSync()) {
        final lines = f.readAsLinesSync();
        if (d.range.index >= 0 && d.range.index < lines.length) {
          errorLineCode = lines[d.range.index].trim();
        }
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.severity.name.toUpperCase()} (Строка $line:$col)',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    relPath,
                    style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Error text box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                ),
                child: Text(
                  d.message,
                  style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              // Code snippet if available
              if (errorLineCode.isNotEmpty) ...[
                Text(
                  'КОД НА СТРОКЕ $line:',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    errorLineCode,
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.amberAccent),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Plain-Russian explanation
              Row(
                children: [
                  const Icon(LucideIcons.book_open, size: 14, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Text(
                    'ОБЪЯСНЕНИЕ ПРОСТЫМИ СЛОВАМИ:',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                ),
                child: Text(
                  explanation,
                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$relPath:$line:$col  ${d.message}'));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Текст ошибки скопирован')),
              );
            },
            icon: const Icon(LucideIcons.copy, size: 13),
            label: const Text('Копировать', style: TextStyle(fontSize: 11)),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(editorProvider.notifier).openFile(filePath, line: d.range.index, column: d.range.start);
            },
            icon: const Icon(LucideIcons.external_link, size: 13),
            label: const Text('Перейти', style: TextStyle(fontSize: 11)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _fixOneWithAi(filePath, relPath, d);
            },
            icon: const Icon(LucideIcons.sparkles, size: 14),
            label: const Text('💡 Исправить с ИИ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
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
                    color: (errors > 0
                            ? const Color(0xFFFF6B6B)
                            : (warnings > 0 ? Colors.amberAccent : Colors.white))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    errors + warnings > 0 ? '${errors + warnings}' : '$hints инфо',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      color: errors > 0
                          ? const Color(0xFFFF6B6B)
                          : (warnings > 0 ? Colors.amberAccent : Colors.white60),
                    ),
                  ),
                ),
              const Spacer(),
              Tooltip(
                message: 'Обновить диагностики (LSP)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final lsp = ref.read(lspServiceProvider);
                    final openFiles = ref.read(editorProvider).openFiles;
                    for (final f in openFiles) {
                      try {
                        final diags = await lsp.getDiagnostics(f.path);
                        ref.read(editorProvider.notifier).updateDiagnostics(f.path, diags);
                      } catch (_) {}
                    }
                    ref.read(analysisServiceProvider).triggerAnalysis(immediate: true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(LucideIcons.refresh_cw, size: 12, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                ),
              ),
              if (total > 0) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Очистить список диагностик',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      ref.read(editorProvider.notifier).clearDiagnostics();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(LucideIcons.trash_2, size: 12, color: Colors.white.withValues(alpha: 0.55)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
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
        // Missing dependencies hint banner
        if (diagnosticsMap.values.any((list) => list.any((d) =>
            d.message.toLowerCase().contains("target of uri doesn't exist") ||
            d.message.toLowerCase().contains("uri") ||
            d.message.toLowerCase().contains("pub get"))))
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.package_search, size: 14, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Не найдены зависимости проекта. Запустите:',
                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.amberAccent, fontWeight: FontWeight.w500),
                  ),
                ),
                InkWell(
                  onTap: () {
                    ref.read(terminalTabsProvider.notifier).sendCommand('flutter pub get\n');
                    ref.read(panelProvider.notifier).selectTab(PanelTab.terminal);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'flutter pub get',
                      style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
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
            _miniIcon(LucideIcons.lightbulb, 'Объяснение и Quick-Fix', () => _showErrorQuickFixDialog(context, filePath, relPath, d), color: Colors.amberAccent),
            _miniIcon(LucideIcons.sparkles, 'Исправить с AI', () => _fixOneWithAi(filePath, relPath, d), color: Colors.purpleAccent),
            _miniIcon(LucideIcons.copy, 'Копировать', () {
              Clipboard.setData(ClipboardData(text: '$relPath:$line:$col  ${d.message}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скопировано'), duration: Duration(milliseconds: 900)),
              );
            }),
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
