import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

class EditorPerformanceService {
  static const int _largeFileLineThreshold = 2500;
  static const int _maxLinesForFullSyntaxHighlight = 5000;

  // Cache for syntax highlighting results
  final Map<String, Map<int, String>> _syntaxCache = {};
  final Map<String, int> _fileSizeCache = {};

  // Debounce timers
  Timer? _cacheCleanupTimer;

  /// Check if a file is considered "large" in O(1) without joining full text
  bool isLargeFile(CodeLineEditingController controller) {
    return controller.codeLines.length > _largeFileLineThreshold;
  }

  /// Optimize controller for large files (no-op without allocating controller.text)
  void optimizeForLargeFile(CodeLineEditingController controller) {}

  /// Check if syntax highlighting should be applied in O(1)
  bool shouldApplySyntaxHighlighting(CodeLineEditingController controller) {
    return controller.codeLines.length <= _maxLinesForFullSyntaxHighlight;
  }

  /// Cache syntax highlighting results for a file
  void cacheSyntaxResults(String filePath, Map<int, String> results) {
    _syntaxCache[filePath] = results;
  }

  /// Get cached syntax results
  Map<int, String>? getCachedSyntaxResults(String filePath) {
    return _syntaxCache[filePath];
  }

  /// Clear old cache entries (call periodically)
  void clearOldCache() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer(const Duration(minutes: 5), () {
      _syntaxCache.clear();
      _fileSizeCache.clear();
      debugPrint('EditorPerformanceService: Cleared syntax cache');
    });
  }

  /// Measure editor performance
  Future<EditorMetrics> measurePerformance(
    CodeLineEditingController controller,
  ) async {
    final stopwatch = Stopwatch()..start();
    final lineCount = controller.codeLines.length;
    final textLength = controller.text.length;
    stopwatch.stop();

    return EditorMetrics(
      textLength: textLength,
      lineCount: lineCount,
      measuredAt: DateTime.now(),
      isLarge: isLargeFile(controller),
      estimatedMs: stopwatch.elapsedMilliseconds,
    );
  }

  void dispose() {
    _cacheCleanupTimer?.cancel();
    _syntaxCache.clear();
    _fileSizeCache.clear();
  }
}

class EditorMetrics {
  final int textLength;
  final int lineCount;
  final DateTime measuredAt;
  final bool isLarge;
  final int estimatedMs;

  EditorMetrics({
    required this.textLength,
    required this.lineCount,
    required this.measuredAt,
    required this.isLarge,
    required this.estimatedMs,
  });

  @override
  String toString() => 'EditorMetrics(size: $textLength bytes, lines: $lineCount, large: $isLarge, ms: $estimatedMs)';
}
