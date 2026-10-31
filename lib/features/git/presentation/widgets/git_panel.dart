import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/github_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_graph_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';
import 'package:quantum_ide/features/github/presentation/pages/github_page.dart';
import 'package:quantum_ide/features/git/presentation/widgets/git_download_dialog.dart';
import 'package:quantum_ide/core/services/secure_storage_service.dart';
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

class _GitPanelState extends ConsumerState<GitPanel> with SingleTickerProviderStateMixin {
  final TextEditingController _commitController = TextEditingController();
  final TextEditingController _fileFilterController = TextEditingController();
  final TextEditingController _commitSearchController = TextEditingController();
  late TabController _tabController;

  bool _isGeneratingCommitMessage = false;
  bool _amendCommit = false;
  bool _stagedExpanded = true;
  bool _workingExpanded = true;
  bool _conflictsExpanded = true;
  String _fileFilter = '';
  String _commitFilter = '';

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
      setState(() => _fileFilter = _fileFilterController.text.trim().toLowerCase());
    });
    _commitSearchController.addListener(() {
      setState(() => _commitFilter = _commitSearchController.text.trim().toLowerCase());
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
      final notifier = ref.read(gitProvider.notifier);
      final diffSnippets = <String>[];
      for (final file in allChanged.take(5)) {
        final d = await notifier.getFileDiff(
          file,
          staged: status.stagedFiles.contains(file),
        );
        if (d.trim().isNotEmpty) {
          final truncated = d.length > 700 ? '${d.substring(0, 700)}\n...' : d;
          diffSnippets.add('--- $file ---\n$truncated');
        }
      }

      try {
        final aiService = ref.read(aiServiceProvider);
        final prompt =
            'Сгенерируй краткое профессиональное сообщение коммита в формате Conventional Commits (например: "feat: ...", "fix: ...", "refactor: ...") на русском или английском языке (1 строка, без кавычек и без markdown). '
            'Список файлов: ${allChanged.take(12).join(', ')}.\n'
            '${diffSnippets.isNotEmpty ? "Фрагменты diff:\n${diffSnippets.join('\n')}" : ""}';
        final response = await aiService
            .getCompletion(prompt)
            .timeout(const Duration(seconds: 10));
        final clean = response
            .trim()
            .replaceAll('```', '')
            .replaceAll('"', '')
            .split('\n')
            .first
            .trim();
        if (clean.isNotEmpty && !clean.startsWith('Error')) {
          _commitController.text = clean;
          setState(() => _isGeneratingCommitMessage = false);
          return;
        }
      } catch (_) {}

      // Fallback heuristic conventional commit generator
      final names = allChanged.map((f) => p.basename(f)).take(3).join(', ');
      final suffix = allChanged.length > 3 ? ' (+${allChanged.length - 3})' : '';
      String prefix = 'chore';
      if (status.untrackedFiles.isNotEmpty && status.modifiedFiles.isEmpty) {
        prefix = 'feat';
      } else if (allChanged.any((f) => f.contains('fix') || f.contains('bug') || f.contains('service'))) {
        prefix = 'fix';
      } else if (allChanged.any((f) => f.contains('widget') || f.contains('page') || f.contains('ui'))) {
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
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0B0E14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopToolbar(gitState, notifier, isLight),
          if (gitState.isLoading) ...[
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: Color(0xFF00F2FE),
            ),
            _buildOperationProgressBanner(gitState.currentOperation),
          ],
          if (gitState.error != null)
            _buildBanner(
              message: gitState.error!,
              color: Colors.redAccent,
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
                      onTap: () => _showGitSettingsDialog(gitState.status!, notifier),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.key_round, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Настроить токен/Remote',
                              style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
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
              color: Colors.greenAccent,
              icon: LucideIcons.circle_check,
              onClose: () => notifier.refreshStatus(silent: true),
            ),
          if (gitState.status != null) _buildTabBar(gitState.status!, isLight),
          Expanded(
            child: gitState.status == null && !gitState.isLoading
                ? _buildNoRepoView(notifier, isLight)
                : gitState.status == null
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildChangesTab(gitState.status!, notifier, isLight),
                          _buildHistoryTab(gitState.status!, notifier, isLight),
                          _buildBranchesAndStashTab(gitState.status!, notifier, isLight),
                          _buildReleasesAndRemoteTab(gitState.status!, notifier, isLight),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationProgressBanner(String? operationText) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              operationText ?? 'Выполняется операция Git...',
              style: const TextStyle(
                color: Color(0xFF00F2FE),
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
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
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
            child: Icon(LucideIcons.x, size: 13, color: color.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar(GitState gitState, GitNotifier notifier, bool isLight) {
    final status = gitState.status;
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white54;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF111520),
        border: Border(
          bottom: BorderSide(color: isLight ? Colors.black12 : Colors.white10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title + Branch Selector + Sync Badges
          Row(
            children: [
              const Icon(LucideIcons.git_branch, size: 15, color: Color(0xFF00F2FE)),
              const SizedBox(width: 6),
              if (status != null)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => _showBranchPickerModal(status, notifier),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F2FE).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF00F2FE).withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  status.currentBranch,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: const Color(0xFF00F2FE),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(LucideIcons.chevron_down, size: 11, color: Color(0xFF00F2FE)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (status.ahead > 0 || status.behind > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '↑${status.ahead} ↓${status.behind}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (status.ahead > 0 || status.behind > 0) const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _showGitSettingsDialog(status, notifier),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              gradient: status.remoteUrl == null
                                  ? const LinearGradient(
                                      colors: [Color(0xFF8B5CF6), Color(0xFF00F2FE)],
                                    )
                                  : null,
                              color: status.remoteUrl != null
                                  ? Colors.greenAccent.withValues(alpha: 0.14)
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: status.remoteUrl != null
                                    ? Colors.greenAccent.withValues(alpha: 0.4)
                                    : Colors.transparent,
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  status.remoteUrl != null ? LucideIcons.cloud : LucideIcons.cloud_upload,
                                  size: 11,
                                  color: status.remoteUrl != null ? Colors.greenAccent : Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  status.remoteUrl != null
                                      ? _shortRemoteName(status.remoteUrl!)
                                      : '🚀 Опубликовать на GitHub',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: status.remoteUrl != null ? Colors.greenAccent : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'УПРАВЛЕНИЕ ВЕРСИЯМИ (GIT)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(LucideIcons.info, size: 14, color: subColor),
                tooltip: 'Шпаргалка по Git',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: _showGitGuideModal,
              ),
              IconButton(
                icon: Icon(LucideIcons.refresh_cw, size: 14, color: subColor),
                tooltip: 'Обновить статус Git',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => notifier.refreshStatus(force: true),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 6),
            // Row 2: Quick Professional Git Operations Bar in Russian
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickToolBtn(
                    icon: LucideIcons.refresh_cw,
                    label: (status.ahead > 0 || status.behind > 0)
                        ? 'Синхр (↓${status.behind} ↑${status.ahead})'
                        : 'Синхронизация',
                    tooltip: 'Синхронизировать код с сервером (Pull & Push в одно действие)',
                    color: (status.ahead > 0 || status.behind > 0) ? const Color(0xFF00F2FE) : Colors.cyanAccent,
                    onTap: () => notifier.sync(),
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.refresh_ccw_dot,
                    label: 'Проверить (Fetch)',
                    tooltip: 'git fetch --all --prune (проверить наличие свежих коммитов на сервере)',
                    color: Colors.cyanAccent,
                    onTap: () => notifier.fetch(),
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.arrow_down_to_line,
                    label: status.behind > 0 ? 'Подтянуть (↓${status.behind})' : 'Подтянуть (Pull)',
                    tooltip: 'git pull (скачать свежие изменения с сервера, долгое нажатие — Pull --rebase)',
                    color: status.behind > 0 ? Colors.amberAccent : Colors.white70,
                    onTap: () => notifier.pull(),
                    onLongPress: () => notifier.pull(rebase: true),
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.arrow_up_from_line,
                    label: status.ahead > 0 ? 'Отправить (↑${status.ahead})' : 'Отправить (Push)',
                    tooltip: 'git push (отправить локальные коммиты на сервер, долгое нажатие — Force Push)',
                    color: status.ahead > 0 ? const Color(0xFF00F2FE) : Colors.white70,
                    onTap: () => notifier.push(),
                    onLongPress: () => _confirmForcePush(notifier),
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.git_graph,
                    label: 'Граф коммитов',
                    tooltip: 'Открыть визуальное интерактивное дерево веток и истории коммитов',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GitGraphPage()),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.archive,
                    label: status.stashes.isNotEmpty ? 'Stash (${status.stashes.length})' : 'Спрятать (Stash)',
                    tooltip: 'Временно спрятать незавершённые изменения рабочей копии в тайник',
                    color: Colors.orangeAccent,
                    onTap: () => _showQuickStashDialog(status, notifier),
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.cloud_download,
                    label: 'Загрузить из Git',
                    tooltip: 'Выбрать и скачать файл или папку из любого репозитория GitHub в проект',
                    color: const Color(0xFF10B981),
                    onTap: () {
                      final wsPath = ref.read(workspaceProvider).currentPath;
                      if (wsPath != null) {
                        GitDownloadDialog.show(context, workspacePath: wsPath, gitNotifier: notifier);
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _buildQuickToolBtn(
                    icon: LucideIcons.key_round,
                    label: 'GitHub / Remote',
                    tooltip: 'Настроить токен GitHub (PAT), URL репозитория (origin) и автора',
                    color: Colors.white70,
                    onTap: () => _showGitSettingsDialog(status, notifier),
                  ),
                ],
              ),
            ),
          ],
        ],
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

  Widget _buildQuickToolBtn({
    required IconData icon,
    required String label,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(GitStatus status, bool isLight) {
    final changesCount = status.totalChangesCount;
    final commitsCount = status.recentCommits.length;
    final branchesAndStashesCount = status.branches.length + status.stashes.length;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0E121B),
        border: Border(bottom: BorderSide(color: isLight ? Colors.black12 : Colors.white10)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: const Color(0xFF00F2FE),
        indicatorWeight: 2,
        labelColor: const Color(0xFF00F2FE),
        unselectedLabelColor: isLight ? Colors.black54 : Colors.white54,
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        tabs: [
          Tab(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.file_diff, size: 12),
                const SizedBox(width: 5),
                const Text('Изменения'),
                if (changesCount > 0) ...[
                  const SizedBox(width: 4),
                  _buildCountPill(changesCount.toString(), const Color(0xFF00F2FE)),
                ],
              ],
            ),
          ),
          Tab(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.history, size: 12),
                const SizedBox(width: 5),
                Text('История ($commitsCount)'),
              ],
            ),
          ),
          Tab(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.git_branch, size: 12),
                const SizedBox(width: 5),
                Text('Ветки / Stash ($branchesAndStashesCount)'),
              ],
            ),
          ),
          Tab(
            height: 34,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.rocket, size: 12),
                const SizedBox(width: 5),
                Text('Релизы (${status.tags.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: ИЗМЕНЕНИЯ (STAGING, WORKING TREE & COMMIT COMPOSER)
  // ===========================================================================

  Widget _buildChangesTab(GitStatus status, GitNotifier notifier, bool isLight) {
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white54;

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
        // Commit Composer Box
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xFF121622),
            border: Border(bottom: BorderSide(color: isLight ? Colors.black12 : Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Conventional Commit Quick Chips + AI + Amend
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final prefix in _conventionalPrefixes)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () => _applyPrefix(prefix),
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _commitController.text.startsWith(prefix)
                                  ? const Color(0xFF00F2FE).withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: _commitController.text.startsWith(prefix)
                                    ? const Color(0xFF00F2FE)
                                    : Colors.white12,
                              ),
                            ),
                            child: Text(
                              prefix.trim(),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: _commitController.text.startsWith(prefix)
                                    ? const Color(0xFF00F2FE)
                                    : subColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Commit Message Input + AI Button
              Stack(
                alignment: Alignment.topRight,
                children: [
                  TextField(
                    controller: _commitController,
                    maxLines: 2,
                    minLines: 1,
                    style: TextStyle(fontSize: 12, color: textColor),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: status.stagedFiles.isNotEmpty
                          ? 'Сообщение коммита (${status.stagedFiles.length} в индексе)...'
                          : 'Сообщение коммита (все изменения будут добавлены)...',
                      hintStyle: TextStyle(color: subColor, fontSize: 11),
                      filled: true,
                      fillColor: isLight ? const Color(0xFFF1F5F9) : Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: isLight ? Colors.black12 : Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: isLight ? Colors.black12 : Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF00F2FE)),
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(10, 8, 56, 8),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: InkWell(
                      onTap: _isGeneratingCommitMessage ? null : _generateSmartCommitMessage,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFF00F2FE)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _isGeneratingCommitMessage
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.sparkles, size: 11, color: Colors.white),
                                  SizedBox(width: 3),
                                  Text(
                                    'AI',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Amend toggle + Commit / Commit & Push Buttons
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _amendCommit = !_amendCommit;
                        if (_amendCommit &&
                            _commitController.text.trim().isEmpty &&
                            status.recentCommits.isNotEmpty) {
                          _commitController.text = status.recentCommits.first.message;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _amendCommit ? LucideIcons.square_check : LucideIcons.square,
                            size: 13,
                            color: _amendCommit ? const Color(0xFF00F2FE) : subColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Amend',
                            style: TextStyle(
                              fontSize: 10,
                              color: _amendCommit ? const Color(0xFF00F2FE) : subColor,
                              fontWeight: _amendCommit ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: (status.hasChanges || _amendCommit)
                            ? () async {
                                final msg = _commitController.text.trim().isNotEmpty
                                    ? _commitController.text.trim()
                                    : 'chore: update (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';
                                final ok = await notifier.commit(msg, amend: _amendCommit);
                                if (ok && mounted) {
                                  _commitController.clear();
                                  setState(() => _amendCommit = false);
                                }
                              }
                            : null,
                        icon: const Icon(LucideIcons.check, size: 13),
                        label: Text(
                          status.stagedFiles.isNotEmpty
                              ? 'Коммит (${status.stagedFiles.length})'
                              : 'Коммит все (${status.totalChangesCount})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F2FE),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: (status.hasChanges || status.ahead > 0)
                            ? () async {
                                if (status.hasChanges) {
                                  final msg = _commitController.text.trim().isNotEmpty
                                      ? _commitController.text.trim()
                                      : 'chore: sync (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})';
                                  final ok = await notifier.commitAndPush(msg, amend: _amendCommit);
                                  if (ok && mounted) {
                                    _commitController.clear();
                                    setState(() => _amendCommit = false);
                                  }
                                } else {
                                  await notifier.push();
                                }
                              }
                            : null,
                        icon: const Icon(LucideIcons.cloud_upload, size: 13),
                        label: Text(
                          status.ahead > 0 ? 'Push (${status.ahead})' : 'Коммит и Push',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _fileFilterController,
                style: TextStyle(fontSize: 11, color: textColor),
                decoration: InputDecoration(
                  hintText: 'Фильтр изменённых файлов...',
                  hintStyle: TextStyle(fontSize: 11, color: subColor),
                  prefixIcon: Icon(LucideIcons.search, size: 13, color: subColor),
                  suffixIcon: _fileFilter.isNotEmpty
                      ? InkWell(
                          onTap: () => _fileFilterController.clear(),
                          child: Icon(LucideIcons.x, size: 12, color: subColor),
                        )
                      : null,
                  filled: true,
                  fillColor: isLight ? Colors.white : const Color(0xFF141824),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

        // Changed Files Sections
        Expanded(
          child: !status.hasChanges
              ? _buildCleanWorkingTreeView(status, notifier, isLight)
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    // 1. CONFLICTS SECTION
                    if (filteredConflicts.isNotEmpty) ...[
                      _buildCollapsibleHeader(
                        title: 'КОНФЛИКТЫ СЛИЯНИЯ (${filteredConflicts.length})',
                        color: Colors.redAccent,
                        expanded: _conflictsExpanded,
                        onToggle: () => setState(() => _conflictsExpanded = !_conflictsExpanded),
                      ),
                      if (_conflictsExpanded)
                        ...filteredConflicts.map(
                          (f) => _buildFileRow(
                            file: f,
                            statusCode: 'U',
                            badgeColor: Colors.redAccent,
                            stats: status.diffStats[f],
                            isLight: isLight,
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
                                color: Colors.amberAccent,
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
                                color: Colors.greenAccent,
                                tooltip: 'Отметить решённым (git add)',
                                onTap: () => notifier.stageFile(f),
                              ),
                            ],
                          ),
                        ),
                    ],

                    // 2. STAGED CHANGES (ИНДЕКС)
                    _buildCollapsibleHeader(
                      title: 'В ИНДЕКСЕ ДЛЯ КОММИТА (${filteredStaged.length})',
                      color: Colors.greenAccent,
                      expanded: _stagedExpanded,
                      onToggle: () => setState(() => _stagedExpanded = !_stagedExpanded),
                      trailing: filteredStaged.isNotEmpty
                          ? InkWell(
                              onTap: () => notifier.unstageAll(),
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.minus, size: 11, color: Colors.orangeAccent),
                                    SizedBox(width: 3),
                                    Text(
                                      'Снять все',
                                      style: TextStyle(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.w600),
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
                          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                          child: Text(
                            'Индекс пуст. Нажмите «+» у нужных файлов или «В индекс все», чтобы подготовить коммит.',
                            style: TextStyle(fontSize: 10, color: subColor),
                          ),
                        )
                      else
                        ...filteredStaged.map(
                          (f) => _buildFileRow(
                            file: f,
                            statusCode: status.fileStatusCodes[f] ?? 'A',
                            badgeColor: Colors.greenAccent,
                            stats: status.diffStats[f],
                            isLight: isLight,
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
                                color: Colors.white54,
                                tooltip: 'Открыть файл в редакторе',
                                onTap: () => _openFileInEditor(f),
                              ),
                              _buildMiniIconBtn(
                                icon: LucideIcons.minus,
                                color: Colors.orangeAccent,
                                tooltip: 'Убрать из индекса (Unstage)',
                                onTap: () => notifier.unstageFile(f),
                              ),
                            ],
                          ),
                        ),

                    // 3. WORKING TREE (РАБОЧАЯ КОПИЯ)
                    _buildCollapsibleHeader(
                      title: 'ИЗМЕНЕНИЯ РАБОЧЕЙ КОПИИ (${workingFiles.length})',
                      color: Colors.amberAccent,
                      expanded: _workingExpanded,
                      onToggle: () => setState(() => _workingExpanded = !_workingExpanded),
                      trailing: workingFiles.isNotEmpty
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => _confirmDiscardAll(notifier),
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    child: Icon(LucideIcons.trash_2, size: 12, color: Colors.redAccent),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () => notifier.stageAll(),
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(LucideIcons.plus, size: 11, color: Color(0xFF00F2FE)),
                                        SizedBox(width: 3),
                                        Text(
                                          'В индекс все',
                                          style: TextStyle(fontSize: 10, color: Color(0xFF00F2FE), fontWeight: FontWeight.w600),
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
                        final code = isUntracked ? 'U' : (status.fileStatusCodes[f] ?? 'M');
                        final color = isUntracked ? Colors.lightBlueAccent : Colors.amberAccent;
                        return _buildFileRow(
                          file: f,
                          statusCode: code,
                          badgeColor: color,
                          stats: status.diffStats[f],
                          isLight: isLight,
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
                              color: Colors.white38,
                              tooltip: 'Добавить в .gitignore',
                              onTap: () => notifier.addToGitignore(f),
                            ),
                            _buildMiniIconBtn(
                              icon: LucideIcons.undo_2,
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              tooltip: 'Откатить изменения в файле (Discard)',
                              onTap: () => _confirmDiscardFile(f, notifier),
                            ),
                            _buildMiniIconBtn(
                              icon: LucideIcons.plus,
                              color: const Color(0xFF00F2FE),
                              tooltip: 'Добавить в индекс (Stage)',
                              onTap: () => notifier.stageFile(f),
                            ),
                          ],
                        );
                      }),
                      if (workingFiles.length > 150)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          child: Text(
                            'Показано 150 из ${workingFiles.length} файлов. Добавьте build/ и .dart_tool/ в .gitignore',
                            style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCleanWorkingTreeView(GitStatus status, GitNotifier notifier, bool isLight) {
    final subColor = isLight ? Colors.black54 : Colors.white54;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.check_check, size: 28, color: Colors.greenAccent),
            ),
            const SizedBox(height: 10),
            Text(
              'Рабочая копия чиста',
              style: TextStyle(
                color: isLight ? Colors.black87 : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Все изменения на ветке «${status.currentBranch}» сохранены в Git.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 11),
            ),
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
                    label: Text('Отправить ${status.ahead} коммит(ов) в Remote'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F2FE),
                      foregroundColor: Colors.black,
                    ),
                  ),
                if (status.behind > 0)
                  ElevatedButton.icon(
                    onPressed: () => notifier.pull(),
                    icon: const Icon(LucideIcons.cloud_download, size: 14),
                    label: Text('Скачать ${status.behind} коммит(ов) (Pull)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                if (status.stashes.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => notifier.stashPop(),
                    icon: const Icon(LucideIcons.archive_restore, size: 14, color: Colors.orangeAccent),
                    label: Text(
                      'Восстановить Stash (${status.stashes.length})',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleHeader({
    required String title,
    required Color color,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: Colors.white.withValues(alpha: 0.02),
        child: Row(
          children: [
            Icon(
              expanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ?trailing,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(LucideIcons.file_code, size: 16, color: Color(0xFF00F2FE)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.eye, color: Color(0xFF00F2FE), size: 18),
                title: const Text('Просмотреть изменения (Diff)', style: TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFileDiff(file, isStaged: isStaged);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.pencil, color: Colors.white70, size: 18),
                title: const Text('Открыть в редакторе кода', style: TextStyle(color: Colors.white, fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFileInEditor(file);
                },
              ),
              if (isStaged)
                ListTile(
                  dense: true,
                  leading: const Icon(LucideIcons.circle_minus, color: Colors.orangeAccent, size: 18),
                  title: const Text('Убрать из индекса (Unstage)', style: TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.unstageFile(file);
                  },
                )
              else
                ListTile(
                  dense: true,
                  leading: const Icon(LucideIcons.circle_plus, color: Color(0xFF00F2FE), size: 18),
                  title: const Text('Добавить в индекс (Stage)', style: TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.stageFile(file);
                  },
                ),
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.undo_2, color: Colors.redAccent, size: 18),
                title: const Text('Откатить изменения (Discard)', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                subtitle: const Text('Сбросить файл к состоянию последнего коммита', style: TextStyle(color: Colors.white38, fontSize: 10)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDiscardFile(file, notifier);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.eye_off, color: Colors.white54, size: 18),
                title: const Text('Добавить в .gitignore', style: TextStyle(color: Colors.white70, fontSize: 13)),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.addToGitignore(file);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(LucideIcons.copy, color: Colors.white54, size: 18),
                title: const Text('Скопировать относительный путь', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
    required String file,
    required String statusCode,
    required Color badgeColor,
    required GitFileDiffStats? stats,
    required bool isLight,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    required List<Widget> actions,
  }) {
    final fileName = p.basename(file);
    final dirName = p.dirname(file);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                statusCode,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isLight ? Colors.black87 : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dirName != '.')
                    Text(
                      dirName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isLight ? Colors.black45 : Colors.white38,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (stats != null && (stats.additions > 0 || stats.deletions > 0)) ...[
              if (stats.additions > 0)
                Text(
                  '+${stats.additions}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (stats.additions > 0 && stats.deletions > 0) const SizedBox(width: 4),
              if (stats.deletions > 0)
                Text(
                  '-${stats.deletions}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
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
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 13, color: color),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: ИСТОРИЯ КОММИТОВ (COMMIT LOG & INTERACTIVE INSPECTOR)
  // ===========================================================================

  Widget _buildHistoryTab(GitStatus status, GitNotifier notifier, bool isLight) {
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white54;

    final commits = status.recentCommits.where((c) {
      if (_commitFilter.isEmpty) return true;
      return c.message.toLowerCase().contains(_commitFilter) ||
          c.shortHash.toLowerCase().contains(_commitFilter) ||
          c.author.toLowerCase().contains(_commitFilter) ||
          c.refs.toLowerCase().contains(_commitFilter);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _commitSearchController,
                    style: TextStyle(fontSize: 11, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Поиск по коммитам, SHA, автору, тегам...',
                      hintStyle: TextStyle(fontSize: 11, color: subColor),
                      prefixIcon: Icon(LucideIcons.search, size: 13, color: subColor),
                      suffixIcon: _commitFilter.isNotEmpty
                          ? InkWell(
                              onTap: () => _commitSearchController.clear(),
                              child: Icon(LucideIcons.x, size: 12, color: subColor),
                            )
                          : null,
                      filled: true,
                      fillColor: isLight ? Colors.white : const Color(0xFF141824),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 30,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GitGraphPage()),
                    );
                  },
                  icon: const Icon(LucideIcons.git_graph, size: 13, color: Color(0xFF00F2FE)),
                  label: const Text('Graph', style: TextStyle(fontSize: 11, color: Color(0xFF00F2FE))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00F2FE)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                    style: TextStyle(color: subColor, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  itemCount: commits.length,
                  itemBuilder: (context, index) {
                    final c = commits[index];
                    final isHead = index == 0 && _commitFilter.isEmpty;
                    return InkWell(
                      onTap: () => _showCommitInspectorSheet(c, notifier),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isLight ? Colors.black12 : Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isHead ? const Color(0xFF00F2FE) : Colors.purpleAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00F2FE).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          c.shortHash,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            color: const Color(0xFF00F2FE),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (c.refs.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.amberAccent.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              c.refs,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.amberAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      Text(
                                        c.relativeTime,
                                        style: TextStyle(fontSize: 10, color: subColor),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    c.message,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    c.author,
                                    style: TextStyle(fontSize: 10, color: subColor),
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
    List<GitCommitFileEntry>? changedFiles;
    String? patchDiff;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121622),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              commit.shortHash,
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFF00F2FE),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${commit.author} • ${commit.relativeTime}',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.copy, size: 15, color: Colors.white70),
                            tooltip: 'Скопировать полный SHA',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: commit.hash));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('SHA скопирован в буфер обмена')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                            onPressed: () => Navigator.pop(modalCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        commit.message,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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
                            color: const Color(0xFF8B5CF6),
                            onTap: () {
                              Navigator.pop(modalCtx);
                              notifier.cherryPickCommit(commit.hash);
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.undo_2,
                            label: 'Revert (обратить)',
                            color: Colors.amberAccent,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              notifier.revertCommit(commit.hash);
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.git_branch_plus,
                            label: 'Ветка отсюда',
                            color: const Color(0xFF00F2FE),
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showCreateBranchDialog(notifier, fromRef: commit.shortHash);
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.tag,
                            label: 'Тег на коммит',
                            color: Colors.greenAccent,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showCreateTagDialog(notifier, commitHash: commit.hash);
                            },
                          ),
                          _buildModalActionBtn(
                            icon: LucideIcons.rotate_ccw,
                            label: 'Reset к коммиту...',
                            color: Colors.redAccent,
                            onTap: () {
                              Navigator.pop(modalCtx);
                              _showResetCommitDialog(commit, notifier);
                            },
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      // Changed files list & patch
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          children: [
                            Text(
                              'ЗАТРОНУТЫЕ ФАЙЛЫ (${changedFiles?.length ?? 0})',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (changedFiles == null)
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: LinearProgressIndicator(color: Color(0xFF00F2FE)),
                              )
                            else
                              ...changedFiles!.map(
                                (f) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 18,
                                        height: 18,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          f.status,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: f.status == 'A'
                                                ? Colors.greenAccent
                                                : f.status == 'D'
                                                    ? Colors.redAccent
                                                    : Colors.amberAccent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          f.path,
                                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            const Text(
                              'ПОЛНЫЙ DIFF КОММИТА',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: SelectableText(
                                patchDiff ?? 'Загрузка diff...',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10.5,
                                  color: Colors.white70,
                                  height: 1.35,
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
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 3: ВЕТКИ И STASH (BRANCHES & STASH MANAGER)
  // ===========================================================================

  Widget _buildBranchesAndStashTab(GitStatus status, GitNotifier notifier, bool isLight) {
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white54;

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // 1. LOCAL BRANCHES CARD
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ЛОКАЛЬНЫЕ ВЕТКИ (${status.branches.length})',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00F2FE),
                letterSpacing: 0.7,
              ),
            ),
            TextButton.icon(
              onPressed: () => _showCreateBranchDialog(notifier),
              icon: const Icon(LucideIcons.plus, size: 12, color: Color(0xFF00F2FE)),
              label: const Text('Новая ветка', style: TextStyle(fontSize: 11, color: Color(0xFF00F2FE))),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...status.branches.map((b) {
          final isCurrent = b == status.currentBranch;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFF00F2FE).withValues(alpha: 0.1)
                  : (isLight ? Colors.white : const Color(0xFF141824)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFF00F2FE).withValues(alpha: 0.4)
                    : (isLight ? Colors.black12 : Colors.white10),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCurrent ? LucideIcons.circle_check : LucideIcons.git_branch,
                  size: 14,
                  color: isCurrent ? const Color(0xFF00F2FE) : subColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: isCurrent ? null : () => notifier.checkoutBranch(b),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: isCurrent ? const Color(0xFF00F2FE) : textColor,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        if (isCurrent)
                          Text(
                            'Активная ветка (HEAD)',
                            style: TextStyle(fontSize: 9.5, color: subColor),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!isCurrent) ...[
                  _buildMiniIconBtn(
                    icon: LucideIcons.git_merge,
                    color: Colors.purpleAccent,
                    tooltip: 'Влить $b в текущую ветку (${status.currentBranch})',
                    onTap: () => notifier.mergeBranch(b),
                  ),
                  _buildMiniIconBtn(
                    icon: LucideIcons.trash_2,
                    color: Colors.redAccent,
                    tooltip: 'Удалить ветку $b',
                    onTap: () => _confirmDeleteBranch(b, notifier),
                  ),
                ] else ...[
                  _buildMiniIconBtn(
                    icon: LucideIcons.pencil,
                    color: Colors.white54,
                    tooltip: 'Переименовать текущую ветку',
                    onTap: () => _showRenameBranchDialog(b, notifier),
                  ),
                ],
              ],
            ),
          );
        }),

        // 2. REMOTE BRANCHES
        if (status.remoteBranches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'УДАЛЁННЫЕ ВЕТКИ ORIGIN (${status.remoteBranches.length})',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: subColor,
                  letterSpacing: 0.7,
                ),
              ),
              InkWell(
                onTap: () => notifier.fetch(),
                child: const Text(
                  'Fetch',
                  style: TextStyle(fontSize: 10, color: Color(0xFF00F2FE), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...status.remoteBranches.map(
            (rb) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF141824),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: isLight ? Colors.black12 : Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.cloud, size: 13, color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rb,
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, color: textColor),
                    ),
                  ),
                  TextButton(
                    onPressed: () => notifier.checkoutBranch(rb),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Checkout', style: TextStyle(fontSize: 10, color: Color(0xFF00F2FE))),
                  ),
                ],
              ),
            ),
          ),
        ],

        // 3. STASH MANAGER
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STASH / ВРЕМЕННОЕ ХРАНИЛИЩЕ (${status.stashes.length})',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
                letterSpacing: 0.7,
              ),
            ),
            TextButton.icon(
              onPressed: status.hasChanges ? () => _showQuickStashDialog(status, notifier) : null,
              icon: const Icon(LucideIcons.archive, size: 12, color: Colors.orangeAccent),
              label: const Text('Спрятать в Stash', style: TextStyle(fontSize: 11, color: Colors.orangeAccent)),
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
              color: isLight ? Colors.white : const Color(0xFF141824),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isLight ? Colors.black12 : Colors.white10),
            ),
            child: Text(
              'Список Stash пуст. Stash позволяет временно отложить незакоммиченные правки, чтобы переключить ветку или сделать Pull.',
              style: TextStyle(fontSize: 11, color: subColor),
            ),
          )
        else
          ...status.stashes.map(
            (st) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          st.ref,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (st.branch.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          'на ${st.branch}',
                          style: TextStyle(fontSize: 10, color: subColor),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        st.relativeTime,
                        style: TextStyle(fontSize: 10, color: subColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    st.message,
                    style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildModalActionBtn(
                        icon: LucideIcons.eye,
                        label: 'Diff',
                        color: Colors.white70,
                        onTap: () => _showStashDiffModal(st, notifier),
                      ),
                      const SizedBox(width: 6),
                      _buildModalActionBtn(
                        icon: LucideIcons.copy_check,
                        label: 'Apply',
                        color: const Color(0xFF00F2FE),
                        onTap: () => notifier.stashApply(st.ref),
                      ),
                      const SizedBox(width: 6),
                      _buildModalActionBtn(
                        icon: LucideIcons.archive_restore,
                        label: 'Pop',
                        color: Colors.greenAccent,
                        onTap: () => notifier.stashPop(st.ref),
                      ),
                      const SizedBox(width: 6),
                      _buildModalActionBtn(
                        icon: LucideIcons.trash_2,
                        label: 'Drop',
                        color: Colors.redAccent,
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

  Widget _buildReleasesAndRemoteTab(GitStatus status, GitNotifier notifier, bool isLight) {
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white54;
    final ghService = GitHubService();
    final ghUserLogin = ghService.currentUser?['login']?.toString();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Remote & Author Configuration Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xFF141824),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isLight ? Colors.black12 : Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(LucideIcons.globe, size: 15, color: Color(0xFF00F2FE)),
                      SizedBox(width: 6),
                      Text(
                        'Удалённый репозиторий (Remote Origin)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00F2FE)),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => _showGitSettingsDialog(status, notifier),
                    icon: const Icon(LucideIcons.pencil, size: 12),
                    label: const Text('Изменить', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                status.remoteUrl ?? 'Remote origin не задан. Нажмите «Изменить», чтобы подключить GitHub URL.',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: status.remoteUrl != null ? textColor : Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.user, size: 12, color: subColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Автор: ${status.userName ?? "Quantum Developer"} <${status.userEmail ?? "dev@quantum-ide.local"}>',
                      style: TextStyle(fontSize: 11, color: subColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    ghService.isAuthenticated ? LucideIcons.shield_check : LucideIcons.key_round,
                    size: 12,
                    color: ghService.isAuthenticated ? Colors.greenAccent : Colors.amberAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ghService.isAuthenticated
                          ? 'GitHub авторизован${ghUserLogin != null ? ": @$ghUserLogin" : ""} (Push/Pull работает автоматически)'
                          : 'GitHub токен не подключён (нажмите для входа в GitHub)',
                      style: TextStyle(
                        fontSize: 11,
                        color: ghService.isAuthenticated ? Colors.greenAccent : Colors.amberAccent,
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
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('Войти', style: TextStyle(fontSize: 11)),
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
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                const Color(0xFF00F2FE).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.rocket, size: 16, color: Color(0xFF00F2FE)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Выпуск релиза и облачная сборка APK',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                    ),
                  ),
                  if (status.projectVersion != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F2FE).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'v${status.projectVersion}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: const Color(0xFF00F2FE),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Создаёт семантический Git-тег (vX.Y.Z) и пушит в GitHub для запуска GitHub Actions.',
                style: TextStyle(fontSize: 11, color: subColor),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showReleaseAndBuildModal(status, notifier),
                      icon: const Icon(LucideIcons.cloud_lightning, size: 14),
                      label: const Text('Выпустить релиз + APK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _showCreateTagDialog(notifier, status: status),
                    icon: const Icon(LucideIcons.tag, size: 13),
                    label: const Text('+ Тег', style: TextStyle(fontSize: 11)),
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
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: subColor,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        if (status.tags.isEmpty)
          Text('Теги ещё не созданы', style: TextStyle(fontSize: 11, color: subColor))
        else
          ...status.tags.map(
            (t) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF141824),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isLight ? Colors.black12 : Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.tag, size: 13, color: Colors.amberAccent),
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
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t.shortHash,
                              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: subColor),
                            ),
                          ],
                        ),
                        if (t.subject.isNotEmpty)
                          Text(
                            t.subject,
                            style: TextStyle(fontSize: 11, color: textColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Text(t.date, style: TextStyle(fontSize: 10, color: subColor)),
                  const SizedBox(width: 4),
                  _buildMiniIconBtn(
                    icon: LucideIcons.trash_2,
                    color: Colors.redAccent,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
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
                    const Text(
                      'Управление ветками',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCreateBranchDialog(notifier);
                      },
                      icon: const Icon(LucideIcons.plus, size: 13, color: Color(0xFF00F2FE)),
                      label: const Text('Создать ветку', style: TextStyle(color: Color(0xFF00F2FE), fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...status.branches.map((b) {
                        final isCurrent = b == status.currentBranch;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isCurrent ? LucideIcons.circle_check : LucideIcons.git_branch,
                            size: 16,
                            color: isCurrent ? const Color(0xFF00F2FE) : Colors.white54,
                          ),
                          title: Text(
                            b,
                            style: GoogleFonts.jetBrainsMono(
                              color: isCurrent ? const Color(0xFF00F2FE) : Colors.white,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          trailing: !isCurrent
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    notifier.mergeBranch(b);
                                  },
                                  child: const Text('Merge в текущую', style: TextStyle(fontSize: 11, color: Colors.purpleAccent)),
                                )
                              : const Text('HEAD', style: TextStyle(fontSize: 10, color: Color(0xFF00F2FE))),
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
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: Text(
          fromRef != null ? 'Новая ветка от $fromRef' : 'Создать новую ветку',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Например: feat/new-ui или fix/auth',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim().replaceAll(' ', '-');
              if (name.isNotEmpty) {
                notifier.checkoutBranch(name, createNew: true, fromRef: fromRef);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black),
            child: const Text('Создать и перейти'),
          ),
        ],
      ),
    );
  }

  void _showRenameBranchDialog(String oldName, GitNotifier notifier) {
    final ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Переименовать ветку', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final newName = ctrl.text.trim().replaceAll(' ', '-');
              if (newName.isNotEmpty && newName != oldName) {
                notifier.renameBranch(oldName, newName);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Переименовать'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBranch(String branch, GitNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: Text('Удалить ветку $branch?', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text(
          'Локальная ветка будет удалена.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.deleteBranch(branch, force: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showResetCommitDialog(GitCommitEntry commit, GitNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: Text('Reset к коммиту ${commit.shortHash}', style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(commit.message, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 12),
            _buildResetOptionTile(
              title: 'Soft (--soft)',
              subtitle: 'Переместить HEAD, но оставить все изменения в Индексе (Staged)',
              color: Colors.greenAccent,
              onTap: () {
                Navigator.pop(ctx);
                notifier.resetToCommit(commit.hash, mode: 'soft');
              },
            ),
            const SizedBox(height: 6),
            _buildResetOptionTile(
              title: 'Mixed (--mixed)',
              subtitle: 'Переместить HEAD и оставить файлы изменёнными в Рабочей копии',
              color: Colors.amberAccent,
              onTap: () {
                Navigator.pop(ctx);
                notifier.resetToCommit(commit.hash, mode: 'mixed');
              },
            ),
            const SizedBox(height: 6),
            _buildResetOptionTile(
              title: 'Hard (--hard)',
              subtitle: 'Полностью откатить код к этому коммиту (несохранённые правки удалятся!)',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(ctx);
                notifier.resetToCommit(commit.hash, mode: 'hard');
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        ],
      ),
    );
  }

  Widget _buildResetOptionTile({
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
            Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  void _showQuickStashDialog(GitStatus status, GitNotifier notifier) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Спрятать изменения в Stash', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Описание Stash (необязательно)...',
            hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.stashSave(ctrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            child: const Text('В Stash'),
          ),
        ],
      ),
    );
  }

  void _showStashDiffModal(GitStashEntry stash, GitNotifier notifier) async {
    final diff = await notifier.getStashDiff(stash.ref);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${stash.ref} — ${stash.message}',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 350),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  diff.isNotEmpty ? diff : 'Нет данных diff',
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white70),
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

    final tokenCtrl = TextEditingController(text: savedToken);
    final remoteCtrl = TextEditingController(text: status.remoteUrl ?? '');
    final nameCtrl = TextEditingController(text: status.userName ?? 'Quantum Developer');
    final emailCtrl = TextEditingController(text: status.userEmail ?? 'dev@quantum-ide.local');

    final wsPath = ref.read(workspaceProvider).currentPath;
    final defaultRepoName = wsPath != null ? p.basename(wsPath) : 'my-project';
    final newRepoNameCtrl = TextEditingController(text: defaultRepoName);
    final newRepoDescCtrl = TextEditingController(text: '');

    bool isCreatingNewRepo = (status.remoteUrl == null || status.remoteUrl!.isEmpty);
    bool isPrivateRepo = true; // Default to Private (закрытый) for user security
    bool isCreatingRepoNow = false;
    String? repoCreateError;

    bool obscureToken = true;
    bool isVerifyingToken = false;
    String? tokenVerifyStatus;
    Color tokenVerifyColor = Colors.white70;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ghService = GitHubService();
          return AlertDialog(
            backgroundColor: const Color(0xFF161922),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(LucideIcons.git_pull_request, color: Color(0xFF00F2FE), size: 18),
                SizedBox(width: 8),
                Text('Настройки Git и GitHub', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mode Switcher: Create New Repo on GitHub vs Existing Remote URL
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => isCreatingNewRepo = true),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCreatingNewRepo ? const Color(0xFF00F2FE).withValues(alpha: 0.18) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isCreatingNewRepo ? const Color(0xFF00F2FE) : Colors.transparent,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.circle_plus, size: 12, color: isCreatingNewRepo ? const Color(0xFF00F2FE) : Colors.white60),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Создать на GitHub',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isCreatingNewRepo ? const Color(0xFF00F2FE) : Colors.white60,
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
                              onTap: () => setDialogState(() => isCreatingNewRepo = false),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: !isCreatingNewRepo ? const Color(0xFF00F2FE).withValues(alpha: 0.18) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: !isCreatingNewRepo ? const Color(0xFF00F2FE) : Colors.transparent,
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.link, size: 12, color: !isCreatingNewRepo ? const Color(0xFF00F2FE) : Colors.white60),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Существующий URL',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: !isCreatingNewRepo ? const Color(0xFF00F2FE) : Colors.white60,
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
                        color: const Color(0xFF1C2230),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(LucideIcons.key_round, size: 14, color: Color(0xFF00F2FE)),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'GitHub Персональный токен (PAT):',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (ghService.isAuthenticated)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    '@${ghService.currentUser?['login'] ?? 'ok'}',
                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Нужен для отправки кода и создания репозиториев. Создаётся в GitHub Settings -> Developer Settings -> Personal access tokens (Classic) с правами repo и workflow.',
                            style: TextStyle(color: Colors.white54, fontSize: 10),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: tokenCtrl,
                            obscureText: obscureToken,
                            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
                            decoration: InputDecoration(
                              hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                              filled: true,
                              fillColor: Colors.black26,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(obscureToken ? LucideIcons.eye_off : LucideIcons.eye, size: 14, color: Colors.white54),
                                    onPressed: () => setDialogState(() => obscureToken = !obscureToken),
                                  ),
                                  IconButton(
                                    icon: const Icon(LucideIcons.clipboard, size: 14, color: Color(0xFF00F2FE)),
                                    tooltip: 'Вставить из буфера',
                                    onPressed: () async {
                                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                                      if (data?.text != null && data!.text!.trim().isNotEmpty) {
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
                                height: 26,
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
                                            final ok = await GitHubService().authenticateWithToken(t);
                                            setDialogState(() {
                                              isVerifyingToken = false;
                                              if (ok) {
                                                tokenVerifyStatus = '✓ Токен валиден (@${GitHubService().currentUser?['login'] ?? ''})';
                                                tokenVerifyColor = Colors.greenAccent;
                                              } else {
                                                tokenVerifyStatus = '⚠ Ошибка проверки токена';
                                                tokenVerifyColor = Colors.orangeAccent;
                                              }
                                            });
                                          } catch (e) {
                                            setDialogState(() {
                                              isVerifyingToken = false;
                                              tokenVerifyStatus = '✗ Ошибка: $e';
                                              tokenVerifyColor = Colors.redAccent;
                                            });
                                          }
                                        },
                                  icon: isVerifyingToken
                                      ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                      : const Icon(LucideIcons.shield_check, size: 12),
                                  label: const Text('Проверить токен', style: TextStyle(fontSize: 10)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF00F2FE),
                                    side: const BorderSide(color: Color(0xFF00F2FE), width: 0.8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (tokenVerifyStatus != null)
                                Expanded(
                                  child: Text(
                                    tokenVerifyStatus!,
                                    style: TextStyle(color: tokenVerifyColor, fontSize: 10, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 2: Either New Repo Creation or Existing Remote URL
                    if (isCreatingNewRepo) ...[
                      const Text('Название нового репозитория на GitHub:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: newRepoNameCtrl,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'my-project-name',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                          filled: true,
                          fillColor: Colors.black26,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Описание репозитория (необязательно):', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: newRepoDescCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Краткое описание проекта...',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                          filled: true,
                          fillColor: Colors.black26,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Доступ к репозиторию (Приватность):', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      // Two visual cards for Private vs Public
                      Row(
                        children: [
                          // Private Card (Закрытый)
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => isPrivateRepo = true),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isPrivateRepo ? Colors.amberAccent.withValues(alpha: 0.12) : Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isPrivateRepo ? Colors.amberAccent : Colors.white12,
                                    width: isPrivateRepo ? 1.5 : 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(LucideIcons.lock, size: 14, color: isPrivateRepo ? Colors.amberAccent : Colors.white54),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Приватный',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isPrivateRepo ? Colors.amberAccent : Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Закрыт от всех. Код виден только вам.',
                                      style: TextStyle(fontSize: 9.5, color: Colors.white54),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Public Card (Открытый)
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => isPrivateRepo = false),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: !isPrivateRepo ? const Color(0xFF00F2FE).withValues(alpha: 0.12) : Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: !isPrivateRepo ? const Color(0xFF00F2FE) : Colors.white12,
                                    width: !isPrivateRepo ? 1.5 : 0.8,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(LucideIcons.globe, size: 14, color: !isPrivateRepo ? const Color(0xFF00F2FE) : Colors.white54),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Публичный',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: !isPrivateRepo ? const Color(0xFF00F2FE) : Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Открыт для всех в интернете (open-source).',
                                      style: TextStyle(fontSize: 9.5, color: Colors.white54),
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
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      ],
                    ] else ...[
                      const Text('Удалённый репозиторий (Remote URL origin):', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: remoteCtrl,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'https://github.com/пользователь/репозиторий.git',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                          filled: true,
                          fillColor: Colors.black26,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                          suffixIcon: IconButton(
                            icon: const Icon(LucideIcons.clipboard, size: 14, color: Color(0xFF00F2FE)),
                            tooltip: 'Вставить из буфера',
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null && data!.text!.trim().isNotEmpty) {
                                remoteCtrl.text = data.text!.trim();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Section 3: Author info
                    const Text('Имя автора коммитов (user.name):', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Email автора коммитов (user.email):', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: emailCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.black26,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              if (isCreatingNewRepo)
                ElevatedButton.icon(
                  onPressed: isCreatingRepoNow
                      ? null
                      : () async {
                          final tokenText = tokenCtrl.text.trim();
                          if (tokenText.isNotEmpty) {
                            await GitHubService().authenticateWithToken(tokenText);
                          }
                          if (!GitHubService().isAuthenticated) {
                            setDialogState(() {
                              repoCreateError = 'Для создания репозитория необходимо ввести и проверить GitHub токен (PAT)';
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
                            final cloneUrl = res['clone_url']?.toString() ?? 'https://github.com/${res['full_name']}.git';
                            await notifier.setRemoteUrl(cloneUrl);
                            if (nameCtrl.text.trim().isNotEmpty && emailCtrl.text.trim().isNotEmpty) {
                              await notifier.setUserConfig(nameCtrl.text.trim(), emailCtrl.text.trim());
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            await notifier.push();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Репозиторий «$repoName» (${isPrivateRepo ? "Приватный" : "Публичный"}) успешно создан и отправлен на GitHub!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isCreatingRepoNow = false;
                              repoCreateError = GitHubService().lastError ?? 'Не удалось создать репозиторий на GitHub';
                            });
                          }
                        },
                  icon: isCreatingRepoNow
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.rocket, size: 14),
                  label: Text(isCreatingRepoNow ? 'Создание...' : '🚀 Создать и Push (${isPrivateRepo ? "Приватный" : "Публичный"})'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
                )
              else ...[
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final tokenText = tokenCtrl.text.trim();
                    if (tokenText.isNotEmpty) {
                      await GitHubService().authenticateWithToken(tokenText);
                    }
                    if (remoteCtrl.text.trim().isNotEmpty) {
                      await notifier.setRemoteUrl(remoteCtrl.text.trim());
                    }
                    if (nameCtrl.text.trim().isNotEmpty && emailCtrl.text.trim().isNotEmpty) {
                      await notifier.setUserConfig(nameCtrl.text.trim(), emailCtrl.text.trim());
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F2FE), foregroundColor: Colors.black),
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
                    if (nameCtrl.text.trim().isNotEmpty && emailCtrl.text.trim().isNotEmpty) {
                      await notifier.setUserConfig(nameCtrl.text.trim(), emailCtrl.text.trim());
                    }
                    await notifier.push();
                  },
                  icon: const Icon(LucideIcons.cloud_upload, size: 14),
                  label: const Text('Сохранить и Push'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _confirmForcePush(GitNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Выполнить Force Push?', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text(
          'Будет выполнен безопасный git push --force-with-lease (полезно после Amend или Reset).',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.push(force: true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Force Push'),
          ),
        ],
      ),
    );
  }

  void _confirmDiscardFile(String file, GitNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Откатить изменения в файле?', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: Text(
          'Все несохранённые правки в «$file» будут возвращены к последнему коммиту.',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.discardFile(file);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Откатить'),
          ),
        ],
      ),
    );
  }

  void _confirmDiscardAll(GitNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Откатить ВСЕ изменения?', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text(
          'Будет выполнен git reset --hard HEAD && git clean -fd. Все незакоммиченные правки будут удалены.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.discardAll();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Откатить всё'),
          ),
        ],
      ),
    );
  }

  void _showCreateTagDialog(GitNotifier notifier, {GitStatus? status, String? commitHash}) {
    final tagCtrl = TextEditingController(text: _suggestNextVersionTag(status, 'patch'));
    final msgCtrl = TextEditingController(text: 'Release');
    bool pushRemote = status?.remoteUrl != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161922),
          title: const Text('Создать тег версии', style: TextStyle(color: Colors.white, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tagCtrl,
                style: GoogleFonts.jetBrainsMono(color: Colors.amberAccent, fontSize: 13),
                decoration: const InputDecoration(labelText: 'Имя тега (например v1.0.1)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: msgCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: pushRemote,
                contentPadding: EdgeInsets.zero,
                title: const Text('Отправить тег в GitHub (git push --tags)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                onChanged: (v) => setDialogState(() => pushRemote = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
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
      final clean = latestTag.startsWith('v') ? latestTag.substring(1) : latestTag;
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
    final tagCtrl = TextEditingController(text: _suggestNextVersionTag(status, 'patch'));
    final notesCtrl = TextEditingController(
      text: _commitController.text.trim().isNotEmpty
          ? _commitController.text.trim()
          : 'Release ${ _suggestNextVersionTag(status, 'patch') }',
    );
    bool isReleasing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141824),
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
              const Text(
                'Выпуск релиза и сборка APK в GitHub Actions',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tagCtrl,
                style: GoogleFonts.jetBrainsMono(color: Colors.amberAccent, fontSize: 13),
                decoration: const InputDecoration(labelText: 'Тег релиза (vX.Y.Z)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(labelText: 'Описание релиза'),
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
                            commitMessage: 'chore(release): $tag — ${notesCtrl.text.trim()}',
                            releaseNotes: notesCtrl.text.trim(),
                          );
                          if (modalCtx.mounted) Navigator.pop(modalCtx);
                          final remote = status.remoteUrl;
                          if (remote != null && remote.contains('github.com')) {
                            var cleanUrl = remote.replaceAll('.git', '');
                            if (cleanUrl.startsWith('git@github.com:')) {
                              cleanUrl = cleanUrl.replaceFirst('git@github.com:', 'https://github.com/');
                            }
                            final uri = Uri.tryParse('$cleanUrl/actions');
                            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        } catch (_) {
                          if (modalCtx.mounted) setModalState(() => isReleasing = false);
                        }
                      },
                icon: const Icon(LucideIcons.rocket, size: 15),
                label: Text(isReleasing ? 'Отправка в GitHub...' : 'Закоммитить, создать тег и запустить сборку'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGitGuideModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141824),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => const Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.book_open, color: Color(0xFF00F2FE), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Как работает профессиональный Git в Quantum IDE',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                '1. Рабочая копия (Working Tree) → Индекс (Staged):\n'
                '   • Все изменённые (M) и новые (U) файлы появляются в разделе «Рабочая копия».\n'
                '   • Нажмите на файл, чтобы открыть визуальный Diff (сравнение было/стало).\n'
                '   • Нажмите «+» напротив нужных файлов, чтобы перенести их в «Индекс (Staged)» для точечного коммита.\n\n'
                '2. Коммит и Conventional Commits:\n'
                '   • Используйте быстрые префиксы (feat:, fix:, refactor:) или кнопку «✨ AI» для автогенерации описания по вашим правкам.\n'
                '   • Флажок «Amend» позволяет дополнить предыдущий коммит без создания нового.\n\n'
                '3. История, Cherry-pick, Revert и Reset:\n'
                '   • Во вкладке «История» нажмите на любой коммит — откроется Инспектор коммита со списком файлов, полным патчем и кнопками Cherry-pick, Revert, Reset (--soft/--mixed/--hard) и создания ветки.\n\n'
                '4. Ветки и Stash:\n'
                '   • Во вкладке «Ветки / Stash» вы можете переключать локальные и удалённые ветки, вливать (Merge) одну ветку в другую и управлять Stash-хранилищем.',
                style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoRepoView(GitNotifier notifier, bool isLight) {
    final textColor = isLight ? const Color(0xFF0F172A) : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white54;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.folder_git_2, size: 42, color: Color(0xFF00F2FE)),
            const SizedBox(height: 12),
            Text(
              'Git-репозиторий не инициализирован',
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Инициализируйте Git в текущем проекте, чтобы отслеживать изменения, управлять ветками и пушить на GitHub.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 11),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => notifier.init(),
              icon: const Icon(LucideIcons.plus, size: 15),
              label: const Text('Инициализировать Git (git init)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
