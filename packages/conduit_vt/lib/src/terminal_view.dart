import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:conduit_vt/src/core/buffer/cell_offset.dart';
import 'package:conduit_vt/src/core/input/keys.dart';
import 'package:conduit_vt/src/terminal.dart';
import 'package:conduit_vt/src/ui/cell_overlay.dart';
import 'package:conduit_vt/src/ui/controller.dart';
import 'package:conduit_vt/src/ui/cursor_type.dart';
import 'package:conduit_vt/src/ui/custom_text_edit.dart';
import 'package:conduit_vt/src/ui/gesture/gesture_handler.dart';
import 'package:conduit_vt/src/ui/input_map.dart';
import 'package:conduit_vt/src/ui/keyboard_listener.dart';
import 'package:conduit_vt/src/ui/keyboard_visibility.dart';
import 'package:conduit_vt/src/ui/render.dart';
import 'package:conduit_vt/src/ui/scroll_handler.dart';
import 'package:conduit_vt/src/ui/shortcut/actions.dart';
import 'package:conduit_vt/src/ui/shortcut/shortcuts.dart';
import 'package:conduit_vt/src/ui/terminal_text_style.dart';
import 'package:conduit_vt/src/ui/terminal_theme.dart';
import 'package:conduit_vt/src/ui/themes.dart';

class TerminalView extends StatefulWidget {
  const TerminalView(
    this.terminal, {
    super.key,
    this.controller,
    this.theme = TerminalThemes.defaultTheme,
    this.textStyle = const TerminalStyle(),
    this.textScaler,
    this.padding,
    this.scrollController,
    this.autoResize = true,
    this.backgroundOpacity = 1,
    this.overlays = const <TerminalCellOverlay>[],
    this.focusNode,
    this.autofocus = false,
    this.onTapUp,
    this.onOpenLink,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.mouseCursor = SystemMouseCursors.text,
    this.keyboardType = TextInputType.emailAddress,
    this.keyboardAppearance = Brightness.dark,
    this.cursorType = TerminalCursorType.block,
    this.alwaysShowCursor = false,
    this.deleteDetection = false,
    this.shortcuts,
    this.onKeyEvent,
    this.readOnly = false,
    this.hardwareKeyboardOnly = false,
    this.simulateScroll = true,
  });

  /// The underlying terminal that this widget renders.
  final Terminal terminal;

  final TerminalController? controller;

  /// The theme to use for this terminal.
  final TerminalTheme theme;

  /// The style to use for painting characters.
  final TerminalStyle textStyle;

  final TextScaler? textScaler;

  /// Padding around the inner [Scrollable] widget.
  final EdgeInsets? padding;

  /// Scroll controller for the inner [Scrollable] widget.
  final ScrollController? scrollController;

  /// Should this widget automatically notify the underlying terminal when its
  /// size changes. [true] by default.
  final bool autoResize;

  /// Opacity of the terminal background. Set to 0 to make the terminal
  /// background transparent.
  final double backgroundOpacity;

  /// Transient cells painted over the terminal buffer without mutating it.
  final List<TerminalCellOverlay> overlays;

  /// An optional focus node to use as the focus node for this widget.
  final FocusNode? focusNode;

  /// True if this widget will be selected as the initial focus when no other
  /// node in its scope is currently focused.
  final bool autofocus;

  /// Callback for when the user taps on the terminal.
  final void Function(TapUpDetails, CellOffset)? onTapUp;

  /// Callback invoked when the user taps or selects "Open Link" on a terminal URL.
  final void Function(String url)? onOpenLink;

  /// Function called when the user taps on the terminal with a secondary
  /// button.
  final void Function(TapDownDetails, CellOffset)? onSecondaryTapDown;

  /// Function called when the user stops holding down a secondary button.
  final void Function(TapUpDetails, CellOffset)? onSecondaryTapUp;

  /// The mouse cursor for mouse pointers that are hovering over the terminal.
  /// [SystemMouseCursors.text] by default.
  final MouseCursor mouseCursor;

  /// The type of information for which to optimize the text input control.
  /// [TextInputType.emailAddress] by default.
  final TextInputType keyboardType;

  /// The appearance of the keyboard. [Brightness.dark] by default.
  ///
  /// This setting is only honored on iOS devices.
  final Brightness keyboardAppearance;

  /// The type of cursor to use. [TerminalCursorType.block] by default.
  final TerminalCursorType cursorType;

  /// Whether to always show the cursor. This is useful for debugging.
  /// [false] by default.
  final bool alwaysShowCursor;

  /// Workaround to detect delete key for platforms and IMEs that does not
  /// emit hardware delete event. Prefered on mobile platforms. [false] by
  /// default.
  final bool deleteDetection;

  /// Shortcuts for this terminal. This has higher priority than input handler
  /// of the terminal If not provided, [defaultTerminalShortcuts] will be used.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Keyboard event handler of the terminal. This has higher priority than
  /// [shortcuts] and input handler of the terminal.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// True if no input should send to the terminal.
  final bool readOnly;

  /// True if only hardware keyboard events should be used as input. This will
  /// also prevent any on-screen keyboard to be shown.
  final bool hardwareKeyboardOnly;

  /// If true, when the terminal is in alternate buffer (for example running
  /// vim, man, etc), if the application does not declare that it can handle
  /// scrolling, the terminal will simulate scrolling by sending up/down arrow
  /// keys to the application. This is standard behavior for most terminal
  /// emulators. True by default.
  final bool simulateScroll;

  @override
  State<TerminalView> createState() => TerminalViewState();
}

class TerminalViewState extends State<TerminalView> {
  late FocusNode _focusNode;

  late final ShortcutManager _shortcutManager;

  final _customTextEditKey = GlobalKey<CustomTextEditState>();

  final _scrollableKey = GlobalKey<ScrollableState>();

  final _viewportKey = GlobalKey();

  String? _composingText;

  late TerminalController _controller;

  late ScrollController _scrollController;

  final _contextMenuController = ContextMenuController();

  Timer? _selectionToolbarTimer;

  bool _selectionClearedByTapDown = false;

  final _selectionHandlesController = OverlayPortalController();

  final _selectionRevision = ValueNotifier<int>(0);

  bool _draggingHandle = false;

  Offset _handleDragOffset = Offset.zero;

  Offset? _magnifierFocalPoint;

  Timer? _autoScrollTimer;

  int _autoScrollDirection = 0;

  bool _autoScrollIsStart = false;

  Offset? _lastHandleTargetGlobal;

  RenderTerminal get renderTerminal =>
      _viewportKey.currentContext!.findRenderObject() as RenderTerminal;

  @override
  void initState() {
    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TerminalController();
    _controller.addListener(_handleSelectionChanged);
    _scrollController = widget.scrollController ?? ScrollController();
    _shortcutManager = ShortcutManager(
      shortcuts: widget.shortcuts ?? defaultTerminalShortcuts,
    );
    super.initState();
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    if (oldWidget.focusNode != widget.focusNode) {
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_handleSelectionChanged);
      if (oldWidget.controller == null) {
        _controller.dispose();
      }
      _controller = widget.controller ?? TerminalController();
      _controller.addListener(_handleSelectionChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = widget.scrollController ?? ScrollController();
    }
    _shortcutManager.shortcuts = widget.shortcuts ?? defaultTerminalShortcuts;
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _selectionToolbarTimer?.cancel();
    _hideSelectionToolbar();
    _selectionRevision.dispose();
    _controller.removeListener(_handleSelectionChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _shortcutManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Scrollable(
      key: _scrollableKey,
      controller: _scrollController,
      viewportBuilder: (context, offset) {
        return _TerminalView(
          key: _viewportKey,
          terminal: widget.terminal,
          controller: _controller,
          offset: offset,
          padding: EdgeInsets.zero,
          autoResize: widget.autoResize,
          textStyle: widget.textStyle,
          textScaler: widget.textScaler ?? MediaQuery.textScalerOf(context),
          theme: widget.theme,
          overlays: widget.overlays,
          focusNode: _focusNode,
          cursorType: widget.cursorType,
          alwaysShowCursor: widget.alwaysShowCursor,
          onEditableRect: _onEditableRect,
          composingText: _composingText,
        );
      },
    );

    child = TerminalScrollGestureHandler(
      terminal: widget.terminal,
      simulateScroll: widget.simulateScroll,
      getCellOffset: (offset) => renderTerminal.getCellOffset(offset),
      getLineHeight: () => renderTerminal.lineHeight,
      child: child,
    );

    if (!widget.hardwareKeyboardOnly) {
      child = CustomTextEdit(
        key: _customTextEditKey,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        inputType: widget.keyboardType,
        keyboardAppearance: widget.keyboardAppearance,
        deleteDetection: widget.deleteDetection,
        onInsert: _onInsert,
        onDelete: () {
          _scrollToBottom();
          widget.terminal.keyInput(TerminalKey.backspace);
        },
        onComposing: _onComposing,
        onAction: (action) {
          _scrollToBottom();
          // Android sends TextInputAction.newline when the user presses the virtual keyboard's enter key.
          if (action == TextInputAction.done ||
              action == TextInputAction.newline) {
            widget.terminal.keyInput(TerminalKey.enter);
          }
        },
        onKeyEvent: _handleKeyEvent,
        readOnly: widget.readOnly,
        child: child,
      );
    } else if (!widget.readOnly) {
      // Only listen for key input from a hardware keyboard.
      child = CustomKeyboardListener(
        child: child,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onInsert: _onInsert,
        onComposing: _onComposing,
        onKeyEvent: _handleKeyEvent,
      );
    }

    child = TerminalActions(
      terminal: widget.terminal,
      controller: _controller,
      child: child,
    );

    child = KeyboardVisibilty(onKeyboardShow: _onKeyboardShow, child: child);

    child = TerminalGestureHandler(
      terminalView: this,
      terminalController: _controller,
      onSingleTapUp: _onTapUp,
      onTapDown: _onTapDown,
      onSecondaryTapDown:
          widget.onSecondaryTapDown != null ? _onSecondaryTapDown : null,
      onSecondaryTapUp:
          widget.onSecondaryTapUp != null ? _onSecondaryTapUp : null,
      readOnly: widget.readOnly,
      child: child,
    );

    child = MouseRegion(cursor: widget.mouseCursor, child: child);

    child = Container(
      color: widget.theme.background.withValues(
        alpha: widget.theme.background.a * widget.backgroundOpacity,
      ),
      padding: widget.padding,
      child: child,
    );

    return OverlayPortal(
      controller: _selectionHandlesController,
      overlayChildBuilder: _buildSelectionHandles,
      child: child,
    );
  }

  void requestKeyboard() {
    _customTextEditKey.currentState?.requestKeyboard();
  }

  void closeKeyboard() {
    _customTextEditKey.currentState?.closeKeyboard();
  }

  Rect get cursorRect {
    return renderTerminal.cursorOffset & renderTerminal.cellSize;
  }

  Rect get globalCursorRect {
    return renderTerminal.localToGlobal(renderTerminal.cursorOffset) &
        renderTerminal.cellSize;
  }

  void _onTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);

    if (_selectionClearedByTapDown || _controller.selection != null) {
      _selectionClearedByTapDown = false;
      _controller.clearSelection();
      return;
    }

    final tappedUrl = widget.terminal.buffer.getUrlAt(offset);
    if (tappedUrl != null && tappedUrl.isNotEmpty) {
      if (widget.onOpenLink != null) {
        widget.onOpenLink!(tappedUrl);
      } else {
        widget.onTapUp?.call(details, offset);
      }
      return;
    }

    widget.onTapUp?.call(details, offset);

    if (!widget.hardwareKeyboardOnly) {
      _customTextEditKey.currentState?.requestKeyboard();
    } else {
      _focusNode.requestFocus();
    }
  }

  void _onTapDown(_) {
    _selectionClearedByTapDown = _controller.selection != null;
  }

  void _handleSelectionChanged() {
    if (_controller.selection == null) {
      _selectionToolbarTimer?.cancel();
      _hideSelectionToolbar();
      _draggingHandle = false;
      _magnifierFocalPoint = null;
      if (_selectionHandlesController.isShowing) {
        _selectionHandlesController.hide();
      }
      _bumpSelectionRevision();
      return;
    }

    if (!_selectionHandlesController.isShowing) {
      _selectionHandlesController.show();
    }
    _bumpSelectionRevision();
    _hideSelectionToolbar();
    _selectionToolbarTimer?.cancel();
    if (!_draggingHandle) {
      _selectionToolbarTimer = Timer(
        const Duration(milliseconds: 150),
        _showSelectionToolbar,
      );
    }
  }

  void _bumpSelectionRevision() {
    _selectionRevision.value++;
  }

  Widget _buildSelectionHandles(BuildContext overlayContext) {
    return ValueListenableBuilder<int>(
      valueListenable: _selectionRevision,
      builder: (ctx, _, __) {
        if (_viewportKey.currentContext == null ||
            _controller.selection == null) {
          return const SizedBox.shrink();
        }

        final render = renderTerminal;
        final startGlobal = render.selectionStartHandleOffset;
        final endGlobal = render.selectionEndHandleOffset;
        if (startGlobal == null || endGlobal == null) {
          return const SizedBox.shrink();
        }

        final overlayBox =
            overlayContext.findRenderObject() as RenderBox?;
        final startLocal = overlayBox != null && overlayBox.hasSize
            ? overlayBox.globalToLocal(startGlobal)
            : startGlobal;
        final endLocal = overlayBox != null && overlayBox.hasSize
            ? overlayBox.globalToLocal(endGlobal)
            : endGlobal;
        final magnifierLocal =
            _magnifierFocalPoint != null &&
                    overlayBox != null &&
                    overlayBox.hasSize
                ? overlayBox.globalToLocal(_magnifierFocalPoint!)
                : _magnifierFocalPoint;

        return SizedBox.expand(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _buildHandle(
                localCorner: startLocal,
                globalCorner: startGlobal,
                isStart: true,
              ),
              _buildHandle(
                localCorner: endLocal,
                globalCorner: endGlobal,
                isStart: false,
              ),
              if (_draggingHandle && magnifierLocal != null)
                _buildMagnifier(magnifierLocal),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle({
    required Offset localCorner,
    required Offset globalCorner,
    required bool isStart,
  }) {
    const visual = 20.0;
    const touch = 56.0;
    final center = localCorner.translate(0, visual / 2 + 2);
    return Positioned(
      left: center.dx - touch / 2,
      top: center.dy - touch / 2,
      width: touch,
      height: touch,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) =>
            _onHandlePanStart(globalCorner, details.globalPosition),
        onPanUpdate: (details) =>
            _onHandlePanUpdate(details.globalPosition, isStart: isStart),
        onPanEnd: (_) => _onHandlePanEnd(),
        onPanCancel: _onHandlePanEnd,
        child: Center(
          child: Container(
            width: visual,
            height: visual,
            decoration: BoxDecoration(
              color: widget.theme.cursor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isStart ? visual / 2 : 3),
                topRight: Radius.circular(isStart ? 3 : visual / 2),
                bottomLeft: const Radius.circular(visual / 2),
                bottomRight: const Radius.circular(visual / 2),
              ),
              border: Border.all(
                color: const Color(0xAAFFFFFF),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x77000000), blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMagnifier(Offset focalPoint) {
    const size = Size(110, 56);
    const gap = 28.0;
    return Positioned(
      left: focalPoint.dx - size.width / 2,
      top: focalPoint.dy - size.height - gap,
      child: IgnorePointer(
        child: RawMagnifier(
          size: size,
          magnificationScale: 1.6,
          focalPointOffset: Offset(0, size.height / 2 + gap),
          decoration: MagnifierDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: widget.theme.cursor, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  void _onHandlePanStart(Offset globalCorner, Offset fingerGlobalPosition) {
    _draggingHandle = true;
    final cellAnchorGlobal = globalCorner.translate(
      0,
      -renderTerminal.lineHeight * 0.5,
    );
    _handleDragOffset = cellAnchorGlobal - fingerGlobalPosition;
    _magnifierFocalPoint = cellAnchorGlobal;
    _hideSelectionToolbar();
    _selectionToolbarTimer?.cancel();
    _bumpSelectionRevision();
  }

  void _updateAutoScroll(int direction, bool isStart) {
    _autoScrollIsStart = isStart;
    if (direction == 0) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      _autoScrollDirection = 0;
      return;
    }
    if (_autoScrollDirection == direction && _autoScrollTimer != null) return;
    _autoScrollDirection = direction;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
      if (!mounted || !_draggingHandle || !_scrollController.hasClients) {
        _updateAutoScroll(0, isStart);
        return;
      }
      final step = renderTerminal.lineHeight;
      final nextOffset = (_scrollController.offset + _autoScrollDirection * step)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      if ((nextOffset - _scrollController.offset).abs() < 0.5) return;
      _scrollController.jumpTo(nextOffset);
      final target = _lastHandleTargetGlobal;
      if (target != null) {
        if (_autoScrollIsStart) {
          renderTerminal.updateSelectionStart(target);
        } else {
          renderTerminal.updateSelectionEnd(target);
        }
        _bumpSelectionRevision();
      }
    });
  }

  void _onHandlePanUpdate(Offset fingerGlobalPosition, {required bool isStart}) {
    final targetGlobal = fingerGlobalPosition + _handleDragOffset;
    _lastHandleTargetGlobal = targetGlobal;
    _magnifierFocalPoint = targetGlobal;

    if (isStart) {
      renderTerminal.updateSelectionStart(targetGlobal);
    } else {
      renderTerminal.updateSelectionEnd(targetGlobal);
    }
    _bumpSelectionRevision();

    // Smoothly auto-scroll when dragging a handle near the top or bottom edge
    if (_scrollController.hasClients) {
      final localPos = renderTerminal.globalToLocal(targetGlobal);
      const edgeThreshold = 32.0;
      final viewportHeight = renderTerminal.size.height;
      if (localPos.dy < edgeThreshold && _scrollController.offset > 0) {
        _updateAutoScroll(-1, isStart);
      } else if (localPos.dy > viewportHeight - edgeThreshold &&
          _scrollController.offset <
              _scrollController.position.maxScrollExtent) {
        _updateAutoScroll(1, isStart);
      } else {
        _updateAutoScroll(0, isStart);
      }
    }
  }

  void _onHandlePanEnd() {
    _updateAutoScroll(0, false);
    _lastHandleTargetGlobal = null;
    _draggingHandle = false;
    _handleDragOffset = Offset.zero;
    _magnifierFocalPoint = null;
    _bumpSelectionRevision();
    _selectionToolbarTimer?.cancel();
    _selectionToolbarTimer = Timer(
      const Duration(milliseconds: 150),
      _showSelectionToolbar,
    );
  }

  void _showSelectionToolbar() {
    if (!mounted ||
        _controller.selection == null ||
        _viewportKey.currentContext == null) {
      return;
    }

    final rect = renderTerminal.globalSelectionRect;
    if (rect == null) {
      return;
    }

    final anchors = TextSelectionToolbarAnchors(
      primaryAnchor: rect.topCenter,
      secondaryAnchor: rect.bottomCenter,
    );

    final selection = _controller.selection;
    final selectedUrl = selection != null
        ? widget.terminal.buffer.getUrlFromSelection(selection)
        : null;

    _contextMenuController.show(
      context: context,
      contextMenuBuilder: (context) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: [
            if (selectedUrl != null && selectedUrl.isNotEmpty)
              ContextMenuButtonItem(
                label: 'Открыть ссылку',
                onPressed: () {
                  _hideSelectionToolbar();
                  _controller.clearSelection();
                  widget.onOpenLink?.call(selectedUrl);
                },
              ),
            ContextMenuButtonItem(
              type: ContextMenuButtonType.copy,
              onPressed: _copySelection,
            ),
            ContextMenuButtonItem(
              type: ContextMenuButtonType.selectAll,
              onPressed: _selectAll,
            ),
          ],
        );
      },
    );
  }

  void _hideSelectionToolbar() {
    if (_contextMenuController.isShown) {
      _contextMenuController.remove();
    }
  }

  void _copySelection() {
    final selection = _controller.selection;
    if (selection != null) {
      var text = widget.terminal.buffer.getText(selection);
      final norm = selection.normalized;
      if (norm.begin.y == norm.end.y && !text.contains('http')) {
        final oscUrl = widget.terminal.buffer.getUrlFromSelection(selection);
        if (oscUrl != null && oscUrl.isNotEmpty) {
          text = oscUrl;
        }
      }
      Clipboard.setData(ClipboardData(text: text));
    }
    _hideSelectionToolbar();
    _controller.clearSelection();
  }

  void _selectAll() {
    final buffer = widget.terminal.buffer;
    if (buffer.lines.length == 0) return;
    _controller.setSelection(
      buffer.createAnchor(0, 0),
      buffer.createAnchor(widget.terminal.viewWidth, buffer.height - 1),
    );
  }

  void _onSecondaryTapDown(TapDownDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapDown?.call(details, offset);
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    final offset = renderTerminal.getCellOffset(details.localPosition);
    widget.onSecondaryTapUp?.call(details, offset);
  }

  bool get hasInputConnection {
    return _customTextEditKey.currentState?.hasInputConnection == true;
  }

  void _onInsert(String text) {
    final key = charToTerminalKey(text.trim());

    // On mobile platforms there is no guarantee that virtual keyboard will
    // generate hardware key events. So we need first try to send the key
    // as a hardware key event. If it fails, then we send it as a text input.
    final consumed = key == null ? false : widget.terminal.keyInput(key);

    if (!consumed) {
      widget.terminal.textInput(text);
    }

    _scrollToBottom();
  }

  void _onComposing(String? text) {
    if (_composingText == text) return;
    setState(() => _composingText = text);
  }

  KeyEventResult _handleKeyEvent(FocusNode focusNode, KeyEvent event) {
    final resultOverride = widget.onKeyEvent?.call(focusNode, event);
    if (resultOverride != null && resultOverride != KeyEventResult.ignored) {
      return resultOverride;
    }

    // ignore: invalid_use_of_protected_member
    final shortcutResult = _shortcutManager.handleKeypress(
      focusNode.context!,
      event,
    );

    if (shortcutResult != KeyEventResult.ignored) {
      return shortcutResult;
    }

    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final key = keyToTerminalKey(event.logicalKey);

    if (key == null) {
      return KeyEventResult.ignored;
    }

    final handled = widget.terminal.keyInput(
      key,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );

    if (handled) {
      _scrollToBottom();
    }

    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _onKeyboardShow() {
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _onEditableRect(Rect rect, Rect caretRect) {
    _customTextEditKey.currentState?.setEditableRect(rect, caretRect);
  }

  void _scrollToBottom() {
    final position = _scrollableKey.currentState?.position;
    if (position != null) {
      position.jumpTo(position.maxScrollExtent);
    }
  }
}

class _TerminalView extends LeafRenderObjectWidget {
  const _TerminalView({
    super.key,
    required this.terminal,
    required this.controller,
    required this.offset,
    required this.padding,
    required this.autoResize,
    required this.textStyle,
    required this.textScaler,
    required this.theme,
    required this.overlays,
    required this.focusNode,
    required this.cursorType,
    required this.alwaysShowCursor,
    this.onEditableRect,
    this.composingText,
  });

  final Terminal terminal;

  final TerminalController controller;

  final ViewportOffset offset;

  final EdgeInsets padding;

  final bool autoResize;

  final TerminalStyle textStyle;

  final TextScaler textScaler;

  final TerminalTheme theme;

  final List<TerminalCellOverlay> overlays;

  final FocusNode focusNode;

  final TerminalCursorType cursorType;

  final bool alwaysShowCursor;

  final EditableRectCallback? onEditableRect;

  final String? composingText;

  @override
  RenderTerminal createRenderObject(BuildContext context) {
    return RenderTerminal(
      terminal: terminal,
      controller: controller,
      offset: offset,
      padding: padding,
      autoResize: autoResize,
      textStyle: textStyle,
      textScaler: textScaler,
      theme: theme,
      overlays: overlays,
      focusNode: focusNode,
      cursorType: cursorType,
      alwaysShowCursor: alwaysShowCursor,
      onEditableRect: onEditableRect,
      composingText: composingText,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderTerminal renderObject) {
    renderObject
      ..terminal = terminal
      ..controller = controller
      ..offset = offset
      ..padding = padding
      ..autoResize = autoResize
      ..textStyle = textStyle
      ..textScaler = textScaler
      ..theme = theme
      ..overlays = overlays
      ..focusNode = focusNode
      ..cursorType = cursorType
      ..alwaysShowCursor = alwaysShowCursor
      ..onEditableRect = onEditableRect
      ..composingText = composingText;
  }
}
