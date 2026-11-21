import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide ClipboardData;
import 'package:flutter/services.dart' as services show Clipboard, ClipboardData;
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import '../notifiers/editor_notifier.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/core/utils/share_utils.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/bookmarks_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';

class FileTreeFilter {
  static const Set<String> ignoredDirNames = {
    '.git',
    '.gradle',
    '.dart_tool',
    '.idea',
    '.vscode',
    '.cache',
    '.cxx',
    'node_modules',
    '.pub-cache',
    'Pods',
  };

  static bool isIgnoredPath(String path) {
    final parts = p.split(path);
    for (final part in parts) {
      if (ignoredDirNames.contains(part)) return true;
    }
    return false;
  }
}

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
      final cleaned = list.where((folder) => !FileTreeFilter.isIgnoredPath(folder)).toSet();
      state = cleaned;
      if (cleaned.length != list.length) {
        await prefs.setStringList('expanded_folders_$path', cleaned.toList());
      }
    } catch (e) {
      state = {};
    }
  }

  Future<void> toggleExpanded(String folderPath) async {
    if (FileTreeFilter.isIgnoredPath(folderPath)) return;
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
    final cleaned = newSet.where((folder) => !FileTreeFilter.isIgnoredPath(folder)).toSet();
    state = cleaned;
    final path = _currentWorkspacePath;
    if (path != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('expanded_folders_$path', cleaned.toList());
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
    int matchedCount = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (FileTreeFilter.isIgnoredPath(entity.path)) continue;

        final name = p.basename(entity.path);
        if (name.toLowerCase().contains(query.toLowerCase())) {
          final parent = entity.parent.path;
          var current = parent;
          while (current.startsWith(workspace) && current.length >= workspace.length) {
            if (!FileTreeFilter.isIgnoredPath(current)) {
              matchingParents.add(current);
            }
            if (current == workspace) break;
            current = p.dirname(current);
          }
          matchedCount++;
          if (matchedCount >= 50) break; // Strict safety threshold to prevent OOM
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
  Timer? _reloadDebounceTimer;

  bool _isCreatingFile = false;
  bool _isCreatingFolder = false;
  bool _isRenaming = false;
  bool _isHovered = false;
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
    if (_watcherSubscription != null || !widget.isDirectory) return;
    if (FileTreeFilter.isIgnoredPath(widget.path)) return;
    try {
      // Use lightweight non-recursive watcher for this single directory,
      // avoiding package:watcher's recursive tree crawling and infinite scan cascades
      _watcherSubscription = Directory(widget.path).watch(recursive: false).listen(
        (event) {
          _reloadDebounceTimer?.cancel();
          _reloadDebounceTimer = Timer(const Duration(milliseconds: 800), () {
            if (mounted) _loadChildren();
          });
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {
      // Watcher might not be supported on this filesystem
    }
  }

  void _stopWatching() {
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = null;
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
  }

  Future<void> _loadChildren() async {
    if (!widget.isDirectory || FileTreeFilter.isIgnoredPath(widget.path)) return;
    try {
      final dir = Directory(widget.path);
      if (!await dir.exists()) return;
      
      final entities = <FileSystemEntity>[];
      final sortMode = ref.read(fileSortModeProvider);
      final showHidden = ref.read(settingsProvider).showHiddenFiles;

      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (FileTreeFilter.ignoredDirNames.contains(name)) continue;
        if (FileTreeFilter.isIgnoredPath(entity.path)) continue;
        if (name.startsWith('.') && name != '.gitignore' && name != '.env' && name != '.editorconfig') {
          if (!showHidden) continue;
        }
        
        entities.add(entity);
      }

      // Resolve compacted children
      final resolvedEntities = <CompactedEntity>[];
      for (final entity in entities) {
        if (entity is Directory) {
          var currentDir = entity;
          var visualName = p.basename(entity.path);
          int compactDepth = 0;
          while (compactDepth < 10) {
            compactDepth++;
            try {
              final list = await currentDir.list().toList();
              final filteredList = list.where((e) {
                final name = p.basename(e.path);
                if (FileTreeFilter.ignoredDirNames.contains(name)) return false;
                if (FileTreeFilter.isIgnoredPath(e.path)) return false;
                if (name.startsWith('.') && name != '.gitignore' && name != '.env' && name != '.editorconfig') {
                  if (!showHidden) return false;
                }
                return true;
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
        if (_watcherSubscription == null) {
          _startWatching();
        }
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
      if (_children == null) {
        _loadChildren();
      } else {
        _startWatching();
      }
    }
  }

  Color _getGitStatusColor(WidgetRef ref) {
    final status = ref.watch(gitProvider.select((s) => s.status));
    if (status == null) return Colors.white;

    final currentWorkspace = ref.read(workspaceProvider).currentPath;
    if (currentWorkspace == null) return Colors.white;
    final relativePath = p.relative(widget.path, from: currentWorkspace);
    
    if (widget.isDirectory) {
      if (status.modifiedDirPrefixes.contains(relativePath)) return Colors.blueAccent;
      if (status.stagedDirPrefixes.contains(relativePath)) return Colors.greenAccent;
      if (status.untrackedDirPrefixes.contains(relativePath)) return Colors.orangeAccent;
    } else {
      if (status.modifiedSet.contains(relativePath)) return Colors.blueAccent;
      if (status.stagedSet.contains(relativePath)) return Colors.greenAccent;
      if (status.untrackedSet.contains(relativePath)) return Colors.orangeAccent;
    }
    
    return Colors.white70;
  }

  Widget _buildGitBadge(Color color, WidgetRef ref) {
    final status = ref.watch(gitProvider.select((s) => s.status));
    if (status == null) return const SizedBox.shrink();

    final currentWorkspace = ref.read(workspaceProvider).currentPath;
    if (currentWorkspace == null) return const SizedBox.shrink();
    final relativePath = p.relative(widget.path, from: currentWorkspace);
    String letter = '';
    int additions = 0;
    int deletions = 0;
    
    if (widget.isDirectory) {
      if (status.modifiedDirPrefixes.contains(relativePath)) {
        letter = 'M';
      } else if (status.stagedDirPrefixes.contains(relativePath)) {
        letter = 'A';
      } else if (status.untrackedDirPrefixes.contains(relativePath)) {
        letter = 'U';
      }
    } else {
      if (status.modifiedSet.contains(relativePath)) {
        letter = 'M';
      } else if (status.stagedSet.contains(relativePath)) {
        letter = 'A';
      } else if (status.untrackedSet.contains(relativePath)) {
        letter = 'U';
      }
      final stat = status.diffStats[relativePath];
      if (stat != null) {
        additions = stat.additions;
        deletions = stat.deletions;
      }
    }

    final showDiffStats = additions > 0 || deletions > 0;

    if (letter.isEmpty && !showDiffStats) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDiffStats && additions > 0)
            Padding(
              padding: const EdgeInsets.only(right: 3.0),
              child: Text(
                '+$additions',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4EC994),
                ),
              ),
            ),
          if (showDiffStats && deletions > 0)
            Padding(
              padding: const EdgeInsets.only(right: 3.0),
              child: Text(
                '-$deletions',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6B6B),
                ),
              ),
            ),
          if (letter.isNotEmpty)
            Container(
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
        ],
      ),
    );
  }

  Widget _buildFileNameText(
    String name,
    String searchQuery,
    Color gitColor, {
    bool isTouchLayout = false,
    bool isActiveFile = false,
  }) {
    final fontSize = isTouchLayout ? 13.5 : 12.5;
    final fontWeight = isActiveFile
        ? FontWeight.w600
        : (widget.isDirectory ? FontWeight.w500 : FontWeight.normal);
    final textColor = isActiveFile && (gitColor == Colors.white70 || gitColor == Colors.white)
        ? Colors.white
        : gitColor;

    if (searchQuery.isEmpty) {
      return Text(
        name,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: textColor,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final startIndex = name.toLowerCase().indexOf(searchQuery.toLowerCase());
    if (startIndex == -1) {
      return Text(
        name,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: textColor,
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
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: textColor,
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

  Future<void> _submitRename() async {
    final newName = _inlineController?.text.trim();
    if (newName != null && newName.isNotEmpty && newName != widget.name) {
      try {
        final newPath = p.join(p.dirname(widget.path), newName);
        if (widget.isDirectory) {
          await Directory(widget.path).rename(newPath);
        } else {
          await File(widget.path).rename(newPath);
        }
        if (!mounted) return;
        widget.onRefreshParent();
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorOccurred(e.toString()))),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _isRenaming = false;
    });
  }

  Future<void> _submitCreate(bool isDir) async {
    final name = _inlineController?.text.trim();
    if (name != null && name.isNotEmpty) {
      try {
        final newPath = p.join(widget.path, name);
        if (isDir) {
          await Directory(newPath).create();
        } else {
          await File(newPath).create();
        }

        if (!mounted) return;

        final expandedSet = ref.read(expandedFoldersProvider);
        if (!expandedSet.contains(widget.path)) {
          _toggleExpanded();
        } else {
          _loadChildren();
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorOccurred(e.toString()))),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _isCreatingFile = false;
      _isCreatingFolder = false;
    });
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final selectedPaths = ref.read(selectedPathsProvider);
    final hasSelection = selectedPaths.isNotEmpty;
    final pathsToProcess = hasSelection ? selectedPaths.toList() : [widget.path];
    final l10n = AppLocalizations.of(context)!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        for (final path in pathsToProcess) {
          if (FileSystemEntity.isDirectorySync(path)) {
            await Directory(path).delete(recursive: true);
          } else {
            await File(path).delete();
          }
        }
        if (!mounted) return;
        ref.read(selectedPathsProvider.notifier).state = {};
        widget.onRefreshParent();
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.deleteError(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _handlePaste() async {
    final clipboard = ref.read(fileClipboardProvider);
    if (clipboard == null) return;

    final targetDir = widget.isDirectory ? widget.path : p.dirname(widget.path);

    try {
      for (final sourcePath in clipboard.paths) {
        final name = p.basename(sourcePath);
        final destPath = p.join(targetDir, name);

        if (clipboard.isCut) {
          if (FileSystemEntity.isDirectorySync(sourcePath)) {
            await Directory(sourcePath).rename(destPath);
          } else {
            await File(sourcePath).rename(destPath);
          }
        } else {
          if (FileSystemEntity.isDirectorySync(sourcePath)) {
            await _copyDirectoryRecursive(Directory(sourcePath), Directory(destPath));
          } else {
            await File(sourcePath).copy(destPath);
          }
        }
      }

      if (!mounted) return;
      if (clipboard.isCut) ref.read(fileClipboardProvider.notifier).state = null;
      _loadChildren();
      widget.onRefreshParent();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pasteError(e.toString()))),
        );
      }
    }
  }

  Future<void> _copyDirectoryRecursive(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectoryRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
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

  Future<void> _showDesktopContextMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final l10n = AppLocalizations.of(context)!;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final copyPathLabel = isRu ? 'Копировать путь' : 'Copy Path';
    final clipboard = ref.read(fileClipboardProvider);
    final selectedPaths = ref.read(selectedPathsProvider);
    final hasSelection = selectedPaths.isNotEmpty;
    final isBookmarked = !widget.isDirectory && ref.read(bookmarksProvider).contains(widget.path);

    final items = <PopupMenuEntry<String>>[
      if (widget.isDirectory) ...[
        PopupMenuItem<String>(
          value: 'new_file',
          height: 34,
          child: Row(
            children: [
              const Icon(LucideIcons.file_plus, size: 15, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.newFile, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_folder',
          height: 34,
          child: Row(
            children: [
              const Icon(LucideIcons.folder_plus, size: 15, color: Colors.white70),
              const SizedBox(width: 8),
              Text(l10n.newFolder, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
      ],
      PopupMenuItem<String>(
        value: 'copy',
        height: 34,
        child: Row(
          children: [
            const Icon(LucideIcons.copy, size: 15, color: Colors.white70),
            const SizedBox(width: 8),
            Text(l10n.copy, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'cut',
        height: 34,
        child: Row(
          children: [
            const Icon(LucideIcons.scissors, size: 15, color: Colors.white70),
            const SizedBox(width: 8),
            Text(l10n.cut, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
          ],
        ),
      ),
      if (clipboard != null)
        PopupMenuItem<String>(
          value: 'paste',
          height: 34,
          child: Row(
            children: [
              const Icon(LucideIcons.clipboard_paste, size: 15, color: Colors.greenAccent),
              const SizedBox(width: 8),
              Text(l10n.paste, style: const TextStyle(fontSize: 12.5, color: Colors.greenAccent)),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'copy_path',
        height: 34,
        child: Row(
          children: [
            const Icon(LucideIcons.link, size: 15, color: Colors.white70),
            const SizedBox(width: 8),
            Text(copyPathLabel, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
          ],
        ),
      ),
      if (!widget.isDirectory)
        PopupMenuItem<String>(
          value: 'bookmark',
          height: 34,
          child: Row(
            children: [
              Icon(
                LucideIcons.star,
                size: 15,
                color: isBookmarked ? Colors.redAccent : Colors.amberAccent,
              ),
              const SizedBox(width: 8),
              Text(
                isBookmarked ? l10n.removeFromBookmarks : l10n.addToBookmarks,
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
      const PopupMenuDivider(height: 8),
      PopupMenuItem<String>(
        value: 'rename',
        height: 34,
        child: Row(
          children: [
            const Icon(LucideIcons.pencil, size: 15, color: Colors.white70),
            const SizedBox(width: 8),
            Text(l10n.rename, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        height: 34,
        child: Row(
          children: [
            const Icon(LucideIcons.trash_2, size: 15, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(l10n.delete, style: const TextStyle(fontSize: 12.5, color: Colors.redAccent)),
          ],
        ),
      ),
    ];

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF18181B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      items: items,
    );

    if (selected == null || !mounted || !context.mounted) return;
    switch (selected) {
      case 'new_file':
        _startInlineCreation(isDir: false);
        break;
      case 'new_folder':
        _startInlineCreation(isDir: true);
        break;
      case 'copy':
        final pathsToCopy = hasSelection ? selectedPaths.toList() : [widget.path];
        ref.read(fileClipboardProvider.notifier).state = ClipboardData(paths: pathsToCopy, isCut: false);
        break;
      case 'cut':
        final pathsToCut = hasSelection ? selectedPaths.toList() : [widget.path];
        ref.read(fileClipboardProvider.notifier).state = ClipboardData(paths: pathsToCut, isCut: true);
        break;
      case 'paste':
        await _handlePaste();
        break;
      case 'copy_path':
        await services.Clipboard.setData(services.ClipboardData(text: widget.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.copiedToClipboard)),
          );
        }
        break;
      case 'bookmark':
        ref.read(bookmarksProvider.notifier).toggleBookmark(widget.path);
        break;
      case 'rename':
        setState(() {
          _inlineController?.dispose();
          _inlineController = TextEditingController(text: widget.name);
          _isRenaming = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inlineFocusNode.requestFocus();
        });
        break;
      case 'delete':
        _confirmDelete(context, ref);
        break;
    }
  }

  void _showBottomSheetMenu(BuildContext context, WidgetRef ref) {
    final selectedPaths = ref.read(selectedPathsProvider);
    final hasSelection = selectedPaths.isNotEmpty;
    final clipboard = ref.read(fileClipboardProvider);
    final l10n = AppLocalizations.of(context)!;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final copyPathLabel = isRu ? 'Копировать путь' : 'Copy Path';
    final iconInfo = FileIconHelper.getIconInfo(widget.visualName ?? widget.name, widget.isDirectory, false);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      children: [
                        Icon(iconInfo.icon, size: 18, color: iconInfo.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasSelection ? l10n.selectedObjectsCount(selectedPaths.length) : widget.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 14),
                  if (widget.isDirectory && !hasSelection) ...[
                    _buildBottomSheetItem(
                      icon: LucideIcons.file_plus,
                      title: l10n.newFile,
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _startInlineCreation(isDir: false);
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.folder_plus,
                      title: l10n.newFolder,
                      color: Colors.orangeAccent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _startInlineCreation(isDir: true);
                      },
                    ),
                    const Divider(color: Colors.white10, height: 10),
                  ],
                  if (!widget.isDirectory && !hasSelection) ...[
                    (() {
                      final isBookmarked = ref.watch(bookmarksProvider).contains(widget.path);
                      return _buildBottomSheetItem(
                        icon: LucideIcons.star,
                        title: isBookmarked ? l10n.removeFromBookmarks : l10n.addToBookmarks,
                        color: isBookmarked ? Colors.redAccent : Colors.amberAccent,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          ref.read(bookmarksProvider.notifier).toggleBookmark(widget.path);
                        },
                      );
                    }()),
                  ],
                  _buildBottomSheetItem(
                    icon: LucideIcons.copy,
                    title: l10n.copy,
                    color: Colors.white70,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final pathsToProcess = hasSelection ? selectedPaths.toList() : [widget.path];
                      ref.read(fileClipboardProvider.notifier).state = ClipboardData(paths: pathsToProcess, isCut: false);
                    },
                  ),
                  _buildBottomSheetItem(
                    icon: LucideIcons.scissors,
                    title: l10n.cut,
                    color: Colors.white70,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final pathsToProcess = hasSelection ? selectedPaths.toList() : [widget.path];
                      ref.read(fileClipboardProvider.notifier).state = ClipboardData(paths: pathsToProcess, isCut: true);
                    },
                  ),
                  if (clipboard != null && widget.isDirectory && !hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.clipboard_paste,
                      title: l10n.paste,
                      color: Colors.greenAccent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _handlePaste();
                      },
                    ),
                  if (!hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.link,
                      title: copyPathLabel,
                      color: Colors.white70,
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await services.Clipboard.setData(services.ClipboardData(text: widget.path));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.copiedToClipboard)),
                          );
                        }
                      },
                    ),
                  if (!hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.pencil,
                      title: l10n.rename,
                      color: Colors.white70,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        setState(() {
                          _inlineController?.dispose();
                          _inlineController = TextEditingController(text: widget.name);
                          _isRenaming = true;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _inlineFocusNode.requestFocus();
                        });
                      },
                    ),
                  if (!hasSelection && widget.name.toLowerCase().endsWith('.apk')) ...[
                    const Divider(color: Colors.white10, height: 10),
                    _buildBottomSheetItem(
                      icon: LucideIcons.smartphone,
                      title: 'Установить APK',
                      color: const Color(0xFF3DDC84),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        try {
                          await OpenFilex.open(widget.path);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Ошибка установки: $e')),
                            );
                          }
                        }
                      },
                    ),
                    _buildBottomSheetItem(
                      icon: LucideIcons.share_2,
                      title: 'Поделиться APK',
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        ShareUtils.shareFile(widget.path);
                      },
                    ),
                  ] else if (!widget.isDirectory && !hasSelection) ...[
                    _buildBottomSheetItem(
                      icon: LucideIcons.share_2,
                      title: isRu ? 'Поделиться файлом' : 'Share file',
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        ShareUtils.shareFile(widget.path);
                      },
                    ),
                  ],
                  if (!hasSelection) ...[
                    if (widget.name.toLowerCase().endsWith('.zip'))
                      _buildBottomSheetItem(
                        icon: LucideIcons.file_archive,
                        title: l10n.extractZip,
                        color: Colors.greenAccent,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _extractZip(context, ref, widget.path);
                        },
                      )
                    else
                      _buildBottomSheetItem(
                        icon: LucideIcons.file_archive,
                        title: l10n.compressZip,
                        color: Colors.amberAccent,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showCompressDialog(context, ref, [widget.path]);
                        },
                      ),
                  ],
                  if (hasSelection)
                    _buildBottomSheetItem(
                      icon: LucideIcons.file_archive,
                      title: l10n.compressSelectedZip,
                      color: Colors.amberAccent,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showCompressDialog(context, ref, selectedPaths.toList());
                      },
                    ),
                  const Divider(color: Colors.white10, height: 10),
                  _buildBottomSheetItem(
                    icon: LucideIcons.trash_2,
                    title: hasSelection ? l10n.deleteSelected : l10n.delete,
                    color: Colors.redAccent,
                    onTap: () {
                      Navigator.pop(sheetContext);
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
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color == Colors.redAccent ? Colors.redAccent : Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11.5))
          : null,
      onTap: onTap,
    );
  }

  Widget _buildInlineRenameField({
    required bool isTouchLayout,
    required Color accentColor,
  }) {
    final fieldHeight = isTouchLayout ? 36.0 : 26.0;
    final btnSize = isTouchLayout ? 34.0 : 26.0;
    final iconSize = isTouchLayout ? 16.0 : 14.0;

    return SizedBox(
      height: fieldHeight,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inlineController,
              focusNode: _inlineFocusNode,
              autofocus: true,
              style: TextStyle(fontSize: isTouchLayout ? 13.5 : 12.5, color: Colors.white),
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: isTouchLayout ? 8 : 4,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: accentColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: accentColor, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _submitRename(),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: btnSize,
            height: btnSize,
            child: IconButton(
              icon: Icon(LucideIcons.check, size: iconSize, color: Colors.greenAccent),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: btnSize, height: btnSize),
              onPressed: _submitRename,
            ),
          ),
          SizedBox(
            width: btnSize,
            height: btnSize,
            child: IconButton(
              icon: Icon(LucideIcons.x, size: iconSize, color: Colors.redAccent),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: btnSize, height: btnSize),
              onPressed: () {
                setState(() {
                  _isRenaming = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCreateField({
    required bool isDir,
    required bool isTouchLayout,
    required Color accentColor,
  }) {
    final fieldHeight = isTouchLayout ? 36.0 : 26.0;
    final btnSize = isTouchLayout ? 34.0 : 26.0;
    final iconSize = isTouchLayout ? 16.0 : 14.0;
    final indentGuides = <Widget>[];
    if (widget.depth > -1) {
      for (int i = 0; i <= widget.depth; i++) {
        final isNodeConnector = i == widget.depth;
        final showLine = isNodeConnector ? true : !widget.ancestorIsLast[i];
        indentGuides.add(
          _GuideSegment(
            width: 12,
            lineColor: Colors.white.withValues(alpha: 0.08),
            showVertical: showLine,
            isNodeConnector: isNodeConnector,
            isLast: false,
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: indentGuides,
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Icon(
                isDir ? LucideIcons.folder : LucideIcons.file,
                size: isTouchLayout ? 16.5 : 15.0,
                color: isDir ? Colors.blue.shade400 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.0),
                child: SizedBox(
                  height: fieldHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inlineController,
                          focusNode: _inlineFocusNode,
                          autofocus: true,
                          style: TextStyle(fontSize: isTouchLayout ? 13.5 : 12.5, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: isDir
                                ? AppLocalizations.of(context)!.nameFolderHint
                                : AppLocalizations.of(context)!.nameFileHint,
                            hintStyle: TextStyle(
                              fontSize: isTouchLayout ? 12 : 11,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: isTouchLayout ? 8 : 4,
                            ),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: BorderSide(color: accentColor, width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: BorderSide(color: accentColor, width: 1.5),
                            ),
                          ),
                          onSubmitted: (_) => _submitCreate(isDir),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: btnSize,
                        height: btnSize,
                        child: IconButton(
                          icon: Icon(LucideIcons.check, size: iconSize, color: Colors.greenAccent),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints.tightFor(width: btnSize, height: btnSize),
                          onPressed: () => _submitCreate(isDir),
                        ),
                      ),
                      SizedBox(
                        width: btnSize,
                        height: btnSize,
                        child: IconButton(
                          icon: Icon(LucideIcons.x, size: iconSize, color: Colors.redAccent),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints.tightFor(width: btnSize, height: btnSize),
                          onPressed: () {
                            setState(() {
                              _isCreatingFile = false;
                              _isCreatingFolder = false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startInlineCreation({required bool isDir}) {
    final isCurrentlyExpanded = ref.read(expandedFoldersProvider).contains(widget.path);
    if (!isCurrentlyExpanded) {
      ref.read(expandedFoldersProvider.notifier).toggleExpanded(widget.path);
      if (_children == null) _loadChildren();
    }
    setState(() {
      _inlineController?.dispose();
      _inlineController = TextEditingController();
      _isCreatingFile = !isDir;
      _isCreatingFolder = isDir;
      _isRenaming = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineFocusNode.requestFocus();
    });
  }

  Widget _buildFolderQuickActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 2),
          child: Icon(icon, size: 12.5, color: Colors.white60),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (FileTreeFilter.isIgnoredPath(widget.path)) {
      return const SizedBox.shrink();
    }

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
    final isActiveFile = !widget.isDirectory &&
        ref.watch(editorProvider.select((s) => s.activeFilePath == widget.path));
    final gitColor = _getGitStatusColor(ref);

    return _buildNode(gitColor, isSelected, isExpanded, isActiveFile);
  }

  Widget _buildNode(Color gitColor, bool isSelected, bool isExpanded, bool isActiveFile) {
    final searchQuery = ref.watch(fileSearchQueryProvider);
    final isTouchLayout = MediaQuery.of(context).size.width < 768;
    final settings = ref.watch(settingsProvider);
    final palette = settings.syncAppWithTerminalPalette
        ? resolveConduitPalette(settings.terminalTheme)
        : null;
    final accentColor = palette?.accent ?? Theme.of(context).colorScheme.primary;

    final verticalPad = isTouchLayout ? 7.5 : 4.0;
    final iconSize = isTouchLayout ? 16.5 : 15.0;
    final chevronSize = isTouchLayout ? 14.0 : 13.0;
    final indentWidth = isTouchLayout ? 11.0 : 12.0;

    final indentGuides = <Widget>[];
    if (widget.depth > 0) {
      for (int i = 0; i < widget.depth; i++) {
        final isNodeConnector = i == widget.depth - 1;
        final showLine = isNodeConnector ? true : !widget.ancestorIsLast[i];
        indentGuides.add(
          _GuideSegment(
            width: indentWidth,
            lineColor: Colors.white.withValues(alpha: 0.08),
            showVertical: showLine,
            isNodeConnector: isNodeConnector,
            isLast: widget.isLast,
          ),
        );
      }
    }

    final rowBgColor = isSelected
        ? accentColor.withValues(alpha: 0.2)
        : isActiveFile
            ? accentColor.withValues(alpha: 0.12)
            : _isHovered
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent;

    final nodeContent = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
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
            await ref.read(editorProvider.notifier).openFile(widget.path);
            if (mounted) {
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold != null && (scaffold.isDrawerOpen || scaffold.isEndDrawerOpen)) {
                Navigator.pop(context);
              }
            }
          }
        },
        onLongPress: () => _showBottomSheetMenu(context, ref),
        onSecondaryTapUp: (details) => _showDesktopContextMenu(context, ref, details.globalPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            color: rowBgColor,
            padding: EdgeInsets.only(right: isTouchLayout ? 2.0 : 4.0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isActiveFile)
                    Container(
                      width: 2.0,
                      color: accentColor,
                    )
                  else
                    const SizedBox(width: 2.0),
                  SizedBox(width: isTouchLayout ? 3.0 : 2.0),
                  if (widget.depth > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: indentGuides,
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: verticalPad),
                      child: Row(
                        children: [
                          if (widget.isDirectory)
                            Icon(
                              isExpanded ? LucideIcons.chevron_down : LucideIcons.chevron_right,
                              size: chevronSize,
                              color: isExpanded ? Colors.white70 : Colors.white38,
                            )
                          else
                            SizedBox(width: chevronSize),
                          const SizedBox(width: 4),
                          () {
                            final iconInfo = FileIconHelper.getIconInfo(
                              widget.visualName ?? widget.name,
                              widget.isDirectory,
                              isExpanded,
                            );
                            return Icon(
                              iconInfo.icon,
                              size: iconSize,
                              color: iconInfo.color,
                            );
                          }(),
                          SizedBox(width: isTouchLayout ? 7 : 6),
                          Expanded(
                            child: _isRenaming
                                ? _buildInlineRenameField(
                                    isTouchLayout: isTouchLayout,
                                    accentColor: accentColor,
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: _buildFileNameText(
                                          widget.visualName ?? widget.name,
                                          searchQuery,
                                          gitColor,
                                          isTouchLayout: isTouchLayout,
                                          isActiveFile: isActiveFile,
                                        ),
                                      ),
                                      if (!widget.isDirectory && ref.watch(bookmarksProvider).contains(widget.path)) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          LucideIcons.star,
                                          size: 10.5,
                                          color: Colors.amberAccent,
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                          if (!_isRenaming) ...[
                            if (gitColor != Colors.white70 && gitColor != Colors.white)
                              _buildGitBadge(gitColor, ref),
                            if (!isTouchLayout && (_isHovered || isSelected) && widget.isDirectory) ...[
                              _buildFolderQuickActionButton(
                                icon: LucideIcons.file_plus,
                                tooltip: AppLocalizations.of(context)!.newFile,
                                onTap: () => _startInlineCreation(isDir: false),
                              ),
                              _buildFolderQuickActionButton(
                                icon: LucideIcons.folder_plus,
                                tooltip: AppLocalizations.of(context)!.newFolder,
                                onTap: () => _startInlineCreation(isDir: true),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!_isRenaming && (isTouchLayout || _isHovered || isSelected || isActiveFile))
                    Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => _showBottomSheetMenu(context, ref),
                            child: Center(
                              child: Icon(
                                LucideIcons.ellipsis_vertical,
                                size: isTouchLayout ? 15.5 : 13.5,
                                color: Colors.white.withValues(alpha: isTouchLayout ? 0.45 : 0.55),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
            final isMobilePlatform = Platform.isAndroid || Platform.isIOS;

            final childWidget = Container(
              decoration: BoxDecoration(
                color: isOver ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: nodeContent,
            );

            if (isMobilePlatform) {
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
            _buildInlineCreateField(
              isDir: _isCreatingFolder,
              isTouchLayout: isTouchLayout,
              accentColor: accentColor,
            ),
          if (_children!.isEmpty && !_isCreatingFile && !_isCreatingFolder)
            Padding(
              padding: EdgeInsets.only(
                left: (widget.depth + 1) * indentWidth + 20.0,
                top: 4.0,
                bottom: 4.0,
              ),
              child: Text(
                AppLocalizations.of(context)!.empty,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.2),
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
  final double? height;
  final Color lineColor;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegment({
    required this.width,
    this.height,
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

