class GitFileDiffStats {
  final int additions;
  final int deletions;
  const GitFileDiffStats(this.additions, this.deletions);
}

class GitStatus {
  final List<String> modifiedFiles;
  final List<String> stagedFiles;
  final List<String> untrackedFiles;
  final List<String> conflictedFiles;
  final String currentBranch;
  final Map<String, GitFileDiffStats> diffStats;

  GitStatus({
    required this.modifiedFiles,
    required this.stagedFiles,
    required this.untrackedFiles,
    required this.conflictedFiles,
    required this.currentBranch,
    this.diffStats = const {},
  });

  bool get hasChanges =>
      modifiedFiles.isNotEmpty ||
      stagedFiles.isNotEmpty ||
      untrackedFiles.isNotEmpty ||
      conflictedFiles.isNotEmpty;
}
