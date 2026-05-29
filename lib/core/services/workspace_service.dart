import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';

class WorkspaceState {
  final String? currentPath;
  final List<String> recentProjects;

  WorkspaceState({this.currentPath, this.recentProjects = const []});

  WorkspaceState copyWith({String? currentPath, List<String>? recentProjects}) {
    return WorkspaceState(
      currentPath: currentPath ?? this.currentPath,
      recentProjects: recentProjects ?? this.recentProjects,
    );
  }
}

class WorkspaceNotifier extends StateNotifier<WorkspaceState> {
  final Ref ref;
  WorkspaceNotifier(this.ref) : super(WorkspaceState()) {
    _loadFromPrefs();
  }

  static const _keyCurrentPath = 'current_workspace_path';
  static const _keyRecentProjects = 'recent_projects';

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var recent = prefs.getStringList(_keyRecentProjects) ?? [];

    // Migrate old /tmp/quantum_ide and mobile paths to ~/.quantum_ide (Desktop)
    if (!Platform.isAndroid && !Platform.isIOS) {
      final homeDir = Platform.environment['HOME'] ?? '';
      final newBase = p.join(homeDir, '.quantum_ide');
      final pcProjectsDir = p.join(newBase, 'projects');
      const oldBase = '/tmp/quantum_ide';
      bool migrated = false;
      recent = recent.map((path) {
        if (path.startsWith(oldBase)) {
          migrated = true;
          return path.replaceFirst(oldBase, newBase);
        }
        if (path.startsWith('/root/projects/')) {
          migrated = true;
          return p.join(pcProjectsDir, path.substring('/root/projects/'.length));
        }
        if (path.contains('/projects/') && !path.startsWith(newBase)) {
          migrated = true;
          final index = path.indexOf('/projects/');
          return p.join(pcProjectsDir, path.substring(index + '/projects/'.length));
        }
        return path;
      }).where((path) => Directory(path).existsSync()).toList();
      if (migrated) {
        await prefs.setStringList(_keyRecentProjects, recent);
      }
    }

    state = WorkspaceState(currentPath: null, recentProjects: recent);
  }

  Future<void> setWorkspace(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentPath, path);
    
    final recent = List<String>.from(state.recentProjects);
    if (!recent.contains(path)) {
      recent.insert(0, path);
      if (recent.length > 5) recent.removeLast();
      await prefs.setStringList(_keyRecentProjects, recent);
    }
    
    state = state.copyWith(currentPath: path, recentProjects: recent);
  }

  Future<void> closeWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentPath);
    state = state.copyWith(currentPath: null);
    
    // Perform centralized cleanup of other modules
    ref.read(editorProvider.notifier).clearWorkspace();
    ref.read(terminalTabsProvider.notifier).closeAllSessions();
    ref.read(gitProvider.notifier).refreshStatus();
  }
}

final workspaceProvider = StateNotifierProvider<WorkspaceNotifier, WorkspaceState>((ref) {
  return WorkspaceNotifier(ref);
});
