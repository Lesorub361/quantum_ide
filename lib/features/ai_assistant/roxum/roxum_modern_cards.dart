import 'dart:async';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
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

  String _tailLines(String text, int maxLines) {
    final lines = text.trimRight().split('\n');
    if (lines.length <= maxLines) return text.trimRight();
    return lines.sublist(lines.length - maxLines).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final sec = (widget.durationMs / 1000).round();
    final secDisplay = sec > 0
        ? '${sec}s'
        : '${(widget.durationMs / 1000).toStringAsFixed(1)}s';
    final label = widget.isStreaming
        ? 'Thinking...'
        : (widget.durationMs > 0 ? 'Thought for $secDisplay' : 'Thought');

    final muted = widget.textColor.withValues(alpha: 0.62);

    final Widget labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
    );

    final displayReasoning = _expanded
        ? widget.reasoningText
        : (widget.isStreaming
            ? _tailLines(widget.reasoningText, 3)
            : widget.reasoningText);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isStreaming)
                    labelWidget
                        .animate(onPlay: (c) => c.repeat())
                        .shimmer(
                          duration: 1300.ms,
                          color: widget.textColor.withValues(alpha: 0.9),
                        )
                  else
                    labelWidget,
                  const SizedBox(width: 6),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                    size: 16,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
          if ((_expanded || widget.isStreaming) &&
              widget.reasoningText.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
              padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: widget.textColor.withValues(alpha: 0.18),
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                displayReasoning,
                maxLines: _expanded ? null : 3,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: widget.textColor.withValues(alpha: 0.68),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RoxumAgentTimeline extends StatefulWidget {
  final List<RoxumToolCallRecord> toolCalls;
  final Color surfaceColor;
  final Color textColor;
  final void Function(String filePath)? onOpenFile;

  const RoxumAgentTimeline({
    super.key,
    required this.toolCalls,
    required this.surfaceColor,
    required this.textColor,
    this.onOpenFile,
  });

  @override
  State<RoxumAgentTimeline> createState() => _RoxumAgentTimelineState();
}

class _RoxumAgentTimelineState extends State<RoxumAgentTimeline> {
  final Set<String> _expandedIds = {};
  bool _chainExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.toolCalls.isEmpty) return const SizedBox.shrink();

    final allFinished = widget.toolCalls.every((tc) => !tc.isRunning);
    final shouldUseSummary = allFinished && widget.toolCalls.length > 4;
    final failedCount =
        widget.toolCalls.where((tc) => !tc.isRunning && !tc.success).length;
    final muted = widget.textColor.withValues(alpha: 0.65);

    if (shouldUseSummary) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => setState(() => _chainExpanded = !_chainExpanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 34),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        failedCount > 0
                            ? Icons.error_outline
                            : LucideIcons.circle_check,
                        size: 14,
                        color: failedCount > 0
                            ? Colors.redAccent
                            : const Color(0xFF22C55E),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          failedCount > 0
                              ? 'Выполнено ${widget.toolCalls.length} шагов ($failedCount с ошибкой)'
                              : 'Выполнено ${widget.toolCalls.length} шагов',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _chainExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                        size: 16,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_chainExpanded)
              Container(
                margin: const EdgeInsets.only(left: 7, top: 2),
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: widget.textColor.withValues(alpha: 0.14),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final tc in widget.toolCalls) _buildInlineStepRow(tc),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tc in widget.toolCalls) _buildInlineStepRow(tc),
        ],
      ),
    );
  }

  Widget _buildInlineStepRow(RoxumToolCallRecord tc) {
    final isExpanded = _expandedIds.contains(tc.id);
    final info = _describeStep(tc);
    final muted = widget.textColor.withValues(alpha: 0.62);
    final hasExpandableOutput = tc.output.isNotEmpty;
    final canOpenFile = info.filePath != null &&
        info.filePath!.isNotEmpty &&
        widget.onOpenFile != null &&
        (tc.name == 'readFile' ||
            tc.name == 'codeOutline' ||
            tc.name == 'writeFile' ||
            tc.name == 'editFile' ||
            tc.name == 'insertAtLine' ||
            tc.name == 'replaceAllInFile');

    final targetTextStyle = info.isMono
        ? GoogleFonts.jetBrainsMono(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: widget.textColor.withValues(alpha: 0.9),
            decoration: canOpenFile ? TextDecoration.underline : null,
            decorationColor: widget.textColor.withValues(alpha: 0.35),
          )
        : TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: widget.textColor.withValues(alpha: 0.9),
            decoration: canOpenFile ? TextDecoration.underline : null,
            decorationColor: widget.textColor.withValues(alpha: 0.35),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: hasExpandableOutput
                ? () {
                    setState(() {
                      if (isExpanded) {
                        _expandedIds.remove(tc.id);
                      } else {
                        _expandedIds.add(tc.id);
                      }
                    });
                  }
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 34),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    if (tc.isRunning) ...[
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: info.iconColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      info.verb,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: muted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildFileOrToolBadge(info),
                    const SizedBox(width: 6),
                    Flexible(
                      child: canOpenFile
                          ? InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => widget.onOpenFile!(info.filePath!),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 2,
                                ),
                                child: Text(
                                  info.primaryTarget,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: targetTextStyle,
                                ),
                              ),
                            )
                          : Text(
                              info.primaryTarget,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: targetTextStyle,
                            ),
                    ),
                    if (info.lineRange != null &&
                        info.lineRange!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        info.lineRange!,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: widget.textColor.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                    if (!tc.isRunning && !tc.success) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                    ],
                    if (hasExpandableOutput) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                        size: 16,
                        color: (!tc.isRunning && !tc.success)
                            ? Colors.redAccent.withValues(alpha: 0.85)
                            : widget.textColor.withValues(alpha: 0.45),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded && tc.output.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 4, left: 6),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: (!tc.isRunning && !tc.success)
                    ? Colors.redAccent.withValues(alpha: 0.08)
                    : widget.surfaceColor.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (!tc.isRunning && !tc.success)
                      ? Colors.redAccent.withValues(alpha: 0.35)
                      : widget.textColor.withValues(alpha: 0.09),
                ),
              ),
              child: SelectableText(
                tc.output.length > 1600
                    ? '${tc.output.substring(0, 1600)}\n... [truncated]'
                    : tc.output,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  height: 1.38,
                  color: (!tc.isRunning && !tc.success)
                      ? Colors.redAccent
                      : widget.textColor.withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFileOrToolBadge(_StepDescriptor info) {
    if (info.badgeText != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
        decoration: BoxDecoration(
          color: info.iconColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          info.badgeText!,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: info.iconColor,
          ),
        ),
      );
    }
    return Icon(
      info.icon,
      size: 14.5,
      color: info.iconColor,
    );
  }

  _StepDescriptor _describeStep(RoxumToolCallRecord tc) {
    final fp = tc.arguments['filePath']?.toString() ??
        tc.arguments['directoryPath']?.toString() ??
        '';
    final base = fp.isNotEmpty ? p.basename(fp) : '';

    switch (tc.name) {
      case 'readFile':
      case 'activeEditorFile':
        final range = _extractLineRange(tc);
        final lang = _fileBadgeFor(base);
        return _StepDescriptor(
          verb: 'Analyzed',
          primaryTarget: base.isNotEmpty ? base : 'file',
          lineRange: range,
          icon: lang.icon,
          iconColor: lang.color,
          badgeText: lang.badge,
          filePath: fp,
        );
      case 'codeOutline':
        final lang = _fileBadgeFor(base);
        return _StepDescriptor(
          verb: 'Analyzed',
          primaryTarget: base.isNotEmpty ? base : 'outline',
          lineRange: 'outline',
          icon: lang.icon,
          iconColor: lang.color,
          badgeText: lang.badge,
          filePath: fp,
        );
      case 'writeFile':
      case 'editFile':
      case 'insertAtLine':
      case 'replaceAllInFile':
        final lang = _fileBadgeFor(base);
        return _StepDescriptor(
          verb: tc.name == 'writeFile' ? 'Created' : 'Edited',
          primaryTarget: base.isNotEmpty ? base : 'file',
          icon: lang.icon,
          iconColor: lang.color,
          badgeText: lang.badge,
          filePath: fp,
        );
      case 'grepInFiles':
      case 'searchInFiles':
        final q = tc.arguments['query']?.toString() ??
            tc.arguments['pattern']?.toString() ??
            '';
        return _StepDescriptor(
          verb: 'Searched',
          primaryTarget: q.isNotEmpty ? '"$q"' : 'workspace',
          icon: LucideIcons.search,
          iconColor: const Color(0xFF38BDF8),
        );
      case 'listFiles':
      case 'globSearchFiles':
        final pat = tc.arguments['pattern']?.toString() ??
            (base.isNotEmpty ? base : 'workspace');
        return _StepDescriptor(
          verb: 'Explored',
          primaryTarget: pat,
          icon: LucideIcons.folder_search,
          iconColor: const Color(0xFF38BDF8),
        );
      case 'getLspDiagnostics':
        return _StepDescriptor(
          verb: 'Checked diagnostics',
          primaryTarget: base.isNotEmpty ? base : 'workspace',
          icon: LucideIcons.activity,
          iconColor: const Color(0xFF22C55E),
        );
      case 'checkEnvironment':
        return const _StepDescriptor(
          verb: 'Checked environment',
          primaryTarget: 'SDKs & toolchains',
          icon: LucideIcons.cpu,
          iconColor: Color(0xFF38BDF8),
        );
      case 'installPackages':
        final mgr = tc.arguments['manager']?.toString() ?? '';
        final pkgs = tc.arguments['packages']?.toString() ?? '';
        return _StepDescriptor(
          verb: 'Installed',
          primaryTarget: '$mgr $pkgs'.trim(),
          icon: LucideIcons.package_plus,
          iconColor: const Color(0xFFA78BFA),
        );
      case 'runCommand':
        final cmd = tc.arguments['command']?.toString() ?? '';
        return _StepDescriptor(
          verb: 'Ran',
          primaryTarget: cmd,
          icon: LucideIcons.terminal,
          iconColor: const Color(0xFF22C55E),
          isMono: true,
        );
      default:
        if (tc.name.startsWith('mcp__')) {
          final parts = tc.name.split('__');
          final srv = parts.length > 1 ? parts[1] : 'mcp';
          final fn = parts.length > 2 ? parts.sublist(2).join('_') : tc.name;
          return _StepDescriptor(
            verb: 'MCP [$srv]',
            primaryTarget: fn,
            icon: LucideIcons.blocks,
            iconColor: const Color(0xFFA78BFA),
          );
        }
        return _StepDescriptor(
          verb: 'Executed',
          primaryTarget: base.isNotEmpty ? '${tc.name} · $base' : tc.name,
          icon: LucideIcons.sparkles,
          iconColor: const Color(0xFF38BDF8),
        );
    }
  }

  String? _extractLineRange(RoxumToolCallRecord tc) {
    final headerMatch = RegExp(r'#L(\d+-\d+)').firstMatch(tc.output);
    if (headerMatch != null) {
      return '#L${headerMatch.group(1)}';
    }
    final s = tc.arguments['startLine'];
    final e = tc.arguments['endLine'];
    if (s != null && e != null) {
      return '#L$s-$e';
    }
    if (tc.output.isNotEmpty) {
      final lineCount = '\n'.allMatches(tc.output).length;
      if (lineCount > 1) {
        return '#L1-$lineCount';
      }
    }
    return null;
  }

  ({IconData icon, Color color, String? badge}) _fileBadgeFor(String filename) {
    if (filename.isEmpty) {
      return (
        icon: LucideIcons.file_code,
        color: const Color(0xFF38BDF8),
        badge: null,
      );
    }
    final info = FileIconHelper.getIconInfo(filename, false);
    return (
      icon: info.icon,
      color: info.color,
      badge: null,
    );
  }
}

class _StepDescriptor {
  final String verb;
  final String primaryTarget;
  final String? lineRange;
  final IconData icon;
  final Color iconColor;
  final String? badgeText;
  final String? filePath;
  final bool isMono;

  const _StepDescriptor({
    required this.verb,
    required this.primaryTarget,
    this.lineRange,
    required this.icon,
    required this.iconColor,
    this.badgeText,
    this.filePath,
    this.isMono = false,
  });
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
  late List<({int op, String text})> _diffLines;

  @override
  void initState() {
    super.initState();
    _diffLines = _computeDiffLines(
      widget.edit.originalContent,
      widget.edit.updatedContent,
    );
  }

  @override
  void didUpdateWidget(covariant RoxumFileDiffCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edit.originalContent != widget.edit.originalContent ||
        oldWidget.edit.updatedContent != widget.edit.updatedContent) {
      _diffLines = _computeDiffLines(
        widget.edit.originalContent,
        widget.edit.updatedContent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleLines =
        _showAllLines ? _diffLines : _diffLines.take(16).toList();
    final hiddenCount = _diffLines.length - visibleLines.length;

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
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(11),
              bottom: _collapsed ? const Radius.circular(11) : Radius.zero,
            ),
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: widget.surfaceColor,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(10),
                  bottom: _collapsed ? const Radius.circular(10) : Radius.zero,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _collapsed
                        ? Icons.chevron_right
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: widget.textColor.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.file_diff,
                    size: 14,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onOpenFile,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
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
                  ),
                  const SizedBox(width: 4),
                  _statPill('+${widget.edit.addedLines}', const Color(0xFF22C55E)),
                  const SizedBox(width: 4),
                  _statPill('-${widget.edit.removedLines}', Colors.redAccent),
                  if (widget.isPending) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: AppLocalizations.of(context)!.revertFile,
                      child: InkWell(
                        onTap: widget.onUndo,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Icon(
                                Icons.undo,
                                size: 16,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: AppLocalizations.of(context)!.acceptFile,
                      child: InkWell(
                        onTap: widget.onKeep,
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 16,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                          ),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: visibleLines.map((dl) {
                              final bg = switch (dl.op) {
                                DIFF_INSERT => const Color(0xFF22C55E)
                                    .withValues(alpha: 0.14),
                                DIFF_DELETE =>
                                  Colors.redAccent.withValues(alpha: 0.14),
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
                                  softWrap: false,
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
                      ),
                    );
                  },
                ),
              ),
            if (hiddenCount > 0 || (_showAllLines && _diffLines.length > 16))
              InkWell(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(11)),
                onTap: () => setState(() => _showAllLines = !_showAllLines),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: widget.textColor.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Text(
                    hiddenCount > 0
                        ? 'Показать ещё $hiddenCount строк'
                        : 'Свернуть',
                    style: const TextStyle(
                      fontSize: 11.5,
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

class RoxumCodeBlockCard extends StatefulWidget {
  final String code;
  final String language;
  final bool isTerminalCommand;
  final VoidCallback? onInsertIntoEditor;
  final VoidCallback? onRunInTerminal;
  final Color? surfaceColor;
  final Color? textColor;

  const RoxumCodeBlockCard({
    super.key,
    required this.code,
    required this.language,
    this.isTerminalCommand = false,
    this.onInsertIntoEditor,
    this.onRunInTerminal,
    this.surfaceColor,
    this.textColor,
  });

  @override
  State<RoxumCodeBlockCard> createState() => _RoxumCodeBlockCardState();
}

class _RoxumCodeBlockCardState extends State<RoxumCodeBlockCard> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  void _handleCopy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    _copyTimer?.cancel();
    setState(() => _copied = true);
    _copyTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseBg = widget.surfaceColor ??
        (isDark ? const Color(0xFF0A0D14) : const Color(0xFFF1F5F9));
    final bg = widget.surfaceColor != null
        ? (isDark
            ? Color.lerp(baseBg, Colors.black, 0.12)!
            : Color.lerp(baseBg, Colors.black, 0.04)!)
        : baseBg;
    final fg = widget.textColor ??
        (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A));
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isTerminalCommand
                            ? LucideIcons.terminal
                            : LucideIcons.code,
                        size: 12,
                        color: accent,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          widget.language.isEmpty
                              ? (widget.isTerminalCommand ? 'terminal' : 'code')
                              : widget.language,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.isTerminalCommand &&
                    widget.onRunInTerminal != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onRunInTerminal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.terminal,
                            size: 13,
                            color: accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppLocalizations.of(context)!.terminal,
                            style: TextStyle(
                              fontSize: 11,
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ] else if (!widget.isTerminalCommand &&
                    widget.onInsertIntoEditor != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onInsertIntoEditor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                              fontSize: 11,
                              color: Color(0xFF22C55E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _handleCopy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? LucideIcons.check : Icons.copy,
                          size: 13,
                          color: _copied ? const Color(0xFF22C55E) : muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied
                              ? 'Скопировано ✓'
                              : AppLocalizations.of(context)!.copy,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                _copied ? FontWeight.w600 : FontWeight.w400,
                            color: _copied ? const Color(0xFF22C55E) : muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              widget.code.trimRight(),
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
