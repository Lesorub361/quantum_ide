import 'package:flutter/material.dart';

/// Parses ANSI SGR escape sequences (`\x1B[...m`) into styled [TextSpan]s
/// for colored build/run logs.
class AnsiTextParser {
  AnsiTextParser._();

  static final RegExp _sgrRegex = RegExp(r'\x1B\[([0-9;]*)m');
  static final RegExp _otherCsiRegex = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');

  static const Map<int, Color> _fgColors = {
    30: Color(0xFF475569),
    31: Color(0xFFF87171),
    32: Color(0xFF4ADE80),
    33: Color(0xFFFBBF24),
    34: Color(0xFF60A5FA),
    35: Color(0xFFC084FC),
    36: Color(0xFF22D3EE),
    37: Color(0xFFE2E8F0),
    90: Color(0xFF94A3B8),
    91: Color(0xFFFCA5A5),
    92: Color(0xFF86EFAC),
    93: Color(0xFFFDE047),
    94: Color(0xFF93C5FD),
    95: Color(0xFFD8B4FE),
    96: Color(0xFF67E8F9),
    97: Colors.white,
  };

  /// Converts [raw] text containing ANSI escape codes into a [TextSpan].
  static TextSpan parse(String raw, {required TextStyle baseStyle}) {
    final cleaned = raw.replaceAllMapped(_otherCsiRegex, (m) {
      final full = m.group(0) ?? '';
      return full.endsWith('m') ? full : '';
    });

    if (!cleaned.contains('\x1B[')) {
      return TextSpan(text: cleaned, style: baseStyle);
    }

    final spans = <TextSpan>[];
    var currentStyle = baseStyle;
    var lastIndex = 0;

    for (final match in _sgrRegex.allMatches(cleaned)) {
      if (match.start > lastIndex) {
        spans.add(
          TextSpan(
            text: cleaned.substring(lastIndex, match.start),
            style: currentStyle,
          ),
        );
      }
      final codesStr = match.group(1) ?? '';
      final codes = codesStr.isEmpty
          ? const [0]
          : codesStr
              .split(';')
              .map((s) => int.tryParse(s) ?? -1)
              .where((v) => v >= 0)
              .toList();
      for (final code in codes) {
        if (code == 0 || code == 39) {
          currentStyle = baseStyle;
        } else if (code == 1) {
          currentStyle = currentStyle.copyWith(fontWeight: FontWeight.w700);
        } else if (code == 2) {
          currentStyle = currentStyle.copyWith(
            color: (currentStyle.color ?? baseStyle.color ?? Colors.white)
                .withValues(alpha: 0.65),
          );
        } else if (code == 22) {
          currentStyle = currentStyle.copyWith(fontWeight: FontWeight.normal);
        } else if (_fgColors.containsKey(code)) {
          currentStyle = currentStyle.copyWith(color: _fgColors[code]);
        }
      }
      lastIndex = match.end;
    }

    if (lastIndex < cleaned.length) {
      spans.add(
        TextSpan(
          text: cleaned.substring(lastIndex),
          style: currentStyle,
        ),
      );
    }

    return TextSpan(children: spans, style: baseStyle);
  }
}
