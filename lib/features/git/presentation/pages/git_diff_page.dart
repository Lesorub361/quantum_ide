import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

enum LineType { added, removed, normal }

class DiffLine {
  final LineType type;
  final String text;
  final int? originalLineNum;
  final int? modifiedLineNum;

  DiffLine({
    required this.type,
    required this.text,
    this.originalLineNum,
    this.modifiedLineNum,
  });
}

class GitDiffPage extends ConsumerStatefulWidget {
  final String relativePath;
  final bool initiallyStaged;
  final String? previewContent;
  final String? originalOverride;

  const GitDiffPage({
    super.key,
    required this.relativePath,
    required this.initiallyStaged,
    this.previewContent,
    this.originalOverride,
  });

  @override
  ConsumerState<GitDiffPage> createState() => _GitDiffPageState();
}

class _GitDiffPageState extends ConsumerState<GitDiffPage> {
  bool _isLoading = true;
  String _error = '';
  List<DiffLine> _diffLines = [];
  bool _isStaged = false;
  bool _isSideBySide = false;

  @override
  void initState() {
    super.initState();
    _isStaged = widget.initiallyStaged;
    _loadDiff();
  }

  Future<void> _loadDiff() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final workspace = ref.read(workspaceProvider);
      final workspacePath = workspace.currentPath;
      if (workspacePath == null) {
        throw Exception('Workspace path is empty');
      }

      final gitService = ref.read(gitServiceProvider);
      
      // 1. Get original content
      String originalContent = '';
      if (widget.originalOverride != null) {
        originalContent = widget.originalOverride!;
      } else {
        originalContent = await gitService.getFileContentFromGit(widget.relativePath);
      }

      // 2. Get modified content
      String modifiedContent = '';
      if (widget.previewContent != null) {
        modifiedContent = widget.previewContent!;
      } else {
        final localFilePath = p.join(workspacePath, widget.relativePath);
        final file = File(localFilePath);
        if (await file.exists()) {
          modifiedContent = await file.readAsString();
        }
      }

      // 3. Compute unified line-by-line diff
      _diffLines = _computeLineDiff(originalContent, modifiedContent);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<DiffLine> _computeLineDiff(String original, String modified) {
    final dmp = DiffMatchPatch();
    
    final originalLines = original.split('\n');
    final modifiedLines = modified.split('\n');
    
    final Map<String, String> lineToCharMap = {};
    final List<String> charToLineList = [''];
    
    String translateLinesToChars(List<String> lines) {
      final buffer = StringBuffer();
      for (final line in lines) {
        if (lineToCharMap.containsKey(line)) {
          buffer.write(lineToCharMap[line]);
        } else {
          final char = String.fromCharCode(lineToCharMap.length + 1);
          lineToCharMap[line] = char;
          charToLineList.add(line);
          buffer.write(char);
        }
      }
      return buffer.toString();
    }
    
    final originalChars = translateLinesToChars(originalLines);
    final modifiedChars = translateLinesToChars(modifiedLines);
    
    final diffs = dmp.diff(originalChars, modifiedChars);
    dmp.diffCleanupSemantic(diffs);
    
    final diffLines = <DiffLine>[];
    int originalLineNum = 1;
    int modifiedLineNum = 1;
    
    for (final diff in diffs) {
      final chars = diff.text.runes;
      for (final rune in chars) {
        final lineText = charToLineList[rune];
        if (diff.operation == DIFF_EQUAL) {
          diffLines.add(DiffLine(
            type: LineType.normal,
            text: lineText,
            originalLineNum: originalLineNum++,
            modifiedLineNum: modifiedLineNum++,
          ));
        } else if (diff.operation == DIFF_INSERT) {
          diffLines.add(DiffLine(
            type: LineType.added,
            text: lineText,
            originalLineNum: null,
            modifiedLineNum: modifiedLineNum++,
          ));
        } else if (diff.operation == DIFF_DELETE) {
          diffLines.add(DiffLine(
            type: LineType.removed,
            text: lineText,
            originalLineNum: originalLineNum++,
            modifiedLineNum: null,
          ));
        }
      }
    }
    
    return diffLines;
  }

  Future<void> _toggleStaging() async {
    final gitNotifier = ref.read(gitProvider.notifier);
    
    setState(() => _isLoading = true);
    try {
      if (_isStaged) {
        await gitNotifier.unstageFile(widget.relativePath);
        _isStaged = false;
      } else {
        await gitNotifier.stageFile(widget.relativePath);
        _isStaged = true;
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isStaged ? l10n.stagedMessage : l10n.unstagedMessage),
            backgroundColor: const Color(0xFF0F172A),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.stageError(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmDiscardChanges() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            const Icon(LucideIcons.triangle_alert, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            Text(l10n.resetChangesTitle, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          l10n.resetChangesConfirmation,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(l10n.resetAction, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      try {
        final gitService = ref.read(gitServiceProvider);
        await gitService.discardChanges(widget.relativePath);
        
        // Refresh global git status
        await ref.read(gitProvider.notifier).refreshStatus();

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          Navigator.of(context).pop(); // Close page after discard
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.changesReset), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.resetError(e.toString())), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(l10n),
            Expanded(child: _buildBody(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.zero,
      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.relativePath.split('/').last,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.relativePath,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!_isLoading && _error.isEmpty) ...[
              // Action: Toggle side-by-side mode
              _buildHeaderButton(
                icon: _isSideBySide ? LucideIcons.list : LucideIcons.columns_2,
                color: Colors.cyanAccent,
                tooltip: _isSideBySide ? l10n.normalView : l10n.splitView,
                onTap: () {
                  setState(() {
                    _isSideBySide = !_isSideBySide;
                  });
                },
              ),
              const SizedBox(width: 8),
              // Action: Discard changes
              _buildHeaderButton(
                icon: LucideIcons.trash_2,
                color: Colors.redAccent,
                tooltip: l10n.resetChangesTitle,
                onTap: _confirmDiscardChanges,
              ),
              const SizedBox(width: 8),
              // Action: Stage / Unstage
              _buildHeaderButton(
                icon: _isStaged ? LucideIcons.circle_minus : LucideIcons.circle_plus,
                color: _isStaged ? Colors.amberAccent : Colors.greenAccent,
                tooltip: _isStaged ? l10n.unstageAction : l10n.stageAction,
                onTap: _toggleStaging,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.circle_alert, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(l10n.failedToLoadChanges, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_error, style: const TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_diffLines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.circle_check, size: 48, color: Colors.greenAccent),
            const SizedBox(height: 16),
            Text(l10n.noChanges, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(l10n.fileIdenticalToHead, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
    }

    if (_isSideBySide) {
      // Build aligned lists for Side-by-Side view
      final List<DiffLine?> leftLines = [];
      final List<DiffLine?> rightLines = [];
      int i = 0;
      while (i < _diffLines.length) {
        List<DiffLine> removedBlock = [];
        List<DiffLine> addedBlock = [];
        
        while (i < _diffLines.length && _diffLines[i].type == LineType.removed) {
          removedBlock.add(_diffLines[i]);
          i++;
        }
        while (i < _diffLines.length && _diffLines[i].type == LineType.added) {
          addedBlock.add(_diffLines[i]);
          i++;
        }
        
        if (removedBlock.isNotEmpty || addedBlock.isNotEmpty) {
          final maxLen = removedBlock.length > addedBlock.length ? removedBlock.length : addedBlock.length;
          for (int k = 0; k < maxLen; k++) {
            leftLines.add(k < removedBlock.length ? removedBlock[k] : null);
            rightLines.add(k < addedBlock.length ? addedBlock[k] : null);
          }
        } else {
          leftLines.add(_diffLines[i]);
          rightLines.add(_diffLines[i]);
          i++;
        }
      }

      return SelectionArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: leftLines.length,
          itemBuilder: (context, index) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSideBySideCell(leftLines[index], isLeft: true),
                ),
                Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.08)),
                Expanded(
                  child: _buildSideBySideCell(rightLines[index], isLeft: false),
                ),
              ],
            );
          },
        ),
      );
    }

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _diffLines.length,
        itemBuilder: (context, index) {
          return _buildDiffLineItem(_diffLines[index]);
        },
      ),
    );
  }

  Widget _buildSideBySideCell(DiffLine? line, {required bool isLeft}) {
    if (line == null) {
      return Container(
        color: Colors.white.withValues(alpha: 0.02),
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Text(
          '',
          style: GoogleFonts.jetBrainsMono(fontSize: 9),
        ),
      );
    }

    Color? backgroundColor;
    Color lineNumColor = Colors.white24;
    Color textColor = Colors.white70;
    String prefix = ' ';

    if (line.type == LineType.added) {
      backgroundColor = Colors.green.withValues(alpha: 0.15);
      lineNumColor = Colors.greenAccent.withValues(alpha: 0.5);
      textColor = Colors.greenAccent;
      prefix = '+';
    } else if (line.type == LineType.removed) {
      backgroundColor = Colors.red.withValues(alpha: 0.15);
      lineNumColor = Colors.redAccent.withValues(alpha: 0.5);
      textColor = Colors.redAccent;
      prefix = '-';
    }

    final lineNum = isLeft ? line.originalLineNum : line.modifiedLineNum;

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              lineNum != null ? '$lineNum' : '',
              style: GoogleFonts.jetBrainsMono(fontSize: 8.5, color: lineNumColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            prefix,
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: lineNumColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              line.text,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                color: textColor,
                height: 1.3,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLineItem(DiffLine line) {
    Color? backgroundColor;
    Color lineNumColor = Colors.white24;
    Color textColor = Colors.white70;
    String prefix = ' ';

    if (line.type == LineType.added) {
      backgroundColor = Colors.green.withValues(alpha: 0.15);
      lineNumColor = Colors.greenAccent.withValues(alpha: 0.5);
      textColor = Colors.greenAccent;
      prefix = '+';
    } else if (line.type == LineType.removed) {
      backgroundColor = Colors.red.withValues(alpha: 0.15);
      lineNumColor = Colors.redAccent.withValues(alpha: 0.5);
      textColor = Colors.redAccent;
      prefix = '-';
    }

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Line Number (Original)
          SizedBox(
            width: 32,
            child: Text(
              line.originalLineNum != null ? '${line.originalLineNum}' : '',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: lineNumColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          // Right Line Number (Modified)
          SizedBox(
            width: 32,
            child: Text(
              line.modifiedLineNum != null ? '${line.modifiedLineNum}' : '',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: lineNumColor),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 12),
          // Diff Prefix (+ / - / space)
          Text(
            prefix,
            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: lineNumColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          // Content
          Expanded(
            child: Text(
              line.text,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: textColor,
                height: 1.3,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
