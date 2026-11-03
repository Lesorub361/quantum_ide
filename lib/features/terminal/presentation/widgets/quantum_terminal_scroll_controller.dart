import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart' as xt;

/// Intelligent terminal scroll controller that prevents mobile virtual keyboards
/// and empty buffer trailing lines from pushing the active cursor off-screen.
class QuantumTerminalScrollController extends ScrollController {
  final xt.Terminal terminal;
  VoidCallback? _terminalListener;
  bool _wasFollowingCursor = true;

  QuantumTerminalScrollController({
    required this.terminal,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  }) {
    _terminalListener = _onTerminalUpdated;
    terminal.addListener(_terminalListener!);
  }

  void _onTerminalUpdated() {
    if (!hasClients) return;
    final pos = position;
    if (pos is! _QuantumTerminalScrollPosition) return;

    if (_wasFollowingCursor) {
      final bound = pos.getCursorTargetOffset();
      if ((pos.pixels - bound).abs() > 1.0) {
        pos.jumpTo(bound);
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _QuantumTerminalScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      terminal: terminal,
      onUserScrollTrackingChanged: (following) {
        _wasFollowingCursor = following;
      },
    );
  }

  @override
  void dispose() {
    if (_terminalListener != null) {
      terminal.removeListener(_terminalListener!);
      _terminalListener = null;
    }
    super.dispose();
  }
}

class _QuantumTerminalScrollPosition extends ScrollPositionWithSingleContext {
  final xt.Terminal terminal;
  final ValueChanged<bool> onUserScrollTrackingChanged;

  _QuantumTerminalScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.terminal,
    required this.onUserScrollTrackingChanged,
  });

  double getCursorTargetOffset() {
    if (viewportDimension <= 0 || maxScrollExtent <= 0) return 0.0;

    final totalLines = terminal.buffer.lines.length;
    if (totalLines <= 0) return 0.0;

    final cellHeight = (maxScrollExtent + viewportDimension) / totalLines;
    if (cellHeight <= 0) return 0.0;

    final cursorY = terminal.buffer.absoluteCursorY;
    final cursorBottom = (cursorY + 1) * cellHeight;

    return math.max(0.0, cursorBottom - viewportDimension);
  }

  double _boundOffset(double targetPixels) {
    if (viewportDimension <= 0 || maxScrollExtent <= 0) return targetPixels;

    final totalLines = terminal.buffer.lines.length;
    if (totalLines <= 0) return targetPixels;

    final cellHeight = (maxScrollExtent + viewportDimension) / totalLines;
    if (cellHeight <= 0) return targetPixels;

    final cursorY = terminal.buffer.absoluteCursorY;
    final cursorTop = cursorY * cellHeight;
    final cursorBottom = (cursorY + 1) * cellHeight;

    // 1. If cursor is already fully visible in current viewport, keep current scroll position
    if (hasPixels && pixels <= cursorTop && (pixels + viewportDimension) >= cursorBottom) {
      return pixels;
    }

    // 2. Cursor target offset to show cursor line at bottom of viewport
    final maxOffsetForCursor = math.max(0.0, cursorBottom - viewportDimension);

    // 3. If jumping past the cursor into empty trailing buffer lines, clamp to cursor
    if (targetPixels > maxOffsetForCursor) {
      return maxOffsetForCursor;
    }

    return targetPixels;
  }

  @override
  void jumpTo(double value) {
    final bounded = _boundOffset(value);
    super.jumpTo(bounded);
    _checkIfFollowingCursor();
  }

  @override
  void correctBy(double correction) {
    if (hasPixels && correction > 0 && maxScrollExtent > 0) {
      final target = pixels + correction;
      final bounded = _boundOffset(target);
      super.correctBy(bounded - pixels);
      _checkIfFollowingCursor();
      return;
    }
    super.correctBy(correction);
    _checkIfFollowingCursor();
  }

  @override
  double setPixels(double newPixels) {
    final res = super.setPixels(newPixels);
    _checkIfFollowingCursor();
    return res;
  }

  void _checkIfFollowingCursor() {
    if (!hasPixels) return;
    final target = getCursorTargetOffset();
    // Following cursor if within 30px of target
    final isFollowing = (pixels - target).abs() < 30.0;
    onUserScrollTrackingChanged(isFollowing);
  }
}
