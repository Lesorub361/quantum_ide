import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:path/path.dart' as p;

class FindReplaceMatch {
  final int lineNumber;
  final String lineContent;
  final int startOffset;
  final int endOffset;

  const FindReplaceMatch({
    required this.lineNumber,
    required this.lineContent,
    required this.startOffset,
    required this.endOffset,
  });
}

class FindReplaceFileResult {
  final String filePath;
  final String fileName;
  final List<FindReplaceMatch> matches;
  bool isExpanded;

  FindReplaceFileResult({
    required this.filePath,
    required this.fileName,
    required this.matches,
    this.isExpanded = true,
  });
}

class FindReplaceState {
  final String query;
  final String replaceText;
  final bool caseSensitive;
  final bool useRegex;
  final bool wholeWord;
  final String fileFilter;
  final List<FindReplaceFileResult> results;
  final bool isSearching;
  final int totalMatches;
  final int totalFiles;
  final String? error;

  const FindReplaceState({
    this.query = '',
    this.replaceText = '',
    this.caseSensitive = false,
    this.useRegex = false,
    this.wholeWord = false,
    this.fileFilter = '',
    this.results = const [],
    this.isSearching = false,
    this.totalMatches = 0,
    this.totalFiles = 0,
    this.error,
  });

  FindReplaceState copyWith({
    String? query,
    String? replaceText,
    bool? caseSensitive,
    bool? useRegex,
    bool? wholeWord,
    String? fileFilter,
    List<FindReplaceFileResult>? results,
    bool? isSearching,
    int? totalMatches,
    int? totalFiles,
    String? error,
  }) {
    return FindReplaceState(
      query: query ?? this.query,
      replaceText: replaceText ?? this.replaceText,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      useRegex: useRegex ?? this.useRegex,
      wholeWord: wholeWord ?? this.wholeWord,
      fileFilter: fileFilter ?? this.fileFilter,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      totalMatches: totalMatches ?? this.totalMatches,
      totalFiles: totalFiles ?? this.totalFiles,
      error: error,
    );
  }
}

class FindReplaceNotifier extends StateNotifier<FindReplaceState> {
  final Ref _ref;

  FindReplaceNotifier(this._ref) : super(const FindReplaceState());

  void setQuery(String query) {
    state = state.copyWith(query: query, error: null);
  }

  void setReplaceText(String text) {
    state = state.copyWith(replaceText: text);
  }

  void toggleCaseSensitive() {
    state = state.copyWith(caseSensitive: !state.caseSensitive);
  }

  void toggleUseRegex() {
    state = state.copyWith(useRegex: !state.useRegex);
  }

  void toggleWholeWord() {
    state = state.copyWith(wholeWord: !state.wholeWord);
  }

  void setFileFilter(String filter) {
    state = state.copyWith(fileFilter: filter);
  }

  void toggleFileExpansion(int index) {
    final results = List<FindReplaceFileResult>.from(state.results);
    if (index < results.length) {
      results[index].isExpanded = !results[index].isExpanded;
      state = state.copyWith(results: results);
    }
  }

  Future<void> search() async {
    final query = state.query;
    if (query.isEmpty) {
      state = state.copyWith(results: [], totalMatches: 0, totalFiles: 0);
      return;
    }

    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null || workspacePath.isEmpty) {
      state = state.copyWith(error: 'No project opened');
      return;
    }

    state = state.copyWith(isSearching: true, error: null);

    try {
      final regex = _buildRegex(query);
      if (regex == null) {
        state = state.copyWith(isSearching: false, error: 'Invalid regex pattern');
        return;
      }

      final dir = Directory(workspacePath);
      if (!await dir.exists()) {
        state = state.copyWith(isSearching: false, results: []);
        return;
      }

      final results = <FindReplaceFileResult>[];
      final filters = state.fileFilter.isNotEmpty
        ? state.fileFilter.split(',').map((f) => f.trim().toLowerCase()).where((f) => f.isNotEmpty).toList()
        : <String>[];

      final entities = await dir.list(recursive: true).toList();

      for (final entity in entities) {
        if (entity is! File) continue;
        final relPath = p.relative(entity.path, from: workspacePath);

        if (_isSkippableFile(relPath)) continue;

        if (filters.isNotEmpty) {
          final ext = p.extension(entity.path).toLowerCase();
          if (!filters.any((f) => ext == '.$f' || relPath.toLowerCase().contains(f))) continue;
        }

        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');
          final matches = <FindReplaceMatch>[];

          for (int i = 0; i < lines.length; i++) {
            final line = lines[i];
            for (final match in regex.allMatches(line)) {
              matches.add(FindReplaceMatch(
                lineNumber: i + 1,
                lineContent: line,
                startOffset: match.start,
                endOffset: match.end,
              ));
            }
          }

          if (matches.isNotEmpty) {
            results.add(FindReplaceFileResult(
              filePath: entity.path,
              fileName: p.basename(entity.path),
              matches: matches,
            ));
          }
        } catch (_) {}
      }

      final totalMatches = results.fold(0, (sum, r) => sum + r.matches.length);

      state = state.copyWith(
        results: results,
        totalMatches: totalMatches,
        totalFiles: results.length,
        isSearching: false,
      );
    } catch (e) {
      state = state.copyWith(isSearching: false, error: e.toString());
    }
  }

  Future<void> replaceInFile(String filePath, FindReplaceMatch match) async {
    if (state.replaceText.isEmpty && state.query.isEmpty) return;

    try {
      final content = await File(filePath).readAsString();
      final lines = content.split('\n');
      if (match.lineNumber - 1 >= lines.length) return;

      final line = lines[match.lineNumber - 1];
      final regex = _buildRegex(state.query);
      if (regex == null) return;

      final newLine = line.replaceFirst(regex, state.replaceText);
      lines[match.lineNumber - 1] = newLine;
      await File(filePath).writeAsString(lines.join('\n'));
    } catch (_) {}
  }

  Future<void> replaceInCurrentFile(String filePath) async {
    final fileResult = state.results.where((r) => r.filePath == filePath).firstOrNull;
    if (fileResult == null) return;

    try {
      var content = await File(filePath).readAsString();
      final regex = _buildRegex(state.query);
      if (regex == null) return;

      content = content.replaceAll(regex, state.replaceText);
      await File(filePath).writeAsString(content);
      await search();
    } catch (_) {}
  }

  Future<void> replaceAll() async {
    if (state.results.isEmpty) return;

    for (final fileResult in state.results) {
      await replaceInCurrentFile(fileResult.filePath);
    }
  }

  String? getPreview(String filePath, FindReplaceMatch match) {
    final line = match.lineContent;
    final before = match.startOffset > 0 ? line.substring(0, match.startOffset) : '';
    final matched = line.substring(match.startOffset, match.endOffset);
    final after = match.endOffset < line.length ? line.substring(match.endOffset) : '';
    return '$before|$matched|$after';
  }

  RegExp? _buildRegex(String query) {
    try {
      if (state.useRegex) {
        return RegExp(query, caseSensitive: state.caseSensitive);
      } else {
        String escaped = RegExp.escape(query);
        if (state.wholeWord) {
          escaped = '\\b$escaped\\b';
        }
        return RegExp(escaped, caseSensitive: state.caseSensitive);
      }
    } catch (e) {
      return null;
    }
  }

  bool _isSkippableFile(String relPath) {
    return relPath.startsWith('.git/') ||
        relPath.startsWith('.dart_tool/') ||
        relPath.startsWith('build/') ||
        relPath.contains('.flutter-plugins') ||
        relPath.endsWith('.png') ||
        relPath.endsWith('.jpg') ||
        relPath.endsWith('.jpeg') ||
        relPath.endsWith('.gif') ||
        relPath.endsWith('.zip') ||
        relPath.endsWith('.apk') ||
        relPath.endsWith('.lock') ||
        relPath.endsWith('.exe') ||
        relPath.endsWith('.so') ||
        relPath.endsWith('.dll');
  }
}

final findReplaceProvider = StateNotifierProvider<FindReplaceNotifier, FindReplaceState>((ref) {
  return FindReplaceNotifier(ref);
});
