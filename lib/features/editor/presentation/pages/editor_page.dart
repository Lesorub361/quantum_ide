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
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_tree_node.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/ui_customizer_modal.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:flutter/services.dart';
import 'package:quantum_ide/features/editor/presentation/handlers/autocomplete_handler.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/keyboard_accessory_bar.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/quick_switcher_dialog.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/core/services/environment_service.dart';
import 'package:quantum_ide/shared/widgets/status_bar.dart';
import 'package:quantum_ide/shared/widgets/breadcrumbs.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_panel_content.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_drawer.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/editor_app_bar.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/code_find_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/stable_editor_widget.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/markdown_preview_widget.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:quantum_ide/shared/providers/drawer_provider.dart';
import 'package:quantum_ide/core/utils/adaptive_dialog_helper.dart';
import 'package:quantum_ide/core/services/project_requirements_service.dart';
import 'package:quantum_ide/shared/widgets/project_requirements_dialog.dart';
import 'package:quantum_ide/core/services/app_update_service.dart';
import 'package:quantum_ide/core/services/project_sync_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/project_sync_panel.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/quantum_ai_agent_panel.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:quantum_ide/core/services/build_resource_optimizer.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/build_target_dialog.dart';

// ─── Вспомогательные функции для диалогов и меню ───────────────────────────

void showSortMenu(BuildContext context, WidgetRef ref) async {
  final RenderBox button = context.findRenderObject() as RenderBox;
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  final result = await showMenu<FileSortMode>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(
        value: FileSortMode.name,
        child: Text(AppLocalizations.of(context)!.sortByName),
      ),
      PopupMenuItem(
        value: FileSortMode.size,
        child: Text(AppLocalizations.of(context)!.sortBySize),
      ),
      PopupMenuItem(
        value: FileSortMode.date,
        child: Text(AppLocalizations.of(context)!.sortByDate),
      ),
    ],
  );
  if (result != null) {
    ref.read(fileSortModeProvider.notifier).state = result;
  }
}

Future<void> showCreateDialog(
  BuildContext context,
  WidgetRef ref,
  String basePath,
  bool isDir,
) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        isDir
            ? AppLocalizations.of(context)!.newFolder
            : AppLocalizations.of(context)!.newFile,
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: isDir
              ? AppLocalizations.of(context)!.nameFolderHint
              : AppLocalizations.of(context)!.nameFileHint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(AppLocalizations.of(context)!.create),
        ),
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

void showEnvironmentBottomSheet(BuildContext context, WidgetRef ref) {
  AdaptiveDialogHelper.showAdaptiveSheet(
    context: context,
    backgroundColor: const Color(0xff18181b),
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
                      Text(
                        AppLocalizations.of(context)!.systemEnv,
                        style: const TextStyle(
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blueAccent,
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(
                                LucideIcons.refresh_cw,
                                size: 18,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () => ref
                                  .read(environmentProvider.notifier)
                                  .checkEnvironment(),
                            ),
                          IconButton(
                            icon: const Icon(
                              LucideIcons.wrench,
                              size: 18,
                              color: Colors.orangeAccent,
                            ),
                            tooltip: AppLocalizations.of(
                              context,
                            )!.fixEnvironmentArm64,
                            onPressed: () => ref
                                .read(environmentProvider.notifier)
                                .fixEnvironment(),
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
                        children: envState.tools
                            .map(
                              (tool) => Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: tool.isInstalled
                                            ? Colors.green.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.red.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        tool.isInstalled
                                            ? LucideIcons.circle_check
                                            : LucideIcons.circle_alert,
                                        size: 16,
                                        color: tool.isInstalled
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tool.name,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (tool.isInstalled &&
                                              tool.version != null)
                                            Text(
                                              tool.version!,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          if (tool.error != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Text(
                                                tool.error!,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: tool.isInstalled
                                                      ? Colors.orangeAccent
                                                      : Colors.redAccent,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
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

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isDragging = false;
  bool _isSplitMode = false;
  int _splitTabIndex = -1;
  bool _isZenMode = false;

  double _leftSidebarWidth = 280.0;
  bool _isResizingLeft = false;

  double _rightAiPanelWidth = 380.0;
  bool _isResizingRight = false;
  bool _isAiDockExpanded = false;
  double _mobileAiDrawerFraction = 0.88;

  void _toggleAiAgent(BuildContext context, WidgetRef ref, bool canDockSide) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (canDockSide) {
      ref.read(rightAiPanelOpenProvider.notifier).update((v) => !v);
    } else {
      if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
        _scaffoldKey.currentState?.closeEndDrawer();
      } else {
        _scaffoldKey.currentState?.openEndDrawer();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appUpdateServiceProvider.notifier).checkForUpdates(silent: true);
      final currentWs = ref.read(workspaceProvider).currentPath;
      if (currentWs != null) {
        _checkProjectRequirements(currentWs);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _checkProjectRequirements(String workspacePath) {
    Future.microtask(() async {
      if (!mounted) return;
      final reqService = ref.read(projectRequirementsServiceProvider);
      final result = await reqService.checkProjectRequirements(workspacePath);
      if (result != null && result.hasMissing && mounted) {
        await ProjectRequirementsDialog.show(context, result);
      }
    });
  }

  /// Вызывается один раз при смене workspace — не на каждый build()
  void _onWorkspaceChanged(String workspacePath) {
    // Раскрываем корневую папку
    final expandedSet = ref.read(expandedFoldersProvider);
    if (expandedSet.isEmpty) {
      ref.read(expandedFoldersProvider.notifier).setExpanded({workspacePath});
    }

    // Синхронизируем терминальную вкладку с рабочей директорией проекта
    final runtime = ref.read(runtimeServiceProvider);
    final guestPath = PathMapper.mapToGuest(
      workspacePath,
      runtime.appDirectory,
    );
    final sessions = ref.read(terminalTabsProvider);
    final sessionIndex = sessions.indexWhere((s) => s.workingDir == guestPath);
    if (sessionIndex != -1) {
      ref.read(terminalTabsProvider.notifier).currentIndex = sessionIndex;
    }

    // Событийный запрос Git статуса при смене рабочего пространства
    ref.read(gitProvider.notifier).refreshStatus();

    // Автопроверка необходимых пакетов для проекта
    _checkProjectRequirements(workspacePath);

    // Показываем уведомление об автонастройке .gitignore
    if (mounted) {
      final isRu = Localizations.localeOf(context).languageCode == 'ru';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRu
                ? 'Проект открыт. Папка .quantum/ автоматически исключена из Git.'
                : 'Project opened. Folder .quantum/ is automatically ignored in Git.',
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final openFiles = ref.watch(editorProvider.select((s) => s.openFiles));
    final openFilesCount = openFiles.length;
    final rawActiveIndex = ref.watch(
      editorProvider.select((s) => s.activeTabIndex),
    );

    int safeActiveIndex = rawActiveIndex;
    if (safeActiveIndex >= openFilesCount) {
      safeActiveIndex = openFilesCount > 0 ? openFilesCount - 1 : 0;
    }
    if (safeActiveIndex < 0) safeActiveIndex = 0;

    final activeFile = (openFilesCount > 0 && safeActiveIndex < openFilesCount)
        ? openFiles[safeActiveIndex]
        : null;

    final isMarkdownFile =
        activeFile != null &&
        (activeFile.path.toLowerCase().endsWith('.md') ||
            activeFile.path.toLowerCase().endsWith('.markdown'));

    final settings = ref.watch(settingsProvider);
    final workspacePath = ref.watch(workspaceProvider).currentPath;
    final panelState = ref.watch(panelProvider);
    final panelNotifier = ref.read(panelProvider.notifier);

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;
    final l10n = AppLocalizations.of(context)!;

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

    final allProjects = ref.watch(projectServiceProvider);
    final currentProjectIndex = allProjects.indexWhere(
      (p) => p.path == workspacePath,
    );
    final currentProject = currentProjectIndex != -1
        ? allProjects[currentProjectIndex]
        : null;

    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardInset > 0;

    final mainBody = LayoutBuilder(
      builder: (context, constraints) {
        final double availableHeight = (constraints.maxHeight - keyboardInset)
            .clamp(120.0, constraints.maxHeight);
        final isMobileTerminalWithKeyboard =
            (Platform.isAndroid || Platform.isIOS || !isDesktop) &&
            isKeyboardOpen &&
            panelState.selectedTab == PanelTab.terminal;

        // Panel height: drag range 90..availableHeight (above software keyboard)
        double activePanelHeight = 0.0;
        if (panelState.isOpened) {
          if (panelState.isMaximized || isMobileTerminalWithKeyboard) {
            activePanelHeight = availableHeight;
          } else {
            activePanelHeight = panelState.panelHeight.clamp(
              90.0,
              availableHeight,
            );
          }
        }

        return Stack(
          children: [
            // ── Редактор (динамически уменьшает высоту при открытии панели) ────
            AnimatedPositioned(
              duration: (_isDragging || isKeyboardOpen)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: 0,
              left: 0,
              right: 0,
              bottom: activePanelHeight + keyboardInset,
              child: activeFile == null
                  ? _buildDashboard(context, ref, isDesktop, workspacePath)
                  : Column(
                      children: [
                        if (!_isZenMode)
                          Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0F14),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  width: 0.8,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Breadcrumbs(
                                    path: activeFile.path,
                                    workspacePath: workspacePath,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.command,
                                    size: 13.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => QuickSwitcherDialog.show(
                                    context,
                                    initialMode: SwitcherMode.commands,
                                  ),
                                  tooltip: 'Палитра команд (Command Palette)',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.wand_sparkles,
                                    size: 13.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => ref
                                      .read(editorProvider.notifier)
                                      .formatActiveFile(),
                                  tooltip: 'Форматировать код',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.search,
                                    size: 13.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => QuickSwitcherDialog.show(
                                    context,
                                    initialMode: SwitcherMode.files,
                                  ),
                                  tooltip: AppLocalizations.of(
                                    context,
                                  )!.quickSearch,
                                ),
                                IconButton(
                                  icon: const Icon(
                                    LucideIcons.maximize_2,
                                    size: 13.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _toggleZenMode(ref),
                                  tooltip: 'Режим фокуса (Zen Mode)',
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: DropTarget(
                            onDragDone: (detail) async {
                              for (final file in detail.files) {
                                if (workspacePath != null) {
                                  final targetPath = p.join(
                                    workspacePath,
                                    p.basename(file.path),
                                  );
                                  final fileEntity = File(file.path);
                                  if (await fileEntity.exists()) {
                                    await fileEntity.copy(targetPath);
                                    ref
                                        .read(editorProvider.notifier)
                                        .openFile(targetPath);
                                  }
                                } else {
                                  ref
                                      .read(editorProvider.notifier)
                                      .openFile(file.path);
                                }
                              }
                            },
                            child: CallbackShortcuts(
                              bindings: {
                                // Save file (Ctrl+S / Cmd+S)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyS,
                                  control: true,
                                ): () => ref
                                    .read(editorProvider.notifier)
                                    .saveFile(safeActiveIndex),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyS,
                                  meta: true,
                                ): () => ref
                                    .read(editorProvider.notifier)
                                    .saveFile(safeActiveIndex),
                                // Quick open files (Ctrl+P / Cmd+P)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyP,
                                  control: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.files,
                                ),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyP,
                                  meta: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.files,
                                ),
                                // Command palette (Ctrl+Shift+P / Cmd+Shift+P)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyP,
                                  control: true,
                                  shift: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.commands,
                                ),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyP,
                                  meta: true,
                                  shift: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.commands,
                                ),
                                // Search files (Ctrl+Shift+F / Cmd+Shift+F)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyF,
                                  control: true,
                                  shift: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.files,
                                ),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyF,
                                  meta: true,
                                  shift: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.files,
                                ),
                                // Toggle Sidebar (Ctrl+B / Cmd+B)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyB,
                                  control: true,
                                ): () {
                                  if (isDesktop) {
                                    ref
                                        .read(leftPanelOpenProvider.notifier)
                                        .update((v) => !v);
                                  } else {
                                    if (_scaffoldKey
                                            .currentState
                                            ?.isDrawerOpen ??
                                        false) {
                                      _scaffoldKey.currentState?.closeDrawer();
                                    } else {
                                      _scaffoldKey.currentState?.openDrawer();
                                    }
                                  }
                                },
                                const SingleActivator(
                                  LogicalKeyboardKey.keyB,
                                  meta: true,
                                ): () {
                                  if (isDesktop) {
                                    ref
                                        .read(leftPanelOpenProvider.notifier)
                                        .update((v) => !v);
                                  } else {
                                    if (_scaffoldKey
                                            .currentState
                                            ?.isDrawerOpen ??
                                        false) {
                                      _scaffoldKey.currentState?.closeDrawer();
                                    } else {
                                      _scaffoldKey.currentState?.openDrawer();
                                    }
                                  }
                                },
                                // Toggle Terminal Panel (Ctrl+` / Cmd+`)
                                const SingleActivator(
                                  LogicalKeyboardKey.backquote,
                                  control: true,
                                ): () =>
                                    panelNotifier.toggle(),
                                const SingleActivator(
                                  LogicalKeyboardKey.backquote,
                                  meta: true,
                                ): () =>
                                    panelNotifier.toggle(),
                                // Quick symbols (Ctrl+T / Cmd+T)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyT,
                                  control: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.symbols,
                                ),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyT,
                                  meta: true,
                                ): () => QuickSwitcherDialog.show(
                                  context,
                                  initialMode: SwitcherMode.symbols,
                                ),
                                // Close active tab (Ctrl+W / Cmd+W)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyW,
                                  control: true,
                                ): () => ref
                                    .read(editorProvider.notifier)
                                    .closeTab(safeActiveIndex),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyW,
                                  meta: true,
                                ): () => ref
                                    .read(editorProvider.notifier)
                                    .closeTab(safeActiveIndex),
                                // Find in file (Ctrl+F / Cmd+F)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyF,
                                  control: true,
                                ): () =>
                                    _showFindPanel(context, ref),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyF,
                                  meta: true,
                                ): () =>
                                    _showFindPanel(context, ref),
                                // Replace in file (Ctrl+H / Cmd+H)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyH,
                                  control: true,
                                ): () =>
                                    _showFindPanel(context, ref, replace: true),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyH,
                                  meta: true,
                                ): () =>
                                    _showFindPanel(context, ref, replace: true),
                                // Duplicate line (Ctrl+D / Cmd+D)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyD,
                                  control: true,
                                ): () =>
                                    _duplicateLine(ref),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyD,
                                  meta: true,
                                ): () =>
                                    _duplicateLine(ref),
                                // Zen mode (Ctrl+K / Cmd+K)
                                const SingleActivator(
                                  LogicalKeyboardKey.keyK,
                                  control: true,
                                ): () =>
                                    _toggleZenMode(ref),
                                const SingleActivator(
                                  LogicalKeyboardKey.keyK,
                                  meta: true,
                                ): () =>
                                    _toggleZenMode(ref),
                                // Split editor (Ctrl+\ / Cmd+\)
                                const SingleActivator(
                                  LogicalKeyboardKey.backslash,
                                  control: true,
                                ): () =>
                                    _toggleSplitMode(ref),
                                const SingleActivator(
                                  LogicalKeyboardKey.backslash,
                                  meta: true,
                                ): () =>
                                    _toggleSplitMode(ref),
                                // Problems tab
                                const SingleActivator(
                                  LogicalKeyboardKey.bracketLeft,
                                  control: true,
                                  shift: true,
                                ): () =>
                                    panelNotifier.selectTab(PanelTab.problems),
                                const SingleActivator(
                                  LogicalKeyboardKey.bracketLeft,
                                  meta: true,
                                  shift: true,
                                ): () =>
                                    panelNotifier.selectTab(PanelTab.problems),
                                // Run project (F5)
                                const SingleActivator(
                                  LogicalKeyboardKey.f5,
                                ): () {
                                  if (currentProject != null) {
                                    ref
                                        .read(projectServiceProvider.notifier)
                                        .runProject(currentProject);
                                    panelNotifier.selectTab(PanelTab.terminal);
                                    panelNotifier.openPanel();
                                  }
                                },
                              },
                              child: _isSplitMode
                                  ? _buildSplitEditor(ref, settings, activeFile)
                                  : _buildSingleEditor(
                                      ref,
                                      settings,
                                      activeFile,
                                    ),
                            ),
                          ),
                        ),
                        if (Platform.isAndroid || Platform.isIOS || !isDesktop)
                          KeyboardAccessoryBar(
                            controller: activeFile.controller,
                          ),
                      ],
                    ),
            ),

            // ── Панель (overlay, выезжает снизу поверх редактора над клавиатурой) ────
            AnimatedPositioned(
              duration: (_isDragging || isKeyboardOpen)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: keyboardInset,
              height: activePanelHeight,
              child: activePanelHeight > 0
                  ? _buildBottomPanel(
                      context,
                      ref,
                      panelState,
                      panelNotifier,
                      availableHeight,
                    )
                  : const SizedBox.shrink(),
            ),

            // ── Плавающий баннер синхронизации проекта (Синхронизация проекта...) ────
            const Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: ProjectSyncFloatingBanner(),
            ),

            // ── Панель синхронизации проекта снизу (Вывод / Проблемы / Логи) ────
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ProjectSyncOutputPanel(),
            ),

            // ── Кнопка выхода из Zen Mode (плавающий неоновый бейдж) ────
            if (_isZenMode)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 12,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _toggleZenMode(ref),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141824).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.45),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.minimize_2,
                            size: 13,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Выйти из Zen',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    final canDockSide = screenWidth >= 650;
    final isRightAiOpen = ref.watch(rightAiPanelOpenProvider);

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

        if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
          _scaffoldKey.currentState?.closeEndDrawer();
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
        drawer: const FileDrawer(),
        endDrawer: canDockSide
            ? null
            : _buildMobileAiDrawer(context, screenWidth),
        appBar: _isZenMode
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(72),
                child: GlassContainer(
                  blur: 30,
                  opacity: 0.1,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Top Row: Leading, File Name, Clean Monochrome Actions
                        Expanded(
                          child: Row(
                            children: [
                              const SizedBox(width: 8),
                              ActionIconButton(
                                icon: LucideIcons.panel_left,
                                color:
                                    (screenWidth >= 1024 &&
                                        ref.watch(leftPanelOpenProvider))
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFF94A3B8),
                                tooltip: AppLocalizations.of(
                                  context,
                                )!.openExplorer,
                                onTap: () {
                                  if (screenWidth >= 1024) {
                                    final isOpen = ref.read(
                                      leftPanelOpenProvider,
                                    );
                                    final currentTab = ref.read(
                                      drawerTabProvider,
                                    );
                                    if (!isOpen) {
                                      ref
                                              .read(drawerTabProvider.notifier)
                                              .state =
                                          0;
                                      ref
                                              .read(
                                                leftPanelOpenProvider.notifier,
                                              )
                                              .state =
                                          true;
                                    } else if (currentTab != 0) {
                                      ref
                                              .read(drawerTabProvider.notifier)
                                              .state =
                                          0;
                                    } else {
                                      ref
                                              .read(
                                                leftPanelOpenProvider.notifier,
                                              )
                                              .state =
                                          false;
                                    }
                                  } else {
                                    _scaffoldKey.currentState?.openDrawer();
                                  }
                                },
                              ),
                              const SizedBox(width: 6),
                              const Expanded(child: EditorAppBarTitle()),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildQuickUpdatePill(ref),
                                  // Primary Run Button — Emerald Accent
                                  ActionIconButton(
                                    icon: LucideIcons.play,
                                    color: const Color(0xFF10B981),
                                    backgroundColor: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.14),
                                    borderColor: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.32),
                                    tooltip: 'Запустить проект (F5)',
                                    onTap: () {
                                      if (currentProject != null) {
                                        ref
                                            .read(
                                              projectServiceProvider.notifier,
                                            )
                                            .runProject(currentProject);
                                        panelNotifier.selectTab(
                                          PanelTab.terminal,
                                        );
                                        panelNotifier.openPanel();
                                      } else {
                                        panelNotifier.selectTab(
                                          PanelTab.terminal,
                                        );
                                        panelNotifier.openPanel();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  // Dedicated Build Menu Button (APK / AAB) — Amber Accent
                                  PopupMenuButton<String>(
                                    tooltip: 'Сборка проекта (APK / AAB)',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    color: const Color(0xFF161922),
                                    elevation: 12,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    icon: Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFF59E0B,
                                        ).withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFF59E0B,
                                          ).withValues(alpha: 0.32),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Icon(
                                        LucideIcons.hammer,
                                        size: 15,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                    itemBuilder: (context) => [
                                      _buildBuildMenuItem(
                                        'open_dialog',
                                        LucideIcons.sliders_horizontal,
                                        'Настройка и запуск сборки...',
                                        'Выбор архитектуры, RAM и воркеров CPU',
                                        const Color(0xFF10B981),
                                      ),
                                      const PopupMenuDivider(),
                                      _buildBuildMenuItem(
                                        'build_arm64',
                                        LucideIcons.zap,
                                        'APK ARM64 (64-бит) ⚡',
                                        'В 4-5 раз быстрее · Для планшета/телефона',
                                        Colors.amber,
                                      ),
                                      _buildBuildMenuItem(
                                        'build_arm32',
                                        LucideIcons.smartphone,
                                        'APK ARMv7 (32-бит)',
                                        'Для старых смартфонов (32-bit ARM)',
                                        Colors.blueAccent,
                                      ),
                                      _buildBuildMenuItem(
                                        'build_x64',
                                        LucideIcons.monitor,
                                        'APK x86_64',
                                        'Для эмуляторов Android и ПК',
                                        Colors.cyanAccent,
                                      ),
                                      _buildBuildMenuItem(
                                        'build_split',
                                        LucideIcons.boxes,
                                        'Split APKs (все архитектуры)',
                                        'Отдельные APK: arm64, armv7, x86_64',
                                        Colors.orangeAccent,
                                      ),
                                      _buildBuildMenuItem(
                                        'build_aab',
                                        LucideIcons.rocket,
                                        'AppBundle (AAB)',
                                        'Бандл для публикации в Google Play Store',
                                        Colors.purpleAccent,
                                      ),
                                      _buildBuildMenuItem(
                                        'build_debug',
                                        LucideIcons.bug,
                                        'Debug APK (ARM64)',
                                        'Быстрая отладочная сборка с логами',
                                        Colors.yellow,
                                      ),
                                    ],
                                    onSelected: (action) {
                                      if (action == 'open_dialog') {
                                        _openBuildTargetDialog(
                                          context,
                                          ref,
                                          panelNotifier,
                                        );
                                      } else {
                                        _triggerProjectBuild(
                                          ref,
                                          panelNotifier,
                                          action,
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  ActionIconButton(
                                    icon: LucideIcons.save,
                                    color: const Color(0xFF94A3B8),
                                    tooltip: AppLocalizations.of(
                                      context,
                                    )!.saveTooltip,
                                    onTap: () => ref
                                        .read(editorProvider.notifier)
                                        .saveFile(safeActiveIndex),
                                  ),
                                  if (isMarkdownFile) ...[
                                    const SizedBox(width: 4),
                                    ActionIconButton(
                                      icon: activeFile.isMarkdownPreview
                                          ? LucideIcons.code
                                          : LucideIcons.eye,
                                      color: activeFile.isMarkdownPreview
                                          ? const Color(0xFFA78BFA)
                                          : const Color(0xFF94A3B8),
                                      backgroundColor:
                                          activeFile.isMarkdownPreview
                                          ? const Color(
                                              0xFF8B5CF6,
                                            ).withValues(alpha: 0.15)
                                          : null,
                                      borderColor: activeFile.isMarkdownPreview
                                          ? const Color(
                                              0xFF8B5CF6,
                                            ).withValues(alpha: 0.35)
                                          : null,
                                      tooltip: activeFile.isMarkdownPreview
                                          ? 'Режим редактора (Код)'
                                          : 'Предпросмотр Markdown',
                                      onTap: () {
                                        ref
                                            .read(editorProvider.notifier)
                                            .toggleMarkdownPreview(
                                              activeFile.path,
                                            );
                                      },
                                    ),
                                  ],
                                  if (screenWidth >= 420) ...[
                                    const SizedBox(width: 4),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final changesCount = ref.watch(
                                          gitProvider.select(
                                            (s) =>
                                                (s.status?.stagedFiles.length ??
                                                    0) +
                                                (s
                                                        .status
                                                        ?.modifiedFiles
                                                        .length ??
                                                    0) +
                                                (s
                                                        .status
                                                        ?.untrackedFiles
                                                        .length ??
                                                    0) +
                                                (s
                                                        .status
                                                        ?.conflictedFiles
                                                        .length ??
                                                    0),
                                          ),
                                        );
                                        return ActionIconButton(
                                          icon: LucideIcons.git_branch,
                                          color:
                                              (panelState.isOpened &&
                                                  panelState.selectedTab ==
                                                      PanelTab.git)
                                              ? const Color(0xFFE2E8F0)
                                              : (changesCount > 0
                                                    ? const Color(0xFFF59E0B)
                                                    : const Color(0xFF94A3B8)),
                                          tooltip: changesCount > 0
                                              ? 'Git ($changesCount изм.)'
                                              : 'Git',
                                          onTap: () {
                                            if (panelState.isOpened &&
                                                panelState.selectedTab ==
                                                    PanelTab.git) {
                                              panelNotifier.closePanel();
                                            } else {
                                              panelNotifier.selectTab(
                                                PanelTab.git,
                                              );
                                              panelNotifier.openPanel();
                                            }
                                          },
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    ActionIconButton(
                                      icon: LucideIcons.terminal,
                                      color:
                                          (panelState.isOpened &&
                                              panelState.selectedTab ==
                                                  PanelTab.terminal)
                                          ? const Color(0xFFE2E8F0)
                                          : const Color(0xFF94A3B8),
                                      tooltip: AppLocalizations.of(
                                        context,
                                      )!.terminal,
                                      onTap: () {
                                        if (panelState.isOpened &&
                                            panelState.selectedTab ==
                                                PanelTab.terminal) {
                                          panelNotifier.closePanel();
                                        } else {
                                          panelNotifier.selectTab(
                                            PanelTab.terminal,
                                          );
                                          panelNotifier.openPanel();
                                        }
                                      },
                                    ),
                                  ],
                                  if (screenWidth >= 520) ...[
                                    const SizedBox(width: 4),
                                    ActionIconButton(
                                      icon: LucideIcons.smartphone,
                                      color:
                                          (panelState.selectedTab ==
                                                  PanelTab.deviceMirror &&
                                              panelState.isOpened)
                                          ? const Color(0xFFE2E8F0)
                                          : const Color(0xFF94A3B8),
                                      tooltip:
                                          'Экран телефона и USB (Device Mirroring)',
                                      onTap: () {
                                        if (panelState.isOpened &&
                                            panelState.selectedTab ==
                                                PanelTab.deviceMirror) {
                                          panelNotifier.closePanel();
                                        } else {
                                          panelNotifier.selectTab(
                                            PanelTab.deviceMirror,
                                          );
                                          panelNotifier.openPanel();
                                        }
                                      },
                                    ),
                                  ],
                                  const SizedBox(width: 4),
                                  // Quantum AI Agent Right Dock Toggle Button — Soft Violet Accent
                                  ActionIconButton(
                                    icon: LucideIcons.sparkles,
                                    color: (canDockSide && isRightAiOpen)
                                        ? Colors.white
                                        : const Color(0xFFA78BFA),
                                    backgroundColor:
                                        (canDockSide && isRightAiOpen)
                                        ? const Color(0xFF8B5CF6)
                                        : const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.14),
                                    borderColor: const Color(
                                      0xFF8B5CF6,
                                    ).withValues(alpha: 0.38),
                                    tooltip: 'Боковая панель Quantum AI Агента',
                                    onTap: () => _toggleAiAgent(
                                      context,
                                      ref,
                                      canDockSide,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  PopupMenuButton<String>(
                                    tooltip: 'Ещё действия',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    color: const Color(0xFF161922),
                                    elevation: 12,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    icon: Container(
                                      width: 32,
                                      height: 32,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF141720),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.08,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: const Icon(
                                        LucideIcons.ellipsis_vertical,
                                        size: 15,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'format':
                                          await ref
                                              .read(editorProvider.notifier)
                                              .formatActiveFile();
                                          break;
                                        case 'find':
                                          final finder = ref.read(
                                            activeFindControllerProvider,
                                          );
                                          if (finder != null) {
                                            finder.findMode();
                                            finder.focusOnFindInput();
                                          }
                                          break;
                                        case 'sync':
                                          final currentWs = ref
                                              .read(workspaceProvider)
                                              .currentPath;
                                          if (currentWs != null) {
                                            ref
                                                .read(
                                                  projectSyncProvider.notifier,
                                                )
                                                .startSync(
                                                  currentWs,
                                                  force: true,
                                                );
                                          }
                                          break;
                                        case 'settings':
                                          context.push('/settings');
                                          break;
                                        case 'home':
                                          await ref
                                              .read(workspaceProvider.notifier)
                                              .closeWorkspace();
                                          if (context.mounted) {
                                            context.go('/');
                                          }
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'format',
                                        child: Row(
                                          children: [
                                            Icon(
                                              LucideIcons.code_xml,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Форматировать код',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'find',
                                        child: Row(
                                          children: [
                                            Icon(
                                              LucideIcons.search,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Поиск в файле (Ctrl+F)',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'sync',
                                        child: Row(
                                          children: [
                                            Icon(
                                              LucideIcons.refresh_cw,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Синхронизировать проект',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'settings',
                                        child: Row(
                                          children: [
                                            Icon(
                                              LucideIcons.settings,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Настройки',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuDivider(),
                                      PopupMenuItem(
                                        value: 'home',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              LucideIcons.house,
                                              size: 16,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              l10n.home,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 6),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Tabs Row
                        const EditorTabBar(),
                      ],
                    ),
                  ),
                ),
              ),
        body: _buildWorkspaceLayout(
          mainBody,
          screenWidth: screenWidth,
          leftOpen:
              isDesktop && ref.watch(leftPanelOpenProvider) && !_isZenMode,
          rightAiOpen: canDockSide && isRightAiOpen && !_isZenMode,
        ),
        bottomNavigationBar: _isZenMode ? null : const StatusBar(),
      ),
    );
  }

  /// На смартфонах (< 650px) Quantum AI Агент открывается сбоку справа как растягиваемая боковая панель.
  Widget _buildMobileAiDrawer(BuildContext context, double screenWidth) {
    final drawerWidth = (screenWidth * _mobileAiDrawerFraction).clamp(
      280.0,
      screenWidth,
    );
    return SizedBox(
      width: drawerWidth,
      child: Drawer(
        backgroundColor: const Color(0xFF0D0F14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: SafeArea(
          child: Row(
            children: [
              // Боковой ползунок изменения ширины окна ИИ даже на телефоне
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    final nextWidth = (drawerWidth - details.delta.dx).clamp(
                      280.0,
                      screenWidth,
                    );
                    _mobileAiDrawerFraction = (nextWidth / screenWidth).clamp(
                      0.70,
                      1.0,
                    );
                  });
                },
                child: Container(
                  width: 8,
                  color: const Color(0xFF141720),
                  child: Center(
                    child: Container(
                      width: 2,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: QuantumAiAgentPanel(
                  isExpanded: _mobileAiDrawerFraction > 0.95,
                  onToggleExpand: () {
                    setState(() {
                      _mobileAiDrawerFraction = _mobileAiDrawerFraction > 0.95
                          ? 0.85
                          : 1.0;
                    });
                  },
                  onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(
    BuildContext context,
    WidgetRef ref,
    PanelState panelState,
    PanelNotifier panelNotifier,
    double maxAllowedPanelHeight,
  ) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final isMobileTerminalWithKeyboard =
        (Platform.isAndroid || Platform.isIOS || !isDesktop) &&
        isKeyboardOpen &&
        panelState.selectedTab == PanelTab.terminal;

    final double targetHeight =
        (panelState.isMaximized || isMobileTerminalWithKeyboard)
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
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black54, blurRadius: 10, spreadRadius: 2),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPanelHeader(
              context,
              panelState,
              panelNotifier,
              maxAllowedPanelHeight,
            ),
            Expanded(
              child: panelState.panelHeight > 60
                  ? const TerminalPanelContent(onlyTerminal: false)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceLayout(
    Widget mainContent, {
    required double screenWidth,
    required bool leftOpen,
    required bool rightAiOpen,
  }) {
    // Гарантируем, что центральному редактору всегда остаётся минимум 260px на планшетах и ПК
    final maxLeftWidth = (screenWidth * 0.35).clamp(180.0, 480.0);
    final effectiveLeftWidth = leftOpen
        ? _leftSidebarWidth.clamp(180.0, maxLeftWidth)
        : 0.0;

    final maxRightWidth = (screenWidth - effectiveLeftWidth - 260.0).clamp(
      260.0,
      720.0,
    );
    final effectiveRightWidth = rightAiOpen
        ? (_isAiDockExpanded
              ? maxRightWidth
              : _rightAiPanelWidth.clamp(260.0, maxRightWidth))
        : 0.0;

    return Row(
      children: [
        if (leftOpen) ...[
          SizedBox(
            width: effectiveLeftWidth,
            child: const FileDrawer(isInline: true),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => setState(() => _isResizingLeft = true),
            onExit: (_) {
              if (!_isDragging) setState(() => _isResizingLeft = false);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _isDragging = true),
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _leftSidebarWidth = (_leftSidebarWidth + details.delta.dx)
                      .clamp(180.0, maxLeftWidth);
                });
              },
              onHorizontalDragEnd: (_) => setState(() {
                _isDragging = false;
                _isResizingLeft = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 6,
                decoration: BoxDecoration(
                  color: _isResizingLeft
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
                      : const Color(0xFF0D0F14),
                  border: Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _isResizingLeft
                          ? const Color(0xFFA78BFA)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        Expanded(child: mainContent),
        if (rightAiOpen) ...[
          // Вертикальный разделитель для растягивания/уменьшения окна Quantum AI Агента сбоку
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            onEnter: (_) => setState(() => _isResizingRight = true),
            onExit: (_) {
              if (!_isDragging) setState(() => _isResizingRight = false);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => setState(() => _isDragging = true),
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _isAiDockExpanded = false;
                  _rightAiPanelWidth = (_rightAiPanelWidth - details.delta.dx)
                      .clamp(260.0, maxRightWidth);
                });
              },
              onHorizontalDragEnd: (_) => setState(() {
                _isDragging = false;
                _isResizingRight = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 7,
                decoration: BoxDecoration(
                  color: _isResizingRight
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.28)
                      : const Color(0xFF0D0F14),
                  border: Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.07),
                      width: 0.5,
                    ),
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.07),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _isResizingRight
                          ? const Color(0xFFA78BFA)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: effectiveRightWidth,
            child: QuantumAiAgentPanel(
              isExpanded: _isAiDockExpanded,
              onToggleExpand: () {
                setState(() {
                  _isAiDockExpanded = !_isAiDockExpanded;
                });
              },
              onClose: () {
                ref.read(rightAiPanelOpenProvider.notifier).state = false;
              },
            ),
          ),
        ],
      ],
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
        if (panelState.panelHeight < 75) {
          panelNotifier.closePanel();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12151E),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
          border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag pill
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: Builder(
                        builder: (context) {
                          final isMobile =
                              MediaQuery.of(context).size.width <= 800;
                          final pluginState = ref.watch(
                            quantumPluginServiceProvider,
                          );
                          final termLayout = pluginState.terminalLayout;
                          final disabledTabs =
                              termLayout?.disabledPanelTabs ?? const [];

                          // ИИ Агент вынесен в правую боковую панель, поэтому в нижней панели оставляем только терминальные инструменты
                          List<PanelTab> visibleTabs = PanelTab.values
                              .where((t) => t != PanelTab.aiAgent)
                              .toList();
                          if (termLayout != null &&
                              termLayout.panelTabsOrder.isNotEmpty) {
                            visibleTabs.sort((a, b) {
                              final idxA = termLayout.panelTabsOrder.indexOf(
                                a.name,
                              );
                              final idxB = termLayout.panelTabsOrder.indexOf(
                                b.name,
                              );
                              if (idxA == -1 && idxB == -1) return 0;
                              if (idxA == -1) return 1;
                              if (idxB == -1) return -1;
                              return idxA.compareTo(idxB);
                            });
                          }
                          visibleTabs = visibleTabs
                              .where((t) => !disabledTabs.contains(t.name))
                              .toList();
                          if (visibleTabs.isEmpty) {
                            visibleTabs = [PanelTab.terminal];
                          }

                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: visibleTabs.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final tab = visibleTabs[index];
                              final isSelected = panelState.selectedTab == tab;
                              final tabColor = _getTabColor(tab);

                              return Padding(
                                padding: const EdgeInsets.only(right: 5.0),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      panelNotifier.selectTab(tab);
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 140,
                                      ),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile
                                            ? (isSelected ? 9 : 7)
                                            : 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(
                                                alpha: 0.06,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: isSelected
                                                ? tabColor
                                                : Colors.transparent,
                                            width: 2.0,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getTabIcon(tab),
                                            size: 13,
                                            color: isSelected
                                                ? const Color(0xFFE2E8F0)
                                                : const Color(0xFF64748B),
                                          ),
                                          if (!isMobile || isSelected) ...[
                                            const SizedBox(width: 5),
                                            Text(
                                              _getTabTitle(context, tab),
                                              style: GoogleFonts.inter(
                                                color: isSelected
                                                    ? Colors.white
                                                    : const Color(0xFF94A3B8),
                                                fontSize: 10.5,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                          if (tab == PanelTab.problems ||
                                              tab == PanelTab.git)
                                            Consumer(
                                              builder: (context, ref, _) {
                                                int? count;
                                                if (tab == PanelTab.problems) {
                                                  final ws = ref
                                                      .watch(workspaceProvider)
                                                      .currentPath;
                                                  count = ref.watch(
                                                    editorProvider.select((s) {
                                                      int c = 0;
                                                      s.allDiagnostics.forEach((
                                                        filePath,
                                                        list,
                                                      ) {
                                                        if (ws != null &&
                                                            filePath.startsWith(
                                                              ws,
                                                            )) {
                                                          for (final d
                                                              in list) {
                                                            if (d.severity ==
                                                                    CodeDiagnosticSeverity
                                                                        .error ||
                                                                d.severity ==
                                                                    CodeDiagnosticSeverity
                                                                        .warning) {
                                                              c++;
                                                            }
                                                          }
                                                        }
                                                      });
                                                      return c;
                                                    }),
                                                  );
                                                } else if (tab ==
                                                    PanelTab.git) {
                                                  count = ref.watch(
                                                    gitProvider.select(
                                                      (s) =>
                                                          (s
                                                                  .status
                                                                  ?.stagedFiles
                                                                  .length ??
                                                              0) +
                                                          (s
                                                                  .status
                                                                  ?.modifiedFiles
                                                                  .length ??
                                                              0) +
                                                          (s
                                                                  .status
                                                                  ?.untrackedFiles
                                                                  .length ??
                                                              0) +
                                                          (s
                                                                  .status
                                                                  ?.conflictedFiles
                                                                  .length ??
                                                              0),
                                                    ),
                                                  );
                                                }
                                                if (count == null || count <= 0) {
                                                  return const SizedBox.shrink();
                                                }
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 4.0,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          tab ==
                                                              PanelTab.problems
                                                          ? const Color(
                                                              0xFFEF4444,
                                                            )
                                                          : const Color(
                                                              0xFF475569,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    constraints:
                                                        const BoxConstraints(
                                                          minWidth: 12,
                                                          minHeight: 12,
                                                        ),
                                                    child: Text(
                                                      '$count',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 7.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.sliders_horizontal,
                        size: 13,
                        color: Color(0xFF94A3B8),
                      ),
                      tooltip:
                          Localizations.localeOf(context).languageCode == 'ru'
                          ? 'Настроить кнопки и вкладки'
                          : 'Customize buttons & tabs',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
                      onPressed: () => UiCustomizerModal.show(
                        context,
                        isRu:
                            Localizations.localeOf(context).languageCode ==
                            'ru',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      icon: Icon(
                        panelState.isMaximized
                            ? LucideIcons.minimize_2
                            : LucideIcons.maximize_2,
                        size: 13,
                        color: const Color(0xFF94A3B8),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
                      onPressed: () => panelNotifier.toggleMaximized(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: IconButton(
                      icon: const Icon(
                        LucideIcons.x,
                        size: 13,
                        color: Color(0xFF94A3B8),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 26,
                      ),
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

  Widget _buildQuickUpdatePill(WidgetRef ref) {
    final updateState = ref.watch(appUpdateServiceProvider);
    if (!updateState.hasUpdate && !updateState.isDownloading) {
      return const SizedBox.shrink();
    }

    if (updateState.isDownloading) {
      final pct = (updateState.downloadProgress * 100).toInt();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFA78BFA),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFFA78BFA),
              ),
            ),
          ],
        ),
      );
    }

    final info = updateState.updateInfo!;
    return InkWell(
      onTap: () {
        ref
            .read(appUpdateServiceProvider.notifier)
            .downloadAndInstallUpdate(info);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.download, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'v${info.versionName}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTabIcon(PanelTab tab) {
    switch (tab) {
      case PanelTab.terminal:
        return LucideIcons.terminal;
      case PanelTab.appLogs:
        return LucideIcons.list;
      case PanelTab.run:
        return LucideIcons.play;
      case PanelTab.buildLogs:
        return LucideIcons.hammer;
      case PanelTab.git:
        return LucideIcons.git_branch;
      case PanelTab.problems:
        return LucideIcons.circle_alert;
      case PanelTab.debug:
        return LucideIcons.bug;
      case PanelTab.deviceMirror:
        return LucideIcons.smartphone;
      case PanelTab.aiAgent:
        return LucideIcons.sparkles;
    }
  }

  Color _getTabColor(PanelTab tab) {
    // Единый строгий акцент вместо радуги («новогодней ёлки»)
    if (tab == PanelTab.problems) return const Color(0xFFEF4444);
    return const Color(0xFF8B5CF6);
  }

  String _getTabTitle(BuildContext context, PanelTab tab) {
    final l10n = AppLocalizations.of(context)!;
    switch (tab) {
      case PanelTab.terminal:
        return l10n.terminal;
      case PanelTab.appLogs:
        return l10n.appLogs;
      case PanelTab.run:
        return l10n.run;
      case PanelTab.buildLogs:
        return l10n.build;
      case PanelTab.git:
        return 'Git';
      case PanelTab.problems:
        return l10n.problems;
      case PanelTab.debug:
        return l10n.debugger;
      case PanelTab.deviceMirror:
        return 'Экран и USB';
      case PanelTab.aiAgent:
        return 'Quantum AI Агент';
    }
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    bool isDesktop,
    String? workspacePath,
  ) {
    final gitChangesCount = ref.watch(
      gitProvider.select(
        (s) =>
            (s.status?.stagedFiles.length ?? 0) +
            (s.status?.modifiedFiles.length ?? 0) +
            (s.status?.untrackedFiles.length ?? 0) +
            (s.status?.conflictedFiles.length ?? 0),
      ),
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome header with glowing title
              Center(
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.purpleAccent, Colors.cyanAccent],
                  ).createShader(bounds),
                  child: Text(
                    'QuantumIDE',
                    style: GoogleFonts.outfit(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Среда разработки нового поколения',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // System Stats Dashboard with Circular Gauges (Isolated Consumer)
              Consumer(
                builder: (context, ref, _) {
                  final stats = ref.watch(systemStatsProvider);
                  return GlassContainer(
                    blur: 0,
                    opacity: 0.05,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'МОНИТОРИНГ СИСТЕМЫ',
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildCircularGauge(
                                label: 'CPU',
                                value:
                                    '${(stats.cpuUsage * 100).toStringAsFixed(1)}%',
                                progress: stats.cpuUsage,
                                color: Colors.cyanAccent,
                              ),
                              Container(
                                width: 1,
                                height: 60,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              _buildCircularGauge(
                                label: 'GPU',
                                value:
                                    '${(stats.gpuUsage * 100).toStringAsFixed(1)}%',
                                progress: stats.gpuUsage,
                                color: Colors.greenAccent,
                              ),
                              Container(
                                width: 1,
                                height: 60,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              _buildCircularGauge(
                                label: 'App RAM',
                                value:
                                    '${stats.appRamFormatted} / ${stats.ramTotalGB.toStringAsFixed(0)} GB',
                                progress: stats.ramUsage,
                                color: Colors.purpleAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Git Status Bento Card
              _buildGitStatusCard(context, gitChangesCount),
              const SizedBox(height: 16),

              // Recent Projects Bento Card
              _buildRecentProjectsCard(context),
              const SizedBox(height: 24),

              // Action grid
              GridView.count(
                crossAxisCount: isDesktop ? 2 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isDesktop ? 2.5 : 3.5,
                children: [
                  _buildDashboardActionCard(
                    icon: LucideIcons.folder_open,
                    iconColor: Colors.blueAccent,
                    title: 'Проводник',
                    subtitle: 'Открыть файлы проекта',
                    onTap: () {
                      if (!isDesktop) {
                        _scaffoldKey.currentState?.openDrawer();
                      }
                    },
                  ),
                  _buildDashboardActionCard(
                    icon: LucideIcons.file_plus,
                    iconColor: Colors.greenAccent,
                    title: 'Создать файл',
                    subtitle: 'Добавить файл в проект',
                    onTap: () {
                      if (workspacePath != null && workspacePath.isNotEmpty) {
                        showCreateDialog(context, ref, workspacePath, false);
                      }
                    },
                  ),
                  _buildDashboardActionCard(
                    icon: LucideIcons.smartphone,
                    iconColor: Colors.cyanAccent,
                    title: 'Зеркалирование экрана (USB)',
                    subtitle: 'Управление телефоном и трансляция',
                    onTap: () {
                      ref
                          .read(panelProvider.notifier)
                          .selectTab(PanelTab.deviceMirror);
                      ref.read(panelProvider.notifier).openPanel();
                    },
                  ),
                  _buildDashboardActionCard(
                    icon: LucideIcons.terminal,
                    iconColor: Colors.orangeAccent,
                    title: 'Терминал',
                    subtitle: 'Командная строка и сборка',
                    onTap: () {
                      ref
                          .read(panelProvider.notifier)
                          .selectTab(PanelTab.terminal);
                      ref.read(panelProvider.notifier).openPanel();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircularGauge({
    required String label,
    required String value,
    required double progress,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.split(' / ').first,
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 9),
        ),
      ],
    );
  }

  Widget _buildRecentProjectsCard(BuildContext context) {
    final theme = Theme.of(context);
    final projects = [
      {'name': 'Orion-OS', 'time': '3 мин назад', 'lang': 'C++'},
      {'name': 'Quantum-Engine', 'time': '2 часа назад', 'lang': 'Dart'},
      {'name': 'Stellar-UI', 'time': 'Вчера', 'lang': 'TypeScript'},
    ];
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'НЕДАВНИЕ ПРОЕКТЫ',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            ...projects.map(
              (p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.folder,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p['name']!,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      p['time']!,
                      style: GoogleFonts.inter(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGitStatusCard(BuildContext context, int gitChangesCount) {
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'GIT СТАТУС',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const Icon(
                  LucideIcons.git_branch,
                  size: 14,
                  color: Colors.purpleAccent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  LucideIcons.git_fork,
                  size: 14,
                  color: Colors.cyanAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  'Ветка: main*',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Изменено файлов: $gitChangesCount',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardActionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GlassContainer(
      blur: 10,
      opacity: 0.04,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white30,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevron_right,
                size: 14,
                color: Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFindPanel(
    BuildContext context,
    WidgetRef ref, {
    bool replace = false,
  }) {
    final finder = ref.read(activeFindControllerProvider);
    if (finder != null) {
      if (replace) {
        finder.replaceMode();
      } else {
        finder.findMode();
      }
      finder.focusOnFindInput();
      return;
    }

    final editorState = ref.read(editorProvider);
    if (editorState.openFiles.isEmpty ||
        editorState.activeTabIndex >= editorState.openFiles.length) {
      return;
    }
    final controller =
        editorState.openFiles[editorState.activeTabIndex].controller;
    final fallbackFinder = CodeFindController(controller);
    if (replace) {
      fallbackFinder.replaceMode();
    } else {
      fallbackFinder.findMode();
    }
  }

  void _duplicateLine(WidgetRef ref) {
    final editorState = ref.read(editorProvider);
    if (editorState.openFiles.isEmpty ||
        editorState.activeTabIndex >= editorState.openFiles.length) {
      return;
    }

    final controller =
        editorState.openFiles[editorState.activeTabIndex].controller;
    final selectedText = controller.selectedText;
    if (selectedText.isNotEmpty) {
      controller.replaceSelection('$selectedText\n$selectedText');
    } else {
      final line = controller.selection.start.index;
      final text = controller.text;
      final lines = text.split('\n');
      if (line >= 0 && line < lines.length) {
        final lineText = lines[line];
        controller.replaceSelection('$lineText\n$lineText');
      }
    }
  }

  void _toggleZenMode(WidgetRef ref) {
    setState(() {
      _isZenMode = !_isZenMode;
    });
    if (_isZenMode) {
      ref.read(panelProvider.notifier).closePanel();
    }
  }

  void _toggleSplitMode(WidgetRef ref) {
    final editorState = ref.read(editorProvider);
    if (editorState.openFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open at least 2 files to use split view'),
          backgroundColor: Color(0xFF1E2230),
        ),
      );
      return;
    }

    setState(() {
      _isSplitMode = !_isSplitMode;
      if (_isSplitMode) {
        _splitTabIndex = editorState.activeTabIndex == 0 ? 1 : 0;
      }
    });
  }

  Widget _buildSingleEditor(
    WidgetRef ref,
    SettingsState settings,
    EditorFile activeFile,
  ) {
    final file = activeFile;

    if (file.isMarkdownPreview) {
      return MarkdownPreviewWidget(
        key: ValueKey('md_preview_${file.path}'),
        content: file.controller.text,
        filePath: file.path,
        onClose: () {
          ref
              .read(editorProvider.notifier)
              .setMarkdownPreview(file.path, false);
        },
      );
    }

    if (file.isDiffView) {
      final workspacePath = ref.read(workspaceProvider).currentPath;
      final relPath =
          (workspacePath != null && file.path.startsWith(workspacePath))
          ? p.relative(file.path, from: workspacePath)
          : file.path;

      return GitDiffPage(
        key: ValueKey('diff_${file.path}'),
        relativePath: relPath,
        initiallyStaged: false,
        originalOverride: file.originalContent,
        previewContent: file.controller.text,
        onClose: () {
          ref.read(editorProvider.notifier).setDiffView(file.path, false);
        },
      );
    }

    return settings.autoCompletion
        ? CodeAutocomplete(
            viewBuilder: (context, notifier, onSelected) {
              return QuantumAutocompleteView(
                notifier: notifier,
                onSelected: onSelected,
              );
            },
            promptsBuilder: QuantumAutocompletePromptsBuilder(),
            child: StableEditorWidget(
              key: ValueKey(file.path),
              file: file,
              settings: settings,
            ),
          )
        : StableEditorWidget(
            key: ValueKey(file.path),
            file: file,
            settings: settings,
          );
  }

  Widget _buildSplitEditor(
    WidgetRef ref,
    SettingsState settings,
    EditorFile activeFile,
  ) {
    final editorState = ref.read(editorProvider);
    final splitFile =
        _splitTabIndex >= 0 && _splitTabIndex < editorState.openFiles.length
        ? editorState.openFiles[_splitTabIndex]
        : activeFile;

    return Row(
      children: [
        Expanded(child: _buildSingleEditor(ref, settings, activeFile)),
        Container(width: 2, color: Colors.white.withValues(alpha: 0.1)),
        Expanded(child: _buildSingleEditor(ref, settings, splitFile)),
      ],
    );
  }

  PopupMenuItem<String> _buildBuildMenuItem(
    String value,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openBuildTargetDialog(
    BuildContext context,
    WidgetRef ref,
    PanelNotifier panelNotifier,
  ) {
    final workspaceState = ref.read(workspaceProvider);
    final projectName = workspaceState.currentPath != null
        ? p.basename(workspaceState.currentPath!)
        : null;

    AdaptiveDialogHelper.showAdaptiveSheet(
      context: context,
      desktopMaxWidth: 560,
      desktopMaxHeight: 680,
      builder: (ctx) => BuildTargetDialog(
        initialProjectName: projectName,
        onStartBuild: (command, displayCmd, target) {
          panelNotifier.selectTab(PanelTab.buildLogs);
          panelNotifier.openPanel();
          ref
              .read(dedicatedTerminalProvider.notifier)
              .sendCommand(
                DedicatedTerminalType.build,
                command,
                interrupt: true,
                clear: false,
              );
        },
      ),
    );
  }

  void _triggerProjectBuild(
    WidgetRef ref,
    PanelNotifier panelNotifier,
    String action,
  ) {
    panelNotifier.selectTab(PanelTab.buildLogs);
    panelNotifier.openPanel();

    BuildTargetType target;
    switch (action) {
      case 'build_arm32':
        target = BuildTargetType.arm32;
        break;
      case 'build_x64':
        target = BuildTargetType.x86_64;
        break;
      case 'build_aab':
        target = BuildTargetType.aab;
        break;
      case 'build_split':
        target = BuildTargetType.split;
        break;
      case 'build_debug':
        target = BuildTargetType.debug;
        break;
      case 'build_arm64':
      case 'build_apk':
      default:
        target = BuildTargetType.arm64;
        break;
    }

    final cmd = BuildResourceOptimizer.generateBuildCommand(
      target: target,
      mode: BuildPerformanceMode.balanced,
    );

    ref
        .read(dedicatedTerminalProvider.notifier)
        .sendCommand(
          DedicatedTerminalType.build,
          cmd,
          interrupt: true,
          clear: false,
        );
  }
}

// ─── Дерево файлов (изолированный StatefulWidget) ───────────────────────────
// Отдельный виджет для дерева файлов, чтобы onRefreshParent вызывал setState
// только на нём, а не на всём EditorPage.
