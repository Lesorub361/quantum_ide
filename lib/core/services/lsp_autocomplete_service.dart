import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'lsp_service.dart';

class LspAutocompleteState {
  final List<CompletionItem> items;
  final String? filePath;
  final int? lineIndex;
  final int? columnOffset;
  final String? triggerWord;
  final bool isLoading;

  LspAutocompleteState({
    this.items = const [],
    this.filePath,
    this.lineIndex,
    this.columnOffset,
    this.triggerWord,
    this.isLoading = false,
  });

  LspAutocompleteState copyWith({
    List<CompletionItem>? items,
    String? filePath,
    int? lineIndex,
    int? columnOffset,
    String? triggerWord,
    bool? isLoading,
  }) {
    return LspAutocompleteState(
      items: items ?? this.items,
      filePath: filePath ?? this.filePath,
      lineIndex: lineIndex ?? this.lineIndex,
      columnOffset: columnOffset ?? this.columnOffset,
      triggerWord: triggerWord ?? this.triggerWord,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LspAutocompleteService extends StateNotifier<LspAutocompleteState> {
  final Ref ref;
  Timer? _debounceTimer;

  LspAutocompleteService(this.ref) : super(LspAutocompleteState());

  void triggerAutocomplete({
    required String filePath,
    required int lineIndex,
    required int columnOffset,
    required String word,
  }) {
    // If we already have items for this precise cursor and word, do nothing
    if (state.filePath == filePath &&
        state.lineIndex == lineIndex &&
        state.columnOffset == columnOffset &&
        state.triggerWord == word) {
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      await _fetchCompletions(
        filePath: filePath,
        lineIndex: lineIndex,
        columnOffset: columnOffset,
        word: word,
      );
    });
  }

  Future<void> _fetchCompletions({
    required String filePath,
    required int lineIndex,
    required int columnOffset,
    required String word,
  }) async {
    final lspService = ref.read(lspServiceProvider);

    state = state.copyWith(
      isLoading: true,
      filePath: filePath,
      lineIndex: lineIndex,
      columnOffset: columnOffset,
      triggerWord: word,
      items: [],
    );

    try {
      final items = await lspService.getCompletions(filePath, lineIndex, columnOffset);
      state = state.copyWith(
        isLoading: false,
        items: items,
      );
    } catch (e) {
      debugPrint('LSP Autocomplete request failed: $e');
      state = state.copyWith(isLoading: false, items: []);
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    state = LspAutocompleteState();
  }
}

final lspAutocompleteServiceProvider = StateNotifierProvider<LspAutocompleteService, LspAutocompleteState>((ref) {
  return LspAutocompleteService(ref);
});

// We need a provider for LspService itself if it doesn't exist yet
// Looking at lsp_service.dart, it takes Ref and some paths.
// Let's check if there's already a provider for it.
