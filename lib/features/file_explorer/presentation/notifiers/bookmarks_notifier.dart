import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class BookmarksNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  String? _currentWorkspacePath;

  BookmarksNotifier(this._ref) : super({}) {
    _ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      if (next.currentPath != _currentWorkspacePath) {
        _currentWorkspacePath = next.currentPath;
        _loadBookmarks();
      }
    });
    _currentWorkspacePath = _ref.read(workspaceProvider).currentPath;
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final path = _currentWorkspacePath;
    if (path == null) {
      state = {};
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('bookmarks_$path') ?? [];
      state = list.toSet();
    } catch (e) {
      state = {};
    }
  }

  Future<void> toggleBookmark(String filePath) async {
    final newSet = {...state};
    if (newSet.contains(filePath)) {
      newSet.remove(filePath);
    } else {
      newSet.add(filePath);
    }
    state = newSet;

    final path = _currentWorkspacePath;
    if (path != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('bookmarks_$path', newSet.toList());
      } catch (e) {
        // Ignore
      }
    }
  }

  bool isBookmarked(String filePath) => state.contains(filePath);
}

final bookmarksProvider = StateNotifierProvider<BookmarksNotifier, Set<String>>((ref) {
  return BookmarksNotifier(ref);
});
