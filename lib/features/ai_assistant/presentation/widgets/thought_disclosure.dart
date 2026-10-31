import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';

class ThoughtDisclosure extends StatefulWidget {
  final String thought;
  final bool isThinking;
  final int? durationSeconds;

  const ThoughtDisclosure({
    super.key,
    required this.thought,
    this.isThinking = false,
    this.durationSeconds,
  });

  @override
  State<ThoughtDisclosure> createState() => _ThoughtDisclosureState();
}

class _ThoughtDisclosureState extends State<ThoughtDisclosure>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late DateTime _startedAt;
  Timer? _timer;
  int _liveSeconds = 0;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isThinking;
    _startedAt = DateTime.now();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _expanded ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ThoughtDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isThinking && !oldWidget.isThinking) {
      _expanded = true;
      _startedAt = DateTime.now();
      _liveSeconds = 0;
      _animController.forward();
    } else if (!widget.isThinking && oldWidget.isThinking) {
      _expanded = false;
      _liveSeconds = widget.durationSeconds ?? _liveSeconds;
      _animController.reverse();
    }

    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _syncTimer() {
    if (!widget.isThinking) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _liveSeconds = DateTime.now().difference(_startedAt).inSeconds;
      });
    });
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = theme.hintColor;
    final accentColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header button
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isThinking)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: accentColor,
                        ),
                      ),
                    ),
                  if (!widget.isThinking)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: muted,
                      ),
                    ),
                  Text(
                    _label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: widget.isThinking ? accentColor : muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 15,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Collapsible body
          SizeTransition(
            sizeFactor: _expandAnimation,
            alignment: AlignmentDirectional.topStart,
            child: Container(
              margin: const EdgeInsets.only(top: 2, bottom: 6, left: 4),
              padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.12),
                    width: 2,
                  ),
                ),
              ),
              child: MarkdownBody(
                data: widget.thought.trim(),
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _label {
    final seconds = widget.durationSeconds ?? _liveSeconds;
    if (widget.isThinking) {
      return seconds > 0 ? 'Размышляет (${seconds}с)...' : 'Размышляет...';
    }
    return seconds > 0 ? 'Мысли (${seconds}с)' : 'Ход мыслей';
  }
}
