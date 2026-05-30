import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

// Representing the parsed file segments
abstract class MergeChunk {}

class TextChunk extends MergeChunk {
  final String text;
  TextChunk(this.text);
}

class ConflictChunk extends MergeChunk {
  final String ourContent;
  final String baseContent;
  final String theirContent;
  final String branchName;
  String? resolvedContent;
  bool isResolved;

  ConflictChunk({
    required this.ourContent,
    required this.baseContent,
    required this.theirContent,
    required this.branchName,
    this.resolvedContent,
    this.isResolved = false,
  });
}

// Parser for conflict markers
List<MergeChunk> parseMergeConflicts(String fileContent) {
  final lines = fileContent.split('\n');
  final chunks = <MergeChunk>[];
  final currentText = StringBuffer();
  
  int i = 0;
  while (i < lines.length) {
    if (lines[i].startsWith('<<<<<<<')) {
      // Flush current text chunk
      if (currentText.isNotEmpty) {
        chunks.add(TextChunk(currentText.toString()));
        currentText.clear();
      }
      
      // Parse our content
      final ourBuffer = StringBuffer();
      i++;
      while (i < lines.length && !lines[i].startsWith('|||||||') && !lines[i].startsWith('=======')) {
        ourBuffer.writeln(lines[i]);
        i++;
      }
      
      final baseBuffer = StringBuffer();
      if (i < lines.length && lines[i].startsWith('|||||||')) {
        i++;
        while (i < lines.length && !lines[i].startsWith('=======')) {
          baseBuffer.writeln(lines[i]);
          i++;
        }
      }
      
      final theirBuffer = StringBuffer();
      if (i < lines.length && lines[i].startsWith('=======')) {
        i++;
        while (i < lines.length && !lines[i].startsWith('>>>>>>>')) {
          theirBuffer.writeln(lines[i]);
          i++;
        }
      }
      
      String branchName = '';
      if (i < lines.length && lines[i].startsWith('>>>>>>>')) {
        branchName = lines[i].substring(7).trim();
        i++;
      }
      
      // Clean trailing newlines
      String cleanOur = ourBuffer.toString();
      if (cleanOur.endsWith('\n')) cleanOur = cleanOur.substring(0, cleanOur.length - 1);
      String cleanBase = baseBuffer.toString();
      if (cleanBase.endsWith('\n')) cleanBase = cleanBase.substring(0, cleanBase.length - 1);
      String cleanTheir = theirBuffer.toString();
      if (cleanTheir.endsWith('\n')) cleanTheir = cleanTheir.substring(0, cleanTheir.length - 1);

      chunks.add(ConflictChunk(
        ourContent: cleanOur,
        baseContent: cleanBase,
        theirContent: cleanTheir,
        branchName: branchName,
      ));
    } else {
      currentText.writeln(lines[i]);
      i++;
    }
  }
  
  if (currentText.isNotEmpty) {
    String text = currentText.toString();
    if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
    chunks.add(TextChunk(text));
  }
  
  return chunks;
}

class GitMergeConflictPage extends ConsumerStatefulWidget {
  final String relativePath;

  const GitMergeConflictPage({
    super.key,
    required this.relativePath,
  });

  @override
  ConsumerState<GitMergeConflictPage> createState() => _GitMergeConflictPageState();
}

class _GitMergeConflictPageState extends ConsumerState<GitMergeConflictPage> {
  bool _isLoading = true;
  String _error = '';
  List<MergeChunk> _chunks = [];
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadConflictFile();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConflictFile() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final workspace = ref.read(workspaceProvider);
      final workspacePath = workspace.currentPath;
      if (workspacePath == null) {
        throw Exception('Путь к рабочему пространству не найден');
      }

      final localFilePath = p.join(workspacePath, widget.relativePath);
      final file = File(localFilePath);
      if (!await file.exists()) {
        throw Exception('Файл не найден: $localFilePath');
      }

      final content = await file.readAsString();
      final parsed = parseMergeConflicts(content);
      
      setState(() {
        _chunks = parsed;
        _isLoading = false;
      });

      // Initialize text controllers for conflict chunks
      for (int k = 0; k < _chunks.length; k++) {
        final chunk = _chunks[k];
        if (chunk is ConflictChunk) {
          _controllers[k] = TextEditingController(text: chunk.resolvedContent ?? '');
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  int get _totalConflicts => _chunks.whereType<ConflictChunk>().length;
  int get _resolvedConflicts => _chunks.whereType<ConflictChunk>().where((c) => c.isResolved).length;
  bool get _isAllResolved => _resolvedConflicts == _totalConflicts;

  void _resolveChunk(int index, String content) {
    final chunk = _chunks[index];
    if (chunk is ConflictChunk) {
      setState(() {
        chunk.resolvedContent = content;
        chunk.isResolved = true;
        _controllers[index]?.text = content;
      });
    }
  }

  void _resetChunk(int index) {
    final chunk = _chunks[index];
    if (chunk is ConflictChunk) {
      setState(() {
        chunk.resolvedContent = '';
        chunk.isResolved = false;
        _controllers[index]?.clear();
      });
    }
  }

  Future<void> _saveAndResolveFile() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_isAllResolved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.resolveConflictsBeforeSaving),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final workspace = ref.read(workspaceProvider);
      final workspacePath = workspace.currentPath;
      if (workspacePath == null) {
        throw Exception('Рабочее пространство не установлено');
      }

      final localFilePath = p.join(workspacePath, widget.relativePath);
      final file = File(localFilePath);

      // Reconstruct content
      final buffer = StringBuffer();
      for (int k = 0; k < _chunks.length; k++) {
        final chunk = _chunks[k];
        if (chunk is TextChunk) {
          buffer.write(chunk.text);
          if (k < _chunks.length - 1) buffer.write('\n');
        } else if (chunk is ConflictChunk) {
          // Use current value in text controller or fallback
          final text = _controllers[k]?.text ?? chunk.resolvedContent ?? '';
          buffer.write(text);
          if (k < _chunks.length - 1) buffer.write('\n');
        }
      }

      await file.writeAsString(buffer.toString());

      // Git add file to mark it as resolved
      final gitNotifier = ref.read(gitProvider.notifier);
      await gitNotifier.stageFile(widget.relativePath);
      await gitNotifier.refreshStatus();

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.fileSavedAndStaged),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.saveError(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: _buildHeader(l10n),
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return GlassContainer(
      blur: 20,
      opacity: 0.04,
      borderRadius: BorderRadius.zero,
      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.arrow_left, color: Colors.white70, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.relativePath.split('/').last,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.relativePath,
                      style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (!_isLoading && _error.isEmpty && _totalConflicts > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isAllResolved
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isAllResolved
                          ? Colors.greenAccent.withValues(alpha: 0.3)
                          : Colors.amberAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isAllResolved ? LucideIcons.circle_check : LucideIcons.git_pull_request,
                        color: _isAllResolved ? Colors.greenAccent : Colors.amberAccent,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_resolvedConflicts / $_totalConflicts',
                        style: GoogleFonts.inter(
                          color: _isAllResolved ? Colors.greenAccent : Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isAllResolved ? _saveAndResolveFile : null,
                  icon: const Icon(LucideIcons.save, size: 14),
                  label: Text(l10n.acceptMerge),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.greenAccent,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                    disabledForegroundColor: Colors.white24,
                    elevation: 0,
                    side: BorderSide(
                      color: _isAllResolved
                          ? Colors.greenAccent.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.05),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                ),
              ],
            ],
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
              Text(
                l10n.errorLoadingConflictFile,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error,
                style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_totalConflicts == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.circle_check, size: 48, color: Colors.greenAccent),
              const SizedBox(height: 16),
              Text(
                l10n.conflictsNotFound,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.noConflictMarkersFound,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.1)),
                child: Text(l10n.backToGit, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _chunks.length,
        itemBuilder: (context, index) {
          final chunk = _chunks[index];
          if (chunk is TextChunk) {
            return _buildTextChunk(chunk);
          } else if (chunk is ConflictChunk) {
            return _buildConflictChunk(index, chunk, l10n);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildTextChunk(TextChunk chunk) {
    if (chunk.text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.01),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          chunk.text,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.75),
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildConflictChunk(int index, ConflictChunk chunk, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F19),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: chunk.isResolved
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.amberAccent.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (chunk.isResolved ? Colors.greenAccent : Colors.amberAccent).withValues(alpha: 0.04),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Conflict header
          _buildConflictChunkHeader(index, chunk, l10n),

          // Left/Right options split view
          _buildSideBySideOptions(index, chunk, l10n),

          // Central Editable Resolve Area
          _buildResolveArea(index, chunk, l10n),
        ],
      ),
    );
  }

  Widget _buildConflictChunkHeader(int index, ConflictChunk chunk, AppLocalizations l10n) {
    final statusColor = chunk.isResolved ? Colors.greenAccent : Colors.amberAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: statusColor.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              chunk.isResolved ? LucideIcons.circle_check : LucideIcons.git_pull_request,
              size: 14,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.conflictBlock,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (chunk.isResolved) ...[
            TextButton.icon(
              onPressed: () => _resetChunk(index),
              icon: const Icon(LucideIcons.undo_2, size: 12, color: Colors.amberAccent),
              label: Text(
                l10n.resetAction,
                style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSideBySideOptions(int index, ConflictChunk chunk, AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useVertical = constraints.maxWidth < 600;
        final children = [
          _buildOptionPanel(
            title: l10n.currentChangesOurs,
            content: chunk.ourContent,
            badgeColor: Colors.blueAccent,
            badgeText: 'OURS',
            onAccept: () => _resolveChunk(index, chunk.ourContent),
            l10n: l10n,
          ),
          _buildOptionPanel(
            title: l10n.incomingChanges(chunk.branchName.isNotEmpty ? chunk.branchName : l10n.incomingBranch),
            content: chunk.theirContent,
            badgeColor: Colors.purpleAccent,
            badgeText: 'THEIRS',
            onAccept: () => _resolveChunk(index, chunk.theirContent),
            l10n: l10n,
          ),
        ];

        if (useVertical) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              children[0],
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
              children[1],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[0]),
              Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
              Expanded(child: children[1]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionPanel({
    required String title,
    required String content,
    required Color badgeColor,
    required String badgeText,
    required VoidCallback onAccept,
    required AppLocalizations l10n,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.inter(color: badgeColor, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
            ),
            child: content.isEmpty
                ? Center(
                    child: Text(
                      l10n.emptyLabel,
                      style: GoogleFonts.jetBrainsMono(color: Colors.white12, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      content,
                      style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11, height: 1.3),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: badgeColor.withValues(alpha: 0.12),
                foregroundColor: badgeColor,
                elevation: 0,
                side: BorderSide(color: badgeColor.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: Text(l10n.useThisVersion, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolveArea(int index, ConflictChunk chunk, AppLocalizations l10n) {
    final statusColor = chunk.isResolved ? Colors.greenAccent : Colors.amberAccent;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.mergeResultEditable,
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              if (!chunk.isResolved)
                const Icon(LucideIcons.pencil, size: 12, color: Colors.amberAccent)
              else
                const Icon(LucideIcons.circle_check, size: 12, color: Colors.greenAccent),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controllers[index],
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: l10n.chooseVersionOrWriteHint,
              hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0D111E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: statusColor, width: 1),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12, height: 1.4),
            onChanged: (val) {
              if (!chunk.isResolved && val.isNotEmpty) {
                setState(() {
                  chunk.isResolved = true;
                  chunk.resolvedContent = val;
                });
              } else if (chunk.isResolved && val.isEmpty) {
                setState(() {
                  chunk.isResolved = false;
                  chunk.resolvedContent = '';
                });
              } else {
                chunk.resolvedContent = val;
              }
            },
          ),
          if (!chunk.isResolved) ...[
            const SizedBox(height: 8),
            Text(
              l10n.markAsResolvedHint,
              style: GoogleFonts.inter(color: Colors.amberAccent.withValues(alpha: 0.8), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}
