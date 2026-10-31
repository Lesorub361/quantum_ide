import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';

/// Overlay widget for interactive touch selection in terminal views.
/// Displays draggable teardrop selection handles and an adaptive floating toolbar.
class TerminalSelectionOverlay extends StatefulWidget {
  final TerminalSession session;
  final xt.TerminalViewState Function() getViewState;
  final VoidCallback? onSelectAll;
  final VoidCallback? onPaste;

  const TerminalSelectionOverlay({
    super.key,
    required this.session,
    required this.getViewState,
    this.onSelectAll,
    this.onPaste,
  });

  @override
  State<TerminalSelectionOverlay> createState() => _TerminalSelectionOverlayState();
}

class _TerminalSelectionOverlayState extends State<TerminalSelectionOverlay> {
  xt.CellOffset? _lastDragStartCell;
  xt.CellOffset? _lastDragEndCell;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session.xtermViewController,
      builder: (context, _) {
        final selection = widget.session.xtermViewController.selection;
        if (selection == null) return const SizedBox.shrink();

        xt.TerminalViewState? viewState;
        try {
          viewState = widget.getViewState();
        } catch (_) {
          return const SizedBox.shrink();
        }

        RenderBox? terminalBox;
        try {
          terminalBox = viewState.context.findRenderObject() as RenderBox?;
        } catch (_) {}

        RenderBox? overlayBox;
        try {
          overlayBox = context.findRenderObject() as RenderBox?;
        } catch (_) {}

        Offset shift = Offset.zero;
        if (terminalBox != null && overlayBox != null && terminalBox.attached && overlayBox.attached) {
          shift = overlayBox.globalToLocal(terminalBox.localToGlobal(Offset.zero));
        }

        final renderTerminal = viewState.renderTerminal;
        final range = selection.normalized;
        final cellSize = renderTerminal.cellSize;
        final rawStartOffset = renderTerminal.getOffset(range.begin);
        final rawEndOffset = renderTerminal.getOffset(range.end);
        final startOffset = rawStartOffset + shift;
        final endOffset = rawEndOffset + shift;

        final selectedText = widget.session.xtermTerminal.buffer.getText(selection);
        final viewportSize = overlayBox?.size ?? renderTerminal.size;

        final isStartVisible = startOffset.dy >= -cellSize.height * 2 &&
            startOffset.dy <= viewportSize.height + cellSize.height;
        final isEndVisible = endOffset.dy >= -cellSize.height * 2 &&
            endOffset.dy <= viewportSize.height + cellSize.height;

        final isUrl = _checkIsUrl(selectedText.trim());

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Start selection handle
            if (isStartVisible)
              Positioned(
                left: (startOffset.dx - 16).clamp(-16.0, viewportSize.width),
                top: startOffset.dy + cellSize.height,
                child: _buildHandle(
                  isStart: true,
                  renderTerminal: renderTerminal,
                  range: range,
                  cellSize: cellSize,
                ),
              ),

            // End selection handle
            if (isEndVisible)
              Positioned(
                left: (endOffset.dx + cellSize.width - 16).clamp(-16.0, viewportSize.width),
                top: endOffset.dy + cellSize.height,
                child: _buildHandle(
                  isStart: false,
                  renderTerminal: renderTerminal,
                  range: range,
                  cellSize: cellSize,
                ),
              ),

            // Floating selection toolbar
            _buildFloatingToolbar(
              context: context,
              startOffset: startOffset,
              endOffset: endOffset,
              cellSize: cellSize,
              viewportSize: viewportSize,
              selectedText: selectedText,
              isUrl: isUrl,
            ),
          ],
        );
      },
    );
  }

  bool _checkIsUrl(String text) {
    final clean = text.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://') || clean.startsWith('ftp://')) {
      return true;
    }
    return false;
  }

  Widget _buildHandle({
    required bool isStart,
    required dynamic renderTerminal,
    required xt.BufferRange range,
    required Size cellSize,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        HapticFeedback.selectionClick();
        if (isStart) {
          _lastDragStartCell = range.begin;
        } else {
          _lastDragEndCell = range.end;
        }
      },
      onPanUpdate: (details) {
        final localPos = renderTerminal.globalToLocal(details.globalPosition);
        // Finger touches below the line, so map to cell slightly above touch
        final targetOffset = Offset(
          localPos.dx,
          localPos.dy - cellSize.height * 0.5,
        );
        final targetCell = renderTerminal.getCellOffset(targetOffset);

        if (isStart) {
          if (targetCell.y < range.end.y || (targetCell.y == range.end.y && targetCell.x <= range.end.x)) {
            if (targetCell != _lastDragStartCell) {
              _lastDragStartCell = targetCell;
              HapticFeedback.selectionClick();
              widget.session.xtermViewController.setSelection(
                widget.session.xtermTerminal.buffer.createAnchorFromOffset(targetCell),
                widget.session.xtermTerminal.buffer.createAnchorFromOffset(range.end),
              );
            }
          }
        } else {
          if (targetCell.y > range.begin.y || (targetCell.y == range.begin.y && targetCell.x >= range.begin.x)) {
            if (targetCell != _lastDragEndCell) {
              _lastDragEndCell = targetCell;
              HapticFeedback.selectionClick();
              widget.session.xtermViewController.setSelection(
                widget.session.xtermTerminal.buffer.createAnchorFromOffset(range.begin),
                widget.session.xtermTerminal.buffer.createAnchorFromOffset(targetCell),
              );
            }
          }
        }
      },
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(
          painter: _TeardropHandlePainter(
            isStart: isStart,
            color: Colors.cyanAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingToolbar({
    required BuildContext context,
    required Offset startOffset,
    required Offset endOffset,
    required Size cellSize,
    required Size viewportSize,
    required String selectedText,
    required bool isUrl,
  }) {
    final minY = math.min(startOffset.dy, endOffset.dy);
    final maxY = math.max(startOffset.dy, endOffset.dy) + cellSize.height;

    double top = minY - 44;
    if (top < 10) {
      top = math.min(viewportSize.height - 46, maxY + 34);
    }

    final avgX = (startOffset.dx + endOffset.dx) / 2;
    final toolbarLeft = (avgX - 100).clamp(10.0, math.max(10.0, viewportSize.width - 240)).toDouble();

    return Positioned(
      top: top,
      left: toolbarLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141722).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolbarBtn(
                icon: LucideIcons.copy,
                label: 'Копировать',
                color: Colors.cyanAccent,
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await Clipboard.setData(ClipboardData(text: selectedText));
                  widget.session.xtermViewController.clearSelection();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Скопировано в буфер обмена'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              if (isUrl) ...[
                _divider(),
                _buildToolbarBtn(
                  icon: LucideIcons.external_link,
                  label: 'Открыть',
                  color: Colors.greenAccent,
                  onTap: () async {
                    final uri = Uri.tryParse(selectedText.trim());
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],

              _divider(),
              _buildToolbarBtn(
                icon: LucideIcons.share_2,
                label: '',
                color: Colors.white70,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Share.share(selectedText);
                  widget.session.xtermViewController.clearSelection();
                },
              ),
              _divider(),
              _buildToolbarBtn(
                icon: LucideIcons.x,
                label: '',
                color: Colors.white54,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.session.xtermViewController.clearSelection();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white12,
    );
  }

  Widget _buildToolbarBtn({
    IconData? icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              if (label.isNotEmpty) const SizedBox(width: 4),
            ],
            if (label.isNotEmpty)
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color == Colors.white70 ? Colors.white : color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for touch-friendly selection teardrop handles
class _TeardropHandlePainter extends CustomPainter {
  final bool isStart;
  final Color color;

  _TeardropHandlePainter({required this.isStart, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    const topY = 0.0;
    const bulbCenterY = 13.0;
    const radius = 7.5;

    final path = Path();
    // Tip touching the character baseline
    path.moveTo(centerX, topY);
    // Draw smooth teardrop body hanging downward
    path.lineTo(centerX + radius, bulbCenterY - 2);
    path.arcToPoint(
      Offset(centerX - radius, bulbCenterY - 2),
      radius: const Radius.circular(radius),
      clockwise: true,
    );
    path.close();

    // Subtle ambient glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    // Solid fill
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Sleek inner center dot
    final dotPaint = Paint()..color = const Color(0xFF0F1117);
    canvas.drawCircle(Offset(centerX, bulbCenterY), 2.2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _TeardropHandlePainter oldDelegate) {
    return oldDelegate.isStart != isStart || oldDelegate.color != color;
  }
}
