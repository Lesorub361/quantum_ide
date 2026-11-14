import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// This class is used to represent the state of a line in the editor.
/// It is used internally by the [CodeCrafter] widget to manage line states such as breakpoints and folding ranges.
class LineState {
  final int lineNumber;
  final bool hasBreakpoint;

  FoldRange? foldRange;

  LineState({required this.lineNumber, this.hasBreakpoint = false});
}

/// This class is used to represent a range of lines that can be folded in the editor.
/// It is used internally by the [CodeCrafter] widget to manage folding ranges.
class FoldRange {
  final int startLine, endLine;
  bool isFolded;
  List<String> foldedLines = [];

  FoldRange(this.startLine, this.endLine, {this.isFolded = false});
}

enum CompletionItemType {
  text(1),
  method(2),
  function(3),
  constructor(4),
  field(5),
  variable(6),
  class_(7),
  interface(8),
  module(9),
  property(10),
  unit(11),
  value_(12),
  enum_(13),
  keyword(14),
  snippet(15),
  color(16),
  file(17),
  reference(18),
  folder(19),
  enumMember(20),
  constant(21),
  struct(22),
  event(23),
  operator(24),
  typeParameter(25);

  final int value;
  const CompletionItemType(this.value);
}

Map<CompletionItemType, Icon> completionItemIcons = {
  CompletionItemType.text: Icon(Icons.text_snippet_rounded, color: Colors.grey),
  CompletionItemType.method: Icon(
    CustomIcons.method,
    color: const Color(0xff9e74c0),
  ),
  CompletionItemType.function: Icon(
    CustomIcons.method,
    color: const Color(0xff9e74c0),
  ),
  CompletionItemType.constructor: Icon(
    CustomIcons.method,
    color: const Color(0xff9e74c0),
  ),
  CompletionItemType.field: Icon(
    CustomIcons.field,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.variable: Icon(
    CustomIcons.variable,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.class_: Icon(
    CustomIcons.class_,
    color: const Color(0xffee9d28),
  ),
  CompletionItemType.interface: Icon(CustomIcons.interface, color: Colors.grey),
  CompletionItemType.module: Icon(Icons.folder_special, color: Colors.grey),
  CompletionItemType.property: Icon(Icons.build, color: Colors.grey),
  CompletionItemType.unit: Icon(Icons.view_module, color: Colors.grey),
  CompletionItemType.value_: Icon(Icons.numbers, color: Colors.grey),
  CompletionItemType.enum_: Icon(
    CustomIcons.enum_,
    color: const Color(0xffee9d28),
  ),
  CompletionItemType.keyword: Icon(CustomIcons.keyword, color: Colors.grey),
  CompletionItemType.snippet: Icon(CustomIcons.snippet, color: Colors.grey),
  CompletionItemType.color: Icon(Icons.color_lens, color: Colors.grey),
  CompletionItemType.file: Icon(Icons.insert_drive_file, color: Colors.grey),
  CompletionItemType.reference: Icon(CustomIcons.reference, color: Colors.grey),
  CompletionItemType.folder: Icon(Icons.folder, color: Colors.grey),
  CompletionItemType.enumMember: Icon(
    CustomIcons.enum_,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.constant: Icon(
    CustomIcons.constant,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.struct: Icon(
    CustomIcons.struct,
    color: const Color(0xff75beff),
  ),
  CompletionItemType.event: Icon(
    CustomIcons.event,
    color: const Color(0xffee9d28),
  ),
  CompletionItemType.operator: Icon(CustomIcons.operator, color: Colors.grey),
  CompletionItemType.typeParameter: Icon(
    CustomIcons.parameter,
    color: const Color(0xffee9d28),
  ),
};

class CustomIcons {
  static const IconData method = IconData(0xe900, fontFamily: 'Method');
  static const IconData variable = IconData(0xe900, fontFamily: 'Variable');
  static const IconData class_ = IconData(0xe900, fontFamily: 'Class');
  static const IconData enum_ = IconData(0x900, fontFamily: 'Enum');
  static const IconData keyword = IconData(0x900, fontFamily: 'KeyWord');
  static const IconData reference = IconData(0x900, fontFamily: 'Reference');
  static const IconData constant = IconData(0x900, fontFamily: 'Constant');
  static const IconData struct = IconData(0x900, fontFamily: 'Struct');
  static const IconData event = IconData(0x900, fontFamily: 'Event');
  static const IconData operator = IconData(0x900, fontFamily: 'Operator');
  static const IconData parameter = IconData(0x900, fontFamily: 'Parameter');
  static const IconData snippet = IconData(0x900, fontFamily: 'Snippet');
  static const IconData interface = IconData(0x900, fontFamily: 'Interface');
  static const IconData field = IconData(0x900, fontFamily: 'Field');
}

/// Represents a completion item in the LSP (Language Server Protocol).
/// This class is used internally by the [CodeCrafter] widget to display completion suggestions.
class LspCompletion {
  /// The label of the completion item, which is displayed in the completion suggestions.
  final String label;

  /// The type of the completion item, which determines the icon and color used to represent it.
  /// The icon is determined by the [completionItemIcons] map.
  final CompletionItemType itemType;

  /// The icon associated with the completion item, determined by its type.
  final Icon icon;

  LspCompletion({required this.label, required this.itemType})
    : icon = Icon(
        completionItemIcons[itemType]!.icon,
        color: completionItemIcons[itemType]!.color,
        size: 18,
      );
}

/// Represents an error in the LSP (Language Server Protocol).
/// This class is used internally by the [CodeCrafter] widget to display errors in the editor.
class LspErrors {
  /// The severity of the error, which can be one of the following:
  /// - 1: Error
  /// - 2: Warning
  /// - 3: Information
  /// - 4: Hint
  final int severity;

  /// The range of the error in the document, represented as a map with keys 'start' and 'end'.
  /// The 'start' and 'end' keys are maps with 'line' and 'character' keys.
  final Map<String, dynamic> range;

  /// The message describing the error.
  String message;

  LspErrors({
    required this.severity,
    required this.range,
    required this.message,
  });
}

/// This class is used to define the properties of the [CodeCrafter] field.
/// It includes the same properties as the [TextField] widget,.
/// If provided it will be passed to the underlying [TextField] of the [CodeCrafter] widget.
class EditorField {
  Key? key;

  // Callbacks
  final void Function(String)? onChanged, onSubmitted;
  final void Function()? onTap, onEditingComplete;
  final void Function(PointerDownEvent)? onTapOutside;

  // Keyboard & input
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization? textCapitalization;
  final bool? obscureText, enableSuggestions, autocorrect;

  // Layout & appearance
  final InputDecoration? decoration;
  final TextAlign? textAlign;
  final TextStyle? style;
  final TextDirection? textDirection;
  final TextAlignVertical? textAlignVertical;
  final bool? expands;
  final int? maxLines, minLines, maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;

  // Cursor & selection
  final bool? showCursor;
  final double? cursorWidth, cursorHeight;
  final Radius? cursorRadius;
  final Color? cursorColor;
  final bool? enableInteractiveSelection;
  final TextSelectionControls? selectionControls;

  // Misc
  final ScrollPhysics? scrollPhysics;
  final ScrollController? scrollController;
  final SmartQuotesType? smartQuotesType;
  final SmartDashesType? smartDashesType;
  final Iterable<String>? autofillHints;
  final String? restorationId;
  final MouseCursor? mouseCursor;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  EditorField({
    this.key,
    this.onChanged,
    this.onTap,
    this.onEditingComplete,
    this.onSubmitted,
    this.onTapOutside,
    this.keyboardType,
    this.inputFormatters,
    this.decoration,
    this.obscureText,
    this.enableSuggestions,
    this.textCapitalization,
    this.autocorrect,
    this.textInputAction,
    this.textAlign,
    this.textAlignVertical,
    this.style,
    this.textDirection,
    this.expands,
    this.maxLines,
    this.minLines,
    this.maxLength,
    this.maxLengthEnforcement,
    this.showCursor,
    this.cursorWidth,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorColor,
    this.enableInteractiveSelection,
    this.selectionControls,
    this.scrollPhysics,
    this.scrollController,
    this.smartQuotesType,
    this.smartDashesType,
    this.autofillHints,
    this.restorationId,
    this.mouseCursor,
    this.contextMenuBuilder,
  });

  TextField build({
    Key? key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool autofocus,
    required bool readOnly,
    required TextStyle? fallbackStyle,
    required Color? fallbackCursorColor,
    required Map<String, TextStyle>? editorTheme,
  }) {
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      readOnly: readOnly,
      onChanged: onChanged,
      onTap: onTap,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTapOutside: onTapOutside,
      keyboardType: keyboardType ?? TextInputType.multiline,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization ?? TextCapitalization.none,
      obscureText: obscureText ?? false,
      enableSuggestions: enableSuggestions ?? true,
      autocorrect: autocorrect ?? true,
      textInputAction: textInputAction,
      textAlign: textAlign ?? TextAlign.start,
      textAlignVertical: textAlignVertical,
      textDirection: textDirection,
      style:
          style ?? fallbackStyle ?? const TextStyle(fontSize: 14, height: 1.5),
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      maxLengthEnforcement: maxLengthEnforcement,
      showCursor: showCursor ?? true,
      cursorWidth: cursorWidth ?? 2,
      cursorHeight: cursorHeight ?? fallbackStyle?.fontSize ?? 14,
      cursorRadius: cursorRadius,
      cursorColor:
          cursorColor ??
          fallbackCursorColor ??
          editorTheme?['root']?.color ??
          Colors.white,
      expands: expands ?? false,
      decoration:
          decoration?.copyWith(isCollapsed: true, border: InputBorder.none) ??
          const InputDecoration(isCollapsed: true, border: InputBorder.none),
      scrollPhysics: scrollPhysics ?? const NeverScrollableScrollPhysics(),
      scrollController: scrollController,
      enableInteractiveSelection: enableInteractiveSelection,
      selectionControls: selectionControls,
      smartDashesType: smartDashesType,
      smartQuotesType: smartQuotesType,
      autofillHints: autofillHints,
      restorationId: restorationId,
      mouseCursor: mouseCursor,
      contextMenuBuilder: contextMenuBuilder,
    );
  }

  /// Creates a copy of this [EditorField] with the given fields replaced by the new values.
  EditorField copyWith({
    Key? key,
    void Function(String)? onChanged,
    onSubmitted,
    void Function()? onTap,
    onEditingComplete,
    void Function(PointerDownEvent)? onTapOutside,

    // Keyboard & input
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization? textCapitalization,
    bool? obscureText,
    enableSuggestions,
    autocorrect,

    // Layout & appearance
    InputDecoration? decoration,
    TextAlign? textAlign,
    TextStyle? style,
    TextDirection? textDirection,
    TextAlignVertical? textAlignVertical,
    bool? expands,
    int? maxLines,
    minLines,
    maxLength,
    MaxLengthEnforcement? maxLengthEnforcement,

    // Cursor & selection
    bool? showCursor,
    double? cursorWidth,
    cursorHeight,
    Radius? cursorRadius,
    Color? cursorColor,
    bool? enableInteractiveSelection,
    TextSelectionControls? selectionControls,

    // Misc
    ScrollPhysics? scrollPhysics,
    ScrollController? scrollController,
    SmartQuotesType? smartQuotesType,
    SmartDashesType? smartDashesType,
    Iterable<String>? autofillHints,
    String? restorationId,
    MouseCursor? mouseCursor,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  }) {
    return EditorField(
      key: key ?? this.key,
      onChanged: onChanged ?? this.onChanged,
      onSubmitted: onSubmitted ?? this.onSubmitted,
      onTap: onTap ?? this.onTap,
      onEditingComplete: onEditingComplete ?? this.onEditingComplete,
      onTapOutside: onTapOutside ?? this.onTapOutside,
      keyboardType: keyboardType ?? this.keyboardType,
      textInputAction: textInputAction ?? this.textInputAction,
      inputFormatters: inputFormatters ?? this.inputFormatters,
      textCapitalization: textCapitalization ?? this.textCapitalization,
      obscureText: obscureText ?? this.obscureText,
      enableSuggestions: enableSuggestions ?? this.enableSuggestions,
      autocorrect: autocorrect ?? this.autocorrect,
      decoration: decoration ?? this.decoration,
      textAlign: textAlign ?? this.textAlign,
      style: style ?? this.style,
      textDirection: textDirection ?? this.textDirection,
      textAlignVertical: textAlignVertical ?? this.textAlignVertical,
      expands: expands ?? this.expands,
      maxLines: maxLines ?? this.maxLines,
      minLines: minLines ?? this.minLines,
      maxLength: maxLength ?? this.maxLength,
      maxLengthEnforcement: maxLengthEnforcement ?? this.maxLengthEnforcement,
      showCursor: showCursor ?? this.showCursor,
      cursorWidth: cursorWidth ?? this.cursorWidth,
      cursorHeight: cursorHeight ?? this.cursorHeight,
      cursorRadius: cursorRadius ?? this.cursorRadius,
      cursorColor: cursorColor ?? this.cursorColor,
      enableInteractiveSelection:
          enableInteractiveSelection ?? this.enableInteractiveSelection,
      selectionControls: selectionControls ?? this.selectionControls,
      scrollPhysics: scrollPhysics ?? this.scrollPhysics,
      scrollController: scrollController ?? this.scrollController,
      smartQuotesType: smartQuotesType ?? this.smartQuotesType,
      smartDashesType: smartDashesType ?? this.smartDashesType,
      autofillHints: autofillHints ?? this.autofillHints,
      restorationId: restorationId ?? this.restorationId,
      mouseCursor: mouseCursor ?? this.mouseCursor,
      contextMenuBuilder: contextMenuBuilder ?? this.contextMenuBuilder,
    );
  }
}
