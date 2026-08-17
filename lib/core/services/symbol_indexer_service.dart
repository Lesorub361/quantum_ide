import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

class IndexSymbol {
  final String name;
  final String type; // 'class', 'method', 'function', 'property'
  final String filePath; // Absolute path
  final int lineNumber;

  IndexSymbol({
    required this.name,
    required this.type,
    required this.filePath,
    required this.lineNumber,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'filePath': filePath,
        'lineNumber': lineNumber,
      };

  factory IndexSymbol.fromJson(Map<String, dynamic> json) => IndexSymbol(
        name: json['name'] as String,
        type: json['type'] as String,
        filePath: json['filePath'] as String,
        lineNumber: json['lineNumber'] as int,
      );
}

class SymbolIndexerState {
  final bool isIndexing;
  final List<IndexSymbol> symbols;
  final List<String> files; // All scanned workspace file paths
  final String? error;

  SymbolIndexerState({
    this.isIndexing = false,
    this.symbols = const [],
    this.files = const [],
    this.error,
  });

  SymbolIndexerState copyWith({
    bool? isIndexing,
    List<IndexSymbol>? symbols,
    List<String>? files,
    String? error,
  }) {
    return SymbolIndexerState(
      isIndexing: isIndexing ?? this.isIndexing,
      symbols: symbols ?? this.symbols,
      files: files ?? this.files,
      error: error ?? this.error,
    );
  }
}

class SymbolIndexerNotifier extends StateNotifier<SymbolIndexerState> {
  final Ref ref;
  SymbolIndexerNotifier(this.ref) : super(SymbolIndexerState()) {
    // Auto-scan workspace when it is loaded
    ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      if (next.currentPath != null && next.currentPath != previous?.currentPath) {
        scanWorkspace(next.currentPath!);
      } else if (next.currentPath == null) {
        clearIndex();
      }
    });
  }

  // Set of folders to ignore during indexing
  static const _ignoredDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    'ios',
    'android',
    'web',
    'windows',
    'linux',
    'macos',
    '.gradle',
    '.idea',
    'assets',
  };

  void clearIndex() {
    state = SymbolIndexerState();
  }

  Future<void> scanWorkspace(String workspaceRoot) async {
    if (state.isIndexing) return;

    state = state.copyWith(isIndexing: true, error: null);

    try {
      final List<IndexSymbol> allSymbols = [];
      final List<String> allFiles = [];
      final List<Directory> queue = [Directory(workspaceRoot)];
      int processedCount = 0;

      while (queue.isNotEmpty) {
        final currentDir = queue.removeLast();
        try {
          final List<FileSystemEntity> entities = await currentDir.list(recursive: false, followLinks: false).toList();
          for (final entity in entities) {
            final name = p.basename(entity.path);
            if (_ignoredDirs.contains(name) || name.startsWith('.')) {
              continue;
            }

            if (entity is File) {
              allFiles.add(entity.path);
              final ext = p.extension(entity.path).toLowerCase();
              if (ext == '.dart' || ext == '.js' || ext == '.ts' || ext == '.py' || ext == '.go') {
                final symbols = await _parseFile(entity);
                allSymbols.addAll(symbols);
              }
            } else if (entity is Directory) {
              queue.add(entity);
            }

            processedCount++;
            if (processedCount % 20 == 0) {
              await Future.delayed(Duration.zero);
            }
          }
        } catch (_) {
          // ignore directory access errors
        }
        await Future.delayed(Duration.zero);
      }

      state = state.copyWith(isIndexing: false, symbols: allSymbols, files: allFiles);
    } catch (e) {
      state = state.copyWith(isIndexing: false, error: 'Indexing error: $e');
    }
  }

  Future<void> indexFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        // If file was deleted, remove it from lists
        final updatedSymbols = state.symbols.where((s) => s.filePath != filePath).toList();
        final updatedFiles = state.files.where((f) => f != filePath).toList();
        state = state.copyWith(symbols: updatedSymbols, files: updatedFiles);
        return;
      }

      // Add to files list if new
      final updatedFiles = List<String>.from(state.files);
      if (!updatedFiles.contains(filePath)) {
        updatedFiles.add(filePath);
      }

      final ext = p.extension(filePath).toLowerCase();
      if (ext != '.dart' && ext != '.js' && ext != '.ts' && ext != '.py' && ext != '.go') {
        state = state.copyWith(files: updatedFiles);
        return;
      }

      // 1. Remove old symbols for this file
      final updatedSymbols = state.symbols.where((s) => s.filePath != filePath).toList();

      // 2. Parse new symbols
      final newSymbols = await _parseFile(file);
      updatedSymbols.addAll(newSymbols);

      state = state.copyWith(symbols: updatedSymbols, files: updatedFiles);
    } catch (_) {}
  }

  Future<List<IndexSymbol>> _parseFile(File file) async {
    final List<IndexSymbol> symbols = [];
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');

      // Precalculate line start offsets to map character positions to line numbers
      final lineStarts = <int>[];
      int currentOffset = 0;
      for (final line in lines) {
        lineStarts.add(currentOffset);
        currentOffset += line.length + 1; // +1 for the newline character
      }

      int getLineNumber(int offset) {
        int low = 0;
        int high = lineStarts.length - 1;
        while (low <= high) {
          final mid = (low + high) >> 1;
          if (lineStarts[mid] <= offset) {
            if (mid == lineStarts.length - 1 || lineStarts[mid + 1] > offset) {
              return mid + 1;
            }
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        return 1;
      }

      final ext = p.extension(file.path).toLowerCase();

      const keywords = {
        'if', 'for', 'switch', 'while', 'catch', 'return', 'assert', 'await',
        'import', 'export', 'part', 'library', 'else', 'super', 'this', 'throw', 'yield',
        'void', 'dynamic', 'var', 'final', 'const'
      };

      if (ext == '.dart') {
        final classReg = RegExp(r'\bclass\s+([A-Za-z0-9_]+)');
        // Matches functions/methods with optional return type, name, parameters (supporting nested parens and newlines), and => or {
        final methodReg = RegExp(
            r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?:async\s*)?(?:{|=>)');

        for (final match in classReg.allMatches(content)) {
          final name = match.group(1)!;
          symbols.add(IndexSymbol(
            name: name,
            type: 'class',
            filePath: file.path,
            lineNumber: getLineNumber(match.start),
          ));
        }

        for (final match in methodReg.allMatches(content)) {
          final name = match.group(1)!;
          if (!keywords.contains(name) && name != 'Widget') {
            symbols.add(IndexSymbol(
              name: name,
              type: 'method',
              filePath: file.path,
              lineNumber: getLineNumber(match.start),
            ));
          }
        }
      } else if (ext == '.py') {
        final classReg = RegExp(r'\bclass\s+([A-Za-z0-9_]+)');
        final defReg = RegExp(r'\bdef\s+([A-Za-z0-9_]+)');

        for (final match in classReg.allMatches(content)) {
          final name = match.group(1)!;
          symbols.add(IndexSymbol(
            name: name,
            type: 'class',
            filePath: file.path,
            lineNumber: getLineNumber(match.start),
          ));
        }

        for (final match in defReg.allMatches(content)) {
          final name = match.group(1)!;
          symbols.add(IndexSymbol(
            name: name,
            type: 'method',
            filePath: file.path,
            lineNumber: getLineNumber(match.start),
          ));
        }
      } else if (ext == '.js' || ext == '.ts') {
        final funcReg = RegExp(r'\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)');
        final methodReg = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*\{');

        for (final match in funcReg.allMatches(content)) {
          final name = match.group(1)!;
          symbols.add(IndexSymbol(
            name: name,
            type: 'method',
            filePath: file.path,
            lineNumber: getLineNumber(match.start),
          ));
        }

        for (final match in methodReg.allMatches(content)) {
          final name = match.group(1)!;
          if (!keywords.contains(name) && name != 'constructor') {
            symbols.add(IndexSymbol(
              name: name,
              type: 'method',
              filePath: file.path,
              lineNumber: getLineNumber(match.start),
            ));
          }
        }
      }
    } catch (_) {}
    return symbols;
  }

  List<IndexSymbol> searchSymbols(String query, {String? typeFilter}) {
    if (query.isEmpty) {
      var results = state.symbols.take(50).toList();
      if (typeFilter != null) {
        results = results.where((s) => s.type == typeFilter).toList();
      }
      return results;
    }
    final normalized = query.toLowerCase();
    final terms = normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    
    final matched = state.symbols.where((symbol) {
      final nameLower = symbol.name.toLowerCase();
      if (typeFilter != null && symbol.type != typeFilter) return false;
      if (terms.isEmpty) return true;
      return terms.any((term) => nameLower.contains(term));
    }).toList();

    matched.sort((a, b) {
      final aLower = a.name.toLowerCase();
      final bLower = b.name.toLowerCase();
      
      // Exact matches first
      if (aLower == normalized && bLower != normalized) return -1;
      if (bLower == normalized && aLower != normalized) return 1;
      
      // Starts with query next
      final aStartsWith = aLower.startsWith(normalized);
      final bStartsWith = bLower.startsWith(normalized);
      if (aStartsWith && !bStartsWith) return -1;
      if (bStartsWith && !aStartsWith) return 1;

      // More matching terms = higher rank
      final aMatches = terms.where((t) => aLower.contains(t)).length;
      final bMatches = terms.where((t) => bLower.contains(t)).length;
      if (aMatches != bMatches) return bMatches.compareTo(aMatches);

      return a.name.compareTo(b.name);
    });

    return matched.take(50).toList();
  }

  List<String> searchFiles(String query) {
    if (query.isEmpty) {
      return state.files.take(50).toList();
    }
    final normalized = query.toLowerCase();
    final terms = normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    
    final matched = state.files.where((filePath) {
      final fileName = p.basename(filePath).toLowerCase();
      final dirPath = p.dirname(filePath).toLowerCase();
      if (terms.isEmpty) return true;
      return terms.any((term) => fileName.contains(term) || dirPath.contains(term) || filePath.toLowerCase().contains(term));
    }).toList();

    matched.sort((a, b) {
      final aName = p.basename(a).toLowerCase();
      final bName = p.basename(b).toLowerCase();
      
      final aStartsWith = terms.any((t) => aName.startsWith(t));
      final bStartsWith = terms.any((t) => bName.startsWith(t));
      if (aStartsWith && !bStartsWith) return -1;
      if (bStartsWith && !aStartsWith) return 1;

      final aContains = terms.where((t) => aName.contains(t)).length;
      final bContains = terms.where((t) => bName.contains(t)).length;
      if (aContains != bContains) return bContains.compareTo(aContains);

      return a.compareTo(b);
    });

    return matched.take(50).toList();
  }

  Future<List<_SearchResult>> semanticSearch(String query, {int limit = 20}) async {
    if (query.isEmpty || state.symbols.isEmpty) return [];
    
    final normalized = query.toLowerCase();
    final terms = normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return [];

    // Precompute document statistics for BM25
    final Map<String, int> docFreq = {};
    for (final term in terms) {
      int count = 0;
      for (final symbol in state.symbols) {
        if (symbol.name.toLowerCase().contains(term)) count++;
      }
      for (final filePath in state.files) {
        final fileName = p.basename(filePath).toLowerCase();
        final dirPath = p.dirname(filePath).toLowerCase();
        if (fileName.contains(term) || dirPath.contains(term)) count++;
      }
      docFreq[term] = count;
    }

    final totalDocs = state.symbols.length + state.files.length;
    const k1 = 1.2;
    const b = 0.75;

    double avgDocLength = 0;
    int docCount = 0;
    for (final symbol in state.symbols) {
      avgDocLength += symbol.name.length;
      docCount++;
    }
    for (final filePath in state.files) {
      avgDocLength += p.basename(filePath).length;
      docCount++;
    }
    avgDocLength = docCount > 0 ? avgDocLength / docCount : 1.0;

    double idf(String term) {
      final n = docFreq[term] ?? 0;
      return log((totalDocs - n + 0.5) / (n + 0.5) + 1);
    }

    double bm25(int tf, double docLen) {
      if (avgDocLength == 0) return tf.toDouble();
      final termIdf = idf;
      return termIdf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * docLen / avgDocLength));
    }

    final results = <_SearchResult>[];
    final seenFiles = <String>{};

    // 1. Symbol matches (high weight)
    for (final symbol in state.symbols) {
      final nameLower = symbol.name.toLowerCase();
      final matchedTerms = terms.where((t) => nameLower.contains(t)).toList();
      if (matchedTerms.isEmpty) continue;

      double score = 0;
      for (final term in matchedTerms) {
        final tf = matchedTerms.where((t) => t == term).length;
        score += bm25(tf, nameLower.length.toDouble());
      }
      if (nameLower == normalized) score += 5.0;
      else if (nameLower.startsWith(normalized)) score += 3.0;

      results.add(_SearchResult(
        type: 'symbol',
        title: symbol.name,
        subtitle: '${symbol.type} in ${p.basename(symbol.filePath)}:${symbol.lineNumber}',
        path: symbol.filePath,
        lineNumber: symbol.lineNumber,
        score: score,
        matchedTerms: matchedTerms,
      ));
      seenFiles.add(symbol.filePath);
    }

    // 2. File name matches (medium weight)
    for (final filePath in state.files) {
      if (seenFiles.length >= limit * 2) break;
      final fileName = p.basename(filePath).toLowerCase();
      final dirPath = p.dirname(filePath).toLowerCase();
      final matchedTerms = terms.where((t) => fileName.contains(t) || dirPath.contains(t)).toList();
      if (matchedTerms.isEmpty) continue;

      double score = 0;
      final docLen = fileName.length.toDouble();
      for (final term in matchedTerms) {
        final tf = matchedTerms.where((t) => t == term).length;
        score += bm25(tf, docLen);
      }
      if (fileName == normalized) score += 4.0;
      else if (fileName.startsWith(normalized)) score += 2.0;

      results.add(_SearchResult(
        type: 'file',
        title: p.basename(filePath),
        subtitle: p.relative(filePath, from: state.files.isNotEmpty ? p.dirname(state.files.first) : ''),
        path: filePath,
        lineNumber: 1,
        score: score,
        matchedTerms: matchedTerms,
      ));
      seenFiles.add(filePath);
    }

    // 3. Content snippet matches (lower weight, but provides context)
    final contentScanLimit = limit * 3;
    int scanned = 0;
    for (final filePath in state.files) {
      if (results.length >= contentScanLimit) break;
      scanned++;
      if (scanned % 10 != 0) continue;

      try {
        final file = File(filePath);
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        final lines = content.split('\n');
        
        for (int i = 0; i < lines.length && results.length < contentScanLimit; i++) {
          final line = lines[i];
          final lineLower = line.toLowerCase();
          final matchedTerms = terms.where((t) => lineLower.contains(t)).toList();
          if (matchedTerms.isEmpty) continue;

          double score = 0;
          final docLen = line.length.toDouble();
          for (final term in matchedTerms) {
            final tf = matchedTerms.where((t) => t == term).length;
            score += bm25(tf, docLen) * 0.5;
          }

          results.add(_SearchResult(
            type: 'snippet',
            title: '${p.basename(filePath)}:${i + 1}',
            subtitle: line.trim().length > 80 ? '${line.trim().substring(0, 80)}...' : line.trim(),
            path: filePath,
            lineNumber: i + 1,
            score: score,
            matchedTerms: matchedTerms,
          ));
        }
      } catch (_) {}
    }

    // Sort by score descending, then by path/line
    results.sort((a, b) {
      if (b.score != a.score) return b.score.compareTo(a.score);
      return a.path.compareTo(b.path);
    });

    return results.take(limit).toList();
  }
}

class _SearchResult {
  final String type; // 'symbol', 'file', 'snippet'
  final String title;
  final String subtitle;
  final String path;
  final int lineNumber;
  final double score;
  final List<String> matchedTerms;

  _SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.lineNumber,
    required this.score,
    required this.matchedTerms,
  });
}

final symbolIndexerProvider = StateNotifierProvider<SymbolIndexerNotifier, SymbolIndexerState>((ref) {
  return SymbolIndexerNotifier(ref);
});
