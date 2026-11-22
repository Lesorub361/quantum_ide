import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextEdit extends StatefulWidget {
  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    // this.initEditingState = TextEditingValue.empty,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.newline,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
  });

  final Widget child;

  final void Function(String) onInsert;

  final void Function() onDelete;

  final void Function(String?) onComposing;

  final void Function(TextInputAction) onAction;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  final FocusNode focusNode;

  final bool autofocus;

  final bool readOnly;

  final TextInputType inputType;

  final TextInputAction inputAction;

  final Brightness keyboardAppearance;

  final bool deleteDetection;

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit> with TextInputClient {
  TextInputConnection? _connection;
  bool _hasComposing = false;
  Size? _lastEditableSize;
  Rect? _lastCaretRect;
  Timer? _editableRectThrottleTimer;
  Rect? _pendingEditableRect;
  Rect? _pendingCaretRect;
  DateTime _lastEditableRectSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _editableRectMinInterval = Duration(milliseconds: 80);

  @override
  void initState() {
    widget.focusNode.addListener(_onFocusChange);
    super.initState();
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else {
      if (oldWidget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    _resetEditableCache();
    if (hasInputConnection) {
      _connection?.close();
    }
  }

  void setEditingState(TextEditingValue value) {
    _currentEditingState = value;
    _connection?.setEditingState(value);
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    if (_lastEditableSize == rect.size && _lastCaretRect == caretRect) {
      _pendingEditableRect = null;
      _pendingCaretRect = null;
      _editableRectThrottleTimer?.cancel();
      _editableRectThrottleTimer = null;
      return;
    }

    final elapsed = DateTime.now().difference(_lastEditableRectSentAt);
    if (elapsed >= _editableRectMinInterval) {
      _pendingEditableRect = null;
      _pendingCaretRect = null;
      _editableRectThrottleTimer?.cancel();
      _editableRectThrottleTimer = null;
      _sendEditableRectNow(rect, caretRect);
      return;
    }

    _pendingEditableRect = rect;
    _pendingCaretRect = caretRect;
    if (_editableRectThrottleTimer == null ||
        !_editableRectThrottleTimer!.isActive) {
      final remaining = _editableRectMinInterval - elapsed;
      _editableRectThrottleTimer = Timer(remaining, () {
        _editableRectThrottleTimer = null;
        final pendingRect = _pendingEditableRect;
        final pendingCaret = _pendingCaretRect;
        _pendingEditableRect = null;
        _pendingCaretRect = null;
        if (mounted &&
            hasInputConnection &&
            pendingRect != null &&
            pendingCaret != null) {
          _sendEditableRectNow(pendingRect, pendingCaret);
        }
      });
    }
  }

  void _sendEditableRectNow(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    if (_lastEditableSize != rect.size) {
      _connection?.setEditableSizeAndTransform(
        rect.size,
        Matrix4.translationValues(0, 0, 0),
      );
      _lastEditableSize = rect.size;
    }

    if (_lastCaretRect != caretRect) {
      _connection?.setCaretRect(caretRect);
      _lastCaretRect = caretRect;
    }

    _lastEditableRectSentAt = DateTime.now();
  }

  void _resetEditableCache() {
    _editableRectThrottleTimer?.cancel();
    _editableRectThrottleTimer = null;
    _pendingEditableRect = null;
    _pendingCaretRect = null;
    _lastEditableSize = null;
    _lastCaretRect = null;
    _hasComposing = false;
  }

  void _onFocusChange() {
    _openOrCloseInputConnectionIfNeeded();
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (_currentEditingState.composing.isCollapsed) {
      return widget.onKeyEvent(focusNode, event);
    }

    return KeyEventResult.skipRemainingHandlers;
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!widget.focusNode.hasFocus) {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (hasInputConnection) {
      if (widget.inputType != TextInputType.none) {
        _connection!.show();
      }
    } else {
      final config = TextInputConfiguration(
        inputType: widget.inputType,
        inputAction: widget.inputAction,
        keyboardAppearance: widget.keyboardAppearance,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      );

      _connection = TextInput.attach(this, config);

      if (widget.inputType != TextInputType.none) {
        _connection!.show();
      }

      // setEditableRect(Rect.zero, Rect.zero);

      _connection!.setEditingState(_initEditingState);
    }
  }

  void _closeInputConnectionIfNeeded() {
    _resetEditableCache();
    if (_connection != null && _connection!.attached) {
      _connection!.close();
      _connection = null;
    }
  }

  TextEditingValue get _initEditingState => widget.deleteDetection
      ? const TextEditingValue(
          text: '  ',
          selection: TextSelection.collapsed(offset: 2),
        )
      : const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );

  late var _currentEditingState = _initEditingState.copyWith();

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null;
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _currentEditingState = value;

    // Get input after composing is done
    if (!_currentEditingState.composing.isCollapsed) {
      final text = _currentEditingState.text;
      final composingText = _currentEditingState.composing.textInside(text);
      _hasComposing = true;
      widget.onComposing(composingText);
      return;
    }

    if (_hasComposing) {
      _hasComposing = false;
      widget.onComposing(null);
    }

    if (_currentEditingState.text.length < _initEditingState.text.length) {
      widget.onDelete();
    } else {
      final textDelta = _currentEditingState.text.substring(
        _initEditingState.text.length,
      );

      widget.onInsert(textDelta);
    }

    // Reset editing state if composing is done
    if (hasInputConnection &&
        _currentEditingState.composing.isCollapsed &&
        _currentEditingState.text != _initEditingState.text) {
      _connection?.setEditingState(_initEditingState);
    }
  }

  @override
  void performAction(TextInputAction action) {
    // print('performAction $action');
    widget.onAction(action);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // print('updateFloatingCursor $point');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // print('showAutocorrectionPromptRect');
  }

  @override
  void connectionClosed() {
    _resetEditableCache();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // print('performPrivateCommand $action');
  }

  @override
  void insertTextPlaceholder(Size size) {
    // print('insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    // print('removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    // print('showToolbar');
  }
}
