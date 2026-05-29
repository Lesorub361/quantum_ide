import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

class EditorPerformanceService {
  static const int _largeFileThreshold = 100000; // 100KB
  static const int _maxLinesForFullSyntaxHighlight = 5000;
  
  // Cache for syntax highlighting results
  final Map<String, Map<int, String>> _syntaxCache = {};
  final Map<String, int> _fileSizeCache = {};
  
  // Debounce timers
  Timer? _cacheCleanupTimer;
  
  /// Check if a file is considered "large"
  bool isLargeFile(CodeLineEditingController controller) {
    return controller.text.length > _largeFileThreshold;
  }

  /// Optimize controller for large files
  void optimizeForLargeFile(CodeLineEditingController controller) {
    if (!isLargeFile(controller)) return;
    
    // For large files, use virtual scrolling
    // Note: re_editor already has virtual scrolling, but we can optimize
    debugPrint('EditorPerformanceService: Optimizing for large file (${controller.text.length} bytes)');
  }

  /// Check if syntax highlighting should be applied
  bool shouldApplySyntaxHighlighting(CodeLineEditingController controller) {
    // Disable full syntax highlighting for very large files
    final lineCount = controller.text.split('\n').length;
    return lineCount <= _maxLinesForFullSyntaxHighlight;
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
  Future<EditorMetrics> measurePerformance(CodeLineEditingController controller) async {
    final stopwatch = Stopwatch()..start();
    
    // Measure text length
    final textLength = controller.text.length;
    final lineCount = controller.text.split('\n').length;
    
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
