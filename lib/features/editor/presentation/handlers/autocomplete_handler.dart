import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import '../../../../core/services/language_service.dart';
import '../notifiers/editor_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'snippet_prompt.dart';
import '../../../../core/services/ai_autocomplete_service.dart';
import '../../../../core/services/lsp_autocomplete_service.dart';
import '../../../../core/services/lsp_service.dart';
import '../../../../core/services/settings_service.dart';

class LspCompletionPrompt extends CodePrompt {
  final CompletionItem item;
  final String userWord;

  LspCompletionPrompt({
    required this.item,
    required this.userWord,
  }) : super(word: item.label);

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: userWord,
    word: item.insertText ?? item.label,
    selection: TextSelection.collapsed(offset: (item.insertText ?? item.label).length),
  );

  @override
  bool match(String input) {
    return word.toLowerCase().contains(input.toLowerCase());
  }
}

class AiAutocompletePrompt extends CodePrompt {
  final String suggestion;
  final String userWord;

  AiAutocompletePrompt({
    required this.suggestion,
    required this.userWord,
  }) : super(word: _getFirstLine(suggestion));

  static String _getFirstLine(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) return '';
    if (lines.length > 1) {
      return '${lines.first} ...';
    }
    return lines.first;
  }

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: userWord,
    word: suggestion,
    selection: TextSelection.collapsed(offset: suggestion.length),
  );

  @override
  bool match(String input) {
    return true; // Predetermined for this exact context, always matches
  }
}

class WordCompletionPrompt extends CodePrompt {
  final String userWord;

  WordCompletionPrompt({
    required super.word,
    required this.userWord,
  });

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: userWord,
    word: word,
    selection: TextSelection.collapsed(offset: word.length),
  );

  @override
  bool match(String input) {
    return word.toLowerCase().contains(input.toLowerCase());
  }
}

class QuantumAutocompletePromptsBuilder extends CodeAutocompletePromptsBuilder {
  @override
  CodeAutocompleteEditingValue? build(BuildContext context, CodeLine codeLine, CodeLineSelection selection) {
    if (!selection.isCollapsed) return null;
    
    final text = codeLine.text;
    final offset = selection.extentOffset;
    final word = _getWordAt(text, offset);
    
    // Check if the cursor is immediately after a trigger character
    final charBefore = offset > 0 ? text[offset - 1] : '';
    final isTriggerChar = charBefore == '.' || 
                         charBefore == '(' || 
                         charBefore == ':' || 
                         charBefore == '\'' || 
                         charBefore == '"' || 
                         charBefore == '/' || 
                         charBefore == '<' || 
                         charBefore == '@';
    
    if (word.isEmpty && !isTriggerChar) return null;

    final container = ProviderScope.containerOf(context);
    final editorState = container.read(editorProvider);
    final activeFileIndex = editorState.activeTabIndex;
    
    if (activeFileIndex < 0 || activeFileIndex >= editorState.openFiles.length) return null;
    final file = editorState.openFiles[activeFileIndex];
    final cursor = file.controller.selection.extent;
    
    final config = LanguageService.getConfigForFile(file.path) ??
        LanguageService.getConfigForExtension('dart'); // Default to dart

    if (config == null) return null;

    final List<CodePrompt> prompts = [];

    // Trigger & add AI autocomplete suggestions if enabled
    final settings = container.read(settingsProvider);
    if (settings.aiAutoCompletion && word.isNotEmpty) {
      // Trigger async fetch
      container.read(aiAutocompleteServiceProvider.notifier).triggerAutocomplete(
        filePath: file.path,
        text: file.controller.text,
        lineIndex: cursor.index,
        columnOffset: cursor.offset,
        word: word,
      );

      // Read loaded AI suggestion synchronously
      final aiState = container.read(aiAutocompleteServiceProvider);
      if (aiState.suggestion != null &&
          aiState.suggestion!.isNotEmpty &&
          aiState.filePath == file.path &&
          aiState.lineIndex == cursor.index &&
          aiState.columnOffset == cursor.offset) {
        prompts.add(AiAutocompletePrompt(
          suggestion: aiState.suggestion!,
          userWord: word,
        ));
      }
    }

    // Add LSP suggestions
    container.read(lspAutocompleteServiceProvider.notifier).triggerAutocomplete(
      filePath: file.path,
      lineIndex: cursor.index,
      columnOffset: cursor.offset,
      word: word,
    );

    final lspState = container.read(lspAutocompleteServiceProvider);
    if (lspState.filePath == file.path &&
        lspState.lineIndex == cursor.index &&
        lspState.columnOffset == cursor.offset) {
      for (final item in lspState.items) {
        if (word.isEmpty || item.label.toLowerCase().contains(word.toLowerCase())) {
          prompts.add(LspCompletionPrompt(item: item, userWord: word));
        }
      }
    }

    // Add snippets
    if (word.isNotEmpty) {
      for (final snippet in config.snippets) {
        if (snippet.label.toLowerCase().startsWith(word.toLowerCase())) {
          prompts.add(CodeSnippetPrompt(snippet: snippet));
        }
      }
    }

    // Add keywords
    if (word.isNotEmpty) {
      for (final k in config.keywords) {
        if (k.toLowerCase().startsWith(word.toLowerCase()) && k != word) {
          prompts.add(CodeKeywordPrompt(word: k));
        }
      }
    }

    // Extract all unique words (length >= 3) from the file content as fallback completions
    if (word.isNotEmpty) {
      final content = file.controller.text;
      final words = RegExp(r'\b[a-zA-Z_][a-zA-Z0-9_]{2,}\b')
          .allMatches(content)
          .map((m) => m.group(0)!)
          .toSet();
      
      for (final w in words) {
        if (w != word && w.toLowerCase().startsWith(word.toLowerCase())) {
          if (!prompts.any((p) => p.word == w)) {
            prompts.add(WordCompletionPrompt(word: w, userWord: word));
          }
        }
      }
    }

    if (prompts.isEmpty) return null;

    return CodeAutocompleteEditingValue(
      input: word,
      prompts: prompts,
      index: 0,
    );
  }

  String _getWordAt(String text, int offset) {
    if (offset <= 0 || offset > text.length) return '';
    int start = offset - 1;
    while (start >= 0 && _isWordChar(text[start])) {
      start--;
    }
    return text.substring(start + 1, offset);
  }

  bool _isWordChar(String char) {
    return RegExp(r'[a-zA-Z0-9_]').hasMatch(char);
  }
}
