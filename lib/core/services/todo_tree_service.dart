import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

class TodoItem {
  final String filePath;
  final int line;
  final String text;
  final String type;

  const TodoItem({
    required this.filePath,
    required this.line,
    required this.text,
    required this.type,
  });
}

class TodoTreeState {
  final List<TodoItem> items;
  final bool isLoading;
  final String? filter;

  const TodoTreeState({
    this.items = const [],
    this.isLoading = false,
    this.filter,
  });

  TodoTreeState copyWith({List<TodoItem>? items, bool? isLoading, String? filter}) {
    return TodoTreeState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      filter: filter ?? this.filter,
    );
  }

  List<TodoItem> get filtered {
    if (filter == null || filter!.isEmpty) return items;
    final lower = filter!.toLowerCase();
    return items.where((i) => i.text.toLowerCase().contains(lower)).toList();
  }
}

class TodoTreeNotifier extends StateNotifier<TodoTreeState> {
  final Ref _ref;

  TodoTreeNotifier(this._ref) : super(const TodoTreeState());

  Future<void> scan() async {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    state = state.copyWith(isLoading: true);

    final items = <TodoItem>[];
    final patterns = ['TODO', 'FIXME', 'HACK', 'XXX', 'BUG'];

    await _scanDirectory(Directory(workspacePath), items, patterns, workspacePath);

    items.sort((a, b) {
      final typeOrder = {'FIXME': 0, 'BUG': 1, 'TODO': 2, 'HACK': 3, 'XXX': 4};
      final aOrder = typeOrder[a.type] ?? 5;
      final bOrder = typeOrder[b.type] ?? 5;
      return aOrder.compareTo(bOrder);
    });

    state = state.copyWith(items: items, isLoading: false);
  }

  Future<void> _scanDirectory(Directory dir, List<TodoItem> items, List<String> patterns, String rootPath) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final ext = p.extension(entity.path);
          if (!_isScannable(ext)) continue;
          if (entity.path.contains('.dart_tool') || entity.path.contains('build/')) continue;

          try {
            final content = await entity.readAsString();
            final lines = content.split('\n');
            final relativePath = p.relative(entity.path, from: rootPath);

            for (int i = 0; i < lines.length; i++) {
              final line = lines[i];
              for (final pattern in patterns) {
                final idx = line.indexOf(pattern);
                if (idx != -1) {
                  final text = line.substring(idx).trim();
                  items.add(TodoItem(
                    filePath: relativePath,
                    line: i + 1,
                    text: text.length > 100 ? '${text.substring(0, 100)}...' : text,
                    type: pattern,
                  ));
                }
              }
            }
          } catch (_) {}
        } else if (entity is Directory) {
          final name = p.basename(entity.path);
          if (!name.startsWith('.') && name != 'build' && name != 'node_modules') {
            await _scanDirectory(entity, items, patterns, rootPath);
          }
        }
        // Yield to event loop to keep UI smooth
        await Future.delayed(Duration.zero);
      }
    } catch (_) {}
  }

  bool _isScannable(String ext) {
    return ['.dart', '.ts', '.js', '.tsx', '.jsx', '.py', '.java', '.kt', '.swift', '.go', '.rs', '.c', '.cpp', '.h']
        .contains(ext);
  }

  void setFilter(String? filter) {
    state = state.copyWith(filter: filter);
  }
}

final todoTreeProvider = StateNotifierProvider<TodoTreeNotifier, TodoTreeState>((ref) {
  return TodoTreeNotifier(ref);
});
