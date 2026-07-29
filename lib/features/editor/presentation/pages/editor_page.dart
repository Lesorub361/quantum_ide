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
import 'package:quantum_ide/features/ai_assistant/presentation/widgets/right_chat_panel.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:quantum_ide/core/services/wasm_plugin_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/file_drawer.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/editor_app_bar.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/stable_editor_widget.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:quantum_ide/shared/providers/drawer_provider.dart';
import 'package:quantum_ide/core/utils/adaptive_dialog_helper.dart';



// ─── Вспомогательные функции для диалогов и меню ───────────────────────────

void showSortMenu(BuildContext context, WidgetRef ref) async {
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

Future<void> showCreateDialog(BuildContext context, WidgetRef ref, String basePath, bool isDir) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isDir ? AppLocalizations.of(context)!.newFolder : AppLocalizations.of(context)!.newFile),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: isDir ? AppLocalizations.of(context)!.nameFolderHint : AppLocalizations.of(context)!.nameFileHint),
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                            )
                          else
                            IconButton(
                              icon: const Icon(LucideIcons.refresh_cw, size: 18, color: Colors.blueAccent),
                              onPressed: () => ref.read(environmentProvider.notifier).checkEnvironment(),
                            ),
                          IconButton(
                            icon: const Icon(LucideIcons.wrench, size: 18, color: Colors.orangeAccent),
                            tooltip: AppLocalizations.of(context)!.fixEnvironmentArm64,
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

  double _leftSidebarWidth = 260.0;
  double _rightSidebarWidth = 340.0;
  bool _isResizingLeft = false;
  bool _isResizingRight = false;

  void _showWasmActionSelector(BuildContext context, WidgetRef ref, int activeFileIndex) {
    final l10n = AppLocalizations.of(context)!;
    final wasmState = ref.read(wasmPluginServiceProvider);
    final enabledPlugins = wasmState.plugins.where((p) => p.isEnabled).toList();

    if (enabledPlugins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noActiveWasmPlugins),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    AdaptiveDialogHelper.showAdaptiveSheet(
      context: context,
      backgroundColor: const Color(0xFF13151D),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.selectPluginAction,
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: enabledPlugins.length,
                  itemBuilder: (context, pIdx) {
                    final plugin = enabledPlugins[pIdx];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Text(
                            plugin.name,
                            style: GoogleFonts.inter(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...plugin.actions.map((action) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              action.name,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            subtitle: Text(
                              action.description,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            trailing: const Icon(LucideIcons.play, size: 12, color: Colors.cyanAccent),
                            onTap: () {
                              Navigator.pop(context);
                              _runWasmActionOnEditor(context, ref, plugin.id, action.id, activeFileIndex);
                            },
                          );
                        }),
                        const Divider(color: Colors.white10),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runWasmActionOnEditor(
    BuildContext context,
    WidgetRef ref,
    String pluginId,
    int actionId,
    int activeFileIndex,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final editorState = ref.read(editorProvider);
    if (editorState.openFiles.isEmpty || activeFileIndex >= editorState.openFiles.length) return;

    final file = editorState.openFiles[activeFileIndex];
    final controller = file.controller;

    String textToProcess = '';
    bool isSelection = false;

    String getSelectedText(CodeLineEditingController controller) {
      final selection = controller.selection;
      if (selection.isCollapsed) return '';
      final text = controller.text;
      final lines = text.split('\n');
      final startLine = selection.start.index;
      final startCol = selection.start.offset;
      final endLine = selection.end.index;
      final endCol = selection.end.offset;

      if (startLine >= lines.length || endLine >= lines.length) return '';

      if (startLine == endLine) {
        return lines[startLine].substring(
          startCol.clamp(0, lines[startLine].length),
          endCol.clamp(0, lines[startLine].length),
        );
      }

      final buffer = StringBuffer();
      buffer.writeln(lines[startLine].substring(startCol.clamp(0, lines[startLine].length)));
      for (int i = startLine + 1; i < endLine; i++) {
        buffer.writeln(lines[i]);
      }
      buffer.write(lines[endLine].substring(0, endCol.clamp(0, lines[endLine].length)));
      return buffer.toString();
    }

    final selectedText = getSelectedText(controller);

    if (selectedText.isNotEmpty) {
      textToProcess = selectedText;
      isSelection = true;
    } else {
      final apply = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF13151D),
          title: Text(l10n.noSelection, style: const TextStyle(color: Colors.white)),
          content: Text(
            l10n.applyPluginToFile,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.apply),
            ),
          ],
        ),
      );

      if (apply != true) return;
      textToProcess = controller.text;
      isSelection = false;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.cyanAccent),
      ),
    );

    try {
      final processedText = await ref.read(wasmPluginServiceProvider.notifier).executeAction(
        pluginId,
        actionId,
        textToProcess,
      );

      if (context.mounted) {
        Navigator.pop(context); // Close loading indicator
      }

      if (isSelection) {
        controller.replaceSelection(processedText);
      } else {
        controller.text = processedText;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pluginExecutedSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.executionError(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

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

    // Показываем уведомление об автонастройке .gitignore
    if (mounted) {
      final isRu = Localizations.localeOf(context).languageCode == 'ru';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRu 
              ? 'Проект открыт. Папка .quantum/ автоматически исключена из Git.' 
              : 'Project opened. Folder .quantum/ is automatically ignored in Git.'
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
    final rawActiveIndex = ref.watch(editorProvider.select((s) => s.activeTabIndex));
    
    int safeActiveIndex = rawActiveIndex;
    if (safeActiveIndex >= openFilesCount) {
      safeActiveIndex = openFilesCount > 0 ? openFilesCount - 1 : 0;
    }
    if (safeActiveIndex < 0) safeActiveIndex = 0;

    final activeFile = (openFilesCount > 0 && safeActiveIndex < openFilesCount)
        ? openFiles[safeActiveIndex]
        : null;
    
    final settings = ref.watch(settingsProvider);
    final workspacePath = ref.watch(workspaceProvider).currentPath;
    final panelState = ref.watch(panelProvider);
    final panelNotifier = ref.read(panelProvider.notifier);
    
    final isDesktop = MediaQuery.of(context).size.width > 800;
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

    ref.listen<bool>(rightChatPanelOpenProvider, (previous, current) {
      if (current) {
        if (!isDesktop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Show bottom sheet instead of endDrawer
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  margin: const EdgeInsets.only(top: 24),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F111A),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: const RightChatPanel(isInline: false),
                );
              },
            ).whenComplete(() {
              // Ensure provider is reset if user dismissed the sheet by swiping
              if (ref.read(rightChatPanelOpenProvider)) {
                ref.read(rightChatPanelOpenProvider.notifier).state = false;
              }
            });
          });
        }
      } else {
        if (!isDesktop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             Navigator.of(context).popUntil((route) {
               return route.settings.name != null || route.isFirst;
             });
          });
        }
      }
    });

    final allProjects = ref.watch(projectServiceProvider);
    final currentProjectIndex = allProjects.indexWhere((p) => p.path == workspacePath);
    final currentProject = currentProjectIndex != -1 ? allProjects[currentProjectIndex] : null;

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
            // ── Редактор (динамически уменьшает высоту при открытии панели) ────
            AnimatedPositioned(
              duration: _isDragging
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              top: 0,
              left: 0,
              right: 0,
              bottom: activePanelHeight,
              child: activeFile == null
                  ? _buildDashboard(context, ref, isDesktop, workspacePath)
                  : Column(
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
                              tooltip: AppLocalizations.of(context)!.quickSearch,
                            ),
                          ],
                        ),
                  Expanded(
                    child: DropTarget(
                      onDragDone: (detail) async {
                        for (final file in detail.files) {
                          if (workspacePath != null) {
                            final targetPath = p.join(workspacePath, p.basename(file.path));
                            final fileEntity = File(file.path);
                            if (await fileEntity.exists()) {
                              await fileEntity.copy(targetPath);
                              ref.read(editorProvider.notifier).openFile(targetPath);
                            }
                          } else {
                            ref.read(editorProvider.notifier).openFile(file.path);
                          }
                        }
                      },
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                              () => ref.read(editorProvider.notifier).saveFile(safeActiveIndex),
                          const SingleActivator(LogicalKeyboardKey.keyP, control: true):
                              () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.files),
                          const SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true):
                              () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.commands),
                          const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
                              () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.files),
                          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
                            if (!isDesktop) {
                              if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
                                _scaffoldKey.currentState?.closeDrawer();
                              } else {
                                _scaffoldKey.currentState?.openDrawer();
                              }
                            }
                          },
                          const SingleActivator(LogicalKeyboardKey.backquote, control: true):
                              () => panelNotifier.toggle(),
                          const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                              () => QuickSwitcherDialog.show(context, initialMode: SwitcherMode.symbols),
                          const SingleActivator(LogicalKeyboardKey.keyW, control: true):
                              () => ref.read(editorProvider.notifier).closeTab(safeActiveIndex),
                          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                              () => _showFindPanel(context, ref),
                          const SingleActivator(LogicalKeyboardKey.keyH, control: true):
                              () => _showFindPanel(context, ref, replace: true),
                          const SingleActivator(LogicalKeyboardKey.keyD, control: true):
                              () => _duplicateLine(ref),
                          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                              () => _toggleZenMode(ref),
                          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
                              () => _toggleSplitMode(ref),
                          const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true, shift: true):
                              () => panelNotifier.selectTab(PanelTab.problems),
                          const SingleActivator(LogicalKeyboardKey.f5): () {
                            if (currentProject != null) {
                              ref.read(projectServiceProvider.notifier).runProject(currentProject);
                              panelNotifier.selectTab(PanelTab.terminal);
                              panelNotifier.openPanel();
                            }
                          },
                        },
                        child: _isSplitMode ? _buildSplitEditor(ref, settings, activeFile) : _buildSingleEditor(ref, settings, activeFile),
                      ),
                    ),
                  ),
                  if (!isDesktop) KeyboardAccessoryBar(controller: activeFile.controller),
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
      drawer: isDesktop ? null : const FileDrawer(),
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
                          icon: const Icon(LucideIcons.menu, size: 20, color: Colors.blueAccent),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          tooltip: AppLocalizations.of(context)!.openExplorer,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          constraints: const BoxConstraints(),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.arrow_left, size: 16),
                              onPressed: () {
                                ref.read(workspaceProvider.notifier).closeWorkspace();
                                context.go('/');
                              },
                              tooltip: AppLocalizations.of(context)!.back,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              constraints: const BoxConstraints(),
                            ),
                            IconButton(
                              icon: const Icon(LucideIcons.panel_left, size: 16),
                              onPressed: () {
                                final isOpen = ref.read(leftPanelOpenProvider);
                                final currentTab = ref.read(drawerTabProvider);
                                if (!isOpen) {
                                  ref.read(drawerTabProvider.notifier).state = 0;
                                  ref.read(leftPanelOpenProvider.notifier).state = true;
                                } else if (currentTab != 0) {
                                  ref.read(drawerTabProvider.notifier).state = 0;
                                } else {
                                  ref.read(leftPanelOpenProvider.notifier).state = false;
                                }
                              },
                              tooltip: AppLocalizations.of(context)!.openExplorer,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      const Expanded(
                        child: EditorAppBarTitle(),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ActionIconButton(
                            icon: LucideIcons.play,
                            color: Colors.greenAccent,
                            tooltip: 'Запустить / Скомпилировать проект (F5)',
                            onTap: () {
                              if (currentProject != null) {
                                ref.read(projectServiceProvider.notifier).runProject(currentProject);
                                panelNotifier.selectTab(PanelTab.terminal);
                                panelNotifier.openPanel();
                              } else {
                                panelNotifier.selectTab(PanelTab.terminal);
                                panelNotifier.openPanel();
                              }
                            },
                          ),
                          ActionIconButton(
                            icon: LucideIcons.save,
                            tooltip: AppLocalizations.of(context)!.saveTooltip,
                            onTap: () => ref.read(editorProvider.notifier).saveFile(safeActiveIndex),
                          ),
                          ActionIconButton(
                            icon: LucideIcons.puzzle,
                            tooltip: AppLocalizations.of(context)!.runWasmPlugin,
                            onTap: () => _showWasmActionSelector(context, ref, safeActiveIndex),
                          ),
                          ActionIconButton(
                            icon: LucideIcons.terminal,
                            tooltip: AppLocalizations.of(context)!.terminal,
                            onTap: () {
                              if (panelState.isOpened && panelState.selectedTab == PanelTab.terminal) {
                                panelNotifier.closePanel();
                              } else {
                                panelNotifier.selectTab(PanelTab.terminal);
                                panelNotifier.openPanel();
                              }
                            },
                          ),
                          ActionIconButton(
                            icon: LucideIcons.message_square,
                            tooltip: AppLocalizations.of(context)!.aiChat,
                            onTap: () {
                              ref.read(rightChatPanelOpenProvider.notifier).update((v) => !v);
                            },
                          ),
                          if (!isDesktop)
                            ActionIconButton(
                              icon: LucideIcons.house,
                              tooltip: l10n.home,
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
                const EditorTabBar(),
              ],
            ),
          ),
        ),
      ),
      endDrawer: null,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: SizedBox(
              width: 1,
              height: 1,
              child: (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
                  ? InAppWebView(
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                      ),
                      initialData: InAppWebViewInitialData(
                        data: """
                          <!DOCTYPE html>
                          <html>
                          <head>
                            <title>WASM Runner</title>
                            <script>
                              window.plugins = window.plugins || {};

                              function registerLogs(pluginId, msg) {
                                if (window.flutter_inappwebview) {
                                  window.flutter_inappwebview.callHandler('onPluginLog', { pluginId: pluginId, message: msg });
                                }
                              }

                              window.loadWasmPlugin = async function(pluginId, base64Bytes) {
                                try {
                                  const binaryString = atob(base64Bytes);
                                  const len = binaryString.length;
                                  const bytes = new Uint8Array(len);
                                  for (let i = 0; i < len; i++) {
                                    bytes[i] = binaryString.charCodeAt(i);
                                  }
                                  
                                  const memory = new WebAssembly.Memory({ initial: 256, maximum: 512 });
                                  
                                  const importObject = {
                                    env: {
                                      memory: memory,
                                      host_log: (ptr, length) => {
                                        const buffer = new Uint8Array(memory.buffer, ptr, length);
                                        const msg = new TextDecoder('utf-8').decode(buffer);
                                        registerLogs(pluginId, msg);
                                      }
                                    }
                                  };
                                  
                                  const { instance } = await WebAssembly.instantiate(bytes, importObject);
                                  
                                  window.plugins[pluginId] = {
                                    instance: instance,
                                    memory: instance.exports.memory || memory
                                  };
                                  
                                  return { success: true };
                                } catch (e) {
                                  console.error("Failed to load WASM plugin:", e);
                                  return { success: false, error: e.toString() };
                                }
                              };

                              window.runWasmAction = async function(pluginId, actionId, inputText) {
                                const plugin = window.plugins[pluginId];
                                if (!plugin) throw new Error("Plugin not loaded");
                                
                                const instance = plugin.instance;
                                const memory = plugin.memory;
                                
                                const utf8Encoder = new TextEncoder();
                                const inputBytes = utf8Encoder.encode(inputText);
                                const inputLen = inputBytes.length;
                                
                                if (!instance.exports.alloc) {
                                  throw new Error("WASM module must export an 'alloc' function");
                                }
                                
                                const inputPtr = instance.exports.alloc(inputLen);
                                const memoryBuffer = new Uint8Array(memory.buffer);
                                memoryBuffer.set(inputBytes, inputPtr);
                                
                                if (!instance.exports.run_plugin) {
                                  throw new Error("WASM module must export a 'run_plugin' function");
                                }
                                
                                const resultPacked = instance.exports.run_plugin(actionId, inputPtr, inputLen);
                                const packedBig = BigInt(resultPacked);
                                const resultPtr = Number(packedBig >> 32n);
                                const resultLen = Number(packedBig & 0xFFFFFFFFn);
                                
                                const resultBuffer = new Uint8Array(memory.buffer, resultPtr, resultLen);
                                const outputText = new TextDecoder('utf-8').decode(resultBuffer);
                                
                                if (instance.exports.dealloc) {
                                  instance.exports.dealloc(inputPtr, inputLen);
                                  instance.exports.dealloc(resultPtr, resultLen);
                                }
                                
                                return outputText;
                              };
                            </script>
                          </head>
                          <body>
                            <h3>WASM Plugin Runner Sandbox</h3>
                          </body>
                          </html>
                        """,
                      ),
                      onWebViewCreated: (controller) {
                        ref.read(wasmPluginServiceProvider.notifier).setController(controller);
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: isDesktop 
                ? _buildDesktopMultiSplit(
                    mainBody, 
                    ref.watch(leftPanelOpenProvider), 
                    ref.watch(rightChatPanelOpenProvider),
                  )
                : mainBody,
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? const StatusBar() : const StatusBar(),
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
                  ? const TerminalPanelContent(onlyTerminal: false)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildDesktopMultiSplit(Widget mainContent, bool leftOpen, bool rightOpen) {
    return Row(
      children: [
        if (leftOpen) ...[
          SizedBox(
            width: _leftSidebarWidth.clamp(180.0, 550.0),
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
                  _leftSidebarWidth = (_leftSidebarWidth + details.delta.dx).clamp(180.0, 550.0);
                });
              },
              onHorizontalDragEnd: (_) => setState(() {
                _isDragging = false;
                _isResizingLeft = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 7,
                decoration: BoxDecoration(
                  color: _isResizingLeft 
                      ? Colors.cyanAccent.withValues(alpha: 0.2) 
                      : Colors.white.withValues(alpha: 0.04),
                  border: Border(
                    left: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
                    right: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _isResizingLeft ? Colors.cyanAccent : Colors.white24,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        Expanded(
          child: mainContent,
        ),
        if (rightOpen) ...[
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
                  _rightSidebarWidth = (_rightSidebarWidth - details.delta.dx).clamp(220.0, 700.0);
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
                      ? Colors.cyanAccent.withValues(alpha: 0.2) 
                      : Colors.white.withValues(alpha: 0.04),
                  border: Border(
                    left: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
                    right: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _isResizingRight ? Colors.cyanAccent : Colors.white24,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _rightSidebarWidth.clamp(220.0, 700.0),
            child: const RightChatPanel(isInline: true),
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
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: Builder(
                        builder: (context) {
                          final isMobile = MediaQuery.of(context).size.width <= 800;
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: PanelTab.values.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                              final tab = PanelTab.values[index];
                              final isSelected = panelState.selectedTab == tab;
                              final tabColor = _getTabColor(tab);
                              return Padding(
                                padding: EdgeInsets.only(right: isMobile ? 8.0 : 6.0),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => panelNotifier.selectTab(tab),
                                    borderRadius: BorderRadius.circular(isMobile ? 12 : 8),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 14 : 10,
                                        vertical: isMobile ? 8 : 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? tabColor.withValues(alpha: 0.12)
                                            : Colors.white.withValues(alpha: 0.02),
                                        borderRadius: BorderRadius.circular(isMobile ? 12 : 8),
                                        border: Border.all(
                                          color: isSelected
                                              ? tabColor.withValues(alpha: 0.35)
                                              : Colors.white.withValues(alpha: 0.05),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getTabIcon(tab),
                                            size: isMobile ? 18 : 13,
                                            color: isSelected ? tabColor : Colors.white54,
                                          ),
                                          if (!isMobile) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              _getTabTitle(context, tab),
                                              style: GoogleFonts.inter(
                                                color: isSelected ? Colors.white : Colors.white54,
                                                fontSize: 11,
                                                fontWeight: isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
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
                  const SizedBox(width: 8),
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
      case PanelTab.problems: return LucideIcons.circle_alert;
      case PanelTab.debug: return LucideIcons.bug;
    }
  }

  Color _getTabColor(PanelTab tab) {
    switch (tab) {
      case PanelTab.terminal: return Colors.cyanAccent;
      case PanelTab.appLogs: return Colors.deepPurpleAccent;
      case PanelTab.run: return Colors.greenAccent;
      case PanelTab.buildLogs: return Colors.orangeAccent;
      case PanelTab.git: return Colors.amberAccent;
      case PanelTab.problems: return Colors.redAccent;
      case PanelTab.debug: return Colors.orangeAccent;
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
      case PanelTab.problems: return l10n.problems;
      case PanelTab.debug: return l10n.debugger;
    }
  }

  Widget _buildDashboard(BuildContext context, WidgetRef ref, bool isDesktop, String? workspacePath) {
    final stats = ref.watch(systemStatsProvider);
    final gitChangesCount = ref.watch(gitProvider.select((s) =>
      (s.status?.stagedFiles.length ?? 0) +
      (s.status?.modifiedFiles.length ?? 0) +
      (s.status?.untrackedFiles.length ?? 0) +
      (s.status?.conflictedFiles.length ?? 0)
    ));


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

              // System Stats Dashboard with Circular Gauges
              GlassContainer(
                blur: 20,
                opacity: 0.05,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                            value: '${(stats.cpuUsage * 100).toStringAsFixed(1)}%',
                            progress: stats.cpuUsage,
                            color: Colors.cyanAccent,
                          ),
                          Container(
                            width: 1,
                            height: 60,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          _buildCircularGauge(
                            label: 'RAM',
                            value: '${stats.ramUsedGB.toStringAsFixed(1)} GB / ${stats.ramTotalGB.toStringAsFixed(1)} GB',
                            progress: stats.ramUsage,
                            color: Colors.purpleAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
                    icon: LucideIcons.terminal,
                    iconColor: Colors.orangeAccent,
                    title: 'Терминал',
                    subtitle: 'Командная строка и сборка',
                    onTap: () {
                      ref.read(panelProvider.notifier).selectTab(PanelTab.terminal);
                      ref.read(panelProvider.notifier).openPanel();
                    },
                  ),
                  _buildDashboardActionCard(
                    icon: LucideIcons.message_square,
                    iconColor: Colors.purpleAccent,
                    title: 'ИИ Ассистент',
                    subtitle: 'Чат с Gemini & Copilot',
                    onTap: () {
                      ref.read(rightChatPanelOpenProvider.notifier).update((v) => !v);
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
          style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
            ),
            const SizedBox(height: 12),
            ...projects.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Icon(LucideIcons.folder, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p['name']!,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    p['time']!,
                    style: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
                  ),
                ],
              ),
            )),
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
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                ),
                const Icon(LucideIcons.git_branch, size: 14, color: Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(LucideIcons.git_fork, size: 14, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text(
                  'Ветка: main*',
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(color: Colors.white30, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevron_right, size: 14, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  void _showFindPanel(BuildContext context, WidgetRef ref, {bool replace = false}) {
    final editorState = ref.read(editorProvider);
    if (editorState.openFiles.isEmpty || editorState.activeTabIndex >= editorState.openFiles.length) return;
    
    final controller = editorState.openFiles[editorState.activeTabIndex].controller;
    final finder = CodeFindController(controller);
    
    if (replace) {
      finder.replaceMode();
    } else {
      finder.findMode();
    }
  }

  void _duplicateLine(WidgetRef ref) {
    final editorState = ref.read(editorProvider);
    if (editorState.openFiles.isEmpty || editorState.activeTabIndex >= editorState.openFiles.length) return;
    
    final controller = editorState.openFiles[editorState.activeTabIndex].controller;
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
    final panelNotifier = ref.read(panelProvider.notifier);
    panelNotifier.toggle();
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

  Widget _buildSingleEditor(WidgetRef ref, SettingsState settings, EditorFile activeFile) {
    final file = activeFile;

    if (file.isDiffView) {
      final workspacePath = ref.read(workspaceProvider).currentPath;
      final relPath = (workspacePath != null && file.path.startsWith(workspacePath))
          ? p.relative(file.path, from: workspacePath)
          : file.path;

      final aiState = ref.read(aiProvider);
      final action = aiState.proposedActions.firstWhere(
        (a) => a.path == file.path && (a.type == 'edit' || a.type == 'create'),
        orElse: () => AIAction(type: 'edit', path: file.path, content: file.controller.text, description: ''),
      );

      return GitDiffPage(
        key: ValueKey('diff_${file.path}_${action.content.hashCode}'),
        relativePath: relPath,
        initiallyStaged: false,
        originalOverride: file.originalContent,
        previewContent: action.content,
      );
    }

    return settings.autoCompletion
        ? CodeAutocomplete(
            viewBuilder: (context, notifier, onSelected) {
              return QuantumAutocompleteView(
                  notifier: notifier, onSelected: onSelected);
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

  Widget _buildSplitEditor(WidgetRef ref, SettingsState settings, EditorFile activeFile) {
    final editorState = ref.read(editorProvider);
    final splitFile = _splitTabIndex >= 0 && _splitTabIndex < editorState.openFiles.length
        ? editorState.openFiles[_splitTabIndex]
        : activeFile;

    return Row(
      children: [
        Expanded(
          child: _buildSingleEditor(ref, settings, activeFile),
        ),
        Container(
          width: 2,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        Expanded(
          child: _buildSingleEditor(ref, settings, splitFile),
        ),
      ],
    );
  }
}

// ─── Дерево файлов (изолированный StatefulWidget) ───────────────────────────
// Отдельный виджет для дерева файлов, чтобы onRefreshParent вызывал setState
// только на нём, а не на всём EditorPage.


