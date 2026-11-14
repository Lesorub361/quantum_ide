import 'dart:async';

import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/core/theme/conduit_terminal_appearance.dart';
import 'package:quantum_ide/core/theme/system_navigation_insets.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_keyboard_controller.dart';

/// Virtual keyboard bar adapted from Conduit for `conduit_vt`.
class ConduitKeyboardBar extends StatelessWidget {
  const ConduitKeyboardBar({
    required this.terminal,
    required this.keyboardController,
    required this.focusNode,
    required this.palette,
    required this.brightness,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.onOpenAppearance,
    this.onPaste,
    this.rows,
    super.key,
  });

  final Terminal terminal;
  final ConduitKeyboardController keyboardController;
  final FocusNode focusNode;
  final AppPalette palette;
  final Brightness brightness;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onOpenAppearance;
  final VoidCallback? onPaste;
  final List<TerminalKeyboardRow>? rows;

  static final List<TerminalKeyboardRow> _defaultRows = [
    TerminalKeyboardRow(
      height: 44,
      items: [
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.escape),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.control),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.alt),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.tab),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.arrowUp),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.arrowDown),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.arrowLeft),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.arrowRight),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.slash),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.dash),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.pipe),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.colon),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.paste),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.controlC),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.controlD),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.controlZ),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.controlL),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.home),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.end),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.pageUp),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.pageDown),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.functionKeys),
        const TerminalKeyboardItem.builtIn(TerminalKeyboardAction.fullscreen),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final activeRows = rows ?? _defaultRows;

    return ListenableBuilder(
      listenable: keyboardController,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.canvasFor(brightness),
            border: Border(
              top: BorderSide(color: palette.hairlineFor(brightness)),
            ),
          ),
          child: SafeArea(
            top: false,
            bottom: shouldApplyBottomSafeArea(context),
            left: false,
            right: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, row) in activeRows.indexed)
                  SizedBox(
                    height:
                        row.height -
                        (index == 0 ? 0 : 5) -
                        (index == activeRows.length - 1 ? 0 : 5),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.fromLTRB(
                        safePadding.left + 8,
                        index == 0 ? 7 : 2,
                        safePadding.right + 8,
                        index == activeRows.length - 1 ? 7 : 2,
                      ),
                      children: [
                        if (index == 0 && onOpenAppearance != null)
                          _Key(
                            icon: Icons.palette_outlined,
                            palette: palette,
                            brightness: brightness,
                            onPressed: onOpenAppearance!,
                          ),
                        for (final item in row.items)
                          _buildItem(context, item),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, TerminalKeyboardItem item) {
    final action = item.action;
    if (item.kind == TerminalKeyboardItemKind.builtIn && action != null) {
      return _buildAction(context, action);
    }
    return _Key(
      label: item.displayLabel,
      palette: palette,
      brightness: brightness,
      onPressed: () {
        final text = item.text;
        if (text != null && text.isNotEmpty) {
          terminal.textInput(item.submit ? '$text\r' : text);
        }
        _focusTerminal();
      },
    );
  }

  Widget _buildAction(BuildContext context, TerminalKeyboardAction action) {
    return switch (action) {
      TerminalKeyboardAction.control => _ToggleKey(
        label: action.label,
        palette: palette,
        brightness: brightness,
        selected: keyboardController.ctrl,
        onPressed: () {
          keyboardController.ctrl = !keyboardController.ctrl;
          _focusTerminal();
        },
      ),
      TerminalKeyboardAction.alt => _ToggleKey(
        label: action.label,
        palette: palette,
        brightness: brightness,
        selected: keyboardController.alt,
        onPressed: () {
          keyboardController.alt = !keyboardController.alt;
          _focusTerminal();
        },
      ),
      TerminalKeyboardAction.fullscreen => _Key(
        icon: fullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        palette: palette,
        brightness: brightness,
        onPressed: () {
          onToggleFullscreen();
          _focusTerminal();
        },
      ),
      TerminalKeyboardAction.arrowUp => _Key(
        icon: Icons.keyboard_arrow_up_rounded,
        palette: palette,
        brightness: brightness,
        repeat: true,
        onPressed: () => _sendKey(TerminalKey.arrowUp),
      ),
      TerminalKeyboardAction.arrowDown => _Key(
        icon: Icons.keyboard_arrow_down_rounded,
        palette: palette,
        brightness: brightness,
        repeat: true,
        onPressed: () => _sendKey(TerminalKey.arrowDown),
      ),
      TerminalKeyboardAction.arrowLeft => _Key(
        icon: Icons.keyboard_arrow_left_rounded,
        palette: palette,
        brightness: brightness,
        repeat: true,
        onPressed: () => _sendKey(TerminalKey.arrowLeft),
      ),
      TerminalKeyboardAction.arrowRight => _Key(
        icon: Icons.keyboard_arrow_right_rounded,
        palette: palette,
        brightness: brightness,
        repeat: true,
        onPressed: () => _sendKey(TerminalKey.arrowRight),
      ),
      TerminalKeyboardAction.escape => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendKey(TerminalKey.escape),
      ),
      TerminalKeyboardAction.tab => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendKey(TerminalKey.tab),
      ),
      TerminalKeyboardAction.home => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendKey(TerminalKey.home),
      ),
      TerminalKeyboardAction.end => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendKey(TerminalKey.end),
      ),
      TerminalKeyboardAction.pageUp => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendKey(TerminalKey.pageUp),
      ),
      TerminalKeyboardAction.pageDown => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendKey(TerminalKey.pageDown),
      ),
      TerminalKeyboardAction.controlC => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendCtrlChar(TerminalKey.keyC, '\x03'),
      ),
      TerminalKeyboardAction.controlD => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendCtrlChar(TerminalKey.keyD, '\x04'),
      ),
      TerminalKeyboardAction.controlZ => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendCtrlChar(TerminalKey.keyZ, '\x1a'),
      ),
      TerminalKeyboardAction.controlL => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendCtrlChar(TerminalKey.keyL, '\x0c'),
      ),
      TerminalKeyboardAction.colon => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendText(':'),
      ),
      TerminalKeyboardAction.slash => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendText('/'),
      ),
      TerminalKeyboardAction.pipe => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendText('|'),
      ),
      TerminalKeyboardAction.dash => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () => _sendText('-'),
      ),
      TerminalKeyboardAction.paste => _Key(
        label: action.label,
        palette: palette,
        brightness: brightness,
        onPressed: () async {
          if (onPaste != null) {
            onPaste!();
          } else {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            final text = data?.text;
            if (text != null && text.isNotEmpty) {
              terminal.paste(text);
            }
          }
          _focusTerminal();
        },
      ),
      TerminalKeyboardAction.functionKeys => _Key(
        label: 'Fn',
        palette: palette,
        brightness: brightness,
        onPressed: () => _showFunctionKeysSheet(context),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  void _sendKey(TerminalKey key, {bool ctrl = false, bool alt = false}) {
    terminal.keyInput(
      key,
      ctrl: ctrl || keyboardController.ctrl,
      alt: alt || keyboardController.alt,
    );
    keyboardController.clearModifiers();
    _focusTerminal();
  }

  void _sendCtrlChar(TerminalKey key, String fallback) {
    final handled = terminal.keyInput(key, ctrl: true);
    if (!handled) {
      terminal.textInput(fallback);
    }
    keyboardController.clearModifiers();
    _focusTerminal();
  }

  void _sendText(String text) {
    terminal.textInput(text);
    _focusTerminal();
  }

  void _focusTerminal() {
    focusNode.requestFocus();
  }

  void _showFunctionKeysSheet(BuildContext context) {
    final fKeys = <({String label, TerminalKey key})>[
      (label: 'F1', key: TerminalKey.f1),
      (label: 'F2', key: TerminalKey.f2),
      (label: 'F3', key: TerminalKey.f3),
      (label: 'F4', key: TerminalKey.f4),
      (label: 'F5', key: TerminalKey.f5),
      (label: 'F6', key: TerminalKey.f6),
      (label: 'F7', key: TerminalKey.f7),
      (label: 'F8', key: TerminalKey.f8),
      (label: 'F9', key: TerminalKey.f9),
      (label: 'F10', key: TerminalKey.f10),
      (label: 'F11', key: TerminalKey.f11),
      (label: 'F12', key: TerminalKey.f12),
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.panelFor(brightness),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final fk in fKeys)
                ActionChip(
                  label: Text(
                    fk.label,
                    style: TextStyle(
                      color: palette.foregroundFor(brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: palette.panelElevatedFor(brightness),
                  side: BorderSide(color: palette.borderFor(brightness)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendKey(fk.key);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({
    this.label,
    this.icon,
    required this.palette,
    required this.brightness,
    required this.onPressed,
    this.repeat = false,
  });

  final String? label;
  final IconData? icon;
  final AppPalette palette;
  final Brightness brightness;
  final VoidCallback onPressed;
  final bool repeat;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  Timer? _repeatDelay;
  Timer? _repeatTick;

  void _startRepeat() {
    if (!widget.repeat) return;
    _stopRepeat();
    _repeatDelay = Timer(const Duration(milliseconds: 340), () {
      _repeatTick = Timer.periodic(const Duration(milliseconds: 65), (_) {
        widget.onPressed();
      });
    });
  }

  void _stopRepeat() {
    _repeatDelay?.cancel();
    _repeatDelay = null;
    _repeatTick?.cancel();
    _repeatTick = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.palette.panelElevatedFor(widget.brightness);
    final fg = widget.palette.foregroundFor(widget.brightness);
    final border = widget.palette.borderFor(widget.brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        onLongPressStart: widget.repeat ? (_) => _startRepeat() : null,
        onLongPressEnd: widget.repeat ? (_) => _stopRepeat() : null,
        onLongPressCancel: widget.repeat ? _stopRepeat : null,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40, minHeight: 30),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: widget.icon != null
                      ? Icon(widget.icon, size: 18, color: fg)
                      : Text(
                          widget.label ?? '',
                          style: TextStyle(
                            color: fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleKey extends StatelessWidget {
  const _ToggleKey({
    required this.label,
    required this.palette,
    required this.brightness,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final AppPalette palette;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? palette.accent.withValues(alpha: 0.22)
        : palette.panelElevatedFor(brightness);
    final fg = selected
        ? palette.accent
        : palette.foregroundFor(brightness);
    final border = selected
        ? palette.accent
        : palette.borderFor(brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 42, minHeight: 30),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
