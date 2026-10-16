import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class GitState {
  final GitStatus? status;
  final bool isLoading;
  final String? error;

  GitState({this.status, this.isLoading = false, this.error});

  GitState copyWith({
    GitStatus? status,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return GitState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GitNotifier extends StateNotifier<GitState> {
  final GitService _gitService;

  GitNotifier(this._gitService) : super(GitState());

  Future<void> refreshStatus({bool silent = false, bool force = false}) async {
    if (!silent && state.status == null) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final status = await _gitService.getStatus(forceRefresh: force);
      state = GitState(status: status, isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> stageFile(String path) async {
    await _gitService.add(path);
    await refreshStatus(silent: true, force: true);
  }

  Future<void> stageAll() async {
    await _gitService.stageAll();
    await refreshStatus(silent: true, force: true);
  }

  Future<void> unstageFile(String path) async {
    await _gitService.unstage(path);
    await refreshStatus(silent: true, force: true);
  }

  Future<void> unstageAll() async {
    await _gitService.unstageAll();
    await refreshStatus(silent: true, force: true);
  }

  Future<void> discardFile(String path) async {
    await _gitService.discardChanges(path);
    await refreshStatus(silent: true, force: true);
  }

  Future<void> discardAll() async {
    await _gitService.discardAllChanges();
    await refreshStatus(silent: true, force: true);
  }

  Future<void> commit(String message, {bool amend = false, bool autoStageIfEmpty = true}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final current = state.status;
      if (autoStageIfEmpty &&
          current != null &&
          current.stagedFiles.isEmpty &&
          (current.modifiedFiles.isNotEmpty || current.untrackedFiles.isNotEmpty)) {
        await _gitService.stageAll();
      }
      await _gitService.commit(message, amend: amend);
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> push() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.push();
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> pull() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.pull();
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> checkoutBranch(String branchName, {bool createNew = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.checkoutBranch(branchName, createNew: createNew);
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createVersionTag(String tagName, String message, {bool pushToRemote = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.createTag(tagName, message.isNotEmpty ? message : 'Release $tagName');
      if (pushToRemote) {
        await _gitService.pushWithTags();
      }
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteTag(String tagName) async {
    await _gitService.deleteTag(tagName);
    await refreshStatus(silent: true, force: true);
  }

  Future<void> stashSave([String? message]) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.stashSave(message);
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> stashPop() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.stashPop();
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<String> getCommitDetails(String commitHash) {
    return _gitService.getCommitDetails(commitHash);
  }

  Future<String> getFileDiff(String filePath, {bool staged = false}) {
    return _gitService.getFileDiff(filePath, staged: staged);
  }

  Future<void> init() async {
    await _gitService.initRepo();
    await refreshStatus(force: true);
  }

  Future<void> releaseAndBuildApk({
    required String tagName,
    required String commitMessage,
    required String releaseNotes,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final status = await _gitService.getStatus(forceRefresh: true);
      if (status != null && status.hasChanges) {
        await _gitService.stageAll();
        await _gitService.commit(commitMessage.isNotEmpty ? commitMessage : 'Release $tagName');
      }

      await _gitService.createTag(tagName, releaseNotes.isNotEmpty ? releaseNotes : 'Release $tagName');
      await _gitService.pushWithTags();
      await refreshStatus(silent: true, force: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }
}

final StateNotifierProvider<GitNotifier, GitState> gitProvider = StateNotifierProvider<GitNotifier, GitState>((ref) {
  ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
    if (previous?.currentPath != next.currentPath) {
      ref.read(gitProvider.notifier).refreshStatus(force: true);
    }
  });
  return GitNotifier(ref.watch(gitServiceProvider));
});

