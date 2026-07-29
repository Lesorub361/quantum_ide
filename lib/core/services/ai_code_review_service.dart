import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/ai_service.dart';

enum ReviewSeverity { error, warning, info, suggestion }

class ReviewItem {
  final ReviewSeverity severity;
  final int? line;
  final int? endLine;
  final String message;
  final String? suggestion;
  final String? editPatch;

  const ReviewItem({
    required this.severity,
    this.line,
    this.endLine,
    required this.message,
    this.suggestion,
    this.editPatch,
  });

  Map<String, dynamic> toJson() => {
    'severity': severity.name,
    'line': line,
    'endLine': endLine,
    'message': message,
    'suggestion': suggestion,
    'editPatch': editPatch,
  };
}

class ReviewResult {
  final String filePath;
  final List<ReviewItem> items;
  final String? summary;
  final int errorCount;
  final int warningCount;
  final int infoCount;
  final int suggestionCount;
  final DateTime reviewedAt;

  const ReviewResult({
    required this.filePath,
    required this.items,
    this.summary,
    this.errorCount = 0,
    this.warningCount = 0,
    this.infoCount = 0,
    this.suggestionCount = 0,
    required this.reviewedAt,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'items': items.map((i) => i.toJson()).toList(),
    'summary': summary,
    'errorCount': errorCount,
    'warningCount': warningCount,
    'infoCount': infoCount,
    'suggestionCount': suggestionCount,
    'reviewedAt': reviewedAt.toIso8601String(),
  };
}

class AiCodeReviewState {
  final bool isReviewing;
  final ReviewResult? lastResult;
  final List<ReviewResult> history;
  final String? error;

  const AiCodeReviewState({
    this.isReviewing = false,
    this.lastResult,
    this.history = const [],
    this.error,
  });

  AiCodeReviewState copyWith({
    bool? isReviewing,
    ReviewResult? lastResult,
    List<ReviewResult>? history,
    String? error,
  }) {
    return AiCodeReviewState(
      isReviewing: isReviewing ?? this.isReviewing,
      lastResult: lastResult ?? this.lastResult,
      history: history ?? this.history,
      error: error,
    );
  }
}

class AiCodeReviewService extends StateNotifier<AiCodeReviewState> {
  final Ref ref;
  final Dio _dio = Dio();

  AiCodeReviewService(this.ref) : super(const AiCodeReviewState());

  Future<ReviewResult> reviewFile(String filePath, {String? content}) async {
    state = state.copyWith(isReviewing: true, error: null);
    try {
      final fileContent = content ?? await File(filePath).readAsString();
      final prompt = _buildReviewPrompt(filePath, fileContent);
      final aiService = ref.read(aiServiceProvider);
      final chatResponse = await aiService.sendChatMessage(prompt, []);
      final items = _parseReviewResponse(chatResponse.text);
      final result = ReviewResult(
        filePath: filePath,
        items: items,
        errorCount: items.where((i) => i.severity == ReviewSeverity.error).length,
        warningCount: items.where((i) => i.severity == ReviewSeverity.warning).length,
        infoCount: items.where((i) => i.severity == ReviewSeverity.info).length,
        suggestionCount: items.where((i) => i.severity == ReviewSeverity.suggestion).length,
        reviewedAt: DateTime.now(),
      );
      state = state.copyWith(
        isReviewing: false,
        lastResult: result,
        history: [result, ...state.history],
      );
      return result;
    } catch (e) {
      state = state.copyWith(isReviewing: false, error: e.toString());
      return ReviewResult(filePath: filePath, items: [], reviewedAt: DateTime.now());
    }
  }

  Future<List<ReviewResult>> reviewMultipleFiles(List<String> filePaths, {Map<String, String>? contents}) async {
    final results = <ReviewResult>[];
    for (final path in filePaths) {
      final content = contents?[path];
      final result = await reviewFile(path, content: content);
      results.add(result);
    }
    return results;
  }

  Future<String> applyFix(ReviewItem item, String filePath) async {
    if (item.editPatch == null) return '';
    try {
      final file = File(filePath);
      var content = await file.readAsString();
      final patch = item.editPatch!;
      if (patch.contains('→')) {
        final parts = patch.split('→');
        if (parts.length == 2) {
          content = content.replaceAll(parts[0].trim(), parts[1].trim());
        }
      }
      await file.writeAsString(content);
      return content;
    } catch (e) {
      return '';
    }
  }

  String _buildReviewPrompt(String filePath, String content) {
    return '''Review this code file for bugs, security issues, performance problems, and code quality issues.

File: $filePath
```
$content
```

Return your analysis as JSON with this structure:
{
  "summary": "brief overall summary",
  "items": [
    {
      "severity": "error|warning|info|suggestion",
      "line": 42,
      "endLine": null,
      "message": "description of the issue",
      "suggestion": "how to fix it",
      "editPatch": "find→replace" (optional)
    }
  ]
}

Focus on:
- Bugs and logic errors (severity: error)
- Security vulnerabilities (severity: error)
- Performance issues (severity: warning)
- Code quality and best practices (severity: info)
- Improvement suggestions (severity: suggestion)

Return ONLY the JSON, no other text.''';
  }

  List<ReviewItem> _parseReviewResponse(String response) {
    try {
      final cleaned = response
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      final items = (parsed['items'] as List<dynamic>?)
              ?.map((item) => ReviewItem(
                    severity: _parseSeverity(item['severity'] as String? ?? 'info'),
                    line: item['line'] as int?,
                    endLine: item['endLine'] as int?,
                    message: item['message'] ?? '',
                    suggestion: item['suggestion'] as String?,
                    editPatch: item['editPatch'] as String?,
                  ))
              .toList() ??
          [];
      return items;
    } catch (e) {
      return [ReviewItem(
        severity: ReviewSeverity.info,
        message: 'Failed to parse review response: $e',
      )];
    }
  }

  ReviewSeverity _parseSeverity(String value) {
    return switch (value.toLowerCase()) {
      'error' => ReviewSeverity.error,
      'warning' => ReviewSeverity.warning,
      'suggestion' => ReviewSeverity.suggestion,
      _ => ReviewSeverity.info,
    };
  }

  void clearHistory() {
    state = state.copyWith(history: []);
  }

  void deleteResult(int index) {
    final history = [...state.history];
    if (index >= 0 && index < history.length) {
      history.removeAt(index);
      state = state.copyWith(history: history);
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }
}

final aiCodeReviewProvider = StateNotifierProvider<AiCodeReviewService, AiCodeReviewState>((ref) {
  final service = AiCodeReviewService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
