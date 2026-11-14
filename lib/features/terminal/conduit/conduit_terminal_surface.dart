import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';

/// Terminal rendering surface powered by `conduit_vt` (`TerminalView`)
/// with built-in selection loupe (magnifying glass), pinch-to-zoom, and
/// Conduit color palettes.
class ConduitTerminalSurface extends StatefulWidget {
  const ConduitTerminalSurface({
    required this.terminal,
    required this.controller,
    required this.palette,
    required this.brightness,
    required this.fontFamily,
    required this.fontSize,
    required this.onFontSizeChanged,
    this.focusNode,
    this.autofocus = false,
    this.terminalMouseInput = true,
    this.onTapUp,
    this.onSecondaryTapDown,
    this.customTheme,
    this.hardwareKeyboardOnly = false,
    super.key,
  });

  final Terminal terminal;
  final TerminalController controller;
  final AppPalette palette;
  final Brightness brightness;
  final String fontFamily;
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool terminalMouseInput;
  final void Function(TapUpDetails, CellOffset)? onTapUp;
  final void Function(TapDownDetails, CellOffset)? onSecondaryTapDown;
  final TerminalTheme? customTheme;
  final bool hardwareKeyboardOnly;

  @override
  State<ConduitTerminalSurface> createState() => _ConduitTerminalSurfaceState();
}

class _ConduitTerminalSurfaceState extends State<ConduitTerminalSurface> {
  final _pinchPointers = <int, Offset>{};
  double? _pinchStartDistance;
  double? _pinchStartFontSize;

  static PointerInputs _pointerInputsFor(bool terminalMouseInput) {
    return terminalMouseInput
        ? const PointerInputs({PointerInput.tap})
        : const PointerInputs.none();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.setPointerInputs(
      _pointerInputsFor(widget.terminalMouseInput),
    );
  }

  @override
  void didUpdateWidget(covariant ConduitTerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminalMouseInput != widget.terminalMouseInput ||
        oldWidget.controller != widget.controller) {
      widget.controller.setPointerInputs(
        _pointerInputsFor(widget.terminalMouseInput),
      );
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pinchPointers[event.pointer] = event.localPosition;
    if (_pinchPointers.length == 2) {
      _pinchStartDistance = _pinchDistance;
      _pinchStartFontSize = widget.fontSize;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pinchPointers.containsKey(event.pointer)) return;
    _pinchPointers[event.pointer] = event.localPosition;
    final startDistance = _pinchStartDistance;
    final startFontSize = _pinchStartFontSize;
    if (_pinchPointers.length != 2 ||
        startDistance == null ||
        startDistance == 0 ||
        startFontSize == null) {
      return;
    }
    widget.onFontSizeChanged(startFontSize * (_pinchDistance / startDistance));
  }

  void _handlePointerEnd(PointerEvent event) {
    _pinchPointers.remove(event.pointer);
    if (_pinchPointers.length < 2) {
      _pinchStartDistance = null;
      _pinchStartFontSize = null;
    }
  }

  double get _pinchDistance {
    final points = _pinchPointers.values.take(2).toList();
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTheme =
        widget.customTheme ?? widget.palette.terminalThemeFor(widget.brightness);

    return ClipRect(
      child: ColoredBox(
        color: effectiveTheme.background,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerEnd,
          onPointerCancel: _handlePointerEnd,
          child: TerminalView(
            widget.terminal,
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            deleteDetection: true,
            keyboardType: widget.hardwareKeyboardOnly
                ? TextInputType.none
                : TextInputType.visiblePassword,
            theme: effectiveTheme,
            textStyle: TerminalStyle(
              fontFamily: widget.fontFamily,
              fontSize: widget.fontSize,
              fontFamilyFallback: const [
                'AtkynsonMonoNerdFontMono',
                'SymbolsNerdFont',
                'jetBrainsMono',
                'firaCode',
                'monospace',
              ],
            ),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            cursorType: TerminalCursorType.block,
            alwaysShowCursor: true,
            simulateScroll: true,
            onTapUp: widget.onTapUp,
            onSecondaryTapDown: widget.onSecondaryTapDown,
          ),
        ),
      ),
    );
  }
}
