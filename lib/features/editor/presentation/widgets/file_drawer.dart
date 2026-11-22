import 'dart:io';
import 'package:flutter/material.dart';
import 'package:quantum_ide/features/editor/presentation/pages/editor_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/shared/providers/drawer_provider.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
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
import 'package:quantum_ide/features/git/presentation/widgets/git_download_dialog.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/packages_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/live_share_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/extensions_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/app_logs_panel.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';


class FileDrawer extends ConsumerStatefulWidget {
  final bool isInline;
  const FileDrawer({super.key, this.isInline = false});

  @override
  ConsumerState<FileDrawer> createState() => FileDrawerState();
}



class FileDrawerState extends ConsumerState<FileDrawer> {
  // Persistent controller: recreating it on every build reset the cursor and caused jank while typing.
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchVisible = false;
  int _treeRefreshSeed = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _resolveTabTitle(BuildContext context, int selectedTab) {
    final l10n = AppLocalizations.of(context)!;
    switch (selectedTab) {
      case 1:
        return l10n.search;
      case 2:
        return l10n.structure;
      case 3:
        return l10n.disk;
      case 4:
        return l10n.problems;
      case 5:
        return 'Git';
      case 7:
        return l10n.packages;
      case 10:
        return l10n.liveShare;
      case 11:
        return l10n.plugins;
      case 13:
        return l10n.appLogs;
      case 0:
      default:
        return l10n.explorer;
    }
  }

  Widget _buildFilterChip(
    WidgetRef ref,
    String label,
    String query,
    bool isSelected, {
    required Color accentColor,
    required bool isTouchLayout,
  }) {
    return InkWell(
      onTap: () => ref.read(fileSearchQueryProvider.notifier).state = query,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: isTouchLayout
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.06),
            width: 0.6,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: isTouchLayout ? 11.5 : 10.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? accentColor : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required Color accentColor,
    required bool isTouchLayout,
    bool isActive = false,
    Color? color,
  }) {
    final buttonSize = isTouchLayout ? 34.0 : 26.0;
    final iconSize = isTouchLayout ? 16.0 : 13.5;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.12),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            alignment: Alignment.center,
            decoration: isActive
                ? BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  )
                : null,
            child: Icon(
              icon,
              size: iconSize,
              color: isActive
                  ? accentColor
                  : (color ?? Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderMenu(
    BuildContext context,
    WidgetRef ref,
    String workspacePath, {
    required bool isTouchLayout,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final sortLabel = isRu ? 'Сортировка' : 'Sort';
    final buttonSize = isTouchLayout ? 34.0 : 26.0;
    final iconSize = isTouchLayout ? 16.0 : 14.0;
    final itemHeight = isTouchLayout ? 40.0 : 32.0;

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: PopupMenuButton<String>(
        icon: Icon(LucideIcons.ellipsis, size: iconSize, color: Colors.white70),
        padding: EdgeInsets.zero,
        tooltip: l10n.actionsTooltip,
        color: const Color(0xFF1E2230),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
        ),
        onSelected: (value) {
          switch (value) {
            case 'new_folder':
              showCreateDialog(context, ref, workspacePath, true);
              break;
            case 'collapse_all':
              ref.read(expandedFoldersProvider.notifier).setExpanded({});
              break;
            case 'refresh':
              setState(() => _treeRefreshSeed++);
              ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
              break;
            case 'sort':
              showSortMenu(context, ref);
              break;
            case 'git_download':
              GitDownloadDialog.show(
                context,
                workspacePath: workspacePath,
                gitNotifier: ref.read(gitProvider.notifier),
              );
              break;
            case 'env':
              showEnvironmentBottomSheet(context, ref);
              break;
            case 'clean_cache':
              _cleanBuildCacheDialog(context, ref, workspacePath);
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'new_folder',
            height: itemHeight,
            child: Row(
              children: [
                const Icon(LucideIcons.folder_plus, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text(l10n.newFolder, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'collapse_all',
            height: itemHeight,
            child: Row(
              children: [
                const Icon(LucideIcons.folder_closed, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text(l10n.collapseAll, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'refresh',
            height: itemHeight,
            child: Row(
              children: [
                const Icon(LucideIcons.refresh_cw, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text(l10n.refresh, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 'sort',
            height: itemHeight,
            child: Row(
              children: [
                const Icon(LucideIcons.arrow_up_down, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text(sortLabel, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'git_download',
            height: 36,
            child: Row(
              children: [
                Icon(LucideIcons.cloud_download, size: 15, color: Color(0xFF10B981)),
                SizedBox(width: 10),
                Text('Загрузить из Git (файл/папка)', style: TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'env',
            height: itemHeight,
            child: Row(
              children: [
                const Icon(LucideIcons.wrench, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text(l10n.environment, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'clean_cache',
            height: 36,
            child: Row(
              children: [
                Icon(LucideIcons.sparkles, size: 15, color: Colors.amberAccent),
                SizedBox(width: 10),
                Text('Очистить кэш сборки', style: TextStyle(fontSize: 12.5, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _dirSizeBytes(Directory dir) async {
    var total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {}
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  }

  Future<void> _cleanBuildCacheDialog(
    BuildContext context,
    WidgetRef ref,
    String workspacePath,
  ) async {
    if (workspacePath.isEmpty) return;
    final cacheTargets = [
      p.join(workspacePath, 'build'),
      p.join(workspacePath, '.dart_tool'),
      p.join(workspacePath, 'android', '.gradle'),
      p.join(workspacePath, 'android', 'app', 'build'),
      p.join(workspacePath, 'android', 'build'),
    ];
    final existing = <Directory>[];
    var totalBytes = 0;
    for (final path in cacheTargets) {
      final dir = Directory(path);
      if (await dir.exists()) {
        existing.add(dir);
        totalBytes += await _dirSizeBytes(dir);
      }
    }
    if (!context.mounted) return;
    if (existing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Кэш сборки уже пуст')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF151922),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Очистить кэш сборки?',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Будут удалены только временные папки (build, .dart_tool, android/.gradle, android/app/build).\n\nОсвободится: ${_formatBytes(totalBytes)}\nИсходный код проекта не затрагивается.',
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text(
              'Очистить',
              style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final dir in existing) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    if (!context.mounted) return;
    ref.read(fileExplorerProvider.notifier).scanDirectory(workspacePath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Кэш сборки очищен (${_formatBytes(totalBytes)})')),
    );
  }

  Widget _buildActivityIcon(
    WidgetRef ref,
    int index,
    IconData icon,
    String tooltip,
    bool isActive, {
    required Color accentColor,
    int badgeCount = 0,
    Color badgeColor = const Color(0xFFFF3C3C),
    bool isTouchLayout = false,
  }) {
    final iconWidget = Icon(
      icon,
      size: isTouchLayout ? 17.5 : 16.0,
      color: isActive ? accentColor : Colors.white.withValues(alpha: 0.45),
    );

    final itemSize = isTouchLayout ? 42.0 : 40.0;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (index == 6) {
              final isOpen = ref.read(floatingPreviewVisibleProvider);
              ref.read(floatingPreviewVisibleProvider.notifier).state = !isOpen;
              if (!isOpen) {
                ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
                ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
              }
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold != null && scaffold.isDrawerOpen) {
                scaffold.closeDrawer();
              }
              return;
            }
            ref.read(drawerTabProvider.notifier).state = index;
          },
          child: SizedBox(
            width: itemSize,
            height: itemSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isActive)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 2.5,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(2),
                          bottomRight: Radius.circular(2),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                badgeCount > 0
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          iconWidget,
                          Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 14,
                                minHeight: 14,
                              ),
                              child: Text(
                                badgeCount > 99 ? '99+' : '$badgeCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      )
                    : iconWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fileSearchWatcher);
    final workspacePath = ref.watch(workspaceProvider.select((s) => s.currentPath ?? ''));
    final selectedTab = ref.watch(drawerTabProvider);
    final currentQuery = ref.watch(fileSearchQueryProvider);
    final l10n = AppLocalizations.of(context)!;

    // Оптимизировано: учитываем только реальные ошибки (error) и предупреждения (warning), не пугая пользователя красным бейджем из-за мелких подсказок (hint/info).
    final (errorCount, warningCount) = ref.watch(editorProvider.select((s) {
      if (workspacePath.isEmpty) return (0, 0);
      int errors = 0;
      int warnings = 0;
      s.allDiagnostics.forEach((filePath, list) {
        if (filePath.startsWith(workspacePath)) {
          for (final d in list) {
            if (d.severity == CodeDiagnosticSeverity.error) {
              errors++;
            } else if (d.severity == CodeDiagnosticSeverity.warning) {
              warnings++;
            }
          }
        }
      });
      return (errors, warnings);
    }));
    final totalProblems = errorCount + warningCount;
    final problemsBadgeColor = errorCount > 0 ? const Color(0xFFFF3C3C) : const Color(0xFFF59E0B);

    final gitChangesCount = ref.watch(gitProvider.select((s) =>
      (s.status?.stagedFiles.length ?? 0) +
      (s.status?.modifiedFiles.length ?? 0) +
      (s.status?.untrackedFiles.length ?? 0) +
      (s.status?.conflictedFiles.length ?? 0)
    ));

    final screenWidth = MediaQuery.of(context).size.width;
    final isTouchLayout = screenWidth < 768;
    final pluginState = ref.watch(quantumPluginServiceProvider);
    final disabledTabs = pluginState.disabledTabIds;
    final sidebarOrder = pluginState.sidebarLayout != null && pluginState.sidebarLayout!.sectionOrder.isNotEmpty
        ? pluginState.sidebarLayout!.sectionOrder
        : const [
            'explorer', 'search', 'structure', 'disk', 'problems', 'git',
            'preview', 'packages', 'liveShare', 'plugins', 'appLogs'
          ];

    final settings = ref.watch(settingsProvider);
    final drawerPalette = settings.syncAppWithTerminalPalette
        ? resolveConduitPalette(settings.terminalTheme)
        : null;
    final accentColor = drawerPalette?.accent ?? Theme.of(context).colorScheme.primary;
    final dividerColor = drawerPalette?.border ?? Colors.white.withValues(alpha: 0.06);

    // Activity bar on the left
    final activityBarWidth = isTouchLayout ? 44.0 : 42.0;
    final activityBar = Container(
      width: activityBarWidth,
      decoration: BoxDecoration(
        color: drawerPalette?.canvas ?? const Color(0xFF090B0F),
        border: Border(
          right: BorderSide(
            color: dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  for (final sec in sidebarOrder) ...[
                    if (!disabledTabs.contains(sec)) ...[
                      if (sec == 'explorer')
                        _buildActivityIcon(
                          ref,
                          0,
                          LucideIcons.files,
                          l10n.explorer,
                          selectedTab == 0,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'search')
                        _buildActivityIcon(
                          ref,
                          1,
                          LucideIcons.search,
                          l10n.search,
                          selectedTab == 1,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'structure')
                        _buildActivityIcon(
                          ref,
                          2,
                          LucideIcons.list,
                          l10n.structure,
                          selectedTab == 2,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'disk')
                        _buildActivityIcon(
                          ref,
                          3,
                          LucideIcons.chart_pie,
                          l10n.disk,
                          selectedTab == 3,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'problems')
                        _buildActivityIcon(
                          ref,
                          4,
                          LucideIcons.circle_alert,
                          l10n.problems,
                          selectedTab == 4,
                          accentColor: accentColor,
                          badgeCount: totalProblems,
                          badgeColor: problemsBadgeColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'git')
                        _buildActivityIcon(
                          ref,
                          5,
                          LucideIcons.git_branch,
                          'Git',
                          selectedTab == 5,
                          accentColor: accentColor,
                          badgeCount: gitChangesCount,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'preview')
                        _buildActivityIcon(
                          ref,
                          6,
                          LucideIcons.server,
                          l10n.preview,
                          ref.watch(floatingPreviewVisibleProvider),
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'packages')
                        _buildActivityIcon(
                          ref,
                          7,
                          LucideIcons.toy_brick,
                          l10n.packages,
                          selectedTab == 7,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'liveShare')
                        _buildActivityIcon(
                          ref,
                          10,
                          LucideIcons.users,
                          l10n.liveShare,
                          selectedTab == 10,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'plugins')
                        _buildActivityIcon(
                          ref,
                          11,
                          LucideIcons.puzzle,
                          l10n.plugins,
                          selectedTab == 11,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                      if (sec == 'appLogs')
                        _buildActivityIcon(
                          ref,
                          13,
                          LucideIcons.terminal,
                          l10n.appLogs,
                          selectedTab == 13,
                          accentColor: accentColor,
                          isTouchLayout: isTouchLayout,
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 4),
          Tooltip(
            message: l10n.settings,
            child: InkWell(
              onTap: () {
                context.push('/settings');
              },
              child: SizedBox(
                width: activityBarWidth,
                height: activityBarWidth,
                child: Icon(
                  LucideIcons.settings,
                  size: isTouchLayout ? 17.5 : 16.0,
                  color: Colors.white38,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );

    // Unified header displayed across ALL sidebar tabs
    final unifiedHeader = Container(
      height: isTouchLayout ? 44.0 : 38.0,
      padding: EdgeInsets.only(left: isTouchLayout ? 12.0 : 10.0, right: 6.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _resolveTabTitle(context, selectedTab).toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.white70,
              ),
            ),
          ),
          if (selectedTab == 0 && workspacePath.isNotEmpty) ...[
            _buildHeaderAction(
              icon: LucideIcons.file_plus,
              tooltip: l10n.newFile,
              accentColor: accentColor,
              isTouchLayout: isTouchLayout,
              onPressed: () => showCreateDialog(context, ref, workspacePath, false),
            ),
            _buildHeaderAction(
              icon: LucideIcons.list_filter,
              tooltip: l10n.searchFiles,
              accentColor: accentColor,
              isTouchLayout: isTouchLayout,
              isActive: _isSearchVisible || currentQuery.isNotEmpty,
              onPressed: () {
                setState(() {
                  _isSearchVisible = !_isSearchVisible;
                  if (!_isSearchVisible) {
                    ref.read(fileSearchQueryProvider.notifier).state = '';
                    _searchController.clear();
                  }
                });
              },
            ),
            _buildHeaderMenu(
              context,
              ref,
              workspacePath,
              isTouchLayout: isTouchLayout,
            ),
          ],
          if (!widget.isInline)
            _buildHeaderAction(
              icon: LucideIcons.x,
              tooltip: l10n.close,
              accentColor: accentColor,
              isTouchLayout: isTouchLayout,
              color: Colors.white60,
              onPressed: () {
                final scaffold = Scaffold.maybeOf(context);
                if (scaffold != null && scaffold.isDrawerOpen) {
                  scaffold.closeDrawer();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
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
      case 7:
        activePanel = const SidebarPackagesPanel();
        break;
      case 10:
        activePanel = const LiveSharePanel();
        break;
      case 11:
        activePanel = const ExtensionsPanel();
        break;
      case 13:
        activePanel = const AppLogsPanel();
        break;
      case 0:
      default:
        activePanel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact Filter & Quick Chips dropdown (only when filter is toggled or active)
            if (workspacePath.isNotEmpty && (_isSearchVisible || currentQuery.isNotEmpty)) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(8, isTouchLayout ? 8 : 6, 8, isTouchLayout ? 8 : 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: isTouchLayout ? 36.0 : 28.0,
                      child: TextField(
                        onChanged: (value) => ref.read(fileSearchQueryProvider.notifier).state = value,
                        controller: () {
                          if (_searchController.text != currentQuery) {
                            _searchController.value = TextEditingValue(
                              text: currentQuery,
                              selection: TextSelection.collapsed(offset: currentQuery.length),
                            );
                          }
                          return _searchController;
                        }(),
                        decoration: InputDecoration(
                          hintText: l10n.searchFiles,
                          hintStyle: TextStyle(
                            fontSize: isTouchLayout ? 12.5 : 11.5,
                            color: Colors.white30,
                          ),
                          prefixIcon: Icon(
                            LucideIcons.list_filter,
                            size: isTouchLayout ? 15 : 13,
                            color: Colors.white38,
                          ),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: isTouchLayout ? 32 : 26,
                            minHeight: isTouchLayout ? 32 : 26,
                          ),
                          suffixIcon: currentQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    LucideIcons.x,
                                    size: isTouchLayout ? 14 : 12,
                                    color: Colors.white54,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(
                                    minWidth: isTouchLayout ? 32 : 24,
                                    minHeight: isTouchLayout ? 32 : 24,
                                  ),
                                  onPressed: () {
                                    ref.read(fileSearchQueryProvider.notifier).state = '';
                                    _searchController.clear();
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isTouchLayout ? 8 : 4,
                            horizontal: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: accentColor, width: 1.0),
                          ),
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          filled: true,
                        ),
                        style: TextStyle(
                          fontSize: isTouchLayout ? 12.5 : 11.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: isTouchLayout ? 8 : 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip(
                            ref,
                            l10n.all,
                            '',
                            currentQuery == '',
                            accentColor: accentColor,
                            isTouchLayout: isTouchLayout,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            ref,
                            'Dart',
                            '.dart',
                            currentQuery == '.dart',
                            accentColor: accentColor,
                            isTouchLayout: isTouchLayout,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            ref,
                            'YAML',
                            '.yaml',
                            currentQuery == '.yaml',
                            accentColor: accentColor,
                            isTouchLayout: isTouchLayout,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            ref,
                            'JSON',
                            '.json',
                            currentQuery == '.json',
                            accentColor: accentColor,
                            isTouchLayout: isTouchLayout,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            ref,
                            'Web',
                            '.html',
                            currentQuery == '.html',
                            accentColor: accentColor,
                            isTouchLayout: isTouchLayout,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
            ],
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context)!.elementMovedToRoot)),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context)!.moveError(e.toString()))),
                        );
                      }
                    }
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isOver = candidateData.isNotEmpty;
                    return Container(
                      color: isOver ? accentColor.withValues(alpha: 0.08) : Colors.transparent,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBookmarksSection(
                              context,
                              ref,
                              workspacePath,
                              accentColor: accentColor,
                              isTouchLayout: isTouchLayout,
                            ),
                            if (ref.watch(bookmarksProvider).isNotEmpty)
                              const Divider(height: 1, color: Colors.white10, indent: 12, endIndent: 12),
                            FileDrawerTree(
                              key: ValueKey(
                                'file_tree_${workspacePath}_${_treeRefreshSeed}_${ref.watch(fileTreeRefreshProvider)}',
                              ),
                              workspacePath: workspacePath,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Text(
                    l10n.projectNotOpened,
                    style: const TextStyle(color: Colors.grey),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                unifiedHeader,
                Expanded(child: activePanel),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.isInline) {
      return Container(
        decoration: BoxDecoration(
          color: (drawerPalette?.panel ?? const Color(0xFF0D0F14))
              .withValues(alpha: drawerPalette != null ? 0.92 : 0.5),
          border: Border(
            right: BorderSide(
              color: drawerPalette?.border ?? Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
        ),
        child: content,
      );
    }

    final drawerWidth = isTouchLayout
        ? (screenWidth * 0.85).clamp(280.0, 380.0).clamp(0.0, screenWidth)
        : 340.0;

    return GlassContainer(
      blur: 30,
      opacity: 0.92,
      color: drawerPalette?.panel ?? const Color(0xFF0F1117),
      borderRadius: BorderRadius.zero,
      border: Border(
        right: BorderSide(
          color: drawerPalette?.border ?? Colors.white.withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      child: Drawer(
        width: drawerWidth,
        backgroundColor: Colors.transparent,
        elevation: 16,
        child: content,
      ),
    );
  }

  Widget _buildBookmarksSection(
    BuildContext context,
    WidgetRef ref,
    String workspacePath, {
    required Color accentColor,
    required bool isTouchLayout,
  }) {
    final bookmarks = ref.watch(bookmarksProvider);
    if (bookmarks.isEmpty) {
      return const SizedBox.shrink();
    }
    final title = AppLocalizations.of(context)!.bookmarks;
    final activeFilePath = ref.watch(editorProvider.select((s) => s.activeFilePath));

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const PageStorageKey<String>('bookmarks_expansion_tile'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        leading: const Icon(LucideIcons.star, size: 13.5, color: Colors.amberAccent),
        minTileHeight: isTouchLayout ? 36 : 30,
        title: Text(
          title.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: Colors.white60,
          ),
        ),
        dense: true,
        iconColor: Colors.white60,
        collapsedIconColor: Colors.white30,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        initiallyExpanded: true,
        children: bookmarks.map((filePath) {
          final fileName = p.basename(filePath);
          final relativePath = p.relative(filePath, from: workspacePath);
          final iconInfo = FileIconHelper.getIconInfo(fileName, false, false);
          final isActive = activeFilePath == filePath;

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
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
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                padding: EdgeInsets.only(
                  left: 8,
                  right: 4,
                  top: isTouchLayout ? 5 : 3,
                  bottom: isTouchLayout ? 5 : 3,
                ),
                decoration: BoxDecoration(
                  color: isActive ? accentColor.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Icon(
                      iconInfo.icon,
                      size: isTouchLayout ? 16.0 : 14.5,
                      color: iconInfo.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fileName,
                            style: TextStyle(
                              fontSize: isTouchLayout ? 13.0 : 12.0,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.9),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            relativePath,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        icon: Icon(
                          LucideIcons.star_off,
                          size: 13.5,
                          color: Colors.redAccent.withValues(alpha: 0.8),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                        tooltip: AppLocalizations.of(context)!.removeFromBookmarks,
                        onPressed: () {
                          ref.read(bookmarksProvider.notifier).toggleBookmark(filePath);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

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
