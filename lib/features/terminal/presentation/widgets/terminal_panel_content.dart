import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

import 'package:xterm/xterm.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/virtual_keys.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/chat_message.dart';
import 'package:quantum_ide/features/git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/ai_permission_service.dart';
import 'package:quantum_ide/core/services/git_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:lottie/lottie.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_diff_page.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/apk_signer_widget.dart';

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
  final TextEditingController _urlController = TextEditingController(text: "http://localhost:8080");
  final TextEditingController _aiChatController = TextEditingController();
  InAppWebViewController? _webViewController;
  bool _serverIsRunning = false;
  int _buildSubTab = 0;


  void _setServerRunning(bool val) {
    setState(() {
      _serverIsRunning = val;
    });
    ref.read(serverRunningProvider.notifier).state = val;
  }

  void _toggleServer() {
    _setServerRunning(!_serverIsRunning);
  }

  void _openInBrowser() async {
    final url = Uri.parse(_urlController.text);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _currentInput = '';
  final ValueNotifier<List<String>?> _suggestionsNotifier = ValueNotifier(null);
  int _selectedSuggestionIndex = 0;
  List<String> _pathBinaries = [];

  OverlayEntry? _selectionToolbarOverlay;
  bool _hasSelection = false;
  TerminalSession? _lastAttachedSession;
  TerminalSession? _lastSelectionSession;

  @override
  void initState() {
    super.initState();
    _loadPathBinaries();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _aiChatController.dispose();
    _suggestionsNotifier.dispose();
    _hideSelectionToolbar();
    _lastSelectionSession?.xtermViewController.removeListener(_onSelectionChanged);
    super.dispose();
  }

  ProjectType _detectProjectType(String? path, ProjectType registeredType) {
    if (registeredType != ProjectType.other) {
      return registeredType;
    }
    if (path == null) return ProjectType.other;
    
    // Try to auto-detect based on files in the path
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
      
      String sequence = '';
      if (hadCtrl) {
        if (data.length == 1) {
          int code = data.toUpperCase().codeUnitAt(0);
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
      } else {
        sequence = data;
      }

      if (sequence.isNotEmpty) {
        session.pty.write(Uint8List.fromList(utf8.encode(sequence)));
        _handleInputForAutocomplete(session, sequence);
      }

      if (hadCtrl || hadAlt) {
        setState(() {
          _activeModifiers.remove('CTRL');
          _activeModifiers.remove('ALT');
        });
      }
    };
  }

  void _setupSelectionListener(TerminalSession session) {
    if (_lastSelectionSession != session) {
      _lastSelectionSession?.xtermViewController.removeListener(_onSelectionChanged);
      _lastSelectionSession = session;
      session.xtermViewController.addListener(_onSelectionChanged);
    }
  }

  void _onSelectionChanged() {
    final session = _lastSelectionSession;
    if (session == null) return;
    
    final selection = session.xtermViewController.selection;
    if (selection != null) {
      if (!_hasSelection) {
        setState(() {
          _hasSelection = true;
        });
        _showSelectionToolbar(session);
      }
    } else {
      if (_hasSelection) {
        setState(() {
          _hasSelection = false;
        });
        _hideSelectionToolbar();
      }
    }
  }

  void _showSelectionToolbar(TerminalSession session) {
    _hideSelectionToolbar();
    if (!mounted) return;

    final overlay = Overlay.of(context);

    _selectionToolbarOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF1E1E24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toolbarButton(
                      icon: LucideIcons.copy,
                      label: 'Copy',
                      onTap: () {
                        final selectedText = session.xtermViewController.selection != null
                            ? session.xtermTerminal.buffer.getText(session.xtermViewController.selection!)
                            : '';
                        if (selectedText.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: selectedText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(AppLocalizations.of(context)!.copiedToClipboard),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          );
                        }
                        session.xtermViewController.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    _toolbarButton(
                      icon: LucideIcons.clipboard_paste,
                      label: 'Paste',
                      onTap: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          session.pty.write(Uint8List.fromList(utf8.encode(data!.text!)));
                        }
                        session.xtermViewController.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    _toolbarButton(
                      icon: LucideIcons.search,
                      label: 'Search',
                      onTap: () {
                        final selectedText = session.xtermViewController.selection != null
                            ? session.xtermTerminal.buffer.getText(session.xtermViewController.selection!)
                            : '';
                        if (selectedText.isNotEmpty) {
                          session.pty.write(Uint8List.fromList(utf8.encode('grep -r "${selectedText.replaceAll('"', '\\"')}" .\n')));
                        }
                        session.xtermViewController.clearSelection();
                      },
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    _toolbarButton(
                      icon: LucideIcons.x,
                      label: '',
                      onTap: () {
                        session.xtermViewController.clearSelection();
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

    overlay.insert(_selectionToolbarOverlay!);
  }

  void _hideSelectionToolbar() {
    _selectionToolbarOverlay?.remove();
    _selectionToolbarOverlay = null;
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: label.isEmpty ? 8 : 12,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.cyanAccent),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onKeyTap(String value, TerminalSession session) async {
    final term = session.xtermTerminal;
    if (value == 'ctrl') {
      setState(() => _activeModifiers.contains('CTRL') ? _activeModifiers.remove('CTRL') : _activeModifiers.add('CTRL'));
      return;
    }
    if (value == 'ALT') {
      setState(() => _activeModifiers.contains('ALT') ? _activeModifiers.remove('ALT') : _activeModifiers.add('ALT'));
      return;
    }
    if (value == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        session.pty.write(Uint8List.fromList(utf8.encode(data.text!)));
      }
      return;
    }
    // Named control shortcuts — sent directly to PTY (most reliable)
    if (value == 'ctrl+c') {
      session.pty.write(Uint8List.fromList([3])); // ETX
      return;
    }
    if (value == 'ctrl+d') {
      session.pty.write(Uint8List.fromList([4])); // EOT
      return;
    }
    if (value == 'ctrl+l') {
      session.pty.write(Uint8List.fromList([12])); // FF — clear screen
      return;
    }
    // Backspace / DEL
    if (value == '\x7f') {
      session.pty.write(Uint8List.fromList([127]));
      _handleInputForAutocomplete(session, '\x7f');
      return;
    }

    final hadCtrl = _activeModifiers.contains('CTRL');
    final hadAlt = _activeModifiers.contains('ALT');
    if (hadCtrl) _activeModifiers.remove('CTRL');
    if (hadAlt) _activeModifiers.remove('ALT');

    if (value == '\t') {
      final suggestions = _suggestionsNotifier.value;
      if (suggestions != null && suggestions.isNotEmpty) {
        _acceptSuggestion(session, suggestions[_selectedSuggestionIndex]);
        return;
      }
      term.keyInput(xt.TerminalKey.tab, ctrl: hadCtrl, alt: hadAlt);
    } else if (value == '\x1b') {
      term.keyInput(xt.TerminalKey.escape, ctrl: hadCtrl, alt: hadAlt);
    } else if (value == '\x1b[A') {
      term.keyInput(xt.TerminalKey.arrowUp, ctrl: hadCtrl, alt: hadAlt);
    } else if (value == '\x1b[B') {
      term.keyInput(xt.TerminalKey.arrowDown, ctrl: hadCtrl, alt: hadAlt);
    } else if (value == '\x1b[D') {
      term.keyInput(xt.TerminalKey.arrowLeft, ctrl: hadCtrl, alt: hadAlt);
    } else if (value == '\x1b[C') {
      term.keyInput(xt.TerminalKey.arrowRight, ctrl: hadCtrl, alt: hadAlt);
    } else if (value == '\x1b[H') {
      // HOME — send directly to PTY
      session.pty.write(Uint8List.fromList(utf8.encode('\x1b[H')));
    } else if (value == '\x1b[F') {
      // END — send directly to PTY
      session.pty.write(Uint8List.fromList(utf8.encode('\x1b[F')));
    } else if (value.length == 1 && hadCtrl) {
      // Ctrl+Letter: convert to control code (e.g. Ctrl+A = 0x01)
      final code = value.toUpperCase().codeUnitAt(0);
      if (code >= 65 && code <= 90) {
        session.pty.write(Uint8List.fromList([code - 64]));
      } else {
        session.pty.write(Uint8List.fromList(utf8.encode(value)));
      }
    } else if (value.length == 1 && hadAlt) {
      // Alt+Letter: ESC prefix
      session.pty.write(Uint8List.fromList(utf8.encode('\x1b$value')));
    } else {
      // Regular text — write directly to PTY for reliability
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
        color: Color(0xFF0D0F14), // Deeper, more premium black
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
            if (widget.onlyTerminal || panelState.selectedTab == PanelTab.terminal || panelState.selectedTab == PanelTab.console)
              _buildVirtualKeys(sessions, notifier),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(PanelState state, List<TerminalSession> sessions, TerminalTabsNotifier notifier, EditorState editorState) {
    final tabs = PanelTab.values;
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
      case PanelTab.console:
        return _buildTerminalView(sessions, notifier, key: const ValueKey('console'));
      case PanelTab.run:
        return _buildRunView(key: const ValueKey('run'));
      case PanelTab.buildLogs:
        return _buildBuildLogsView(key: const ValueKey('buildLogs'));
      case PanelTab.appLogs:
        return _buildAppLogsView(key: const ValueKey('appLogs'));
      case PanelTab.aiAgent:
        return const SizedBox.shrink();
      case PanelTab.servers:
        return _buildServersView(key: const ValueKey('servers'));
      case PanelTab.packages:
        return _buildPackagesTabContent(key: const ValueKey('packages'));
      case PanelTab.problems:
        return _buildProblemsView(editorState);
      case PanelTab.git:
        return _buildGitView();
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
    Color statusColor = isConflicted 
        ? Colors.redAccent 
        : (isStaged ? Colors.greenAccent : (isUntracked ? Colors.orangeAccent : Colors.amberAccent));
    String statusLabel = isConflicted
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
                        builder: (context) => GitMergeConflictPage(
                          relativePath: path,
                        ),
                      ),
                    );
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GitDiffPage(
                          relativePath: path,
                          initiallyStaged: isStaged,
                        ),
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
                        icon: const Icon(
                          LucideIcons.git_pull_request, 
                          size: 14, 
                          color: Colors.redAccent,
                        ),
                        tooltip: l10n.resolveConflictTooltip,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => GitMergeConflictPage(
                                relativePath: path,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      IconButton(
                        icon: Icon(
                          isStaged ? LucideIcons.minus : LucideIcons.plus, 
                          size: 14, 
                          color: Colors.white54,
                        ),
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
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.nodejs:
        title = l10n.nodejsProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'npm start || node index.js || node server.js || node app.js || (js_file=\$(find . -maxdepth 2 -name "*.js" ! -path "*/node_modules/*" | head -n 1); if [ -n "\$js_file" ]; then node "\$js_file"; else echo "No JS file found. Please create index.js or package.json"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.dart:
        title = l10n.dartProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'dart run || dart bin/main.dart || dart main.dart || (dart_file=\$(find . -maxdepth 2 -name "*.dart" | head -n 1); if [ -n "\$dart_file" ]; then dart "\$dart_file"; else echo "No Dart file found. Please create bin/main.dart"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.web:
        title = l10n.webProject;
        actions.addAll([
          _buildActionButton(l10n.startServer, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(DedicatedTerminalType.run, 
                  'python3 -m http.server 8080 || npx http-server -p 8080 || npx serve -p 8080')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), // Ctrl+C
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
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), // Ctrl+C
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
              () => _sendRawKeyToDedicatedTerminal(DedicatedTerminalType.run, String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
    }

    // Always add Copy button at the end
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.cyanAccent.withValues(alpha: 0.25) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.cyanAccent : Colors.white38),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive ? Colors.white : Colors.white38,
                fontSize: 12,
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
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 16, color: color.withValues(alpha: 0.9)),
            ),
          ),
        ),
      ),
    );
  }

  void _runDedicatedCommand(DedicatedTerminalType type, String cmd) {
    final workspace = ref.read(workspaceProvider);
    final path = workspace.currentPath;
    
    // We must ensure we are in the project directory.
    // To keep it clean, we execute: cd path && clear && command
    // This way the user doesn't see the long path after the clear happens.
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


  Widget _buildZoomButton(IconData icon, VoidCallback onTap) {
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
          child: Icon(icon, size: 12, color: Colors.white38),
        ),
      ),
    );
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                      child: Icon(
                        _isSidebarOpen ? LucideIcons.panel_left_close : LucideIcons.panel_left_open, 
                        size: 16, 
                        color: Colors.white38
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(LucideIcons.folder, size: 12, color: Colors.cyanAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ref.watch(workspaceProvider).currentPath?.split('/').last ?? 'root',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white38, 
                          fontSize: 10,
                          fontWeight: FontWeight.w500
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(LucideIcons.chevron_right, size: 10, color: Colors.white10),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'bash',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.cyanAccent.withValues(alpha: 0.5), 
                          fontSize: 10,
                          fontWeight: FontWeight.bold
                        ),
                        overflow: TextOverflow.clip,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildZoomButton(LucideIcons.minus, () {
                      final size = ref.read(settingsProvider).terminalFontSize;
                      ref.read(settingsProvider.notifier).setTerminalFontSize((size - 1).clamp(8.0, 24.0));
                    }),
                    const SizedBox(width: 4),
                    Text(
                      '${ref.watch(settingsProvider).terminalFontSize.toInt()}',
                      style: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    _buildZoomButton(LucideIcons.plus, () {
                      final size = ref.read(settingsProvider).terminalFontSize;
                      ref.read(settingsProvider.notifier).setTerminalFontSize((size + 1).clamp(8.0, 24.0));
                    }),
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
                            letterSpacing: 0.5
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

    if (!isSecondary) {
      if (_lastAttachedSession != session) {
        _lastAttachedSession = session;
        _currentInput = '';
        _suggestionsNotifier.value = null;
        _attachTerminalOutputListener(session);
      }
      _setupSelectionListener(session);
    } else {
      session.xtermTerminal.onOutput = (data) {
        final hadCtrl = _activeModifiers.contains('CTRL');
        final hadAlt = _activeModifiers.contains('ALT');
        String sequence = hadCtrl ? (data.length == 1 ? String.fromCharCode(data.toUpperCase().codeUnitAt(0) - 64) : data) : (hadAlt ? '\x1b$data' : data);
        if (sequence.isNotEmpty) {
          session.pty.write(Uint8List.fromList(utf8.encode(sequence)));
        }
        if (hadCtrl || hadAlt) {
          setState(() {
            _activeModifiers.remove('CTRL');
            _activeModifiers.remove('ALT');
          });
        }
      };
    }

    return Stack(
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
                child: SelectionContainer.disabled(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (details) => _showTerminalContextMenu(context, details.globalPosition, session),
                    child: xt.TerminalView(
                      session.xtermTerminal,
                      controller: session.xtermViewController,
                      autofocus: true,
                      padding: const EdgeInsets.all(12),
                      theme: theme,
                      backgroundOpacity: 0,
                      textStyle: xt.TerminalStyle(
                        fontSize: terminalFontSize,
                        fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
                      ),
                      keyboardType: TextInputType.visiblePassword,
                      deleteDetection: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        _buildSuggestionBox(session),
      ],
    );
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

      // Scan first level of directory for python files
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

    // Open right AI chat panel
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
    
    // Ask AI
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

    // Header widget that is always shown
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
    // Open right AI chat panel
    ref.read(rightChatPanelOpenProvider.notifier).state = true;
    
    // Prepare prompt
    String content = '';
    final openFiles = ref.read(editorProvider).openFiles;
    final openedFile = openFiles.any((f) => f.path == path) 
        ? openFiles.firstWhere((f) => f.path == path) 
        : null;

    if (openedFile != null) {
      content = openedFile.controller.text;
    } else {
      // If file not open, try to read it
      try {
        content = await File(path).readAsString();
      } catch (e) {
        content = '[Failed to read file]';
      }
    }

    final prompt = """
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
""";

    ref.read(aiProvider.notifier).askAI(prompt);
  }

  Widget _buildServersView({Key? key}) {
    return Column(
      key: key,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              // Address Bar with Glass Look
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.globe, size: 14, color: Colors.white38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 12),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) {
                            if (_serverIsRunning) {
                              _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(_urlController.text)));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Reload Button
              if (_serverIsRunning)
                IconButton(
                  icon: const Icon(LucideIcons.rotate_cw, size: 16, color: Colors.greenAccent),
                  tooltip: AppLocalizations.of(context)!.refreshPreview,
                  onPressed: () => _webViewController?.reload(),
                ),
              // Toggle Power (Start/Stop) Button
              IconButton(
                icon: Icon(
                  _serverIsRunning ? LucideIcons.square : LucideIcons.play,
                  size: 14,
                  color: _serverIsRunning ? Colors.redAccent : Colors.greenAccent,
                ),
                tooltip: _serverIsRunning 
                    ? AppLocalizations.of(context)!.stopWebServer 
                    : AppLocalizations.of(context)!.startWebServer,
                onPressed: _toggleServer,
              ),
              IconButton(
                icon: const Icon(LucideIcons.external_link, size: 14, color: Colors.cyanAccent),
                tooltip: AppLocalizations.of(context)!.openInExternalBrowser,
                onPressed: _openInBrowser,
              ),
            ],
          ),
        ),
        Expanded(
          child: _serverIsRunning
              ? InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_urlController.text)),
                  initialSettings: InAppWebViewSettings(
                    transparentBackground: true,
                    javaScriptEnabled: true,
                  ),
                  onWebViewCreated: (controller) => _webViewController = controller,
                  onReceivedError: (controller, request, error) {
                    Future.delayed(const Duration(seconds: 2), () {
                      _webViewController?.reload();
                    });
                  },
                )
              : Center(
                  child: SingleChildScrollView(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.01),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.15)),
                            ),
                            child: const Icon(LucideIcons.globe, color: Colors.blueAccent, size: 38),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            AppLocalizations.of(context)!.localWebServer,
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppLocalizations.of(context)!.webServerDesc,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _toggleServer,
                            icon: const Icon(LucideIcons.play, size: 14),
                            label: Text(AppLocalizations.of(context)!.startWebServer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                              foregroundColor: Colors.blueAccent,
                              elevation: 0,
                              side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
  }

  void _showTerminalContextMenu(BuildContext context, Offset position, TerminalSession session) async {
    HapticFeedback.mediumImpact();
    
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    
    final result = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy - 40, // Offset upwards slightly to be above the finger
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: const Color(0xFF1E1E1E),
      elevation: 8,
      useRootNavigator: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), 
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1))
      ),
      items: [
        PopupMenuItem(
          value: 'copy_all',
          child: Row(
            children: [
              const Icon(LucideIcons.files, size: 14, color: Colors.white54),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.copyAll, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'paste',
          child: Row(
            children: [
              const Icon(LucideIcons.clipboard_paste, size: 14, color: Colors.white54),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.paste, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              const Icon(LucideIcons.trash_2, size: 14, color: Colors.white54),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.clearTerminal, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (result == 'copy_all') {
      final text = _extractTerminalText(session.xtermTerminal);
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } else if (result == 'paste') {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data?.text != null) {
        session.pty.write(Uint8List.fromList(utf8.encode(data!.text!)));
      }
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

  Widget _buildPackagesTabContent({Key? key}) {
    final packages = ref.watch(packageServiceProvider);
    
    return Column(
      key: key,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.toy_brick, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.packagesAndEnv,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              Text(
                AppLocalizations.of(context)!.packagesInstalledCount(packages.where((p) => p.isInstalled).length, packages.length),
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: packages.length,
            itemBuilder: (context, index) {
              final pkg = packages[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(pkg.icon, color: Colors.cyanAccent, size: 16),
                  ),
                  title: Text(
                    pkg.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    pkg.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pkg.isInstalled) ...[
                        const Icon(LucideIcons.circle_check_big, color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(LucideIcons.refresh_cw, size: 14, color: Colors.white38),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            ref.read(packageServiceProvider.notifier).installPackage(pkg);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!.updatingPackage(pkg.name)),
                              ),
                            );
                          },
                        ),
                      ] else
                        ElevatedButton(
                          onPressed: () {
                            ref.read(packageServiceProvider.notifier).installPackage(pkg);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!.installingPackage(pkg.name)),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                            foregroundColor: Colors.cyanAccent,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            minimumSize: const Size(60, 26),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(context)!.install,
                            style: GoogleFonts.inter(
                              fontSize: 10,
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
      ],
    );
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

// ── AI Chat Messages Widget (auto-scrolls to bottom) ────────────────────────

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

class AIChatMessages extends ConsumerStatefulWidget {
  final AIState aiState;
  const AIChatMessages({super.key, required this.aiState});

  @override
  ConsumerState<AIChatMessages> createState() => AIChatMessagesState();
}

class AIChatMessagesState extends ConsumerState<AIChatMessages> {
  final ScrollController _scroll = ScrollController();
  int? _editingMessageIndex;
  TextEditingController? _editingController;

  @override
  void didUpdateWidget(AIChatMessages oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Прокрутка вниз при появлении нового сообщения или индикатора загрузки
    if (oldWidget.aiState.messages.length != widget.aiState.messages.length ||
        oldWidget.aiState.isLoading != widget.aiState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _editingController?.dispose();
    super.dispose();
  }

  Widget _buildMessageActionDetails(AIAction action) {
    return SelectionArea(
      child: Builder(builder: (context) {
        final workspacePath = ref.watch(workspaceProvider).currentPath;
        IconData iconData;
        Color iconColor;
        String text;
        
        if (action.type == 'command') {
          iconData = LucideIcons.terminal;
          iconColor = Colors.white54;
          text = AppLocalizations.of(context)!.ranAction(action.content);
        } else {
          final fileName = action.path.split('/').last;
          iconColor = action.type == 'create' 
              ? Colors.greenAccent 
              : (action.type == 'delete' ? Colors.redAccent : Colors.blueAccent);
          
          iconData = action.type == 'create' 
              ? LucideIcons.file_plus 
              : (action.type == 'delete' ? LucideIcons.file_x : LucideIcons.pencil);
          
          final relDir = workspacePath != null && action.path.startsWith(workspacePath)
              ? p.dirname(p.relative(action.path, from: workspacePath))
              : '';
          
          final dirSuffix = relDir.isNotEmpty && relDir != '.' ? ' ${AppLocalizations.of(context)!.inFolder(relDir)}' : '';
          final typeStr = action.type == 'create' 
              ? AppLocalizations.of(context)!.created 
              : (action.type == 'delete' ? AppLocalizations.of(context)!.deleted : AppLocalizations.of(context)!.edited);
          text = '$typeStr $fileName$dirSuffix';
        }
        
        return Row(
          children: [
            Icon(iconData, size: 11, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70))),
          ],
        );
      }),
    );
  }

  Widget _buildStepSummary(ChatMessage message) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final executed = message.executedActions ?? [];
    
    // Count stats
    int editCount = 0;
    int additions = 0;
    int deletions = 0;
    int commandCount = 0;
    
    for (final action in executed) {
      if (action.type == 'command') {
        commandCount++;
      } else {
        editCount++;
        additions += action.additions ?? 0;
        deletions += action.deletions ?? 0;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Timeline Events
        if (executed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(executed.length, (index) {
                final action = executed[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildMessageActionDetails(action),
                );
              }),
            ),
          ),
        
        // 2. Structured Task Card
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2230),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card Header
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(LucideIcons.circle_check, size: 12, color: Colors.greenAccent),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.taskName != null && message.taskName!.isNotEmpty
                                ? (message.taskName!.length > 40 ? '${message.taskName!.substring(0, 40)}...' : message.taskName!)
                                : AppLocalizations.of(context)!.taskExecution,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          if (message.stepNumber != null)
                            Text(
                              AppLocalizations.of(context)!.stepNumber(message.stepNumber!, message.totalSteps ?? 12),
                              style: GoogleFonts.inter(color: Colors.white38, fontSize: 9.5),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              
              // Summary stats row & Keep / Undo buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      editCount > 0 
                          ? AppLocalizations.of(context)!.filesChangedCount(editCount, additions, deletions)
                          : AppLocalizations.of(context)!.commandsExecutedCount(commandCount),
                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 10),
                    ),
                    if (editCount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Keep Button
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.check, size: 10, color: Colors.greenAccent),
                            label: Text(
                              AppLocalizations.of(context)!.keep,
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context)!.changesAccepted),
                                  backgroundColor: const Color(0xFF1E2230),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          // Undo Button
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(LucideIcons.undo_2, size: 10, color: Colors.redAccent),
                            label: Text(
                              AppLocalizations.of(context)!.undo,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final gitSvc = ref.read(gitServiceProvider);
                              final editor = ref.read(editorProvider.notifier);
                              int undone = 0;
                              for (final action in executed) {
                                if (action.type == 'edit' || action.type == 'create') {
                                  final relPath = workspacePath != null && action.path.startsWith(workspacePath)
                                      ? p.relative(action.path, from: workspacePath)
                                      : action.path;
                                  await gitSvc.discardChanges(relPath);
                                  
                                  // Reload in editor if open
                                  final isOpen = ref.read(editorProvider).openFiles.any((f) => f.path == action.path);
                                  if (isOpen) {
                                    await editor.openFile(action.path);
                                  }
                                  undone++;
                                }
                              }
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!.undoneChanges(undone)),
                                    backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // File list inside the card (optional dropdown style or visible)
              if (editCount > 0) ...[
                const Divider(color: Colors.white10, height: 1),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: executed.where((a) => a.type != 'command').length,
                  itemBuilder: (context, idx) {
                    final editActions = executed.where((a) => a.type != 'command').toList();
                    final action = editActions[idx];
                    final fileName = action.path.split('/').last;
                    final displayPath = workspacePath != null && action.path.startsWith(workspacePath)
                        ? p.relative(action.path, from: workspacePath)
                        : action.path;
                    final dirPath = displayPath.contains('/')
                        ? displayPath.substring(0, displayPath.lastIndexOf('/'))
                        : '';

                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      leading: const Icon(LucideIcons.file_code, size: 13, color: Colors.white54),
                      title: Row(
                        children: [
                          Text(fileName, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                          if (dirPath.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Expanded(child: Text('in $dirPath', style: GoogleFonts.inter(color: Colors.white30, fontSize: 9), overflow: TextOverflow.ellipsis)),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((action.additions ?? 0) > 0)
                            Text(
                              '+${action.additions}',
                              style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          if ((action.additions ?? 0) > 0 && (action.deletions ?? 0) > 0) const SizedBox(width: 4),
                          if ((action.deletions ?? 0) > 0)
                            Text(
                              '-${action.deletions}',
                              style: GoogleFonts.jetBrainsMono(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          const SizedBox(width: 8),
                          // Individual file Undo/Discard icon
                          IconButton(
                            icon: const Icon(LucideIcons.undo_2, size: 10, color: Colors.white38),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final gitSvc = ref.read(gitServiceProvider);
                              final relPath = workspacePath != null && action.path.startsWith(workspacePath)
                                  ? p.relative(action.path, from: workspacePath)
                                  : action.path;
                              await gitSvc.discardChanges(relPath);
                              
                              final isOpen = ref.read(editorProvider).openFiles.any((f) => f.path == action.path);
                              if (isOpen) {
                                await ref.read(editorProvider.notifier).openFile(action.path);
                              }
                              
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(AppLocalizations.of(context)!.discardedFileChanges(fileName)),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.aiState.messages.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final hasEnoughSpace = constraints.maxHeight > 90;
          return ClipRect(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasEnoughSpace) ...[
                    Icon(LucideIcons.sparkles, size: 36, color: Colors.purpleAccent.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                  ],
                  if (constraints.maxHeight > 40)
                    Text(
                      l10n.askAboutCode,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }


    final itemCount = widget.aiState.messages.length + (widget.aiState.isLoading ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == widget.aiState.messages.length) {
          final role = widget.aiState.activeAgentRole ?? 'Agent';
          final status = widget.aiState.currentStatusMessage ?? 
              AppLocalizations.of(context)!.thinking;
          
          Color roleColor;
          String roleText;
          IconData roleIcon;
          
          switch (role.toLowerCase()) {
            case 'planner':
              roleColor = Colors.cyanAccent;
              roleText = AppLocalizations.of(context)!.planner;
              roleIcon = LucideIcons.compass;
              break;
            case 'coder':
              roleColor = Colors.purpleAccent;
              roleText = AppLocalizations.of(context)!.coder;
              roleIcon = LucideIcons.code;
              break;
            case 'validator':
              roleColor = Colors.orangeAccent;
              roleText = AppLocalizations.of(context)!.validator;
              roleIcon = LucideIcons.shield_check;
              break;
            default:
              roleColor = Colors.blueAccent;
              roleText = AppLocalizations.of(context)!.aiAgentRole;
              roleIcon = LucideIcons.bot;
          }

          return Container(
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2230).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: roleColor.withValues(alpha: 0.25),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Lottie.network(
                    'https://assets5.lottiefiles.com/packages/lf20_q5pk6hy1.json',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        valueColor: AlwaysStoppedAnimation<Color>(roleColor),
                      ),
                    ),
                    frameBuilder: (context, child, composition) {
                      if (composition == null) {
                        return SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            valueColor: AlwaysStoppedAnimation<Color>(roleColor),
                          ),
                        );
                      }
                      return child;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(roleIcon, size: 11, color: roleColor),
                          const SizedBox(width: 4),
                          Text(
                            roleText,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: roleColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final message = widget.aiState.messages[index];
        final isUser = message.role == MessageRole.user;
        final isSystem = message.role == MessageRole.system;
        final isLastMessage = index == widget.aiState.messages.length - 1;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: isUser 
                ? CrossAxisAlignment.end 
                : (isSystem ? CrossAxisAlignment.stretch : CrossAxisAlignment.start),
            children: [
              if (isSystem)
                message.isStepSummary
                    ? _buildStepSummary(message)
                    : CollapsibleConsole(content: message.content)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF3B1E60).withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: isUser ? BorderRadius.circular(16) : BorderRadius.circular(12),
                    border: Border.all(
                      color: isUser
                          ? Colors.purpleAccent.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.05),
                      width: isUser ? 0.8 : 0.5,
                    ),
                  ),
                  child: isUser
                      ? (_editingMessageIndex == index
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _editingController,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5),
                                  maxLines: null,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _editingMessageIndex = null;
                                          _editingController?.dispose();
                                          _editingController = null;
                                        });
                                      },
                                      child: Text(
                                        AppLocalizations.of(context)!.cancel,
                                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
                                        foregroundColor: Colors.cyanAccent,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                          side: const BorderSide(color: Colors.cyanAccent, width: 0.5),
                                        ),
                                      ),
                                      onPressed: () {
                                        final newText = _editingController?.text.trim() ?? '';
                                        if (newText.isNotEmpty && newText != message.content) {
                                          ref.read(aiProvider.notifier).editUserRequest(index, newText);
                                        }
                                        setState(() {
                                          _editingMessageIndex = null;
                                          _editingController?.dispose();
                                          _editingController = null;
                                        });
                                      },
                                      child: Text(
                                        AppLocalizations.of(context)!.resubmit,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : SelectableText(
                              message.content,
                              style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, height: 1.45),
                            ))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _renderMarkdown(message.content, context),
                        ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Row(
                  mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    Text(
                      isUser 
                          ? l10n.you 
                          : (isSystem 
                              ? AppLocalizations.of(context)!.system 
                              : (ref.read(aiServiceProvider).settings.currentProvider.id == 'local_edge'
                                  ? l10n.localAiDisplayName
                                  : ref.read(aiServiceProvider).settings.currentProvider.displayName)),
                      style: GoogleFonts.inter(color: Colors.white24, fontSize: 10),
                    ),
                    if (isUser && !widget.aiState.isLoading && _editingMessageIndex == null) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _editingMessageIndex = index;
                            _editingController = TextEditingController(text: message.content);
                          });
                        },
                        child: const Icon(LucideIcons.pencil, size: 10, color: Colors.cyanAccent),
                      ),
                    ],
                    if (!widget.aiState.isLoading && index < widget.aiState.messages.length - 1) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: AppLocalizations.of(context)!.rollbackHistoryToStep,
                        child: InkWell(
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF1E2230),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                title: Text(
                                  AppLocalizations.of(context)!.confirmRollback,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                content: Text(
                                  AppLocalizations.of(context)!.rollbackConfirmationText,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text(
                                      AppLocalizations.of(context)!.cancel,
                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text(
                                      AppLocalizations.of(context)!.yesRollback,
                                      style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(aiProvider.notifier).rollbackToMessage(index);
                            }
                          },
                          child: const Icon(LucideIcons.rotate_ccw, size: 10, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (message.actions != null && message.actions!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildMessageActionsCard(message.actions!, isLastMessage),
              ] else if (!isUser && !isSystem && isLastMessage && widget.aiState.proposedActions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildMessageActionsCard(widget.aiState.proposedActions, isLastMessage),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageActionsCard(List<AIAction> actions, bool isLastMessage) {
    final l10n = AppLocalizations.of(context)!;
    
    // Check if any of these actions are still pending in the global proposedActions state
    final pendingActions = actions.where((a) => widget.aiState.proposedActions.any((pa) => pa.path == a.path && pa.content == a.content)).toList();
    final isPending = pendingActions.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161923),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              final isActionPending = widget.aiState.proposedActions.any((pa) => pa.path == action.path && pa.content == action.content);
              return AIActionFileItem(
                action: action,
                isPending: isActionPending,
                onShowDiff: () => _showDiffDialog(action),
                onRemove: () => ref.read(aiProvider.notifier).removeAction(action),
              );
            },
          ),
          if (isPending) ...[
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${l10n.filesCount(pendingActions.length)} ${l10n.withChanges}',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          for (final action in List<AIAction>.from(pendingActions)) {
                            ref.read(aiProvider.notifier).removeAction(action);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          l10n.rejectAll,
                          style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await ref.read(aiProvider.notifier).executeActionsManually(pendingActions);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E60FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: Text(
                          l10n.acceptAll,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.circle_check, size: 12, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    l10n.changesApplied,
                    style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showDiffDialog(AIAction action) async {
    final file = File(action.path);
    String originalContent = '';
    if (await file.exists()) {
      originalContent = await file.readAsString();
    }

    if (!mounted) return;

    final workspacePath = ref.read(workspaceProvider).currentPath;
    final relPath = (workspacePath != null && action.path.startsWith(workspacePath))
        ? p.relative(action.path, from: workspacePath)
        : action.path;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D27),
        title: Text(AppLocalizations.of(context)!.changesInFile(action.path.split('/').last), style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.7,
          child: GitDiffPage(
            relativePath: relPath, 
            initiallyStaged: false,
            originalOverride: originalContent,
            previewContent: action.content,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close)),
          ElevatedButton(
            onPressed: () {
              ref.read(aiProvider.notifier).executeActionManually(action);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.apply),
          ),
        ],
      ),
    );
  }

  List<Widget> _renderMarkdown(String text, BuildContext context) {
    final List<Widget> widgets = [];
    final regex = RegExp(r'```([a-zA-Z0-9_\-+]*)\n([\s\S]*?)```');
    
    int lastIndex = 0;
    
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        final prevText = text.substring(lastIndex, match.start).trim();
        if (prevText.isNotEmpty) {
          widgets.add(_buildTextSection(prevText));
        }
      }
      
      final language = match.group(1)?.trim() ?? '';
      final code = match.group(2) ?? '';
      widgets.add(_buildCodeBlock(code, language, context));
      
      lastIndex = match.end;
    }
    
    if (lastIndex < text.length) {
      final remainingText = text.substring(lastIndex).trim();
      if (remainingText.isNotEmpty) {
        widgets.add(_buildTextSection(remainingText));
      }
    }
    
    return widgets;
  }

  Widget _buildTextSection(String text) {
    final lines = text.split('\n');
    final List<Widget> lineWidgets = [];
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        lineWidgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6.0, right: 6.0),
                  child: Icon(LucideIcons.circle, size: 4, color: Colors.purpleAccent),
                ),
                Expanded(
                  child: _buildInlineFormattedText(trimmed.substring(2)),
                ),
              ],
            ),
          ),
        );
      } else {
        lineWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: _buildInlineFormattedText(trimmed),
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lineWidgets,
    );
  }

  Widget _buildInlineFormattedText(String text) {
    final List<TextSpan> spans = [];
    final boldRegex = RegExp(r'\*\*(.*?)\*\*');
    int lastIndex = 0;
    
    for (final match in boldRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ));
      lastIndex = match.end;
    }
    
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }
    
    return SelectableText.rich(
      TextSpan(
        children: spans,
        style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5),
      ),
    );
  }

  Widget _buildCodeBlock(String code, String language, BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.codeCopied),
                        duration: const Duration(seconds: 1),
                        backgroundColor: const Color(0xFF1E2230),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.copy, size: 12, color: Colors.white38),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)!.copy,
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SelectableText(
              code.trim(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AIActionFileItem extends ConsumerStatefulWidget {
  final AIAction action;
  final VoidCallback onShowDiff;
  final VoidCallback onRemove;
  final bool isPending;

  const AIActionFileItem({
    super.key,
    required this.action,
    required this.onShowDiff,
    required this.onRemove,
    this.isPending = true,
  });

  @override
  ConsumerState<AIActionFileItem> createState() => _AIActionFileItemState();
}

class _AIActionFileItemState extends ConsumerState<AIActionFileItem> {
  int _additions = 0;
  int _deletions = 0;
  bool _calculated = false;

  @override
  void initState() {
    super.initState();
    _calculateDiffStats();
  }

  @override
  void didUpdateWidget(AIActionFileItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action.content != widget.action.content || oldWidget.action.path != widget.action.path) {
      _calculateDiffStats();
    }
  }

  Future<void> _calculateDiffStats() async {
    if (widget.action.type == 'command') return;
    
    try {
      final file = File(widget.action.path);
      String originalContent = '';
      if (widget.action.type == 'edit' && await file.exists()) {
        originalContent = await file.readAsString();
      }
      final modifiedContent = widget.action.content;

      final dmp = DiffMatchPatch();
      final diffs = dmp.diff(originalContent, modifiedContent);
      dmp.diffCleanupSemantic(diffs);

      int additions = 0;
      int deletions = 0;

      for (final d in diffs) {
        final lineCount = '\n'.allMatches(d.text).length + (d.text.isNotEmpty ? 1 : 0);
        if (d.operation == DIFF_INSERT) {
          additions += lineCount;
        } else if (d.operation == DIFF_DELETE) {
          deletions += lineCount;
        }
      }

      if (mounted) {
        setState(() {
          _additions = additions;
          _deletions = deletions;
          _calculated = true;
        });
      }
    } catch (_) {
      // Fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    final displayPath = (workspacePath != null && widget.action.path.startsWith(workspacePath))
        ? p.relative(widget.action.path, from: workspacePath)
        : widget.action.path;

    final fileName = displayPath.split('/').last;
    final dirPath = displayPath.contains('/') 
        ? displayPath.substring(0, displayPath.lastIndexOf('/')) 
        : '';

    Color typeColor;
    IconData typeIcon;
    switch (widget.action.type) {
      case 'edit':
        typeColor = Colors.blueAccent;
        typeIcon = LucideIcons.pencil;
        break;
      case 'create':
        typeColor = Colors.greenAccent;
        typeIcon = LucideIcons.file_plus;
        break;
      case 'delete':
        typeColor = Colors.redAccent;
        typeIcon = LucideIcons.file_x;
        break;
      case 'command':
        typeColor = Colors.amberAccent;
        typeIcon = LucideIcons.terminal;
        break;
      default:
        typeColor = Colors.white38;
        typeIcon = LucideIcons.sparkles;
    }

    const permissionService = AiPermissionService();
    
    // Evaluate risk and path scoping
    final inScope = widget.action.type == 'command' || permissionService.isPathInScope(widget.action.path, workspacePath ?? '');
    final risk = permissionService.evaluateActionRisk(widget.action, workspacePath ?? '');
    
    Color riskColor;
    String riskLabel;
    
    if (!inScope) {
      riskColor = Colors.redAccent;
      riskLabel = AppLocalizations.of(context)!.outOfScope;
    } else {
      switch (risk) {
        case AiRiskLevel.low:
          riskColor = Colors.greenAccent;
          riskLabel = AppLocalizations.of(context)!.low;
          break;
        case AiRiskLevel.medium:
          riskColor = Colors.purpleAccent;
          riskLabel = AppLocalizations.of(context)!.medium;
          break;
        case AiRiskLevel.high:
          riskColor = Colors.orangeAccent;
          riskLabel = AppLocalizations.of(context)!.high;
          break;
      }
    }

    return InkWell(
      onTap: () {
        if (widget.action.type == 'edit' || widget.action.type == 'create') {
          ref.read(editorProvider.notifier).openFile(widget.action.path);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File name row + diff stats
            Row(
              children: [
                Icon(typeIcon, size: 13, color: typeColor),
                const SizedBox(width: 7),
                Expanded(
                  child: widget.action.type == 'command'
                      ? Text(
                          widget.action.content,
                          style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Row(
                          children: [
                            Flexible(
                              child: Text(
                                fileName,
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (dirPath.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  dirPath,
                                  style: GoogleFonts.inter(color: Colors.white30, fontSize: 10.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                // Diff stats +N -N
                if (widget.action.type != 'command' && _calculated) ...[
                  if (_additions > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '+$_additions',
                      style: GoogleFonts.jetBrainsMono(color: const Color(0xFF4EC994), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                  if (_deletions > 0) ...[
                    const SizedBox(width: 2),
                    Text(
                      '-$_deletions',
                      style: GoogleFonts.jetBrainsMono(color: const Color(0xFFFF6B6B), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ],
            ),
            // Risk badge + action buttons row
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: riskColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    riskLabel,
                    style: GoogleFonts.inter(color: riskColor, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                if (widget.isPending) ...[
                  // Diff preview link
                  if (widget.action.type == 'edit' || widget.action.type == 'create') ...[
                    InkWell(
                      onTap: widget.onShowDiff,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.diff, size: 10, color: Colors.white38),
                            const SizedBox(width: 3),
                            Text('Diff', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // Keep / Accept button
                  InkWell(
                    onTap: () => ref.read(aiProvider.notifier).executeActionManually(widget.action),
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F5132).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFF4EC994).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.keep,
                        style: GoogleFonts.inter(color: const Color(0xFF4EC994), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Reject button
                  InkWell(
                    onTap: widget.onRemove,
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C1818).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.reject,
                        style: GoogleFonts.inter(color: const Color(0xFFFF6B6B), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ] else ...[
                  if (widget.action.type == 'edit' || widget.action.type == 'create') ...[
                    InkWell(
                      onTap: widget.onShowDiff,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.eye, size: 10, color: Colors.white38),
                            const SizedBox(width: 3),
                            Text(AppLocalizations.of(context)!.viewAction, style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.circle_check, size: 10, color: Color(0xFF4EC994)),
                      const SizedBox(width: 3),
                      Text(
                        AppLocalizations.of(context)!.applied,
                        style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF4EC994), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

