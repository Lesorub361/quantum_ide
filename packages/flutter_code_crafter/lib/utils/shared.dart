import '../code_crafter/code_crafter_controller.dart';
import './utils.dart';
import 'package:flutter/material.dart';

/// This class is a singleton that holds shared state and configurations for the application.
/// It is used internally by the [CodeCrafter] widget and other components to maintain a consistent state across the application.
/// It includes properties for AI responses, gutter width, theme styles, text styles, tab size, diagnostics, and more.
class Shared {
  static final Shared _instance = Shared._internal();
  factory Shared() => _instance;
  Shared._internal();

  String? aiResponse;
  double gutterWidth = 65;
  Map<String, TextStyle> theme = {};
  TextStyle? textStyle, aiOverlayStyle;
  int tabSize = 0;
  int? lastCursorPosition;
  List<LspErrors> diagnostics = [];
  bool enableRulerLines = true;
  CodeCrafterController controller = CodeCrafterController();
  ValueNotifier<List<LineState>> lineStates = ValueNotifier([]);
}
