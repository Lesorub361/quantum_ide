import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/file_explorer/domain/file_node.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:open_filex/open_filex.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:quantum_ide/features/file_explorer/presentation/pages/file_preview_page.dart';
import 'package:quantum_ide/models/chat_message.dart';

class FileExplorerPage extends ConsumerStatefulWidget {
  const FileExplorerPage({super.key});

  @override
  ConsumerState<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends ConsumerState<FileExplorerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  bool _isSelectMode = false;
  final Set<String> _selectedPaths = {};
  bool _isDraggingOver = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final explorerState = ref.watch(fileExplorerProvider);
    final notifier = ref.read(fileExplorerProvider.notifier);
    final workspaceRoot = ref.watch(workspaceProvider).currentPath;
    final isRoot = explorerState.currentPath == workspaceRoot || explorerState.currentPath.isEmpty;

    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDraggingOver = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDraggingOver = false;
        });
      },
      onDragDone: (details) async {
        final messenger = ScaffoldMessenger.of(context);
        setState(() {
          _isDraggingOver = false;
        });
        final currentPath = ref.read(fileExplorerProvider).currentPath;
        if (currentPath.isEmpty) return;

        for (final file in details.files) {
          try {
            final fileType = FileSystemEntity.typeSync(file.path);
            if (fileType == FileSystemEntityType.directory) {
              final srcDir = Directory(file.path);
              final destDir = Directory(p.join(currentPath, p.basename(file.path)));
              await _copyDirectory(srcDir, destDir);
            } else if (fileType == FileSystemEntityType.file) {
              final srcFile = File(file.path);
              final destFile = File(p.join(currentPath, p.basename(file.path)));
              await destFile.create(recursive: true);
              await srcFile.copy(destFile.path);
            }
            final destPath = p.join(currentPath, p.basename(file.path));
            await ref.read(projectServiceProvider.notifier).mirrorEntity(destPath);
          } catch (e) {
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(content: Text('Ошибка импорта: $e')),
              );
            }
          }
        }
        
        ref.read(fileExplorerProvider.notifier).scanDirectory(currentPath);
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Файлы успешно импортированы')),
          );
        }
      },
      child: Stack(
        children: [
          PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              if (_isSelectMode) {
                setState(() {
                  _isSelectMode = false;
                  _selectedPaths.clear();
                });
              } else if (!isRoot) {
                notifier.goUp();
              } else {
                await ref.read(workspaceProvider.notifier).closeWorkspace();
                if (context.mounted) {
                  context.go('/');
                }
              }
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0D0F14),
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.02, 0.0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: CustomScrollView(
                  key: ValueKey(explorerState.currentPath),
                  slivers: [
                    _isSelectMode
                        ? explorerState.files.when(
                            data: (nodes) => _buildSelectionAppBar(context, ref, nodes),
                            loading: () => _buildSelectionAppBar(context, ref, []),
                            error: (err, stack) => _buildSelectionAppBar(context, ref, []),
                          )
                        : _buildSliverAppBar(context, ref, explorerState, workspaceRoot),
                    if (!_isSelectMode)
                      SliverToBoxAdapter(
                        child: _buildBreadcrumbs(context, explorerState.currentPath, workspaceRoot),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: _buildSearchBar(),
                      ),
                    ),
                    explorerState.files.when(
                      data: (nodes) => SliverToBoxAdapter(child: _buildStatsPanel(nodes)),
                      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                      error: (err, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    ),
                    explorerState.files.when(
                      data: (nodes) {
                        final filteredNodes = nodes.where((n) => 
                          n.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
                        
                        if (filteredNodes.isEmpty) {
                          return SliverFillRemaining(
                            child: Center(child: Text(AppLocalizations.of(context)!.noFilesFound, style: const TextStyle(color: Colors.white24))),
                          );
                        }

                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildFileItem(context, ref, filteredNodes[index]),
                              childCount: filteredNodes.length,
                            ),
                          ),
                        );
                      },
                      loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))),
                      error: (err, stack) => SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(LucideIcons.circle_alert, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 16),
                              Text(AppLocalizations.of(context)!.errorOccurred(err.toString()), style: const TextStyle(color: Colors.white38)),
                              TextButton(
                                onPressed: () => notifier.scanDirectory(explorerState.currentPath),
                                child: Text(AppLocalizations.of(context)!.retry, style: const TextStyle(color: Color(0xFF00D4FF))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
              floatingActionButton: _buildFAB(context, ref),
            ),
          ),
          if (_isDraggingOver)
            Container(
              color: Colors.cyanAccent.withValues(alpha: 0.15),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2230),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.cyanAccent, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.cloud_upload, size: 48, color: Colors.cyanAccent),
                      const SizedBox(height: 16),
                      const Text(
                        'Перетащите файлы сюда для импорта',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  Widget _buildSliverAppBar(BuildContext context, WidgetRef ref, FileExplorerState state, String? root) {
    final pathSegments = state.currentPath.replaceFirst(root ?? '', '').split('/').where((s) => s.isNotEmpty).toList();
    final isRoot = state.currentPath == root || state.currentPath.isEmpty;

    return SliverAppBar(
      expandedHeight: 80,
      pinned: true,
      backgroundColor: const Color(0xFF0D0F14),
      elevation: 0,
      leading: IconButton(
        icon: Icon(isRoot ? LucideIcons.arrow_left : LucideIcons.chevron_left, color: Colors.white),
        onPressed: () async {
          if (isRoot) {
            await ref.read(workspaceProvider.notifier).closeWorkspace();
            if (context.mounted) {
              context.go('/');
            }
          } else {
            ref.read(fileExplorerProvider.notifier).goUp();
          }
        },
      ),
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 52, bottom: 12),
        title: Text(
          isRoot ? 'Project Explorer' : (pathSegments.isEmpty ? 'Root' : pathSegments.last),
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF6C63FF).withValues(alpha: 0.1),
                const Color(0xFF0D0F14),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.refresh_cw, size: 18, color: Colors.white70),
          onPressed: () => ref.read(fileExplorerProvider.notifier).scanDirectory(state.currentPath),
        ),
        PopupMenuButton<FileSortMode>(
          icon: const Icon(LucideIcons.arrow_up_down, size: 18, color: Colors.white70),
          tooltip: 'Sort Files',
          onSelected: (mode) {
            ref.read(fileSortModeProvider.notifier).state = mode;
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: FileSortMode.name,
              child: Row(
                children: [
                  const Icon(LucideIcons.file_text, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.sortByName),
                ],
              ),
            ),
            PopupMenuItem(
              value: FileSortMode.size,
              child: Row(
                children: [
                  const Icon(LucideIcons.database, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.sortBySize),
                ],
              ),
            ),
            PopupMenuItem(
              value: FileSortMode.date,
              child: Row(
                children: [
                  const Icon(LucideIcons.calendar, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.sortByDate),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(LucideIcons.log_out, size: 18, color: Colors.redAccent),
          tooltip: AppLocalizations.of(context)!.closeProject,
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF151922),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(
                  AppLocalizations.of(context)!.closeProject,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                content: Text(
                  AppLocalizations.of(context)!.closeProjectConfirm,
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      AppLocalizations.of(context)!.cancel,
                      style: const TextStyle(color: Colors.white38),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'OK',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(workspaceProvider.notifier).closeWorkspace();
              if (context.mounted) {
                context.go('/');
              }
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSelectionAppBar(BuildContext context, WidgetRef ref, List<FileNode> allNodes) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: const Color(0xFF1E2130),
      elevation: 4,
      leading: IconButton(
        icon: const Icon(LucideIcons.x, color: Colors.white),
        onPressed: () {
          setState(() {
            _isSelectMode = false;
            _selectedPaths.clear();
          });
        },
      ),
      title: Text(
        'Выбрано: ${_selectedPaths.length}',
        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
      ),
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.check, size: 18, color: Colors.cyanAccent),
          tooltip: 'Выбрать все',
          onPressed: () {
            setState(() {
              if (_selectedPaths.length == allNodes.length) {
                _selectedPaths.clear();
                _isSelectMode = false;
              } else {
                _selectedPaths.addAll(allNodes.map((n) => n.path));
              }
            });
          },
        ),
        IconButton(
          icon: const Icon(LucideIcons.copy, size: 18, color: Colors.white70),
          tooltip: 'Копировать',
          onPressed: () {
            ref.read(fileClipboardProvider.notifier).state = ClipboardData(
              paths: _selectedPaths.toList(),
              isCut: false,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Скопировано объектов: ${_selectedPaths.length}')),
            );
            setState(() {
              _isSelectMode = false;
              _selectedPaths.clear();
            });
          },
        ),
        IconButton(
          icon: const Icon(LucideIcons.scissors, size: 18, color: Colors.white70),
          tooltip: 'Вырезать',
          onPressed: () {
            ref.read(fileClipboardProvider.notifier).state = ClipboardData(
              paths: _selectedPaths.toList(),
              isCut: true,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Вырезано объектов: ${_selectedPaths.length}')),
            );
            setState(() {
              _isSelectMode = false;
              _selectedPaths.clear();
            });
          },
        ),
        IconButton(
          icon: const Icon(LucideIcons.file_archive, size: 18, color: Colors.amberAccent),
          tooltip: 'Сжать в ZIP',
          onPressed: () => _showCompressDialog(context, ref, _selectedPaths.toList()),
        ),
        IconButton(
          icon: const Icon(LucideIcons.trash_2, size: 18, color: Colors.redAccent),
          tooltip: 'Удалить',
          onPressed: () => _showBatchDeleteConfirm(context, ref, _selectedPaths.toList()),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildStatsPanel(List<FileNode> nodes) {
    final folderCount = nodes.where((n) => n.isDirectory).length;
    final fileCount = nodes.where((n) => !n.isDirectory).length;
    final totalSizeBytes = nodes.where((n) => !n.isDirectory).fold<int>(0, (sum, n) => sum + n.size);
    
    String sizeStr = '';
    if (totalSizeBytes < 1024) {
      sizeStr = '$totalSizeBytes B';
    } else if (totalSizeBytes < 1024 * 1024) {
      sizeStr = '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      sizeStr = '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    final stats = ref.watch(systemStatsProvider);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: GlassContainer(
        blur: 10,
        opacity: 0.03,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.folder, size: 12, color: Colors.blueAccent),
                    const SizedBox(width: 4),
                    Text(
                      '$folderCount папок',
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(LucideIcons.file, size: 12, color: Colors.tealAccent),
                    const SizedBox(width: 4),
                    Text(
                      '$fileCount файлов',
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(LucideIcons.hard_drive, size: 12, color: Colors.purpleAccent),
                    const SizedBox(width: 4),
                    Text(
                      sizeStr,
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6.0),
              child: Divider(height: 1, color: Colors.white10),
            ),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(LucideIcons.cpu, size: 12, color: Colors.cyanAccent),
                      const SizedBox(width: 4),
                      Text(
                        'CPU: ${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: stats.cpuUsage,
                            minHeight: 2,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(_getLoadColor(stats.cpuUsage)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(LucideIcons.memory_stick, size: 12, color: Colors.amberAccent),
                      const SizedBox(width: 4),
                      Text(
                        'RAM: ${stats.ramUsedGB.toStringAsFixed(1)} GB',
                        style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: stats.ramUsage,
                            minHeight: 2,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(_getLoadColor(stats.ramUsage)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getLoadColor(double value) {
    if (value < 0.6) return Colors.greenAccent;
    if (value < 0.85) return Colors.amberAccent;
    return Colors.redAccent;
  }

  Widget _buildSearchBar() {
    return GlassContainer(
      blur: 10,
      opacity: 0.05,
      borderRadius: BorderRadius.circular(8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: Colors.white, fontSize: 12.5),
        decoration: InputDecoration(
          hintText: 'Search in folder...',
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: const Icon(LucideIcons.search, size: 14, color: Colors.white38),
          suffixIcon: _searchQuery.isNotEmpty ? IconButton(
            icon: const Icon(LucideIcons.x, size: 12, color: Colors.white38),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Color _getGitStatusColor(WidgetRef ref, String nodePath, bool isDirectory) {
    final gitState = ref.watch(gitProvider);
    final status = gitState.status;
    if (status == null) return Colors.white70;

    final currentWorkspace = ref.read(workspaceProvider).currentPath;
    if (currentWorkspace == null) return Colors.white70;
    final relativePath = p.relative(nodePath, from: currentWorkspace);
    
    if (isDirectory) {
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

  Widget _buildGitBadge(Color color, WidgetRef ref, String nodePath, bool isDirectory) {
    final gitState = ref.read(gitProvider);
    final status = gitState.status;
    if (status == null) return const SizedBox.shrink();

    final currentWorkspace = ref.read(workspaceProvider).currentPath;
    if (currentWorkspace == null) return const SizedBox.shrink();
    final relativePath = p.relative(nodePath, from: currentWorkspace);
    String letter = '';
    
    if (isDirectory) {
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
      padding: const EdgeInsets.only(right: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
        ),
        child: Text(
          letter,
          style: TextStyle(
            color: color,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildAIBadge(WidgetRef ref, String nodePath, bool isDirectory) {
    final aiState = ref.watch(aiProvider);

    if (isDirectory) {
      final actions = aiState.proposedActions.where((a) => a.path.startsWith('$nodePath/')).toList();
      final hasReadFiles = aiState.agentReadFiles.any((f) => f.startsWith('$nodePath/'));
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

    final wasReadByAgent = aiState.agentReadFiles.contains(nodePath);

    final action = aiState.proposedActions.firstWhere(
      (a) => a.path == nodePath,
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
          if (wasReadByAgent && !hasPendingAction) ...[
            const Icon(LucideIcons.eye, size: 10, color: Colors.cyanAccent),
            const SizedBox(width: 3),
          ],
          if (hasPendingAction) ...[
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

  Widget _buildFileItem(BuildContext context, WidgetRef ref, FileNode node) {
    final iconInfo = FileIconHelper.getIconInfo(node.name, node.isDirectory);
    final isSelected = _selectedPaths.contains(node.path);
    final gitColor = _getGitStatusColor(ref, node.path, node.isDirectory);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected 
            ? Colors.cyanAccent.withValues(alpha: 0.08) 
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected 
              ? Colors.cyanAccent.withValues(alpha: 0.3) 
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: iconInfo.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            iconInfo.icon,
            size: 16,
            color: iconInfo.color,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                node.name,
                style: GoogleFonts.inter(
                  color: gitColor == Colors.white70 ? Colors.white : gitColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildAIBadge(ref, node.path, node.isDirectory),
            if (gitColor != Colors.white70 && gitColor != Colors.white)
              _buildGitBadge(gitColor, ref, node.path, node.isDirectory),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: Row(
            children: [
              Text(
                node.isDirectory ? 'Folder' : _getFileTypeLabel(node.name),
                style: const TextStyle(color: Colors.white38, fontSize: 9.5),
              ),
              if (!node.isDirectory) ...[
                const SizedBox(width: 4),
                const Text('•', style: TextStyle(color: Colors.white24, fontSize: 9.5)),
                const SizedBox(width: 4),
                Text(
                  _formatSize(node.size),
                  style: const TextStyle(color: Colors.white38, fontSize: 9.5),
                ),
              ],
              const SizedBox(width: 4),
              const Text('•', style: TextStyle(color: Colors.white24, fontSize: 9.5)),
              const SizedBox(width: 4),
              Text(
                _formatDateTime(node.modified),
                style: const TextStyle(color: Colors.white38, fontSize: 9.5),
              ),
            ],
          ),
        ),
        trailing: _isSelectMode
            ? Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.cyanAccent : Colors.white30,
                    width: 1.5,
                  ),
                  color: isSelected ? Colors.cyanAccent : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(LucideIcons.check, size: 12, color: Colors.black)
                    : null,
              )
            : _buildItemActions(context, ref, node),
        onTap: () async {
          if (_isSelectMode) {
            setState(() {
              if (isSelected) {
                _selectedPaths.remove(node.path);
                if (_selectedPaths.isEmpty) {
                  _isSelectMode = false;
                }
              } else {
                _selectedPaths.add(node.path);
              }
            });
          } else {
            if (node.isDirectory) {
              ref.read(fileExplorerProvider.notifier).navigateTo(node.path);
            } else if (node.name.toLowerCase().endsWith('.apk')) {
               try {
                await OpenFilex.open(node.path);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error opening APK: $e')),
                  );
                }
              }
            } else {
              final ext = p.extension(node.path).toLowerCase();
              final isPreviewable = ext == '.md' || 
                  ext == '.png' || 
                  ext == '.jpg' || 
                  ext == '.jpeg' || 
                  ext == '.gif' || 
                  ext == '.webp';
              if (isPreviewable) {
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FilePreviewPage(filePath: node.path),
                    ),
                  );
                }
              } else {
                await ref.read(editorProvider.notifier).openFile(node.path);
                if (context.mounted) context.push('/editor');
              }
            }
          }
        },
        onLongPress: () {
          if (!_isSelectMode) {
            setState(() {
              _isSelectMode = true;
              _selectedPaths.add(node.path);
            });
          }
        },
      ),
    );
  }

  Widget _buildItemActions(BuildContext context, WidgetRef ref, FileNode node) {
    final isZip = node.name.toLowerCase().endsWith('.zip');
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.ellipsis_vertical, size: 18, color: Colors.white24),
      color: const Color(0xFF1A1D27),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) async {
        if (value == 'rename') {
          _showRenameDialog(context, ref, node);
        } else if (value == 'delete') {
          _showDeleteConfirm(context, ref, node);
        } else if (value == 'extract') {
          _extractZip(context, ref, node.path);
        } else if (value == 'compress') {
          _showCompressDialog(context, ref, [node.path]);
        } else if (value == 'ai_ask') {
          _handleAiAsk(node);
        } else if (value == 'ai_explain') {
          _handleAiAsk(node, presetQuery: node.isDirectory
              ? 'Объясни назначение и структуру этой папки.'
              : 'Подробно объясни назначение и логику работы этого файла.');
        } else if (value == 'ai_docs') {
          _handleAiAsk(node, presetQuery: node.isDirectory
              ? 'Добавь документацию, docstrings и подробные комментарии к коду во всех файлах этой папки.'
              : 'Добавь понятную документацию, docstrings и подробные комментарии к коду в этом файле.');
        } else if (value == 'ai_tests') {
          _handleAiAsk(node, presetQuery: node.isDirectory
              ? 'Напиши unit-тесты для файлов в этой папке.'
              : 'Напиши комплексные unit-тесты для кода в этом файле.');
        } else if (value == 'ai_optimize') {
          _handleAiAsk(node, presetQuery: node.isDirectory
              ? 'Проанализируй код в этой папке и предложи оптимизацию производительности и читаемости.'
              : 'Проанализируй код в этом файле и предложи варианты оптимизации производительности, читаемости и архитектуры.');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'ai_ask',
          child: Row(children: [const Icon(LucideIcons.sparkles, size: 14, color: Colors.cyanAccent), const SizedBox(width: 12), Text(isRu ? 'Спросить ИИ' : 'Ask AI', style: const TextStyle(color: Colors.cyanAccent))]),
        ),
        PopupMenuItem(
          value: 'ai_explain',
          child: Row(children: [const Icon(LucideIcons.book_open, size: 14, color: Colors.cyanAccent), const SizedBox(width: 12), Text(isRu ? 'ИИ: Объяснить' : 'AI: Explain', style: const TextStyle(color: Colors.cyanAccent))]),
        ),
        PopupMenuItem(
          value: 'ai_docs',
          child: Row(children: [const Icon(LucideIcons.file_text, size: 14, color: Colors.cyanAccent), const SizedBox(width: 12), Text(isRu ? 'ИИ: Документация' : 'AI: Document', style: const TextStyle(color: Colors.cyanAccent))]),
        ),
        PopupMenuItem(
          value: 'ai_tests',
          child: Row(children: [const Icon(LucideIcons.shield_check, size: 14, color: Colors.cyanAccent), const SizedBox(width: 12), Text(isRu ? 'ИИ: Создать тесты' : 'AI: Generate Tests', style: const TextStyle(color: Colors.cyanAccent))]),
        ),
        PopupMenuItem(
          value: 'ai_optimize',
          child: Row(children: [const Icon(LucideIcons.zap, size: 14, color: Colors.cyanAccent), const SizedBox(width: 12), Text(isRu ? 'ИИ: Оптимизировать' : 'AI: Optimize', style: const TextStyle(color: Colors.cyanAccent))]),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'rename',
          child: Row(children: const [Icon(LucideIcons.pencil, size: 14, color: Colors.white70), SizedBox(width: 12), Text('Rename', style: TextStyle(color: Colors.white70))]),
        ),
        if (isZip)
          PopupMenuItem(
            value: 'extract',
            child: Row(children: const [Icon(LucideIcons.file_archive, size: 14, color: Colors.greenAccent), SizedBox(width: 12), Text('Extract ZIP', style: TextStyle(color: Colors.greenAccent))]),
          ),
        if (!isZip)
          PopupMenuItem(
            value: 'compress',
            child: Row(children: const [Icon(LucideIcons.file_archive, size: 14, color: Colors.amberAccent), SizedBox(width: 12), Text('Compress to ZIP', style: TextStyle(color: Colors.amberAccent))]),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: const [Icon(LucideIcons.trash_2, size: 14, color: Colors.redAccent), SizedBox(width: 12), Text('Delete', style: TextStyle(color: Colors.redAccent))]),
        ),
      ],
    );
  }

  Widget _buildFAB(BuildContext context, WidgetRef ref) {
    final clipboard = ref.watch(fileClipboardProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (clipboard != null) ...[
          FloatingActionButton.extended(
            heroTag: 'paste_files',
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            onPressed: () => _handlePaste(context, ref, clipboard),
            icon: const Icon(LucideIcons.clipboard_paste),
            label: Text('Вставить (${clipboard.paths.length})'),
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton.small(
          heroTag: 'new_folder',
          backgroundColor: const Color(0xFF1A1D27),
          foregroundColor: Colors.amberAccent,
          onPressed: () => _showCreateDialog(context, ref, true),
          child: const Icon(LucideIcons.folder_plus, size: 18),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'new_file',
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          onPressed: () => _showCreateDialog(context, ref, false),
          child: const Icon(LucideIcons.file_plus),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref, bool isDirectory) async {
    final notifier = ref.read(fileExplorerProvider.notifier);
    final currentPath = ref.read(fileExplorerProvider).currentPath;
    final controller = TextEditingController();
    
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        title: Text(isDirectory ? 'New Folder' : 'New File', style: const TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: isDirectory ? 'folder_name' : 'file.dart',
                    hintStyle: const TextStyle(color: Colors.white24),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6C63FF))),
                  ),
                ),
                if (!isDirectory) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: ['.dart', '.yaml', '.json', '.md', '.html', '.css', '.js', '.txt'].map((ext) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ActionChip(
                            label: Text(ext, style: const TextStyle(fontSize: 12, color: Colors.white)),
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              final text = controller.text;
                              if (text.contains('.')) {
                                final lastDot = text.lastIndexOf('.');
                                controller.text = text.substring(0, lastDot) + ext;
                              } else {
                                controller.text = text + ext;
                              }
                              controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: controller.text.length),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            );
          }
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final path = '$currentPath/$name';
      try {
        if (isDirectory) {
          await Directory(path).create();
        } else {
          await File(path).create();
        }
        await ref.read(projectServiceProvider.notifier).mirrorEntity(path);
        notifier.scanDirectory(currentPath);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, FileNode node) async {
    final controller = TextEditingController(text: node.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        title: const Text('Rename', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6C63FF))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != node.name) {
      try {
        await ref.read(fileExplorerProvider.notifier).renameEntity(node.path, newName);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref, FileNode node) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete ${node.name}?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(fileExplorerProvider.notifier).deleteEntity(node.path);
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showCompressDialog(BuildContext context, WidgetRef ref, List<String> paths) async {
    final controller = TextEditingController(text: 'archive');
    final zipName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Сжать в ZIP', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Имя архива',
            hintStyle: TextStyle(color: Colors.white24),
            suffixText: '.zip',
            suffixStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF6C63FF))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сжать', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
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
            const SnackBar(content: Text('Архив успешно создан!')),
          );
          setState(() {
            _isSelectMode = false;
            _selectedPaths.clear();
          });
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context); // close progress
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка сжатия: $e')),
          );
        }
      }
    }
  }

  void _extractZip(BuildContext context, WidgetRef ref, String path) async {
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
          const SnackBar(content: Text('Архив успешно распакован!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка распаковки: $e')),
        );
      }
    }
  }

  void _showBatchDeleteConfirm(BuildContext context, WidgetRef ref, List<String> paths) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(LucideIcons.trash_2, color: Colors.redAccent),
            SizedBox(width: 10),
            Text('Удалить выбранное?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Вы уверены, что хотите удалить ${paths.length} элементов?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(fileExplorerProvider.notifier).deleteMultipleEntities(paths);
        setState(() {
          _isSelectMode = false;
          _selectedPaths.clear();
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Выбранные элементы удалены!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка удаления: $e')),
          );
        }
      }
    }
  }

  void _handlePaste(BuildContext context, WidgetRef ref, ClipboardData clipboard) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );

      final currentPath = ref.read(fileExplorerProvider).currentPath;
      final projectNotifier = ref.read(projectServiceProvider.notifier);

      for (final sourcePath in clipboard.paths) {
        final name = sourcePath.split(Platform.pathSeparator).last;
        final destPath = '$currentPath/$name';

        if (clipboard.isCut) {
          final type = FileSystemEntity.typeSync(sourcePath);
          if (type == FileSystemEntityType.directory) {
            await Directory(sourcePath).rename(destPath);
          } else if (type == FileSystemEntityType.file) {
            await File(sourcePath).rename(destPath);
          }
          await projectNotifier.mirrorDelete(sourcePath);
        } else {
          final type = FileSystemEntity.typeSync(sourcePath);
          if (type == FileSystemEntityType.directory) {
            await _copyDirectory(Directory(sourcePath), Directory(destPath));
          } else if (type == FileSystemEntityType.file) {
            await File(sourcePath).copy(destPath);
          }
        }
        await projectNotifier.mirrorEntity(destPath);
      }

      if (clipboard.isCut) {
        ref.read(fileClipboardProvider.notifier).state = null;
      }
      
      if (context.mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файлы успешно вставлены!')),
        );
      }
      
      await ref.read(fileExplorerProvider.notifier).scanDirectory(currentPath);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка вставки: $e')),
        );
      }
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final newPath = '${destination.path}/$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  void _handleAiAsk(FileNode node, {String? presetQuery}) async {
    final controller = TextEditingController();
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
                AppLocalizations.of(context)!.aiAskDialogTitle,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.isDirectory
                    ? AppLocalizations.of(context)!.aiAskFolder(p.basename(node.path))
                    : AppLocalizations.of(context)!.aiAskFile(p.basename(node.path)),
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
                  hintText: node.isDirectory
                      ? AppLocalizations.of(context)!.aiAskFolderHint
                      : AppLocalizations.of(context)!.aiAskFileHint,
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
                AppLocalizations.of(context)!.cancel,
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
                AppLocalizations.of(context)!.send,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

    if (instruction == null || instruction.trim().isEmpty) return;

    String content = '';
    if (!node.isDirectory) {
      try {
        content = await File(node.path).readAsString();
      } catch (e) {
        content = '[Could not read file]';
      }
    }

    final prompt = node.isDirectory
        ? """
Я работаю в папке: `${node.path}`.
Список файлов и подпапок в ней:
${node.children.map((c) => (c.isDirectory ? '[Папка] ' : '[Файл] ') + c.name).join('\n')}

Запрос пользователя:
$instruction

Пожалуйста, выполни этот запрос. Если требуется изменить или создать файлы/папки, или запустить команду в терминале, используй формат действий <actions>.
"""
        : """
Я работаю над файлом: `${node.path}`.
Его текущее содержимое:
```
$content
```

Запрос пользователя:
$instruction

Пожалуйста, выполни этот запрос. Если требуется изменить файл, создать новый, удалить или запустить команду в терминале, используй формат действий <actions>.
""";

    ref.read(aiProvider.notifier).askAI(prompt);
    ref.read(rightChatPanelOpenProvider.notifier).state = true;

    if (mounted) context.push('/editor');
  }

  String _getFileTypeLabel(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart': return 'Dart Source';
      case 'yaml': return 'Config';
      case 'md': return 'Markdown';
      case 'xml': return 'Android Manifest';
      case 'gradle': return 'Gradle Config';
      case 'html': return 'Web Page';
      case 'js': return 'JavaScript';
      default: return '${ext.toUpperCase()} File';
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  List<({String name, String path})> _getBreadcrumbs(String currentPath, String? rootPath) {
    if (rootPath == null || rootPath.isEmpty) {
      return [
        (name: 'Root', path: currentPath),
      ];
    }
    
    final List<({String name, String path})> crumbs = [];
    final rootDirName = p.basename(rootPath);
    crumbs.add((name: rootDirName.isEmpty ? 'Project' : rootDirName, path: rootPath));
    
    if (currentPath == rootPath || !currentPath.startsWith(rootPath)) {
      return crumbs;
    }
    
    final relativePath = p.relative(currentPath, from: rootPath);
    if (relativePath == '.') {
      return crumbs;
    }
    
    final parts = relativePath.split(Platform.pathSeparator);
    String currentBuildPath = rootPath;
    for (final part in parts) {
      if (part.isEmpty) continue;
      currentBuildPath = p.join(currentBuildPath, part);
      crumbs.add((name: part, path: currentBuildPath));
    }
    return crumbs;
  }

  Widget _buildBreadcrumbs(BuildContext context, String currentPath, String? rootPath) {
    final crumbs = _getBreadcrumbs(currentPath, rootPath);
    final scrollController = ScrollController();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: ListView.builder(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: crumbs.length,
        itemBuilder: (context, index) {
          final crumb = crumbs[index];
          final isLast = index == crumbs.length - 1;
          
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: isLast
                    ? null
                    : () => ref.read(fileExplorerProvider.notifier).navigateTo(crumb.path),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    crumb.name,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                      color: isLast ? const Color(0xFF00D4FF) : Colors.white70,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    LucideIcons.chevron_right,
                    size: 11,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
