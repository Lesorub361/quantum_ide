import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:quantum_ide/core/services/git_graph_service.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class GitGraphPage extends ConsumerStatefulWidget {
  const GitGraphPage({super.key});

  @override
  ConsumerState<GitGraphPage> createState() => _GitGraphPageState();
}

class _GitGraphPageState extends ConsumerState<GitGraphPage> {
  List<GitGraphEntry> _entries = [];
  List<String> _branches = [];
  bool _isLoading = true;
  String? _error;
  String? _filterBranch;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGraph() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(gitGraphServiceProvider);
      final commits = await service.getCommits(branch: _filterBranch, maxCount: 300);
      final refs = await service.getBranchRefs();
      final branches = await service.getBranches();
      final entries = service.buildGraph(commits, refs);

      setState(() {
        _entries = entries;
        _branches = branches;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  List<GitGraphEntry> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    final q = _searchQuery.toLowerCase();
    return _entries.where((e) =>
      e.commit.message.toLowerCase().contains(q) ||
      e.commit.author.toLowerCase().contains(q) ||
      e.commit.shortHash.toLowerCase().contains(q)
    ).toList();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredEntries;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: GlassContainer(
                    borderRadius: BorderRadius.circular(10),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.jetBrainsMono(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search commits...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                        border: InputBorder.none,
                        prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                        suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(LucideIcons.x, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GlassContainer(
                  borderRadius: BorderRadius.circular(10),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _filterBranch,
                      isDense: true,
                      dropdownColor: theme.colorScheme.surface.withValues(alpha: 0.95),
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                      hint: Text('All', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All branches'),
                        ),
                        ..._branches.map((b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        )),
                      ],
                      onChanged: (v) {
                        setState(() => _filterBranch = v);
                        _loadGraph();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.git_branch, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                        const SizedBox(height: 16),
                        TextButton(onPressed: _loadGraph, child: const Text('Retry')),
                      ],
                    ),
                  )
                : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.git_commit_horizontal, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text('No commits found', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemBuilder: (context, index) => _buildCommitRow(filtered[index]),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommitRow(GitGraphEntry entry) {
    final commit = entry.commit;
    final isMerge = commit.parents.length > 1;

    return InkWell(
      onTap: () => _showCommitDiff(commit),
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGraphVisual(entry, isMerge),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    commit.message,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          commit.shortHash,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        commit.author,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(commit.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      if (commit.branches.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        ...commit.branches.map((b) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 0.5),
                            ),
                            child: Text(
                              b,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: Colors.blue.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                        )),
                      ],
                      if (commit.tags.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        ...commit.tags.map((t) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.tag, size: 10, color: Colors.amber.withValues(alpha: 0.8)),
                                const SizedBox(width: 3),
                                Text(
                                  t,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: Colors.amber.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGraphVisual(GitGraphEntry entry, bool isMerge) {
    const double cellWidth = 20.0;
    const double rowHeight = 48.0;
    const double dotRadius = 5.0;

    int maxCol = 0;
    for (final col in entry.columns) {
      if (col.index > maxCol) maxCol = col.index;
    }
    final graphWidth = (maxCol + 1) * cellWidth + dotRadius * 2 + 4;

    return SizedBox(
      width: graphWidth,
      height: rowHeight,
      child: CustomPaint(
        painter: _GraphPainter(
          columns: entry.columns,
          isMerge: isMerge,
          cellWidth: cellWidth,
          dotRadius: dotRadius,
        ),
      ),
    );
  }

  void _showCommitDiff(GitCommit commit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          blur: 20,
          opacity: 0.12,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        commit.shortHash,
                        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        commit.message,
                        style: GoogleFonts.jetBrainsMono(fontSize: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(LucideIcons.user, size: 12, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      commit.author,
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(width: 12),
                    Icon(LucideIcons.calendar, size: 12, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d, yyyy HH:mm').format(commit.date),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(width: 12),
                    Icon(LucideIcons.users, size: 12, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      '${commit.parents.length} parent(s)',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Commit: ${commit.hash}',
                      style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    if (commit.parents.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Parents: ${commit.parents.join(", ")}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                    if (commit.branches.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Branches: ${commit.branches.join(", ")}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                    if (commit.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tags: ${commit.tags.join(", ")}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphColumn> columns;
  final bool isMerge;
  final double cellWidth;
  final double dotRadius;

  _GraphPainter({
    required this.columns,
    required this.isMerge,
    required this.cellWidth,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (columns.isEmpty) return;

    final centerY = size.height / 2;

    for (final col in columns) {
      final paint = Paint()
        ..color = col.color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final x = col.index * cellWidth + dotRadius + 2;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );

      final dotPaint = Paint()
        ..color = col.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, centerY), dotRadius, dotPaint);

      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      canvas.drawCircle(Offset(x, centerY), dotRadius + 1, ringPaint);
    }

    if (isMerge && columns.length > 1) {
      final mainCol = columns.first;
      final mergeCol = columns.last;
      final x1 = mainCol.index * cellWidth + dotRadius + 2;
      final x2 = mergeCol.index * cellWidth + dotRadius + 2;

      final mergePaint = Paint()
        ..color = mainCol.color.withValues(alpha: 0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(x1, centerY)
        ..cubicTo(x1, centerY - 10, x2, centerY + 10, x2, centerY);

      canvas.drawPath(path, mergePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.columns != columns || oldDelegate.isMerge != isMerge;
  }
}
