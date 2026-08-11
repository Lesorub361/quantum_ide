import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:xterm/xterm.dart' as xt;

import '../../../../core/utils/share_utils.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';

/// Термукс-подобный оверлей для выделения текста в терминале.
///
/// Когда в терминале появляется выделение — рисует два ползунка-ручки
/// (егиpte: стартовую и конечную), которые можно перетаскивать чтобы
/// продолжить / изменить выделение, а также показывает панель
/// Копировать / Выделить всё / Вставить / Отправить.
class TerminalSelectionOverlay extends StatefulWidget {
  final TerminalSession session;
  final GlobalKey<xt.TerminalViewState> terminalKey;
  final ScrollController scrollController;
  final Widget child;

  const TerminalSelectionOverlay({
    super.key,
    required this.session,
    required this.terminalKey,
    required this.scrollController,
    required this.child,
  });

  @override
  State<TerminalSelectionOverlay> createState() =>
      _TerminalSelectionOverlayState();
}

class _TerminalSelectionOverlayState extends State<TerminalSelectionOverlay> {
  final GlobalKey _overlayKey = GlobalKey();

  Offsets? _offset;

  _HandleKind? _dragHandle;
  xt.CellOffset? _dragFixed;

  bool get _hasSelection => widget.session.xtermViewController.selection != null;

  xt.BufferRange? get _selection => widget.session.xtermViewController.selection;

  @override
  void initState() {
    super.initState();
    widget.session.xtermViewController.addListener(_onChange);
    widget.session.xtermTerminal.addListener(_onChange);
    widget.scrollController.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOffsets());
  }

  @override
  void dispose() {
    widget.session.xtermViewController.removeListener(_onChange);
    widget.session.xtermTerminal.removeListener(_onChange);
    widget.scrollController.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateOffsets();
    });
    setState(() {});
  }

  void _updateOffsets() {
    final rt = widget.terminalKey.currentState?.renderTerminal;
    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final selection = _selection;
    if (rt == null || overlayBox == null) {
      _offset = null;
      return;
    }
    if (selection == null) {
      _offset = null;
      return;
    }

    final norm = selection.normalized;
    final cellSize = rt.cellSize;

    Offset localToOverlay(Offset local) {
      final global = rt.localToGlobal(local);
      return overlayBox.globalToLocal(global);
    }

    final startLocal = rt.getOffset(norm.begin);
    final endLocal = rt.getOffset(norm.end);

    _offset = Offsets(
      start: localToOverlay(startLocal),
      end: localToOverlay(endLocal + Offset(cellSize.width, cellSize.height)),
      cellSize: cellSize,
    );
  }

  xt.CellOffset _cellAt(Offset globalPos) {
    final rt = widget.terminalKey.currentState!.renderTerminal;
    final local = rt.globalToLocal(globalPos);
    return rt.getCellOffset(local);
  }

  void _beginHandleDrag(_HandleKind kind) {
    final sel = _selection;
    if (sel == null) return;
    HapticFeedback.mediumImpact();
    _dragHandle = kind;
    _dragFixed = kind == _HandleKind.start ? sel.end : sel.begin;
  }

  void _moveHandle(Offset globalPos) {
    final sel = _selection;
    if (sel == null) return;
    final kind = _dragHandle;
    if (kind == null) return;

    final cell = _cellAt(globalPos);
    final buffer = widget.session.xtermTerminal.buffer;
    final fixed = _dragFixed ?? (kind == _HandleKind.start ? sel.end : sel.begin);

    final newAnchor = buffer.createAnchorFromOffset(cell);
    final fixedAnchor = buffer.createAnchorFromOffset(fixed);

    if (kind == _HandleKind.start) {
      widget.session.xtermViewController.setSelection(newAnchor, fixedAnchor);
    } else {
      widget.session.xtermViewController.setSelection(fixedAnchor, newAnchor);
    }

    _autoScrollForDrag(globalPos);
  }

  void _endHandleDrag() {
    _dragHandle = null;
    _dragFixed = null;
  }

  void _autoScrollForDrag(Offset globalPos) {
    final rt = widget.terminalKey.currentState?.renderTerminal;
    final sc = widget.scrollController;
    if (rt == null || !sc.hasClients) return;

    final local = rt.globalToLocal(globalPos);
    final lineH = rt.lineHeight;
    const edge = 32.0;
    var delta = 0.0;
    if (local.dy < edge) delta = -lineH;
    if (local.dy > rt.size.height - edge) delta = lineH;
    if (delta == 0) return;

    final pos = sc.position;
    final target = (pos.pixels + delta * 2).clamp(0.0, pos.maxScrollExtent);
    sc.jumpTo(target);
  }

  Future<void> _copySelected() async {
    final sel = _selection;
    if (sel == null) return;
    final text = widget.session.xtermTerminal.buffer.getText(sel);
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
    }
    widget.session.xtermViewController.clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _selectAll() {
    final term = widget.session.xtermTerminal;
    final buffer = term.buffer;
    widget.session.xtermViewController.setSelection(
      buffer.createAnchorFromOffset(const xt.CellOffset(0, 0)),
      buffer.createAnchorFromOffset(
        xt.CellOffset(term.viewWidth - 1, buffer.height - 1),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      widget.session.pty
          .write(Uint8List.fromList(utf8.encode(data!.text!)));
    }
    widget.session.xtermViewController.clearSelection();
  }

  Future<void> _share() async {
    final sel = _selection;
    if (sel == null) return;
    final text = widget.session.xtermTerminal.buffer.getText(sel);
    if (text.isNotEmpty) {
      await ShareUtils.shareText(text);
    }
  }

  void _clearSelection() {
    widget.session.xtermViewController.clearSelection();
    _offset = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: _overlayKey,
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_hasSelection) ...[
          if (_offset != null) ...[
            Positioned(
              left: _offset!.start.dx - 14,
              top: _offset!.start.dy - 14,
              child: _buildHandle(_HandleKind.start),
            ),
            Positioned(
              left: _offset!.end.dx - 6,
              top: _offset!.end.dy - 10,
              child: _buildHandle(_HandleKind.end),
            ),
          ],
          _buildToolbar(),
        ],
      ],
    );
  }

  Widget _buildToolbar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Center(
          child: Material(
            color: const Color(0xF21E1E24),
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolbarButton(
                    LucideIcons.copy,
                    'Copy',
                    Colors.cyanAccent,
                    _copySelected,
                  ),
                  _toolbarButton(
                    LucideIcons.check_check,
                    'All',
                    Colors.blueAccent,
                    _selectAll,
                  ),
                  _toolbarButton(
                    LucideIcons.clipboard_paste,
                    'Paste',
                    Colors.greenAccent,
                    _paste,
                  ),
                  _toolbarButton(
                    LucideIcons.share_2,
                    'Share',
                    Colors.orangeAccent,
                    _share,
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(LucideIcons.x,
                        size: 14, color: Colors.white54),
                    onPressed: _clearSelection,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 26, minHeight: 26),
                    tooltip: 'Clear selection',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.15)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: color.withValues(alpha: 0.9),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(_HandleKind kind) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _beginHandleDrag(kind),
      onPanUpdate: (d) => _moveHandle(d.globalPosition),
      onPanEnd: (_) => _endHandleDrag(),
      onPanCancel: _endHandleDrag,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.cyanAccent.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.cyanAccent, width: 1.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.cyanAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

enum _HandleKind { start, end }

class Offsets {
  final Offset start;
  final Offset end;
  final Size cellSize;

  Offsets({required this.start, required this.end, required this.cellSize});
}