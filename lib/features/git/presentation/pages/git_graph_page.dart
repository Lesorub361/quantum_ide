import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';

class GitCommitItem {
  final String hash;
  final List<String> parentHashes;
  final String refs;
  final String message;
  final String author;
  final String relativeDate;
  final int laneIndex;

  const GitCommitItem({
    required this.hash,
    required this.parentHashes,
    required this.refs,
    required this.message,
    required this.author,
    required this.relativeDate,
    required this.laneIndex,
  });
}

class GitGraphPage extends ConsumerStatefulWidget {
  final String? projectPath;

  const GitGraphPage({super.key, this.projectPath});

  @override
  ConsumerState<GitGraphPage> createState() => _GitGraphPageState();
}

class _GitGraphPageState extends ConsumerState<GitGraphPage> {
  final TextEditingController _searchController = TextEditingController();
  List<GitCommitItem> _allCommits = [];
  List<GitCommitItem> _filteredCommits = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _currentBranch = 'main';

  final List<Color> _laneColors = const [
    Color(0xFF00F2FE), // Cyan
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF43F5E), // Rose
    Color(0xFF38BDF8), // Sky
    Color(0xFFA855F7), // Violet
  ];

  @override
  void initState() {
    super.initState();
    _loadGitLog();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() => _filteredCommits = _allCommits);
    } else {
      setState(() {
        _filteredCommits = _allCommits.where((c) {
          return c.message.toLowerCase().contains(query) ||
              c.author.toLowerCase().contains(query) ||
              c.hash.toLowerCase().contains(query) ||
              c.refs.toLowerCase().contains(query);
        }).toList();
      });
    }
  }

  Future<String> _resolveGuestRepoPath() async {
    final hostPath = widget.projectPath ?? ref.read(workspaceProvider).currentPath ?? '/root/projects/quantum_ide';
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  Future<void> _loadGitLog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final guestPath = await _resolveGuestRepoPath();
      final runtime = ref.read(runtimeServiceProvider);

      final rawOut = await runtime.runCommand(
        'cd "$guestPath" 2>/dev/null && '
        'echo "__BRANCH__" && '
        '(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main") && '
        'echo "__LOG__" && '
        'git log --all -n 120 --format="format:%h\t%p\t%D\t%s\t%an\t%cr" 2>/dev/null',
      );

      if (!rawOut.contains('__LOG__')) {
        throw Exception('Не удалось прочитать историю Git в $guestPath');
      }

      final branchIdx = rawOut.indexOf('__BRANCH__');
      final logIdx = rawOut.indexOf('__LOG__');
      if (branchIdx != -1 && logIdx != -1) {
        final br = rawOut.substring(branchIdx + '__BRANCH__'.length, logIdx).trim();
        if (br.isNotEmpty) _currentBranch = br.split('\n').first.trim();
      }

      final logSection = rawOut.substring(logIdx + '__LOG__'.length).trim();
      final rawLines = logSection.split('\n');
      final List<GitCommitItem> parsed = [];
      final Map<String, int> activeLanes = {};
      int nextLane = 0;

      for (final line in rawLines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split('\t');
        if (parts.length < 6) continue;

        final hash = parts[0].trim();
        final parents = parts[1].trim().split(' ').where((s) => s.isNotEmpty).toList();
        final refs = parts[2].trim();
        final message = parts[3].trim();
        final author = parts[4].trim();
        final date = parts[5].trim();

        int lane = activeLanes[hash] ?? nextLane++;
        if (lane >= _laneColors.length) {
          lane = lane % _laneColors.length;
        }

        for (int i = 0; i < parents.length; i++) {
          final p = parents[i];
          if (i == 0) {
            activeLanes.putIfAbsent(p, () => lane);
          } else {
            activeLanes.putIfAbsent(p, () => (lane + i) % _laneColors.length);
          }
        }

        parsed.add(GitCommitItem(
          hash: hash,
          parentHashes: parents,
          refs: refs,
          message: message,
          author: author,
          relativeDate: date,
          laneIndex: lane,
        ));
      }

      if (!mounted) return;
      setState(() {
        _allCommits = parsed;
        _filteredCommits = parsed;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Ошибка загрузки истории Git: $e';
        _isLoading = false;
      });
    }
  }

  void _showCommitDetails(GitCommitItem commit) async {
    final guestPath = await _resolveGuestRepoPath();
    final runtime = ref.read(runtimeServiceProvider);
    String diffStat = 'Загрузка изменений...';

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131722),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            if (diffStat == 'Загрузка изменений...') {
              runtime
                  .runCommand('cd "$guestPath" && git show --stat --patch --no-color "${commit.hash}" 2>/dev/null')
                  .then((out) {
                if (modalCtx.mounted) {
                  setModalState(() {
                    diffStat = out.trim().isNotEmpty ? out.trim() : 'Нет изменений в коммите';
                  });
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _laneColors[commit.laneIndex].withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                commit.hash,
                                style: GoogleFonts.jetBrainsMono(
                                  color: _laneColors[commit.laneIndex],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (commit.refs.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  commit.refs,
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.copy, size: 16, color: Colors.white70),
                        tooltip: 'Скопировать SHA',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: commit.hash));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('SHA коммита скопирован!'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    commit.message,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Автор: ${commit.author} • ${commit.relativeDate}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  // Quick Commit Actions
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildActionChip(
                        icon: LucideIcons.git_pull_request_create,
                        label: 'Cherry-pick',
                        color: const Color(0xFF8B5CF6),
                        onTap: () async {
                          Navigator.pop(modalCtx);
                          await ref.read(gitProvider.notifier).cherryPickCommit(commit.hash);
                          await _loadGitLog();
                        },
                      ),
                      _buildActionChip(
                        icon: LucideIcons.undo_2,
                        label: 'Revert',
                        color: Colors.amberAccent,
                        onTap: () async {
                          Navigator.pop(modalCtx);
                          await ref.read(gitProvider.notifier).revertCommit(commit.hash);
                          await _loadGitLog();
                        },
                      ),
                      _buildActionChip(
                        icon: LucideIcons.git_branch_plus,
                        label: 'Ветка отсюда',
                        color: const Color(0xFF00F2FE),
                        onTap: () async {
                          Navigator.pop(modalCtx);
                          final branchName = 'branch-${commit.hash}';
                          await ref.read(gitProvider.notifier).checkoutBranch(branchName, createNew: true, fromRef: commit.hash);
                          await _loadGitLog();
                        },
                      ),
                      _buildActionChip(
                        icon: LucideIcons.rotate_ccw,
                        label: 'Reset --mixed',
                        color: Colors.redAccent,
                        onTap: () async {
                          Navigator.pop(modalCtx);
                          await ref.read(gitProvider.notifier).resetToCommit(commit.hash, mode: 'mixed');
                          await _loadGitLog();
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 22),
                  const Text('DIFF И ИЗМЕНЕНИЯ В ФАЙЛАХ:', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 260),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        diffStat,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141724),
        title: Row(
          children: [
            const Icon(LucideIcons.git_graph, color: Color(0xFF00F2FE), size: 20),
            const SizedBox(width: 10),
            Text('Git Graph (Все ветки)', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00F2FE).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _currentBranch,
                style: GoogleFonts.jetBrainsMono(color: const Color(0xFF00F2FE), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить дерево Git',
            icon: const Icon(LucideIcons.rotate_cw, size: 18),
            onPressed: _loadGitLog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Поиск по сообщениям, автору, SHA или веткам...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(LucideIcons.search, color: Colors.white38, size: 16),
                filled: true,
                fillColor: const Color(0xFF171B2B),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F2FE)))
                : _errorMessage != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))))
                    : _filteredCommits.isEmpty
                        ? const Center(child: Text('Коммиты не найдены', style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            itemCount: _filteredCommits.length,
                            itemBuilder: (context, index) {
                              final commit = _filteredCommits[index];
                              final color = _laneColors[commit.laneIndex % _laneColors.length];
                              final isHead = commit.refs.contains('HEAD');

                              return InkWell(
                                onTap: () => _showCommitDetails(commit),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 38,
                                        child: CustomPaint(
                                          painter: _GitNodePainter(
                                            color: color,
                                            isFirst: index == 0,
                                            isLast: index == _filteredCommits.length - 1,
                                            isHead: isHead,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    commit.message,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  commit.hash,
                                                  style: GoogleFonts.jetBrainsMono(
                                                    color: color,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  '${commit.author} • ${commit.relativeDate}',
                                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                ),
                                                if (commit.refs.isNotEmpty)
                                                  Flexible(
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amberAccent.withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        commit.refs,
                                                        style: const TextStyle(
                                                          color: Colors.amberAccent,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                              ],
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
      ),
    );
  }
}

class _GitNodePainter extends CustomPainter {
  final Color color;
  final bool isFirst;
  final bool isLast;
  final bool isHead;

  _GitNodePainter({
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.isHead,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    const centerY = 12.0;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    if (!isFirst) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, centerY), linePaint);
    }
    if (!isLast) {
      canvas.drawLine(Offset(centerX, centerY), Offset(centerX, size.height), linePaint);
    }

    if (isHead) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(centerX, centerY), 7.5, glowPaint);
    }

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _GitNodePainter old) =>
      old.color != color || old.isFirst != isFirst || old.isLast != isLast || old.isHead != isHead;
}
