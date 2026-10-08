import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/models/chat_message.dart';

/// Animated 3-dot thinking indicator replicating Mobile-Harness AnimatedThinkingDots
class AnimatedThinkingDots extends StatefulWidget {
  final Color? dotColor;
  final double size;

  const AnimatedThinkingDots({
    super.key,
    this.dotColor,
    this.size = 3.5,
  });

  @override
  State<AnimatedThinkingDots> createState() => _AnimatedThinkingDotsState();
}

class _AnimatedThinkingDotsState extends State<AnimatedThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getOffset(double progress, double delayFraction) {
    final t = (progress - delayFraction) % 1.0;
    if (t < 0.2) {
      // Move up to -3.5
      return -3.5 * (t / 0.2);
    } else if (t < 0.4) {
      // Move down from -3.5 to 0
      return -3.5 * (1.0 - (t - 0.2) / 0.2);
    }
    return 0.0;
  }

  double _getAlpha(double progress, double delayFraction) {
    final t = (progress - delayFraction) % 1.0;
    if (t < 0.2) {
      return 0.35 + 0.65 * (t / 0.2);
    } else if (t < 0.4) {
      return 1.0 - 0.65 * ((t - 0.2) / 0.2);
    }
    return 0.35;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.dotColor ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildDot(color, _getOffset(progress, 0.0), _getAlpha(progress, 0.0)),
            const SizedBox(width: 3),
            _buildDot(color, _getOffset(progress, 0.16), _getAlpha(progress, 0.16)),
            const SizedBox(width: 3),
            _buildDot(color, _getOffset(progress, 0.32), _getAlpha(progress, 0.32)),
          ],
        );
      },
    );
  }

  Widget _buildDot(Color baseColor, double offsetY, double alpha) {
    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Helper to get the correct icon for an ActivityItem
IconData activityIcon(ActivityItem? item) {
  if (item == null) return LucideIcons.sparkles;
  final task = item.title
      .replaceAll('Running ', '')
      .replaceAll(' completed', '')
      .trim()
      .toLowerCase();

  if (item.isCommand || task == 'bash' || task.contains('command')) {
    return LucideIcons.terminal;
  }
  if (task == 'write' || task == 'edit' || task.contains('notebookedit')) {
    return LucideIcons.pencil;
  }
  if (task == 'read' || task.contains('file') || task.contains('view')) {
    return LucideIcons.file_text;
  }
  if (task == 'search' || task == 'grep' || task == 'glob') {
    return LucideIcons.search;
  }
  if (task == 'think') {
    return LucideIcons.brain;
  }
  return LucideIcons.sparkles;
}

String activityName(ActivityItem item) {
  return item.title
      .replaceAll('Running ', '')
      .replaceAll(' completed', '')
      .trim();
}

String formatDuration(int totalSeconds) {
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final mins = totalSeconds ~/ 60;
  final secs = totalSeconds % 60;
  return '${mins}m ${secs}s';
}

/// Mobile-Harness Activity Summary Row
class ActivitySummaryRow extends StatelessWidget {
  final ActivityItem? item;
  final String text;
  final bool expanded;
  final bool showProgress;
  final VoidCallback onToggle;

  const ActivitySummaryRow({
    super.key,
    required this.item,
    required this.text,
    required this.expanded,
    required this.showProgress,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              activityIcon(item),
              size: 14,
              color: item?.isComplete == false ? theme.colorScheme.primary : muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: item?.isComplete == false ? theme.colorScheme.onSurface : muted,
                  fontWeight: item?.isComplete == false ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showProgress) ...[
              const SizedBox(width: 6),
              AnimatedThinkingDots(dotColor: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Icon(
              expanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
              size: 14,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded detail box for an ActivityItem with rich diff & console output
class ActivityExpandedDetail extends StatelessWidget {
  final ActivityItem? item;
  final String detail;

  const ActivityExpandedDetail({
    super.key,
    required this.item,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Code modification (diff or code content)
    final hasDiff = item?.targetContent != null || item?.replacementContent != null;
    if (hasDiff) {
      return Container(
        margin: const EdgeInsets.only(left: 22, right: 6, bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF131720),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item?.targetFile != null) ...[
              Row(
                children: [
                  const Icon(LucideIcons.file_code, size: 13, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      item!.targetFile!,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.cyanAccent.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (item?.instruction != null && item!.instruction!.isNotEmpty) ...[
              Text(
                item!.instruction!,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Removed chunk (targetContent)
            if (item?.targetContent != null && item!.targetContent!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.circle_minus, size: 12, color: Colors.redAccent),
                        const SizedBox(width: 5),
                        Text(
                          'Было (Удалено):',
                          style: GoogleFonts.inter(fontSize: 10.5, color: Colors.redAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      item!.targetContent!,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: const Color(0xFFFF8B8B), height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
            // Added chunk (replacementContent)
            if (item?.replacementContent != null && item!.replacementContent!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.circle_plus, size: 12, color: Colors.greenAccent),
                        const SizedBox(width: 5),
                        Text(
                          item?.targetContent != null ? 'Стало (Заменено):' : 'Новый код:',
                          style: GoogleFonts.inter(fontSize: 10.5, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      item!.replacementContent!,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: const Color(0xFF9AFFC5), height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 2. Command execution with console output
    if (item?.isCommand == true) {
      return Container(
        margin: const EdgeInsets.only(left: 22, right: 6, bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F131A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              '\$ $detail',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                height: 1.4,
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item?.output != null && item!.output!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  item!.output!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    height: 1.35,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 3. General item with optional output
    return Container(
      margin: const EdgeInsets.only(left: 22, right: 6, bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            detail,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.4,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (item?.output != null && item!.output!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                item!.output!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  height: 1.35,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Collapsible disclosure for list of activities (Mobile-Harness style)
class ClaudeActivityDisclosure extends StatefulWidget {
  final List<ActivityItem> items;
  final String headline;
  final bool isRunning;

  const ClaudeActivityDisclosure({
    super.key,
    required this.items,
    required this.headline,
    this.isRunning = false,
  });

  @override
  State<ClaudeActivityDisclosure> createState() => _ClaudeActivityDisclosureState();
}

class _ClaudeActivityDisclosureState extends State<ClaudeActivityDisclosure> {
  final Set<int> _expandedIndices = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.items.isEmpty) {
      final isExpanded = _expandedIndices.contains(0);
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ActivitySummaryRow(
              item: null,
              text: widget.headline,
              expanded: isExpanded,
              showProgress: widget.isRunning,
              onToggle: () {
                setState(() {
                  if (isExpanded) {
                    _expandedIndices.remove(0);
                  } else {
                    _expandedIndices.add(0);
                  }
                });
              },
            ),
            if (isExpanded)
              const ActivityExpandedDetail(
                item: null,
                detail: 'Reviewing the request and planning the next action.',
              ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < widget.items.length; i++) ...[
            ActivitySummaryRow(
              item: widget.items[i],
              text: '${activityName(widget.items[i])} · ${widget.items[i].detail.replaceAll(RegExp(r'\s+'), ' ').trim()}',
              expanded: _expandedIndices.contains(i),
              showProgress: widget.isRunning && !widget.items[i].isComplete,
              onToggle: () {
                setState(() {
                  if (_expandedIndices.contains(i)) {
                    _expandedIndices.remove(i);
                  } else {
                    _expandedIndices.add(i);
                  }
                });
              },
            ),
            if (_expandedIndices.contains(i))
              ActivityExpandedDetail(
                item: widget.items[i],
                detail: widget.items[i].detail.isNotEmpty ? widget.items[i].detail : widget.items[i].title,
              ),
          ],
        ],
      ),
    );
  }
}

/// WorkBlockCard: Displays completed work items for each assistant turn
class WorkBlockCard extends StatelessWidget {
  final ChatMessage message;

  const WorkBlockCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = (message.workedMillis / 1000).ceil().clamp(1, 999999);
    final totalSteps = message.workItems.length;
    final headline = totalSteps > 0
        ? 'Task completed · ${formatDuration(seconds)} · $totalSteps step${totalSteps == 1 ? '' : 's'}'
        : 'Task completed · ${formatDuration(seconds)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClaudeActivityDisclosure(
            items: message.workItems,
            headline: headline,
            isRunning: false,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.check_check, size: 12, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Worked for ${formatDuration(seconds)}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live in-progress activity card while agent is running
class LiveAgentProcessCard extends StatefulWidget {
  final List<ActivityItem> liveItems;
  final bool isRunning;
  final DateTime startedAt;
  final VoidCallback onStop;

  const LiveAgentProcessCard({
    super.key,
    required this.liveItems,
    required this.isRunning,
    required this.startedAt,
    required this.onStop,
  });

  @override
  State<LiveAgentProcessCard> createState() => _LiveAgentProcessCardState();
}

class _LiveAgentProcessCardState extends State<LiveAgentProcessCard> {
  late Timer _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _elapsedSeconds = DateTime.now().difference(widget.startedAt).inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds = DateTime.now().difference(widget.startedAt).inSeconds;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = widget.liveItems.isNotEmpty ? widget.liveItems.last : null;
    final headline = latest != null
        ? '${activityName(latest)} · ${latest.detail.replaceAll(RegExp(r'\s+'), ' ').trim()} · ${formatDuration(_elapsedSeconds)}'
        : 'Think · Analyzing request · ${formatDuration(_elapsedSeconds)}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedThinkingDots(dotColor: theme.colorScheme.primary, size: 4),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Stop Task Button
              InkWell(
                onTap: widget.onStop,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.square, size: 11, color: theme.colorScheme.error),
                      const SizedBox(width: 4),
                      Text(
                        'Stop',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (widget.liveItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClaudeActivityDisclosure(
              items: widget.liveItems,
              headline: headline,
              isRunning: true,
            ),
          ],
        ],
      ),
    );
  }
}
