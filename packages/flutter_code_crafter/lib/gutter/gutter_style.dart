import 'package:flutter/material.dart';

/// This class provides styling options for the Gutter.
class GutterStyle {
  /// The style for line numbers in the gutter. Expected to be a [TextStyle].
  final TextStyle? lineNumberStyle;

  /// The color for the breakpoint icon in the gutter. Defaults to [Colors.red].
  final Color breakpointColor;

  /// The color for the unfilled breakpoint icon in the gutter. Defaults to [Colors.transparent].
  final Color unfilledBreakpointColor;

  /// The color for the folded line folding indicator icon in the gutter. Defaults to [Colors.grey].
  final Color foldedIconColor;

  /// The color for the unfolded line folding indicator icon in the gutter. Defaults to [Colors.grey].
  final Color unfoldedIconColor;

  /// Color of the vertical divider line between gutter and editor.
  final Color? dividerColor;

  /// The size of the breakpoint icon in the gutter. Defaults to (widget?.textStyle?.fontSize ?? 14) * 0.6.
  ///
  /// Recommended to leave it null, because the default value is dynamic based on editor fontSize.
  final double? breakpointSize;

  /// The width of the gutter. Dynamic by default, which means it can adapt best width based on line number. So recommended to leave it null.
  final double? gutterWidth;

  /// The thickness of the vertical divider between gutter and editor.
  final double? dividerThickness;

  /// The size of the folding icon in the gutter. Defaults to (widget?.textStyle?.fontSize ?? 14) * 1.2.
  ///
  /// /// Recommended to leave it null, because the default value is dynamic based on editor fontSize.
  final double? foldingIconSize;

  /// The icons used for breakpoints and folding indicators in the gutter.
  ///
  /// Defaults to [Icons.circle] for breakpoints.
  final IconData breakpointIcon;

  /// The icon used for unfilled breakpoints in the gutter.
  ///
  /// Defaults to [Icons.circle_outlined] for unfilled breakpoints.
  final IconData unfilledBreakpointIcon;

  /// The icon used for the folded line folding indicator in the gutter.
  ///
  /// Defaults to [Icons.chevron_right_outlined] for folded lines.
  final IconData unfoldedIcon;

  /// The icon used for the unfolded line folding indicator in the gutter.
  ///
  /// Defaults to [Icons.keyboard_arrow_down_outlined] for unfolded lines.
  final IconData foldedIcon;
  GutterStyle({
    this.lineNumberStyle,
    this.gutterWidth,
    this.breakpointIcon = Icons.circle,
    this.unfilledBreakpointIcon = Icons.circle_outlined,
    this.foldedIcon = Icons.chevron_right_outlined,
    this.unfoldedIcon = Icons.keyboard_arrow_down_outlined,
    this.dividerColor,
    this.dividerThickness,
    this.breakpointSize,
    this.foldingIconSize,
    this.breakpointColor = Colors.red,
    this.unfilledBreakpointColor = Colors.transparent,
    this.foldedIconColor = Colors.grey,
    this.unfoldedIconColor = Colors.grey,
  });
}
