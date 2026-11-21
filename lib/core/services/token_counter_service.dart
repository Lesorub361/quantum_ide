import 'package:langchain_tiktoken/langchain_tiktoken.dart';

/// Exact BPE token counter backed by `langchain_tiktoken` (`cl100k_base`)
/// with a fast length-based fallback for edge cases.
class TokenCounterService {
  TokenCounterService._();

  static Tiktoken? _cachedEncoding;

  static Tiktoken? get _encoding {
    if (_cachedEncoding != null) return _cachedEncoding;
    try {
      _cachedEncoding = getEncoding('cl100k_base');
    } catch (_) {
      _cachedEncoding = null;
    }
    return _cachedEncoding;
  }

  /// Returns exact token count for [text] using `cl100k_base` BPE.
  static int countTokens(String text) {
    if (text.isEmpty) return 0;
    try {
      final enc = _encoding;
      if (enc != null) {
        return enc.encode(text).length;
      }
    } catch (_) {}
    return (text.length / 3.8).ceil();
  }

  /// Formats token counts compactly (e.g. `420 tok`, `1.8k tok`).
  static String formatCompact(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}k tok';
    }
    return '$tokens tok';
  }
}
