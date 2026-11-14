import 'package:flutter/material.dart';

sealed class OverlayStyle {
  /// The elevation of the overlay, which determines the shadow depth.
  /// Defaults to 6.
  final double elevation;

  /// The background color of the overlay.
  final Color backgroundColor;

  /// The color used when the overlay is focused.
  final Color focusColor;

  /// The color used when the overlay is hovered.
  final Color hoverColor;

  /// The color used for the splash effect when the overlay is tapped.
  final Color splashColor;

  /// The shape of the overlay, which defines its border and corner radius.
  /// This can be a [ShapeBorder] such as [RoundedRectangleBorder], [CircleBorder], etc.
  final ShapeBorder shape;

  /// The text style used for the text in the overlay.
  /// This is typically a [TextStyle] that defines the font size, weight, color, etc.
  final TextStyle textStyle;
  OverlayStyle({
    this.elevation = 6,
    required this.shape,
    required this.backgroundColor,
    required this.focusColor,
    required this.hoverColor,
    required this.splashColor,
    required this.textStyle,
  });
}

class SuggestionStyle extends OverlayStyle {
  SuggestionStyle({
    super.elevation,
    required super.shape,
    required super.backgroundColor,
    required super.focusColor,
    required super.hoverColor,
    required super.splashColor,
    required super.textStyle,
  });
}

class HoverDetailsStyle extends OverlayStyle {
  HoverDetailsStyle({
    super.elevation,
    required super.shape,
    required super.backgroundColor,
    required super.focusColor,
    required super.hoverColor,
    required super.splashColor,
    required super.textStyle,
  });
}
