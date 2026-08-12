import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' as xt;

import 'native_terminal_selection.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';

/// Оверлей для нативного выделения текста в терминале (Android System Text Selection).
///
/// Использует прозрачный нативный EditText поверх терминала для отображения
/// стандартных синих маркеров выделения и ActionMode (Copy/Select All).
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
  final NativeTerminalSelectionBridge _nativeBridge = NativeTerminalSelectionBridge();

  bool _nativeActive = false;
  bool _suppressNativeSync = false;
  BufferTextMapper? _mapper;
  Rect? _terminalTextRect;
  int _firstVisibleLine = 0;
  int _lastVisibleLine = 0;

  @override
  void initState() {
    super.initState();
    _nativeBridge.startListening();
    _nativeBridge.onSelectionChanged = _onNativeSelectionChanged;
    _nativeBridge.onCopy = _onNativeCopy;
    _nativeBridge.onSelectAll = _onNativeSelectAll;
    _nativeBridge.onActionModeDestroyed = _onNativeActionModeDestroyed;

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
    _nativeBridge.stopListening();
    _nativeBridge.hide();
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
    final terminalViewState = widget.terminalKey.currentState;
    if (terminalViewState == null) {
      if (_nativeActive) {
        _hideNativeOverlay();
      }
      _mapper = null;
      _terminalTextRect = null;
      return;
    }

    final rt = terminalViewState.renderTerminal;
    final selection = widget.session.xtermViewController.selection;
    if (selection == null) {
      if (_nativeActive) {
        _hideNativeOverlay();
      }
      _mapper = null;
      _terminalTextRect = null;
      return;
    }

    final norm = selection.normalized;
    final cellSize = rt.cellSize;
    final lineHeight = rt.lineHeight;

    // Compute visible line range
    final scrollPixels = widget.scrollController.hasClients
        ? widget.scrollController.position.pixels
        : 0.0;
    final firstVisibleLine = (scrollPixels / lineHeight).floor().clamp(0, widget.session.xtermTerminal.buffer.height - 1);
    final visibleRows = (rt.size.height / lineHeight).floor().clamp(1, widget.session.xtermTerminal.buffer.height);
    final lastVisibleLine = (firstVisibleLine + visibleRows - 1).clamp(0, widget.session.xtermTerminal.buffer.height - 1);

    // Check if visible range changed
    if (_firstVisibleLine != firstVisibleLine || _lastVisibleLine != lastVisibleLine) {
      _firstVisibleLine = firstVisibleLine;
      _lastVisibleLine = lastVisibleLine;
    }

    // Build text mapper for visible lines
    _mapper = BufferTextMapper(
      terminal: widget.session.xtermTerminal,
      firstVisibleLine: firstVisibleLine,
      lastVisibleLine: lastVisibleLine,
    );

    // Compute terminal text area rect in global coordinates
    final textOrigin = rt.localToGlobal(Offset(0, firstVisibleLine * lineHeight));
    final terminal = terminalViewState.widget.terminal;
    final textWidth = terminal.viewWidth * cellSize.width;
    final textHeight = visibleRows * lineHeight;
    _terminalTextRect = Rect.fromLTWH(textOrigin.dx, textOrigin.dy, textWidth, textHeight);

    // Map selection to character indices in the overlay text
    final startIdx = _mapper!.charIndexForCell(norm.begin);
    final endIdx = _mapper!.charIndexForCell(norm.end);

    // Show or update native overlay.
    // Once the native overlay is active the user drives the selection through
    // the OS handles, so we must NOT reset the native selection — we only keep
    // its position in sync with the terminal (e.g. while scrolling).
    if (!_nativeActive) {
      _showNativeOverlay(startIdx, endIdx);
    } else {
      _updateNativePosition();
    }
  }

  void _updateNativePosition() {
    if (_terminalTextRect == null) return;
    _nativeBridge.updatePosition(_terminalTextRect!);
  }

  void _showNativeOverlay(int startIdx, int endIdx) {
    if (_mapper == null || _terminalTextRect == null) return;
    final terminalViewState = widget.terminalKey.currentState;
    if (terminalViewState == null) return;

    final rt = terminalViewState.renderTerminal;
    final fontSize = rt.cellSize.width; // approximate, use cell width as font size
    final lineHeight = rt.lineHeight;

    // Get font family from terminal view's textStyle
    final fontFamily = terminalViewState.widget.textStyle.fontFamily;

    _nativeActive = true;
    _nativeBridge.show(
      text: _mapper!.fullText,
      selectionStart: startIdx,
      selectionEnd: endIdx,
      rect: _terminalTextRect!,
      fontSize: fontSize,
      lineHeight: lineHeight,
      fontFamily: fontFamily,
    );
  }

  void _hideNativeOverlay() {
    if (_nativeActive) {
      _nativeActive = false;
      _nativeBridge.hide();
    }
  }

  void _onNativeSelectionChanged(int start, int end) {
    if (_mapper == null || _suppressNativeSync) return;
    _suppressNativeSync = true;

    final startCell = _mapper!.cellForCharIndex(start);
    final endCell = _mapper!.cellForCharIndex(end);

    if (startCell != null && endCell != null) {
      final buffer = widget.session.xtermTerminal.buffer;
      final beginAnchor = buffer.createAnchorFromOffset(startCell);
      final endAnchor = buffer.createAnchorFromOffset(endCell);
      widget.session.xtermViewController.setSelection(beginAnchor, endAnchor);
    }

    _suppressNativeSync = false;
  }

  void _onNativeCopy() {
    final sel = widget.session.xtermViewController.selection;
    if (sel != null) {
      final text = widget.session.xtermTerminal.buffer.getText(sel);
      if (text.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: text));
      }
    }
    // Keep selection visible briefly, then clear
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        widget.session.xtermViewController.clearSelection();
      }
    });
  }

  void _onNativeSelectAll() {
    // The native EditText already selected all of its (visible) text and fired
    // onSelectionChanged, which mirrored the selection into xterm. We just make
    // sure xterm's selection also spans the full visible buffer range and keep
    // the current native overlay/position intact (no reset of handles).
    final terminalViewState = widget.terminalKey.currentState;
    if (terminalViewState == null) return;

    final terminal = terminalViewState.widget.terminal;
    final buffer = terminal.buffer;
    final first = _firstVisibleLine;
    final last = _lastVisibleLine;
    if (last >= first) {
      widget.session.xtermViewController.setSelection(
        buffer.createAnchorFromOffset(xt.CellOffset(0, first)),
        buffer.createAnchorFromOffset(
          xt.CellOffset(terminal.viewWidth - 1, last),
        ),
      );
    }
  }

  void _onNativeActionModeDestroyed() {
    _nativeActive = false;
    if (mounted) {
      widget.session.xtermViewController.clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The native overlay handles all selection UI (handles, ActionMode)
    // We just pass through the child
    return widget.child;
  }
}