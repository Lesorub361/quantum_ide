import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/find_replace_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class FindReplacePage extends ConsumerStatefulWidget {
  const FindReplacePage({super.key});

  @override
  ConsumerState<FindReplacePage> createState() => _FindReplacePageState();
}

class _FindReplacePageState extends ConsumerState<FindReplacePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _replaceController.dispose();
    _filterController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final notifier = ref.read(findReplaceProvider.notifier);
    notifier.setQuery(_searchController.text);
    notifier.setReplaceText(_replaceController.text);
    notifier.search();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(findReplaceProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildSearchBar(state),
          _buildOptionsBar(state),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(LucideIcons.circle_alert, size: 14, color: Colors.red.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: TextStyle(fontSize: 12, color: Colors.red.withValues(alpha: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
          _buildResultsHeader(state),
          Expanded(child: _buildResultsList(state)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(FindReplaceState state) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          GlassContainer(
            borderRadius: BorderRadius.circular(10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: GoogleFonts.jetBrainsMono(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search in files...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                border: InputBorder.none,
                prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(LucideIcons.x, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(findReplaceProvider.notifier).setQuery('');
                          ref.read(findReplaceProvider.notifier).search();
                        },
                      ),
                    IconButton(
                        icon: Icon(LucideIcons.arrow_right, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                      onPressed: _performSearch,
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _performSearch(),
            ),
          ),
          const SizedBox(height: 8),
          GlassContainer(
            borderRadius: BorderRadius.circular(10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _replaceController,
              style: GoogleFonts.jetBrainsMono(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Replace with...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                border: InputBorder.none,
                prefixIcon: Icon(LucideIcons.replace, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replaceController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(LucideIcons.x, size: 14, color: Colors.white.withValues(alpha: 0.5)),
                        onPressed: () {
                          _replaceController.clear();
                          ref.read(findReplaceProvider.notifier).setReplaceText('');
                        },
                      ),
                  ],
                ),
              ),
              onChanged: (v) => ref.read(findReplaceProvider.notifier).setReplaceText(v),
            ),
          ),
          const SizedBox(height: 8),
          GlassContainer(
            borderRadius: BorderRadius.circular(10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _filterController,
              style: GoogleFonts.jetBrainsMono(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'File filter (e.g. dart, ts, json)',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                border: InputBorder.none,
                prefixIcon: Icon(LucideIcons.list_filter, size: 16, color: Colors.white.withValues(alpha: 0.5)),
              ),
              onChanged: (v) => ref.read(findReplaceProvider.notifier).setFileFilter(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsBar(FindReplaceState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _buildToggleChip(
            label: 'Aa',
            active: state.caseSensitive,
            tooltip: 'Case Sensitive',
            onTap: () => ref.read(findReplaceProvider.notifier).toggleCaseSensitive(),
          ),
          const SizedBox(width: 6),
          _buildToggleChip(
            label: '.*',
            active: state.useRegex,
            tooltip: 'Regex',
            onTap: () => ref.read(findReplaceProvider.notifier).toggleUseRegex(),
          ),
          const SizedBox(width: 6),
          _buildToggleChip(
            label: '\\b',
            active: state.wholeWord,
            tooltip: 'Whole Word',
            onTap: () => ref.read(findReplaceProvider.notifier).toggleWholeWord(),
          ),
          const Spacer(),
          if (state.totalMatches > 0)
            _buildReplaceButtons(state),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? Colors.white.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplaceButtons(FindReplaceState state) {
    return Row(
      children: [
        _buildActionButton(
          label: 'Replace',
          icon: LucideIcons.replace,
          color: Colors.orange,
          onTap: state.results.isNotEmpty ? _replaceNext : null,
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          label: 'All',
          icon: LucideIcons.check_check,
          color: Colors.red,
          onTap: state.results.isNotEmpty ? _replaceAll : null,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: onTap != null ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: onTap != null ? color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: onTap != null ? color.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.3)),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: onTap != null ? color.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader(FindReplaceState state) {
    if (state.isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (state.totalMatches == 0 && state.query.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'No matches found',
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
        ),
      );
    }

    if (state.totalMatches > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              '${state.totalMatches} matches in ${state.totalFiles} files',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildResultsList(FindReplaceState state) {
    if (state.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.search, size: 48, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              'Search across all files',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: state.results.length,
      itemBuilder: (context, fileIndex) {
        final fileResult = state.results[fileIndex];
        return _buildFileGroup(fileIndex, fileResult);
      },
    );
  }

  Widget _buildFileGroup(int fileIndex, FindReplaceFileResult fileResult) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GlassContainer(
      borderRadius: BorderRadius.circular(8),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => ref.read(findReplaceProvider.notifier).toggleFileExpansion(fileIndex),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    fileResult.isExpanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.file_code, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileResult.fileName,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${fileResult.matches.length}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (fileResult.isExpanded) ...[
            const Divider(height: 1, color: Colors.white10),
            ...fileResult.matches.map((match) => _buildMatchRow(fileResult, match)),
          ],
        ],
      ),
    ),
    );
  }

  Widget _buildMatchRow(FindReplaceFileResult fileResult, FindReplaceMatch match) {
    return InkWell(
      onTap: () => _openFileAtLine(fileResult.filePath, match.lineNumber),
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${match.lineNumber}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _highlightMatch(match.lineContent, match.startOffset, match.endOffset),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => ref.read(findReplaceProvider.notifier).replaceInFile(fileResult.filePath, match),
              child: Icon(LucideIcons.arrow_right, size: 14, color: Colors.orange.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  String _highlightMatch(String line, int start, int end) {
    if (start < 0 || end > line.length || start >= end) return line;
    final before = line.substring(0, start);
    final matched = line.substring(start, end);
    final after = end < line.length ? line.substring(end) : '';
    return '$before[$matched]$after';
  }

  void _openFileAtLine(String filePath, int lineNumber) {
    ref.read(editorProvider.notifier).openFile(filePath, line: lineNumber);
  }

  void _replaceNext() {
    final state = ref.read(findReplaceProvider);
    if (state.results.isEmpty) return;
    final firstFile = state.results.first;
    if (firstFile.matches.isEmpty) return;
    ref.read(findReplaceProvider.notifier).replaceInFile(firstFile.filePath, firstFile.matches.first);
  }

  void _replaceAll() {
    ref.read(findReplaceProvider.notifier).replaceAll();
  }
}
