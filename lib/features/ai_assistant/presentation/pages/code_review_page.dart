import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/services/ai_code_review_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'dart:io';

class CodeReviewPage extends ConsumerStatefulWidget {
  const CodeReviewPage({super.key});

  @override
  ConsumerState<CodeReviewPage> createState() => _CodeReviewPageState();
}

class _CodeReviewPageState extends ConsumerState<CodeReviewPage> {
  String? _selectedFilePath;
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiCodeReviewProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.greenAccent.withValues(alpha: 0.12), Colors.transparent],
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(LucideIcons.arrow_left, color: theme.colorScheme.onSurface),
                  onPressed: () => context.go('/'),
                ),
                title: Row(
                  children: [
                    const Icon(LucideIcons.scan_eye, size: 18, color: Colors.greenAccent),
                    const SizedBox(width: 8),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Colors.greenAccent, Colors.tealAccent],
                      ).createShader(b),
                      child: Text(
                        'AI Code Review',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildFileSelector(state),
                    const SizedBox(height: 16),
                    _buildReviewButton(state),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      _buildErrorBanner(state.error!),
                    ],
                    if (state.lastResult != null) ...[
                      const SizedBox(height: 16),
                      _buildSummaryStats(state.lastResult!),
                      const SizedBox(height: 16),
                      _buildFilterBar(),
                      const SizedBox(height: 8),
                      _buildResultsList(state),
                    ],
                    if (state.history.isNotEmpty && state.lastResult == null) ...[
                      const SizedBox(height: 16),
                      _buildHistorySection(state),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileSelector(AiCodeReviewState state) {
    final theme = Theme.of(context);
    final workspace = ref.watch(workspaceProvider);
    final workspacePath = workspace.currentPath;
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.file_code, size: 14, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text('Select File', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _showFilePicker(workspacePath),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.folder_open, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedFilePath ?? 'Tap to select a file...',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _selectedFilePath != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(LucideIcons.chevron_right, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilePicker(String? workspacePath) {
    if (workspacePath == null) return;
    final dir = Directory(workspacePath);
    final files = <String>[];
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          final path = entity.path;
          if (path.endsWith('.dart') || path.endsWith('.js') || path.endsWith('.ts') ||
              path.endsWith('.py') || path.endsWith('.java') || path.endsWith('.cpp') ||
              path.endsWith('.c') || path.endsWith('.h') || path.endsWith('.go') ||
              path.endsWith('.rs') || path.endsWith('.yaml') || path.endsWith('.json')) {
            files.add(path);
          }
        }
      }
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Select File to Review', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final relativePath = file.replaceFirst(workspacePath, '').replaceFirst(RegExp(r'^[/\\]'), '');
                    return ListTile(
                      leading: const Icon(LucideIcons.file_code, size: 16, color: Colors.greenAccent),
                      title: Text(relativePath, style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis),
                      onTap: () {
                        setState(() => _selectedFilePath = file);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewButton(AiCodeReviewState state) {
    final theme = Theme.of(context);
    final canReview = _selectedFilePath != null && !state.isReviewing;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canReview ? () => _startReview() : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: canReview ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: canReview ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.isReviewing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                )
              else
                const Icon(LucideIcons.scan, size: 18, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text(
                state.isReviewing ? 'Reviewing...' : 'Start AI Review',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: canReview ? Colors.greenAccent : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startReview() async {
    if (_selectedFilePath == null) return;
    await ref.read(aiCodeReviewProvider.notifier).reviewFile(_selectedFilePath!);
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.triangle_alert, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error, style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStats(ReviewResult result) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.chart_bar, size: 14, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text('Summary', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              Text(
                '${result.items.length} issues found',
                style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statBadge('Errors', result.errorCount, Colors.redAccent),
              const SizedBox(width: 8),
              _statBadge('Warnings', result.warningCount, Colors.amberAccent),
              const SizedBox(width: 8),
              _statBadge('Info', result.infoCount, Colors.cyanAccent),
              const SizedBox(width: 8),
              _statBadge('Suggestions', result.suggestionCount, Colors.purpleAccent),
            ],
          ),
          if (result.summary != null) ...[
            const SizedBox(height: 12),
            Text(result.summary!, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _statBadge(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text('$count', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.inter(fontSize: 9, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Row(
      children: [
        _filterChip('all', 'All'),
        const SizedBox(width: 6),
        _filterChip('error', 'Errors'),
        const SizedBox(width: 6),
        _filterChip('warning', 'Warnings'),
        const SizedBox(width: 6),
        _filterChip('info', 'Info'),
        const SizedBox(width: 6),
        _filterChip('suggestion', 'Ideas'),
      ],
    );
  }

  Widget _filterChip(String id, String label) {
    final isActive = _filter == id;
    final theme = Theme.of(context);
    final color = switch (id) {
      'error' => Colors.redAccent,
      'warning' => Colors.amberAccent,
      'info' => Colors.cyanAccent,
      'suggestion' => Colors.purpleAccent,
      _ => Colors.greenAccent,
    };
    return GestureDetector(
      onTap: () => setState(() => _filter = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 11, color: isActive ? color : theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }

  Widget _buildResultsList(AiCodeReviewState state) {
    final result = state.lastResult;
    if (result == null) return const SizedBox.shrink();
    final filtered = _filter == 'all'
        ? result.items
        : result.items.where((i) => i.severity.name == _filter).toList();
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('No $_filter issues found', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12)),
        ),
      );
    }
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: filtered.map((item) => _buildReviewItem(item)).toList(),
      ),
    );
  }

  Widget _buildReviewItem(ReviewItem item) {
    final theme = Theme.of(context);
    final (color, icon) = switch (item.severity) {
      ReviewSeverity.error => (Colors.redAccent, LucideIcons.circle_x),
      ReviewSeverity.warning => (Colors.amberAccent, LucideIcons.triangle_alert),
      ReviewSeverity.info => (Colors.cyanAccent, LucideIcons.info),
      ReviewSeverity.suggestion => (Colors.purpleAccent, LucideIcons.lightbulb),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.severity.name.toUpperCase(),
                              style: GoogleFonts.inter(fontSize: 9, color: color, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (item.line != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Line ${item.line}',
                              style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(item.message, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface)),
                      if (item.suggestion != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.suggestion!,
                          style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (item.editPatch != null)
                  GestureDetector(
                    onTap: () async {
                      if (_selectedFilePath != null) {
                        await ref.read(aiCodeReviewProvider.notifier).applyFix(item, _selectedFilePath!);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fix applied', style: GoogleFonts.inter(fontSize: 12))),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Apply Fix', style: GoogleFonts.inter(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(AiCodeReviewState state) {
    final theme = Theme.of(context);
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.history, size: 14, color: Colors.amberAccent),
              const SizedBox(width: 8),
              Text('Review History', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(aiCodeReviewProvider.notifier).clearHistory(),
                child: Text('Clear', style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...state.history.take(10).map((result) {
            final relPath = result.filePath.split('/').last;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(LucideIcons.file_code, size: 12, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$relPath · ${result.items.length} issues · ${result.reviewedAt.hour}:${result.reviewedAt.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
