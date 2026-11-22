import 'package:flutter/widgets.dart';

/// Rebuilds only when the on-screen keyboard crosses [threshold] logical pixels,
/// avoiding 60-120Hz rebuilds on intermediate slide animation frames.
class KeyboardVisibilityBuilder extends StatefulWidget {
  const KeyboardVisibilityBuilder({
    super.key,
    this.threshold = 20.0,
    required this.builder,
  });

  final double threshold;
  final Widget Function(BuildContext context, bool isKeyboardOpen) builder;

  @override
  State<KeyboardVisibilityBuilder> createState() =>
      _KeyboardVisibilityBuilderState();
}

class _KeyboardVisibilityBuilderState extends State<KeyboardVisibilityBuilder>
    with WidgetsBindingObserver {
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isOpen = _computeIsOpen();
  }

  @override
  void didChangeMetrics() {
    final nextOpen = _computeIsOpen();
    if (nextOpen != _isOpen && mounted) {
      setState(() => _isOpen = nextOpen);
    }
  }

  bool _computeIsOpen() {
    final view = View.maybeOf(context);
    if (view == null || view.devicePixelRatio <= 0) return false;
    final logicalBottom = view.viewInsets.bottom / view.devicePixelRatio;
    return logicalBottom > widget.threshold;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isOpen);
  }
}
