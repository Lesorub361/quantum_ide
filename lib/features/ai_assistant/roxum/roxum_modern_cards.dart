import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class RoxumThinkingCard extends StatefulWidget {
  final String reasoningText;
  final int durationMs;
  final bool isStreaming;
  final Color surfaceColor;
  final Color textColor;

  const RoxumThinkingCard({
    super.key,
    required this.reasoningText,
    required this.durationMs,
    required this.isStreaming,
    required this.surfaceColor,
    required this.textColor,
  });

  @override
  State<RoxumThinkingCard> createState() => _RoxumThinkingCardState();
}

class _RoxumThinkingCardState extends State<RoxumThinkingCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = ThemeData.estimateBrightnessForColor(widget.surfaceColor) ==
        Brightness.dark;
    final thinkAccent =
        isDark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9);
    final sec = (widget.durationMs / 1000).toStringAsFixed(1);
    final label = widget.isStreaming && widget.reasoningText.isNotEmpty
        ? l10n.thinkingNow
        : (widget.durationMs > 0
            ? '${l10n.thinkingAgent} · ${sec}s'
            : l10n.thinkingAgent);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: thinkAccent.withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.brain,
                    size: 14,
                    color: thinkAccent,
                  )
                      .animate(
                        onPlay: (c) => widget.isStreaming ? c.repeat() : c.stop(),
                      )
                      .shimmer(
                        duration: 1200.ms,
                        color: widget.textColor.withValues(alpha: 0.45),
                      ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: thinkAccent,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: widget.textColor.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
          ),
          if ((_expanded || widget.isStreaming) &&
              widget.reasoningText.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                widget.reasoningText,
                maxLines: _expanded ? null : 3,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: widget.textColor.withValues(alpha: 0.75),
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms);
  }
}

class RoxumAgentTimeline extends StatefulWidget {
  final List<RoxumToolCallRecord> toolCalls;
  final Color surfaceColor;
  final Color textColor;

  const RoxumAgentTimeline({
    super.key,
    required this.toolCalls,
    required this.surfaceColor,
    required this.textColor,
  });

  @override
  State<RoxumAgentTimeline> createState() => _RoxumAgentTimelineState();
}

class _RoxumAgentTimelineState extends State<RoxumAgentTimeline> {
  final Set<String> _expandedIds = {};
  bool _exploredExpanded = false;

  static const _exploreTools = {
    'activeEditorFile',
    'currentlySelectedText',
    'getLspDiagnostics',
    'readFile',
    'readFilesBatch',
    'listFiles',
    'globSearchFiles',
    'grepInFiles',
    'searchInFiles',
    'getFileInfo',
  };

  @override
  Widget build(BuildContext context) {
    if (widget.toolCalls.isEmpty) return const SizedBox.shrink();

    final exploreCalls = <RoxumToolCallRecord>[];
    final actionCalls = <RoxumToolCallRecord>[];
    for (final tc in widget.toolCalls) {
      if (_exploreTools.contains(tc.name) && !tc.isRunning) {
        exploreCalls.add(tc);
      } else {
        actionCalls.add(tc);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (exploreCalls.isNotEmpty) _buildExploredGroup(exploreCalls),
          for (final tc in actionCalls) _buildActionStep(tc),
        ],
      ),
    );
  }

  Widget _buildExploredGroup(List<RoxumToolCallRecord> calls) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: widget.surfaceColor.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.textColor.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _exploredExpanded = !_exploredExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.search,
                    size: 13.5,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${AppLocalizations.of(context)!.exploredLabel} · ${calls.length}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  Icon(
                    _exploredExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: widget.textColor.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          if (_exploredExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: calls.map((tc) {
                  final target = tc.arguments['filePath'] ??
                      tc.arguments['query'] ??
                      tc.arguments['pattern'] ??
                      tc.arguments['directoryPath'] ??
                      '';
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          tc.success ? Icons.check : Icons.error_outline,
                          size: 12,
                          color: tc.success
                              ? const Color(0xFF22C55E)
                              : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${tc.name}${target.toString().isNotEmpty ? ': $target' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: widget.textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 160.ms);
  }

  Widget _buildActionStep(RoxumToolCallRecord tc) {
    final isExpanded = _expandedIds.contains(tc.id);
    final isShell = tc.name == 'runCommand' || tc.name.startsWith('git');
    final isMcp = tc.name.startsWith('mcp__');
    final isEdit = const {
      'writeFile',
      'editFile',
      'insertAtLine',
      'replaceAllInFile',
    }.contains(tc.name);

    final label = _formatActionLabel(tc);
    final accent = tc.isRunning
        ? const Color(0xFF38BDF8)
        : (tc.success
            ? (isMcp ? const Color(0xFFA78BFA) : const Color(0xFF22C55E))
            : Colors.redAccent);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: tc.output.isEmpty
                ? null
                : () => setState(() {
                      if (isExpanded) {
                        _expandedIds.remove(tc.id);
                      } else {
                        _expandedIds.add(tc.id);
                      }
                    }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  if (tc.isRunning)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  else
                    Icon(
                      isShell
                          ? LucideIcons.terminal
                          : (isMcp
                              ? LucideIcons.blocks
                              : (isEdit
                                  ? LucideIcons.file_pen
                                  : Icons.check_circle_outline)),
                      size: 14,
                      color: accent,
                    ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: isShell
                          ? GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: widget.textColor,
                            )
                          : TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: widget.textColor,
                            ),
                    ),
                  ),
                  if (!tc.isRunning)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        tc.success ? 'OK' : 'ERR',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  if (tc.output.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 15,
                      color: widget.textColor.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isExpanded && tc.output.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 9),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: widget.textColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: SelectableText(
                tc.output.length > 1500
                    ? '${tc.output.substring(0, 1500)}\n... [truncated]'
                    : tc.output,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  height: 1.38,
                  color: widget.textColor.withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: 0.05, end: 0);
  }

  String _formatActionLabel(RoxumToolCallRecord tc) {
    if (tc.name == 'runCommand') {
      return '\$ ${tc.arguments['command'] ?? ''}';
    }
    if (tc.name.startsWith('mcp__')) {
      final parts = tc.name.split('__');
      final srv = parts.length > 1 ? parts[1] : 'mcp';
      final fn = parts.length > 2 ? parts.sublist(2).join('_') : tc.name;
      return 'MCP [$srv] · $fn';
    }
    final fp = tc.arguments['filePath']?.toString();
    if (fp != null && fp.isNotEmpty) {
      return '${tc.name} · ${p.basename(fp)}';
    }
    return tc.name;
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'шаг';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'шага';
    }
    return 'шагов';
  }
}

class RoxumFileDiffCard extends StatefulWidget {
  final RoxumPendingEdit edit;
  final bool isPending;
  final Color surfaceColor;
  final Color textColor;
  final VoidCallback? onOpenFile;
  final VoidCallback? onKeep;
  final VoidCallback? onUndo;

  const RoxumFileDiffCard({
    super.key,
    required this.edit,
    required this.isPending,
    required this.surfaceColor,
    required this.textColor,
    this.onOpenFile,
    this.onKeep,
    this.onUndo,
  });

  @override
  State<RoxumFileDiffCard> createState() => _RoxumFileDiffCardState();
}

class _RoxumFileDiffCardState extends State<RoxumFileDiffCard> {
  bool _showAllLines = false;
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final diffLines = _computeDiffLines(
      widget.edit.originalContent,
      widget.edit.updatedContent,
    );
    final visibleLines =
        _showAllLines ? diffLines : diffLines.take(16).toList();
    final hiddenCount = diffLines.length - visibleLines.length;

    final isDark = ThemeData.estimateBrightnessForColor(widget.surfaceColor) ==
        Brightness.dark;
    final insertFg =
        isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);
    final deleteFg =
        isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.surfaceColor,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: widget.isPending
              ? const Color(0xFF38BDF8).withValues(alpha: 0.45)
              : widget.textColor.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: widget.surfaceColor,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(10),
                  bottom: _collapsed ? const Radius.circular(10) : Radius.zero,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.file_diff,
                    size: 14,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onOpenFile,
                      child: Text(
                        p.basename(widget.edit.filePath),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF38BDF8),
                          decoration: widget.onOpenFile != null
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  ),
                  _statPill('+${widget.edit.addedLines}', const Color(0xFF22C55E)),
                  const SizedBox(width: 4),
                  _statPill('-${widget.edit.removedLines}', Colors.redAccent),
                  if (widget.isPending) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: widget.onUndo,
                      child: Tooltip(
                        message: AppLocalizations.of(context)!.revertFile,
                        child: const Icon(
                          Icons.undo,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: widget.onKeep,
                      child: Tooltip(
                        message: AppLocalizations.of(context)!.acceptFile,
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Color(0xFF22C55E),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!_collapsed) ...[
            if (visibleLines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  widget.edit.existedBefore
                      ? 'Файл обновлён без текстовых отличий'
                      : 'Создан новый файл',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.textColor.withValues(alpha: 0.6),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: visibleLines.map((dl) {
                    final bg = switch (dl.op) {
                      DIFF_INSERT =>
                        const Color(0xFF22C55E).withValues(alpha: 0.14),
                      DIFF_DELETE => Colors.redAccent.withValues(alpha: 0.14),
                      _ => Colors.transparent,
                    };
                    final prefix = switch (dl.op) {
                      DIFF_INSERT => '+',
                      DIFF_DELETE => '-',
                      _ => ' ',
                    };
                    final fg = switch (dl.op) {
                      DIFF_INSERT => insertFg,
                      DIFF_DELETE => deleteFg,
                      _ => widget.textColor.withValues(alpha: 0.72),
                    };
                    return Container(
                      color: bg,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1.5,
                      ),
                      child: Text(
                        '$prefix ${dl.text}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          height: 1.35,
                          color: fg,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            if (hiddenCount > 0)
              InkWell(
                onTap: () => setState(() => _showAllLines = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: widget.textColor.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Text(
                    'Показать ещё $hiddenCount строк',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _statPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  List<({int op, String text})> _computeDiffLines(String before, String after) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(before, after);
    dmp.diffCleanupSemantic(diffs);

    final result = <({int op, String text})>[];
    for (final d in diffs) {
      final lines = d.text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (i == lines.length - 1 && line.isEmpty) continue;
        if (d.operation == DIFF_EQUAL && lines.length > 4) {
          if (i == 0 || i == lines.length - 2) {
            result.add((op: DIFF_EQUAL, text: line));
          } else if (i == 1) {
            result.add((op: DIFF_EQUAL, text: '...'));
          }
          continue;
        }
        result.add((op: d.operation, text: line));
      }
    }
    return result;
  }
}

class RoxumCodeBlockCard extends StatelessWidget {
  final String code;
  final String language;
  final VoidCallback? onInsertIntoEditor;
  final Color? surfaceColor;
  final Color? textColor;

  const RoxumCodeBlockCard({
    super.key,
    required this.code,
    required this.language,
    this.onInsertIntoEditor,
    this.surfaceColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = surfaceColor ??
        (isDark ? const Color(0xFF0A0D14) : const Color(0xFFF1F5F9));
    final fg = textColor ?? (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A));
    final accent = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    final muted = fg.withValues(alpha: 0.65);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Text(
                  language.isEmpty ? 'code' : language,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const Spacer(),
                if (onInsertIntoEditor != null) ...[
                  InkWell(
                    onTap: onInsertIntoEditor,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.input_rounded,
                          size: 13,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppLocalizations.of(context)!.insert,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.codeCopied),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(Icons.copy, size: 13, color: muted),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)!.copy,
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              code.trimRight(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                height: 1.45,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
