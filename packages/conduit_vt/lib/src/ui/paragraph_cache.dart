import 'dart:collection';
import 'dart:ui';

import 'package:flutter/widgets.dart';

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
class ParagraphCache {
  ParagraphCache(this.maximumSize);

  final int maximumSize;
  final LinkedHashMap<int, Paragraph> _cache = LinkedHashMap<int, Paragraph>();

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(int key) {
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
    }
    return existing;
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create
  /// a [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    int key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final old = _cache.remove(key);
    old?.dispose();
    while (_cache.length >= maximumSize && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey)?.dispose();
    }
    _cache[key] = paragraph;
    return paragraph;
  }

  /// Clears the cache and disposes native [Paragraph] handles.
  void clear() {
    for (final paragraph in _cache.values) {
      paragraph.dispose();
    }
    _cache.clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _cache.length;
  }
}
