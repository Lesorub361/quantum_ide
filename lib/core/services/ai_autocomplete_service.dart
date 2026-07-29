import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';

class AiAutocompleteState {
  final String? suggestion;
  final String? filePath;
  final int? lineIndex;
  final int? columnOffset;
  final String? triggerWord;
  final bool isLoading;

  AiAutocompleteState({
    this.suggestion,
    this.filePath,
    this.lineIndex,
    this.columnOffset,
    this.triggerWord,
    this.isLoading = false,
  });

  AiAutocompleteState copyWith({
    String? suggestion,
    String? filePath,
    int? lineIndex,
    int? columnOffset,
    String? triggerWord,
    bool? isLoading,
  }) {
    return AiAutocompleteState(
      suggestion: suggestion ?? this.suggestion,
      filePath: filePath ?? this.filePath,
      lineIndex: lineIndex ?? this.lineIndex,
      columnOffset: columnOffset ?? this.columnOffset,
      triggerWord: triggerWord ?? this.triggerWord,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AiAutocompleteService extends StateNotifier<AiAutocompleteState> {
  final Ref ref;
  Timer? _debounceTimer;

  AiAutocompleteService(this.ref) : super(AiAutocompleteState());

  void triggerAutocomplete({
    required String filePath,
    required String text,
    required int lineIndex,
    required int columnOffset,
    required String word,
  }) {
    final settings = ref.read(settingsProvider);
    if (!settings.aiAutoCompletion) {
      return;
    }
    
    // If the suggestion is already fetched for this precise cursor and word, do nothing
    if (state.filePath == filePath &&
        state.lineIndex == lineIndex &&
        state.columnOffset == columnOffset &&
        state.triggerWord == word) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () async {
      await _fetchAutocomplete(
        filePath: filePath,
        text: text,
        lineIndex: lineIndex,
        columnOffset: columnOffset,
        word: word,
      );
    });
  }

  Future<void> _fetchAutocomplete({
    required String filePath,
    required String text,
    required int lineIndex,
    required int columnOffset,
    required String word,
  }) async {
    final aiService = ref.read(aiServiceProvider);
    final provider = aiService.settings.currentProvider;
    if (provider.requiresApiKey && aiService.apiKey.isEmpty) {
      return; // No API key configured
    }

    state = state.copyWith(
      isLoading: true,
      filePath: filePath,
      lineIndex: lineIndex,
      columnOffset: columnOffset,
      triggerWord: word,
      suggestion: null,
    );

    try {
      final codeBefore = _getCodeBeforeCursor(text, lineIndex, columnOffset);
      final codeAfter = _getCodeAfterCursor(text, lineIndex, columnOffset);
      final filename = filePath.split(Platform.pathSeparator).last;

      final prompt = '''
You are an expert AI code completion engine. Your job is to predict the code that the developer is about to write next at the cursor position.

We will provide you with the file context:
- File name: $filename
- Source code before cursor:
$codeBefore
- Source code after cursor:
$codeAfter

Rules:
1. Return ONLY the immediate completion (one line or a small snippet up to 5 lines of code) to insert at the cursor.
2. DO NOT include any comments, markdown formatting (like ```), markdown code blocks, or explanations.
3. Keep indentation matching the surrounding code.
4. If no logical completion is needed, return empty string.
''';

      final completion = await aiService.getCompletion(prompt);
      
      // Clean up markdown block wraps if AI returned them
      var cleanCompletion = completion.trim();
      if (cleanCompletion.startsWith('```')) {
        final lines = cleanCompletion.split('\n');
        if (lines.isNotEmpty && lines.first.startsWith('```')) {
          lines.removeAt(0);
        }
        if (lines.isNotEmpty && lines.last.startsWith('```')) {
          lines.removeLast();
        }
        cleanCompletion = lines.join('\n').trim();
      }

      state = state.copyWith(
        isLoading: false,
        suggestion: cleanCompletion,
      );
    } catch (e) {
      debugPrint('AI Autocomplete request failed: $e');
      state = state.copyWith(isLoading: false, suggestion: '');
    }
  }

  String _getCodeBeforeCursor(String text, int lineIndex, int columnOffset) {
    final lines = text.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return text;
    
    final buffer = StringBuffer();
    // Gather previous lines
    final startLine = lineIndex > 50 ? lineIndex - 50 : 0;
    for (int i = startLine; i < lineIndex; i++) {
      buffer.writeln(lines[i]);
    }
    
    // Gather current line before cursor
    final currentLine = lines[lineIndex];
    if (columnOffset >= 0 && columnOffset <= currentLine.length) {
      buffer.write(currentLine.substring(0, columnOffset));
    } else {
      buffer.write(currentLine);
    }
    
    return buffer.toString();
  }

  String _getCodeAfterCursor(String text, int lineIndex, int columnOffset) {
    final lines = text.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return '';
    
    final buffer = StringBuffer();
    // Gather current line after cursor
    final currentLine = lines[lineIndex];
    if (columnOffset >= 0 && columnOffset <= currentLine.length) {
      buffer.writeln(currentLine.substring(columnOffset));
    }
    
    // Gather subsequent lines
    final endLine = (lineIndex + 50) < lines.length ? lineIndex + 50 : lines.length;
    for (int i = lineIndex + 1; i < endLine; i++) {
      buffer.writeln(lines[i]);
    }
    
    return buffer.toString();
  }

  void clear() {
    _debounceTimer?.cancel();
    state = AiAutocompleteState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final aiAutocompleteServiceProvider = StateNotifierProvider<AiAutocompleteService, AiAutocompleteState>((ref) {
  return AiAutocompleteService(ref);
});
