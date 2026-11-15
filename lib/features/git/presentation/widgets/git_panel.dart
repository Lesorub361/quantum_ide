import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/github_service.dart';
import 'package:quantum_ide/core/services/secure_storage_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_graph_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';
import 'package:quantum_ide/features/git/presentation/widgets/git_download_dialog.dart';
import 'package:quantum_ide/features/git/presentation/widgets/git_theme.dart';
import 'package:quantum_ide/features/github/presentation/pages/github_page.dart';
import 'package:url_launcher/url_launcher.dart';

class SidebarGitPanel extends GitPanel {
  const SidebarGitPanel({super.key, super.isBottomPanel = false});
}

class GitPanel extends ConsumerStatefulWidget {
  final bool isBottomPanel;
  const GitPanel({super.key, this.isBottomPanel = false});

  @override
  ConsumerState<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends ConsumerState<GitPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _commitController = TextEditingController();
  final TextEditingController _fileFilterController = TextEditingController();
  final TextEditingController _commitSearchController = TextEditingController();
  final TextEditingController _branchFilterController = TextEditingController();
  late TabController _tabController;

  bool _isGeneratingCommitMessage = false;
  bool _amendCommit = false;
  bool _stagedExpanded = true;
  bool _workingExpanded = true;
  bool _conflictsExpanded = true;
  bool _localBranchesExpanded = true;
  bool _remoteBranchesExpanded = true;
  String _fileFilter = '';
  String _commitFilter = '';
  String _branchFilter = '';

  static const List<String> _conventionalPrefixes = [
    'feat: ',
    'fix: ',
    'refactor: ',
    'ui: ',
    'docs: ',
    'chore: ',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fileFilterController.addListener(() {
      setState(() {
        _fileFilter = _fileFilterController.text.trim().toLowerCase();
      });
    });
    _commitSearchController.addListener(() {
      setState(() {
        _commitFilter = _commitSearchController.text.trim().toLowerCase();
      });
    });
    _branchFilterController.addListener(() {
      setState(() {
        _branchFilter = _branchFilterController.text.trim().toLowerCase();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gitProvider.notifier).refreshStatus();
    });
  }

  @override
  void dispose() {
    _commitController.dispose();
    _fileFilterController.dispose();
    _commitSearchController.dispose();
    _branchFilterController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _applyPrefix(String prefix) {
    final text = _commitController.text;
    for (final existing in _conventionalPrefixes) {
      if (text.startsWith(existing)) {
        _commitController.text = '$prefix${text.substring(existing.length)}';
        _commitController.selection = TextSelection.fromPosition(
          TextPosition(offset: _commitController.text.length),
        );
        setState(() {});
        return;
      }
    }
    _commitController.text = '$prefix$text';
    _commitController.selection = TextSelection.fromPosition(
      TextPosition(offset: _commitController.text.length),
    );
    setState(() {});
  }

  Future<void> _generateSmartCommitMessage() async {
    final gitState = ref.read(gitProvider);
    final status = gitState.status;
    if (status == null) return;

    final allChanged = <String>{
      ...status.stagedFiles,
      ...status.modifiedFiles,
      ...status.untrackedFiles,
    }.toList();

    if (allChanged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет изменённых файлов для анализа')),
      );
      return;
    }

    setState(() => _isGeneratingCommitMessage = true);

    try {
      final names = allChanged.map((f) => p.basename(f)).take(3).join(', ');
      final suffix =
          allChanged.length > 3 ? ' (+${allChanged.length - 3})' : '';
      String prefix = 'chore';
      if (status.untrackedFiles.isNotEmpty && status.modifiedFiles.isEmpty) {
        prefix = 'feat';
      } else if (allChanged.any(
        (f) => f.contains('fix') || f.contains('bug') || f.contains('service'),
      )) {
        prefix = 'fix';
      } else if (allChanged.any(
        (f) => f.contains('widget') || f.contains('page') || f.contains('ui'),
      )) {
        prefix = 'feat';
      }
      _commitController.text = '$prefix: update $names$suffix';
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCommitMessage = false);
      }
    }
  }

  void _openFileDiff(String file, {required bool isStaged}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GitDiffPage(
          relativePath: file,
          initiallyStaged: isStaged,
        ),
      ),
    );
  }

  void _openFileInEditor(String relativePath) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    final fullPath = p.join(workspacePath, relativePath);
    ref.read(editorProvider.notifier).openFile(fullPath);
  }

  @override
  Widget build(BuildContext context) {
    final gitState = ref.watch(gitProvider);
    final notifier = ref.read(gitProvider.notifier);
    final c = GitThemeColors.resolve(context, ref);

    return ColoredBox(
      color: c.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopToolbar(gitState, notifier, c),
          if (gitState.isLoading) ...[
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: c.accent,
            ),
            _buildOperationProgressBanner(gitState.currentOperation, c),
          ],
          if (gitState.error != null)
            _buildBanner(
              message: gitState.error!,
              color: c.danger,
              icon: LucideIcons.circle_alert,
              onClose: () => notifier.refreshStatus(silent: true),
              action: (gitState.status != null &&
                      (gitState.error!.contains('remote') ||
                          gitState.error!.contains('Authentication') ||
                          gitState.error!.contains('fatal:') ||
                          gitState.error!.contains('token') ||
                          gitState.error!.contains('denied') ||
                          gitState.error!.contains('failed to push')))
                  ? InkWell(
                      onTap: () =>
                          _showGitSettingsDialog(gitState.status!, notifier),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.danger.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: c.danger.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.key_round,
                              size: 10,
                              color: c.foreground,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Токен / Remote',
                              style: TextStyle(
                                fontSize: 10,
                                color: c.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
          if (gitState.lastActionMessage != null && gitState.error == null)
            _buildBanner(
              message: gitState.lastActionMessage!,
              color: c.success,
              icon: LucideIcons.circle_check,
              onClose: () => notifier.refreshStatus(silent: true),
            ),
          if (gitState.status != null) _buildTabBar(gitState.status!, c),
          Expanded(
            child: gitState.status == null && !gitState.isLoading
                ? _buildNoRepoView(notifier, c)
                : gitState.status == null
                    ? Center(
                        child: CircularProgressIndicator(
                          color: c.accent,
                          strokeWidth: 2.2,
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildChangesTab(gitState.status!, notifier, c),
                          _buildHistoryTab(gitState.status!, notifier, c),
                          _buildBranchesAndStashTab(
                            gitState.status!,
                            notifier,
                            c,
                          ),
                          _buildReleasesAndRemoteTab(
                            gitState.status!,
                            notifier,
                            c,
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationProgressBanner(
    String? operationText,
    GitThemeColors c,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: c.accent.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              operationText ?? 'Выполняется операция Git...',
              style: TextStyle(
                color: c.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner({
    required String message,
    required Color color,
    required IconData icon,
    required VoidCallback onClose,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 6),
            action,
          ],
          const SizedBox(width: 6),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(4),
            child: Icon(
              LucideIcons.x,
              size: 13,
              color: color.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar(
    GitState gitState,
    GitNotifier notifier,
    GitThemeColors c,
  ) {
    final status = gitState.status;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Active Branch Selector + Sync Badge / Remote + Compact Actions
          Row(
            children: [
              if (status != null)
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: () => _showBranchPickerModal(status, notifier),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: c.accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: c.accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.git_branch,
                                  size: 12,
                                  color: c.accent,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    status.currentBranch,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11.5,
                                      color: c.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  LucideIcons.chevron_down,
                                  size: 12,
                                  color: c.accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (status.ahead > 0 || status.behind > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.warning.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                              color: c.warning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            [
                              if (status.behind > 0) '↓${status.behind}',
                              if (status.ahead > 0) '↑${status.ahead}',
                            ].join(' '),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5,
                              color: c.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: InkWell(
                          onTap: () => _showGitSettingsDialog(status, notifier),
                          borderRadius: BorderRadius.circular(7),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4.5,
                            ),
                            decoration: BoxDecoration(
                              color: status.remoteUrl != null
                                  ? c.card
                                  : c.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: status.remoteUrl != null
                                    ? c.hairline
                                    : c.accent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  status.remoteUrl != null
                                      ? LucideIcons.cloud
                                      : LucideIcons.cloud_upload,
                                  size: 11,
                                  color: status.remoteUrl != null
                                      ? c.success
                                      : c.accent,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    status.remoteUrl != null
                                        ? _shortRemoteName(status.remoteUrl!)
                                        : 'Подключить GitHub',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: status.remoteUrl != null
                                          ? c.mutedForeground
                                          : c.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'GIT И КОНТРОЛЬ ВЕРСИЙ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.foreground,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              if (status != null)
                _buildToolbarIconButton(
                  icon: LucideIcons.git_branch_plus,
                  tooltip: 'Создать новую ветку',
                  color: c.mutedForeground,
                  onTap: () => _showCreateBranchDialog(notifier),
                ),
              if (status != null)
                _buildToolbarIconButton(
                  icon: LucideIcons.git_graph,
                  tooltip: 'Открыть граф коммитов и веток',
                  color: c.accent,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GitGraphPage()),
                    );
                  },
                ),
              _buildToolbarIconButton(
                icon: LucideIcons.refresh_cw,
                tooltip: 'Обновить статус Git',
                color: c.mutedForeground,
                onTap: () => notifier.refreshStatus(force: true),
              ),
              if (status != null)
                PopupMenuButton<String>(
                  tooltip: 'Дополнительные команды Git',
                  color: c.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: c.border),
                  ),
                  icon: Icon(
                    LucideIcons.ellipsis_vertical,
                    size: 16,
                    color: c.mutedForeground,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'stash':
                        _showQuickStashDialog(status, notifier);
                      case 'download':
                        final wsPath = ref.read(workspaceProvider).currentPath;
                        if (wsPath != null) {
                          GitDownloadDialog.show(
                            context,
                            workspacePath: wsPath,
                            gitNotifier: notifier,
                          );
                        }
                      case 'pull_rebase':
                        notifier.pull(rebase: true);
                      case 'force_push':
                        _confirmForcePush(notifier);
                      case 'settings':
                        _showGitSettingsDialog(status, notifier);
                      case 'guide':
                        _showGitGuideModal();
                    }
                  },
                  itemBuilder: (ctx) => [
                    _buildMenuEntry(
                      'stash',
                      LucideIcons.archive,
                      'Спрятать в Stash',
                      c,
                    ),
                    _buildMenuEntry(
                      'download',
                      LucideIcons.cloud_download,
                      'Скачать из GitHub',
                      c,
                    ),
                    const PopupMenuDivider(height: 8),
                    _buildMenuEntry(
                      'pull_rebase',
                      LucideIcons.git_pull_request_arrow,
                      'Pull --rebase',
                      c,
                    ),
                    _buildMenuEntry(
                      'force_push',
                      LucideIcons.shield_alert,
                      'Force Push (--force-with-lease)',
                      c,
                      color: c.warning,
                    ),
                    const PopupMenuDivider(height: 8),
                    _buildMenuEntry(
                      'settings',
                      LucideIcons.sliders_horizontal,
                      'Настройки Git / Токен',
                      c,
                    ),
                    _buildMenuEntry(
                      'guide',
                      LucideIcons.book_open,
                      'Шпаргалка по Git',
                      c,
                    ),
                  ],
                ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            // Row 2: Crisp, full-width segmented remote sync strip (never overflows)
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.inputFill,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.hairline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionStripButton(
                      c: c,
                      icon: LucideIcons.refresh_cw,
                      label: 'Sync',
                      tooltip: 'Pull + Push в одно действие',
                      highlight: status.ahead > 0 || status.behind > 0,
                      onTap: () => notifier.sync(),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: _buildActionStripButton(
                      c: c,
                      icon: LucideIcons.refresh_ccw_dot,
                      label: 'Fetch',
                      tooltip: 'Проверить обновления на сервере (git fetch)',
                      onTap: () => notifier.fetch(),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: _buildActionStripButton(
                      c: c,
                      icon: LucideIcons.arrow_down_to_line,
                      label:
                          status.behind > 0 ? 'Pull (${status.behind})' : 'Pull',
                      tooltip:
                          'Скачать изменения (долгое нажатие — Pull --rebase)',
                      accentColor: status.behind > 0 ? c.warning : null,
                      highlight: status.behind > 0,
                      onTap: () => notifier.pull(),
                      onLongPress: () => notifier.pull(rebase: true),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: _buildActionStripButton(
                      c: c,
                      icon: LucideIcons.arrow_up_from_line,
                      label:
                          status.ahead > 0 ? 'Push (${status.ahead})' : 'Push',
                      tooltip:
                          'Отправить коммиты (долгое нажатие — Force Push)',
                      highlight: status.ahead > 0,
                      onTap: () => notifier.push(),
                      onLongPress: () => _confirmForcePush(notifier),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Tooltip(
                    message: 'Спрятать изменения в Stash',
                    child: InkWell(
                      onTap: () => _showQuickStashDialog(status, notifier),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: status.stashes.isNotEmpty
                              ? c.warning.withValues(alpha: 0.14)
                              : c.card.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.archive,
                              size: 12,
                              color: status.stashes.isNotEmpty
                                  ? c.warning
                                  : c.mutedForeground,
                            ),
                            if (status.stashes.isNotEmpty) ...[
                              const SizedBox(width: 3),
                              Text(
                                '${status.stashes.length}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.warning,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbarIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuEntry(
    String value,
    IconData icon,
    String title,
    GitThemeColors c, {
    Color? color,
  }) {
    final fg = color ?? c.foreground;
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStripButton({
    required GitThemeColors c,
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool highlight = false,
    Color? accentColor,
  }) {
    final tint = accentColor ?? c.accent;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: highlight
                ? tint.withValues(alpha: 0.16)
                : c.card.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(6),
            border: highlight
                ? Border.all(color: tint.withValues(alpha: 0.4), width: 0.8)
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: highlight ? tint : c.mutedForeground,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
                    color: highlight ? tint : c.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _shortRemoteName(String url) {
    var clean = url.trim();
    if (clean.endsWith('.git')) {
      clean = clean.substring(0, clean.length - 4);
    }
    final ghIdx = clean.indexOf('github.com/');
    if (ghIdx != -1) {
      return clean.substring(ghIdx + 'github.com/'.length);
    }
    final parts = clean.split('/');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}/${parts.last}';
    }
    return clean;
  }

  Widget _buildTabBar(GitStatus status, GitThemeColors c) {
    final changesCount = status.totalChangesCount;
    final commitsCount = status.recentCommits.length;
    final branchesCount = status.branches.length;

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorColor: c.accent,
        indicatorWeight: 2.5,
        labelColor: c.accent,
        unselectedLabelColor: c.mutedForeground,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.file_diff, size: 13),
                const SizedBox(width: 5),
                const Text('Изменения'),
                if (changesCount > 0) ...[
                  const SizedBox(width: 5),
                  _buildCountPill(changesCount.toString(), c.accent),
                ],
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.history, size: 13),
                const SizedBox(width: 5),
                const Text('История'),
                if (commitsCount > 0) ...[
                  const SizedBox(width: 5),
                  _buildCountPill(commitsCount.toString(), c.mutedForeground),
                ],
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.git_branch, size: 13),
                const SizedBox(width: 5),
                const Text('Ветки'),
                const SizedBox(width: 5),
                _buildCountPill(branchesCount.toString(), c.mutedForeground),
              ],
            ),
          ),
          Tab(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.rocket, size: 13),
                const SizedBox(width: 5),
                const Text('Релизы'),
                if (status.tags.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  _buildCountPill(
                    status.tags.length.toString(),
                    c.mutedForeground,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: ИЗМЕНЕНИЯ (STAGING, WORKING TREE & COMMIT COMPOSER)
  // ===========================================================================

  Widget _buildChangesTab(
    GitStatus status,
    GitNotifier notifier,
    GitThemeColors c,
  ) {
    final filteredConflicts = status.conflictedFiles
        .where((f) => _fileFilter.isEmpty || f.toLowerCase().contains(_fileFilter))
        .toList();
    final filteredStaged = status.stagedFiles
        .where((f) => _fileFilter.isEmpty || f.toLowerCase().contains(_fileFilter))
        .toList();
    final modifiedSet = status.modifiedFiles.toSet();
    final untrackedSet = status.untrackedFiles.toSet();
    final workingFiles = <String>[
      ...status.modifiedFiles,
      ...status.untrackedFiles.where((u) => !modifiedSet.contains(u)),
    ].where((f) => _fileFilter.isEmpty || f.toLowerCase().contains(_fileFilter)).toList();

    return Column(
      children: [
        // Commit Composer Card
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Conventional Commit Quick Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final prefix in _conventionalPrefixes)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: InkWell(
                          onTap: () => _applyPrefix(prefix),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _commitController.text.startsWith(prefix)
                                  ? c.accent.withValues(alpha: 0.16)
                                  : c.inputFill,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _commitController.text.startsWith(prefix)
                                    ? c.accent.withValues(alpha: 0.65)
                                    : c.hairline,
                              ),
                            ),
                            child: Text(
                              prefix.trim(),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10.5,
                                color: _commitController.text.startsWith(prefix)
                                    ? c.accent
                                    : c.mutedForeground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Commit Message Input + Integrated AI Button
              Stack(
                alignment: Alignment.topRight,
                children: [
                  TextField(
                    controller: _commitController,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(fontSize: 12.5, color: c.foreground),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: status.stagedFiles.isNotEmpty
                          ? 'Сообщение коммита (${status.stagedFiles.length} в индексе)...'
                          : 'Сообщение коммита (или оставьте автоописание)...',
                      hintStyle: TextStyle(
                        color: c.subtleForeground,
                        fontSize: 11.5,
                      ),
                      filled: true,
                      fillColor: c.inputFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.accent, width: 1.2),
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(10, 9, 54, 9),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 5, right: 5),
                    child: Tooltip(
                      message: 'Сгенерировать сообщение коммита по изменениям',
                      child: InkWell(
                        onTap: _isGeneratingCommitMessage
                            ? null
                            : _generateSmartCommitMessage,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: c.accent.withValues(alpha: 0.35),
                            ),
                          ),
                          child: _isGeneratingCommitMessage
                              ? SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: c.accent,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.sparkles,
                                      size: 11,
                                      color: c.accent,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'AI',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: c.accent,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Amend toggle + Balanced Primary Commit & Tonal Push Buttons
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _amendCommit = !_amendCommit;
                        if (_amendCommit &&
                            _commitController.text.trim().isEmpty &&
                            status.recentCommits.isNotEmpty) {
                          _commitController.text =
                              status.recentCommits.first.message;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _amendCommit
                            ? c.accent.withValues(alpha: 0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _amendCommit
                              ? c.accent.withValues(alpha: 0.45)
                              : c.hairline,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _amendCommit
                                ? LucideIcons.square_check
                                : LucideIcons.square,
                            size: 12.5,
                            color: _amendCommit ? c.accent : c.mutedForeground,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Amend',
                            style: TextStyle(
                              fontSize: 10.5,
                              color:
                                  _amendCommit ? c.accent : c.mutedForeground,
                              fontWeight: _amendCommit
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 33,
                      child: ElevatedButton.icon(
                        onPressed: (status.hasChanges || _amendCommit)
                            ? () async {
                                final msg = _commitController.text
                                        .trim()
                                        .isNotEmpty
                                    ? _commitController.text.trim()
                                    : 'chore: update (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';
                                final ok = await notifier.commit(
                                  msg,
                                  amend: _amendCommit,
                                );
                                if (ok && mounted) {
                                  _commitController.clear();
                                  setState(() => _amendCommit = false);
                                }
                              }
                            : null,
                        icon: const Icon(LucideIcons.check, size: 13.5),
                        label: Text(
                          status.stagedFiles.isNotEmpty
                              ? 'Коммит (${status.stagedFiles.length})'
                              : 'Коммит все (${status.totalChangesCount})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.accentForeground,
                          disabledBackgroundColor: c.inputFill,
                          disabledForegroundColor: c.subtleForeground,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 33,
                      child: OutlinedButton.icon(
                        onPressed: (status.hasChanges || status.ahead > 0)
                            ? () async {
                                if (status.hasChanges) {
                                  final msg = _commitController.text
                                          .trim()
                                          .isNotEmpty
                                      ? _commitController.text.trim()
                                      : 'chore: sync (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';
                                  final ok = await notifier.commitAndPush(
                                    msg,
                                    amend: _amendCommit,
                                  );
                                  if (ok && mounted) {
                                    _commitController.clear();
                                    setState(() => _amendCommit = false);
                                  }
                                } else {
                                  await notifier.push();
                                }
                              }
                            : null,
                        icon: const Icon(LucideIcons.cloud_upload, size: 13.5),
                        label: Text(
                          status.ahead > 0
                              ? 'Push (${status.ahead})'
                              : 'Коммит + Push',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.accent,
                          backgroundColor: c.accent.withValues(alpha: 0.12),
                          disabledForegroundColor: c.subtleForeground,
                          side: BorderSide(
                            color: (status.hasChanges || status.ahead > 0)
                                ? c.accent.withValues(alpha: 0.45)
                                : c.hairline,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // File Filter Bar (if > 4 files)
        if (status.totalChangesCount > 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _fileFilterController,
                style: TextStyle(fontSize: 11.5, color: c.foreground),
                decoration: InputDecoration(
                  hintText: 'Фильтр изменённых файлов...',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: c.subtleForeground,
                  ),
                  prefixIcon: Icon(
                    LucideIcons.search,
                    size: 13.5,
                    color: c.mutedForeground,
                  ),
                  suffixIcon: _fileFilter.isNotEmpty
                      ? InkWell(
                          onTap: () => _fileFilterController.clear(),
                          child: Icon(
                            LucideIcons.x,
                            size: 13,
                            color: c.mutedForeground,
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: c.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.hairline),
                  ),
                ),
              ),
            ),
          ),

        // Changed Files Sections
        Expanded(
          child: !status.hasChanges
              ? _buildCleanWorkingTreeView(status, notifier, c)
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    // 1. CONFLICTS SECTION
                    if (filteredConflicts.isNotEmpty) ...[
                      _buildCollapsibleHeader(
                        c: c,
                        title: 'КОНФЛИКТЫ СЛИЯНИЯ (${filteredConflicts.length})',
                        color: c.danger,
                        expanded: _conflictsExpanded,
                        onToggle: () => setState(
                          () => _conflictsExpanded = !_conflictsExpanded,
                        ),
                      ),
                      if (_conflictsExpanded)
                        ...filteredConflicts.map(
                          (f) => _buildFileRow(
                            c: c,
                            file: f,
                            statusCode: 'U',
                            badgeColor: c.danger,
                            stats: status.diffStats[f],
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GitMergeConflictPage(
                                    relativePath: f,
                                  ),
                                ),
                              );
                            },
                            actions: [
                              _buildMiniIconBtn(
                                icon: LucideIcons.wrench,
                                color: c.warning,
                                tooltip: 'Разрешить конфликт',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => GitMergeConflictPage(
                                        relativePath: f,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              _buildMiniIconBtn(
                                icon: LucideIcons.check,
                                color: c.success,
                                tooltip: 'Отметить решённым (git add)',
                                onTap: () => notifier.stageFile(f),
                              ),
                            ],
                          ),
                        ),
                    ],

                    // 2. STAGED CHANGES
                    _buildCollapsibleHeader(
                      c: c,
                      title: 'В ИНДЕКСЕ (${filteredStaged.length})',
                      color: c.success,
                      expanded: _stagedExpanded,
                      onToggle: () => setState(
                        () => _stagedExpanded = !_stagedExpanded,
                      ),
                      trailing: filteredStaged.isNotEmpty
                          ? InkWell(
                              onTap: () => notifier.unstageAll(),
                              borderRadius: BorderRadius.circular(5),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.minus,
                                      size: 11,
                                      color: c.warning,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Снять все',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: c.warning,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : null,
                    ),
                    if (_stagedExpanded)
                      if (filteredStaged.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 5, 14, 8),
                          child: Text(
                            'Индекс пуст — отметьте файлы «+» ниже или нажмите «Коммит все».',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: c.subtleForeground,
                            ),
                          ),
                        )
                      else
                        ...filteredStaged.map(
                          (f) => _buildFileRow(
                            c: c,
                            file: f,
                            statusCode: status.fileStatusCodes[f] ?? 'A',
                            badgeColor: c.success,
                            stats: status.diffStats[f],
                            onTap: () => _openFileDiff(f, isStaged: true),
                            onLongPress: () => _showFileContextMenu(
                              file: f,
                              isStaged: true,
                              notifier: notifier,
                              status: status,
                            ),
                            actions: [
                              _buildMiniIconBtn(
                                icon: LucideIcons.file_code,
                                color: c.mutedForeground,
                                tooltip: 'Открыть файл в редакторе',
                                onTap: () => _openFileInEditor(f),
                              ),
                              _buildMiniIconBtn(
                                icon: LucideIcons.minus,
                                color: c.warning,
                                tooltip: 'Убрать из индекса (Unstage)',
                                onTap: () => notifier.unstageFile(f),
                              ),
                            ],
                          ),
                        ),

                    // 3. WORKING TREE CHANGES
                    _buildCollapsibleHeader(
                      c: c,
                      title: 'ИЗМЕНЕНИЯ (${workingFiles.length})',
                      color: c.warning,
                      expanded: _workingExpanded,
                      onToggle: () => setState(
                        () => _workingExpanded = !_workingExpanded,
                      ),
                      trailing: workingFiles.isNotEmpty
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Откатить все изменения',
                                  child: InkWell(
                                    onTap: () => _confirmDiscardAll(notifier),
                                    borderRadius: BorderRadius.circular(5),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      child: Icon(
                                        LucideIcons.trash_2,
                                        size: 12.5,
                                        color: c.danger,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => notifier.stageAll(),
                                  borderRadius: BorderRadius.circular(5),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.plus,
                                          size: 11.5,
                                          color: c.accent,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'В индекс все',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: c.accent,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                    if (_workingExpanded) ...[
                      ...workingFiles.take(150).map((f) {
                        final isUntracked = untrackedSet.contains(f);
                        final code = isUntracked
                            ? 'U'
                            : (status.fileStatusCodes[f] ?? 'M');
                        final color = isUntracked ? c.accent : c.warning;
                        return _buildFileRow(
                          c: c,
                          file: f,
                          statusCode: code,
                          badgeColor: color,
                          stats: status.diffStats[f],
                          onTap: () => _openFileDiff(f, isStaged: false),
                          onLongPress: () => _showFileContextMenu(
                            file: f,
                            isStaged: false,
                            notifier: notifier,
                            status: status,
                          ),
                          actions: [
                            _buildMiniIconBtn(
                              icon: LucideIcons.eye_off,
                              color: c.subtleForeground,
                              tooltip: 'Добавить в .gitignore',
                              onTap: () => notifier.addToGitignore(f),
                            ),
                            _buildMiniIconBtn(
                              icon: LucideIcons.undo_2,
                              color: c.danger.withValues(alpha: 0.85),
                              tooltip: 'Откатить изменения в файле (Discard)',
                              onTap: () => _confirmDiscardFile(f, notifier),
                            ),
                            _buildMiniIconBtn(
                              icon: LucideIcons.plus,
                              color: c.accent,
                              tooltip: 'Добавить в индекс (Stage)',
                              onTap: () => notifier.stageFile(f),
                            ),
                          ],
                        );
                      }),
                      if (workingFiles.length > 150)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          child: Text(
                            'Показано 150 из ${workingFiles.length} файлов. Добавьте build/ и .dart_tool/ в .gitignore',
                            style: TextStyle(fontSize: 11, color: c.warning),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCleanWorkingTreeView(
    GitStatus status,
    GitNotifier notifier,
    GitThemeColors c,
  ) {
    final latestCommit =
        status.recentCommits.isNotEmpty ? status.recentCommits.first : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.success.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.check_check,
                  size: 26,
                  color: c.success,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Рабочая копия чиста',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'На ветке «${status.currentBranch}» нет незакоммиченных правок.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mutedForeground, fontSize: 11.5),
              ),
              if (latestCommit != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: c.inputFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.hairline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          latestCommit.shortHash,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: c.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          latestCommit.message,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.foreground,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (status.ahead > 0)
                    ElevatedButton.icon(
                      onPressed: () => notifier.push(),
                      icon: const Icon(LucideIcons.cloud_upload, size: 14),
                      label: Text('Отправить ${status.ahead} коммит(ов)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: c.accentForeground,
                        elevation: 0,
                      ),
                    ),
                  if (status.behind > 0)
                    ElevatedButton.icon(
                      onPressed: () => notifier.pull(),
                      icon: const Icon(LucideIcons.cloud_download, size: 14),
                      label: Text('Скачать ${status.behind} коммит(ов)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.warning,
                        foregroundColor: GitThemeColors.contrastOn(c.warning),
                        elevation: 0,
                      ),
                    ),
                  if (status.stashes.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => notifier.stashPop(),
                      icon: Icon(
                        LucideIcons.archive_restore,
                        size: 14,
                        color: c.warning,
                      ),
                      label: Text(
                        'Вернуть Stash (${status.stashes.length})',
                        style: TextStyle(color: c.warning, fontSize: 11.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.warning.withValues(alpha: 0.45)),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _showCreateBranchDialog(notifier),
                    icon: Icon(
                      LucideIcons.git_branch_plus,
                      size: 13.5,
                      color: c.accent,
                    ),
                    label: Text(
                      'Новая ветка',
                      style: TextStyle(color: c.accent, fontSize: 11.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.border),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsibleHeader({
    required GitThemeColors c,
    required String title,
    required Color color,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.panel.withValues(alpha: 0.72),
          border: Border(
            top: BorderSide(color: c.hairline, width: 0.6),
            bottom: BorderSide(color: c.hairline, width: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              expanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: c.mutedForeground,
                  letterSpacing: 0.55,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  void _showFileContextMenu({
    required String file,
    required bool isStaged,
    required GitNotifier notifier,
    required GitStatus status,
  }) {
    final c = GitThemeColors.resolve(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(LucideIcons.file_code, size: 16, color: c.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: c.foreground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: c.hairline, height: 1),
              ListTile(
                dense: true,
                leading: Icon(LucideIcons.eye, color: c.accent, size: 18),
                title: Text(
                  'Просмотреть изменения (Diff)',
                  style: TextStyle(color: c.foreground, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFileDiff(file, isStaged: isStaged);
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(
                  LucideIcons.pencil,
                  color: c.mutedForeground,
                  size: 18,
                ),
                title: Text(
                  'Открыть в редакторе кода',
                  style: TextStyle(color: c.foreground, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFileInEditor(file);
                },
              ),
              if (isStaged)
                ListTile(
                  dense: true,
                  leading: Icon(
                    LucideIcons.circle_minus,
                    color: c.warning,
                    size: 18,
                  ),
                  title: Text(
                    'Убрать из индекса (Unstage)',
                    style: TextStyle(color: c.foreground, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.unstageFile(file);
                  },
                )
              else
                ListTile(
                  dense: true,
                  leading: Icon(
                    LucideIcons.circle_plus,
                    color: c.accent,
                    size: 18,
                  ),
                  title: Text(
                    'Добавить в индекс (Stage)',
                    style: TextStyle(color: c.foreground, fontSize: 13),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.stageFile(file);
                  },
                ),
              ListTile(
                dense: true,
                leading: Icon(LucideIcons.undo_2, color: c.danger, size: 18),
                title: Text(
                  'Откатить изменения (Discard)',
                  style: TextStyle(color: c.danger, fontSize: 13),
                ),
                subtitle: Text(
                  'Сбросить файл к состоянию последнего коммита',
                  style: TextStyle(color: c.subtleForeground, fontSize: 10.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDiscardFile(file, notifier);
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(
                  LucideIcons.eye_off,
                  color: c.mutedForeground,
                  size: 18,
                ),
                title: Text(
                  'Добавить в .gitignore',
                  style: TextStyle(color: c.mutedForeground, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.addToGitignore(file);
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(
                  LucideIcons.copy,
                  color: c.mutedForeground,
                  size: 18,
                ),
                title: Text(
                  'Скопировать относительный путь',
                  style: TextStyle(color: c.mutedForeground, fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: file));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Путь скопирован: $file'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileRow({
    required GitThemeColors c,
    required String file,
    required String statusCode,
    required Color badgeColor,
    required GitFileDiffStats? stats,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required List<Widget> actions,
  }) {
    final fileName = p.basename(file);
    final dirName = p.dirname(file);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: c.hairline.withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
              ),
              child: Text(
                statusCode,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: c.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dirName != '.')
                    Text(
                      dirName,
                      style: TextStyle(
                        fontSize: 10,
                        color: c.subtleForeground,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (stats != null &&
                (stats.additions > 0 || stats.deletions > 0)) ...[
              if (stats.additions > 0)
                Text(
                  '+${stats.additions}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: c.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (stats.additions > 0 && stats.deletions > 0)
                const SizedBox(width: 4),
              if (stats.deletions > 0)
                Text(
                  '-${stats.deletions}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: c.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(width: 6),
            ],
            ...actions,
          ],
        ),
      ),
    );
  }

  Widget _buildMiniIconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Icon(icon, size: 13.5, color: color),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: ИСТОРИЯ КОММИТОВ (COMMIT LOG & INTERACTIVE INSPECTOR)
  // ===========================================================================

  Widget _buildHistoryTab(
    GitStatus status,
    GitNotifier notifier,
    GitThemeColors c,
  ) {
    final commits = status.recentCommits.where((item) {
      if (_commitFilter.isEmpty) return true;
      return item.message.toLowerCase().contains(_commitFilter) ||
          item.shortHash.toLowerCase().contains(_commitFilter) ||
          item.author.toLowerCase().contains(_commitFilter) ||
          item.refs.toLowerCase().contains(_commitFilter);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _commitSearchController,
                    style: TextStyle(fontSize: 11.5, color: c.foreground),
                    decoration: InputDecoration(
                      hintText: 'Поиск по коммитам, SHA, автору, тегам...',
                      hintStyle: TextStyle(
                        fontSize: 11.5,
                        color: c.subtleForeground,
                      ),
                      prefixIcon: Icon(
                        LucideIcons.search,
                        size: 13.5,
                        color: c.mutedForeground,
                      ),
                      suffixIcon: _commitFilter.isNotEmpty
                          ? InkWell(
                              onTap: () => _commitSearchController.clear(),
                              child: Icon(
                                LucideIcons.x,
                                size: 13,
                                color: c.mutedForeground,
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: c.card,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.hairline),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GitGraphPage()),
                    );
                  },
                  icon: Icon(
                    LucideIcons.git_graph,
                    size: 13.5,
                    color: c.accent,
                  ),
                  label: Text(
                    'Граф',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: c.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: c.accent.withValues(alpha: 0.1),
                    side: BorderSide(color: c.accent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: commits.isEmpty
              ? Center(
                  child: Text(
                    'Коммиты не найдены',
                    style: TextStyle(color: c.mutedForeground, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: commits.length,
                  itemBuilder: (context, index) {
                    final entry = commits[index];
                    final isHead = index == 0 && _commitFilter.isEmpty;
                    final nodeColor =
                        isHead ? c.accent : c.accentSecondary;

                    return InkWell(
                      onTap: () => _showCommitInspectorSheet(entry, notifier),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: c.hairline.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: nodeColor,
                                  border: isHead
                                      ? Border.all(
                                          color: c.accent.withValues(alpha: 0.35),
                                          width: 3,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              c.accent.withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          entry.shortHash,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10.5,
                                            color: c.accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (entry.refs.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.warning
                                                  .withValues(alpha: 0.14),
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                              border: Border.all(
                                                color: c.warning
                                                    .withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Text(
                                              entry.refs,
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                color: c.warning,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        entry.relativeTime,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: c.subtleForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    entry.message,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: c.foreground,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.author,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: c.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCommitInspectorSheet(GitCommitEntry commit, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    List<GitCommitFileEntry>? changedFiles;
    String? patchDiff;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            if (changedFiles == null) {
              notifier.getCommitFiles(commit.hash).then((files) {
                if (modalCtx.mounted) setModalState(() => changedFiles = files);
              });
              notifier.getCommitDetails(commit.hash).then((diff) {
                if (modalCtx.mounted) setModalState(() => patchDiff = diff);
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: c.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              commit.shortHash,
                              style: GoogleFonts.jetBrainsMono(
                                color: c.accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${commit.author} • ${commit.relativeTime}',
                              style: TextStyle(
                                color: c.mutedForeground,
                                fontSize: 11.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              LucideIcons.copy,
                              size: 15,
                              color: c.mutedForeground,
                            ),
                            tooltip: 'Скопировать полный SHA',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: commit.hash),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('SHA скопирован в буфер обмена'),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              LucideIcons.x,
                              size: 16,
                              color: c.mutedForeground,
                            ),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        commit.message,
                        style: TextStyle(
                          color: c.foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Interactive Operations Row
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildModalActionBtn(
                            icon: LucideIcons.git_pull_request_create,
                            label: 'Cherry-pick',
                            color: c.accentSecondary,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              notifier.cherryPickCommit(commit.hash);
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.undo_2,
                            label: 'Revert (обратить)',
                            color: c.warning,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              notifier.revertCommit(commit.hash);
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.git_branch_plus,
                            label: 'Ветка отсюда',
                            color: c.accent,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showCreateBranchDialog(
                                notifier,
                                fromRef: commit.shortHash,
                              );
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.tag,
                            label: 'Тег на коммит',
                            color: c.success,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showCreateTagDialog(
                                notifier,
                                commitHash: commit.hash,
                              );
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.rotate_ccw,
                            label: 'Reset к коммиту...',
                            color: c.danger,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showResetCommitDialog(commit, notifier);
                            },
                          ),
                        ],
                      ),
                      Divider(color: c.hairline, height: 20),

                      // Changed files list & patch
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          children: [
                            Text(
                              'ЗАТРОНУТЫЕ ФАЙЛЫ (${changedFiles?.length ?? 0})',
                              style: TextStyle(
                                color: c.subtleForeground,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (changedFiles == null)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: LinearProgressIndicator(color: c.accent),
                              )
                            else
                              ...changedFiles!.map(
                                (f) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 19,
                                        height: 19,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: c.inputFill,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(color: c.hairline),
                                        ),
                                        child: Text(
                                          f.status,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: f.status == 'A'
                                                ? c.success
                                                : f.status == 'D'
                                                    ? c.danger
                                                    : c.warning,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          f.path,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            color: c.foreground,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            Text(
                              'ПОЛНЫЙ DIFF КОММИТА',
                              style: TextStyle(
                                color: c.subtleForeground,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.inputFill,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.hairline),
                              ),
                              child: SelectableText(
                                patchDiff ?? 'Загрузка diff...',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  color: c.foreground.withValues(alpha: 0.85),
                                  height: 1.38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildModalActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 3: ВЕТКИ И STASH (BRANCHES & STASH MANAGER)
  // ===========================================================================

  Widget _buildBranchesAndStashTab(
    GitStatus status,
    GitNotifier notifier,
    GitThemeColors c,
  ) {
    final localBranches = status.branches
        .where(
          (b) => _branchFilter.isEmpty || b.toLowerCase().contains(_branchFilter),
        )
        .toList();
    final remoteBranches = status.remoteBranches
        .where(
          (b) => _branchFilter.isEmpty || b.toLowerCase().contains(_branchFilter),
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Branch Search + Create Bar
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _branchFilterController,
                  style: TextStyle(fontSize: 11.5, color: c.foreground),
                  decoration: InputDecoration(
                    hintText: 'Поиск по веткам...',
                    hintStyle: TextStyle(
                      fontSize: 11.5,
                      color: c.subtleForeground,
                    ),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 13.5,
                      color: c.mutedForeground,
                    ),
                    suffixIcon: _branchFilter.isNotEmpty
                        ? InkWell(
                            onTap: () => _branchFilterController.clear(),
                            child: Icon(
                              LucideIcons.x,
                              size: 13,
                              color: c.mutedForeground,
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: c.card,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.hairline),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: () => _showCreateBranchDialog(notifier),
                icon: const Icon(LucideIcons.git_branch_plus, size: 13.5),
                label: const Text(
                  'Новая',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.accentForeground,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Current Active Branch Overview Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.accent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      LucideIcons.git_branch,
                      size: 14,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                status.currentBranch,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.foreground,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: c.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'HEAD',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status.remoteUrl != null
                              ? 'origin: ${_shortRemoteName(status.remoteUrl!)}'
                              : 'Удалённый репозиторий не подключён',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: c.mutedForeground,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildMiniIconBtn(
                    icon: LucideIcons.pencil,
                    color: c.mutedForeground,
                    tooltip: 'Переименовать текущую ветку',
                    onTap: () =>
                        _showRenameBranchDialog(status.currentBranch, notifier),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildModalActionBtn(
                    icon: LucideIcons.arrow_up_from_line,
                    label: status.ahead > 0
                        ? 'Отправить (${status.ahead})'
                        : 'Отправить ветку',
                    color: c.accent,
                    onTap: () => notifier.push(),
                  ),
                  _buildModalActionBtn(
                    icon: LucideIcons.git_graph,
                    label: 'Дерево веток',
                    color: c.mutedForeground,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GitGraphPage()),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 1. LOCAL BRANCHES
        InkWell(
          onTap: () => setState(
            () => _localBranchesExpanded = !_localBranchesExpanded,
          ),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _localBranchesExpanded
                      ? LucideIcons.chevron_down
                      : LucideIcons.chevron_right,
                  size: 13,
                  color: c.accent,
                ),
                const SizedBox(width: 4),
                Text(
                  'ЛОКАЛЬНЫЕ ВЕТКИ (${localBranches.length})',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: c.mutedForeground,
                    letterSpacing: 0.65,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_localBranchesExpanded) ...[
          const SizedBox(height: 4),
          if (localBranches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ветки не найдены',
                style: TextStyle(fontSize: 11, color: c.subtleForeground),
              ),
            )
          else
            ...localBranches.map((b) {
              final isCurrent = b == status.currentBranch;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? c.accent.withValues(alpha: 0.1)
                      : c.card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isCurrent
                        ? c.accent.withValues(alpha: 0.45)
                        : c.hairline,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCurrent
                          ? LucideIcons.circle_check
                          : LucideIcons.git_branch,
                      size: 14,
                      color: isCurrent ? c.accent : c.mutedForeground,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: InkWell(
                        onTap:
                            isCurrent ? null : () => notifier.checkoutBranch(b),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                color: isCurrent ? c.accent : c.foreground,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              isCurrent
                                  ? 'Текущая ветка (HEAD)'
                                  : 'Нажмите для переключения',
                              style: TextStyle(
                                fontSize: 10,
                                color: c.subtleForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isCurrent) ...[
                      InkWell(
                        onTap: () => notifier.checkoutBranch(b),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Переключить',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: c.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildMiniIconBtn(
                        icon: LucideIcons.git_merge,
                        color: c.accentSecondary,
                        tooltip:
                            'Влить $b в текущую ветку (${status.currentBranch})',
                        onTap: () => notifier.mergeBranch(b),
                      ),
                      _buildMiniIconBtn(
                        icon: LucideIcons.trash_2,
                        color: c.danger,
                        tooltip: 'Удалить ветку $b',
                        onTap: () => _confirmDeleteBranch(b, notifier),
                      ),
                    ] else
                      _buildMiniIconBtn(
                        icon: LucideIcons.pencil,
                        color: c.mutedForeground,
                        tooltip: 'Переименовать текущую ветку',
                        onTap: () => _showRenameBranchDialog(b, notifier),
                      ),
                  ],
                ),
              );
            }),
        ],

        // 2. REMOTE BRANCHES
        if (status.remoteBranches.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(
                    () => _remoteBranchesExpanded = !_remoteBranchesExpanded,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _remoteBranchesExpanded
                              ? LucideIcons.chevron_down
                              : LucideIcons.chevron_right,
                          size: 13,
                          color: c.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'УДАЛЁННЫЕ ВЕТКИ (${remoteBranches.length})',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: c.mutedForeground,
                            letterSpacing: 0.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () => notifier.fetch(),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Text(
                    'Fetch',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_remoteBranchesExpanded) ...[
            const SizedBox(height: 4),
            ...remoteBranches.map(
              (rb) => Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.cloud,
                      size: 13,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rb,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.5,
                          color: c.foreground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => notifier.checkoutBranch(rb),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Checkout',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: c.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],

        // 3. STASH MANAGER
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STASH / ХРАНИЛИЩЕ (${status.stashes.length})',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: c.warning,
                letterSpacing: 0.65,
              ),
            ),
            TextButton.icon(
              onPressed: status.hasChanges
                  ? () => _showQuickStashDialog(status, notifier)
                  : null,
              icon: Icon(
                LucideIcons.archive,
                size: 12,
                color: status.hasChanges ? c.warning : c.subtleForeground,
              ),
              label: Text(
                'Спрятать в Stash',
                style: TextStyle(
                  fontSize: 11,
                  color: status.hasChanges ? c.warning : c.subtleForeground,
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (status.stashes.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.hairline),
            ),
            child: Text(
              'Список Stash пуст. Временное хранилище позволяет отложить правки перед переключением ветки.',
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
          )
        else
          ...status.stashes.map(
            (st) => Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.warning.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: c.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          st.ref,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: c.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (st.branch.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          'на ${st.branch}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        st.relativeTime,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: c.subtleForeground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    st.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildModalActionBtn(
                        icon: LucideIcons.eye,
                        label: 'Diff',
                        color: c.mutedForeground,
                        onTap: () => _showStashDiffModal(st, notifier),
                      ),
                      const SizedBox(width: 6),
                      _buildModalActionBtn(
                        icon: LucideIcons.copy_check,
                        label: 'Apply',
                        color: c.accent,
                        onTap: () => notifier.stashApply(st.ref),
                      ),
                      const SizedBox(width: 6),
                      _buildModalActionBtn(
                        icon: LucideIcons.archive_restore,
                        label: 'Pop',
                        color: c.success,
                        onTap: () => notifier.stashPop(st.ref),
                      ),
                      const SizedBox(width: 6),
                      _buildModalActionBtn(
                        icon: LucideIcons.trash_2,
                        label: 'Drop',
                        color: c.danger,
                        onTap: () => notifier.stashDrop(st.ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // TAB 4: РЕЛИЗЫ, ТЕГИ И REMOTE ORIGIN
  // ===========================================================================

  Widget _buildReleasesAndRemoteTab(
    GitStatus status,
    GitNotifier notifier,
    GitThemeColors c,
  ) {
    final ghService = GitHubService();
    final ghUserLogin = ghService.currentUser?['login']?.toString();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Remote & Author Configuration Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.globe, size: 15, color: c.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Удалённый репозиторий (Origin)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.foreground,
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => _showGitSettingsDialog(status, notifier),
                    icon: Icon(LucideIcons.pencil, size: 12, color: c.accent),
                    label: Text(
                      'Изменить',
                      style: TextStyle(fontSize: 11, color: c.accent),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: c.inputFill,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: c.hairline),
                ),
                child: SelectableText(
                  status.remoteUrl ??
                      'Remote origin не задан. Нажмите «Изменить», чтобы подключить GitHub.',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: status.remoteUrl != null ? c.foreground : c.warning,
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(
                    LucideIcons.user,
                    size: 12.5,
                    color: c.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Автор: ${status.userName ?? "Quantum Developer"} <${status.userEmail ?? "dev@quantum-ide.local"}>',
                      style: TextStyle(fontSize: 11, color: c.mutedForeground),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    ghService.isAuthenticated
                        ? LucideIcons.shield_check
                        : LucideIcons.key_round,
                    size: 12.5,
                    color: ghService.isAuthenticated ? c.success : c.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ghService.isAuthenticated
                          ? 'GitHub подключён${ghUserLogin != null ? " (@$ghUserLogin)" : ""}'
                          : 'GitHub токен не подключён',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            ghService.isAuthenticated ? c.success : c.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!ghService.isAuthenticated)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const GitHubPage(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        'Войти',
                        style: TextStyle(fontSize: 11, color: c.accent),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Cloud Release Builder Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.rocket, size: 16, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Релиз и облачная сборка APK',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.foreground,
                      ),
                    ),
                  ),
                  if (status.projectVersion != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'v${status.projectVersion}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10.5,
                          color: c.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Создаёт семантический Git-тег (vX.Y.Z) и пушит в GitHub для запуска GitHub Actions.',
                style: TextStyle(fontSize: 11, color: c.mutedForeground),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 33,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _showReleaseAndBuildModal(status, notifier),
                        icon: const Icon(
                          LucideIcons.cloud_lightning,
                          size: 14,
                        ),
                        label: const Text(
                          'Выпустить релиз + APK',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.accentForeground,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 33,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _showCreateTagDialog(notifier, status: status),
                      icon: Icon(LucideIcons.tag, size: 13, color: c.accent),
                      label: Text(
                        '+ Тег',
                        style: TextStyle(fontSize: 11, color: c.accent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Tags List
        Text(
          'ТЕГИ ВЕРСИЙ (${status.tags.length})',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: c.mutedForeground,
            letterSpacing: 0.65,
          ),
        ),
        const SizedBox(height: 6),
        if (status.tags.isEmpty)
          Text(
            'Теги ещё не созданы',
            style: TextStyle(fontSize: 11, color: c.subtleForeground),
          )
        else
          ...status.tags.map(
            (t) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: c.hairline),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.tag, size: 13.5, color: c.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              t.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.warning,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t.shortHash,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: c.subtleForeground,
                              ),
                            ),
                          ],
                        ),
                        if (t.subject.isNotEmpty)
                          Text(
                            t.subject,
                            style: TextStyle(fontSize: 11, color: c.foreground),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Text(
                    t.date,
                    style: TextStyle(fontSize: 10, color: c.subtleForeground),
                  ),
                  const SizedBox(width: 4),
                  _buildMiniIconBtn(
                    icon: LucideIcons.trash_2,
                    color: c.danger,
                    tooltip: 'Удалить тег ${t.name}',
                    onTap: () => notifier.deleteTag(t.name),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // MODALS & DIALOGS
  // ===========================================================================

  void _showBranchPickerModal(GitStatus status, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Переключение и слияние веток',
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCreateBranchDialog(notifier);
                      },
                      icon: Icon(LucideIcons.plus, size: 13, color: c.accent),
                      label: Text(
                        'Создать ветку',
                        style: TextStyle(color: c.accent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Divider(color: c.hairline),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...status.branches.map((b) {
                        final isCurrent = b == status.currentBranch;
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: Icon(
                            isCurrent
                                ? LucideIcons.circle_check
                                : LucideIcons.git_branch,
                            size: 16,
                            color: isCurrent ? c.accent : c.mutedForeground,
                          ),
                          title: Text(
                            b,
                            style: GoogleFonts.jetBrainsMono(
                              color: isCurrent ? c.accent : c.foreground,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12.5,
                            ),
                          ),
                          trailing: !isCurrent
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    notifier.mergeBranch(b);
                                  },
                                  child: Text(
                                    'Merge в текущую',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.accentSecondary,
                                    ),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.accent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'HEAD',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: c.accent,
                                    ),
                                  ),
                                ),
                          onTap: () {
                            Navigator.pop(ctx);
                            if (!isCurrent) notifier.checkoutBranch(b);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateBranchDialog(GitNotifier notifier, {String? fromRef}) {
    final c = GitThemeColors.resolve(context);
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          fromRef != null ? 'Новая ветка от $fromRef' : 'Создать новую ветку',
          style: TextStyle(
            color: c.foreground,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.foreground, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Например: feat/new-ui или fix/auth',
            hintStyle: TextStyle(color: c.subtleForeground, fontSize: 12),
            filled: true,
            fillColor: c.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.hairline),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim().replaceAll(' ', '-');
              if (name.isNotEmpty) {
                notifier.checkoutBranch(
                  name,
                  createNew: true,
                  fromRef: fromRef,
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.accentForeground,
              elevation: 0,
            ),
            child: const Text('Создать и перейти'),
          ),
        ],
      ),
    );
  }

  void _showRenameBranchDialog(String oldName, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Переименовать ветку',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.foreground, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: c.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.hairline),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim().replaceAll(' ', '-');
              if (newName.isNotEmpty && newName != oldName) {
                notifier.renameBranch(oldName, newName);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.accentForeground,
              elevation: 0,
            ),
            child: const Text('Переименовать'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBranch(String branch, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Удалить ветку $branch?',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: Text(
          'Локальная ветка будет удалена.',
          style: TextStyle(color: c.mutedForeground, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.deleteBranch(branch, force: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: GitThemeColors.contrastOn(c.danger),
              elevation: 0,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showResetCommitDialog(GitCommitEntry commit, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Reset к коммиту ${commit.shortHash}',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              commit.message,
              style: TextStyle(color: c.mutedForeground, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildResetOptionTile(
              c: c,
              title: 'Soft (--soft)',
              subtitle:
                  'Переместить HEAD, но оставить все изменения в Индексе (Staged)',
              color: c.success,
              onTap: () {
                Navigator.pop(ctx);
                notifier.resetToCommit(commit.hash, mode: 'soft');
              },
            ),
            const SizedBox(height: 6),
            _buildResetOptionTile(
              c: c,
              title: 'Mixed (--mixed)',
              subtitle:
                  'Переместить HEAD и оставить файлы изменёнными в Рабочей копии',
              color: c.warning,
              onTap: () {
                Navigator.pop(ctx);
                notifier.resetToCommit(commit.hash, mode: 'mixed');
              },
            ),
            const SizedBox(height: 6),
            _buildResetOptionTile(
              c: c,
              title: 'Hard (--hard)',
              subtitle:
                  'Полностью откатить код к этому коммиту (несохранённые правки удалятся!)',
              color: c.danger,
              onTap: () {
                Navigator.pop(ctx);
                notifier.resetToCommit(commit.hash, mode: 'hard');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
        ],
      ),
    );
  }

  Widget _buildResetOptionTile({
    required GitThemeColors c,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: c.mutedForeground, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickStashDialog(GitStatus status, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Спрятать изменения в Stash',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.foreground, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Описание Stash (необязательно)...',
            hintStyle: TextStyle(color: c.subtleForeground, fontSize: 12),
            filled: true,
            fillColor: c.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.hairline),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.stashSave(ctrl.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.warning,
              foregroundColor: GitThemeColors.contrastOn(c.warning),
              elevation: 0,
            ),
            child: const Text('В Stash'),
          ),
        ],
      ),
    );
  }

  void _showStashDiffModal(GitStashEntry stash, GitNotifier notifier) async {
    final c = GitThemeColors.resolve(context);
    final diff = await notifier.getStashDiff(stash.ref);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${stash.ref} — ${stash.message}',
              style: TextStyle(
                color: c.foreground,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 350),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.inputFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.hairline),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  diff.isNotEmpty ? diff : 'Нет данных diff',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: c.foreground.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGitSettingsDialog(GitStatus status, GitNotifier notifier) async {
    final storage = SecureStorageService();
    final savedToken = await storage.retrieve('github_token') ?? '';
    if (!mounted) return;
    final c = GitThemeColors.resolve(context);

    final tokenCtrl = TextEditingController(text: savedToken);
    final remoteCtrl = TextEditingController(text: status.remoteUrl ?? '');
    final nameCtrl =
        TextEditingController(text: status.userName ?? 'Quantum Developer');
    final emailCtrl =
        TextEditingController(text: status.userEmail ?? 'dev@quantum-ide.local');

    final wsPath = ref.read(workspaceProvider).currentPath;
    final defaultRepoName = wsPath != null ? p.basename(wsPath) : 'my-project';
    final newRepoNameCtrl = TextEditingController(text: defaultRepoName);
    final newRepoDescCtrl = TextEditingController(text: '');

    bool isCreatingNewRepo =
        status.remoteUrl == null || status.remoteUrl!.isEmpty;
    bool isPrivateRepo = true;
    bool isCreatingRepoNow = false;
    String? repoCreateError;

    bool obscureToken = true;
    bool isVerifyingToken = false;
    String? tokenVerifyStatus;
    Color tokenVerifyColor = c.mutedForeground;

    InputDecoration fieldDecoration({
      String? hint,
      Widget? suffixIcon,
    }) =>
        InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.subtleForeground, fontSize: 11),
          filled: true,
          fillColor: c.inputFill,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.accent),
          ),
          suffixIcon: suffixIcon,
        );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ghService = GitHubService();
          return AlertDialog(
            backgroundColor: c.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.hairline),
            ),
            title: Row(
              children: [
                Icon(LucideIcons.git_pull_request, color: c.accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Настройки Git и GitHub',
                  style: TextStyle(
                    color: c.foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode Switcher
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: c.inputFill,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: c.hairline),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setDialogState(() => isCreatingNewRepo = true),
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCreatingNewRepo
                                      ? c.accent.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: isCreatingNewRepo
                                        ? c.accent.withValues(alpha: 0.6)
                                        : Colors.transparent,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.circle_plus,
                                      size: 12,
                                      color: isCreatingNewRepo
                                          ? c.accent
                                          : c.mutedForeground,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Создать на GitHub',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isCreatingNewRepo
                                            ? c.accent
                                            : c.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(
                                () => isCreatingNewRepo = false,
                              ),
                              borderRadius: BorderRadius.circular(7),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 7),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: !isCreatingNewRepo
                                      ? c.accent.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: !isCreatingNewRepo
                                        ? c.accent.withValues(alpha: 0.6)
                                        : Colors.transparent,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.link,
                                      size: 12,
                                      color: !isCreatingNewRepo
                                          ? c.accent
                                          : c.mutedForeground,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Существующий URL',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: !isCreatingNewRepo
                                            ? c.accent
                                            : c.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 1: GitHub PAT Token
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.panel,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: c.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                LucideIcons.key_round,
                                size: 14,
                                color: c.accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'GitHub Персональный токен (PAT):',
                                  style: TextStyle(
                                    color: c.foreground,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (ghService.isAuthenticated)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.success.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: c.success.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    '@${ghService.currentUser?['login'] ?? 'ok'}',
                                    style: TextStyle(
                                      color: c.success,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Нужен для отправки кода и создания репозиториев (права repo и workflow).',
                            style: TextStyle(
                              color: c.mutedForeground,
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: tokenCtrl,
                            obscureText: obscureToken,
                            style: GoogleFonts.jetBrainsMono(
                              color: c.foreground,
                              fontSize: 11,
                            ),
                            decoration: fieldDecoration(
                              hint: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      obscureToken
                                          ? LucideIcons.eye_off
                                          : LucideIcons.eye,
                                      size: 14,
                                      color: c.mutedForeground,
                                    ),
                                    onPressed: () => setDialogState(
                                      () => obscureToken = !obscureToken,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      LucideIcons.clipboard,
                                      size: 14,
                                      color: c.accent,
                                    ),
                                    tooltip: 'Вставить из буфера',
                                    onPressed: () async {
                                      final data = await Clipboard.getData(
                                        Clipboard.kTextPlain,
                                      );
                                      if (data?.text != null &&
                                          data!.text!.trim().isNotEmpty) {
                                        setDialogState(() {
                                          tokenCtrl.text = data.text!.trim();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              SizedBox(
                                height: 28,
                                child: OutlinedButton.icon(
                                  onPressed: isVerifyingToken
                                      ? null
                                      : () async {
                                          final t = tokenCtrl.text.trim();
                                          if (t.isEmpty) return;
                                          setDialogState(() {
                                            isVerifyingToken = true;
                                            tokenVerifyStatus = null;
                                          });
                                          try {
                                            final ok = await GitHubService()
                                                .authenticateWithToken(t);
                                            setDialogState(() {
                                              isVerifyingToken = false;
                                              if (ok) {
                                                tokenVerifyStatus =
                                                    '✓ Токен валиден (@${GitHubService().currentUser?['login'] ?? ''})';
                                                tokenVerifyColor = c.success;
                                              } else {
                                                tokenVerifyStatus =
                                                    '⚠ Ошибка проверки токена';
                                                tokenVerifyColor = c.warning;
                                              }
                                            });
                                          } catch (e) {
                                            setDialogState(() {
                                              isVerifyingToken = false;
                                              tokenVerifyStatus =
                                                  '✗ Ошибка: $e';
                                              tokenVerifyColor = c.danger;
                                            });
                                          }
                                        },
                                  icon: isVerifyingToken
                                      ? SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: c.accent,
                                          ),
                                        )
                                      : const Icon(
                                          LucideIcons.shield_check,
                                          size: 12,
                                        ),
                                  label: const Text(
                                    'Проверить токен',
                                    style: TextStyle(fontSize: 10.5),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: c.accent,
                                    side: BorderSide(
                                      color: c.accent.withValues(alpha: 0.6),
                                      width: 0.9,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (tokenVerifyStatus != null)
                                Expanded(
                                  child: Text(
                                    tokenVerifyStatus!,
                                    style: TextStyle(
                                      color: tokenVerifyColor,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 2: New Repo Creation vs Existing Remote URL
                    if (isCreatingNewRepo) ...[
                      Text(
                        'Название нового репозитория на GitHub:',
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: newRepoNameCtrl,
                        style: GoogleFonts.jetBrainsMono(
                          color: c.foreground,
                          fontSize: 12,
                        ),
                        decoration: fieldDecoration(hint: 'my-project-name'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Описание репозитория (необязательно):',
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: newRepoDescCtrl,
                        style: TextStyle(color: c.foreground, fontSize: 12),
                        decoration:
                            fieldDecoration(hint: 'Краткое описание проекта...'),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Доступ к репозиторию (Приватность):',
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setDialogState(() => isPrivateRepo = true),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isPrivateRepo
                                      ? c.warning.withValues(alpha: 0.12)
                                      : c.inputFill,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isPrivateRepo ? c.warning : c.hairline,
                                    width: isPrivateRepo ? 1.4 : 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          LucideIcons.lock,
                                          size: 14,
                                          color: isPrivateRepo
                                              ? c.warning
                                              : c.mutedForeground,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Приватный',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isPrivateRepo
                                                ? c.warning
                                                : c.foreground,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Закрыт от всех. Код виден только вам.',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: c.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  setDialogState(() => isPrivateRepo = false),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: !isPrivateRepo
                                      ? c.accent.withValues(alpha: 0.12)
                                      : c.inputFill,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: !isPrivateRepo ? c.accent : c.hairline,
                                    width: !isPrivateRepo ? 1.4 : 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          LucideIcons.globe,
                                          size: 14,
                                          color: !isPrivateRepo
                                              ? c.accent
                                              : c.mutedForeground,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Публичный',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: !isPrivateRepo
                                                ? c.accent
                                                : c.foreground,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Открыт для всех в интернете.',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: c.mutedForeground,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (repoCreateError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          repoCreateError!,
                          style: TextStyle(color: c.danger, fontSize: 11),
                        ),
                      ],
                    ] else ...[
                      Text(
                        'Удалённый репозиторий (Remote URL origin):',
                        style: TextStyle(
                          color: c.mutedForeground,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: remoteCtrl,
                        style: GoogleFonts.jetBrainsMono(
                          color: c.foreground,
                          fontSize: 12,
                        ),
                        decoration: fieldDecoration(
                          hint: 'https://github.com/пользователь/репозиторий.git',
                          suffixIcon: IconButton(
                            icon: Icon(
                              LucideIcons.clipboard,
                              size: 14,
                              color: c.accent,
                            ),
                            tooltip: 'Вставить из буфера',
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null &&
                                  data!.text!.trim().isNotEmpty) {
                                remoteCtrl.text = data.text!.trim();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Section 3: Author info
                    Text(
                      'Имя автора коммитов (user.name):',
                      style: TextStyle(color: c.mutedForeground, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: c.foreground, fontSize: 12),
                      decoration: fieldDecoration(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Email автора коммитов (user.email):',
                      style: TextStyle(color: c.mutedForeground, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: emailCtrl,
                      style: TextStyle(color: c.foreground, fontSize: 12),
                      decoration: fieldDecoration(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    Text('Отмена', style: TextStyle(color: c.mutedForeground)),
              ),
              if (isCreatingNewRepo)
                ElevatedButton.icon(
                  onPressed: isCreatingRepoNow
                      ? null
                      : () async {
                          final tokenText = tokenCtrl.text.trim();
                          if (tokenText.isNotEmpty) {
                            await GitHubService()
                                .authenticateWithToken(tokenText);
                          }
                          if (!GitHubService().isAuthenticated) {
                            setDialogState(() {
                              repoCreateError =
                                  'Для создания репозитория необходимо ввести и проверить GitHub токен (PAT)';
                            });
                            return;
                          }
                          final repoName = newRepoNameCtrl.text.trim();
                          if (repoName.isEmpty) {
                            setDialogState(() {
                              repoCreateError = 'Введите название репозитория';
                            });
                            return;
                          }
                          setDialogState(() {
                            isCreatingRepoNow = true;
                            repoCreateError = null;
                          });

                          final res = await GitHubService().createRepository(
                            name: repoName,
                            description: newRepoDescCtrl.text.trim(),
                            isPrivate: isPrivateRepo,
                          );

                          if (res != null) {
                            final cloneUrl = res['clone_url']?.toString() ??
                                'https://github.com/${res['full_name']}.git';
                            await notifier.setRemoteUrl(cloneUrl);
                            if (nameCtrl.text.trim().isNotEmpty &&
                                emailCtrl.text.trim().isNotEmpty) {
                              await notifier.setUserConfig(
                                nameCtrl.text.trim(),
                                emailCtrl.text.trim(),
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            await notifier.push();
                            if (mounted && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '✓ Репозиторий «$repoName» (${isPrivateRepo ? "Приватный" : "Публичный"}) создан и отправлен на GitHub!',
                                  ),
                                  backgroundColor: c.success,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isCreatingRepoNow = false;
                              repoCreateError = GitHubService().lastError ??
                                  'Не удалось создать репозиторий на GitHub';
                            });
                          }
                        },
                  icon: isCreatingRepoNow
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.accentForeground,
                          ),
                        )
                      : const Icon(LucideIcons.rocket, size: 14),
                  label: Text(
                    isCreatingRepoNow
                        ? 'Создание...'
                        : 'Создать и Push (${isPrivateRepo ? "Приватный" : "Публичный"})',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.accentForeground,
                    elevation: 0,
                  ),
                )
              else ...[
                OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final tokenText = tokenCtrl.text.trim();
                    if (tokenText.isNotEmpty) {
                      await GitHubService().authenticateWithToken(tokenText);
                    }
                    if (remoteCtrl.text.trim().isNotEmpty) {
                      await notifier.setRemoteUrl(remoteCtrl.text.trim());
                    }
                    if (nameCtrl.text.trim().isNotEmpty &&
                        emailCtrl.text.trim().isNotEmpty) {
                      await notifier.setUserConfig(
                        nameCtrl.text.trim(),
                        emailCtrl.text.trim(),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.accent,
                    side: BorderSide(color: c.border),
                  ),
                  child: const Text('Сохранить'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final tokenText = tokenCtrl.text.trim();
                    if (tokenText.isNotEmpty) {
                      await GitHubService().authenticateWithToken(tokenText);
                    }
                    if (remoteCtrl.text.trim().isNotEmpty) {
                      await notifier.setRemoteUrl(remoteCtrl.text.trim());
                    }
                    if (nameCtrl.text.trim().isNotEmpty &&
                        emailCtrl.text.trim().isNotEmpty) {
                      await notifier.setUserConfig(
                        nameCtrl.text.trim(),
                        emailCtrl.text.trim(),
                      );
                    }
                    await notifier.push();
                  },
                  icon: const Icon(LucideIcons.cloud_upload, size: 14),
                  label: const Text('Сохранить и Push'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.accentForeground,
                    elevation: 0,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _confirmForcePush(GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Выполнить Force Push?',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: Text(
          'Будет выполнен безопасный git push --force-with-lease (полезно после Amend или Reset).',
          style: TextStyle(color: c.mutedForeground, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.push(force: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: GitThemeColors.contrastOn(c.danger),
              elevation: 0,
            ),
            child: const Text('Force Push'),
          ),
        ],
      ),
    );
  }

  void _confirmDiscardFile(String file, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Откатить изменения в файле?',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: Text(
          'Все несохранённые правки в «$file» будут возвращены к последнему коммиту.',
          style: TextStyle(color: c.mutedForeground, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.discardFile(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: GitThemeColors.contrastOn(c.danger),
              elevation: 0,
            ),
            child: const Text('Откатить'),
          ),
        ],
      ),
    );
  }

  void _confirmDiscardAll(GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        title: Text(
          'Откатить ВСЕ изменения?',
          style: TextStyle(color: c.foreground, fontSize: 15),
        ),
        content: Text(
          'Будет выполнен git reset --hard HEAD && git clean -fd. Все незакоммиченные правки будут удалены.',
          style: TextStyle(color: c.mutedForeground, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.discardAll();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.danger,
              foregroundColor: GitThemeColors.contrastOn(c.danger),
              elevation: 0,
            ),
            child: const Text('Откатить всё'),
          ),
        ],
      ),
    );
  }

  void _showCreateTagDialog(
    GitNotifier notifier, {
    GitStatus? status,
    String? commitHash,
  }) {
    final c = GitThemeColors.resolve(context);
    final tagCtrl =
        TextEditingController(text: _suggestNextVersionTag(status, 'patch'));
    final msgCtrl = TextEditingController(text: 'Release');
    bool pushRemote = status?.remoteUrl != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.hairline),
          ),
          title: Text(
            'Создать тег версии',
            style: TextStyle(color: c.foreground, fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tagCtrl,
                style: GoogleFonts.jetBrainsMono(color: c.warning, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Имя тега (например v1.0.1)',
                  labelStyle: TextStyle(color: c.mutedForeground, fontSize: 12),
                  filled: true,
                  fillColor: c.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: msgCtrl,
                style: TextStyle(color: c.foreground, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Описание',
                  labelStyle: TextStyle(color: c.mutedForeground, fontSize: 12),
                  filled: true,
                  fillColor: c.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: pushRemote,
                activeColor: c.accent,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Отправить тег в GitHub (git push --tags)',
                  style: TextStyle(color: c.mutedForeground, fontSize: 11),
                ),
                onChanged: (v) => setDialogState(() => pushRemote = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: TextStyle(color: c.mutedForeground)),
            ),
            ElevatedButton(
              onPressed: () {
                if (tagCtrl.text.trim().isNotEmpty) {
                  notifier.createVersionTag(
                    tagCtrl.text.trim(),
                    msgCtrl.text.trim(),
                    pushToRemote: pushRemote,
                    commitHash: commitHash,
                  );
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.accentForeground,
                elevation: 0,
              ),
              child: const Text('Создать тег'),
            ),
          ],
        ),
      ),
    );
  }

  String _suggestNextVersionTag(GitStatus? status, String bumpType) {
    String base = status?.projectVersion?.split('+').first ?? '1.0.0';
    if (status != null && status.tags.isNotEmpty) {
      final latestTag = status.tags.first.name;
      final clean =
          latestTag.startsWith('v') ? latestTag.substring(1) : latestTag;
      if (RegExp(r'^\d+\.\d+\.\d+').hasMatch(clean)) {
        base = clean.split('-').first.split('+').first;
      }
    }
    final parts = base.split('.');
    int major = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 1) : 1;
    int minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    int patch = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;

    if (bumpType == 'major') {
      major++;
      minor = 0;
      patch = 0;
    } else if (bumpType == 'minor') {
      minor++;
      patch = 0;
    } else {
      patch++;
    }
    return 'v$major.$minor.$patch';
  }

  void _showReleaseAndBuildModal(GitStatus status, GitNotifier notifier) {
    final c = GitThemeColors.resolve(context);
    final tagCtrl =
        TextEditingController(text: _suggestNextVersionTag(status, 'patch'));
    final notesCtrl = TextEditingController(
      text: _commitController.text.trim().isNotEmpty
          ? _commitController.text.trim()
          : 'Release ${_suggestNextVersionTag(status, 'patch')}',
    );
    bool isReleasing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Выпуск релиза и сборка APK в GitHub Actions',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tagCtrl,
                style: GoogleFonts.jetBrainsMono(color: c.warning, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Тег релиза (vX.Y.Z)',
                  labelStyle: TextStyle(color: c.mutedForeground, fontSize: 12),
                  filled: true,
                  fillColor: c.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                style: TextStyle(color: c.foreground, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Описание релиза',
                  labelStyle: TextStyle(color: c.mutedForeground, fontSize: 12),
                  filled: true,
                  fillColor: c.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: isReleasing
                    ? null
                    : () async {
                        final tag = tagCtrl.text.trim();
                        if (tag.isEmpty) return;
                        setModalState(() => isReleasing = true);
                        try {
                          await notifier.releaseAndBuildApk(
                            tagName: tag,
                            commitMessage:
                                'chore(release): $tag — ${notesCtrl.text.trim()}',
                            releaseNotes: notesCtrl.text.trim(),
                          );
                          if (modalCtx.mounted) Navigator.pop(modalCtx);
                          final remote = status.remoteUrl;
                          if (remote != null && remote.contains('github.com')) {
                            var cleanUrl = remote.replaceAll('.git', '');
                            if (cleanUrl.startsWith('git@github.com:')) {
                              cleanUrl = cleanUrl.replaceFirst(
                                'git@github.com:',
                                'https://github.com/',
                              );
                            }
                            final uri = Uri.tryParse('$cleanUrl/actions');
                            if (uri != null) {
                              launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          }
                        } catch (_) {
                          if (modalCtx.mounted) {
                            setModalState(() => isReleasing = false);
                          }
                        }
                      },
                icon: const Icon(LucideIcons.rocket, size: 15),
                label: Text(
                  isReleasing
                      ? 'Отправка в GitHub...'
                      : 'Закоммитить, создать тег и запустить сборку',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.accentForeground,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGitGuideModal() {
    final c = GitThemeColors.resolve(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.book_open, color: c.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Как устроен Git в Quantum IDE',
                      style: TextStyle(
                        color: c.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1. Рабочая копия → Индекс (Staged):\n'
                '   • Изменённые (M) и новые (U) файлы отображаются во вкладке «Изменения».\n'
                '   • Нажмите на файл для просмотра Diff или «+» для добавления в индекс.\n\n'
                '2. Коммит и Conventional Commits:\n'
                '   • Выберите префикс (feat:, fix:, refactor:) или нажмите «✨ AI» для автоописания.\n'
                '   • Флаг «Amend» дополнит последний коммит без создания нового.\n\n'
                '3. История и граф веток:\n'
                '   • Нажмите на коммит в истории для просмотра патча, Cherry-pick, Revert или Reset.\n\n'
                '4. Ветки и Stash:\n'
                '   • Во вкладке «Ветки» переключайте локальные и удалённые ветки, выполняйте Merge и управляйте Stash.',
                style: TextStyle(
                  color: c.mutedForeground,
                  fontSize: 11.5,
                  height: 1.48,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoRepoView(GitNotifier notifier, GitThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.folder_git_2, size: 42, color: c.accent),
              const SizedBox(height: 12),
              Text(
                'Git-репозиторий не инициализирован',
                style: TextStyle(
                  color: c.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Инициализируйте Git в текущем проекте, чтобы отслеживать изменения, управлять ветками и пушить на GitHub.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.mutedForeground, fontSize: 11.5),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => notifier.init(),
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('Инициализировать Git (git init)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.accentForeground,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
