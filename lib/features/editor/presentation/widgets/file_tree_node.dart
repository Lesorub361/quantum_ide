import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import '../notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/pages/file_preview_page.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/bookmarks_notifier.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

enum FileSortMode { name, size, date }

class ExpandedFoldersNotifier extends StateNotifier<Set<String>> {
  final Ref _ref;
  String? _currentWorkspacePath;

  ExpandedFoldersNotifier(this._ref) : super({}) {
    _ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      if (next.currentPath != _currentWorkspacePath) {
        _currentWorkspacePath = next.currentPath;
        _loadExpandedFolders();
      }
    });
    _currentWorkspacePath = _ref.read(workspaceProvider).currentPath;
    _loadExpandedFolders();
  }

  Future<void> _loadExpandedFolders() async {
    final path = _currentWorkspacePath;
    if (path == null) {
      state = {};
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('expanded_folders_$path') ?? [];
      state = list.toSet();
    } catch (e) {
      state = {};
    }
  }

  Future<void> toggleExpanded(String folderPath) async {
    final newSet = {...state};
    if (newSet.contains(folderPath)) {
      newSet.remove(folderPath);
    } else {
      newSet.add(folderPath);
    }
    state = newSet;

    final path = _currentWorkspacePath;
    if (path != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('expanded_folders_$path', newSet.toList());
      } catch (e) {
        // Ignore
      }
    }
  }
  
  Future<void> setExpanded(Set<String> newSet) async {
    state = newSet;
    final path = _currentWorkspacePath;
    if (path != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('expanded_folders_$path', newSet.toList());
      } catch (e) {
        // Ignore
      }
    }
  }
}

final expandedFoldersProvider = StateNotifierProvider<ExpandedFoldersNotifier, Set<String>>((ref) {
  return ExpandedFoldersNotifier(ref);
});

final fileSearchQueryProvider = StateProvider<String>((ref) => '');
final fileSortModeProvider = StateProvider<FileSortMode>((ref) => FileSortMode.name);
final selectedPathsProvider = StateProvider<Set<String>>((ref) => {});
final fileClipboardProvider = StateProvider<ClipboardData?>((ref) => null);

final fileSearchWatcher = Provider<void>((ref) {
  final query = ref.watch(fileSearchQueryProvider);
  final workspace = ref.watch(workspaceProvider).currentPath;

  if (query.isEmpty || workspace == null || workspace.isEmpty) return;

  // Debounce: wait 300ms after the user stops typing before scanning the FS.
  // Each rebuild of this provider cancels the previous timer via ref.onDispose.
  final debounce = Timer(const Duration(milliseconds: 300), () async {
    final dir = Directory(workspace);
    if (!await dir.exists()) return;

    final matchingParents = <String>{};
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        final name = p.basename(entity.path);
        if (name == '.git' || name == 'node_modules' || name == '.dart_tool') continue;
        if (entity.path.contains('/.git/') ||
            entity.path.contains('/node_modules/') ||
            entity.path.contains('/.dart_tool/')) {
          continue;
        }

        if (name.toLowerCase().contains(query.toLowerCase())) {
          final parent = entity.parent.path;
          var current = parent;
          while (current.startsWith(workspace) && current.length >= workspace.length) {
            matchingParents.add(current);
            if (current == workspace) break;
            current = p.dirname(current);
          }
        }
      }
    } catch (_) {
      // Ignore permission / filesystem errors
    }

    if (matchingParents.isNotEmpty) {
      final currentExpanded = ref.read(expandedFoldersProvider);
      ref.read(expandedFoldersProvider.notifier).setExpanded({
        ...currentExpanded,
        ...matchingParents,
      });
    }
  });

  // Cancel the timer if the query changes before it fires
  ref.onDispose(debounce.cancel);
});

class ClipboardData {
  final List<String> paths;
  final bool isCut;
  ClipboardData({required this.paths, required this.isCut});
}

class CompactedEntity {
  final FileSystemEntity entity;
  final String visualName;
  CompactedEntity(this.entity, this.visualName);
}

class FileTreeNode extends ConsumerStatefulWidget {
  final String path;
  final String name;
  final String? visualName;
  final bool isDirectory;
  final Function() onRefreshParent;
  final int depth;
  final bool isLast;
  final List<bool> ancestorIsLast;

  const FileTreeNode({
    super.key,
    required this.path,
    required this.name,
    this.visualName,
    required this.isDirectory,
    required this.onRefreshParent,
    this.depth = 0,
    this.isLast = false,
    this.ancestorIsLast = const [],
  });

  @override
  ConsumerState<FileTreeNode> createState() => _FileTreeNodeState();
}

class _FileTreeNodeState extends ConsumerState<FileTreeNode> {
  List<CompactedEntity>? _children;
  StreamSubscription<FileSystemEvent>? _watcherSubscription;

  bool _isCreatingFile = false;
  bool _isCreatingFolder = false;
  bool _isRenaming = false;
  TextEditingController? _inlineController;
  final FocusNode _inlineFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _stopWatching();
    _inlineFocusNode.dispose();
    _inlineController?.dispose();
    super.dispose();
  }

  void _startWatching() {
    _stopWatching();
    try {
      _watcherSubscription = Directory(widget.path).watch().listen((event) {
        _loadChildren();
      });
    } catch (e) {
      // Watcher might not be supported on this filesystem / OS config
    }
  }

  void _stopWatching() {
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
  }

  Future<void> _loadChildren() async {
    if (!widget.isDirectory) return;
    try {
      final dir = Directory(widget.path);
      if (!await dir.exists()) return;
      
      final entities = <FileSystemEntity>[];
      final sortMode = ref.read(fileSortModeProvider);

      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        // Simple filter for common noise
        if (name == '.git' || name == 'node_modules' || name == '.dart_tool') continue;
        
        entities.add(entity);
      }

      // Resolve compacted children
      final resolvedEntities = <CompactedEntity>[];
      for (final entity in entities) {
        if (entity is Directory) {
          var currentDir = entity;
          var visualName = p.basename(entity.path);
          while (true) {
            try {
              final list = await currentDir.list().toList();
              // Filter out noise
              final filteredList = list.where((e) {
                final name = p.basename(e.path);
                return name != '.git' && name != 'node_modules' && name != '.dart_tool';
              }).toList();
              
              final subdirs = filteredList.whereType<Directory>().toList();
              final files = filteredList.whereType<File>().toList();
              if (subdirs.length == 1 && files.isEmpty) {
                currentDir = subdirs.first;
                visualName = '$visualName/${p.basename(currentDir.path)}';
              } else {
                break;
              }
            } catch (e) {
              break;
            }
          }
          resolvedEntities.add(CompactedEntity(currentDir, visualName));
        } else {
          resolvedEntities.add(CompactedEntity(entity, p.basename(entity.path)));
        }
      }

      // Sorting logic
      if (sortMode == FileSortMode.name) {
        resolvedEntities.sort((a, b) {
          final aIsDir = a.entity is Directory;
          final bIsDir = b.entity is Directory;
          if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
          return p.basename(a.entity.path).toLowerCase().compareTo(p.basename(b.entity.path).toLowerCase());
        });
      } else {
        // For size and date, we fetch stats once
        final List<MapEntry<CompactedEntity, FileStat>> stats = [];
        for (final e in resolvedEntities) {
          stats.add(MapEntry(e, await e.entity.stat()));
        }

        stats.sort((a, b) {
          final aIsDir = a.key.entity is Directory;
          final bIsDir = b.key.entity is Directory;
          if (aIsDir != bIsDir) return aIsDir ? -1 : 1;

          switch (sortMode) {
            case FileSortMode.size:
              return b.value.size.compareTo(a.value.size);
            case FileSortMode.date:
              return b.value.modified.compareTo(a.value.modified);
            default:
              return p.basename(a.key.entity.path).toLowerCase().compareTo(p.basename(b.key.entity.path).toLowerCase());
          }
        });
        
        resolvedEntities.clear();
        resolvedEntities.addAll(stats.map((e) => e.key));
      }
      
      if (mounted) {
        setState(() {
          _children = resolvedEntities;
        });
        _startWatching();
      }
    } catch (e) {
      // Ignore permission errors etc
    }
  }

  void _toggleExpanded() {
    final isCurrentlyExpanded = ref.read(expandedFoldersProvider).contains(widget.path);
    ref.read(expandedFoldersProvider.notifier).toggleExpanded(widget.path);
    if (isCurrentlyExpanded) {
      _stopWatching();
    } else {
      if (_children == null) _loadChildren();
    }
  }

  Color _getGitStatusColor(WidgetRef ref) {
    final gitState = ref.watch(gitProvider);
    final status = gitState.status;
    if (status == null) return Colors.white;

    final currentWorkspace = ref.read(workspaceProvider).currentPath;
    if (currentWorkspace == null) return Colors.white;
    final relativePath = p.relative(widget.path, from: currentWorkspace);
    
    if (widget.isDirectory) {
      if (status.modifiedFiles.any((f) => f.startsWith('$relativePath/'))) return Colors.blueAccent;
      if (status.stagedFiles.any((f) => f.startsWith('$relativePath/'))) return Colors.greenAccent;
      if (status.untrackedFiles.any((f) => f.startsWith('$relativePath/'))) return Colors.orangeAccent;
    } else {
      if (status.modifiedFiles.contains(relativePath)) return Colors.blueAccent;
      if (status.stagedFiles.contains(relativePath)) return Colors.greenAccent;
      if (status.untrackedFiles.contains(relativePath)) return Colors.orangeAccent;
    }
    
    return Colors.white70;
  }

  bool _hasAIPending(WidgetRef ref) {
    final aiState = ref.watch(aiProvider);
    if (widget.isDirectory) {
      return aiState.proposedActions.any((a) => a.path.startsWith('${widget.path}/'));
    } else {
      return aiState.proposedActions.any((a) => a.path == widget.path);
    }
  }

  Widget _buildAIBadge(WidgetRef ref) {
    final aiState = ref.watch(aiProvider);

    if (widget.isDirectory) {
      final actions = aiState.proposedActions.where((a) => a.path.startsWith('${widget.path}/')).toList();
      // Check if any files in this dir were read by agent
      final hasReadFiles = aiState.agentReadFiles.any((f) => f.startsWith('${widget.path}/'));
      if (actions.isEmpty && !hasReadFiles) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (actions.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.sparkles, size: 8, color: Colors.purpleAccent),
                    const SizedBox(width: 2),
                    Text(
                      '${actions.length}',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.purpleAccent),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // Check if agent READ this file (shows eye icon — AI is aware)
    final wasReadByAgent = aiState.agentReadFiles.contains(widget.path);

    // For files: find matching pending action
    final action = aiState.proposedActions.firstWhere(
      (a) => a.path == widget.path,
      orElse: () => AIAction(type: '', path: '', content: ''),
    );
    final hasPendingAction = action.path.isNotEmpty;

    if (!hasPendingAction && !wasReadByAgent) return const SizedBox.shrink();

    final additions = action.additions ?? 0;
    final deletions = action.deletions ?? 0;
    
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Eye icon — AI read this file
          if (wasReadByAgent && !hasPendingAction) ...[
            const Icon(LucideIcons.eye, size: 10, color: Colors.cyanAccent),
            const SizedBox(width: 3),
          ],
          if (hasPendingAction) ...[
            // Action type indicator dot
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: action.type == 'create'
                    ? const Color(0xFF4EC994)
                    : action.type == 'delete'
                        ? const Color(0xFFFF6B6B)
                        : Colors.purpleAccent,
              ),
            ),
            // Show diff stats if available
            if (additions > 0)
              Text(
                '+$additions',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4EC994),
                ),
              ),
            if (additions > 0 && deletions > 0)
              const SizedBox(width: 2),
            if (deletions > 0)
              Text(
                '-$deletions',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6B6B),
                ),
              ),
            // If no stats available yet, show action type letter
            if (additions == 0 && deletions == 0)
              Text(
                action.type == 'create' ? 'A' : action.type == 'delete' ? 'D' : 'M',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: action.type == 'create'
                      ? const Color(0xFF4EC994)
                      : action.type == 'delete'
                          ? const Color(0xFFFF6B6B)
                          : Colors.purpleAccent,
                ),
              ),
          ],
        ],
      ),
    );
  }



  Widget _buildGitBadge(Color color, WidgetRef ref) {
    final gitState = ref.read(gitProvider);
    final status = gitState.status;
    if (status == null) return const SizedBox.shrink();

    final currentWorkspace = ref.read(workspaceProvider).currentPath;
    if (currentWorkspace == null) return const SizedBox.shrink();
    final relativePath = p.relative(widget.path, from: currentWorkspace);
    String letter = '';
    
    if (widget.isDirectory) {
      if (status.modifiedFiles.any((f) => f.startsWith('$relativePath/'))) {
        letter = 'M';
      } else if (status.stagedFiles.any((f) => f.startsWith('$relativePath/'))) {
        letter = 'A';
      } else if (status.untrackedFiles.any((f) => f.startsWith('$relativePath/'))) {
        letter = 'U';
      }
    } else {
      if (status.modifiedFiles.contains(relativePath)) {
        letter = 'M';
      } else if (status.stagedFiles.contains(relativePath)) {
        letter = 'A';
      } else if (status.untrackedFiles.contains(relativePath)) {
        letter = 'U';
      }
    }

    if (letter.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildFileNameText(String name, String searchQuery, Color gitColor) {
    if (searchQuery.isEmpty) {
      return Text(
        name,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: widget.isDirectory ? FontWeight.w500 : FontWeight.normal,
          color: gitColor,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final startIndex = name.toLowerCase().indexOf(searchQuery.toLowerCase());
    if (startIndex == -1) {
      return Text(
        name,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: widget.isDirectory ? FontWeight.w500 : FontWeight.normal,
          color: gitColor,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final endIndex = startIndex + searchQuery.length;
    final before = name.substring(0, startIndex);
    final match = name.substring(startIndex, endIndex);
    final after = name.substring(endIndex);

    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: widget.isDirectory ? FontWeight.w500 : FontWeight.normal,
          color: gitColor,
          fontFamily: GoogleFonts.inter().fontFamily,
        ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: const TextStyle(
              color: Colors.yellowAccent,
              backgroundColor: Colors.black45,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }


  void _submitRename() async {
    final newName = _inlineController?.text;
    if (newName != null && newName.isNotEmpty && newName != widget.name) {
      final newPath = p.join(p.dirname(widget.path), newName);
      await ref.read(projectServiceProvider.notifier).mirrorDelete(widget.path);
      if (widget.isDirectory) {
        await Directory(widget.path).rename(newPath);
      } else {
        await File(widget.path).rename(newPath);
      }
      await ref.read(projectServiceProvider.notifier).mirrorEntity(newPath);
      widget.onRefreshParent();
    }
    setState(() {
      _isRenaming = false;
    });
  }

  void _submitCreate(bool isDir) async {
    final name = _inlineController?.text;
    if (name != null && name.isNotEmpty) {
      final newPath = p.join(widget.path, name);
      if (isDir) {
        await Directory(newPath).create();
      } else {
        await File(newPath).create();
      }
      
      // Mirror to external storage
      await ref.read(projectServiceProvider.notifier).mirrorEntity(newPath);

      final expandedSet = ref.read(expandedFoldersProvider);
      if (!expandedSet.contains(widget.path)) {
        _toggleExpanded();
      } else {
        _loadChildren();
      }
    }
    setState(() {
      _isCreatingFile = false;
      _isCreatingFolder = false;
    });
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) async {
    final selectedPaths = ref.read(selectedPathsProvider);
    final hasSelection = selectedPaths.isNotEmpty;
    final pathsToProcess = hasSelection ? selectedPaths.toList() : [widget.path];
    final l10n = AppLocalizations.of(context)!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xff1e1e24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.trash_2, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(l10n.confirmDelete, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          l10n.confirmDeleteMultiple(pathsToProcess.length),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (final path in pathsToProcess) {
        await ref.read(projectServiceProvider.notifier).mirrorDelete(path);
        if (FileSystemEntity.isDirectorySync(path)) {
          await Directory(path).delete(recursive: true);
        } else {
          await File(path).delete();
        }
      }
      ref.read(selectedPathsProvider.notifier).state = {};
      widget.onRefreshParent();
    }
  }

  void _handlePaste() async {
    final clipboard = ref.read(fileClipboardProvider);
    if (clipboard == null) return;

    final targetDir = widget.isDirectory ? widget.path : p.dirname(widget.path);

    for (final sourcePath in clipboard.paths) {
      final name = p.basename(sourcePath);
      final destPath = p.join(targetDir, name);

      if (clipboard.isCut) {
        if (FileSystemEntity.isDirectorySync(sourcePath)) {
          await Directory(sourcePath).rename(destPath);
        } else {
          await File(sourcePath).rename(destPath);
        }
        await ref.read(projectServiceProvider.notifier).mirrorDelete(sourcePath);
      } else {
        // Copy logic (simplified)
        if (FileSystemEntity.isDirectorySync(sourcePath)) {
          // Recursive copy would be needed here
        } else {
          await File(sourcePath).copy(destPath);
        }
      }
      await ref.read(projectServiceProvider.notifier).mirrorEntity(destPath);
    }

    if (clipboard.isCut) ref.read(fileClipboardProvider.notifier).state = null;
    _loadChildren();
    widget.onRefreshParent();
  }

  void _extractZip(BuildContext context, WidgetRef ref, String path) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
      await ref.read(fileExplorerProvider.notifier).extractZip(path);
      if (context.mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.archiveExtracted)),
        );
        _loadChildren();
        widget.onRefreshParent();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.executionError(e.toString()))),
        );
      }
    }
  }

  void _showCompressDialog(BuildContext context, WidgetRef ref, List<String> paths) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: 'archive');
    final zipName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.compressToZip, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.nameFileHint,
            hintStyle: const TextStyle(color: Colors.white24),
            suffixText: '.zip',
            suffixStyle: const TextStyle(color: Colors.white54),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6C63FF))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.compressToZip.split(' ').first, style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (zipName != null && zipName.isNotEmpty) {
      try {
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          );
        }
        
        await ref.read(fileExplorerProvider.notifier).compressToZip(paths, zipName);
        
        if (context.mounted) {
          Navigator.pop(context); // close progress
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.archiveCreated)),
          );
          ref.read(selectedPathsProvider.notifier).state = {};
          _loadChildren();
          widget.onRefreshParent();
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context); // close progress
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.executionError(e.toString()))),
          );
        }
      }
    }
  }

  void _handleAiAsk(BuildContext context, WidgetRef ref, {String? presetQuery}) async {
    final controller = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    String? instruction = presetQuery;
    instruction ??= await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF13151A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(LucideIcons.sparkles, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                l10n.askAi,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isDirectory
                    ? l10n.folderLabel(widget.name)
                    : l10n.fileLabel(widget.name),
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.isDirectory
                      ? l10n.whatShouldAiDoFolder
                      : l10n.whatShouldAiDoFile,
                  hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.cyanAccent, width: 0.8),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l10n.cancel,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
                foregroundColor: Colors.cyanAccent,
                elevation: 0,
                side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                l10n.send,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

    if (instruction == null || instruction.trim().isEmpty) return;

    String content = '';
    if (!widget.isDirectory) {
      try {
        content = await File(widget.path).readAsString();
      } catch (e) {
        content = '[Could not read file]';
      }
    }

    final prompt = widget.isDirectory
        ? """
I am working in directory: `${widget.path}`.
User request:
$instruction

Please fulfill this request. If you need to modify or create files/folders, or run a command in the terminal, use the actions format <actions>.
"""
        : """
I am working on file: `${widget.path}`.
Its current content:
```
$content
```

User request:
$instruction

Please fulfill this request. If you need to modify the file, create a new one, delete, or run a command in the terminal, use the actions format <actions>.
""";

    ref.read(aiProvider.notifier).askAI(prompt);
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
  }

  void _showBottomSheetMenu(BuildContext context, WidgetRef ref) {
    final selectedPaths = ref.read(selectedPathsProvider);
    final hasSelection = selectedPaths.isNotEmpty;
    final clipboard = ref.read(fileClipboardProvider);
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff18181b),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      hasSelection ? l10n.selectedObjectsCount(selectedPaths.length) : widget.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  if (!hasSelection) ...[
                    _buildBottomSheetItem(
                      icon: LucideIcons.sparkles,
                      title: l10n.askAi,
                      subtitle: l10n.askAiDesc,
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _handleAiAsk(context, ref);
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.book_open,
                      title: l10n.explainStructure,
                      subtitle: l10n.explainStructureDesc,
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _handleAiAsk(context, ref, presetQuery: widget.isDirectory
                            ? l10n.explainFolderPreset
                            : l10n.explainFilePreset);
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.file_text,
                      title: l10n.addDoc,
                      subtitle: l10n.addDocDesc,
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _handleAiAsk(context, ref, presetQuery: widget.isDirectory
                            ? l10n.addDocFolderPreset
                            : l10n.addDocFilePreset);
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.shield_check,
                      title: l10n.generateTests,
                      subtitle: l10n.generateTestsDesc,
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _handleAiAsk(context, ref, presetQuery: widget.isDirectory
                            ? l10n.generateTestsFolderPreset
                            : l10n.generateTestsFilePreset);
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.zap,
                      title: l10n.optimizeCode,
                      subtitle: l10n.optimizeCodeDesc,
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _handleAiAsk(context, ref, presetQuery: widget.isDirectory
                            ? l10n.optimizeFolderPreset
                            : l10n.optimizeFilePreset);
                      },
                    ),
                    const Divider(color: Colors.white10),
                  ],
                  if (widget.isDirectory && !hasSelection) ...[
                    _buildBottomSheetItem(
                      icon: LucideIcons.file_plus,
                      title: l10n.newFile,
                      subtitle: l10n.newFileDesc,
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _inlineController = TextEditingController();
                          _isCreatingFile = true;
                          _isCreatingFolder = false;
                          _inlineFocusNode.requestFocus();
                        });
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.folder_plus,
                      title: l10n.newFolder,
                      subtitle: l10n.newFolderDesc,
                      color: Colors.orangeAccent,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _inlineController = TextEditingController();
                          _isCreatingFolder = true;
                          _isCreatingFile = false;
                          _inlineFocusNode.requestFocus();
                        });
                      },
                    ),
                    const Divider(color: Colors.white10),
                  ],
                  if (!widget.isDirectory && !hasSelection) ...[
                    (() {
                      final isBookmarked = ref.watch(bookmarksProvider).contains(widget.path);
                      return _buildBottomSheetItem(
                        icon: LucideIcons.star,
                        title: isBookmarked ? l10n.removeFromBookmarks : l10n.addToBookmarks,
                        subtitle: isBookmarked ? l10n.removeFromBookmarksDesc : l10n.addToBookmarksDesc,
                        color: isBookmarked ? Colors.redAccent : Colors.amberAccent,
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(bookmarksProvider.notifier).toggleBookmark(widget.path);
                        },
                      );
                    }()),
                    const Divider(color: Colors.white10),
                  ],
                  _buildBottomSheetItem(
                    icon: LucideIcons.copy,
                    title: l10n.copy,
                    subtitle: l10n.copyDesc,
                    color: Colors.white70,
                    onTap: () {
                      Navigator.pop(context);
                      final pathsToProcess = hasSelection ? selectedPaths.toList() : [widget.path];
                      ref.read(fileClipboardProvider.notifier).state = ClipboardData(paths: pathsToProcess, isCut: false);
                    },
                  ),
                  _buildBottomSheetItem(
                    icon: LucideIcons.scissors,
                    title: l10n.cut,
                    subtitle: l10n.cutDesc,
                    color: Colors.white70,
                    onTap: () {
                      Navigator.pop(context);
                      final pathsToProcess = hasSelection ? selectedPaths.toList() : [widget.path];
                      ref.read(fileClipboardProvider.notifier).state = ClipboardData(paths: pathsToProcess, isCut: true);
                    },
                  ),
                  if (clipboard != null && widget.isDirectory && !hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.clipboard_paste,
                      title: l10n.paste,
                      subtitle: l10n.pasteDesc,
                      color: Colors.greenAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _handlePaste();
                      },
                    ),
                  if (!hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.pencil,
                      title: l10n.rename,
                      subtitle: l10n.renameDesc,
                      color: Colors.white70,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _inlineController = TextEditingController(text: widget.name);
                          _isRenaming = true;
                          _inlineFocusNode.requestFocus();
                        });
                      },
                    ),
                  if (!hasSelection) ...[
                    if (widget.name.toLowerCase().endsWith('.zip'))
                      _buildBottomSheetItem(
                        icon: LucideIcons.file_archive,
                        title: l10n.extractZip,
                        subtitle: l10n.extractZipDesc,
                        color: Colors.greenAccent,
                        onTap: () {
                          Navigator.pop(context);
                          _extractZip(context, ref, widget.path);
                        },
                      )
                    else
                      _buildBottomSheetItem(
                        icon: LucideIcons.file_archive,
                        title: l10n.compressZip,
                        subtitle: l10n.compressZipDesc,
                        color: Colors.amberAccent,
                        onTap: () {
                          Navigator.pop(context);
                          _showCompressDialog(context, ref, [widget.path]);
                        },
                      ),
                  ],
                  if (hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.file_archive,
                      title: l10n.compressSelectedZip,
                      subtitle: l10n.compressSelectedZipDesc,
                      color: Colors.amberAccent,
                      onTap: () {
                        Navigator.pop(context);
                        _showCompressDialog(context, ref, selectedPaths.toList());
                      },
                    ),
                  _buildBottomSheetItem(
                    icon: LucideIcons.trash_2,
                    title: hasSelection ? l10n.deleteSelected : l10n.delete,
                    subtitle: l10n.deleteDesc,
                    color: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _confirmDelete(context, ref);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      onTap: onTap,
    );
  }

  Widget _buildInlineRenameField() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inlineController,
              focusNode: _inlineFocusNode,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.blueAccent, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
                ),
              ),
              onSubmitted: (val) => _submitRename(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(LucideIcons.check, size: 14, color: Colors.greenAccent),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _submitRename,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 14, color: Colors.redAccent),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _isRenaming = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCreateField({required bool isDir}) {
    final indentGuides = <Widget>[];
    if (widget.depth > -1) {
      for (int i = 0; i <= widget.depth; i++) {
        final isNodeConnector = i == widget.depth;
        final showLine = isNodeConnector ? true : !widget.ancestorIsLast[i];
        indentGuides.add(
          _GuideSegment(
            width: 16,
            height: 24,
            lineColor: Colors.white.withValues(alpha: 0.08),
            showVertical: showLine,
            isNodeConnector: isNodeConnector,
            isLast: false,
          ),
        );
      }
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: indentGuides,
          ),
          const SizedBox(width: 16),
          Icon(
            isDir ? LucideIcons.folder : LucideIcons.file,
            size: 18,
            color: isDir ? Colors.blue.shade400 : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inlineController,
                      focusNode: _inlineFocusNode,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: isDir
                            ? AppLocalizations.of(context)!.nameFolderHint
                            : AppLocalizations.of(context)!.nameFileHint,
                        hintStyle: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(color: Colors.blueAccent, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
                        ),
                      ),
                      onSubmitted: (val) => _submitCreate(isDir),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(LucideIcons.check, size: 14, color: Colors.greenAccent),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _submitCreate(isDir),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 14, color: Colors.redAccent),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _isCreatingFile = false;
                        _isCreatingFolder = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expandedFolders = ref.watch(expandedFoldersProvider);
    final isExpanded = expandedFolders.contains(widget.path);

    if (widget.isDirectory) {
      if (isExpanded) {
        if (_children == null) {
          Future.microtask(() => _loadChildren());
        }
      } else {
        _stopWatching();
      }
    }

    final searchQuery = ref.watch(fileSearchQueryProvider);
    if (searchQuery.isNotEmpty && !widget.isDirectory && !widget.name.toLowerCase().contains(searchQuery.toLowerCase())) {
      return const SizedBox.shrink();
    }

    final isSelected = ref.watch(selectedPathsProvider).contains(widget.path);
    final gitColor = _getGitStatusColor(ref);

    return _buildNode(gitColor, isSelected, isExpanded);
  }

  Widget _buildNode(Color gitColor, bool isSelected, bool isExpanded) {
    final searchQuery = ref.watch(fileSearchQueryProvider);
    final indentGuides = <Widget>[];
    if (widget.depth > 0) {
      for (int i = 0; i < widget.depth; i++) {
        final isNodeConnector = i == widget.depth - 1;
        final showLine = isNodeConnector ? true : !widget.ancestorIsLast[i];
        indentGuides.add(
          _GuideSegment(
            width: 12,
            height: 20,
            lineColor: Colors.white.withValues(alpha: 0.08),
            showVertical: showLine,
            isNodeConnector: isNodeConnector,
            isLast: widget.isLast,
          ),
        );
      }
    }

    final nodeContent = InkWell(
      onTap: () async {
        if (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed) {
          final selected = {...ref.read(selectedPathsProvider)};
          if (selected.contains(widget.path)) {
            selected.remove(widget.path);
          } else {
            selected.add(widget.path);
          }
          ref.read(selectedPathsProvider.notifier).state = selected;
          return;
        }

        if (widget.isDirectory) {
          _toggleExpanded();
        } else if (widget.name.toLowerCase().endsWith('.apk')) {
          try {
            await OpenFilex.open(widget.path);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error opening APK: $e')),
              );
            }
          }
        } else {
          final ext = p.extension(widget.path).toLowerCase();
          final isPreviewable = ext == '.md' || 
              ext == '.png' || 
              ext == '.jpg' || 
              ext == '.jpeg' || 
              ext == '.gif' || 
              ext == '.webp';
          if (isPreviewable) {
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FilePreviewPage(filePath: widget.path),
                ),
              );
            }
          } else {
            await ref.read(editorProvider.notifier).openFile(widget.path);
            if (mounted) {
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold != null && (scaffold.isDrawerOpen || scaffold.isEndDrawerOpen)) {
                Navigator.pop(context);
              }
            }
          }
        }
      },
      onLongPress: () => _showBottomSheetMenu(context, ref),
      child: Container(
        color: isSelected 
            ? Colors.blue.withValues(alpha: 0.15) 
            : (_hasAIPending(ref) && !widget.isDirectory)
                ? Colors.purpleAccent.withValues(alpha: 0.06)
                : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 6.0),
        child: Row(
          children: [
            if (widget.depth > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: indentGuides,
              ),
            if (widget.isDirectory)
              Icon(isExpanded ? LucideIcons.chevron_down : LucideIcons.chevron_right, size: 14, color: Colors.grey)
            else
              const SizedBox(width: 12),
            const SizedBox(width: 3),
            () {
              final iconInfo = FileIconHelper.getIconInfo(widget.visualName ?? widget.name, widget.isDirectory, isExpanded);
              return Icon(
                iconInfo.icon,
                size: 15,
                color: iconInfo.color,
              );
            }(),
            const SizedBox(width: 6),
            Expanded(
              child: _isRenaming
                  ? _buildInlineRenameField()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: _buildFileNameText(
                            widget.visualName ?? widget.name,
                            searchQuery,
                            _hasAIPending(ref) ? Colors.purpleAccent : gitColor,
                          ),
                        ),
                        if (!widget.isDirectory && ref.watch(bookmarksProvider).contains(widget.path)) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            LucideIcons.star,
                            size: 10,
                            color: Colors.amberAccent,
                          ),
                        ],
                      ],
                    ),
            ),
            if (!_isRenaming) ...[
              _buildAIBadge(ref),
              if (gitColor != Colors.white70 && gitColor != Colors.white)
                _buildGitBadge(gitColor, ref),
            ],
            if (!_isRenaming)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showBottomSheetMenu(context, ref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                  child: Icon(
                    LucideIcons.ellipsis_vertical,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            final draggedPath = details.data;
            if (draggedPath == widget.path) return false;
            if (!widget.isDirectory) return false;
            if (widget.path.startsWith('$draggedPath/')) return false;
            return true;
          },
          onAcceptWithDetails: (details) async {
            final draggedPath = details.data;
            try {
              await ref.read(fileExplorerProvider.notifier).moveEntity(draggedPath, widget.path);
              if (mounted) {
                final l10n = AppLocalizations.of(context)!;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.itemMoved)),
                );
                _loadChildren();
                widget.onRefreshParent();
              }
            } catch (e) {
              if (mounted) {
                final l10n = AppLocalizations.of(context)!;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.moveError(e.toString()))),
                );
              }
            }
          },
          builder: (context, candidateData, rejectedData) {
            final isOver = candidateData.isNotEmpty;
            final isMobile = Platform.isAndroid || Platform.isIOS;

            final childWidget = Container(
              decoration: BoxDecoration(
                color: isOver ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: nodeContent,
            );

            if (isMobile) {
              return childWidget;
            }

            return Draggable<String>(
              data: widget.path,
              feedback: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2230),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isDirectory ? LucideIcons.folder : LucideIcons.file,
                        size: 14,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.name,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: nodeContent,
              ),
              child: childWidget,
            );
          },
        ),
        if (widget.isDirectory && isExpanded && _children != null) ...[
          if (_isCreatingFile || _isCreatingFolder)
            _buildInlineCreateField(isDir: _isCreatingFolder),
          if (_children!.isEmpty && !_isCreatingFile && !_isCreatingFolder)
            Padding(
              padding: EdgeInsets.only(
                left: (widget.depth + 1) * 12.0 + 15.0,
                top: 3.0,
                bottom: 3.0,
              ),
              child: Text(
                AppLocalizations.of(context)!.empty,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            )
          else
            ..._children!.asMap().entries.map((entry) {
              final index = entry.key;
              final compacted = entry.value;
              final entryIsLast = index == _children!.length - 1;
              return FileTreeNode(
                key: ValueKey(compacted.entity.path),
                path: compacted.entity.path,
                name: p.basename(compacted.entity.path),
                visualName: compacted.visualName,
                isDirectory: compacted.entity is Directory,
                onRefreshParent: _loadChildren,
                depth: widget.depth + 1,
                isLast: entryIsLast,
                ancestorIsLast: [...widget.ancestorIsLast, widget.isLast],
              );
            }),
        ],
      ],
    );
  }
}

class _GuideSegment extends StatelessWidget {
  final double width;
  final double height;
  final Color lineColor;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegment({
    required this.width,
    required this.height,
    required this.lineColor,
    required this.showVertical,
    this.isNodeConnector = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _GuideSegmentPainter(
          color: lineColor,
          showVertical: showVertical,
          isNodeConnector: isNodeConnector,
          isLast: isLast,
        ),
      ),
    );
  }
}

class _GuideSegmentPainter extends CustomPainter {
  final Color color;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegmentPainter({
    required this.color,
    required this.showVertical,
    required this.isNodeConnector,
    required this.isLast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final x = size.width / 2;
    final yMid = size.height / 2;

    if (showVertical && !isNodeConnector) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }

    if (!isNodeConnector) return;

    // Draw vertical connector from top to mid
    canvas.drawLine(Offset(x, 0), Offset(x, yMid), paint);
    
    // Draw horizontal branch line to the right
    canvas.drawLine(Offset(x, yMid), Offset(size.width, yMid), paint);
    
    // Draw vertical line from mid to bottom if not the last item in folder
    if (!isLast) {
      canvas.drawLine(Offset(x, yMid), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuideSegmentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.showVertical != showVertical ||
        oldDelegate.isNodeConnector != isNodeConnector ||
        oldDelegate.isLast != isLast;
  }
}
