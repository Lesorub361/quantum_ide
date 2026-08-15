import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

enum DiffViewMode { unified, sideBySide }

enum DiffHunkStatus { pending, applied, rejected }

class DiffHunk {
  final int startLine;
  final int lineCount;
  final List<String> lines;
  DiffHunkStatus status;

  DiffHunk({
    required this.startLine,
    required this.lineCount,
    required this.lines,
    this.status = DiffHunkStatus.pending,
  });
}

class DiffLineInfo {
  final int? oldLine;
  final int? newLine;
  final String content;
  final DiffLineType type;

  DiffLineInfo({
    this.oldLine,
    this.newLine,
    required this.content,
    required this.type,
  });
}

enum DiffLineType { context, addition, deletion }

class DiffViewerPage extends StatefulWidget {
  final String fileName;
  final String originalContent;
  final String modifiedContent;

  const DiffViewerPage({
    super.key,
    required this.fileName,
    required this.originalContent,
    required this.modifiedContent,
  });

  @override
  State<DiffViewerPage> createState() => _DiffViewerPageState();
}

class _DiffViewerPageState extends State<DiffViewerPage> {
  DiffViewMode _viewMode = DiffViewMode.unified;
  List<DiffLineInfo> _diffLines = <DiffLineInfo>[];
  final List<DiffHunk> _hunks = <DiffHunk>[];
  int _currentHunkIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _computeDiff();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _computeDiff() {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(widget.originalContent, widget.modifiedContent);
    dmp.diffCleanupSemantic(diffs);

    final result = <DiffLineInfo>[];
    int oldLine = 1;
    int newLine = 1;

    for (final diff in diffs) {
      final lines = diff.text.split('\n');
      if (lines.last.isEmpty) lines.removeLast();

      for (final line in lines) {
        if (diff.operation == DIFF_EQUAL) {
          result.add(DiffLineInfo(
            oldLine: oldLine++,
            newLine: newLine++,
            content: line,
            type: DiffLineType.context,
          ));
        } else if (diff.operation == DIFF_DELETE) {
          result.add(DiffLineInfo(
            oldLine: oldLine++,
            content: line,
            type: DiffLineType.deletion,
          ));
        } else if (diff.operation == DIFF_INSERT) {
          result.add(DiffLineInfo(
            newLine: newLine++,
            content: line,
            type: DiffLineType.addition,
          ));
        }
      }
    }

    _diffLines = result;
    _buildHunks();
  }

  void _buildHunks() {
    _hunks.clear();
    int hunkStart = -1;

    for (int i = 0; i < _diffLines.length; i++) {
      final line = _diffLines[i];
      if (line.type != DiffLineType.context) {
        if (hunkStart == -1) {
          hunkStart = i > 0 ? i - 1 : 0;
        }
      } else if (hunkStart != -1) {
        final end = i < _diffLines.length - 1 ? i + 1 : i;
        _hunks.add(DiffHunk(
          startLine: hunkStart,
          lineCount: end - hunkStart + 1,
          lines: _diffLines
              .sublist(hunkStart, end + 1)
              .map((l) => l.content)
              .toList(),
        ));
        hunkStart = -1;
      }
    }

    if (hunkStart != -1) {
      _hunks.add(DiffHunk(
        startLine: hunkStart,
        lineCount: _diffLines.length - hunkStart,
        lines: _diffLines
            .sublist(hunkStart)
            .map((l) => l.content)
            .toList(),
      ));
    }
  }

  void _navigateToHunk(int index) {
    if (index < 0 || index >= _hunks.length) return;
    setState(() => _currentHunkIndex = index);
    final hunk = _hunks[index];
    final targetOffset = hunk.startLine * 20.0;
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _applyHunk(int index) {
    setState(() {
      _hunks[index].status = DiffHunkStatus.applied;
    });
  }

  void _rejectHunk(int index) {
    setState(() {
      _hunks[index].status = DiffHunkStatus.rejected;
    });
  }

  void _applyAll() {
    setState(() {
      for (final hunk in _hunks) {
        if (hunk.status == DiffHunkStatus.pending) {
          hunk.status = DiffHunkStatus.applied;
        }
      }
    });
  }

  void _rejectAll() {
    setState(() {
      for (final hunk in _hunks) {
        if (hunk.status == DiffHunkStatus.pending) {
          hunk.status = DiffHunkStatus.rejected;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildToolbar(),
            Expanded(child: _buildDiffContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.zero,
      border:
          Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.git_compare, size: 16, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName.split('/').last,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_diffLines.where((l) => l.type == DiffLineType.deletion).length} deletions · '
                    '${_diffLines.where((l) => l.type == DiffLineType.addition).length} additions',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
            _buildViewModeToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            icon: LucideIcons.list,
            isActive: _viewMode == DiffViewMode.unified,
            onTap: () => setState(() => _viewMode = DiffViewMode.unified),
          ),
          _buildModeButton(
            icon: LucideIcons.columns_2,
            isActive: _viewMode == DiffViewMode.sideBySide,
            onTap: () => setState(() => _viewMode = DiffViewMode.sideBySide),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.cyanAccent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: isActive ? Colors.cyanAccent : Colors.white38,
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    if (_hunks.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          _buildHunkNavigation(),
          const Spacer(),
          TextButton.icon(
            onPressed: _applyAll,
            icon: const Icon(LucideIcons.check, size: 12, color: Colors.greenAccent),
            label: Text('Apply All',
                style: GoogleFonts.inter(
                    color: Colors.greenAccent, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _rejectAll,
            icon: const Icon(LucideIcons.x, size: 12, color: Colors.redAccent),
            label: Text('Reject All',
                style: GoogleFonts.inter(
                    color: Colors.redAccent, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildHunkNavigation() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(LucideIcons.chevron_up, size: 16, color: Colors.white54),
          onPressed:
              _currentHunkIndex > 0 ? () => _navigateToHunk(_currentHunkIndex - 1) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${_currentHunkIndex + 1} / ${_hunks.length}',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.chevron_down,
              size: 16, color: Colors.white54),
          onPressed: _currentHunkIndex < _hunks.length - 1
              ? () => _navigateToHunk(_currentHunkIndex + 1)
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildDiffContent() {
    if (_viewMode == DiffViewMode.sideBySide) {
      return _buildSideBySideView();
    }
    return _buildUnifiedView();
  }

  Widget _buildUnifiedView() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _diffLines.length,
      itemBuilder: (context, index) {
        final line = _diffLines[index];
        final hunkIndex = _findHunkForLine(index);

        return Column(
          children: [
            if (hunkIndex != null && _hunks[hunkIndex].startLine == index)
              _buildHunkHeader(hunkIndex),
            _buildUnifiedLine(line),
          ],
        );
      },
    );
  }

  Widget _buildSideBySideView() {
    final leftLines = <DiffLineInfo?>[];
    final rightLines = <DiffLineInfo?>[];

    int i = 0;
    while (i < _diffLines.length) {
      final removed = <DiffLineInfo>[];
      final added = <DiffLineInfo>[];

      while (i < _diffLines.length && _diffLines[i].type == DiffLineType.deletion) {
        removed.add(_diffLines[i]);
        i++;
      }
      while (i < _diffLines.length && _diffLines[i].type == DiffLineType.addition) {
        added.add(_diffLines[i]);
        i++;
      }

      if (removed.isNotEmpty || added.isNotEmpty) {
        final maxLen = removed.length > added.length ? removed.length : added.length;
        for (int k = 0; k < maxLen; k++) {
          leftLines.add(k < removed.length ? removed[k] : null);
          rightLines.add(k < added.length ? added[k] : null);
        }
      } else {
        if (i < _diffLines.length) {
          leftLines.add(_diffLines[i]);
          rightLines.add(_diffLines[i]);
          i++;
        }
      }
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: leftLines.length,
      itemBuilder: (context, index) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSideBySideCell(leftLines[index], isLeft: true)),
            Container(
                width: 1,
                height: 20,
                color: Colors.white.withValues(alpha: 0.06)),
            Expanded(child: _buildSideBySideCell(rightLines[index], isLeft: false)),
          ],
        );
      },
    );
  }

  Widget _buildSideBySideCell(DiffLineInfo? line, {required bool isLeft}) {
    if (line == null) {
      return Container(
        color: Colors.white.withValues(alpha: 0.02),
        height: 20,
      );
    }

    Color? bgColor;
    Color lineNumColor = Colors.white24;
    Color textColor = Colors.white70;
    String prefix = ' ';

    if (line.type == DiffLineType.addition) {
      bgColor = Colors.green.withValues(alpha: 0.15);
      lineNumColor = Colors.greenAccent.withValues(alpha: 0.5);
      textColor = Colors.greenAccent;
      prefix = '+';
    } else if (line.type == DiffLineType.deletion) {
      bgColor = Colors.red.withValues(alpha: 0.15);
      lineNumColor = Colors.redAccent.withValues(alpha: 0.5);
      textColor = Colors.redAccent;
      prefix = '-';
    }

    final lineNum = isLeft ? line.oldLine : line.newLine;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              lineNum != null ? '$lineNum' : '',
              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: lineNumColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 6),
          Text(prefix,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: lineNumColor, fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              line.content,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 10, color: textColor, height: 1.3),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHunkHeader(int hunkIndex) {
    final hunk = _hunks[hunkIndex];
    final isActive = _currentHunkIndex == hunkIndex;

    Color statusColor;
    String statusLabel;

    switch (hunk.status) {
      case DiffHunkStatus.applied:
        statusColor = Colors.greenAccent;
        statusLabel = 'Applied';
        break;
      case DiffHunkStatus.rejected:
        statusColor = Colors.redAccent;
        statusLabel = 'Rejected';
        break;
      case DiffHunkStatus.pending:
        statusColor = Colors.cyanAccent;
        statusLabel = 'Pending';
        break;
    }

    return GestureDetector(
      onTap: () => setState(() => _currentHunkIndex = hunkIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: isActive
            ? Colors.cyanAccent.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.02),
        child: Row(
          children: [
            Icon(LucideIcons.code, size: 11, color: statusColor),
            const SizedBox(width: 6),
            Text(
              'Hunk ${hunkIndex + 1}',
              style: GoogleFonts.inter(
                  color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Text(
              '@ ${hunk.startLine + 1}',
              style:
                  GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 9),
            ),
            const Spacer(),
            if (hunk.status == DiffHunkStatus.pending) ...[
              GestureDetector(
                onTap: () => _applyHunk(hunkIndex),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(LucideIcons.check,
                      size: 10, color: Colors.greenAccent),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _rejectHunk(hunkIndex),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(LucideIcons.x,
                      size: 10, color: Colors.redAccent),
                ),
              ),
            ] else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                      color: statusColor, fontSize: 8.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedLine(DiffLineInfo line) {
    Color? bgColor;
    Color lineNumColor = Colors.white24;
    Color textColor = Colors.white70;
    String prefix = ' ';

    if (line.type == DiffLineType.addition) {
      bgColor = Colors.green.withValues(alpha: 0.15);
      lineNumColor = Colors.greenAccent.withValues(alpha: 0.5);
      textColor = Colors.greenAccent;
      prefix = '+';
    } else if (line.type == DiffLineType.deletion) {
      bgColor = Colors.red.withValues(alpha: 0.15);
      lineNumColor = Colors.redAccent.withValues(alpha: 0.5);
      textColor = Colors.redAccent;
      prefix = '-';
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              line.oldLine != null ? '${line.oldLine}' : '',
              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: lineNumColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 36,
            child: Text(
              line.newLine != null ? '${line.newLine}' : '',
              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: lineNumColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          Text(prefix,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: lineNumColor, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: SelectionArea(
              child: Text(
                line.content,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: textColor, height: 1.3),
                softWrap: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _findHunkForLine(int lineIndex) {
    for (int i = 0; i < _hunks.length; i++) {
      final hunk = _hunks[i];
      if (lineIndex >= hunk.startLine &&
          lineIndex < hunk.startLine + hunk.lineCount) {
        return i;
      }
    }
    return null;
  }
}
