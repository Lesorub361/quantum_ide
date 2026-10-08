import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class GitState {
  final GitStatus? status;
  final bool isLoading;
  final String? error;

  GitState({this.status, this.isLoading = false, this.error});

  GitState copyWith({GitStatus? status, bool? isLoading, String? error}) {
    return GitState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class GitNotifier extends StateNotifier<GitState> {
  final GitService _gitService;

  GitNotifier(this._gitService) : super(GitState());

  Future<void> refreshStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final status = await _gitService.getStatus();
      state = state.copyWith(isLoading: false, status: status);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> stageFile(String path) async {
    await _gitService.add(path);
    await refreshStatus();
  }

  Future<void> unstageFile(String path) async {
    await _gitService.unstage(path);
    await refreshStatus();
  }

  Future<void> commit(String message) async {
    state = state.copyWith(isLoading: true);
    try {
      await _gitService.commit(message);
      await refreshStatus();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> push() async {
    state = state.copyWith(isLoading: true);
    try {
      await _gitService.push();
      await refreshStatus();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> pull() async {
    state = state.copyWith(isLoading: true);
    try {
      await _gitService.pull();
      await refreshStatus();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> init() async {
    await _gitService.initRepo();
    await refreshStatus();
  }

  Future<void> releaseAndBuildApk({
    required String tagName,
    required String commitMessage,
    required String releaseNotes,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      // 1. Stage all changes if any
      final status = await _gitService.getStatus();
      if (status != null && status.hasChanges) {
        await _gitService.add('.');
        await _gitService.commit(commitMessage.isNotEmpty ? commitMessage : 'Release $tagName');
      }

      // 2. Create annotated git tag
      await _gitService.createTag(tagName, releaseNotes.isNotEmpty ? releaseNotes : 'Release $tagName');

      // 3. Push commit and tag to remote
      await _gitService.pushWithTags();
      await refreshStatus();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }
}

final StateNotifierProvider<GitNotifier, GitState> gitProvider = StateNotifierProvider<GitNotifier, GitState>((ref) {
  ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
    ref.read(gitProvider.notifier).refreshStatus();
  });
  return GitNotifier(ref.watch(gitServiceProvider));
});
