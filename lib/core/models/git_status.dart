class GitStatus {
  final List<String> modifiedFiles;
  final List<String> stagedFiles;
  final List<String> untrackedFiles;
  final List<String> conflictedFiles;
  final String currentBranch;

  GitStatus({
    required this.modifiedFiles,
    required this.stagedFiles,
    required this.untrackedFiles,
    required this.conflictedFiles,
    required this.currentBranch,
  });

  bool get hasChanges =>
      modifiedFiles.isNotEmpty ||
      stagedFiles.isNotEmpty ||
      untrackedFiles.isNotEmpty ||
      conflictedFiles.isNotEmpty;
}
