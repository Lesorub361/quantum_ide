import 'dart:collection';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
class ParagraphCache {
  ParagraphCache(this.maximumSize);

  final int maximumSize;
  final LinkedHashMap<int, Paragraph> _cache = LinkedHashMap<int, Paragraph>();
  final List<Paragraph> _pendingDispose = <Paragraph>[];
  bool _disposeScheduled = false;

  void _scheduleDispose(Paragraph? paragraph) {
    if (paragraph == null) return;
    _pendingDispose.add(paragraph);
    if (_disposeScheduled) return;
    _disposeScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _disposeScheduled = false;
      if (_pendingDispose.isEmpty) return;
      final toDispose = List<Paragraph>.of(_pendingDispose);
      _pendingDispose.clear();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        for (final p in toDispose) {
          try {
            p.dispose();
          } catch (_) {}
        }
      });
    });
  }

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
    _scheduleDispose(old);
    while (_cache.length >= maximumSize && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      _scheduleDispose(_cache.remove(oldestKey));
    }
    _cache[key] = paragraph;
    return paragraph;
  }

  /// Clears the cache and disposes native [Paragraph] handles after frame rasterization.
  void clear() {
    for (final paragraph in _cache.values) {
      _scheduleDispose(paragraph);
    }
    _cache.clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _cache.length;
  }
}
