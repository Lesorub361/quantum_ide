import 'package:flutter/painting.dart';

TextStyle _c(int c, {FontStyle? italic, FontWeight? weight}) =>
    TextStyle(color: Color(c), fontStyle: italic, fontWeight: weight);

/// Builds a highlight.js-compatible style map from a palette.
Map<String, TextStyle> _build({
  required int bg,
  required int fg,
  required int comment,
  required int keyword,
  required int string,
  required int number,
  required int type,
  required int fn,
  required int attr,
  required int meta,
}) {
  return {
    'root': TextStyle(color: Color(fg), backgroundColor: Color(bg)),
    'comment': _c(comment, italic: FontStyle.italic),
    'quote': _c(comment, italic: FontStyle.italic),
    'doctag': _c(keyword),
    'keyword': _c(keyword, weight: FontWeight.w600),
    'selector-tag': _c(keyword),
    'literal': _c(number),
    'number': _c(number),
    'built_in': _c(type),
    'type': _c(type),
    'class': _c(type),
    'title': _c(fn),
    'title.class_': _c(type),
    'title.function_': _c(fn),
    'function': _c(fn),
    'string': _c(string),
    'regexp': _c(string),
    'symbol': _c(number),
    'bullet': _c(number),
    'attr': _c(attr),
    'attribute': _c(attr),
    'variable': _c(fg),
    'variable.language_': _c(keyword, italic: FontStyle.italic),
    'params': _c(fg),
    'property': _c(attr),
    'meta': _c(meta),
    'meta keyword': _c(meta),
    'tag': _c(keyword),
    'name': _c(keyword),
    'selector-id': _c(fn),
    'selector-class': _c(type),
    'link': _c(fn),
    'addition': _c(string),
    'deletion': _c(keyword),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.bold),
  };
}

final Map<String, TextStyle> draculaTheme = _build(
  bg: 0xFF282A36, fg: 0xFFF8F8F2, comment: 0xFF6272A4, keyword: 0xFFFF79C6,
  string: 0xFFF1FA8C, number: 0xFFBD93F9, type: 0xFF8BE9FD, fn: 0xFF50FA7B,
  attr: 0xFFFFB86C, meta: 0xFF8BE9FD,
);

final Map<String, TextStyle> catppuccinMochaTheme = _build(
  bg: 0xFF1E1E2E, fg: 0xFFCDD6F4, comment: 0xFF6C7086, keyword: 0xFFCBA6F7,
  string: 0xFFA6E3A1, number: 0xFFFAB387, type: 0xFFF9E2AF, fn: 0xFF89B4FA,
  attr: 0xFF94E2D5, meta: 0xFFF5C2E7,
);

final Map<String, TextStyle> auroraNeonTheme = _build(
  bg: 0xFF0B0E1A, fg: 0xFFE6EDF7, comment: 0xFF5B6B8C, keyword: 0xFFFF5CAA,
  string: 0xFF7CFFB2, number: 0xFFFFD36B, type: 0xFF5CE1FF, fn: 0xFF9D7CFF,
  attr: 0xFFFF9F6B, meta: 0xFF5CE1FF,
);
