class GitFileDiffStats {
  final int additions;
  final int deletions;
  const GitFileDiffStats(this.additions, this.deletions);
}

class GitCommitEntry {
  final String hash;
  final String shortHash;
  final String message;
  final String author;
  final String relativeTime;
  final String refs;

  const GitCommitEntry({
    required this.hash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.relativeTime,
    this.refs = '',
  });
}

class GitTagEntry {
  final String name;
  final String shortHash;
  final String date;
  final String subject;

  const GitTagEntry({
    required this.name,
    required this.shortHash,
    required this.date,
    this.subject = '',
  });
}

class GitStatus {
  final List<String> modifiedFiles;
  final List<String> stagedFiles;
  final List<String> untrackedFiles;
  final List<String> conflictedFiles;
  final String currentBranch;
  final List<String> branches;
  final int ahead;
  final int behind;
  final Map<String, GitFileDiffStats> diffStats;
  final List<GitCommitEntry> recentCommits;
  final List<GitTagEntry> tags;
  final String? projectVersion;
  final String? remoteUrl;

  GitStatus({
    required this.modifiedFiles,
    required this.stagedFiles,
    required this.untrackedFiles,
    required this.conflictedFiles,
    required this.currentBranch,
    this.branches = const [],
    this.ahead = 0,
    this.behind = 0,
    this.diffStats = const {},
    this.recentCommits = const [],
    this.tags = const [],
    this.projectVersion,
    this.remoteUrl,
  });

  bool get hasChanges =>
      modifiedFiles.isNotEmpty ||
      stagedFiles.isNotEmpty ||
      untrackedFiles.isNotEmpty ||
      conflictedFiles.isNotEmpty;

  int get totalChangesCount =>
      modifiedFiles.length +
      stagedFiles.length +
      untrackedFiles.length +
      conflictedFiles.length;
}

