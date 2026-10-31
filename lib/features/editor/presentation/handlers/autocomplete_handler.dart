import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import '../notifiers/editor_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'snippet_prompt.dart';
import '../../../../core/services/lsp_autocomplete_service.dart';
import '../../../../core/services/lsp_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/emmet_service.dart';
import '../../../../core/services/language_service.dart';

class CodeKeywordPrompt extends CodePrompt {
  final String? label;
  
  CodeKeywordPrompt({required super.word, this.label});
  
  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: '',
    word: word,
    selection: TextSelection.collapsed(offset: word.length),
  );
  
  @override
  bool match(String input) {
    return word.toLowerCase().startsWith(input.toLowerCase());
  }
}

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

    // Context-aware member completions after dot (e.g., Colors., Icons., EdgeInsets.)
    if (charBefore == '.') {
      final expr = _getExpressionBeforeDot(text, offset - 1);
      final memberSuggestions = _getDotCompletions(expr, config.name);
      for (final m in memberSuggestions) {
        if (word.isEmpty || m.toLowerCase().startsWith(word.toLowerCase())) {
          prompts.add(WordCompletionPrompt(word: m, userWord: word));
        }
      }
    }

    // Add Emmet abbreviations
    if (word.isNotEmpty) {
      final emmet = EmmetService();
      final langConfig = LanguageService.getConfigForFile(file.path);
      final language = langConfig?.name.toLowerCase() ?? '';
      if (emmet.isEmmetAbbreviation(word) && (language == 'html' || language == 'css' || language == 'xml')) {
        final expanded = emmet.expandAbbreviation(word, language);
        if (expanded != word) {
          prompts.add(CodeKeywordPrompt(word: expanded, label: 'Emmet: $word'));
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

  String _getExpressionBeforeDot(String text, int dotOffset) {
    if (dotOffset <= 0 || dotOffset > text.length) return '';
    int start = dotOffset - 1;
    while (start >= 0 && _isWordChar(text[start])) {
      start--;
    }
    return text.substring(start + 1, dotOffset);
  }

  List<String> _getDotCompletions(String expr, String langName) {
    switch (expr) {
      case 'Colors':
        return ['blue', 'cyan', 'green', 'amber', 'red', 'purple', 'white', 'black', 'transparent', 'grey', 'indigo', 'teal', 'orange'];
      case 'Icons':
      case 'LucideIcons':
        return ['check', 'close', 'search', 'play', 'save', 'refresh', 'settings', 'menu', 'folder', 'file', 'code', 'sparkles', 'git_branch', 'terminal'];
      case 'EdgeInsets':
        return ['all()', 'symmetric()', 'only()', 'zero'];
      case 'BorderRadius':
        return ['circular()', 'all()', 'only()', 'zero'];
      case 'MainAxisAlignment':
      case 'CrossAxisAlignment':
        return ['start', 'center', 'end', 'spaceBetween', 'spaceAround', 'spaceEvenly', 'stretch'];
      case 'FontWeight':
        return ['bold', 'normal', 'w500', 'w600', 'w700', 'w800', 'w900', 'w300', 'w400'];
      case 'console':
        return ['log()', 'warn()', 'error()', 'table()', 'info()', 'clear()'];
      case 'document':
        return ['querySelector()', 'querySelectorAll()', 'getElementById()', 'createElement()', 'addEventListener()'];
      case 'window':
        return ['localStorage', 'sessionStorage', 'location', 'fetch()', 'addEventListener()', 'setTimeout()'];
      case 'JSON':
        return ['stringify()', 'parse()'];
      case 'Math':
      case 'math':
        return ['max()', 'min()', 'round()', 'floor()', 'ceil()', 'random()', 'sqrt()', 'abs()'];
      default:
        return [];
    }
  }

  bool _isWordChar(String char) {
    return RegExp(r'[a-zA-Z0-9_]').hasMatch(char);
  }
}
