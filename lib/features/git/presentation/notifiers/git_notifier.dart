import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class GitState {
  final GitStatus? status;
  final bool isLoading;
  final String? error;
  final String? lastActionMessage;
  final String? currentOperation;

  GitState({
    this.status,
    this.isLoading = false,
    this.error,
    this.lastActionMessage,
    this.currentOperation,
  });

  GitState copyWith({
    GitStatus? status,
    bool? isLoading,
    String? error,
    String? lastActionMessage,
    String? currentOperation,
    bool clearError = false,
    bool clearMessage = false,
    bool clearOperation = false,
  }) {
    return GitState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastActionMessage: clearMessage ? null : (lastActionMessage ?? this.lastActionMessage),
      currentOperation: clearOperation ? null : (currentOperation ?? this.currentOperation),
    );
  }
}

class GitNotifier extends StateNotifier<GitState> {
  final GitService _gitService;

  GitNotifier(this._gitService) : super(GitState());

  Future<void> refreshStatus({bool silent = false, bool force = false, String? message}) async {
    if (!silent && state.status == null) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final status = await _gitService.getStatus(forceRefresh: force);
      state = GitState(
        status: status,
        isLoading: false,
        error: null,
        lastActionMessage: message,
        currentOperation: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
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
    state = state.copyWith(isLoading: true, currentOperation: 'Откат изменений в файле...', clearError: true);
    await _gitService.discardChanges(path);
    await refreshStatus(silent: true, force: true, message: 'Изменения в файле сброшены');
  }

  Future<void> discardAll() async {
    state = state.copyWith(isLoading: true, currentOperation: 'Откат всех изменений рабочей копии...', clearError: true);
    await _gitService.discardAllChanges();
    await refreshStatus(silent: true, force: true, message: 'Все изменения рабочей копии откатаны');
  }

  Future<void> addToGitignore(String pattern) async {
    await _gitService.addToGitignore(pattern);
    await refreshStatus(silent: true, force: true, message: 'Добавлено в .gitignore: $pattern');
  }

  Future<bool> commit(String message, {bool amend = false, bool autoStageIfEmpty = true}) async {
    state = state.copyWith(
      isLoading: true,
      currentOperation: amend ? 'Дополнение предыдущего коммита (--amend)...' : 'Создание Git-коммита...',
      clearError: true,
      clearMessage: true,
    );
    try {
      final current = state.status;
      if (autoStageIfEmpty &&
          current != null &&
          current.stagedFiles.isEmpty &&
          (current.modifiedFiles.isNotEmpty || current.untrackedFiles.isNotEmpty)) {
        await _gitService.stageAll();
      }
      await _gitService.commit(message, amend: amend);
      await refreshStatus(silent: true, force: true, message: amend ? 'Коммит успешно обновлён (--amend)' : 'Коммит успешно создан');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
      return false;
    }
  }

  Future<bool> commitAndPush(String message, {bool amend = false}) async {
    state = state.copyWith(
      isLoading: true,
      currentOperation: 'Создание коммита и отправка на GitHub (git push)...',
      clearError: true,
      clearMessage: true,
    );
    try {
      final current = state.status;
      if (current != null &&
          current.stagedFiles.isEmpty &&
          (current.modifiedFiles.isNotEmpty || current.untrackedFiles.isNotEmpty)) {
        await _gitService.stageAll();
      }
      await _gitService.commit(message, amend: amend);
      await _gitService.push();
      await refreshStatus(silent: true, force: true, message: 'Коммит успешно создан и отправлен на GitHub!');
      return true;
    } catch (e) {
      await refreshStatus(silent: true, force: true);
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
      return false;
    }
  }

  Future<bool> fetch() async {
    state = state.copyWith(
      isLoading: true,
      currentOperation: 'Проверка изменений на GitHub (git fetch)...',
      clearError: true,
      clearMessage: true,
    );
    try {
      await _gitService.fetch();
      await refreshStatus(silent: true, force: true, message: 'Проверка завершена (ветки и теги обновлены)');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
      return false;
    }
  }

  Future<bool> push({bool force = false}) async {
    state = state.copyWith(
      isLoading: true,
      currentOperation: force ? 'Принудительная отправка на GitHub (force push)...' : 'Отправка коммитов на GitHub (git push)...',
      clearError: true,
      clearMessage: true,
    );
    try {
      await _gitService.push(force: force);
      await refreshStatus(silent: true, force: true, message: 'Код успешно отправлен на GitHub!');
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
      return false;
    }
  }

  Future<bool> pull({bool rebase = false}) async {
    state = state.copyWith(
      isLoading: true,
      currentOperation: 'Подтягивание изменений с GitHub (git pull)...',
      clearError: true,
      clearMessage: true,
    );
    try {
      await _gitService.pull(rebase: rebase);
      await refreshStatus(silent: true, force: true, message: 'Изменения успешно подтянуты с GitHub!');
      return true;
    } catch (e) {
      await refreshStatus(silent: true, force: true);
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
      return false;
    }
  }

  Future<bool> sync() async {
    state = state.copyWith(
      isLoading: true,
      currentOperation: 'Синхронизация с сервером (Pull & Push)...',
      clearError: true,
      clearMessage: true,
    );
    try {
      await _gitService.pull();
      await _gitService.push();
      await refreshStatus(silent: true, force: true, message: 'Синхронизация успешно завершена (Pull + Push)!');
      return true;
    } catch (e) {
      await refreshStatus(silent: true, force: true);
      state = state.copyWith(isLoading: false, clearOperation: true, error: e.toString());
      return false;
    }
  }

  Future<void> setRemoteUrl(String url) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.setRemoteUrl(url);
      await refreshStatus(silent: true, force: true, message: 'Remote origin обновлён');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> setUserConfig(String name, String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.setUserConfig(name, email);
      await refreshStatus(silent: true, force: true, message: 'Автор коммитов сохранён: $name <$email>');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> checkoutBranch(String branchName, {bool createNew = false, String? fromRef}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.checkoutBranch(branchName, createNew: createNew, fromRef: fromRef);
      await refreshStatus(silent: true, force: true, message: 'Переключено на ветку $branchName');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> mergeBranch(String branchName) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.mergeBranch(branchName);
      await refreshStatus(silent: true, force: true, message: 'Ветка $branchName влита в текущую');
      return true;
    } catch (e) {
      await refreshStatus(silent: true, force: true);
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<void> deleteBranch(String branchName, {bool force = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.deleteBranch(branchName, force: force);
      await refreshStatus(silent: true, force: true, message: 'Ветка $branchName удалена');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> renameBranch(String oldName, String newName) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.renameBranch(oldName, newName);
      await refreshStatus(silent: true, force: true, message: 'Ветка переименована в $newName');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> resetToCommit(String commitHash, {String mode = 'mixed'}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.resetToCommit(commitHash, mode: mode);
      await refreshStatus(silent: true, force: true, message: 'Выполнен git reset --$mode к $commitHash');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> revertCommit(String commitHash) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.revertCommit(commitHash);
      await refreshStatus(silent: true, force: true, message: 'Коммит $commitHash обращён (revert)');
    } catch (e) {
      await refreshStatus(silent: true, force: true);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> cherryPickCommit(String commitHash) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.cherryPickCommit(commitHash);
      await refreshStatus(silent: true, force: true, message: 'Cherry-pick коммита $commitHash выполнен');
    } catch (e) {
      await refreshStatus(silent: true, force: true);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createVersionTag(String tagName, String message, {bool pushToRemote = false, String? commitHash}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.createTag(
        tagName,
        message.isNotEmpty ? message : 'Release $tagName',
        commitHash: commitHash,
      );
      if (pushToRemote) {
        await _gitService.pushWithTags();
      }
      await refreshStatus(silent: true, force: true, message: 'Тег $tagName создан');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteTag(String tagName) async {
    await _gitService.deleteTag(tagName);
    await refreshStatus(silent: true, force: true, message: 'Тег $tagName удалён');
  }

  Future<void> stashSave([String? message]) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.stashSave(message);
      await refreshStatus(silent: true, force: true, message: 'Изменения спрятаны в Stash');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> stashPop([String? stashRef]) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.stashPop(stashRef);
      await refreshStatus(silent: true, force: true, message: 'Stash восстановлен (Pop)');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> stashApply(String stashRef) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.stashApply(stashRef);
      await refreshStatus(silent: true, force: true, message: 'Stash применён ($stashRef)');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> stashDrop(String stashRef) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _gitService.stashDrop(stashRef);
      await refreshStatus(silent: true, force: true, message: 'Stash удалён ($stashRef)');
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<String> getStashDiff(String stashRef) {
    return _gitService.getStashDiff(stashRef);
  }

  Future<List<GitCommitFileEntry>> getCommitFiles(String commitHash) {
    return _gitService.getCommitFiles(commitHash);
  }

  Future<String> getCommitDetails(String commitHash) {
    return _gitService.getCommitDetails(commitHash);
  }

  Future<String> getFileDiff(String filePath, {bool staged = false}) {
    return _gitService.getFileDiff(filePath, staged: staged);
  }

  Future<void> init() async {
    await _gitService.initRepo();
    await refreshStatus(force: true, message: 'Git-репозиторий инициализирован');
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
      await refreshStatus(silent: true, force: true, message: 'Релиз $tagName отправлен в GitHub');
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
