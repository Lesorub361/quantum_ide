import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:quantum_ide/core/services/ghost_qa_service.dart';
import 'package:quantum_ide/core/utils/platform_utils.dart';

class WorkspaceState {
  final String? currentPath;
  final List<String> recentProjects;

  WorkspaceState({this.currentPath, this.recentProjects = const []});

  WorkspaceState copyWith({
    String? currentPath,
    bool clearCurrentPath = false,
    List<String>? recentProjects,
  }) {
    return WorkspaceState(
      currentPath: clearCurrentPath ? null : (currentPath ?? this.currentPath),
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
      final newBase = PlatformUtils.desktopDataDir;
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
      }).toList();
      final validRecent = <String>[];
      for (final path in recent) {
        if (await Directory(path).exists()) validRecent.add(path);
      }
      recent = validRecent;
      if (migrated) {
        await prefs.setStringList(_keyRecentProjects, recent);
      }
    }

    state = WorkspaceState(currentPath: null, recentProjects: recent);
  }

  Future<void> restoreLastWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final currentSaved = prefs.getString(_keyCurrentPath);
    if (currentSaved != null && Directory(currentSaved).existsSync()) {
      await setWorkspace(currentSaved);
    }
  }

  Future<void> setWorkspace(String path) async {
    String resolvedPath = path;
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        final hasDirectMarkers = await File(p.join(path, 'pubspec.yaml')).exists() ||
            await File(p.join(path, 'package.json')).exists() ||
            await Directory(p.join(path, '.git')).exists() ||
            await File(p.join(path, 'build.gradle')).exists() ||
            await File(p.join(path, 'build.gradle.kts')).exists() ||
            await File(p.join(path, 'main.py')).exists();

        if (!hasDirectMarkers) {
          final folderName = p.basename(path);
          final nestedSameName = Directory(p.join(path, folderName));
          if (await nestedSameName.exists()) {
            final hasNested = await File(p.join(nestedSameName.path, 'pubspec.yaml')).exists() ||
                await File(p.join(nestedSameName.path, 'package.json')).exists() ||
                await Directory(p.join(nestedSameName.path, '.git')).exists();
            if (hasNested) {
              resolvedPath = nestedSameName.path;
              LogService.log('Workspace auto-resolved to nested project directory: $resolvedPath');
            }
          }
        }
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentPath, resolvedPath);
    
    final recent = List<String>.from(state.recentProjects);
    if (!recent.contains(resolvedPath)) {
      recent.insert(0, resolvedPath);
      if (recent.length > 5) recent.removeLast();
      await prefs.setStringList(_keyRecentProjects, recent);
    }
    
    await _ensureGitIgnore(resolvedPath);
    await LogService.setWorkspace(resolvedPath);
    GhostQAService.instance.onWorkspaceChanged(resolvedPath);
    state = state.copyWith(currentPath: resolvedPath, recentProjects: recent);
  }

  Future<void> _ensureGitIgnore(String workspacePath) async {
    try {
      final gitIgnoreFile = File(p.join(workspacePath, '.gitignore'));
      if (await gitIgnoreFile.exists()) {
        final content = await gitIgnoreFile.readAsString();
        if (!content.contains('.quantum/') && !content.contains('.quantum')) {
          final sb = StringBuffer(content);
          if (!content.endsWith('\n')) {
            sb.write('\n');
          }
          sb.writeln('.quantum/');
          await gitIgnoreFile.writeAsString(sb.toString());
          LogService.log('Gitignore auto-check: added .quantum/ to .gitignore to keep workspace clean.');
        } else {
          LogService.log('Gitignore auto-check: .quantum/ is already ignored.');
        }
      } else {
        await gitIgnoreFile.writeAsString('.quantum/\n');
        LogService.log('Gitignore auto-check: created .gitignore and added .quantum/.');
      }
    } catch (e) {
      LogService.log('Gitignore auto-check failed: $e');
    }
  }

  Future<void> closeWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentPath);
    await LogService.setWorkspace(null);
    GhostQAService.instance.onWorkspaceChanged(null);
    state = state.copyWith(clearCurrentPath: true);
    
    // Perform centralized cleanup of other modules
    ref.read(editorProvider.notifier).clearWorkspace();
    ref.read(terminalTabsProvider.notifier).closeAllSessions();
    ref.read(gitProvider.notifier).refreshStatus();
  }
}

final workspaceProvider = StateNotifierProvider<WorkspaceNotifier, WorkspaceState>((ref) {
  return WorkspaceNotifier(ref);
});
