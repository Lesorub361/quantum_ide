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

class GitCommitFileEntry {
  final String status; // M, A, D, R
  final String path;

  const GitCommitFileEntry({
    required this.status,
    required this.path,
  });
}

class GitStashEntry {
  final String ref; // e.g. stash@{0}
  final String branch;
  final String message;
  final String relativeTime;

  const GitStashEntry({
    required this.ref,
    required this.branch,
    required this.message,
    this.relativeTime = '',
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
  final Map<String, String> fileStatusCodes; // path -> 'M', 'A', 'D', 'R', 'U', '?'
  final String currentBranch;
  final List<String> branches;
  final List<String> remoteBranches;
  final int ahead;
  final int behind;
  final Map<String, GitFileDiffStats> diffStats;
  final List<GitCommitEntry> recentCommits;
  final List<GitTagEntry> tags;
  final List<GitStashEntry> stashes;
  final String? projectVersion;
  final String? remoteUrl;
  final String? userName;
  final String? userEmail;

  GitStatus({
    required this.modifiedFiles,
    required this.stagedFiles,
    required this.untrackedFiles,
    required this.conflictedFiles,
    this.fileStatusCodes = const {},
    required this.currentBranch,
    this.branches = const [],
    this.remoteBranches = const [],
    this.ahead = 0,
    this.behind = 0,
    this.diffStats = const {},
    this.recentCommits = const [],
    this.tags = const [],
    this.stashes = const [],
    this.projectVersion,
    this.remoteUrl,
    this.userName,
    this.userEmail,
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

  int get workingTreeChangesCount =>
      modifiedFiles.length + untrackedFiles.length + conflictedFiles.length;
}
