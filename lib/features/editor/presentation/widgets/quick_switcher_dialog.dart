import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';

enum SwitcherMode { files, symbols, commands }

class IDECommand {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final VoidCallback action;

  const IDECommand({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.action,
  });
}

class QuickSwitcherDialog extends ConsumerStatefulWidget {
  final SwitcherMode initialMode;
  const QuickSwitcherDialog({
    super.key,
    this.initialMode = SwitcherMode.files,
  });

  static void show(BuildContext context, {SwitcherMode initialMode = SwitcherMode.files}) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => QuickSwitcherDialog(initialMode: initialMode),
    );
  }

  @override
  ConsumerState<QuickSwitcherDialog> createState() => _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends ConsumerState<QuickSwitcherDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();
  
  SwitcherMode _mode = SwitcherMode.files;
  List<dynamic> _results = [];
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    if (_mode == SwitcherMode.commands) {
      _controller.text = '>';
    }
    _controller.addListener(_onSearchChanged);
    _inputFocus.requestFocus();
    
    // Initial results loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateResults();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _keyboardFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final text = _controller.text;
    SwitcherMode newMode = _mode;
    
    if (text.startsWith('>')) {
      newMode = SwitcherMode.commands;
    } else if (text.startsWith('#')) {
      newMode = SwitcherMode.symbols;
    } else {
      newMode = SwitcherMode.files;
    }

    if (newMode != _mode) {
      setState(() {
        _mode = newMode;
        _selectedIndex = 0;
      });
    }

    _updateResults();
  }

  List<IDECommand> _getCommandsList(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final editorState = ref.read(editorProvider);
    final editorNotifier = ref.read(editorProvider.notifier);
    final allProjects = ref.read(projectServiceProvider);
    final workspacePath = ref.read(workspaceProvider).currentPath;
    
    final currentProjectIndex = allProjects.indexWhere((p) => p.path == workspacePath);
    final currentProject = currentProjectIndex != -1 ? allProjects[currentProjectIndex] : null;
    
    final panelNotifier = ref.read(panelProvider.notifier);
    final hasActiveFile = editorState.openFiles.isNotEmpty &&
        editorState.activeTabIndex >= 0 &&
        editorState.activeTabIndex < editorState.openFiles.length;

    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return [
      IDECommand(
        title: isRu ? 'Сохранить файл' : 'Save File',
        description: isRu ? 'Сохранить текущие изменения файла на диск' : 'Save current active file changes to disk',
        icon: LucideIcons.save,
        iconColor: Colors.blueAccent,
        action: () {
          if (hasActiveFile) {
            editorNotifier.saveFile(editorState.activeTabIndex);
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Форматировать документ' : 'Format Document',
        description: isRu ? 'Форматировать код active-документа через LSP' : 'Format code in the current active document using LSP',
        icon: LucideIcons.file_code,
        iconColor: Colors.cyanAccent,
        action: () {
          if (hasActiveFile) {
            editorNotifier.formatActiveFile();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Переключить перенос строк' : 'Toggle Word Wrap',
        description: isRu ? 'Включить или выключить автоматический перенос длинных строк' : 'Toggle line wrapping in the editor viewport',
        icon: LucideIcons.code,
        iconColor: Colors.tealAccent,
        action: () {
          settingsNotifier.setWordWrap(!settings.wordWrap);
        },
      ),
      IDECommand(
        title: isRu ? 'Переключить номера строк' : 'Toggle Line Numbers',
        description: isRu ? 'Показать или скрыть левую колонку с номерами строк' : 'Show or hide editor line numbers column',
        icon: LucideIcons.list_ordered,
        iconColor: Colors.amberAccent,
        action: () {
          settingsNotifier.setLineNumbers(!settings.lineNumbers);
        },
      ),
      IDECommand(
        title: isRu ? 'Переключить миникарту' : 'Toggle Minimap',
        description: isRu ? 'Показать или скрыть визуальную карту кода справа' : 'Show or hide the visual editor code map preview',
        icon: LucideIcons.map,
        iconColor: Colors.purpleAccent,
        action: () {
          settingsNotifier.setMinimap(!settings.minimap);
        },
      ),
      IDECommand(
        title: isRu ? 'Переключить форматирование при сохранении' : 'Toggle Format on Save',
        description: isRu ? 'Включить или отключить автоформатирование файлов при сохранении' : 'Automatically format files whenever they are saved',
        icon: LucideIcons.circle_check_big,
        iconColor: Colors.greenAccent,
        action: () {
          settingsNotifier.setFormatOnSave(!settings.formatOnSave);
        },
      ),
      if (currentProject != null) ...[
        IDECommand(
          title: isRu ? 'Запустить проект' : 'Run Project',
          description: isRu ? 'Собрать и запустить текущий проект Flutter/Dart' : 'Build and run the current Flutter/Dart project',
          icon: LucideIcons.play,
          iconColor: Colors.lightGreenAccent,
          action: () {
            ref.read(projectServiceProvider.notifier).runProject(currentProject);
            panelNotifier.selectTab(PanelTab.terminal);
            panelNotifier.openPanel();
          },
        ),
      ],
      IDECommand(
        title: isRu ? 'Остановить выполнение проекта' : 'Stop Running Project',
        description: isRu ? 'Прервать active-процесс выполнения проекта в терминале' : 'Stop the currently running project process',
        icon: LucideIcons.square,
        iconColor: Colors.redAccent,
        action: () {
          ref.read(terminalTabsProvider.notifier).sendCommand('', interrupt: true);
        },
      ),
      IDECommand(
        title: isRu ? 'Открыть настройки' : 'Open Settings',
        description: isRu ? 'Перейти в экран глобальных настроек приложения' : 'Go to the global application settings screen',
        icon: LucideIcons.settings,
        iconColor: Colors.grey,
        action: () {
          context.push('/settings');
        },
      ),
      IDECommand(
        title: isRu ? 'Показать панель терминала' : 'Show Terminal Panel',
        description: isRu ? 'Открыть нижнюю панель с консолью терминала' : 'Open the bottom panel with the terminal view',
        icon: LucideIcons.terminal,
        iconColor: Colors.blue,
        action: () {
          panelNotifier.selectTab(PanelTab.terminal);
          panelNotifier.openPanel();
        },
      ),
      IDECommand(
        title: isRu ? 'Закрыть текущую вкладку' : 'Close Current Editor Tab',
        description: isRu ? 'Закрыть активный файл в панели редактора' : 'Close the active file and tab panel',
        icon: LucideIcons.x,
        iconColor: Colors.orangeAccent,
        action: () {
          if (hasActiveFile) {
            editorNotifier.closeTab(editorState.activeTabIndex);
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Переключить тему оформления' : 'Toggle Theme Mode',
        description: isRu ? 'Переключить визуальную тему (Тёмная/Светлая)' : 'Switch between light and dark visual themes',
        icon: LucideIcons.sun,
        iconColor: Colors.yellowAccent,
        action: () {
          settingsNotifier.setThemeMode(settings.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
        },
      ),
      IDECommand(
        title: isRu ? 'Найти и заменить' : 'Find and Replace',
        description: isRu ? 'Открыть панель поиска и замены (Ctrl+H)' : 'Open find and replace panel (Ctrl+H)',
        icon: LucideIcons.replace,
        iconColor: Colors.cyanAccent,
        action: () {
          Navigator.pop(context);
        },
      ),
      IDECommand(
        title: isRu ? 'Найти в файле' : 'Find in File',
        description: isRu ? 'Открыть панель поиска (Ctrl+F)' : 'Open find panel (Ctrl+F)',
        icon: LucideIcons.search,
        iconColor: Colors.cyanAccent,
        action: () {
          Navigator.pop(context);
        },
      ),
      IDECommand(
        title: isRu ? 'Вырезать строку' : 'Cut Line',
        description: isRu ? 'Вырезать текущую строку' : 'Cut the current line',
        icon: LucideIcons.scissors,
        iconColor: Colors.redAccent,
        action: () {
          if (hasActiveFile) {
            editorState.openFiles[editorState.activeTabIndex].controller.cut();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Дублировать строку' : 'Duplicate Line',
        description: isRu ? 'Дублировать текущую строку вниз' : 'Duplicate the current line below',
        icon: LucideIcons.copy,
        iconColor: Colors.blueAccent,
        action: () {
          if (hasActiveFile) {
            final ctrl = editorState.openFiles[editorState.activeTabIndex].controller;
            ctrl.replaceSelection('${ctrl.selectedText}\n${ctrl.selectedText}');
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Удалить строку' : 'Delete Line',
        description: isRu ? 'Удалить текущую строку' : 'Delete the current line',
        icon: LucideIcons.trash_2,
        iconColor: Colors.redAccent,
        action: () {
          if (hasActiveFile) {
            editorState.openFiles[editorState.activeTabIndex].controller.deleteSelectionLines();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Переместить строку вверх' : 'Move Line Up',
        description: isRu ? 'Переместить текущую строку вверх' : 'Move the current line up',
        icon: LucideIcons.arrow_up,
        iconColor: Colors.greenAccent,
        action: () {
          if (hasActiveFile) {
            editorState.openFiles[editorState.activeTabIndex].controller.moveSelectionLinesUp();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Переместить строку вниз' : 'Move Line Down',
        description: isRu ? 'Переместить текущую строку вниз' : 'Move the current line down',
        icon: LucideIcons.arrow_down,
        iconColor: Colors.greenAccent,
        action: () {
          if (hasActiveFile) {
            editorState.openFiles[editorState.activeTabIndex].controller.moveSelectionLinesDown();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Выделить всё на экране' : 'Select All',
        description: isRu ? 'Выделить весь текст в файле' : 'Select all text in file',
        icon: LucideIcons.lasso_select,
        iconColor: Colors.purpleAccent,
        action: () {
          if (hasActiveFile) {
            editorState.openFiles[editorState.activeTabIndex].controller.selectAll();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Мульти-курсор: все вхождения' : 'Multi-cursor: All Occurrences',
        description: isRu ? 'Добавить курсор ко всем вхождениям выделенного текста' : 'Add cursor to all occurrences of selected text',
        icon: LucideIcons.mouse_pointer_click,
        iconColor: Colors.cyanAccent,
        action: () {
          if (hasActiveFile) {
            final ctrl = editorState.openFiles[editorState.activeTabIndex].controller;
            ctrl.selectAll();
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Свернуть все блоки' : 'Fold All',
        description: isRu ? 'Свернуть все блоки кода в файле' : 'Fold all code blocks in file',
        icon: LucideIcons.minimize_2,
        iconColor: Colors.tealAccent,
        action: () {
          if (hasActiveFile) {
            final ctrl = editorState.openFiles[editorState.activeTabIndex].controller;
            final text = ctrl.text;
            final lines = text.split('\n');
            int depth = 0;
            for (int i = 0; i < lines.length; i++) {
              final line = lines[i];
              for (final ch in line.split('')) {
                if (ch == '{') depth++;
                if (ch == '}') {
                  depth--;
                  if (depth > 0) {
                    ctrl.collapseChunk(i - depth, i);
                  }
                }
              }
            }
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Развернуть все блоки' : 'Unfold All',
        description: isRu ? 'Развернуть все свёрнутые блоки кода' : 'Unfold all folded code blocks',
        icon: LucideIcons.maximize_2,
        iconColor: Colors.tealAccent,
        action: () {
          if (hasActiveFile) {
            final ctrl = editorState.openFiles[editorState.activeTabIndex].controller;
            for (int i = 0; i < ctrl.lineCount; i++) {
              ctrl.expandChunk(i);
            }
          }
        },
      ),
      IDECommand(
        title: isRu ? 'AI: Объяснить код' : 'AI: Explain Code',
        description: isRu ? 'Отправить текущий файл в AI для объяснения' : 'Send current file to AI for explanation',
        icon: LucideIcons.brain,
        iconColor: Colors.purpleAccent,
        action: () {
          if (hasActiveFile) {
            final code = editorState.openFiles[editorState.activeTabIndex].controller.text;
            ref.read(aiProvider.notifier).askAI('Explain this code:\n\n```dart\n$code\n```');
            ref.read(rightChatPanelOpenProvider.notifier).state = true;
          }
        },
      ),
      IDECommand(
        title: isRu ? 'AI: Исправить ошибки' : 'AI: Fix Errors',
        description: isRu ? 'Отправить ошибки компиляции в AI для исправления' : 'Send compilation errors to AI for fixing',
        icon: LucideIcons.wrench,
        iconColor: Colors.orangeAccent,
        action: () {
          if (hasActiveFile) {
            final file = editorState.openFiles[editorState.activeTabIndex];
            final errors = file.diagnostics.where((d) => d.severity == CodeDiagnosticSeverity.error).toList();
            if (errors.isEmpty) {
              return;
            }
            final errorText = errors.map((e) => '${e.range.index + 1}: ${e.message}').join('\n');
            final code = file.controller.text;
            ref.read(aiProvider.notifier).askAI('Fix these compilation errors:\n\nErrors:\n$errorText\n\nCode:\n```dart\n$code\n```');
            ref.read(rightChatPanelOpenProvider.notifier).state = true;
          }
        },
      ),
      IDECommand(
        title: isRu ? 'AI: Рефакторинг' : 'AI: Refactor',
        description: isRu ? 'Предложить рефакторинг для текущего файла' : 'Suggest refactoring for current file',
        icon: LucideIcons.refresh_cw,
        iconColor: Colors.cyanAccent,
        action: () {
          if (hasActiveFile) {
            final code = editorState.openFiles[editorState.activeTabIndex].controller.text;
            ref.read(aiProvider.notifier).askAI('Suggest refactoring improvements for this code:\n\n```dart\n$code\n```');
            ref.read(rightChatPanelOpenProvider.notifier).state = true;
          }
        },
      ),
      IDECommand(
        title: isRu ? 'AI: Написать тесты' : 'AI: Write Tests',
        description: isRu ? 'Сгенерировать unit-тесты для текущего файла' : 'Generate unit tests for current file',
        icon: LucideIcons.flask_conical,
        iconColor: Colors.greenAccent,
        action: () {
          if (hasActiveFile) {
            final code = editorState.openFiles[editorState.activeTabIndex].controller.text;
            ref.read(aiProvider.notifier).askAI('Write unit tests for this code:\n\n```dart\n$code\n```');
            ref.read(rightChatPanelOpenProvider.notifier).state = true;
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Запустить тесты' : 'Run Tests',
        description: isRu ? 'Запустить тесты текущего проекта' : 'Run tests for the current project',
        icon: LucideIcons.flask_conical,
        iconColor: Colors.greenAccent,
        action: () {
          if (currentProject != null) {
            ref.read(projectServiceProvider.notifier).runProject(currentProject);
            panelNotifier.selectTab(PanelTab.terminal);
          }
        },
      ),
      IDECommand(
        title: isRu ? 'Очистить консоль' : 'Clear Terminal',
        description: isRu ? 'Очистить вывод терминала' : 'Clear terminal output',
        icon: LucideIcons.eraser,
        iconColor: Colors.grey,
        action: () {
          ref.read(terminalTabsProvider.notifier).sendCommand('clear');
        },
      ),
      IDECommand(
        title: isRu ? 'Переключить панель' : 'Toggle Panel',
        description: isRu ? 'Скрыть/показать нижнюю панель' : 'Hide/show bottom panel',
        icon: LucideIcons.maximize,
        iconColor: Colors.purpleAccent,
        action: () {
          panelNotifier.toggle();
        },
      ),
      IDECommand(
        title: isRu ? 'Показать проблемы' : 'Show Problems',
        description: isRu ? 'Открыть панель проблем (ошибки и предупреждения)' : 'Open problems panel (errors and warnings)',
        icon: LucideIcons.circle_alert,
        iconColor: Colors.redAccent,
        action: () {
          panelNotifier.selectTab(PanelTab.problems);
        },
      ),
    ];
  }

  void _updateResults() {
    final text = _controller.text;
    
    setState(() {
      if (_mode == SwitcherMode.files) {
        final indexer = ref.read(symbolIndexerProvider.notifier);
        _results = indexer.searchFiles(text);
      } else if (_mode == SwitcherMode.symbols) {
        final query = text.startsWith('#') ? text.substring(1) : text;
        final indexer = ref.read(symbolIndexerProvider.notifier);
        _results = indexer.searchSymbols(query);
      } else if (_mode == SwitcherMode.commands) {
        final query = text.startsWith('>') ? text.substring(1).trim() : text.trim();
        final allCommands = _getCommandsList(context);
        if (query.isEmpty) {
          _results = allCommands;
        } else {
          _results = allCommands.where((cmd) {
            return cmd.title.toLowerCase().contains(query.toLowerCase()) ||
                cmd.description.toLowerCase().contains(query.toLowerCase());
          }).toList();
        }
      }
      
      if (_selectedIndex >= _results.length) {
        _selectedIndex = 0;
      }
    });
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_results.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % _results.length;
        });
        _scrollToSelected();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_results.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + _results.length) % _results.length;
        });
        _scrollToSelected();
      }
    } else if (key == LogicalKeyboardKey.enter) {
      _openSelected();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    const itemHeight = 44.0;
    final viewHeight = _scrollController.position.viewportDimension;
    final targetOffset = _selectedIndex * itemHeight;

    if (targetOffset < _scrollController.offset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + itemHeight > _scrollController.offset + viewHeight) {
      _scrollController.animateTo(
        targetOffset + itemHeight - viewHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _openSelected() {
    if (_results.isEmpty || _selectedIndex >= _results.length) return;
    final item = _results[_selectedIndex];
    
    Navigator.pop(context);
    
    if (_mode == SwitcherMode.files) {
      final String path = item as String;
      ref.read(editorProvider.notifier).openFile(path);
    } else if (_mode == SwitcherMode.symbols) {
      final IndexSymbol symbol = item as IndexSymbol;
      ref.read(editorProvider.notifier).openFile(
        symbol.filePath,
        line: symbol.lineNumber - 1,
        column: 0,
      );
    } else if (_mode == SwitcherMode.commands) {
      final IDECommand cmd = item as IDECommand;
      cmd.action();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceRoot = ref.watch(workspaceProvider).currentPath ?? '';
    final l10n = AppLocalizations.of(context)!;

    return KeyboardListener(
      focusNode: _keyboardFocus,
      onKeyEvent: _handleKey,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2230).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search Input Section
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _controller,
                  focusNode: _inputFocus,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.purpleAccent, Colors.cyanAccent],
                      ).createShader(bounds),
                      child: Icon(
                        _mode == SwitcherMode.files 
                            ? LucideIcons.search 
                            : (_mode == SwitcherMode.symbols ? LucideIcons.list : LucideIcons.terminal),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(LucideIcons.x, size: 14, color: Colors.white30),
                            onPressed: () => _controller.clear(),
                          )
                        : null,
                    hintText: _mode == SwitcherMode.files
                        ? l10n.searchFilesHint
                        : (_mode == SwitcherMode.symbols 
                            ? l10n.searchSymbolsHint 
                            : (Localizations.localeOf(context).languageCode == 'ru' ? 'Введите команду...' : 'Type a command...')),
                    hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: Colors.black26,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFFF3C3C), width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              
              // Mode Indicator & Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      _mode == SwitcherMode.files
                          ? l10n.modeFiles
                          : (_mode == SwitcherMode.symbols 
                              ? l10n.modeSymbols 
                              : (Localizations.localeOf(context).languageCode == 'ru' ? 'КОМАНДЫ' : 'COMMANDS')),
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: _mode == SwitcherMode.files 
                            ? Colors.cyanAccent 
                            : (_mode == SwitcherMode.symbols ? Colors.purpleAccent : Colors.greenAccent),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l10n.resultsCount(_results.length),
                      style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white30),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),

              // Search Results List
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noResults,
                          style: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _results.length,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemBuilder: (context, index) {
                          final isSelected = index == _selectedIndex;
                          final item = _results[index];
                          
                          Widget icon;
                          String title;
                          String subtitle;

                          if (_mode == SwitcherMode.files) {
                            final filePath = item as String;
                            final fileName = p.basename(filePath);
                            final iconInfo = FileIconHelper.getIconInfo(fileName, false);
                            
                            icon = Icon(iconInfo.icon, size: 14, color: iconInfo.color);
                            title = fileName;
                            subtitle = workspaceRoot.isNotEmpty && filePath.startsWith(workspaceRoot)
                                ? p.relative(filePath, from: workspaceRoot)
                                : filePath;
                          } else if (_mode == SwitcherMode.symbols) {
                            final symbol = item as IndexSymbol;
                            
                            IconData symIcon;
                            Color symColor;
                            switch (symbol.type) {
                              case 'class':
                                symIcon = LucideIcons.box;
                                symColor = Colors.blueAccent;
                                break;
                              case 'method':
                                symIcon = LucideIcons.braces;
                                symColor = Colors.purpleAccent;
                                break;
                              default:
                                symIcon = LucideIcons.key;
                                symColor = Colors.amberAccent;
                            }
                            
                            icon = Icon(symIcon, size: 14, color: symColor);
                            title = symbol.name;
                            
                            final relPath = workspaceRoot.isNotEmpty && symbol.filePath.startsWith(workspaceRoot)
                                ? p.relative(symbol.filePath, from: workspaceRoot)
                                : symbol.filePath;
                            subtitle = '$relPath : L${symbol.lineNumber}';
                          } else {
                            final cmd = item as IDECommand;
                            icon = Icon(cmd.icon, size: 14, color: cmd.iconColor);
                            title = cmd.title;
                            subtitle = cmd.description;
                          }

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                              _openSelected();
                            },
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? const Color(0xFFFF3C3C).withValues(alpha: 0.12)
                                    : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected ? const Color(0xFFFF3C3C) : Colors.transparent,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  icon,
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          style: GoogleFonts.inter(
                                            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.87),
                                            fontSize: 12.5,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          subtitle,
                                          style: GoogleFonts.inter(
                                            color: isSelected ? Colors.white60 : Colors.white30,
                                            fontSize: 9.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      LucideIcons.corner_down_left,
                                      size: 12,
                                      color: Color(0xFFFF3C3C),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
