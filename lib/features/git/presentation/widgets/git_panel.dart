import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';

class SidebarGitPanel extends ConsumerStatefulWidget {
  const SidebarGitPanel({super.key});

  @override
  ConsumerState<SidebarGitPanel> createState() => _SidebarGitPanelState();
}

class _SidebarGitPanelState extends ConsumerState<SidebarGitPanel> {
  final TextEditingController _commitController = TextEditingController();

  @override
  void dispose() {
    _commitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gitState = ref.watch(gitProvider);
    final gitNotifier = ref.read(gitProvider.notifier);

    if (gitState.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    if (gitState.status == null) {
      return Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.15)),
                  ),
                  child: const Icon(LucideIcons.git_branch, color: Colors.amberAccent, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  'Репозиторий не найден',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Инициализируйте локальный Git-репозиторий для отслеживания изменений.',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => gitNotifier.init(),
                  icon: const Icon(LucideIcons.git_fork, size: 13),
                  label: const Text('Инициализировать Git'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent.withValues(alpha: 0.15),
                    foregroundColor: Colors.amberAccent,
                    elevation: 0,
                    side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
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
        // Git panel header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          child: Row(
            children: [
              const Icon(LucideIcons.git_branch, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                status.currentBranch,
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, size: 14, color: Colors.white38),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => gitNotifier.refreshStatus(),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => gitNotifier.refreshStatus(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (status.conflictedFiles.isNotEmpty) ...[
                  _buildGitSectionHeader('КОНФЛИКТЫ', status.conflictedFiles.length),
                  ...status.conflictedFiles.map((f) => _buildGitFileItem(f, isStaged: false, isConflicted: true)),
                ],
                if (status.stagedFiles.isNotEmpty) ...[
                  _buildGitSectionHeader('ИНДЕКСИРОВАНО', status.stagedFiles.length),
                  ...status.stagedFiles.map((f) => _buildGitFileItem(f, isStaged: true)),
                ],
                if (status.modifiedFiles.isNotEmpty) ...[
                  _buildGitSectionHeader('ИЗМЕНЕНО', status.modifiedFiles.length),
                  ...status.modifiedFiles.map((f) => _buildGitFileItem(f, isStaged: false)),
                ],
                if (status.untrackedFiles.isNotEmpty) ...[
                  _buildGitSectionHeader('НЕОТСЛЕЖИВАЕМОЕ', status.untrackedFiles.length),
                  ...status.untrackedFiles.map((f) => _buildGitFileItem(f, isStaged: false, isUntracked: true)),
                ],
                const SizedBox(height: 16),
                if (status.hasChanges) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.01),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _commitController,
                          decoration: InputDecoration(
                            hintText: 'Сообщение коммита...',
                            hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), 
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), 
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8), 
                              borderSide: const BorderSide(color: Colors.amberAccent, width: 0.8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                          onSubmitted: (msg) {
                            if (msg.isNotEmpty) {
                              gitNotifier.commit(msg);
                              _commitController.clear();
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => gitNotifier.push(),
                                icon: const Icon(LucideIcons.arrow_up, size: 13),
                                label: const Text('Push', style: TextStyle(fontSize: 11.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.15), 
                                  foregroundColor: Colors.blueAccent,
                                  elevation: 0,
                                  side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.25)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => gitNotifier.pull(),
                                icon: const Icon(LucideIcons.arrow_down, size: 13),
                                label: const Text('Pull', style: TextStyle(fontSize: 11.5)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent.withValues(alpha: 0.15), 
                                  foregroundColor: Colors.greenAccent,
                                  elevation: 0,
                                  side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.25)),
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
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGitSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Text(
            title, 
            style: GoogleFonts.inter(
              fontSize: 9.5, 
              color: Colors.white24, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05), 
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Text(
              '$count', 
              style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitFileItem(String path, {required bool isStaged, bool isUntracked = false, bool isConflicted = false}) {
    final notifier = ref.read(gitProvider.notifier);
    Color statusColor = isConflicted 
        ? Colors.redAccent 
        : (isStaged ? Colors.greenAccent : (isUntracked ? Colors.orangeAccent : Colors.amberAccent));
    
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: statusColor),
            Expanded(
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 10, right: 4),
                leading: Icon(
                  isConflicted
                      ? LucideIcons.git_pull_request
                      : (isUntracked ? LucideIcons.file_plus : LucideIcons.file_text),
                  size: 15,
                  color: statusColor,
                ),
                title: Text(
                  path.split('/').last, 
                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  path, 
                  style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: Colors.white24),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  if (isConflicted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GitMergeConflictPage(
                          relativePath: path,
                        ),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GitDiffPage(
                          relativePath: path,
                          initiallyStaged: isStaged,
                        ),
                      ),
                    );
                  }
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isStaged)
                      IconButton(
                        icon: const Icon(LucideIcons.circle_minus, size: 13, color: Colors.redAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => notifier.unstageFile(path),
                      )
                    else
                      IconButton(
                        icon: const Icon(LucideIcons.circle_plus, size: 13, color: Colors.greenAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => notifier.stageFile(path),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
