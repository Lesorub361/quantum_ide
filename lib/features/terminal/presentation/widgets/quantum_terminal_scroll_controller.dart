import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart' as xt;

/// Intelligent terminal scroll controller that prevents mobile virtual keyboards
/// and empty buffer trailing lines from pushing the active cursor off-screen.
class QuantumTerminalScrollController extends ScrollController {
  final xt.Terminal terminal;
  VoidCallback? _terminalListener;
  bool _wasFollowingCursor = true;

  bool get wasFollowingCursor => _wasFollowingCursor;

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
      if (pos.maxScrollExtent > 0) {
        pos.jumpTo(pos.maxScrollExtent);
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
    return maxScrollExtent;
  }

  double _boundOffset(double targetPixels) {
    if (viewportDimension <= 0 || maxScrollExtent <= 0) {
      return math.max(0.0, targetPixels);
    }
    return targetPixels.clamp(0.0, maxScrollExtent);
  }

  @override
  void jumpTo(double value) {
    final bounded = _boundOffset(value);
    super.jumpTo(bounded);
    _checkIfFollowingCursor();
  }

  @override
  void correctBy(double correction) {
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
    final isFollowing = (pixels - maxScrollExtent).abs() < 40.0;
    onUserScrollTrackingChanged(isFollowing);
  }
}
