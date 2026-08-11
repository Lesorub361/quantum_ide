import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

import 'package:xterm/xterm.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/virtual_keys.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';

import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:flutter/services.dart';

import 'package:quantum_ide/l10n/app_localizations.dart';

import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/apk_signer_widget.dart';

import 'package:quantum_ide/features/editor/presentation/widgets/debugger_panel.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_selection_overlay.dart';

class TerminalPanelContent extends ConsumerStatefulWidget {
  final bool onlyTerminal;
  const TerminalPanelContent({super.key, this.onlyTerminal = false});

  @override
  ConsumerState<TerminalPanelContent> createState() => _TerminalPanelContentState();
}

class _TerminalPanelContentState extends ConsumerState<TerminalPanelContent> {
  final Set<String> _activeModifiers = {};
  bool _isSidebarOpen = false;
  bool _isTerminalSplit = false;
  int _buildSubTab = 0;

  String _currentInput = '';
  final ValueNotifier<List<String>?> _suggestionsNotifier = ValueNotifier(null);
  int _selectedSuggestionIndex = 0;
  List<String> _pathBinaries = [];

  TerminalSession? _lastAttachedSession;
  final Set<TerminalSession> _initializedSessions = {}; // Для контроля слушателей выделения

  final Map<String, GlobalKey<xt.TerminalViewState>> _terminalViewStateKeys = {};

  final ScrollController _terminalScrollController = ScrollController();
  final ScrollController _secondaryScrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _isVirtualKeysCollapsed = false;

  final List<String> _commandHistory = [];
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();
  final List<int> _searchMatches = [];
  int _searchIndex = -1;

  static const List<({String label, String command})> _quickCommands = [
    (label: 'git status', command: 'git status'),
    (label: 'git add . + commit', command: 'git add . && git commit -m "update"'),
    (label: 'flutter run', command: 'flutter run'),
    (label: 'flutter analyze', command: 'flutter analyze'),
    (label: 'flutter pub get', command: 'flutter pub get'),
    (label: 'adb logcat', command: 'adb logcat -v color'),
    (label: 'clear', command: 'clear'),
    (label: 'ls -la', command: 'ls -la'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPathBinaries();
    _terminalScrollController.addListener(_onTerminalScroll);
  }

  void _onTerminalScroll() {
    if (!_terminalScrollController.hasClients) return;
    final pos = _terminalScrollController.position;
    final nearBottom =
        pos.pixels >= pos.maxScrollExtent - 8;
    if (nearBottom != !_showScrollToBottom) {
      setState(() => _showScrollToBottom = !nearBottom);
    }
  }

  void _scrollTerminalToBottom() {
    if (_terminalScrollController.hasClients) {
      _terminalScrollController.jumpTo(
        _terminalScrollController.position.maxScrollExtent,
      );
    }
  }

  @override
  void dispose() {
    _terminalScrollController.dispose();
    _secondaryScrollController.dispose();
    _searchController.dispose();
    _suggestionsNotifier.dispose();
    super.dispose();
  }

  ProjectType _detectProjectType(String? path, ProjectType registeredType) {
    if (registeredType != ProjectType.other) {
      return registeredType;
    }
    if (path == null) return ProjectType.other;
    
    final dir = Directory(path);
    if (!dir.existsSync()) return ProjectType.other;
    
    try {
      final files = dir.listSync();
      bool hasPubspec = false;
      bool hasPackageJson = false;
      bool hasPyFile = false;
      bool hasHtmlFile = false;
      
      for (final file in files) {
        final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
        if (name == 'pubspec.yaml') hasPubspec = true;
        if (name == 'package.json') hasPackageJson = true;
        if (name.endsWith('.py')) hasPyFile = true;
        if (name == 'index.html' || name.endsWith('.html')) hasHtmlFile = true;
      }
      
      if (hasPubspec) return ProjectType.flutter;
      if (hasPackageJson) return ProjectType.nodejs;
      if (hasPyFile) return ProjectType.python;
      if (hasHtmlFile) return ProjectType.web;
    } catch (_) {}
    
    return ProjectType.other;
  }

  Future<void> _loadPathBinaries() async {
    final runtime = ref.read(runtimeServiceProvider);
    final appDir = runtime.appDirectory;

    final pathDirs = [
      p.join(appDir, 'rootfs', 'ubuntu', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'usr', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'usr', 'sbin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'sbin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'usr', 'local', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'root', 'flutter', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'platform-tools'),
    ];

    final binaries = <String>{};
    for (final dirPath in pathDirs) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File) {
              final name = p.basename(entity.path);
              binaries.add(name);
            }
          }
        }
      } catch (_) {}
    }
    _pathBinaries = binaries.toList()..sort();
  }

  String _mapGuestToHostForAutocomplete(String guestPath, RuntimeService runtime) {
    return PathMapper.mapToHost(guestPath, runtime.appDirectory);
  }

  void _handleInputForAutocomplete(TerminalSession session, String data) {
    if (data == '\r' || data == '\n') {
      if (_currentInput.trim().isNotEmpty) {
        _commandHistory.removeWhere((c) => c == _currentInput.trim());
        _commandHistory.insert(0, _currentInput.trim());
        if (_commandHistory.length > 50) _commandHistory.removeLast();
      }
      _suggestionsNotifier.value = null;
      _currentInput = '';
      return;
    }

    if (data == '\x7f' || data == '\b') {
      if (_currentInput.isNotEmpty) {
        _currentInput = _currentInput.substring(0, _currentInput.length - 1);
      }
    } else if (data == '\t') {
      final suggestions = _suggestionsNotifier.value;
      if (suggestions != null && suggestions.isNotEmpty) {
        _acceptSuggestion(session, suggestions[_selectedSuggestionIndex]);
      }
      return;
    } else if (data == ' ' || data.contains('\x1b')) {
      _suggestionsNotifier.value = null;
      _currentInput = '';
      return;
    } else if (data.length == 1 && data.codeUnitAt(0) >= 32) {
      _currentInput += data;
    } else {
      return;
    }

    _updateSuggestions(session);
  }

  Future<void> _updateSuggestions(TerminalSession session) async {
    if (_currentInput.isEmpty) {
      _suggestionsNotifier.value = null;
      return;
    }

    final query = _currentInput.toLowerCase();
    List<String> matches = [];

    if (_currentInput.startsWith('./') ||
        _currentInput.startsWith('/') ||
        _currentInput.startsWith('~/') ||
        _currentInput.contains('/')) {
      matches = await _getPathSuggestions(session, _currentInput);
    } else {
      matches = _pathBinaries
          .where((bin) => bin.toLowerCase().startsWith(query))
          .take(10)
          .toList();
    }

    if (matches.isEmpty) {
      _suggestionsNotifier.value = null;
    } else {
      _selectedSuggestionIndex = 0;
      _suggestionsNotifier.value = matches;
    }
  }

  Future<List<String>> _getPathSuggestions(TerminalSession session, String input) async {
    try {
      final runtime = ref.read(runtimeServiceProvider);
      final workspace = ref.read(workspaceProvider);
      
      final hostProjectDir = workspace.currentPath ?? p.join(runtime.appDirectory, 'projects');
      final hostHomeDir = p.join(runtime.appDirectory, 'rootfs', 'ubuntu', 'root');
      
      String searchPath;
      String prefix = '';

      if (input.startsWith('~/')) {
        searchPath = p.join(hostHomeDir, input.substring(2));
        prefix = '~/';
      } else if (input.startsWith('./')) {
        searchPath = p.join(hostProjectDir, input.substring(2));
        prefix = './';
      } else if (input.startsWith('/')) {
        searchPath = _mapGuestToHostForAutocomplete(input, runtime);
        prefix = '';
      } else {
        searchPath = p.join(hostProjectDir, input);
        prefix = '';
      }

      final lastSlash = searchPath.lastIndexOf('/');
      final dirPath = lastSlash >= 0 ? searchPath.substring(0, lastSlash + 1) : searchPath;
      final partial = lastSlash >= 0 ? searchPath.substring(lastSlash + 1).toLowerCase() : '';

      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final suggestions = <String>[];
      await for (final entity in dir.list()) {
        final name = p.basename(entity.path);
        if (partial.isEmpty || name.toLowerCase().startsWith(partial)) {
          final isDir = entity is Directory;
          String displayPath = prefix;
          if (prefix == '~/') {
            displayPath += p.relative(entity.path, from: hostHomeDir);
          } else if (prefix == './') {
            displayPath += p.relative(entity.path, from: hostProjectDir);
          } else if (input.startsWith('/')) {
            final relativeToRootfs = p.relative(entity.path, from: p.join(runtime.appDirectory, 'rootfs', 'ubuntu'));
            displayPath = relativeToRootfs.startsWith('.') ? entity.path : '/$relativeToRootfs';
          } else {
            displayPath = name;
          }
          suggestions.add(isDir ? '$displayPath/' : displayPath);
        }
      }

      suggestions.sort();
      return suggestions.take(10).toList();
    } catch (_) {
      return [];
    }
  }

  void _acceptSuggestion(TerminalSession session, String suggestion) {
    final toSend = suggestion.substring(_currentInput.length);
    session.pty.write(Uint8List.fromList(utf8.encode(toSend)));
    _currentInput = suggestion;
    _suggestionsNotifier.value = null;
  }

  void _attachTerminalOutputListener(TerminalSession session) {
    session.xtermTerminal.onOutput = (data) {
      final hadCtrl = _activeModifiers.contains('CTRL');
      final hadAlt = _activeModifiers.contains('ALT');
      final hadShift = _activeModifiers.contains('SHIFT');
      
      String sequence = '';
      if (hadCtrl) {
        if (data.length == 1) {
          final int code = data.toUpperCase().codeUnitAt(0);
          if (code >= 65 && code <= 90) {
            sequence = String.fromCharCode(code - 64);
          } else {
            sequence = data;
          }
        } else {
          sequence = data;
        }
      } else if (hadAlt) {
        sequence = '\x1b$data';
      } else if (hadShift) {
        sequence = data.toUpperCase();
      } else {
        sequence = data;
      }

      if (sequence.isNotEmpty) {
        session.pty.write(Uint8List.fromList(utf8.encode(sequence)));
        _handleInputForAutocomplete(session, sequence);
      }

      if (hadCtrl || hadAlt || hadShift) {
        setState(() {
          _activeModifiers.remove('CTRL');
          _activeModifiers.remove('ALT');
          _activeModifiers.remove('SHIFT');
        });
      }
    };
  }

  void _onKeyTap(String value, TerminalSession session) async {
    final term = session.xtermTerminal;
    if (value == 'ctrl') {
      setState(() {
        if (_activeModifiers.contains('CTRL')) {
          _activeModifiers.remove('CTRL');
        } else {
          _activeModifiers.clear();
          _activeModifiers.add('CTRL');
        }
      });
      return;
    }
    if (value == 'ALT') {
      setState(() {
        if (_activeModifiers.contains('ALT')) {
          _activeModifiers.remove('ALT');
        } else {
          _activeModifiers.clear();
          _activeModifiers.add('ALT');
        }
      });
      return;
    }
    if (value == 'SHIFT') {
      setState(() {
        if (_activeModifiers.contains('SHIFT')) {
          _activeModifiers.remove('SHIFT');
        } else {
          _activeModifiers.clear();
          _activeModifiers.add('SHIFT');
        }
      });
      return;
    }
    if (value == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        session.pty.write(Uint8List.fromList(utf8.encode(data.text!)));
      }
      return;
    }
    
    if (value == 'ctrl+c') {
      session.pty.write(Uint8List.fromList([3])); 
      return;
    }
    if (value == 'ctrl+d') {
      session.pty.write(Uint8List.fromList([4])); 
      return;
    }
    if (value == 'ctrl+l') {
      session.pty.write(Uint8List.fromList([12])); 
      return;
    }
    
    if (value == '\x7f') {
      session.pty.write(Uint8List.fromList([127]));
      _handleInputForAutocomplete(session, '\x7f');
      return;
    }

    final hadCtrl = _activeModifiers.contains('CTRL');
    final hadAlt = _activeModifiers.contains('ALT');
    final hadShift = _activeModifiers.contains('SHIFT');
    if (hadCtrl) _activeModifiers.remove('CTRL');
    if (hadAlt) _activeModifiers.remove('ALT');
    if (hadShift) _activeModifiers.remove('SHIFT');

    if (value == '\t') {
      final suggestions = _suggestionsNotifier.value;
      if (suggestions != null && suggestions.isNotEmpty) {
        _acceptSuggestion(session, suggestions[_selectedSuggestionIndex]);
        return;
      }
      term.keyInput(xt.TerminalKey.tab, ctrl: hadCtrl, alt: hadAlt, shift: hadShift);
    } else if (value == '\x1b') {
      term.keyInput(xt.TerminalKey.escape, ctrl: hadCtrl, alt: hadAlt, shift: hadShift);
    } else if (value == '\x1b[A') {
      term.keyInput(xt.TerminalKey.arrowUp, ctrl: hadCtrl, alt: hadAlt, shift: hadShift);
    } else if (value == '\x1b[B') {
      term.keyInput(xt.TerminalKey.arrowDown, ctrl: hadCtrl, alt: hadAlt, shift: hadShift);
    } else if (value == '\x1b[D') {
      term.keyInput(xt.TerminalKey.arrowLeft, ctrl: hadCtrl, alt: hadAlt, shift: hadShift);
    } else if (value == '\x1b[C') {
      term.keyInput(xt.TerminalKey.arrowRight, ctrl: hadCtrl, alt: hadAlt, shift: hadShift);
    } else if (value == '\x1b[H') {
      session.pty.write(Uint8List.fromList(utf8.encode('\x1b[H')));
    } else if (value == '\x1b[F') {
      session.pty.write(Uint8List.fromList(utf8.encode('\x1b[F')));
    } else if (value.length == 1 && hadCtrl) {
      final code = value.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        session.pty.write(Uint8List.fromList([code - 64]));
      } else {
        session.pty.write(Uint8List.fromList(utf8.encode(value)));
      }
    } else if (value.length == 1 && hadAlt) {
      session.pty.write(Uint8List.fromList(utf8.encode('\x1b$value')));
    } else {
      session.pty.write(Uint8List.fromList(utf8.encode(value)));
      _handleInputForAutocomplete(session, value);
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final panelState = ref.watch(panelProvider);
    final sessions = ref.watch(terminalTabsProvider);
    final notifier = ref.read(terminalTabsProvider.notifier);
    final editorState = ref.watch(editorProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F14), 
      ),
      child: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: widget.onlyTerminal
                  ? _buildTerminalView(sessions, notifier, key: const ValueKey('terminal'))
                  : _buildBody(panelState, sessions, notifier, editorState),
            ),
            if ((widget.onlyTerminal || panelState.selectedTab == PanelTab.terminal) &&
                !(Platform.isLinux || Platform.isWindows || Platform.isMacOS || MediaQuery.of(context).size.width > 800))
              _isVirtualKeysCollapsed
                  ? const SizedBox.shrink()
                  : _buildVirtualKeys(sessions, notifier),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PanelState state, List<TerminalSession> sessions, TerminalTabsNotifier notifier, EditorState editorState) {
    const tabs = PanelTab.values;
    final index = tabs.indexOf(state.selectedTab);

    return IndexedStack(
      index: index,
      children: tabs.map((tab) => _getTabWidget(tab, sessions, notifier, editorState)).toList(),
    );
  }

  Widget _getTabWidget(PanelTab tab, List<TerminalSession> sessions, TerminalTabsNotifier notifier, EditorState editorState) {
    switch (tab) {
      case PanelTab.terminal:
        return _buildTerminalView(sessions, notifier, key: const ValueKey('terminal'));
      case PanelTab.run:
        return _buildRunView(key: const ValueKey('run'));
      case PanelTab.buildLogs:
        return _buildBuildLogsView(key: const ValueKey('buildLogs'));
      case PanelTab.appLogs:
        return _buildAppLogsView(key: const ValueKey('appLogs'));
      case PanelTab.problems:
        return _buildProblemsView(editorState);
      case PanelTab.git:
        return _buildGitView();
      case PanelTab.debug:
        return const DebuggerPanel(key: ValueKey('debug'));
    }
  }

  Widget _buildGitView() {
    final l10n = AppLocalizations.of(context)!;
    final gitState = ref.watch(gitProvider);
    final gitNotifier = ref.read(gitProvider.notifier);

    if (gitState.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
    }

    if (gitState.status == null) {
      return Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.15)),
                  ),
                  child: const Icon(LucideIcons.git_branch, color: Colors.amberAccent, size: 38),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.repositoryNotFound,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.initGitRepoDescription,
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => gitNotifier.init(),
                  icon: const Icon(LucideIcons.git_fork, size: 14),
                  label: Text(l10n.initGitAction),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent.withValues(alpha: 0.15),
                    foregroundColor: Colors.amberAccent,
                    elevation: 0,
                    side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final status = gitState.status!;

    return RefreshIndicator(
      onRefresh: () => gitNotifier.refreshStatus(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(LucideIcons.git_branch, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                status.currentBranch,
                style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, size: 14, color: Colors.white38),
                onPressed: () => gitNotifier.refreshStatus(),
              ),
            ],
          ),
          const Divider(color: Colors.white10),
          if (status.conflictedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitConflicted, status.conflictedFiles.length),
            ...status.conflictedFiles.map((f) => _buildGitFileItem(f, isStaged: false, isConflicted: true)),
          ],
          if (status.stagedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitStaged, status.stagedFiles.length),
            ...status.stagedFiles.map((f) => _buildGitFileItem(f, isStaged: true)),
          ],
          if (status.modifiedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitModified, status.modifiedFiles.length),
            ...status.modifiedFiles.map((f) => _buildGitFileItem(f, isStaged: false)),
          ],
          if (status.untrackedFiles.isNotEmpty) ...[
            _buildGitSectionHeader(l10n.gitUntracked, status.untrackedFiles.length),
            ...status.untrackedFiles.map((f) => _buildGitFileItem(f, isStaged: false, isUntracked: true)),
          ],
          const SizedBox(height: 20),
          if (status.hasChanges) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.commitMessageHint,
                      hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), 
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), 
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8), 
                        borderSide: const BorderSide(color: Colors.amberAccent, width: 0.8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    onSubmitted: (msg) {
                      if (msg.isNotEmpty) {
                        gitNotifier.commit(msg);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => gitNotifier.push(),
                          icon: const Icon(LucideIcons.arrow_up, size: 14),
                          label: const Text('Push'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent.withValues(alpha: 0.15), 
                            foregroundColor: Colors.blueAccent,
                            elevation: 0,
                            side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.25)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => gitNotifier.pull(),
                          icon: const Icon(LucideIcons.arrow_down, size: 14),
                          label: const Text('Pull'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent.withValues(alpha: 0.15), 
                            foregroundColor: Colors.greenAccent,
                            elevation: 0,
                            side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.25)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGitSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Text(
            title, 
            style: GoogleFonts.inter(
              fontSize: 10, 
              color: Colors.white24, 
              fontWeight: FontWeight.bold, 
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05), 
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Text(
              '$count', 
              style: GoogleFonts.inter(fontSize: 9, color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitFileItem(String path, {required bool isStaged, bool isUntracked = false, bool isConflicted = false}) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(gitProvider.notifier);
    final Color statusColor = isConflicted 
        ? Colors.redAccent 
        : (isStaged ? Colors.greenAccent : (isUntracked ? Colors.orangeAccent : Colors.amberAccent));
    final String statusLabel = isConflicted
        ? 'CONFLICT'
        : (isStaged ? 'STAGED' : (isUntracked ? 'UNTRACKED' : 'MODIFIED'));
    
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: statusColor),
            Expanded(
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 12, right: 6),
                leading: Icon(
                  isConflicted
                      ? LucideIcons.git_pull_request
                      : (isUntracked ? LucideIcons.file_plus : LucideIcons.file_text),
                  size: 16,
                  color: statusColor,
                ),
                title: Text(
                  path.split('/').last, 
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  path, 
                  style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white24),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  if (isConflicted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GitMergeConflictPage(relativePath: path),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GitDiffPage(relativePath: path, initiallyStaged: isStaged),
                      ),
                    );
                  }
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.inter(color: statusColor, fontSize: 7, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isConflicted)
                      IconButton(
                        icon: const Icon(LucideIcons.git_pull_request, size: 14, color: Colors.redAccent),
                        tooltip: l10n.resolveConflictTooltip,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => GitMergeConflictPage(relativePath: path),
                            ),
                          );
                        },
                      )
                    else
                      IconButton(
                        icon: Icon(isStaged ? LucideIcons.minus : LucideIcons.plus, size: 14, color: Colors.white54),
                        tooltip: isStaged ? l10n.unstageAction : l10n.stageAction,
                        onPressed: () => isStaged ? notifier.unstageFile(path) : notifier.stageFile(path),
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

  Widget _buildRunView({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final dedicatedState = ref.watch(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[DedicatedTerminalType.run];
    final workspaceState = ref.watch(workspaceProvider);
    final allProjects = ref.watch(projectServiceProvider);

    final currentProject = allProjects.firstWhere(
      (p) => p.path == workspaceState.currentPath,
      orElse: () => Project(
        id: '',
        name: 'Default',
        path: workspaceState.currentPath ?? '',
        type: ProjectType.other,
        lastOpened: DateTime.now(),
      ),
    );

    final projectType = _detectProjectType(workspaceState.currentPath, currentProject.type);
    final String title;
    final List<Widget> actions = [];

    switch (projectType) {
      case ProjectType.flutter:
        title = l10n.flutterProject;
        if (Platform.isAndroid) {
          actions.addAll([
            _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
                () => _runDedicatedCommand(DedicatedTerminalType.run, 'flutter run -d web-server --web-port 8080')),
            _buildActionButton('Hot Reload', LucideIcons.zap, Colors.yellow, 
                () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, 'r')),
            _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
                () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, 'q')),
          ]);
        } else {
          actions.addAll([
            _buildActionButton(l10n.runPC, LucideIcons.laptop, Colors.cyanAccent, 
                () => _runDedicatedCommand(DedicatedTerminalType.run, 'flutter run -d linux')),
            _buildActionButton(l10n.runMob, LucideIcons.smartphone, Colors.greenAccent, 
                () => _runDedicatedCommand(DedicatedTerminalType.run, 'flutter run -d android')),
            _buildActionButton('Hot Reload', LucideIcons.zap, Colors.yellow, 
                () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, 'r')),
            _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
                () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, 'q')),
          ]);
        }
        break;
      case ProjectType.python:
        title = l10n.pythonProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'python3 main.py || python3 app.py || (py_file=\$(find . -maxdepth 2 -name "*.py" | head -n 1); if [ -n "\$py_file" ]; then python3 "\$py_file"; else echo "No python file found. Please create main.py"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), 
        ]);
        break;
      case ProjectType.nodejs:
        title = l10n.nodejsProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'npm start || node index.js || node server.js || node app.js || (js_file=\$(find . -maxdepth 2 -name "*.js" ! -path "*/node_modules/*" | head -n 1); if [ -n "\$js_file" ]; then node "\$js_file"; else echo "No JS file found. Please create index.js or package.json"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), 
        ]);
        break;
      case ProjectType.dart:
        title = l10n.dartProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'dart run || dart bin/main.dart || dart main.dart || (dart_file=\$(find . -maxdepth 2 -name "*.dart" | head -n 1); if [ -n "\$dart_file" ]; then dart "\$dart_file"; else echo "No Dart file found. Please create bin/main.dart"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), 
        ]);
        break;
      case ProjectType.web:
        title = l10n.webProject;
        actions.addAll([
          _buildActionButton(l10n.startServer, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'python3 -m http.server 8080 || npx http-server -p 8080 || npx serve -p 8080')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), 
        ]);
        break;
      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        title = l10n.androidProject;
        actions.addAll([
          _buildActionButton(l10n.buildAPK, LucideIcons.box, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 'chmod +x gradlew && ./gradlew assembleDebug')),
          _buildActionButton(l10n.install, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 'chmod +x gradlew && ./gradlew installDebug')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), 
        ]);
        break;
      case ProjectType.shell:
      case ProjectType.other:
        title = l10n.genericProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'bash main.sh || bash run.sh || ./run.sh || ./main.sh || (sh_file=\$(find . -maxdepth 2 -name "*.sh" | head -n 1); if [ -n "\$sh_file" ]; then bash "\$sh_file"; else echo "No run script (.sh) found."; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), 
        ]);
        break;
      case ProjectType.rust:
        title = l10n.rustProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 'cargo run')),
          _buildActionButton(l10n.buildPC, LucideIcons.laptop, Colors.cyanAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 'cargo build')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))),
        ]);
        break;
    }

    actions.add(
      _buildActionButton(l10n.copy, LucideIcons.copy, Colors.white60, () => _copyTerminalOutput(DedicatedTerminalType.run))
    );

    return Column(
      children: [
        _buildActionHeader(title, actions),
        Expanded(
          child: session != null 
            ? _buildTerminalWidget(session)
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.rocket, size: 48, color: Colors.white10),
                    const SizedBox(height: 12),
                    Text(AppLocalizations.of(context)!.typeRunToStart, style: const TextStyle(color: Colors.white24, fontSize: 12)),
                  ],
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildSubTabButton(int index, String label, IconData icon) {
    final isActive = _buildSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _buildSubTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? Colors.cyanAccent.withValues(alpha: 0.25) : Colors.transparent,
            width: 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? Colors.cyanAccent : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive ? Colors.white : Colors.white38,
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildLogsView({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final dedicatedState = ref.watch(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[DedicatedTerminalType.build];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.01),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              _buildSubTabButton(0, l10n.console, LucideIcons.terminal),
              const SizedBox(width: 8),
              _buildSubTabButton(1, l10n.signApk, LucideIcons.pen_tool),
            ],
          ),
        ),
        Expanded(
          child: _buildSubTab == 0
              ? Column(
                  children: [
                    _buildActionHeader(l10n.build, [
                      if (Platform.isAndroid) ...[
                        _buildActionButton('APK', LucideIcons.package, Colors.orange, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
                      ] else ...[
                        _buildActionButton(l10n.buildPC, LucideIcons.laptop, Colors.cyanAccent, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get && flutter build linux --release')),
                        _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
                      ],
                      _buildActionButton('Pub Get', LucideIcons.download, Colors.blue, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get')),
                      _buildActionButton('Clean', LucideIcons.trash_2, Colors.red, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter clean')),
                      _buildActionButton(l10n.copy, LucideIcons.copy, Colors.white60, () => _copyTerminalOutput(DedicatedTerminalType.build)),
                    ]),
                    Expanded(
                      child: session != null 
                        ? _buildTerminalWidget(session)
                        : Center(child: Text(l10n.buildLogs, style: const TextStyle(color: Colors.white38))),
                    ),
                  ],
                )
              : const ApkSignerWidget(),
        ),
      ],
    );
  }

  Widget _buildAppLogsView({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final dedicatedState = ref.watch(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[DedicatedTerminalType.appLogs];

    return Column(
      children: [
        _buildActionHeader(l10n.appLogs, [
          _buildActionButton('Logs', LucideIcons.list, Colors.cyanAccent, () => _runDedicatedCommand(DedicatedTerminalType.appLogs, 'flutter logs')),
          _buildActionButton(l10n.copy, LucideIcons.copy, Colors.white60, () => _copyTerminalOutput(DedicatedTerminalType.appLogs)),
          _buildActionButton(l10n.setupSdk, LucideIcons.settings, Colors.purpleAccent, () => _runDedicatedCommand(DedicatedTerminalType.appLogs, 'kill -9 \$(pgrep -x "apt|apt-get|dpkg|dpkg-deb" 2>/dev/null) 2>/dev/null ; rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null ; dpkg --configure -a 2>/dev/null ; apt update && apt install -y debianutils libz1 libexpat1 openjdk-21-jdk wget unzip libstdc++6 zlib1g zlib1g-dev libncurses6 libtinfo6 libc++1 libc6 aapt adb zipalign apksigner clang lld cmake ninja-build pkg-config libgtk-3-dev && git config --global --add safe.directory \'*\' && flutter config --android-sdk /root/android-sdk && (which which >/dev/null || (echo "#!/bin/sh" > /usr/bin/which && echo "command -v \$1" >> /usr/bin/which && chmod +x /usr/bin/which))')),
        ]),
        Expanded(
          child: session != null 
            ? _buildTerminalWidget(session)
            : Center(child: Text(l10n.appLogs, style: const TextStyle(color: Colors.white38))),
        ),
      ],
    );
  }

  Widget _buildActionHeader(String title, List<Widget> actions) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title.toUpperCase(), 
              style: GoogleFonts.inter(
                color: Colors.cyanAccent, 
                fontSize: 9, 
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1
              )
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: actions,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 14, color: color.withValues(alpha: 0.9)),
            ),
          ),
        ),
      ),
    );
  }

  void _runDedicatedCommand(DedicatedTerminalType type, String cmd) {
    final workspace = ref.read(workspaceProvider);
    final path = workspace.currentPath;
    
    final finalCmd = path != null ? 'cd "$path" && clear && $cmd' : 'clear && $cmd';
    ref.read(dedicatedTerminalProvider.notifier).sendCommand(type, finalCmd, interrupt: true, clear: false);
  }

  void _sendRawKeyToDedicatedTerminal(DedicatedTerminalType type, String key) {
    ref.read(dedicatedTerminalProvider.notifier).sendRawChar(type, key);
  }

  String _extractTerminalText(xt.Terminal terminal) {
    final buffer = terminal.buffer;
    final lines = <String>[];
    for (var i = 0; i < buffer.lines.length; i++) {
      lines.add(buffer.lines[i].toString());
    }
    return lines.join('\n');
  }

  Future<void> _copyTerminalOutput(DedicatedTerminalType type) async {
    final dedicatedState = ref.read(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[type];
    if (session == null) return;

    final text = _extractTerminalText(session.xtermTerminal);

    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.copiedToClipboard), duration: const Duration(seconds: 1)),
        );
      }
    }
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 12, color: color ?? Colors.white38),
        ),
      ),
    );
  }

  Future<void> _copyTerminalSessionOutput(TerminalSession session) async {
    final selection = session.xtermViewController.selection;
    final String text;
    if (selection != null) {
      text = session.xtermTerminal.buffer.getText(selection);
      session.xtermViewController.clearSelection();
    } else {
      text = _extractTerminalText(session.xtermTerminal);
    }
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.copiedToClipboard), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _pasteToTerminalSession(TerminalSession session) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      session.pty.write(Uint8List.fromList(utf8.encode(data.text!)));
    }
  }

  void _runSearchQuery(TerminalSession session, String query) {
    _searchMatches.clear();
    _searchIndex = -1;
    if (query.isEmpty) {
      setState(() {});
      return;
    }
    final buffer = session.xtermTerminal.buffer;
    final q = query.toLowerCase();
    for (var i = 0; i < buffer.lines.length; i++) {
      if (buffer.lines[i].toString().toLowerCase().contains(q)) {
        _searchMatches.add(i);
      }
    }
    if (_searchMatches.isNotEmpty) _searchIndex = 0;
    setState(() {});
  }

  void _jumpToSearchMatch(TerminalSession session, int delta) {
    if (_searchMatches.isEmpty) return;
    _searchIndex = (_searchIndex + delta) % _searchMatches.length;
    if (_searchIndex < 0) _searchIndex = _searchMatches.length - 1;
    setState(() {});
  }

  void _openSearch(TerminalSession session) {
    setState(() {
      _showSearchBar = !_showSearchBar;
      if (!_showSearchBar) {
        _searchController.clear();
        _runSearchQuery(session, '');
      }
    });
  }

  void _sendQuickCommand(TerminalSession session, String command) {
    _commandHistory.removeWhere((c) => c == command);
    _commandHistory.insert(0, command);
    if (_commandHistory.length > 50) _commandHistory.removeLast();
    session.pty.write(Uint8List.fromList(utf8.encode('$command\n')));
  }

  Future<void> _showCommandHistory(TerminalSession session) async {
    if (_commandHistory.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.noCommandHistory),
            duration: const Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.of(context)!.commandHistory,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _commandHistory.length,
                itemBuilder: (ctx, index) {
                  final cmd = _commandHistory[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.terminal,
                        size: 14, color: Colors.cyanAccent),
                    title: Text(
                      cmd,
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(ctx, cmd),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      _sendQuickCommand(session, selected);
    }
  }

  Widget _buildSearchOverlay(TerminalSession session) {
    if (!_showSearchBar) return const SizedBox.shrink();
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Material(
        color: const Color(0xFF1E1E24).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Icon(LucideIcons.search, size: 14, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: GoogleFonts.jetBrainsMono(
                      color: Colors.white, fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search...',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                  onChanged: (v) => _runSearchQuery(session, v),
                ),
              ),
              if (_searchMatches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '${_searchIndex + 1}/${_searchMatches.length}',
                    style: GoogleFonts.jetBrainsMono(
                        color: Colors.cyanAccent, fontSize: 10),
                  ),
                ),
              IconButton(
                icon: const Icon(LucideIcons.chevron_up,
                    size: 16, color: Colors.white54),
                onPressed: () => _jumpToSearchMatch(session, -1),
              ),
              IconButton(
                icon: const Icon(LucideIcons.chevron_down,
                    size: 16, color: Colors.white54),
                onPressed: () => _jumpToSearchMatch(session, 1),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                onPressed: () => _openSearch(session),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollToBottomButton() {
    if (!_showScrollToBottom) return const SizedBox.shrink();
    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        color: const Color(0xFF1E1E24).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        elevation: 4,
        child: InkWell(
          onTap: _scrollTerminalToBottom,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(LucideIcons.arrow_down_to_line,
                size: 18, color: Colors.cyanAccent),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickCommands(TerminalSession session) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                AppLocalizations.of(context)!.quickCommands,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _quickCommands.length,
                itemBuilder: (ctx, index) {
                  final cmd = _quickCommands[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.zap,
                        size: 14, color: Colors.amberAccent),
                    title: Text(
                      cmd.label,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      cmd.command,
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white38,
                        fontSize: 9,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(ctx, cmd.command),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      _sendQuickCommand(session, selected);
    }
  }

  Widget _buildTerminalView(List<TerminalSession> sessions, TerminalTabsNotifier notifier, {Key? key}) {
    if (sessions.isEmpty) return const Center(child: CircularProgressIndicator());
    final currentSession = sessions[notifier.currentIndex];

    return Row(
      key: key,
      children: [
        if (_isSidebarOpen)
          GlassContainer(
            blur: 15,
            opacity: 0.08,
            borderRadius: BorderRadius.zero,
            border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            child: SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Text('SESSIONS', style: GoogleFonts.inter(
                          color: Colors.white24, 
                          fontSize: 10, 
                          fontWeight: FontWeight.bold, 
                          letterSpacing: 1.2
                        )),
                        const Spacer(),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => notifier.createNewSession(),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              child: const Icon(LucideIcons.plus, size: 14, color: Colors.cyanAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final isActive = index == notifier.currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.cyanAccent.withValues(alpha: 0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.transparent
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              LucideIcons.terminal, 
                              size: 14, 
                              color: isActive ? Colors.cyanAccent : Colors.white24
                            ),
                            title: Text(
                              sessions[index].title,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: isActive ? Colors.white : Colors.white38,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              sessions[index].isExited ? 'Stopped' : 'Running',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: sessions[index].isExited ? Colors.redAccent.withValues(alpha: 0.5) : Colors.greenAccent.withValues(alpha: 0.5),
                              ),
                            ),
                            onTap: () => notifier.currentIndex = index,
                            trailing: isActive ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    sessions[index].isExited ? LucideIcons.play : LucideIcons.refresh_cw,
                                    size: 12,
                                    color: sessions[index].isExited ? Colors.greenAccent : Colors.white38,
                                  ),
                                  onPressed: () => notifier.restartSession(index),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  tooltip: sessions[index].isExited 
                                      ? AppLocalizations.of(context)!.start 
                                      : AppLocalizations.of(context)!.restartTerminalTooltip,
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(LucideIcons.trash_2, size: 12, color: Colors.redAccent),
                                  onPressed: () => notifier.closeSession(index),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                  tooltip: AppLocalizations.of(context)!.delete,
                                ),
                              ],
                            ) : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              LucideIcons.menu,
                              size: 16,
                              color: _isSidebarOpen ? Colors.cyanAccent : Colors.white54,
                            ),
                          ),
                        ),
                        if (sessions.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.purpleAccent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                              child: Text(
                                '${sessions.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      currentSession.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ref.watch(workspaceProvider).currentPath?.split('/').last ?? 'root',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white38,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildZoomButton(LucideIcons.zoom_out, () {
                      final size = ref.read(settingsProvider).terminalFontSize;
                      ref.read(settingsProvider.notifier).setTerminalFontSize((size - 1).clamp(8.0, 24.0));
                    }),
                    const SizedBox(width: 4),
                    Text(
                      '${ref.watch(settingsProvider).terminalFontSize.toInt()}',
                      style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    _buildZoomButton(LucideIcons.zoom_in, () {
                      final size = ref.read(settingsProvider).terminalFontSize;
                      ref.read(settingsProvider.notifier).setTerminalFontSize((size + 1).clamp(8.0, 24.0));
                    }),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.plus, () {
                      notifier.createNewSession();
                    }, color: Colors.cyanAccent),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.copy, () {
                      _copyTerminalSessionOutput(currentSession);
                    }, color: Colors.cyanAccent),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.clipboard_paste, () {
                      _pasteToTerminalSession(currentSession);
                    }, color: Colors.white70),
                    const SizedBox(width: 8),
                    _buildZoomButton(_isTerminalSplit ? LucideIcons.square : LucideIcons.columns_2, () {
                      setState(() {
                        _isTerminalSplit = !_isTerminalSplit;
                        if (_isTerminalSplit && sessions.length < 2) {
                          notifier.createNewSession();
                        }
                      });
                    }),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.search, () {
                      _openSearch(currentSession);
                    }, color: Colors.white70),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.history, () {
                      _showCommandHistory(currentSession);
                    }, color: Colors.white70),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.zap, () {
                      _showQuickCommands(currentSession);
                    }, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    _buildZoomButton(
                      _isVirtualKeysCollapsed
                          ? LucideIcons.keyboard
                          : LucideIcons.keyboard_off,
                      () {
                        setState(() =>
                            _isVirtualKeysCollapsed = !_isVirtualKeysCollapsed);
                      },
                      color: _isVirtualKeysCollapsed
                          ? Colors.white54
                          : Colors.cyanAccent,
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => notifier.sendCommand('clear\n'),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text('CLR', style: GoogleFonts.inter(
                            color: Colors.white24, 
                            fontSize: 9, 
                            fontWeight: FontWeight.bold,
                          )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: (_isTerminalSplit && sessions.length >= 2)
                    ? Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  color: Colors.white.withValues(alpha: 0.02),
                                  width: double.infinity,
                                  child: Text(
                                    '${AppLocalizations.of(context)!.panel1}: ${sessions[notifier.currentIndex].title}',
                                    style: GoogleFonts.inter(fontSize: 8.5, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Expanded(child: _buildTerminalWidget(sessions[notifier.currentIndex])),
                              ],
                            ),
                          ),
                          Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  color: Colors.white.withValues(alpha: 0.02),
                                  width: double.infinity,
                                  child: Row(
                                    children: [
                                      Text(
                                        '${AppLocalizations.of(context)!.panel2}: ${sessions[(notifier.currentIndex + 1) % sessions.length].title}',
                                        style: GoogleFonts.inter(fontSize: 8.5, color: Colors.cyanAccent.withValues(alpha: 0.7), fontWeight: FontWeight.bold),
                                      ),
                                      const Spacer(),
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _isTerminalSplit = false;
                                          });
                                        },
                                        child: const Icon(LucideIcons.x, size: 10, color: Colors.white38),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(child: _buildTerminalWidget(sessions[(notifier.currentIndex + 1) % sessions.length], isSecondary: true)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : _buildTerminalWidget(currentSession),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalWidget(TerminalSession session, {bool isSecondary = false}) {
    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _getTerminalTheme(terminalThemeName);
    final scrollController =
        isSecondary ? _secondaryScrollController : _terminalScrollController;

    if (!isSecondary) {
      if (_lastAttachedSession != session) {
        _lastAttachedSession = session;
        _currentInput = '';
        _suggestionsNotifier.value = null;
        _attachTerminalOutputListener(session);
      }

      // Чистим слушателей закрытых сессий, чтобы не копить память
      final active = ref.read(terminalTabsProvider).toSet();
      _initializedSessions.removeWhere((s) => !active.contains(s));
    } else {
      session.xtermTerminal.onOutput = (data) {
        final hadCtrl = _activeModifiers.contains('CTRL');
        final hadAlt = _activeModifiers.contains('ALT');
        final hadShift = _activeModifiers.contains('SHIFT');
        String sequence = '';
        if (hadCtrl) {
          if (data.length == 1) {
            final int code = data.toUpperCase().codeUnitAt(0);
            if (code >= 65 && code <= 90) {
              sequence = String.fromCharCode(code - 64);
            } else {
              sequence = data;
            }
          } else {
            sequence = data;
          }
        } else if (hadAlt) {
          sequence = '\x1b$data';
        } else if (hadShift) {
          sequence = data.toUpperCase();
        } else {
          sequence = data;
        }
        if (sequence.isNotEmpty) {
          session.pty.write(Uint8List.fromList(utf8.encode(sequence)));
        }
        if (hadCtrl || hadAlt || hadShift) {
          setState(() {
            _activeModifiers.remove('CTRL');
            _activeModifiers.remove('ALT');
            _activeModifiers.remove('SHIFT');
          });
        }
      };
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (isSecondary) return;
        _onHorizontalSwipe(details.primaryVelocity ?? 0, session);
      },
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                  ),
                  clipBehavior: Clip.antiAlias,
child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (_) => _pinchBaseFontSize = terminalFontSize,
                      onScaleUpdate: (details) {
                        if (details.scale != 1.0) {
                          _applyPinchZoom(details.scale);
                        }
                      },
                      child: TerminalSelectionOverlay(
                        session: session,
                        terminalKey: _terminalViewStateKeys[session.id] ??=
                            GlobalKey<xt.TerminalViewState>(),
                        scrollController: scrollController,
                        child: xt.TerminalView(
                          session.xtermTerminal,
                          controller: session.xtermViewController,
                          autofocus: true,
                          padding: const EdgeInsets.all(12),
                          theme: theme,
                          backgroundOpacity: 0,
                          textStyle: xt.TerminalStyle(
                            fontSize: terminalFontSize,
                            fontFamily: _getFontFamily(ref.watch(settingsProvider).terminalFontFamily),
                            fontFamilyFallback: const [
                              'monospace',
                              'sans-serif',
                              'Roboto Mono',
                              'Droid Sans Mono',
                              'Noto Sans Mono',
                            ],
                          ),
                          keyboardType: TextInputType.visiblePassword,
                          deleteDetection: true,
                          scrollController: scrollController,
                          onSecondaryTapDown: (details, _) =>
                              _showTerminalContextMenu(context, details.globalPosition, session),
                        ),
                      ),
                    ),
                ),
              ),
            ],
          ),
          _buildSearchOverlay(session),
          _buildScrollToBottomButton(),
          _buildSuggestionBox(session),
        ],
      ),
    );
  }

  double? _pinchBaseFontSize;

  void _applyPinchZoom(double scale) {
    final base = _pinchBaseFontSize;
    if (base == null) return;
    final newSize = (base * scale).clamp(8.0, 24.0);
    ref.read(settingsProvider.notifier).setTerminalFontSize(newSize);
  }

  void _onHorizontalSwipe(double velocity, TerminalSession session) {
    if (velocity.abs() < 300) return;
    final notifier = ref.read(terminalTabsProvider.notifier);
    final sessions = ref.read(terminalTabsProvider);
    if (sessions.isEmpty) return;
    if (velocity > 0) {
      // свайп вправо → предыдущая сессия
      notifier.currentIndex =
          (notifier.currentIndex - 1 + sessions.length) % sessions.length;
    } else {
      // свайп влево → следующая сессия
      notifier.currentIndex = (notifier.currentIndex + 1) % sessions.length;
    }
    _scrollTerminalToBottom();
  }

  Widget _buildSuggestionBox(TerminalSession session) {
    return ValueListenableBuilder<List<String>?>(
      valueListenable: _suggestionsNotifier,
      builder: (context, suggestions, _) {
        if (suggestions == null || suggestions.isEmpty) {
          _selectedSuggestionIndex = 0;
          return const SizedBox.shrink();
        }

        return _SuggestionBox(
          suggestions: suggestions,
          selectedSuggestionIndex: _selectedSuggestionIndex,
          session: session,
          onAccept: _acceptSuggestion,
        );
      },
    );
  }

  xt.TerminalTheme _getTerminalTheme(String themeName) {
    Color bg;
    Color fg = Colors.white;
    switch (themeName) {
      case 'dracula':
        bg = const Color(0xFF282A36);
        fg = const Color(0xFFF8F8F2);
        break;
      case 'monokai':
        bg = const Color(0xFF272822);
        fg = const Color(0xFFF8F8F2);
        break;
      case 'dark':
        bg = const Color(0xFF0D0F14);
        fg = const Color(0xFFE0E0E0);
        break;
      case 'ubuntu':
      default:
        bg = const Color(0xFF300A24);
        fg = Colors.white;
        break;
    }

    return xt.TerminalTheme(
      cursor: fg,
      selection: fg.withValues(alpha: 0.25),
      foreground: fg,
      background: bg,
      black: Colors.black,
      red: const Color(0xFFCC0000),
      green: const Color(0xFF4E9A06),
      yellow: const Color(0xFFC4A000),
      blue: const Color(0xFF3465A4),
      magenta: const Color(0xFF75507B),
      cyan: const Color(0xFF06989A),
      white: const Color(0xFFD3D7CF),
      brightBlack: const Color(0xFF555753),
      brightRed: const Color(0xFFEF2929),
      brightGreen: const Color(0xFF8AE234),
      brightYellow: const Color(0xFFFCE94F),
      brightBlue: const Color(0xFF729FCF),
      brightMagenta: const Color(0xFFAD7FA8),
      brightCyan: const Color(0xFF34E2E2),
      brightWhite: const Color(0xFFEEEEEC),
      searchHitBackground: Colors.yellow,
      searchHitBackgroundCurrent: Colors.orange,
      searchHitForeground: Colors.black,
    );
  }

  Future<String> _detectProjectCheckCommand(String? workspacePath) async {
    if (workspacePath == null) return 'flutter analyze';
    try {
      final dir = Directory(workspacePath);
      if (!await dir.exists()) return 'flutter analyze';
      
      final pubspec = File(p.join(workspacePath, 'pubspec.yaml'));
      if (await pubspec.exists()) {
        final content = await pubspec.readAsString();
        if (content.contains('sdk: flutter') || content.contains('flutter:')) {
          return 'flutter analyze';
        }
        return 'dart analyze';
      }
      
      final packageJson = File(p.join(workspacePath, 'package.json'));
      if (await packageJson.exists()) {
        final tsconfig = File(p.join(workspacePath, 'tsconfig.json'));
        if (await tsconfig.exists()) {
          return 'npx tsc --noEmit';
        }
        return 'npm run build';
      }
      
      final cargo = File(p.join(workspacePath, 'Cargo.toml'));
      if (await cargo.exists()) {
        return 'cargo check';
      }
      
      final goMod = File(p.join(workspacePath, 'go.mod'));
      if (await goMod.exists()) {
        return 'go vet ./...';
      }

      final buildGradle = File(p.join(workspacePath, 'build.gradle'));
      final buildGradleKts = File(p.join(workspacePath, 'build.gradle.kts'));
      if (await buildGradle.exists() || await buildGradleKts.exists()) {
        final gradlew = File(p.join(workspacePath, 'gradlew'));
        if (await gradlew.exists()) {
          return './gradlew compileJava';
        }
        return 'gradle compileJava';
      }

      final cmake = File(p.join(workspacePath, 'CMakeLists.txt'));
      if (await cmake.exists()) {
        return 'cmake --build build';
      }

      final entities = await dir.list().toList();
      bool hasPython = false;
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.py')) {
          hasPython = true;
          break;
        }
      }
      if (hasPython) {
        return 'python3 -m compileall .';
      }
    } catch (e) {
      debugPrint('Error detecting project check command: $e');
    }
    return 'flutter analyze';
  }

  Future<void> _fixErrorsWithAI() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final allDiagnostics = <String, List<CodeDiagnostic>>{};
    ref.read(editorProvider).allDiagnostics.forEach((filePath, diags) {
      if (workspacePath != null && filePath.startsWith(workspacePath)) {
        allDiagnostics[filePath] = diags;
      }
    });
    final totalErrors = allDiagnostics.values.fold<int>(0, (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.error).length);
    final totalWarnings = allDiagnostics.values.fold<int>(0, (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.warning).length);
    final hasErrors = totalErrors > 0 || totalWarnings > 0;
    
    final checkCommand = await _detectProjectCheckCommand(workspacePath);
    
    String prompt;
    if (hasErrors) {
      final buffer = StringBuffer();
      buffer.writeln('I have the following compilation/analysis errors in my project. Please fix them:\n');
      
      allDiagnostics.forEach((filePath, diags) {
        if (diags.isNotEmpty) {
          final relPath = workspacePath != null && filePath.startsWith(workspacePath)
              ? p.relative(filePath, from: workspacePath)
              : filePath;
          for (final d in diags) {
            if (d.severity == CodeDiagnosticSeverity.error || d.severity == CodeDiagnosticSeverity.warning) {
              final severityStr = d.severity == CodeDiagnosticSeverity.error ? 'ERROR' : 'WARNING';
              buffer.writeln('- $relPath (line ${d.range.index + 1}, column ${d.range.start + 1}): [$severityStr] ${d.message}');
            }
          }
        }
      });
      
      buffer.writeln('\nAnalyze these errors, find the corresponding files, fix them using the <actions> block, and then run a project check using the command `$checkCommand` (action type "command") in the background to verify that errors are resolved.');
      prompt = buffer.toString();
    } else {
      prompt = 'Run the check command for this project in the background: `$checkCommand`. Wait for the results, analyze the output for errors, fix all found errors using the <actions> block, and run the check again to confirm the fix.';
    }

    ref.read(rightChatPanelOpenProvider.notifier).state = true;
    ref.read(aiProvider.notifier).askAI(prompt);
  }

  Widget _buildProblemsView(EditorState state) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final allDiagnostics = <String, List<CodeDiagnostic>>{};
    state.allDiagnostics.forEach((filePath, diags) {
      if (workspacePath != null && filePath.startsWith(workspacePath)) {
        allDiagnostics[filePath] = diags;
      }
    });
    final filesWithErrors = allDiagnostics.keys.where((k) => allDiagnostics[k]!.isNotEmpty).toList();
    
    final totalErrors = allDiagnostics.values.fold<int>(0, (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.error).length);
    final totalWarnings = allDiagnostics.values.fold<int>(0, (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.warning).length);
    final totalProblems = totalErrors + totalWarnings;

    final l10n = AppLocalizations.of(context)!;

    final headerWidget = Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.projectAnalysis,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.problemsFound(totalProblems, totalErrors, totalWarnings),
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _fixErrorsWithAI,
            icon: const Icon(LucideIcons.sparkles, size: 14, color: Colors.cyanAccent),
            label: Text(
              l10n.fixWithAi,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E60FF),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );

    if (filesWithErrors.isEmpty) {
      return Column(
        children: [
          headerWidget,
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.01),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.15)),
                        ),
                        child: const Icon(LucideIcons.shield_check, color: Colors.greenAccent, size: 38),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.noErrorsFound,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.noErrorsDescription,
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 12, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        headerWidget,
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: filesWithErrors.length,
            itemBuilder: (context, index) {
              final filePath = filesWithErrors[index];
              final diagnostics = allDiagnostics[filePath]!;
              final fileName = filePath.split('/').last;

              return Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  iconColor: Colors.white60,
                  collapsedIconColor: Colors.white24,
                  title: Row(
                    children: [
                      const Icon(LucideIcons.file_code, size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(
                        fileName, 
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${diagnostics.length}',
                          style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(left: 22.0),
                    child: Text(
                      filePath, 
                      style: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  children: diagnostics.map((d) => _buildDiagnosticTile(filePath, d)).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticTile(String path, CodeDiagnostic d) {
    Color color;
    IconData icon;
    String label;
    switch (d.severity) {
      case CodeDiagnosticSeverity.error:
        color = Colors.redAccent;
        icon = LucideIcons.circle_x;
        label = 'ERROR';
        break;
      case CodeDiagnosticSeverity.warning:
        color = Colors.orangeAccent;
        icon = LucideIcons.triangle_alert;
        label = 'WARNING';
        break;
      case CodeDiagnosticSeverity.hint:
        color = Colors.blueAccent;
        icon = LucideIcons.info;
        label = 'INFO';
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                leading: Icon(icon, color: color, size: 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.inter(color: color, fontSize: 8, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d.message,
                        style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    AppLocalizations.of(context)!.lineColumn(d.range.index + 1, d.range.start + 1),
                    style: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 10),
                  ),
                ),
                onTap: () async {
                  await ref.read(editorProvider.notifier).openFile(path);
                },
                trailing: IconButton(
                  icon: const Icon(LucideIcons.sparkles, color: Colors.cyanAccent, size: 16),
                  tooltip: AppLocalizations.of(context)!.fixWithAi,
                  onPressed: () => _handleAiFix(path, d),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAiFix(String path, CodeDiagnostic diagnostic) async {
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
    
    String content = '';
    final openFiles = ref.read(editorProvider).openFiles;
    final openedFile = openFiles.any((f) => f.path == path) 
        ? openFiles.firstWhere((f) => f.path == path) 
        : null;

    if (openedFile != null) {
      content = openedFile.controller.text;
    } else {
      try {
        content = await File(path).readAsString();
      } catch (e) {
        content = '[Failed to read file]';
      }
    }

    final prompt = '''
I am working on a project. I got an error in file: $path
Error: ${diagnostic.message}
Line: ${diagnostic.range.index + 1}, Column: ${diagnostic.range.start + 1}

File content:
```
$content
```

Please analyze the error and propose a fix.
Please apply the fix to this file using the <actions> tag format.
You must return the corrected version of the file inside <actions> tags, so that the user can press "Apply" and fix the error immediately.
Example:
<actions>
[
  {
    "type": "edit",
    "path": "$path",
    "content": "complete corrected code of the file",
    "description": "fixing error: ${diagnostic.message}"
  }
]
</actions>

Also explain what exactly went wrong and how you fixed it.
''';

    ref.read(aiProvider.notifier).askAI(prompt);
  }

  // ОБНОВЛЕННОЕ ХАКЕРСКОЕ КОНТЕКСТНОЕ МЕНЮ (Как в Termux)
  Future<void> _openSelectedPathInEditor(String selectedText) async {
    final runtime = ref.read(runtimeServiceProvider);

    // Ищем строку, похожую на путь к файлу: "path/to/file.ext" (с расширением)
    final candidate = selectedText
        .split(RegExp(r'[\r\n]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .firstWhere(
          (line) => _looksLikeFilePath(line),
          orElse: () => '',
        );
    if (candidate.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.noFileFoundInSelection),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Извлекаем голый путь из строки вроде "lib/main.dart:12:34" или "  /abs/path.py "
    var guestPath = candidate;
    final lineCol = RegExp(r'^(.+?):(\d+)(?::(\d+))?\s*$').firstMatch(candidate);
    int? line;
    int? column;
    if (lineCol != null) {
      guestPath = lineCol.group(1)!;
      line = int.tryParse(lineCol.group(2)!);
      column = lineCol.group(3) != null ? int.tryParse(lineCol.group(3)!) : null;
    }
    guestPath = guestPath.replaceAll(RegExp("[\"'<>]"), '').trim();

    final hostPath = PathMapper.mapToHost(guestPath, runtime.appDirectory);
    if (!await File(hostPath).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.fileNotFound(hostPath)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    await ref.read(editorProvider.notifier).openFile(
          hostPath,
          line: line != null ? (line - 1).clamp(0, 1 << 30) : null,
          column: column,
        );
  }

  bool _looksLikeFilePath(String line) {
    // Строка должна содержать путь с расширением файла
    if (!line.contains('/')) return false;
    final cleaned = line.replaceAll(RegExp(r':\d+.*$'), '');
    return RegExp(r'\.\w{1,6}$').hasMatch(cleaned.trim());
  }

  void _showTerminalContextMenu(BuildContext context, Offset position, TerminalSession session) async {
    HapticFeedback.mediumImpact();
    
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final hasSelection = session.xtermViewController.selection != null;
    
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - 60, 
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: const Color(0xFF25252D), 
      elevation: 12,
      useRootNavigator: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), 
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1))
      ),
      items: [
        if (hasSelection)
          PopupMenuItem(
            value: 'copy',
            height: 40,
            child: Row(
              children: [
                const Icon(LucideIcons.copy, size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.copy, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        if (hasSelection)
          PopupMenuItem(
            value: 'open_in_editor',
            height: 40,
            child: Row(
              children: [
                const Icon(LucideIcons.file_pen, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context)!.openInEditor, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'paste',
          height: 40,
          child: Row(
            children: [
              const Icon(LucideIcons.clipboard_paste, size: 16, color: Colors.white70),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.paste, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'copy_all',
          height: 40,
          child: Row(
            children: [
              const Icon(LucideIcons.files, size: 16, color: Colors.white54),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.copyAll, style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          height: 40,
          child: Row(
            children: [
              const Icon(LucideIcons.trash_2, size: 16, color: Colors.redAccent),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)!.clearTerminal, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
            ],
          ),
        ),
      ],
    );

    if (result == 'copy') {
      final selectedText = session.xtermViewController.selection != null
          ? session.xtermTerminal.buffer.getText(session.xtermViewController.selection!)
          : '';
      if (selectedText.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: selectedText));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.copiedToClipboard),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            )
          );
        }
      }
      session.xtermViewController.clearSelection();
    } else if (result == 'open_in_editor') {
      final selectedText = session.xtermViewController.selection != null
          ? session.xtermTerminal.buffer.getText(session.xtermViewController.selection!)
          : '';
      session.xtermViewController.clearSelection();
      if (selectedText.trim().isNotEmpty) {
        await _openSelectedPathInEditor(selectedText);
      }
    } else if (result == 'copy_all') {
      final text = _extractTerminalText(session.xtermTerminal);
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } else if (result == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) {
        session.pty.write(Uint8List.fromList(utf8.encode(data!.text!)));
      }
      session.xtermViewController.clearSelection();
    } else if (result == 'clear') {
       session.xtermTerminal.eraseDisplay();
       session.xtermTerminal.eraseScrollbackOnly();
    }
  }

  Widget _buildVirtualKeys(List<TerminalSession> sessions, TerminalTabsNotifier notifier) {
    if (sessions.isEmpty) return const SizedBox();
    final currentSession = sessions[notifier.currentIndex];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: VirtualKeysView(
        activeKeys: _activeModifiers,
        onKeyTap: (value) => _onKeyTap(value, currentSession),
      ),
    );
  }

  String _getFontFamily(String fontName) {
    final normalized = fontName.toLowerCase().replaceAll(' ', '');
    switch (normalized) {
      case 'jetbrainsmono':
        return 'jetBrainsMono';
      case 'firacode':
        return 'firaCode';
      case 'sourcecodepro':
      case 'anonymouspro':
        return 'sourceCodePro';
      case 'inconsolata':
        return 'inconsolata';
      case 'hack':
        return 'hack';
      case 'dejavusansmono':
        return 'dejaVuSansMono';
      case 'proggy':
      case 'proggyvector':
        return 'proggy';
      case 'cascadiacode':
      case 'cascadia':
        return 'cascadia';
      case 'monospace':
      default:
        return 'monospace';
    }
  }
}

class _SuggestionBox extends StatefulWidget {
  final List<String> suggestions;
  final int selectedSuggestionIndex;
  final TerminalSession session;
  final Function(TerminalSession, String) onAccept;

  const _SuggestionBox({
    required this.suggestions,
    required this.selectedSuggestionIndex,
    required this.session,
    required this.onAccept,
  });

  @override
  State<_SuggestionBox> createState() => _SuggestionBoxState();
}

class _SuggestionBoxState extends State<_SuggestionBox> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const itemHeight = 36.0;
    final maxHeight = (widget.suggestions.length * itemHeight).clamp(0.0, 180.0);

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: maxHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E24).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: RawScrollbar(
            thumbVisibility: true,
            thumbColor: Colors.white.withValues(alpha: 0.15),
            controller: _scrollController,
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemExtent: itemHeight,
              itemCount: widget.suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = widget.suggestions[index];
                final isSelected = index == widget.selectedSuggestionIndex;
                final isDirectory = suggestion.endsWith('/');
                final isPath = suggestion.contains('/');

                return InkWell(
                  onTap: () => widget.onAccept(widget.session, suggestion),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    color: isSelected
                        ? Colors.cyanAccent.withValues(alpha: 0.15)
                        : Colors.transparent,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isDirectory
                                ? Colors.amber.withValues(alpha: 0.1)
                                : isPath
                                ? Colors.blueAccent.withValues(alpha: 0.1)
                                : Colors.greenAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            isDirectory
                                ? LucideIcons.folder
                                : isPath
                                ? LucideIcons.file
                                : LucideIcons.terminal,
                            size: 12,
                            color: isDirectory
                                ? Colors.amber
                                : isPath
                                ? Colors.blueAccent
                                : Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: GoogleFonts.jetBrainsMono(
                              color: isSelected ? Colors.cyanAccent : Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isPath)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'cmd',
                              style: GoogleFonts.inter(
                                color: Colors.greenAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (isDirectory)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'dir',
                              style: GoogleFonts.inter(
                                color: Colors.amber,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (isPath && !isDirectory)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'file',
                              style: GoogleFonts.inter(
                                color: Colors.blueAccent,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class CollapsibleConsole extends StatefulWidget {
  final String content;
  const CollapsibleConsole({super.key, required this.content});

  @override
  State<CollapsibleConsole> createState() => _CollapsibleConsoleState();
}

class _CollapsibleConsoleState extends State<CollapsibleConsole> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(LucideIcons.terminal, size: 12, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    'Console Log',
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(_isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down, size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black26,
              child: SelectableText(
                widget.content.trim(),
                style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10.5, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}