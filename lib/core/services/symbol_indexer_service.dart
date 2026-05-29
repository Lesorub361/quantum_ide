import 'dart:async';
import 'dart:io';
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
      final dir = Directory(workspaceRoot);

      if (!await dir.exists()) {
        state = state.copyWith(isIndexing: false, error: 'Директория проекта не найдена');
        return;
      }

      final List<FileSystemEntity> entities = await _listAllFiles(dir);

      for (final entity in entities) {
        if (entity is File) {
          allFiles.add(entity.path);
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.dart' || ext == '.js' || ext == '.ts' || ext == '.py' || ext == '.go') {
            final symbols = await _parseFile(entity);
            allSymbols.addAll(symbols);
          }
        }
        // Yield to event loop to keep UI smooth
        await Future.delayed(Duration.zero);
      }

      state = state.copyWith(isIndexing: false, symbols: allSymbols, files: allFiles);
    } catch (e) {
      state = state.copyWith(isIndexing: false, error: 'Ошибка индексации: $e');
    }
  }

  Future<List<FileSystemEntity>> _listAllFiles(Directory dir) async {
    final List<FileSystemEntity> files = [];
    try {
      final List<FileSystemEntity> entities = await dir.list(recursive: true, followLinks: false).toList();
      for (final entity in entities) {
        // Skip ignored directories
        final pathSegments = p.split(entity.path);
        bool shouldIgnore = false;
        for (final segment in pathSegments) {
          if (_ignoredDirs.contains(segment)) {
            shouldIgnore = true;
            break;
          }
        }
        if (!shouldIgnore) {
          files.add(entity);
        }
      }
    } catch (_) {}
    return files;
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

      final ext = p.extension(file.path).toLowerCase();

      // Regex patterns
      final dartClassReg = RegExp(r'^\s*(?:abstract\s+|mixin\s+|extension\s+)?class\s+([A-Za-z0-9_]+)');
      final dartMethodReg = RegExp(
          r'^\s*(?:(?:Future<[A-Za-z0-9_<>]+>|Stream<[A-Za-z0-9_<>]+>|void|[A-Za-z0-9_<>]+)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?:async\s*)?[\{=>]');
      final pythonClassReg = RegExp(r'^\s*class\s+([A-Za-z0-9_]+)');
      final pythonDefReg = RegExp(r'^\s*def\s+([A-Za-z0-9_]+)');
      final jsFuncReg = RegExp(r'^\s*(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)');
      final jsMethodReg = RegExp(r'^\s*(?:async\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*\{');

      const keywords = {
        'if', 'for', 'switch', 'while', 'catch', 'return', 'assert', 'await',
        'import', 'export', 'part', 'library', 'else', 'super', 'this', 'throw', 'yield',
        'void', 'dynamic', 'var', 'final', 'const'
      };

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];

        if (ext == '.dart') {
          final classMatch = dartClassReg.firstMatch(line);
          if (classMatch != null) {
            symbols.add(IndexSymbol(
              name: classMatch.group(1)!,
              type: 'class',
              filePath: file.path,
              lineNumber: i + 1,
            ));
            continue;
          }

          final methodMatch = dartMethodReg.firstMatch(line);
          if (methodMatch != null) {
            final name = methodMatch.group(1)!;
            if (!keywords.contains(name) && name != 'Widget' && name != 'build') {
              symbols.add(IndexSymbol(
                name: name,
                type: 'method',
                filePath: file.path,
                lineNumber: i + 1,
              ));
            }
          }
        } else if (ext == '.py') {
          final classMatch = pythonClassReg.firstMatch(line);
          if (classMatch != null) {
            symbols.add(IndexSymbol(
              name: classMatch.group(1)!,
              type: 'class',
              filePath: file.path,
              lineNumber: i + 1,
            ));
            continue;
          }

          final defMatch = pythonDefReg.firstMatch(line);
          if (defMatch != null) {
            final name = defMatch.group(1)!;
            symbols.add(IndexSymbol(
              name: name,
              type: 'method',
              filePath: file.path,
              lineNumber: i + 1,
            ));
          }
        } else if (ext == '.js' || ext == '.ts') {
          final funcMatch = jsFuncReg.firstMatch(line);
          if (funcMatch != null) {
            symbols.add(IndexSymbol(
              name: funcMatch.group(1)!,
              type: 'method',
              filePath: file.path,
              lineNumber: i + 1,
            ));
            continue;
          }

          final methodMatch = jsMethodReg.firstMatch(line);
          if (methodMatch != null) {
            final name = methodMatch.group(1)!;
            if (!keywords.contains(name) && name != 'constructor') {
              symbols.add(IndexSymbol(
                name: name,
                type: 'method',
                filePath: file.path,
                lineNumber: i + 1,
              ));
            }
          }
        }
      }
    } catch (_) {}
    return symbols;
  }

  List<IndexSymbol> searchSymbols(String query) {
    if (query.isEmpty) {
      return state.symbols.take(50).toList();
    }
    final normalized = query.toLowerCase();
    
    // Sort results by how close they match
    final matched = state.symbols.where((symbol) {
      final nameLower = symbol.name.toLowerCase();
      return nameLower.contains(normalized);
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

      return a.name.compareTo(b.name);
    });

    return matched.take(50).toList();
  }

  List<String> searchFiles(String query) {
    if (query.isEmpty) {
      return state.files.take(50).toList();
    }
    final normalized = query.toLowerCase();
    
    final matched = state.files.where((filePath) {
      final fileName = p.basename(filePath).toLowerCase();
      return fileName.contains(normalized) || filePath.toLowerCase().contains(normalized);
    }).toList();

    // Sort: files whose name starts with query first, then files whose name contains query
    matched.sort((a, b) {
      final aName = p.basename(a).toLowerCase();
      final bName = p.basename(b).toLowerCase();
      
      final aStartsWith = aName.startsWith(normalized);
      final bStartsWith = bName.startsWith(normalized);
      if (aStartsWith && !bStartsWith) return -1;
      if (bStartsWith && !aStartsWith) return 1;

      final aNameContains = aName.contains(normalized);
      final bNameContains = bName.contains(normalized);
      if (aNameContains && !bNameContains) return -1;
      if (bNameContains && !aNameContains) return 1;

      return a.compareTo(b);
    });

    return matched.take(50).toList();
  }
}

final symbolIndexerProvider = StateNotifierProvider<SymbolIndexerNotifier, SymbolIndexerState>((ref) {
  return SymbolIndexerNotifier(ref);
});
