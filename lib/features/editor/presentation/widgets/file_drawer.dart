import 'package:flutter/material.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/stable_editor_widget.dart';
import 'package:quantum_ide/features/editor/presentation/pages/editor_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/providers/drawer_provider.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/problems_panel.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/features/file_explorer/presentation/widgets/global_search_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/code_outline_widget.dart';
import 'package:quantum_ide/features/file_explorer/presentation/widgets/disk_analyzer_widget.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/bookmarks_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/pages/file_preview_page.dart';
import 'package:quantum_ide/features/git/presentation/widgets/git_panel.dart';
import 'package:quantum_ide/features/preview/presentation/widgets/web_preview_panel.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/packages_panel.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/run_build_panels.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/live_share_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/extensions_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/models_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/app_logs_panel.dart';


class FileDrawer extends ConsumerStatefulWidget {
  final bool isInline;
  const FileDrawer({super.key, this.isInline = false});

  @override
  ConsumerState<FileDrawer> createState() => FileDrawerState();
}



class FileDrawerState extends ConsumerState<FileDrawer> {

  Widget _buildFilterChip(WidgetRef ref, String label, String query, bool isSelected) {
    return InkWell(
      onTap: () => ref.read(fileSearchQueryProvider.notifier).state = query,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4CD7F6).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF4CD7F6).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06),
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFF4CD7F6) : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildActivityIcon(WidgetRef ref, int index, IconData icon, String tooltip, bool isActive, {int badgeCount = 0}) {
    const activeColor = Color(0xFF4CD7F6);
    final iconWidget = Icon(
      icon,
      size: 16,
      color: isActive ? activeColor : Colors.white38,
    );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => ref.read(drawerTabProvider.notifier).state = index,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? activeColor.withValues(alpha: 0.1) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? activeColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: badgeCount > 0
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    iconWidget,
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3C3C), // Mandy Red
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : iconWidget,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fileSearchWatcher);
    final workspacePath = ref.watch(workspaceProvider.select((s) => s.currentPath ?? ''));
    final selectedTab = ref.watch(drawerTabProvider);
    final panelState = ref.watch(panelProvider);

    // Оптимизировано: считываем только количество проблем через select() — не ребилдимся при каждом нажатии клавиши!
    final totalProblems = ref.watch(editorProvider.select((s) {
      if (workspacePath.isEmpty) return 0;
      int count = 0;
      s.allDiagnostics.forEach((filePath, list) {
        if (filePath.startsWith(workspacePath)) count += list.length;
      });
      return count;
    }));

    final gitChangesCount = ref.watch(gitProvider.select((s) =>
      (s.status?.stagedFiles.length ?? 0) +
      (s.status?.modifiedFiles.length ?? 0) +
      (s.status?.untrackedFiles.length ?? 0) +
      (s.status?.conflictedFiles.length ?? 0)
    ));

    // Activity bar on the left
    final activityBar = Container(
      width: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF090B0F),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildActivityIcon(ref, 0, LucideIcons.files, AppLocalizations.of(context)!.explorer, selectedTab == 0),
                  _buildActivityIcon(ref, 1, LucideIcons.search, AppLocalizations.of(context)!.search, selectedTab == 1),
                  _buildActivityIcon(ref, 2, LucideIcons.list, AppLocalizations.of(context)!.structure, selectedTab == 2),
                  _buildActivityIcon(ref, 3, LucideIcons.chart_pie, AppLocalizations.of(context)!.disk, selectedTab == 3),
                  _buildActivityIcon(ref, 4, LucideIcons.circle_alert, AppLocalizations.of(context)!.problems, selectedTab == 4, badgeCount: totalProblems),
                  _buildActivityIcon(ref, 5, LucideIcons.git_branch, 'Git', selectedTab == 5, badgeCount: gitChangesCount),
                  _buildActivityIcon(ref, 6, LucideIcons.server, AppLocalizations.of(context)!.preview, selectedTab == 6),
                  _buildActivityIcon(ref, 7, LucideIcons.toy_brick, AppLocalizations.of(context)!.packages, selectedTab == 7),
                  _buildActivityIcon(ref, 8, LucideIcons.play, AppLocalizations.of(context)!.run, selectedTab == 8),
                  _buildActivityIcon(ref, 9, LucideIcons.hammer, AppLocalizations.of(context)!.build, selectedTab == 9),
                  _buildActivityIcon(ref, 10, LucideIcons.users, AppLocalizations.of(context)!.liveShare, selectedTab == 10),
                  _buildActivityIcon(ref, 11, LucideIcons.puzzle, AppLocalizations.of(context)!.plugins, selectedTab == 11),
                  _buildActivityIcon(ref, 12, LucideIcons.cpu, 'AI Models', selectedTab == 12),
                  _buildActivityIcon(ref, 13, LucideIcons.terminal, 'App Logs', selectedTab == 13),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 4),
          Tooltip(
            message: AppLocalizations.of(context)!.settings,
            child: InkWell(
              onTap: () {
                context.push('/settings');
              },
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child: const Icon(LucideIcons.settings, size: 16, color: Colors.white38),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );


    Widget activePanel;
    switch (selectedTab) {
      case 1:
        activePanel = const GlobalSearchPanel();
        break;
      case 2:
        activePanel = const CodeOutlineWidget();
        break;
      case 3:
        activePanel = const DiskAnalyzerWidget();
        break;
      case 4:
        activePanel = const ProblemsPanel();
        break;
      case 5:
        activePanel = const SidebarGitPanel();
        break;
      case 6:
        activePanel = const SidebarWebPreviewPanel();
        break;
      case 7:
        activePanel = const SidebarPackagesPanel();
        break;
      case 8:
        activePanel = const SidebarRunPanel();
        break;
      case 9:
        activePanel = const SidebarBuildPanel();
        break;
      case 10:
        activePanel = const LiveSharePanel();
        break;
      case 11:
        activePanel = const ExtensionsPanel();
        break;
      case 12:
        activePanel = const ModelsPanel();
        break;
      case 13:
        activePanel = const AppLogsPanel();
        break;
      case 0:
      default:
        activePanel = Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.blue, Colors.cyan],
                            ).createShader(bounds),
                            child: const Icon(LucideIcons.folder, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(AppLocalizations.of(context)!.explorer, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                          ),
                        ],
                      ),
                      if (workspacePath.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              DrawerActionIcon(
                                icon: LucideIcons.wrench,
                                tooltip: AppLocalizations.of(context)!.environment,
                                onPressed: () => showEnvironmentBottomSheet(context, ref),
                              ),
                              DrawerActionIcon(
                                icon: LucideIcons.folder_closed,
                                tooltip: AppLocalizations.of(context)!.collapseAll,
                                onPressed: () {
                                  ref.read(expandedFoldersProvider.notifier).setExpanded({});
                                },
                              ),
                              DrawerActionIcon(
                                icon: LucideIcons.arrow_up_down,
                                tooltip: AppLocalizations.of(context)!.sortByDate.split(' ').first,
                                onPressed: () => showSortMenu(context, ref),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (workspacePath.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Consumer(
                          builder: (context, ref, _) {
                            final currentQuery = ref.watch(fileSearchQueryProvider);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  onChanged: (value) => ref.read(fileSearchQueryProvider.notifier).state = value,
                                  controller: TextEditingController(text: currentQuery)..selection = TextSelection.fromPosition(TextPosition(offset: currentQuery.length)),
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(context)!.searchFiles,
                                    hintStyle: const TextStyle(fontSize: 12.5, color: Colors.white30),
                                    prefixIcon: const Icon(LucideIcons.search, size: 14, color: Colors.white38),
                                    suffixIcon: currentQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(LucideIcons.x, size: 14, color: Colors.white54),
                                            onPressed: () => ref.read(fileSearchQueryProvider.notifier).state = '',
                                          )
                                        : null,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    fillColor: Colors.white.withValues(alpha: 0.05),
                                    filled: true,
                                  ),
                                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    children: [
                                      _buildFilterChip(ref, AppLocalizations.of(context)!.all, '', currentQuery == ''),
                                      const SizedBox(width: 4),
                                      _buildFilterChip(ref, 'Dart', '.dart', currentQuery == '.dart'),
                                      const SizedBox(width: 4),
                                      _buildFilterChip(ref, 'YAML', '.yaml', currentQuery == '.yaml'),
                                      const SizedBox(width: 4),
                                      _buildFilterChip(ref, 'JSON', '.json', currentQuery == '.json'),
                                      const SizedBox(width: 4),
                                      _buildFilterChip(ref, 'Web', '.html', currentQuery == '.html'),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10, indent: 14, endIndent: 14),
                const SizedBox(height: 6),
                if (workspacePath.isNotEmpty)
                  Expanded(
                    child: DragTarget<String>(
                      onWillAcceptWithDetails: (details) {
                        final draggedPath = details.data;
                        final parentDir = p.dirname(draggedPath);
                        if (parentDir == workspacePath) return false;
                        return true;
                      },
                      onAcceptWithDetails: (details) async {
                        final draggedPath = details.data;
                        try {
                          await ref.read(fileExplorerProvider.notifier).moveEntity(draggedPath, workspacePath);
                          if (context.mounted) {
                            final l10n = AppLocalizations.of(context)!;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.elementMovedToRoot)),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            final l10n = AppLocalizations.of(context)!;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.moveError(e.toString()))),
                            );
                          }
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isOver = candidateData.isNotEmpty;
                        return Container(
                          color: isOver ? Colors.blue.withValues(alpha: 0.05) : Colors.transparent,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildBookmarksSection(context, ref, workspacePath),
                                if (ref.watch(bookmarksProvider).isNotEmpty)
                                  const Divider(height: 1, color: Colors.white10, indent: 14, endIndent: 14),
                                FileDrawerTree(workspacePath: workspacePath),
                                const SizedBox(height: 80),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  Expanded(child: Center(child: Text(AppLocalizations.of(context)!.projectNotOpened, style: const TextStyle(color: Colors.grey)))),
                const DrawerStatsPanel(),
                const SizedBox(height: 80),
              ],
            ),
            if (workspacePath.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: GlassContainer(
                  blur: 20,
                  opacity: 0.9,
                  color: const Color(0xFF1E2230),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FloatingCapsuleButton(
                            icon: LucideIcons.file_plus,
                            label: AppLocalizations.of(context)!.newFile.toUpperCase(),
                            onPressed: () => showCreateDialog(context, ref, workspacePath, false),
                          ),
                          const SizedBox(width: 16),
                              FloatingCapsuleButton(
                                icon: LucideIcons.folder_plus,
                                label: AppLocalizations.of(context)!.newFolder.toUpperCase(),
                                onPressed: () => showCreateDialog(context, ref, workspacePath, true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 24,
                        width: 1,
                        color: Colors.white10,
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.terminal, size: 18),
                        color: const Color(0xFF4CD7F6),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF03B5D3).withValues(alpha: 0.2),
                          padding: const EdgeInsets.all(8),
                        ),
                        onPressed: () {
                          final panelNotifier = ref.read(panelProvider.notifier);
                          if (panelState.isOpened && panelState.selectedTab == PanelTab.terminal) {
                            panelNotifier.closePanel();
                          } else {
                            panelNotifier.selectTab(PanelTab.terminal);
                            panelNotifier.openPanel();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
    }

    final content = SafeArea(
      child: Row(
        children: [
          activityBar,
          Expanded(
            child: activePanel,
          ),
        ],
      ),
    );

    if (widget.isInline) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0F14).withValues(alpha: 0.5),
          border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
        ),
        child: content,
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    
    return GlassContainer(
      blur: 30,
      opacity: 0.85,
      color: const Color(0xFF0F1117),
      borderRadius: BorderRadius.zero,
      border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
      child: Drawer(
        width: screenWidth,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: content,
      ),
    );
  }

  Widget _buildBookmarksSection(BuildContext context, WidgetRef ref, String workspacePath) {
    final bookmarks = ref.watch(bookmarksProvider);
    if (bookmarks.isEmpty) {
      return const SizedBox.shrink();
    }
    final title = AppLocalizations.of(context)!.bookmarks;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const PageStorageKey<String>('bookmarks_expansion_tile'),
        leading: const Icon(LucideIcons.star, size: 16, color: Colors.amberAccent),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        dense: true,
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white30,
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 4),
        initiallyExpanded: true,
        children: bookmarks.map((filePath) {
          final fileName = p.basename(filePath);
          final relativePath = p.relative(filePath, from: workspacePath);
          final iconInfo = FileIconHelper.getIconInfo(fileName, false, false);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minLeadingWidth: 20,
              leading: Icon(
                iconInfo.icon,
                size: 15,
                color: iconInfo.color,
              ),
              title: Text(
                fileName,
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                relativePath,
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.35)),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(LucideIcons.star_off, size: 12, color: Colors.redAccent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ref.read(bookmarksProvider.notifier).toggleBookmark(filePath);
                },
              ),
              onTap: () async {
                final ext = p.extension(filePath).toLowerCase();
                final isPreviewable = ext == '.md' || 
                    ext == '.png' || 
                    ext == '.jpg' || 
                    ext == '.jpeg' || 
                    ext == '.gif' || 
                    ext == '.webp';
                if (isPreviewable) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FilePreviewPage(filePath: filePath),
                    ),
                  );
                } else {
                  await ref.read(editorProvider.notifier).openFile(filePath);
                  if (context.mounted) {
                    final scaffold = Scaffold.maybeOf(context);
                    if (scaffold != null && (scaffold.isDrawerOpen || scaffold.isEndDrawerOpen)) {
                      Navigator.pop(context);
                    }
                  }
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Панель Системной Статистики (Изолировано) ─────────────────────────────



class DrawerStatsPanel extends ConsumerWidget {
  const DrawerStatsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(systemStatsProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.activity, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.system,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CPU', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
                        Expanded(
                          child: Text(
                            '${(stats.cpuUsage * 100).toStringAsFixed(0)}%', 
                            textAlign: TextAlign.right,
                            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: _getLoadColor(stats.cpuUsage), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: stats.cpuUsage,
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(_getLoadColor(stats.cpuUsage)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('RAM', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${stats.ramUsedGB.toStringAsFixed(1)} / ${stats.ramTotalGB.toStringAsFixed(0)} GB', 
                              style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _getLoadColor(stats.ramUsage), fontWeight: FontWeight.bold)
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: stats.ramUsage,
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(_getLoadColor(stats.ramUsage)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getLoadColor(double value) {
    if (value < 0.6) return Colors.greenAccent;
    if (value < 0.85) return Colors.amberAccent;
    return Colors.redAccent;
  }
}

// ─── Заголовок AppBar (Изолировано) ──────────────────────────────────────────



class FileDrawerTree extends StatefulWidget {
  final String workspacePath;
  const FileDrawerTree({super.key, required this.workspacePath});

  @override
  State<FileDrawerTree> createState() => FileDrawerTreeState();
}



class FileDrawerTreeState extends State<FileDrawerTree> {
  @override
  Widget build(BuildContext context) {
    return FileTreeNode(
      path: widget.workspacePath,
      name: p.basename(widget.workspacePath),
      isDirectory: true,
      onRefreshParent: () => setState(() {}),
    );
  }
}



class DrawerActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const DrawerActionIcon({super.key, 
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, size: 15, color: Colors.white70),
        ),
      ),
    );
  }
}



