import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class AgentLoopException implements Exception {
  final String message;
  const AgentLoopException(this.message);
  @override
  String toString() => 'AgentLoopException: $message';
}

class ActionRecord {
  final String type;
  final bool success;
  final DateTime timestamp;
  ActionRecord({required this.type, required this.success, required this.timestamp});
}

class AgentOrchestrator {
  final int maxSteps;
  final int maxConsecutiveErrors;
  final int maxSameActionRepeats;

  int _currentStep = 0;
  int _consecutiveErrors = 0;
  final List<ActionRecord> _recentActions = [];
  String? _lastFailedActionType;
  int _sameActionRepeatCount = 0;

  AgentOrchestrator({
    this.maxSteps = 50,
    this.maxConsecutiveErrors = 3,
    this.maxSameActionRepeats = 3,
  });

  bool get isLooping =>
      _consecutiveErrors >= maxConsecutiveErrors ||
      _sameActionRepeatCount >= maxSameActionRepeats;

  String? get loopDiagnosis {
    if (_sameActionRepeatCount >= maxSameActionRepeats && _lastFailedActionType != null) {
      return 'LOOP_DETECTED: repeated "$_lastFailedActionType" $_sameActionRepeatCount times. Stopping.';
    }
    if (_consecutiveErrors >= maxConsecutiveErrors) {
      return 'LOOP_DETECTED: $_consecutiveErrors consecutive errors. Stopping.';
    }
    return null;
  }

  void reset() {
    _currentStep = 0;
    _consecutiveErrors = 0;
    _recentActions.clear();
    _lastFailedActionType = null;
    _sameActionRepeatCount = 0;
  }

  bool advanceStep() {
    _currentStep++;
    if (_currentStep > maxSteps) {
      debugPrint('[AgentOrchestrator] Step limit exceeded: $_currentStep/$maxSteps');
      return false;
    }
    return true;
  }

  void recordAction(String type, bool success) {
    _recentActions.add(ActionRecord(type: type, success: success, timestamp: DateTime.now()));
    if (_recentActions.length > 20) {
      _recentActions.removeRange(0, _recentActions.length - 20);
    }

    if (!success) {
      _consecutiveErrors++;
      if (type == _lastFailedActionType) {
        _sameActionRepeatCount++;
      } else {
        _sameActionRepeatCount = 1;
        _lastFailedActionType = type;
      }
    } else {
      _consecutiveErrors = 0;
      _lastFailedActionType = null;
      _sameActionRepeatCount = 0;
    }
  }

  Future<void> handleApiError(Object error) async {
    final errorStr = error.toString();
    final isRateLimit = errorStr.contains('429') ||
        errorStr.contains('Rate limit') ||
        errorStr.contains('quota') ||
        errorStr.contains('Quota exceeded');
    final isServerError = errorStr.contains('503') ||
        errorStr.contains('Server Error') ||
        errorStr.contains('UNAVAILABLE');

    if (isRateLimit || isServerError) {
      final retryMatch = RegExp(r'retry in (\d+(?:\.\d+)?)s').firstMatch(errorStr);
      int delaySeconds = 10;
      if (retryMatch != null) {
        delaySeconds = int.tryParse(retryMatch.group(1)!) ?? 10;
      } else if (isRateLimit) {
        delaySeconds = 15;
      } else {
        delaySeconds = 5;
      }

      debugPrint('[AgentOrchestrator] API backoff ${delaySeconds}s: ${errorStr.substring(0, errorStr.length > 120 ? 120 : errorStr.length)}');
      await Future.delayed(Duration(seconds: delaySeconds));
    }
  }

  static bool isApiError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('quota exceeded') ||
        lower.contains('rate limit') ||
        lower.contains('server error') ||
        lower.contains('api key error') ||
        lower.contains('connection error') ||
        lower.contains('failed to connect') ||
        lower.startsWith('error:') ||
        lower.startsWith('⏳') ||
        lower.startsWith('❌') ||
        lower.startsWith('🔌');
  }

  static String stripThoughtTags(String text) {
    return text
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .trim();
  }

  static String cleanAssistantResponse(String text) {
    String cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'</think>[\s\S]*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '');
    return cleaned.trim();
  }

  List<String> getRecentErrorActions() {
    return _recentActions
        .where((r) => !r.success)
        .take(5)
        .map((r) => r.type)
        .toList();
  }
}

class AgentFileTools {
  static Future<String> rewriteWholeFile(String path, String content, {String? workspacePath}) async {
    final fullPath = p.isAbsolute(path) ? path : p.join(workspacePath ?? '', path);
    final file = File(fullPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return 'Rewritten ${p.basename(fullPath)} (${content.length} chars)';
  }

  static Future<String> replaceCodeBlock(String path, String searchBlock, String replaceBlock, {String? workspacePath}) async {
    final fullPath = p.isAbsolute(path) ? path : p.join(workspacePath ?? '', path);
    final file = File(fullPath);
    if (!await file.exists()) {
      return 'replace_code_block: file not found: $fullPath';
    }

    final original = await file.readAsString();
    final trimmedSearch = searchBlock.trim();
    final trimmedReplace = replaceBlock.trim();

    if (original.contains(searchBlock)) {
      final updated = original.replaceFirst(searchBlock, replaceBlock);
      await file.writeAsString(updated);
      return 'Replaced code block in ${p.basename(fullPath)} (exact match)';
    }

    if (original.contains(trimmedSearch)) {
      final updated = original.replaceFirst(trimmedSearch, trimmedReplace);
      await file.writeAsString(updated);
      return 'Replaced code block in ${p.basename(fullPath)} (trimmed match)';
    }

    final originalLines = original.split('\n');
    final searchLines = trimmedSearch.split('\n');
    if (searchLines.isEmpty) {
      return 'replace_code_block: empty search_block';
    }

    for (int i = 0; i <= originalLines.length - searchLines.length; i++) {
      bool match = true;
      for (int j = 0; j < searchLines.length; j++) {
        if ((originalLines[i + j].trim()) != searchLines[j].trim()) {
          match = false;
          break;
        }
      }
      if (match) {
        final firstOrigLine = originalLines[i];
        final indent = firstOrigLine.length - firstOrigLine.trimLeft().length;
        final indentedReplace = trimmedReplace.split('\n').map((line) {
          if (line.trim().isEmpty) return line;
          return (' ' * indent) + line.trimLeft();
        }).join('\n');

        final before = originalLines.sublist(0, i).join('\n');
        final after = originalLines.sublist(i + searchLines.length).join('\n');
        final updated = '$before\n$indentedReplace\n${after.startsWith('\n') ? after.substring(1) : after}';
        await file.writeAsString(updated);
        return 'Replaced code block in ${p.basename(fullPath)} (fuzzy whitespace match)';
      }
    }

    return 'replace_code_block: search_block not found in ${p.basename(fullPath)}. Use read_file to see current content.';
  }

  static Future<Map<String, String?>> createCheckpoint(String path, {String? workspacePath}) async {
    final fullPath = p.isAbsolute(path) ? path : p.join(workspacePath ?? '', path);
    final file = File(fullPath);
    String? originalContent;
    if (await file.exists()) {
      originalContent = await file.readAsString();
    }
    return {'path': fullPath, 'content': originalContent};
  }
}
