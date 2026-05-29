import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:re_editor/re_editor.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/core/services/ai_autocomplete_service.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:flutter/services.dart';
import 'package:quantum_ide/features/editor/presentation/handlers/autocomplete_handler.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/diff_gutter_indicator.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/diagnostic_indicator.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/keyboard_accessory_bar.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/services/diff_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/quick_switcher_dialog.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/problems_panel.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/core/services/environment_service.dart';
import 'package:quantum_ide/shared/widgets/status_bar.dart';
import 'package:quantum_ide/shared/widgets/breadcrumbs.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/features/file_explorer/presentation/widgets/global_search_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/code_outline_widget.dart';
import 'package:quantum_ide/features/file_explorer/presentation/widgets/disk_analyzer_widget.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/file_explorer_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_panel_content.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/lsp_autocomplete_service.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/right_chat_panel.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/file_explorer/presentation/notifiers/bookmarks_notifier.dart';
import 'package:quantum_ide/features/file_explorer/presentation/pages/file_preview_page.dart';
import 'package:quantum_ide/features/git/presentation/widgets/git_panel.dart';
import 'package:quantum_ide/features/preview/presentation/widgets/web_preview_panel.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/packages_panel.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/run_build_panels.dart';

// ─── Вспомогательные функции для диалогов и меню ───────────────────────────

void _showSortMenu(BuildContext context, WidgetRef ref) async {
  final RenderBox button = context.findRenderObject() as RenderBox;
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final result = await showMenu<FileSortMode>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(value: FileSortMode.name, child: Text(AppLocalizations.of(context)!.sortByName)),
      PopupMenuItem(value: FileSortMode.size, child: Text(AppLocalizations.of(context)!.sortBySize)),
      PopupMenuItem(value: FileSortMode.date, child: Text(AppLocalizations.of(context)!.sortByDate)),
    ],
  );
  if (result != null) {
    ref.read(fileSortModeProvider.notifier).state = result;
  }
}

Future<void> _showCreateDialog(BuildContext context, WidgetRef ref, String basePath, bool isDir) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isDir ? AppLocalizations.of(context)!.newFolder : AppLocalizations.of(context)!.newFile),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: isDir ? 'имя_папки' : 'файл.txt'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(AppLocalizations.of(context)!.create)),
      ],
    ),
  );

  if (name != null && name.isNotEmpty) {
    final newPath = p.join(basePath, name);
    if (isDir) {
      await Directory(newPath).create();
    } else {
      await File(newPath).create();
    }
    
    // Mirror to external storage
    await ref.read(projectServiceProvider.notifier).mirrorEntity(newPath);

    ref.read(expandedFoldersProvider.notifier).setExpanded({
      ...ref.read(expandedFoldersProvider),
      basePath,
    });
  }
}

void _showEnvironmentBottomSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xff18181b),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Consumer(
        builder: (context, ref, _) {
          final envState = ref.watch(environmentProvider);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Системное окружение',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          if (envState.isChecking)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                            )
                          else
                            IconButton(
                              icon: const Icon(LucideIcons.refresh_cw, size: 18, color: Colors.blueAccent),
                              onPressed: () => ref.read(environmentProvider.notifier).checkEnvironment(),
                            ),
                          IconButton(
                            icon: const Icon(LucideIcons.wrench, size: 18, color: Colors.orangeAccent),
                            tooltip: 'Исправить окружение (ARM64)',
                            onPressed: () => ref.read(environmentProvider.notifier).fixEnvironment(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: envState.tools.map((tool) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: tool.isInstalled 
                                    ? Colors.green.withValues(alpha: 0.1) 
                                    : Colors.red.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  tool.isInstalled ? LucideIcons.circle_check : LucideIcons.circle_alert,
                                  size: 16,
                                  color: tool.isInstalled ? Colors.greenAccent : Colors.redAccent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tool.name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (tool.isInstalled && tool.version != null)
                                      Text(
                                        tool.version!,
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    if (tool.error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          tool.error!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: tool.isInstalled ? Colors.orangeAccent : Colors.redAccent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// ─── Боковое Меню Проводника (Изолировано) ───────────────────────────────────

// ─── Боковое Меню Проводника (Изолировано) ───────────────────────────────────

final drawerTabProvider = StateProvider<int>((ref) => 0);

class _FileDrawer extends ConsumerStatefulWidget {
  final bool isInline;
  const _FileDrawer({this.isInline = false});

  @override
  ConsumerState<_FileDrawer> createState() => _FileDrawerState();
}

class _FileDrawerState extends ConsumerState<_FileDrawer> {
  bool _isResizingHovered = false;

  Widget _buildActivityIcon(WidgetRef ref, int index, IconData icon, String tooltip, bool isActive, {int badgeCount = 0}) {
    final iconWidget = Icon(
      icon,
      size: 20,
      color: isActive ? const Color(0xFFFF3C3C) : Colors.white38,
    );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => ref.read(drawerTabProvider.notifier).state = index,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isActive ? const Color(0xFFFF3C3C) : Colors.transparent, // Mandy Red
                width: 2.5,
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
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
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
    final workspacePath = ref.watch(workspaceProvider).currentPath ?? '';
    final selectedTab = ref.watch(drawerTabProvider);
    final editorState = ref.watch(editorProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    // Count workspace diagnostics problems
    int totalProblems = 0;
    editorState.allDiagnostics.forEach((filePath, list) {
      if (workspacePath.isNotEmpty && filePath.startsWith(workspacePath)) {
        totalProblems += list.length;
      }
    });

    final gitChangesCount = ref.watch(gitProvider.select((s) =>
      (s.status?.stagedFiles.length ?? 0) +
      (s.status?.modifiedFiles.length ?? 0) +
      (s.status?.untrackedFiles.length ?? 0) +
      (s.status?.conflictedFiles.length ?? 0)
    ));

    // Activity bar on the left
    final activityBar = Container(
      width: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF090B0F),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildActivityIcon(ref, 0, LucideIcons.files, 'Проводник', selectedTab == 0),
            _buildActivityIcon(ref, 1, LucideIcons.search, 'Поиск', selectedTab == 1),
            _buildActivityIcon(ref, 2, LucideIcons.list, 'Структура', selectedTab == 2),
            _buildActivityIcon(ref, 3, LucideIcons.chart_pie, 'Диск', selectedTab == 3),
            _buildActivityIcon(ref, 4, LucideIcons.circle_alert, 'Проблемы', selectedTab == 4, badgeCount: totalProblems),
            _buildActivityIcon(ref, 5, LucideIcons.git_branch, 'Git', selectedTab == 5, badgeCount: gitChangesCount),
            _buildActivityIcon(ref, 6, LucideIcons.server, 'Предпросмотр', selectedTab == 6),
            _buildActivityIcon(ref, 7, LucideIcons.toy_brick, 'Пакеты', selectedTab == 7),
            _buildActivityIcon(ref, 8, LucideIcons.play, isRu ? 'Запуск' : 'Run', selectedTab == 8),
            _buildActivityIcon(ref, 9, LucideIcons.hammer, isRu ? 'Сборка' : 'Build', selectedTab == 9),
          ],
        ),
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
      case 0:
      default:
        activePanel = Column(
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
                          _DrawerActionIcon(
                            icon: LucideIcons.wrench,
                            tooltip: 'Окружение',
                            onPressed: () => _showEnvironmentBottomSheet(context, ref),
                          ),
                          _DrawerActionIcon(
                            icon: LucideIcons.folder_closed,
                            tooltip: 'Свернуть все',
                            onPressed: () {
                              ref.read(expandedFoldersProvider.notifier).setExpanded({});
                            },
                          ),
                          _DrawerActionIcon(
                            icon: LucideIcons.arrow_up_down,
                            tooltip: AppLocalizations.of(context)!.sortByDate.split(' ').first,
                            onPressed: () => _showSortMenu(context, ref),
                          ),
                          _DrawerActionIcon(
                            icon: LucideIcons.file_plus,
                            tooltip: AppLocalizations.of(context)!.newFile,
                            onPressed: () => _showCreateDialog(context, ref, workspacePath, false),
                          ),
                          _DrawerActionIcon(
                            icon: LucideIcons.folder_plus,
                            tooltip: AppLocalizations.of(context)!.newFolder,
                            onPressed: () => _showCreateDialog(context, ref, workspacePath, true),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (workspacePath.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (value) => ref.read(fileSearchQueryProvider.notifier).state = value,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.searchFiles,
                        hintStyle: const TextStyle(fontSize: 12.5),
                        prefixIcon: const Icon(LucideIcons.search, size: 14),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        filled: true,
                      ),
                      style: const TextStyle(fontSize: 12.5),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Элемент перемещен в корень')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка перемещения: $e')),
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
                            _FileDrawerTree(workspacePath: workspacePath),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Expanded(child: Center(child: Text(AppLocalizations.of(context)!.projectNotOpened, style: const TextStyle(color: Colors.grey)))),
            const _DrawerStatsPanel(),
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

    final leftWidth = ref.watch(leftPanelWidthProvider);

    if (widget.isInline) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: leftWidth,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F14).withValues(alpha: 0.5),
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
            ),
            child: content,
          ),
          Positioned(
            right: -3,
            top: 0,
            bottom: 0,
            width: 6,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              onEnter: (_) => setState(() => _isResizingHovered = true),
              onExit: (_) => setState(() => _isResizingHovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  final currentWidth = ref.read(leftPanelWidthProvider);
                  final newWidth = (currentWidth + details.primaryDelta!).clamp(240.0, 600.0);
                  ref.read(leftPanelWidthProvider.notifier).state = newWidth;
                },
                child: Container(
                  color: _isResizingHovered ? Colors.cyanAccent.withValues(alpha: 0.4) : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GlassContainer(
      blur: 30,
      opacity: 0.15,
      borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
      border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5)),
      child: Drawer(
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
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final title = isRu ? 'Закладки' : 'Bookmarks';

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

class _DrawerStatsPanel extends ConsumerWidget {
  const _DrawerStatsPanel();

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
                        Text('CPU', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                        Text('${(stats.cpuUsage * 100).toStringAsFixed(0)}%', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _getLoadColor(stats.cpuUsage), fontWeight: FontWeight.bold)),
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
                        Text('RAM', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                        Text('${stats.ramUsedGB.toStringAsFixed(1)} / ${stats.ramTotalGB.toStringAsFixed(0)} GB', style: GoogleFonts.jetBrainsMono(fontSize: 9, color: _getLoadColor(stats.ramUsage), fontWeight: FontWeight.bold)),
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

class _EditorAppBarTitle extends ConsumerWidget {
  const _EditorAppBarTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFileName = ref.watch(editorProvider.select((s) {
      if (s.openFiles.isEmpty) return '';
      int idx = s.activeTabIndex;
      if (idx < 0 || idx >= s.openFiles.length) {
        idx = s.openFiles.length - 1;
      }
      return s.openFiles[idx].name;
    }));
    return Text(
      activeFileName,
      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }
}

// ─── Строка Вкладок Редактора (Изолировано) ──────────────────────────────────

class _EditorTabBar extends ConsumerWidget {
  const _EditorTabBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openFiles = ref.watch(editorProvider.select((s) => s.openFiles));
    final activeTabIndex = ref.watch(editorProvider.select((s) => s.activeTabIndex));
    final notifier = ref.read(editorProvider.notifier);

    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.03), width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: openFiles.length,
        itemBuilder: (context, index) {
          final file = openFiles[index];
          final isActive = index == activeTabIndex;
          return GestureDetector(
            onTap: () => notifier.setActiveTab(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  () {
                    final iconInfo = FileIconHelper.getIconInfo(file.name, false);
                    return Icon(
                      iconInfo.icon,
                      size: 12,
                      color: isActive ? iconInfo.color : iconInfo.color.withValues(alpha: 0.5),
                    );
                  }(),
                  const SizedBox(width: 6),
                  Text(
                    file.name + (file.isModified ? ' •' : ''), 
                    style: GoogleFonts.inter(
                      fontSize: 11, 
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? Colors.white : Colors.white60,
                    )
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => notifier.closeTab(index),
                    child: Icon(
                      LucideIcons.x, 
                      size: 10, 
                      color: isActive ? Colors.white54 : Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Главная Страница Редактора ──────────────────────────────────────────────

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Вызывается один раз при смене workspace — не на каждый build()
  void _onWorkspaceChanged(String workspacePath) {
    // Раскрываем корневую папку
    final expandedSet = ref.read(expandedFoldersProvider);
    if (expandedSet.isEmpty) {
      ref.read(expandedFoldersProvider.notifier).setExpanded({workspacePath});
    }

    // Создаём терминальную сессию если нужно
    final runtime = ref.read(runtimeServiceProvider);
    final guestPath = PathMapper.mapToGuest(workspacePath, runtime.appDirectory);
    final hasProjectSession = ref.read(terminalTabsProvider).any((s) => s.workingDir == guestPath);
    if (!hasProjectSession) {
      ref.read(terminalTabsProvider.notifier).createNewSession(workingDir: workspacePath);
    }
    
    // Событийный запрос Git статуса при смене рабочего пространства
    ref.read(gitProvider.notifier).refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final openFilesCount = ref.watch(editorProvider.select((s) => s.openFiles.length));
    final activeTabIndex = ref.watch(editorProvider.select((s) => s.activeTabIndex));
    final activeFile = ref.watch(editorProvider.select((s) => s.openFiles.isNotEmpty && activeTabIndex < s.openFiles.length ? s.openFiles[activeTabIndex] : null));
    
    final settings = ref.watch(settingsProvider);
    final workspacePath = ref.watch(workspaceProvider).currentPath;
    final panelState = ref.watch(panelProvider);
    final panelNotifier = ref.read(panelProvider.notifier);
    
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    // Слушаем смену workspace ОДИН РАЗ — не на каждый build()
    ref.listen<WorkspaceState>(workspaceProvider, (prev, next) {
      final newPath = next.currentPath;
      if (newPath != null && newPath != prev?.currentPath) {
        // Вызываем после окончания текущего кадра
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onWorkspaceChanged(newPath);
        });
      }
    });

    ref.listen<bool>(rightChatPanelOpenProvider, (previous, current) {
      if (current) {
        if (!isDesktop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scaffoldKey.currentState?.openEndDrawer();
          });
        }
      } else {
        if (!isDesktop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
          });
        }
      }
    });

    if (openFilesCount == 0 || activeFile == null) {
      final emptyBody = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.code, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.selectFileToStart, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (!isDesktop)
              Builder(
                builder: (context) => ElevatedButton.icon(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(LucideIcons.folder_open, size: 18),
                  label: Text(AppLocalizations.of(context)!.openExplorer),
                ),
              ),
          ],
        ),
      );

      return Scaffold(
        drawer: isDesktop ? null : const _FileDrawer(),
        appBar: AppBar(
          title: const Text('QuantumIDE'),
          leading: isDesktop
              ? IconButton(
                  icon: const Icon(LucideIcons.arrow_left),
                  onPressed: () {
                    ref.read(workspaceProvider.notifier).closeWorkspace();
                    context.go('/');
                  },
                )
              : null,
        ),
        body: isDesktop ? Row(
          children: [
            const _FileDrawer(isInline: true),
            Expanded(child: emptyBody),
          ],
        ) : emptyBody,
      );
    }

    // Safety check for index
    int safeActiveIndex = activeTabIndex;
    if (safeActiveIndex >= openFilesCount) {
      safeActiveIndex = openFilesCount - 1;
    }
    if (safeActiveIndex < 0) safeActiveIndex = 0;

    final diagnosticsCount = ref.watch(editorProvider.select((s) {
      int count = 0;
      s.allDiagnostics.forEach((filePath, list) {
        if (workspacePath != null && filePath.startsWith(workspacePath)) {
          count += list.length;
        }
      });
      return count;
    }));
    final gitChangesCount = ref.watch(gitProvider.select((s) => 
      (s.status?.stagedFiles.length ?? 0) + 
      (s.status?.modifiedFiles.length ?? 0) + 
      (s.status?.untrackedFiles.length ?? 0) +
      (s.status?.conflictedFiles.length ?? 0)
    ));
    final isServerRunning = ref.watch(serverRunningProvider);

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    final mainBody = LayoutBuilder(
      builder: (context, constraints) {
        final double availableHeight = constraints.maxHeight;

        // Panel height: drag range 90..availableHeight (full screen overlay)
        double activePanelHeight = 0.0;
        if (panelState.isOpened) {
          if (panelState.isMaximized) {
            activePanelHeight = availableHeight;
          } else {
            activePanelHeight = panelState.panelHeight.clamp(90.0, availableHeight);
          }
        }

        return Stack(
          children: [
            // ── Редактор (всегда на весь экран) ──────────────────────
            Positioned.fill(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Breadcrumbs(path: activeFile.path, workspacePath: workspacePath),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.search, size: 16, color: Colors.cyanAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        constraints: const BoxConstraints(),
                        onPressed: () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.files),
                        tooltip: isRu ? 'Быстрый поиск (Ctrl+P)' : 'Quick Search (Ctrl+P)',
                      ),
                    ],
                  ),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                            () => ref.read(editorProvider.notifier).saveFile(safeActiveIndex),
                        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
                            () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.files),
                        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                            () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.symbols),
                      },
                      child: () {
                        // Optimization for low-end devices: only build the active editor.
                        // Re-editor state is preserved because the controller is kept in EditorNotifier.
                        final file = activeFile;
                        final editor = settings.autoCompletion
                            ? CodeAutocomplete(
                                viewBuilder: (context, notifier, onSelected) {
                                  return _QuantumAutocompleteView(
                                      notifier: notifier, onSelected: onSelected);
                                },
                                promptsBuilder: QuantumAutocompletePromptsBuilder(),
                                child: _StableEditorWidget(
                                  key: ValueKey(file.path),
                                  file: file,
                                  settings: settings,
                                ),
                              )
                            : _StableEditorWidget(
                                key: ValueKey(file.path),
                                file: file,
                                settings: settings,
                              );
                        return editor;
                      }(),
                    ),
                  ),
                  KeyboardAccessoryBar(controller: activeFile.controller),
                ],
              ),
            ),

            // ── Панель (overlay, выезжает снизу поверх редактора) ────
            AnimatedPositioned(
              duration: _isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: activePanelHeight,
              child: activePanelHeight > 0
                  ? _buildBottomPanel(
                      context,
                      ref,
                      panelState,
                      panelNotifier,
                      diagnosticsCount,
                      gitChangesCount,
                      isServerRunning,
                      availableHeight,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        if (isKeyboardOpen) {
          FocusManager.instance.primaryFocus?.unfocus();
          return;
        }

        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }

        if (panelState.isOpened) {
          panelNotifier.closePanel();
          return;
        }

        await ref.read(workspaceProvider.notifier).closeWorkspace();
        if (context.mounted) {
          context.go('/');
        }
      },
      child: Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: isDesktop ? null : const _FileDrawer(),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: GlassContainer(
          blur: 30,
          opacity: 0.1,
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
          child: SafeArea(
            child: Column(
              children: [
                // Top Row: Leading, File Name, Actions
                Expanded(
                  child: Row(
                    children: [
                      if (!isDesktop)
                        IconButton(
                          icon: const Icon(LucideIcons.library, size: 16, color: Colors.blueAccent),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          tooltip: 'Открыть проводник',
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          constraints: const BoxConstraints(),
                        )
                      else
                        IconButton(
                          icon: const Icon(LucideIcons.arrow_left, size: 16),
                          onPressed: () {
                            ref.read(workspaceProvider.notifier).closeWorkspace();
                            context.go('/');
                          },
                          tooltip: 'Назад',
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          constraints: const BoxConstraints(),
                        ),
                      const Expanded(
                        child: _EditorAppBarTitle(),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ActionIconButton(
                            icon: LucideIcons.save,
                            tooltip: isRu ? 'Сохранить' : 'Save',
                            onTap: () => ref.read(editorProvider.notifier).saveFile(safeActiveIndex),
                          ),
                          _ActionIconButton(
                            icon: LucideIcons.terminal,
                            tooltip: isRu ? 'Терминал' : 'Terminal',
                            onTap: () {
                              if (panelState.isOpened && panelState.selectedTab == PanelTab.terminal) {
                                panelNotifier.closePanel();
                              } else {
                                panelNotifier.selectTab(PanelTab.terminal);
                                panelNotifier.openPanel();
                              }
                            },
                          ),
                          _ActionIconButton(
                            icon: LucideIcons.message_square,
                            tooltip: isRu ? 'Чат с ИИ' : 'AI Chat',
                            onTap: () {
                              ref.read(rightChatPanelOpenProvider.notifier).update((v) => !v);
                            },
                          ),
                          if (!isDesktop)
                            _ActionIconButton(
                              icon: LucideIcons.house,
                              tooltip: 'Домой',
                              onTap: () async {
                                await ref.read(workspaceProvider.notifier).closeWorkspace();
                                if (context.mounted) {
                                  context.go('/');
                                }
                              },
                            ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ],
                  ),
                ),
                // Tabs Row
                const _EditorTabBar(),
              ],
            ),
          ),
        ),
      ),
      endDrawer: isDesktop ? null : const RightChatPanel(isInline: false),
      body: isDesktop ? Row(
        children: [
          const _FileDrawer(isInline: true),
          Expanded(child: mainBody),
          if (ref.watch(rightChatPanelOpenProvider))
            const RightChatPanel(isInline: true),
        ],
      ) : mainBody,
      bottomNavigationBar: const StatusBar(),
    ),
  );
  }

  // _buildPanelHeader is no longer needed

  Widget _buildBottomPanel(
    BuildContext context,
    WidgetRef ref,
    PanelState panelState,
    PanelNotifier panelNotifier,
    int diagnosticsCount,
    int gitChangesCount,
    bool isServerRunning,
    double maxAllowedPanelHeight,
  ) {
    final double targetHeight = panelState.isMaximized
        ? maxAllowedPanelHeight
        : panelState.panelHeight.clamp(80.0, maxAllowedPanelHeight);

    return OverflowBox(
      minHeight: targetHeight,
      maxHeight: targetHeight,
      alignment: Alignment.topCenter,
      child: Container(
        height: targetHeight,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0F14),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPanelHeader(context, panelState, panelNotifier, maxAllowedPanelHeight),
            Expanded(
              child: panelState.panelHeight > 60
                  ? const TerminalPanelContent(onlyTerminal: true)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelHeader(
    BuildContext context,
    PanelState panelState,
    PanelNotifier panelNotifier,
    double maxAllowedPanelHeight,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onVerticalDragUpdate: (details) {
        const double minPanelHeight = 80.0;
        final newHeight = (panelState.panelHeight - details.primaryDelta!)
            .clamp(minPanelHeight, maxAllowedPanelHeight);
        panelNotifier.updateHeight(newHeight);
      },
      onVerticalDragEnd: (details) {
        setState(() {
          _isDragging = false;
        });
        // Snap: если высота меньше минимума — закрываем панель
        if (panelState.panelHeight < 75) {
          panelNotifier.closePanel();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161925),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag pill
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    _getTabIcon(panelState.selectedTab),
                    size: 15,
                    color: _getTabColor(panelState.selectedTab),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getTabTitle(context, panelState.selectedTab).toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  // Кнопки с явными ограничениями — без 48px минимума
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      icon: Icon(
                        panelState.isMaximized
                            ? LucideIcons.minimize_2
                            : LucideIcons.maximize_2,
                        size: 14,
                        color: Colors.white60,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      onPressed: () => panelNotifier.toggleMaximized(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      icon: const Icon(LucideIcons.x, size: 14, color: Colors.white60),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      onPressed: () => panelNotifier.closePanel(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }




  IconData _getTabIcon(PanelTab tab) {
    switch (tab) {
      case PanelTab.terminal: return LucideIcons.terminal;
      case PanelTab.appLogs: return LucideIcons.list;
      case PanelTab.run: return LucideIcons.play;
      case PanelTab.buildLogs: return LucideIcons.hammer;
      case PanelTab.git: return LucideIcons.git_branch;
      case PanelTab.aiAgent: return LucideIcons.bot;
      case PanelTab.problems: return LucideIcons.circle_alert;
      case PanelTab.servers: return LucideIcons.server;
      case PanelTab.packages: return LucideIcons.toy_brick;
      default: return LucideIcons.terminal;
    }
  }

  Color _getTabColor(PanelTab tab) {
    switch (tab) {
      case PanelTab.terminal: return Colors.cyanAccent;
      case PanelTab.appLogs: return Colors.deepPurpleAccent;
      case PanelTab.run: return Colors.greenAccent;
      case PanelTab.buildLogs: return Colors.orangeAccent;
      case PanelTab.git: return Colors.amberAccent;
      case PanelTab.aiAgent: return Colors.purpleAccent;
      case PanelTab.problems: return Colors.redAccent;
      case PanelTab.servers: return Colors.blueAccent;
      case PanelTab.packages: return Colors.tealAccent;
      default: return Colors.cyanAccent;
    }
  }

  String _getTabTitle(BuildContext context, PanelTab tab) {
    final l10n = AppLocalizations.of(context)!;
    switch (tab) {
      case PanelTab.terminal: return l10n.terminal;
      case PanelTab.appLogs: return l10n.appLogs;
      case PanelTab.run: return l10n.run;
      case PanelTab.buildLogs: return l10n.build;
      case PanelTab.git: return 'Git';
      case PanelTab.aiAgent: return l10n.aiAgent;
      case PanelTab.problems: return l10n.problems;
      case PanelTab.servers: return l10n.servers;
      case PanelTab.packages: return l10n.packages;
      default: return l10n.tools;
    }
  }
}

// ─── Дерево файлов (изолированный StatefulWidget) ───────────────────────────
// Отдельный виджет для дерева файлов, чтобы onRefreshParent вызывал setState
// только на нём, а не на всём EditorPage.
class _FileDrawerTree extends StatefulWidget {
  final String workspacePath;
  const _FileDrawerTree({required this.workspacePath});

  @override
  State<_FileDrawerTree> createState() => _FileDrawerTreeState();
}

class _FileDrawerTreeState extends State<_FileDrawerTree> {
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

class DiffBackgroundPainter extends CustomPainter {
  final CodeIndicatorValueNotifier? notifier;
  final List<DiffMarker> markers;

  DiffBackgroundPainter({required this.notifier, required this.markers}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final val = notifier?.value;
    if (val == null || markers.isEmpty) return;

    for (final paragraph in val.paragraphs) {
      final lineIndex = paragraph.index;
      final marker = markers.firstWhere(
        (m) => m.line == lineIndex,
        orElse: () => DiffMarker(line: -1, type: DiffType.added),
      );

      if (marker.line != -1) {
        final paint = Paint();
        switch (marker.type) {
          case DiffType.added:
            paint.color = Colors.green.withValues(alpha: 0.12);
            break;
          case DiffType.removed:
            paint.color = Colors.red.withValues(alpha: 0.12);
            break;
          case DiffType.modified:
            paint.color = Colors.orange.withValues(alpha: 0.12);
            break;
        }

        final rect = Rect.fromLTWH(
          0,
          paragraph.offset.dy,
          size.width,
          paragraph.paragraph.height,
        );
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DiffBackgroundPainter oldDelegate) {
    return oldDelegate.markers != markers || oldDelegate.notifier != notifier;
  }
}

// ─── Стабильный виджет редактора ─────────────────────────────────────────────
// Каждый открытый файл имеет СВОЙ постоянный _StableEditorWidget.
// IndexedStack в EditorPage держит все экземпляры живыми одновременно —
// CodeEditor НИКОГДА не уничтожается и не пересоздаётся при смене вкладки.
// Это устраняет stale _CodeEditableState listener crash из re_editor.

class _StableEditorWidget extends ConsumerStatefulWidget {
  final EditorFile file;
  final SettingsState settings;

  const _StableEditorWidget({
    super.key,
    required this.file,
    required this.settings,
  });

  @override
  ConsumerState<_StableEditorWidget> createState() => _StableEditorWidgetState();
}

class _StableEditorWidgetState extends ConsumerState<_StableEditorWidget> {
  late List<CodeDiagnostic> _diagnostics;
  late List<DiffMarker> _diffMarkers;

  String _getFontFamily(String fontName) {
    if (fontName == 'Monospace') return 'monospace';
    try {
      return GoogleFonts.getFont(fontName).fontFamily ?? 'monospace';
    } catch (_) {
      return 'monospace';
    }
  }

  // Cached static resources — created once, never rebuilt
  static final CodeHighlightTheme _highlightTheme = CodeHighlightTheme(
    languages: {
      'dart': CodeHighlightThemeMode(mode: langDart),
      'json': CodeHighlightThemeMode(mode: langJson),
      'html': CodeHighlightThemeMode(mode: langXml),
      'xml': CodeHighlightThemeMode(mode: langXml),
      'js': CodeHighlightThemeMode(mode: langJavascript),
      'javascript': CodeHighlightThemeMode(mode: langJavascript),
      'yaml': CodeHighlightThemeMode(mode: langYaml),
      'markdown': CodeHighlightThemeMode(mode: langMarkdown),
      'py': CodeHighlightThemeMode(mode: langPython),
      'python': CodeHighlightThemeMode(mode: langPython),
      'cpp': CodeHighlightThemeMode(mode: langCpp),
      'java': CodeHighlightThemeMode(mode: langJava),
      'php': CodeHighlightThemeMode(mode: langPhp),
    },
    theme: atomOneDarkTheme,
  );

  @override
  void initState() {
    super.initState();
    _diagnostics = widget.file.diagnostics;
    _diffMarkers = widget.file.diffMarkers;
  }

  @override
  void didUpdateWidget(_StableEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Обновляем только диагностику и маркеры — не пересоздаём CodeEditor
    if (widget.file.diagnostics != oldWidget.file.diagnostics ||
        widget.file.diffMarkers != oldWidget.file.diffMarkers) {
      setState(() {
        _diagnostics = widget.file.diagnostics;
        _diffMarkers = widget.file.diffMarkers;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes in the AI autocomplete service, when suggestion is loaded, trigger editor refresh
    ref.listen<AiAutocompleteState>(aiAutocompleteServiceProvider, (previous, current) {
      if (!current.isLoading && current.suggestion != null && current.suggestion!.isNotEmpty) {
        if (current.filePath == widget.file.path) {
          widget.file.controller.value = widget.file.controller.value;
        }
      }
    });
    ref.listen<LspAutocompleteState>(lspAutocompleteServiceProvider, (previous, current) {
      if (!current.isLoading && current.items.isNotEmpty) {
        if (current.filePath == widget.file.path) {
          widget.file.controller.value = widget.file.controller.value;
        }
      }
    });
    final settings = widget.settings;
    final file = widget.file;

    final aiState = ref.watch(aiProvider);
    final List<AIAction> pendingActions = aiState.proposedActions.where((a) => a.path == file.path && (a.type == 'edit' || a.type == 'create')).toList();
    final hasPendingAction = pendingActions.isNotEmpty;

    if (file.isImage) {
      final sizeInBytes = File(file.path).existsSync() ? File(file.path).lengthSync() : 0;
      final sizeKb = (sizeInBytes / 1024).toStringAsFixed(2);
      
      return Container(
        color: const Color(0xFF0F111A), // Sleek deep dark background
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161925),
                        border: Border.all(color: Colors.white10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: InteractiveViewer(
                        maxScale: 5.0,
                        child: Center(
                          child: Hero(
                            tag: file.path,
                            child: Image.file(
                              File(file.path),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(LucideIcons.image_off, color: Colors.redAccent, size: 48),
                                      const SizedBox(height: 16),
                                      Text(
                                        AppLocalizations.of(context)!.imageLoadError,
                                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Info panel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF161925),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          file.path,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      '$sizeKb KB',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget editorWidget = CodeEditor(
      controller: file.controller,
      wordWrap: settings.wordWrap,
      toolbarController: MobileSelectionToolbarController(
        builder: ({
          required BuildContext context,
          required TextSelectionToolbarAnchors anchors,
          required CodeLineEditingController controller,
          required VoidCallback onDismiss,
          required VoidCallback onRefresh,
        }) {
          final List<ContextMenuButtonItem> buttonItems = [];
          final l10n = AppLocalizations.of(context)!;
          
          if (!controller.selection.isCollapsed) {
            buttonItems.add(
              ContextMenuButtonItem(
                label: l10n.cut,
                onPressed: () {
                  controller.cut();
                  onDismiss();
                },
              ),
            );
            buttonItems.add(
              ContextMenuButtonItem(
                label: l10n.copy,
                onPressed: () {
                  controller.copy();
                  onDismiss();
                },
              ),
            );
          }
          
          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.paste,
              onPressed: () {
                controller.paste();
                onDismiss();
              },
            ),
          );
          
          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.selectAll,
              onPressed: () {
                controller.selectAll();
                onRefresh();
              },
            ),
          );

          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.goToDefinition,
              onPressed: () {
                onDismiss();
                ref.read(editorProvider.notifier).goToDefinition();
              },
            ),
          );

          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.info,
              onPressed: () async {
                onDismiss();
                final hover = await ref.read(editorProvider.notifier).getHover();
                if (hover != null && context.mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E2230),
                      title: Text(l10n.documentation, style: const TextStyle(color: Colors.white, fontSize: 16)),
                      content: SingleChildScrollView(
                        child: Text(
                          hover.contents,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l10n.ok),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          );

          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.usages,
              onPressed: () async {
                onDismiss();
                final locations = await ref.read(editorProvider.notifier).getReferences();
                if (locations.isNotEmpty && context.mounted) {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF1E2230),
                    builder: (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(l10n.usages, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: locations.length,
                            itemBuilder: (context, index) {
                              final loc = locations[index];
                              final fileName = p.basename(Uri.parse(loc.uri).toFilePath());
                              return ListTile(
                                title: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                subtitle: Text('${l10n.line} ${loc.range.start.line + 1}, ${l10n.column} ${loc.range.start.character + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                onTap: () {
                                  Navigator.pop(context);
                                  ref.read(editorProvider.notifier).openFile(Uri.parse(loc.uri).toFilePath(), line: loc.range.start.line, column: loc.range.start.character);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          );

          buttonItems.add(
            ContextMenuButtonItem(
              label: l10n.rename,
              onPressed: () async {
                onDismiss();
                final controller = TextEditingController();
                final newName = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E2230),
                    title: Text(l10n.rename, style: const TextStyle(color: Colors.white)),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.rename,
                        hintStyle: const TextStyle(color: Colors.white38),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                      TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.ok)),
                    ],
                  ),
                );
                if (newName != null && newName.isNotEmpty) {
                  ref.read(editorProvider.notifier).rename(newName);
                }
              },
            ),
          );

          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: anchors,
            buttonItems: buttonItems,
          );
        },
      ),
      indicatorBuilder: (context, controller, chunkController, notifier) {
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: DiffBackgroundPainter(
                  notifier: notifier,
                  markers: _diffMarkers,
                ),
                size: Size.zero,
              ),
            ),
            Row(
              children: [
                if (settings.lineNumbers) ...[
                  DefaultCodeLineNumber(controller: controller, notifier: notifier),
                  const SizedBox(width: 8),
                ],
                DefaultCodeChunkIndicator(width: 20, controller: chunkController, notifier: notifier),
              ],
            ),
            Positioned.fill(
              child: DiagnosticIndicator(diagnostics: _diagnostics, notifier: notifier),
            ),
            Positioned(
              left: 0, top: 0, bottom: 0, width: 4,
              child: DiffGutterIndicator(
                controller: controller,
                markers: _diffMarkers,
                notifier: notifier,
              ),
            ),
          ],
        );
      },
      style: CodeEditorStyle(
        fontSize: settings.fontSize,
        fontFamily: _getFontFamily(settings.editorFontFamily),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        codeTheme: _highlightTheme,
      ),
    );

    if (hasPendingAction) {
      final action = pendingActions.first;
      final isRu = Localizations.localeOf(context).languageCode == 'ru';
      
      final hunks = DiffService.calculateHunks(file.originalContent, file.controller.text);
      int additions = 0;
      int deletions = 0;
      for (final hunk in hunks) {
        if (hunk.type == DiffType.added) {
          additions += (hunk.endLine - hunk.startLine + 1);
        } else if (hunk.type == DiffType.removed) {
          deletions += 1;
        } else if (hunk.type == DiffType.modified) {
          additions += (hunk.endLine - hunk.startLine + 1);
          deletions += (hunk.endLine - hunk.startLine + 1);
        }
      }

      editorWidget = Stack(
        children: [
          Positioned.fill(child: editorWidget),
          Positioned(
            right: 16,
            bottom: 16,
            width: 290,
            child: GlassContainer(
              blur: 24,
              opacity: 0.18,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25), width: 0.8),
              child: Container(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card Header
                    Row(
                      children: [
                        const Icon(LucideIcons.sparkles, color: Colors.purpleAccent, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isRu ? 'Ожидающий Diff' : 'Pending Diff',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (additions > 0)
                          Text(
                            '+$additions',
                            style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        if (additions > 0 && deletions > 0) const SizedBox(width: 4),
                        if (deletions > 0)
                          Text(
                            '-$deletions',
                            style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(height: 0.5, color: Colors.white10),
                    const SizedBox(height: 6),
                    
                    // Contiguous hunks list
                    if (hunks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            isRu ? 'Нет изменений' : 'No changes',
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: SingleChildScrollView(
                          child: Column(
                            children: List.generate(hunks.length, (hIdx) {
                              final hunk = hunks[hIdx];
                              String typeLabel = hunk.type == DiffType.added
                                  ? (isRu ? 'добавлено' : 'added')
                                  : hunk.type == DiffType.removed
                                      ? (isRu ? 'удалено' : 'removed')
                                      : (isRu ? 'изменено' : 'modified');
                              Color typeColor = hunk.type == DiffType.added
                                  ? Colors.greenAccent
                                  : hunk.type == DiffType.removed
                                      ? Colors.redAccent
                                      : Colors.amberAccent;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Row(
                                  children: [
                                    Icon(LucideIcons.circle, size: 6, color: typeColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'L${hunk.startLine + 1}-${hunk.endLine + 1} $typeLabel',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Individual Hunk Keep Button
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        ref.read(editorProvider.notifier).applyHunkAction(file.path, hIdx, true);
                                      },
                                      child: Text(
                                        isRu ? 'Принять' : 'Keep',
                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    // Individual Hunk Reject Button
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        ref.read(editorProvider.notifier).applyHunkAction(file.path, hIdx, false);
                                      },
                                      child: Text(
                                        isRu ? 'Отмена' : 'Reject',
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 8),
                    Container(height: 0.5, color: Colors.white10),
                    const SizedBox(height: 8),
                    
                    // Card Level Keep all / Reject all Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent.withValues(alpha: 0.12),
                              foregroundColor: Colors.greenAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3)),
                              ),
                            ),
                            onPressed: () {
                              ref.read(editorProvider.notifier).acceptProposedChanges(file.path, action);
                            },
                            child: Text(
                              isRu ? 'Принять все' : 'Keep all',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
                              foregroundColor: Colors.redAccent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                              ),
                            ),
                            onPressed: () {
                              ref.read(editorProvider.notifier).revertProposedChanges(file.path, action);
                            },
                            child: Text(
                              isRu ? 'Отклонить все' : 'Reject all',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return editorWidget;
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _ActionIconButton({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 15, color: Colors.white70),
      onPressed: onTap,
      tooltip: tooltip,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      constraints: const BoxConstraints(),
    );
  }
}

class _DrawerActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _DrawerActionIcon({
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

class _QuantumAutocompleteView extends StatelessWidget implements PreferredSizeWidget {
  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  const _QuantumAutocompleteView({
    required this.notifier,
    required this.onSelected,
  });

  @override
  Size get preferredSize => const Size(300, 250);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, child) {
        if (value.prompts.isEmpty) return const SizedBox();
        return GlassContainer(
          blur: 40,
          opacity: 0.2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
          child: Container(
            width: 300,
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: value.prompts.length,
              itemBuilder: (context, index) {
                final prompt = value.prompts[index];
                final isSelected = value.index == index;
                final isAi = prompt is AiAutocompletePrompt;
                return InkWell(
                  onTap: () => onSelected(value.copyWith(index: index).autocomplete),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? (isAi 
                              ? Colors.deepPurpleAccent.withValues(alpha: 0.25)
                              : Colors.cyanAccent.withValues(alpha: 0.15))
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isAi
                                ? Colors.deepPurpleAccent.withValues(alpha: 0.15)
                                : Colors.cyanAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            isAi ? LucideIcons.sparkles : LucideIcons.code, 
                            size: 14, 
                            color: isAi ? Colors.deepPurpleAccent : Colors.cyanAccent
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            prompt.word,
                            style: TextStyle(
                              color: isSelected ? Colors.white : (isAi ? Colors.deepPurpleAccent : Colors.white70),
                              fontSize: 14,
                              fontWeight: (isSelected || isAi) ? FontWeight.w600 : FontWeight.w400,
                              fontStyle: isAi ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ),
                        if (isAi)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.3), width: 0.5),
                              ),
                              child: const Text(
                                'AI ✨',
                                style: TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (isSelected)
                          const Icon(LucideIcons.chevron_right, size: 14, color: Colors.white38),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

