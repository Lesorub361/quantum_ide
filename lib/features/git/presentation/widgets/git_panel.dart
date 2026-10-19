import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/models/git_status.dart';
import 'package:quantum_ide/core/services/github_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_graph_page.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class SidebarGitPanel extends ConsumerStatefulWidget {
  final bool isBottomPanel;

  const SidebarGitPanel({
    super.key,
    this.isBottomPanel = false,
  });

  @override
  ConsumerState<SidebarGitPanel> createState() => _SidebarGitPanelState();
}

class _SidebarGitPanelState extends ConsumerState<SidebarGitPanel> {
  final TextEditingController _commitController = TextEditingController();
  int _selectedSection = 0; // 0: Изменения, 1: Коммиты, 2: Версии и сборки
  bool _amendCommit = false;
  bool _isBeginnerMode = true;
  bool _isGeneratingAiCommit = false;
  bool _isSyncing = false;
  bool _isFaqExpanded = false;

  @override
  void dispose() {
    _commitController.dispose();
    super.dispose();
  }

  Future<void> _generateAiCommitMessage(GitStatus status) async {
    final changedFiles = <String>[
      ...status.stagedFiles,
      ...status.modifiedFiles,
      ...status.untrackedFiles,
    ];
    if (changedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет изменённых файлов для анализа')),
      );
      return;
    }

    setState(() => _isGeneratingAiCommit = true);
    try {
      final prompt = 'Придумай лаконичное сообщение коммита Git на русском языке (максимум 5-8 слов, без кавычек и точек в конце, в стиле "добавлен экран настроек" или "исправлена ошибка валидации") для следующих измененных файлов:\n${changedFiles.take(15).join('\n')}';
      final completion = await ref.read(aiServiceProvider).getCompletion(prompt);
      final cleaned = completion.trim().replaceAll('"', '').replaceAll("'", '').split('\n').first.trim();
      if (cleaned.isNotEmpty) {
        _commitController.text = cleaned;
      } else {
        _commitController.text = 'Обновление проекта (${changedFiles.length} файлов)';
      }
    } catch (_) {
      _commitController.text = 'Обновление проекта (${changedFiles.length} файлов)';
    } finally {
      if (mounted) setState(() => _isGeneratingAiCommit = false);
    }
  }

  Future<void> _performBeginnerSync(GitNotifier gitNotifier, GitStatus status) async {
    if (!status.hasChanges && status.ahead == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все файлы уже сохранены и отправлены в Git!')),
      );
      return;
    }

    String msg = _commitController.text.trim();
    if (msg.isEmpty) {
      final total = status.totalChangesCount;
      msg = 'Обновление проекта ($total файлов)';
    }

    setState(() => _isSyncing = true);
    final scaffold = ScaffoldMessenger.of(context);

    try {
      if (status.hasChanges) {
        await gitNotifier.stageAll();
        await gitNotifier.commit(msg);
      }
      if (status.remoteUrl != null && status.remoteUrl!.isNotEmpty) {
        await gitNotifier.push();
      }
      _commitController.clear();
      scaffold.showSnackBar(
        const SnackBar(
          content: Text('🚀 Изменения успешно сохранены и отправлены в Git!'),
          backgroundColor: Color(0xFF238636),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text('Ошибка отправки: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _confirmRollbackAll(GitNotifier gitNotifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.triangle_alert, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Откатить все изменения?',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Text(
          'Вы действительно хотите отменить все несохранённые изменения и вернуть код к последнему коммиту?\n\nЭто действие безопасно вернет файлы в предыдущее сохранённое состояние.',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              gitNotifier.discardAll();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Все изменения отменены, код возвращен назад')),
              );
            },
            icon: const Icon(LucideIcons.rotate_ccw, size: 14),
            label: const Text('Да, откатить'),
          ),
        ],
      ),
    );
  }

  void _performCommit(GitNotifier gitNotifier) {
    final msg = _commitController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите сообщение коммита'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    gitNotifier.commit(msg, amend: _amendCommit);
    _commitController.clear();
    if (_amendCommit) {
      setState(() => _amendCommit = false);
    }
  }

  void _showBranchSwitcherDialog(BuildContext context, GitStatus status, GitNotifier notifier) {
    final newBranchCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141820),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(LucideIcons.git_branch, size: 18, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text(
              'Ветки Git (${status.currentBranch})',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: newBranchCtrl,
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Новая ветка (напр. feat/ui)...',
                        hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white30),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      final name = newBranchCtrl.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(ctx);
                        notifier.checkoutBranch(name, createNew: true);
                      }
                    },
                    icon: const Icon(LucideIcons.plus, size: 13),
                    label: const Text('Создать', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.2),
                      foregroundColor: Colors.cyanAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'ЛОКАЛЬНЫЕ ВЕТКИ',
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white38),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: status.branches.length,
                  itemBuilder: (_, idx) {
                    final b = status.branches[idx];
                    final isCurrent = b == status.currentBranch;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      leading: Icon(
                        isCurrent ? LucideIcons.circle_check : LucideIcons.git_branch,
                        size: 14,
                        color: isCurrent ? Colors.cyanAccent : Colors.white54,
                      ),
                      title: Text(
                        b,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: isCurrent ? Colors.cyanAccent : Colors.white,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onTap: isCurrent
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              notifier.checkoutBranch(b);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showCommitDetailsSheet(BuildContext context, GitCommitEntry commit, GitNotifier notifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return FutureBuilder<String>(
              future: notifier.getCommitDetails(commit.hash),
              builder: (context, snapshot) {
                final rawDiff = snapshot.data ?? '';
                final lines = rawDiff.split('\n');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              commit.shortHash,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.cyanAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  commit.message,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  '${commit.author} • ${commit.relativeTime}',
                                  style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.copy, size: 15, color: Colors.white54),
                            tooltip: 'Скопировать хэш',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: commit.hash));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Хэш ${commit.shortHash} скопирован')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: lines.length,
                              itemBuilder: (_, i) {
                                final line = lines[i];
                                Color textColor = Colors.white70;
                                Color? bgColor;
                                if (line.startsWith('+') && !line.startsWith('+++')) {
                                  textColor = const Color(0xFF4ADE80);
                                  bgColor = const Color(0xFF4ADE80).withValues(alpha: 0.08);
                                } else if (line.startsWith('-') && !line.startsWith('---')) {
                                  textColor = const Color(0xFFF87171);
                                  bgColor = const Color(0xFFF87171).withValues(alpha: 0.08);
                                } else if (line.startsWith('@@')) {
                                  textColor = Colors.cyanAccent;
                                  bgColor = Colors.cyanAccent.withValues(alpha: 0.06);
                                } else if (line.startsWith('diff --git')) {
                                  textColor = Colors.amberAccent;
                                }
                                return Container(
                                  color: bgColor,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  child: SelectableText(
                                    line,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: textColor,
                                      height: 1.35,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showCreateTagDialog(BuildContext context, GitStatus status, GitNotifier notifier) {
    final nextSuggested = status.projectVersion != null
        ? 'v${status.projectVersion!.split('+').first}'
        : (status.tags.isNotEmpty ? status.tags.first.name : 'v1.0.0');
    final tagCtrl = TextEditingController(text: nextSuggested);
    final msgCtrl = TextEditingController(text: 'Release $nextSuggested');
    bool pushRemote = status.remoteUrl != null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF141820),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(LucideIcons.tag, size: 18, color: Colors.amberAccent),
              const SizedBox(width: 8),
              Text(
                'Создать версию / тег релиза',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tagCtrl,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Версия (тег)',
                    labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                    hintText: 'v1.0.0',
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: msgCtrl,
                  maxLines: 2,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Описание сборки / изменений',
                    labelStyle: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: pushRemote,
                  onChanged: (v) => setDialogState(() => pushRemote = v ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.cyanAccent,
                  title: Text(
                    'Сразу отправить тег на GitHub (git push --tags)',
                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton.icon(
              onPressed: () {
                final t = tagCtrl.text.trim();
                if (t.isNotEmpty) {
                  Navigator.pop(ctx);
                  notifier.createVersionTag(t, msgCtrl.text.trim(), pushToRemote: pushRemote);
                }
              },
              icon: const Icon(LucideIcons.check, size: 14),
              label: const Text('Создать тег'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gitState = ref.watch(gitProvider);
    final gitNotifier = ref.read(gitProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    if (gitState.isLoading && gitState.status == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    if (gitState.status == null) {
      return Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(LucideIcons.git_branch, color: Colors.amberAccent, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.repositoryNotFound,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.initGitRepoDescription,
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 11, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => gitNotifier.init(),
                      icon: const Icon(LucideIcons.git_fork, size: 13),
                      label: Text(l10n.initGitAction),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent.withValues(alpha: 0.15),
                        foregroundColor: Colors.amberAccent,
                        elevation: 0,
                        side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/github'),
                      icon: const Icon(LucideIcons.folder_git_2, size: 13),
                      label: const Text('GitHub Клон / Вход'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

    final status = gitState.status!;

    return Column(
      children: [
        // Top Header: Branch switcher, ahead/behind indicators, quick actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF10131A),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => _showBranchSwitcherDialog(context, status, gitNotifier),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.git_branch, size: 12, color: Colors.cyanAccent),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          status.currentBranch,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (status.ahead > 0 || status.behind > 0) ...[
                        const SizedBox(width: 5),
                        Text(
                          '${status.ahead > 0 ? "↑${status.ahead}" : ""}${status.behind > 0 ? "↓${status.behind}" : ""}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amberAccent,
                          ),
                        ),
                      ],
                      const SizedBox(width: 3),
                      const Icon(LucideIcons.chevron_down, size: 11, color: Colors.cyanAccent),
                    ],
                  ),
                ),
              ),
              if (status.projectVersion != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'v${status.projectVersion}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFC084FC),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (gitState.isLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.cyanAccent),
                  ),
                ),
              IconButton(
                icon: const Icon(LucideIcons.git_commit_horizontal, size: 14, color: Colors.amberAccent),
                tooltip: 'Граф коммитов (Git Graph)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GitGraphPage()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(LucideIcons.folder_git_2, size: 14, color: Colors.cyanAccent),
                tooltip: 'GitHub репозитории и клонирование',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => context.push('/github'),
              ),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, size: 13, color: Colors.white54),
                tooltip: 'Обновить Git',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => gitNotifier.refreshStatus(force: true),
              ),
            ],
          ),
        ),

        // Segmented Navigation Tabs: Изменения | Коммиты | Версии и Сборки
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          color: const Color(0xFF0B0D13),
          child: Row(
            children: [
              _buildSectionTab(
                index: 0,
                icon: LucideIcons.file_diff,
                label: 'Изменения',
                badge: '${status.totalChangesCount}',
              ),
              const SizedBox(width: 5),
              _buildSectionTab(
                index: 1,
                icon: LucideIcons.history,
                label: 'Коммиты',
                badge: '${status.recentCommits.length}',
              ),
              const SizedBox(width: 5),
              _buildSectionTab(
                index: 2,
                icon: LucideIcons.tag,
                label: 'Сборки/Версии',
                badge: '${status.tags.length}',
              ),
            ],
          ),
        ),

        if (gitState.error != null && gitState.error!.trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: Colors.redAccent.withValues(alpha: 0.14),
            child: Text(
              gitState.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10.5, color: Colors.redAccent),
            ),
          ),

        const Divider(color: Colors.white10, height: 1),

        // Tab Body
        Expanded(
          child: IndexedStack(
            index: _selectedSection,
            children: [
              _buildChangesTab(context, status, gitNotifier, l10n),
              _buildCommitsTab(context, status, gitNotifier),
              _buildVersionsTab(context, status, gitNotifier, l10n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTab({
    required int index,
    required IconData icon,
    required String label,
    required String badge,
  }) {
    final isSelected = _selectedSection == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedSection = index),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.cyanAccent.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: isSelected
                  ? Colors.cyanAccent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 12,
                color: isSelected ? Colors.cyanAccent : Colors.white54,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.white60,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.cyanAccent.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.cyanAccent : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isBeginnerMode = true),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _isBeginnerMode ? Colors.cyanAccent.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: _isBeginnerMode ? Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.smile, size: 13, color: Colors.cyanAccent),
                    const SizedBox(width: 5),
                    Text(
                      'Простой (Новичок)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: _isBeginnerMode ? FontWeight.bold : FontWeight.normal,
                        color: _isBeginnerMode ? Colors.white : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _isBeginnerMode = false),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !_isBeginnerMode ? Colors.amberAccent.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: !_isBeginnerMode ? Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)) : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.sliders_horizontal, size: 13, color: Colors.amberAccent),
                    const SizedBox(width: 5),
                    Text(
                      'Эксперт (Git Pro)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: !_isBeginnerMode ? FontWeight.bold : FontWeight.normal,
                        color: !_isBeginnerMode ? Colors.white : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeginnerChangesTab(
    BuildContext context,
    GitStatus status,
    GitNotifier gitNotifier,
    AppLocalizations l10n,
  ) {
    final changedCount = status.totalChangesCount;
    final hasChanges = status.hasChanges;

    return RefreshIndicator(
      onRefresh: () => gitNotifier.refreshStatus(force: true),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          _buildModeSwitcher(),
          const SizedBox(height: 10),

          // Status Summary Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasChanges
                  ? Colors.amberAccent.withValues(alpha: 0.08)
                  : Colors.greenAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasChanges
                    ? Colors.amberAccent.withValues(alpha: 0.25)
                    : Colors.greenAccent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasChanges
                        ? Colors.amberAccent.withValues(alpha: 0.15)
                        : Colors.greenAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    hasChanges ? LucideIcons.file_pen : LucideIcons.circle_check,
                    size: 20,
                    color: hasChanges ? Colors.amberAccent : Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasChanges
                            ? 'Есть несохранённые изменения: $changedCount файлов'
                            : 'Все файлы сохранены в Git',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Ветка: ${status.currentBranch}${status.ahead > 0 ? " (к отправке: ↑${status.ahead})" : ""}${status.behind > 0 ? " (на GitHub: ↓${status.behind})" : ""}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action Card 1: Сохранить и отправить (Commit & Push)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                  const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(LucideIcons.rocket, size: 16, color: Colors.cyanAccent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '1. Сохранить и отправить в Git',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Главное действие',
                        style: GoogleFonts.inter(fontSize: 9.5, color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Сохраняет все изменённые файлы и отправляет их на GitHub в один клик, чтобы ваш код был в безопасности.',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _commitController,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Что вы изменили? (например: добавил кнопку, исправил баг)',
                    hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white30),
                    filled: true,
                    fillColor: Colors.black38,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isGeneratingAiCommit ? null : () => _generateAiCommitMessage(status),
                      icon: _isGeneratingAiCommit
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.cyanAccent),
                            )
                          : const Icon(LucideIcons.sparkles, size: 13),
                      label: Text(
                        _isGeneratingAiCommit ? 'ИИ...' : '✨ Сообщение через ИИ',
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.35)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSyncing ? null : () => _performBeginnerSync(gitNotifier, status),
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(LucideIcons.send, size: 14),
                        label: Text(
                          _isSyncing ? 'Отправка...' : 'Отправить в Git',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF238636),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Action Card 2 & 3: Откатить & Обновить
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.rotate_ccw, size: 13, color: Colors.redAccent),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '2. Откатить всё',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Вернуть код к предыдущему сохранению.',
                        style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white54),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: hasChanges ? () => _confirmRollbackAll(gitNotifier) : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          ),
                          child: const Text('Откатить', style: TextStyle(fontSize: 10.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.arrow_down, size: 13, color: Colors.blueAccent),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '3. Обновить (Pull)',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Скачать свежий код с GitHub.',
                        style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white54),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => gitNotifier.pull(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                            side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          ),
                          child: Text(status.behind > 0 ? 'Скачать (${status.behind})' : 'Обновить', style: const TextStyle(fontSize: 10.5)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Action Card 4: Собрать APK
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(LucideIcons.package_check, color: Colors.amberAccent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '4. Собрать релизный APK',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Ключ release-key.jks настроен: установится прямо поверх старого!',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: () => _showCloudBuildDialog(context),
                  icon: const Icon(LucideIcons.rocket, size: 12),
                  label: const Text('Собрать', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // File List
          Row(
            children: [
              Text(
                'ИЗМЕНЁННЫЕ ФАЙЛЫ ($changedCount)',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (hasChanges)
                InkWell(
                  onTap: () => _confirmRollbackAll(gitNotifier),
                  child: Text(
                    'Откатить все',
                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          if (!hasChanges)
            Container(
              padding: const EdgeInsets.all(14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '🎉 Нет изменений. Все файлы сохранены в Git!',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
              ),
            ),

          if (status.conflictedFiles.isNotEmpty) ...[
            _buildBeginnerCategoryHeader('⚠️ Конфликты версий', status.conflictedFiles.length, Colors.redAccent),
            ...status.conflictedFiles.map((f) => _buildBeginnerFileRow(f, status, isConflicted: true)),
          ],
          if (status.modifiedFiles.isNotEmpty || status.stagedFiles.isNotEmpty) ...[
            _buildBeginnerCategoryHeader('🔵 Отредактированные файлы', status.modifiedFiles.length + status.stagedFiles.length, Colors.cyanAccent),
            ...status.modifiedFiles.map((f) => _buildBeginnerFileRow(f, status)),
            ...status.stagedFiles.map((f) => _buildBeginnerFileRow(f, status)),
          ],
          if (status.untrackedFiles.isNotEmpty) ...[
            _buildBeginnerCategoryHeader('🟢 Новые файлы', status.untrackedFiles.length, Colors.greenAccent),
            ...status.untrackedFiles.map((f) => _buildBeginnerFileRow(f, status, isUntracked: true)),
          ],

          const SizedBox(height: 14),
          _buildBeginnerFaqCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBeginnerFileRow(String path, GitStatus status, {bool isUntracked = false, bool isConflicted = false}) {
    final notifier = ref.read(gitProvider.notifier);
    final cleanPath = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final fileName = cleanPath.split('/').last;
    final parentDir = cleanPath.contains('/') ? cleanPath.substring(0, cleanPath.lastIndexOf('/')) : '';
    final diffStat = status.diffStats[cleanPath] ?? status.diffStats[path];

    final Color statusColor = isConflicted
        ? Colors.redAccent
        : (isUntracked ? Colors.greenAccent : Colors.cyanAccent);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
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
                        fileName,
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (diffStat != null && (diffStat.additions > 0 || diffStat.deletions > 0)) ...[
                      const SizedBox(width: 5),
                      if (diffStat.additions > 0)
                        Text('+${diffStat.additions}', style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                      if (diffStat.deletions > 0) ...[
                        const SizedBox(width: 3),
                        Text('-${diffStat.deletions}', style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ],
                ),
                Text(
                  parentDir.isNotEmpty ? parentDir : cleanPath,
                  style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white38),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => GitDiffPage(relativePath: cleanPath, initiallyStaged: false),
                ),
              );
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.file_diff, size: 11, color: Colors.cyanAccent),
                  const SizedBox(width: 3),
                  Text('Diff', style: GoogleFonts.inter(fontSize: 9.5, color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(LucideIcons.rotate_ccw, size: 12, color: Colors.redAccent),
            tooltip: 'Откатить этот файл назад',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () {
              notifier.discardFile(path);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Файл $fileName возвращён к исходному состоянию')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBeginnerCategoryHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeginnerFaqCard() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isFaqExpanded = !_isFaqExpanded),
            child: Row(
              children: [
                const Icon(LucideIcons.circle_question_mark, size: 15, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 Как работает Git? (Понятный справочник)',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                Icon(
                  _isFaqExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                  size: 13,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
          if (_isFaqExpanded) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            _buildFaqItem('Что такое коммит?', 'Коммит — это сохранение вашей работы (как точка сохранения в видеоигре). Если в будущем что-то сломается, вы всегда сможете вернуться к этому моменту.'),
            _buildFaqItem('Зачем нужен Push?', 'Push отправляет ваши сохранения из памяти телефона/ПК на сервер GitHub. Даже если телефон потеряется, код останется в безопасности.'),
            _buildFaqItem('Что делает Откат (Discard)?', 'Откат отменяет все последние изменения и возвращает код в точности к предыдущему коммиту.'),
            _buildFaqItem('Как обновлять приложение на телефоне?', 'Благодаря единому ключу release-key.jks, который мы настроили в вашем проекте, каждая новая сборка APK может быть установлена прямо поверх старой, без удаления и без потери ваших данных!'),
          ],
        ],
      ),
    );
  }

  Widget _buildFaqItem(String q, String a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
          const SizedBox(height: 2),
          Text(a, style: GoogleFonts.inter(fontSize: 10, color: Colors.white70, height: 1.35)),
        ],
      ),
    );
  }

  Widget _buildChangesTab(
    BuildContext context,
    GitStatus status,
    GitNotifier gitNotifier,
    AppLocalizations l10n,
  ) {
    if (_isBeginnerMode) {
      return _buildBeginnerChangesTab(context, status, gitNotifier, l10n);
    }

    return RefreshIndicator(
      onRefresh: () => gitNotifier.refreshStatus(force: true),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          _buildModeSwitcher(),
          const SizedBox(height: 10),
          // Commit & Sync Control Box (always visible!)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141822),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _commitController,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: l10n.commitMessageHint,
                    hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.28),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.cyanAccent, width: 0.9),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  onSubmitted: (_) => _performCommit(gitNotifier),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: () => _performCommit(gitNotifier),
                        icon: const Icon(LucideIcons.check, size: 13),
                        label: Text(
                          _amendCommit ? 'Amend Коммит' : 'Закоммитить',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.withValues(alpha: 0.18),
                          foregroundColor: Colors.cyanAccent,
                          elevation: 0,
                          side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.35)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() => _amendCommit = !_amendCommit),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        decoration: BoxDecoration(
                          color: _amendCommit
                              ? Colors.amberAccent.withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _amendCommit
                                ? Colors.amberAccent.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          'Amend',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _amendCommit ? Colors.amberAccent : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => gitNotifier.push(),
                        icon: const Icon(LucideIcons.arrow_up, size: 12),
                        label: Text(
                          status.ahead > 0 ? 'Push (${status.ahead})' : 'Push',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                          foregroundColor: Colors.blueAccent,
                          elevation: 0,
                          side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.28)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => gitNotifier.pull(),
                        icon: const Icon(LucideIcons.arrow_down, size: 12),
                        label: Text(
                          status.behind > 0 ? 'Pull (${status.behind})' : 'Pull',
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent.withValues(alpha: 0.15),
                          foregroundColor: Colors.greenAccent,
                          elevation: 0,
                          side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.28)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(LucideIcons.archive, size: 14, color: Colors.white60),
                      tooltip: 'Спрятать изменения в Stash',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                      ),
                      onPressed: () => gitNotifier.stashSave(),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Quick Bulk Actions Bar
          if (status.hasChanges)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    'ФАЙЛЫ (${status.totalChangesCount})',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  _buildMiniActionChip(
                    icon: LucideIcons.plus,
                    label: 'Все в Stage',
                    color: Colors.greenAccent,
                    onTap: () => gitNotifier.stageAll(),
                  ),
                  const SizedBox(width: 6),
                  if (status.stagedFiles.isNotEmpty)
                    _buildMiniActionChip(
                      icon: LucideIcons.minus,
                      label: 'Снять все',
                      color: Colors.amberAccent,
                      onTap: () => gitNotifier.unstageAll(),
                    ),
                ],
              ),
            ),

          if (!status.hasChanges)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(LucideIcons.circle_check, size: 28, color: Colors.greenAccent.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  Text(
                    'Рабочая директория чиста',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Нет незакоммиченных изменений. Перейдите во вкладку «Коммиты» для просмотра истории.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white38),
                  ),
                ],
              ),
            ),

          if (status.conflictedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitConflicted, status.conflictedFiles.length, Colors.redAccent),
            ...status.conflictedFiles.map(
              (f) => _buildGitFileItem(f, status: status, isStaged: false, isConflicted: true),
            ),
          ],
          if (status.stagedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitStaged, status.stagedFiles.length, Colors.greenAccent),
            ...status.stagedFiles.map(
              (f) => _buildGitFileItem(f, status: status, isStaged: true),
            ),
          ],
          if (status.modifiedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitModified, status.modifiedFiles.length, Colors.amberAccent),
            ...status.modifiedFiles.map(
              (f) => _buildGitFileItem(f, status: status, isStaged: false),
            ),
          ],
          if (status.untrackedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitUntracked, status.untrackedFiles.length, Colors.orangeAccent),
            ...status.untrackedFiles.map(
              (f) => _buildGitFileItem(f, status: status, isStaged: false, isUntracked: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommitsTab(BuildContext context, GitStatus status, GitNotifier gitNotifier) {
    if (status.recentCommits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'В репозитории пока нет коммитов.\nСделайте первый коммит во вкладке «Изменения».',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white54),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => gitNotifier.refreshStatus(force: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: status.recentCommits.length,
        itemBuilder: (context, index) {
          final commit = status.recentCommits[index];
          final isHead = index == 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isHead
                  ? Colors.cyanAccent.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isHead
                    ? Colors.cyanAccent.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: InkWell(
              onTap: () => _showCommitDetailsSheet(context, commit, gitNotifier),
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            commit.shortHash,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                        if (commit.refs.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                commit.refs,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amberAccent,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          commit.relativeTime,
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      commit.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(LucideIcons.user, size: 10, color: Colors.white38),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            commit.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.white54),
                          ),
                        ),
                        Text(
                          'Открыть diff →',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            color: Colors.cyanAccent.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVersionsTab(
    BuildContext context,
    GitStatus status,
    GitNotifier gitNotifier,
    AppLocalizations l10n,
  ) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Current Project Build Version Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                const Color(0xFF0EA5E9).withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.package_check, size: 16, color: Color(0xFFC084FC)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Версия сборки проекта',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.projectVersion ?? '1.0.0+1',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                status.recentCommits.isNotEmpty
                    ? 'Последний коммит сборки: ${status.recentCommits.first.shortHash} (${status.recentCommits.first.message})'
                    : 'Коммитов ещё нет',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white60),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showCreateTagDialog(context, status, gitNotifier),
                      icon: const Icon(LucideIcons.tag, size: 13),
                      label: const Text('Создать версию (Tag)', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent.withValues(alpha: 0.16),
                        foregroundColor: Colors.cyanAccent,
                        elevation: 0,
                        side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showCloudBuildDialog(context),
                      icon: const Icon(LucideIcons.rocket, size: 13),
                      label: Text(
                        l10n.cloudBuildApk,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent.withValues(alpha: 0.16),
                        foregroundColor: Colors.amberAccent,
                        elevation: 0,
                        side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.35)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Text(
          'ИСТОРИЯ ВЕРСИЙ И РЕЛИЗОВ (${status.tags.length})',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white38,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),

        if (status.tags.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Text(
              'Теги версий (например v1.0.0, v1.1.0) пока не созданы.\nНажмите «Создать версию (Tag)» выше, чтобы зафиксировать версию сборки.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
            ),
          )
        else
          ...status.tags.map((tag) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.tag, size: 14, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tag.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amberAccent,
                              ),
                            ),
                            if (tag.shortHash.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '(${tag.shortHash})',
                                style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white38),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              tag.date,
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                            ),
                          ],
                        ),
                        if (tag.subject.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tag.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.trash_2, size: 13, color: Colors.redAccent),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Удалить тег',
                    onPressed: () => gitNotifier.deleteTag(tag.name),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMiniActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGitSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 5),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              color: Colors.white54,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitFileItem(
    String path, {
    required GitStatus status,
    required bool isStaged,
    bool isUntracked = false,
    bool isConflicted = false,
  }) {
    final notifier = ref.read(gitProvider.notifier);
    final Color statusColor = isConflicted
        ? Colors.redAccent
        : (isStaged ? Colors.greenAccent : (isUntracked ? Colors.orangeAccent : Colors.amberAccent));
    final cleanPath = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final fileName = cleanPath.split('/').last;
    final parentDir = cleanPath.contains('/') ? cleanPath.substring(0, cleanPath.lastIndexOf('/')) : '';
    final diffStat = status.diffStats[cleanPath] ?? status.diffStats[path];

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isConflicted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => GitMergeConflictPage(relativePath: cleanPath),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => GitDiffPage(
                  relativePath: cleanPath,
                  initiallyStaged: isStaged,
                ),
              ),
            );
          }
        },
        child: Row(
          children: [
            Container(width: 3, height: 38, color: statusColor),
            const SizedBox(width: 8),
            Icon(
              isConflicted
                  ? LucideIcons.git_pull_request
                  : (isUntracked ? LucideIcons.file_plus : LucideIcons.file_code),
              size: 14,
              color: statusColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (diffStat != null && (diffStat.additions > 0 || diffStat.deletions > 0)) ...[
                          const SizedBox(width: 6),
                          if (diffStat.additions > 0)
                            Text(
                              '+${diffStat.additions}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          if (diffStat.deletions > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              '-${diffStat.deletions}',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    Text(
                      parentDir.isNotEmpty ? parentDir : cleanPath,
                      style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: Colors.white38),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            if (!isStaged)
              IconButton(
                icon: const Icon(LucideIcons.rotate_ccw, size: 12, color: Colors.white38),
                tooltip: 'Откатить изменения файла',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => notifier.discardFile(path),
              ),
            IconButton(
              icon: Icon(
                isStaged ? LucideIcons.circle_minus : LucideIcons.circle_plus,
                size: 14,
                color: isStaged ? Colors.amberAccent : Colors.greenAccent,
              ),
              tooltip: isStaged ? 'Убрать из индекса (Unstage)' : 'Добавить в коммит (Stage)',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => isStaged ? notifier.unstageFile(path) : notifier.stageFile(path),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  void _showCloudBuildDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tagController = TextEditingController(text: 'v1.0.0');
    final commitController = TextEditingController(text: 'chore: release v1.0.0');
    final notesController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.rocket, color: Colors.amberAccent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.cloudBuildApk,
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.cloudBuildApkDesc,
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.releaseTagName,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: tagController,
                      enabled: !isSubmitting,
                      style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.releaseTagNameHint,
                        hintStyle: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white24),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.releaseCommitMsg,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: commitController,
                      enabled: !isSubmitting,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.releaseCommitMsgHint,
                        hintStyle: GoogleFonts.inter(fontSize: 11.5, color: Colors.white24),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.releaseNotes,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      enabled: !isSubmitting,
                      maxLines: 4,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.releaseNotesHint,
                        hintStyle: GoogleFonts.inter(fontSize: 11.5, color: Colors.white24),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.3),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                    if (isSubmitting) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              l10n.releasingAndPushing,
                              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.amberAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                child: Text(AppLocalizations.of(context)!.cancel, style: const TextStyle(color: Colors.white60)),
              ),
              FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final tag = tagController.text.trim();
                        if (tag.isEmpty) return;

                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        setDialogState(() => isSubmitting = true);

                        try {
                          final currentWorkspace = ref.read(workspaceProvider).currentPath;
                          if (currentWorkspace != null) {
                            await GitHubService().setupCloudApkWorkflow(currentWorkspace);
                          }

                          await ref.read(gitProvider.notifier).releaseAndBuildApk(
                                tagName: tag,
                                commitMessage: commitController.text.trim(),
                                releaseNotes: notesController.text.trim(),
                              );

                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }

                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.releaseTriggeredSuccess(tag)),
                              backgroundColor: const Color(0xFF238636),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.releaseTriggerFailed(e.toString())),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                icon: const Icon(LucideIcons.send, size: 14),
                label: Text(l10n.publishReleaseBtn),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF238636),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


