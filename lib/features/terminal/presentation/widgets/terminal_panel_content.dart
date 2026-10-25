import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:convert';
import 'dart:io';
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
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/quantum_plugin_service.dart';

import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';

import 'package:quantum_ide/l10n/app_localizations.dart';

import 'package:quantum_ide/features/git/presentation/widgets/git_panel.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/apk_signer_widget.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_text_selection_modal.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_selection_overlay.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quantum_ide/features/editor/presentation/widgets/debugger_panel.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class CopyTextIntent extends Intent {
  const CopyTextIntent();
}

class PasteTextIntent extends Intent {
  const PasteTextIntent();
}

class SelectAllTextIntent extends Intent {
  const SelectAllTextIntent();
}

class TerminalFocusNode extends FocusNode {
  bool allowAutoKeyboard;

  TerminalFocusNode({this.allowAutoKeyboard = true});

  @override
  bool consumeKeyboardToken() {
    if (!allowAutoKeyboard) {
      super.consumeKeyboardToken();
      return false;
    }
    return super.consumeKeyboardToken();
  }
}

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
  bool _isMobileKeyboardActive = false;
  bool _inlineSelectionMode = false;
  String _inlineSelectedText = '';
  int _problemsSeverityFilter = 0; // 0: Все, 1: Ошибки, 2: Предупреждения, 3: Инфо
  int _buildSubTab = 0;
  bool _isWakelockEnabled = false;
  double _pinchBaseFontSize = 13.0;
  final Map<int, Offset> _pinchPointers = {};
  double? _initialPinchDistance;

  Widget _buildTerminalPinchWrapper({required Widget child}) {
    return Listener(
      onPointerDown: (event) {
        _pinchPointers[event.pointer] = event.position;
        if (_pinchPointers.length == 2) {
          final points = _pinchPointers.values.toList();
          _initialPinchDistance = (points[0] - points[1]).distance;
          _pinchBaseFontSize = ref.read(settingsProvider).terminalFontSize;
        }
      },
      onPointerMove: (event) {
        _pinchPointers[event.pointer] = event.position;
        if (_pinchPointers.length >= 2 && _initialPinchDistance != null && _initialPinchDistance! > 0) {
          final points = _pinchPointers.values.toList();
          final currentDistance = (points[0] - points[1]).distance;
          final scale = currentDistance / _initialPinchDistance!;
          final newSize = (_pinchBaseFontSize * scale).clamp(8.0, 32.0);
          if ((newSize - ref.read(settingsProvider).terminalFontSize).abs() >= 0.5) {
            ref.read(settingsProvider.notifier).setTerminalFontSize(newSize);
          }
        }
      },
      onPointerUp: (event) {
        _pinchPointers.remove(event.pointer);
        if (_pinchPointers.length < 2) {
          _initialPinchDistance = null;
        }
      },
      onPointerCancel: (event) {
        _pinchPointers.remove(event.pointer);
        if (_pinchPointers.length < 2) {
          _initialPinchDistance = null;
        }
      },
      child: child,
    );
  }

  void _showUrlDetected(String url) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.external_link, size: 16, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 12),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Открыть',
          textColor: Colors.cyanAccent,
          onPressed: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String? _findUrlAt(String line, int col) {
    final regExp = RegExp(r'https?://[^\s<>"]+|ftp://[^\s<>"]+');
    for (final match in regExp.allMatches(line)) {
      if (col >= match.start && col <= match.end) {
        return match.group(0);
      }
    }
    return null;
  }

  final Map<String, GlobalKey<xt.TerminalViewState>> _terminalKeys = {};
  final Map<String, GlobalKey<_AndroidTerminalDirectInputState>> _directInputKeys = {};
  final Map<String, TerminalFocusNode> _terminalFocusNodes = {};

  GlobalKey<xt.TerminalViewState> _getTerminalKey(String id) {
    return _terminalKeys.putIfAbsent(id, () => GlobalKey<xt.TerminalViewState>());
  }

  GlobalKey<_AndroidTerminalDirectInputState> _getDirectInputKey(String id) {
    return _directInputKeys.putIfAbsent(id, () => GlobalKey<_AndroidTerminalDirectInputState>());
  }

  TerminalFocusNode _getFocusNode(String id) {
    final isMobile = Platform.isAndroid || Platform.isIOS || (mounted && MediaQuery.of(context).size.width < 650);
    return _terminalFocusNodes.putIfAbsent(
      id,
      () => TerminalFocusNode(allowAutoKeyboard: !isMobile),
    );
  }

  void _openTerminalKeyboard(TerminalSession session, {bool isSecondary = false}) {
    if (_inlineSelectionMode) return;
    if (session.xtermViewController.selection != null) return;

    final wasActive = _isMobileKeyboardActive;
    _isMobileKeyboardActive = true;
    final keyId = isSecondary ? '${session.id}_sec' : session.id;
    final focusNode = _getFocusNode(keyId);
    focusNode.allowAutoKeyboard = true;
    focusNode.requestFocus();
    if (Platform.isAndroid || Platform.isIOS) {
      _getDirectInputKey(keyId).currentState?.requestKeyboard();
    } else {
      _getTerminalKey(keyId).currentState?.requestKeyboard();
    }
    SystemChannels.textInput.invokeMethod('TextInput.show');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        focusNode.allowAutoKeyboard = false;
      }
    });
    if (mounted && !wasActive) setState(() {});
  }

  void _closeTerminalKeyboard(TerminalSession session, {bool isSecondary = false}) {
    final wasActive = _isMobileKeyboardActive;
    _isMobileKeyboardActive = false;
    final keyId = isSecondary ? '${session.id}_sec' : session.id;
    if (Platform.isAndroid || Platform.isIOS) {
      _getDirectInputKey(keyId).currentState?.closeKeyboard();
    } else {
      _getTerminalKey(keyId).currentState?.closeKeyboard();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (mounted && wasActive) setState(() {});
  }

  void _toggleTerminalKeyboard(TerminalSession session, {bool isSecondary = false}) {
    if (_inlineSelectionMode) {
      setState(() {
        _inlineSelectionMode = false;
        _inlineSelectedText = '';
      });
    }
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset > 20) {
      _closeTerminalKeyboard(session, isSecondary: isSecondary);
    } else if (_isMobileKeyboardActive && bottomInset == 0 && !Platform.isAndroid && !Platform.isIOS) {
      _closeTerminalKeyboard(session, isSecondary: isSecondary);
    } else {
      _openTerminalKeyboard(session, isSecondary: isSecondary);
    }
  }

  String _currentInput = '';
  final ValueNotifier<List<String>?> _suggestionsNotifier = ValueNotifier(null);
  int _selectedSuggestionIndex = 0;
  List<String> _pathBinaries = [];

  TerminalSession? _lastAttachedSession;
  final Set<TerminalSession> _initializedSessions = {}; // Для контроля слушателей выделения

  @override
  void initState() {
    super.initState();
    _loadPathBinaries();
    WakelockPlus.enabled.then((val) {
      if (mounted) setState(() => _isWakelockEnabled = val);
    }).catchError((_) {});
  }

  Future<void> _toggleWakelock() async {
    try {
      final nextState = !_isWakelockEnabled;
      await WakelockPlus.toggle(enable: nextState);
      if (mounted) {
        setState(() => _isWakelockEnabled = nextState);
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  LucideIcons.coffee,
                  size: 16,
                  color: nextState ? Colors.orangeAccent : Colors.white60,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nextState
                        ? 'Режим бодрствования активен (экран не погаснет во время сборки/команд)'
                        : 'Режим бодрствования выключен',
                    style: GoogleFonts.inter(fontSize: 12),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Wakelock toggle error: $e');
    }
  }

  @override
  void dispose() {
    for (final node in _terminalFocusNodes.values) {
      node.dispose();
    }
    _terminalFocusNodes.clear();
    _terminalKeys.clear();
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

    final home = Platform.environment['HOME'] ?? '';
    final pathDirs = [
      p.join(appDir, 'rootfs', 'ubuntu', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'usr', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'usr', 'sbin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'sbin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'usr', 'local', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'root', 'flutter', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'cmdline-tools', 'latest', 'bin'),
      p.join(appDir, 'rootfs', 'ubuntu', 'root', 'android-sdk', 'platform-tools'),
      '/usr/bin',
      '/usr/local/bin',
      if (home.isNotEmpty) p.join(home, '.local', 'bin'),
    ];

    final binaries = <String>{};
    const defaultCliTools = [
      'git', 'flutter', 'dart', 'npm', 'npx', 'node', 'yarn', 'pnpm',
      'python3', 'python', 'pip', 'pip3', 'cargo', 'rustc', 'docker',
      'curl', 'wget', 'cat', 'grep', 'find', 'ssh', 'scp', 'apt', 'apt-get',
      'tar', 'zip', 'unzip', 'ps', 'kill', 'htop', 'ls', 'cd', 'mkdir',
      'rm', 'cp', 'mv', 'chmod', 'chown', 'clear', 'bash', 'sh', 'nano', 'vim',
      'df', 'free', 'uname', 'which', 'export', 'source', 'env',
    ];
    binaries.addAll(defaultCliTools);

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

  bool _isAtShellPrompt(TerminalSession session) {
    if (session.xtermTerminal.isUsingAltBuffer) return false;
    try {
      final buf = session.xtermTerminal.buffer;
      final y = buf.absoluteCursorY;
      if (y >= 0 && y < buf.lines.length) {
        final line = buf.lines[y].toString();
        return line.contains('boss@') ||
            line.contains('root@') ||
            line.contains(r'$ ') ||
            line.contains('# ');
      }
    } catch (_) {}
    return false;
  }

  void _handleInputForAutocomplete(TerminalSession session, String data) {
    if (!_isAtShellPrompt(session)) {
      if (_suggestionsNotifier.value != null) {
        _suggestionsNotifier.value = null;
      }
      _currentInput = '';
      return;
    }

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

    final query = _currentInput.trim();
    if (query.isEmpty) {
      _suggestionsNotifier.value = null;
      return;
    }

    List<String> matches = [];

    if (_currentInput.startsWith('./') ||
        _currentInput.startsWith('/') ||
        _currentInput.startsWith('~/') ||
        _currentInput.contains('/')) {
      final pathSuggestions = await _getPathSuggestions(session, _currentInput);
      if (pathSuggestions.isNotEmpty) {
        if (query.length >= 2) {
          final fuse = Fuzzy<String>(pathSuggestions, options: FuzzyOptions(threshold: 0.45));
          final results = fuse.search(query);
          matches = results.isNotEmpty
              ? results.map((r) => r.item).take(10).toList()
              : pathSuggestions.take(10).toList();
        } else {
          matches = pathSuggestions.take(10).toList();
        }
      }
    } else {
      if (_pathBinaries.isNotEmpty) {
        final queryLower = query.toLowerCase();
        final prefixMatches = _pathBinaries
            .where((bin) => bin.toLowerCase().startsWith(queryLower))
            .take(6)
            .toList();

        final fuse = Fuzzy<String>(
          _pathBinaries,
          options: FuzzyOptions(
            threshold: 0.35,
            isCaseSensitive: false,
          ),
        );
        final fuzzyMatches = fuse.search(queryLower).map((r) => r.item).take(8).toList();

        final combined = <String>{...prefixMatches, ...fuzzyMatches};
        matches = combined.take(10).toList();
      }
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
    if (suggestion.startsWith(_currentInput)) {
      final toSend = suggestion.substring(_currentInput.length);
      session.pty.write(Uint8List.fromList(utf8.encode(toSend)));
    } else {
      final delSequence = '\x7f' * _currentInput.length;
      session.pty.write(Uint8List.fromList(utf8.encode('$delSequence$suggestion')));
    }
    _currentInput = suggestion;
    _suggestionsNotifier.value = null;
  }

  String _sanitizeTerminalInput(String text) {
    return text
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('«', '"')
        .replaceAll('»', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('—', '--')
        .replaceAll('–', '-');
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
        final sanitized = _sanitizeTerminalInput(sequence);
        session.pty.write(Uint8List.fromList(utf8.encode(sanitized)));
        if (sanitized.length == 1 && data.length == 1) {
          _handleInputForAutocomplete(session, sanitized);
        }
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

  void _toggleInlineSelectionMode(TerminalSession session) {
    setState(() {
      _inlineSelectionMode = !_inlineSelectionMode;
      _inlineSelectedText = '';
    });
    if (_inlineSelectionMode) {
      _closeTerminalKeyboard(session);
    }
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
    if (value == 'toggle_keyboard') {
      _toggleTerminalKeyboard(session);
      return;
    }
    if (value == 'inline_selection_mode') {
      _toggleInlineSelectionMode(session);
      return;
    }
    if (value == 'selection_mode') {
      TerminalTextSelectionModal.show(context, session.xtermTerminal, session.title);
      return;
    }
    if (value == 'copy_all_output') {
      _copyTerminalOutputDirect(session);
      return;
    }
    if (value.startsWith('cmd:')) {
      final cmd = value.substring(4);
      if (_inlineSelectionMode) {
        setState(() {
          _inlineSelectionMode = false;
          _inlineSelectedText = '';
        });
      }
      session.pty.write(Uint8List.fromList(utf8.encode(cmd)));
      return;
    }
    if (value == 'paste') {
      await _pasteToTerminal(session);
      return;
    }
    if (value == 'copy') {
      if (_inlineSelectionMode && _inlineSelectedText.trim().isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: _inlineSelectedText));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.copiedToClipboard),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
        }
        return;
      }
      await _copySelection(session);
      return;
    }
    if (value == 'select_all' || value == 'sel') {
      _selectAllInTerminal(session);
      return;
    }
    if (value == 'ctrl+c') {
      session.pty.write(Uint8List.fromList([3])); 
      return;
    }
    if (value == 'ctrl+z') {
      session.pty.write(Uint8List.fromList([26])); 
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
    } else if (value == '\x1b[H' || value == '\x1b[F' || value == '\x1b[5~' || value == '\x1b[6~') {
      session.pty.write(Uint8List.fromList(utf8.encode(value)));
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
    if (hadCtrl || hadAlt || hadShift) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelState = ref.watch(panelProvider);
    final sessions = ref.watch(terminalTabsProvider);
    final notifier = ref.read(terminalTabsProvider.notifier);
    final editorState = ref.watch(editorProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0F14), 
      ),
      child: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.onlyTerminal ? bottomInset : 0),
          child: Column(
            children: [
              Expanded(
                child: widget.onlyTerminal
                    ? _buildTerminalView(sessions, notifier, key: const ValueKey('terminal'))
                    : _buildBody(panelState, sessions, notifier, editorState),
              ),
              if ((widget.onlyTerminal || panelState.selectedTab == PanelTab.terminal) &&
                  sessions.isNotEmpty &&
                  notifier.currentIndex < sessions.length &&
                  ((bottomInset <= 20) && !_isMobileKeyboardActive))
                _buildPluginCommandsBar(sessions[notifier.currentIndex]),
              if ((widget.onlyTerminal || panelState.selectedTab == PanelTab.terminal) &&
                  (Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 650))
                _buildVirtualKeys(sessions, notifier),
            ],
          ),
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
    return const SidebarGitPanel(isBottomPanel: true);
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
    final ws = ref.watch(workspaceProvider).currentPath ?? '';
    final isFlutter = ws.isNotEmpty && File(p.join(ws, 'pubspec.yaml')).existsSync();
    final isNativeAndroid = ws.isNotEmpty && !isFlutter && (
      File(p.join(ws, 'build.gradle.kts')).existsSync() ||
      File(p.join(ws, 'build.gradle')).existsSync() ||
      File(p.join(ws, 'settings.gradle.kts')).existsSync() ||
      File(p.join(ws, 'settings.gradle')).existsSync() ||
      File(p.join(ws, 'gradlew')).existsSync()
    );

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
                      if (isFlutter)
                        _buildActionButton(l10n.buildPC, LucideIcons.laptop, Colors.cyanAccent, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get && flutter build linux --release')),
                      _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange, () {
                        if (isNativeAndroid) {
                          _runDedicatedCommand(DedicatedTerminalType.build, '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; ./gradlew --no-daemon --max-workers=1 assembleRelease && (cp app/build/outputs/apk/release/app-release-unsigned.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/app-release.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/*.apk ./app-release.apk 2>/dev/null || true) && echo "✓ Release APK: ./app-release.apk"');
                        } else {
                          _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get && (sed -i "/extra-gen-snapshot-options/d" android/gradle.properties ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation && (cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./app-release.apk 2>/dev/null || true)');
                        }
                      }),
                      if (isNativeAndroid)
                        _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow, () => _runDedicatedCommand(DedicatedTerminalType.build, '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; ./gradlew --no-daemon --max-workers=1 assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"')),
                      if (isFlutter)
                        _buildActionButton('Pub Get', LucideIcons.download, Colors.blue, () => _runDedicatedCommand(DedicatedTerminalType.build, 'flutter pub get')),
                      _buildActionButton('Clean', LucideIcons.trash_2, Colors.red, () {
                        if (isNativeAndroid) {
                          _runDedicatedCommand(DedicatedTerminalType.build, 'chmod +x ./gradlew 2>/dev/null; ./gradlew clean && rm -f ./app-release.apk ./app-debug.apk');
                        } else {
                          _runDedicatedCommand(DedicatedTerminalType.build, 'flutter clean');
                        }
                      }),
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
          _buildActionButton(l10n.setupSdk, LucideIcons.settings, Colors.purpleAccent, () => _runDedicatedCommand(DedicatedTerminalType.appLogs, 'kill -9 \$(pgrep -x "apt|apt-get|dpkg|dpkg-deb" 2>/dev/null) 2>/dev/null ; rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null ; dpkg --configure -a 2>/dev/null ; apt update && apt install -y debianutils libz1 libexpat1 openjdk-21-jdk wget unzip libstdc++6 zlib1g zlib1g-dev libncurses6 libtinfo6 libc++1 libc6 aapt adb zipalign apksigner clang lld cmake ninja-build pkg-config libgtk-3-dev && git config --global --add safe.directory \'*\' && mkdir -p /root/android-sdk/licenses && printf "24333f8a63b6825ea9c5514f83c2829b004d1fee\\nd56f5187479451eabf01fb78af6dfcb131a6481e\\n2fa2d150aa0a1204d10e5ed57ab8369e7b50077c\\n" > /root/android-sdk/licenses/android-sdk-license && printf "84831b9409646a918e30573bab4c9c91346d8abd\\n" > /root/android-sdk/licenses/android-sdk-preview-license && printf "859f317696f67ef3d7f30a50a5560e7834b43903\\n" > /root/android-sdk/licenses/android-sdk-arm-dbt-license && (flutter config --android-sdk /root/android-sdk 2>/dev/null || true) && (flutter config --jdk-dir /usr/lib/jvm/java-17-openjdk-arm64 2>/dev/null || flutter config --jdk-dir /usr/lib/jvm/java-21-openjdk-arm64 2>/dev/null || true) && (which which >/dev/null || (echo "#!/bin/sh" > /usr/bin/which && echo "command -v \$1" >> /usr/bin/which && chmod +x /usr/bin/which))')),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              title.toUpperCase(), 
              style: GoogleFonts.inter(
                color: Colors.cyanAccent, 
                fontSize: 8.5, 
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0
              )
            ),
          ),
          const SizedBox(width: 8),
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
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 12, color: color.withValues(alpha: 0.9)),
            ),
          ),
        ),
      ),
    );
  }

  void _runDedicatedCommand(DedicatedTerminalType type, String cmd) {
    final workspace = ref.read(workspaceProvider);
    final path = workspace.currentPath;
    
    final cdCmd = path != null ? 'cd "$path"' : '';
    final safeCmd = cmd.replaceAll('"', '\\"');
    final banner = 'printf "\\033[1;36m▶ ЗАПУСК КОМАНДЫ:\\033[0m \\033[1;33m%s\\033[0m\\n\\033[0;34m--------------------------------------------------\\033[0m\\n" "$safeCmd"';
    final fullCmd = cdCmd.isNotEmpty ? '$cdCmd && $banner && $cmd' : '$banner && $cmd';
    ref.read(dedicatedTerminalProvider.notifier).sendCommand(type, fullCmd, interrupt: true, clear: false);
  }

  void _sendRawKeyToDedicatedTerminal(DedicatedTerminalType type, String key) {
    ref.read(dedicatedTerminalProvider.notifier).sendRawChar(type, key);
  }

  String _extractTerminalText(xt.Terminal terminal) {
    final buffer = terminal.buffer;
    final rawLines = <String>[];
    for (var i = 0; i < buffer.lines.length; i++) {
      rawLines.add(buffer.lines[i].toString().trimRight());
    }
    while (rawLines.isNotEmpty && rawLines.last.isEmpty) {
      rawLines.removeLast();
    }
    final deduped = _deduplicateTerminalLines(rawLines);
    return deduped.join('\n');
  }

  /// Removes consecutive duplicate multi-line blocks caused by TUI redraws
  /// overflowing into the scrollback buffer.
  List<String> _deduplicateTerminalLines(List<String> lines) {
    if (lines.length < 6) return lines;
    final result = <String>[];
    int i = 0;
    while (i < lines.length) {
      bool skippedBlock = false;
      final maxWindow = ((lines.length - i) ~/ 2).clamp(0, 80);
      for (int w = maxWindow; w >= 3; w--) {
        int nonEmpty = 0;
        bool matches = true;
        for (int k = 0; k < w; k++) {
          if (lines[i + k] != lines[i + w + k]) {
            matches = false;
            break;
          }
          if (lines[i + k].trim().isNotEmpty) nonEmpty++;
        }
        if (matches && nonEmpty >= 2) {
          // Skip the first copy of the repeated block and advance to the second copy
          i += w;
          skippedBlock = true;
          break;
        }
      }
      if (!skippedBlock) {
        result.add(lines[i]);
        i++;
      }
    }
    return result;
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

  Future<void> _copyTerminalOutputDirect(TerminalSession session) async {
    final text = _extractTerminalText(session.xtermTerminal);
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.check, color: Colors.greenAccent, size: 15),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.copiedToClipboard),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Widget _buildTerminalActionButton(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: (color ?? Colors.white).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.1), width: 0.5),
              ),
              child: Icon(icon, size: 12, color: color ?? Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionsSidebarList(List<TerminalSession> sessions, TerminalTabsNotifier notifier, {bool isOverlay = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131722).withValues(alpha: 0.95),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 14, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Text(
                  'СЕССИИ',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${sessions.length}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => notifier.createNewSession(),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2), width: 0.8),
                      ),
                      child: const Icon(LucideIcons.plus, size: 13, color: Colors.cyanAccent),
                    ),
                  ),
                ),
                if (isOverlay) ...[
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _isSidebarOpen = false),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        child: const Icon(LucideIcons.x, size: 14, color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final isActive = index == notifier.currentIndex;
                final session = sessions[index];
                final isExited = session.isExited;
                final statusColor = isExited ? Colors.redAccent : Colors.greenAccent;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: isActive 
                        ? Colors.cyanAccent.withValues(alpha: 0.1) 
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive 
                          ? Colors.cyanAccent.withValues(alpha: 0.4) 
                          : Colors.white.withValues(alpha: 0.04),
                      width: isActive ? 1.0 : 0.6,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        notifier.currentIndex = index;
                        if (isOverlay) {
                          setState(() => _isSidebarOpen = false);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.6),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: isActive ? Colors.white : Colors.white70,
                                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    isExited ? 'Остановлен' : 'Работает',
                                    style: GoogleFonts.inter(
                                      fontSize: 8.5,
                                      color: statusColor.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isActive || sessions.length > 1)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => notifier.restartSession(index),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(
                                          isExited ? LucideIcons.play : LucideIcons.refresh_cw,
                                          size: 11,
                                          color: isExited ? Colors.greenAccent : Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => notifier.closeSession(index),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(LucideIcons.trash_2, size: 11, color: Colors.redAccent),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalView(List<TerminalSession> sessions, TerminalTabsNotifier notifier, {Key? key}) {
    if (sessions.isEmpty) return const Center(child: CircularProgressIndicator());
    final currentSession = sessions[notifier.currentIndex];

    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 650;

        final terminalContent = Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1219),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _isSidebarOpen 
                            ? Colors.cyanAccent.withValues(alpha: 0.15) 
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isSidebarOpen 
                              ? Colors.cyanAccent.withValues(alpha: 0.3) 
                              : Colors.white.withValues(alpha: 0.08),
                          width: 0.6,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.terminal,
                            size: 13,
                            color: _isSidebarOpen ? Colors.cyanAccent : Colors.white70,
                          ),
                          if (sessions.length > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${sessions.length}',
                              style: TextStyle(
                                color: _isSidebarOpen ? Colors.cyanAccent : Colors.white60,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: currentSession.isExited ? Colors.redAccent : Colors.greenAccent,
                      boxShadow: [
                        BoxShadow(
                          color: (currentSession.isExited ? Colors.redAccent : Colors.greenAccent).withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      currentSession.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        ref.watch(workspaceProvider).currentPath?.split('/').last ?? 'workspace',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white30,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (!isCompact) ...[
                    _buildTerminalActionButton(
                      _isTerminalSplit ? LucideIcons.square : LucideIcons.columns_2,
                      _isTerminalSplit ? 'Объединить' : 'Разделить экран',
                      () {
                        setState(() {
                          _isTerminalSplit = !_isTerminalSplit;
                          if (_isTerminalSplit && sessions.length < 2) {
                            notifier.createNewSession();
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 3),
                    _buildTerminalActionButton(
                      LucideIcons.coffee,
                      _isWakelockEnabled ? 'Экран не гаснет (активно)' : 'Не гасить экран (Wakelock)',
                      _toggleWakelock,
                      color: _isWakelockEnabled ? Colors.orangeAccent : Colors.white60,
                    ),
                    const SizedBox(width: 3),
                  ],
                  _buildTerminalActionButton(
                    LucideIcons.plus,
                    'Новая сессия',
                    () => notifier.createNewSession(),
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 4),
                  Material(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: () {
                        currentSession.xtermTerminal.eraseDisplay();
                        currentSession.xtermTerminal.eraseScrollbackOnly();
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        child: Text(
                          'CLR',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white60,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  _buildTerminalActionButton(
                    LucideIcons.ellipsis_vertical,
                    'Меню терминала',
                    () => _showTerminalContextMenu(context, Offset.zero, currentSession, fromToolbar: true),
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
                                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
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
                                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
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
                                      onTap: () => setState(() => _isTerminalSplit = false),
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
        );

        if (!isCompact) {
          return Row(
            children: [
              if (_isSidebarOpen)
                SizedBox(
                  width: 220,
                  child: _buildSessionsSidebarList(sessions, notifier, isOverlay: false),
                ),
              Expanded(child: terminalContent),
            ],
          );
        }

        return Stack(
          children: [
            terminalContent,
            if (_isSidebarOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _isSidebarOpen = false),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.65),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 230,
                child: _buildSessionsSidebarList(sessions, notifier, isOverlay: true),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildInlineSelectableTerminal(
    TerminalSession session,
    xt.TerminalTheme theme,
    double terminalFontSize,
  ) {
    final fullText = _extractTerminalText(session.xtermTerminal);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.45), width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF151924),
              border: Border(
                bottom: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.25)),
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.mouse_pointer_click, size: 13, color: Colors.cyanAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _inlineSelectedText.isNotEmpty
                        ? 'Выделено символов: ${_inlineSelectedText.length}'
                        : 'Выделяйте текст прямо в терминале (зажмите или проведите)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyanAccent,
                    ),
                  ),
                ),
                if (_inlineSelectedText.isNotEmpty) ...[
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: _inlineSelectedText));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.copiedToClipboard),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.copy, size: 12, color: Colors.cyanAccent),
                          const SizedBox(width: 4),
                          Text(
                            l10n.copy,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      final sel = _inlineSelectedText;
                      ref.read(rightChatPanelOpenProvider.notifier).state = true;
                      ref.read(aiProvider.notifier).askAI(
                        'Помоги разобраться с этим выводом из терминала:\n```\n$sel\n```',
                      );
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'AI ✨',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.purpleAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                InkWell(
                  onTap: () => _copyTerminalOutputDirect(session),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'Копировать всё',
                      style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white70),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() {
                    _inlineSelectionMode = false;
                    _inlineSelectedText = '';
                  }),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'К вводу ✕',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                reverse: true,
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    fullText.isEmpty ? '(Пустой вывод терминала)' : fullText,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: terminalFontSize,
                      color: theme.foreground,
                      height: 1.35,
                    ),
                    onSelectionChanged: (selection, cause) {
                      if (selection.start >= 0 &&
                          selection.end <= fullText.length &&
                          selection.start != selection.end) {
                        final selected = fullText.substring(selection.start, selection.end);
                        if (selected != _inlineSelectedText) {
                          setState(() => _inlineSelectedText = selected);
                        }
                      } else if (_inlineSelectedText.isNotEmpty) {
                        setState(() => _inlineSelectedText = '');
                      }
                    },
                    contextMenuBuilder: (context, editableTextState) {
                      final List<ContextMenuButtonItem> buttonItems =
                          editableTextState.contextMenuButtonItems;
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: editableTextState.contextMenuAnchors,
                        buttonItems: buttonItems,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalWidget(TerminalSession session, {bool isSecondary = false}) {
    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _getTerminalTheme(terminalThemeName);
    final isMobile = Platform.isAndroid || Platform.isIOS || MediaQuery.of(context).size.width < 650;
    final keyId = isSecondary ? '${session.id}_sec' : session.id;

    if (!isSecondary) {
      if (_lastAttachedSession != session) {
        _lastAttachedSession = session;
        _currentInput = '';
        _suggestionsNotifier.value = null;
        _attachTerminalOutputListener(session);
      }

      if (!_initializedSessions.contains(session)) {
        _initializedSessions.add(session);
      }
    }

    if (_inlineSelectionMode && !isSecondary) {
      return _buildInlineSelectableTerminal(session, theme, terminalFontSize);
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    CopyTextIntent: CallbackAction<CopyTextIntent>(
                      onInvoke: (intent) => _copySelection(session),
                    ),
                    PasteTextIntent: CallbackAction<PasteTextIntent>(
                      onInvoke: (intent) => _pasteToTerminal(session),
                    ),
                    SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
                      onInvoke: (intent) => _selectAllInTerminal(session),
                    ),
                  },
                  child: Focus(
                    autofocus: !isMobile,
                    child: Shortcuts(
                      shortcuts: <LogicalKeySet, Intent>{
                        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC): const CopyTextIntent(),
                        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC): const CopyTextIntent(),
                        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV): const PasteTextIntent(),
                        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV): const PasteTextIntent(),
                        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA): const SelectAllTextIntent(),
                        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA): const SelectAllTextIntent(),
                      },
                      child: _buildTerminalPinchWrapper(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onSecondaryTapDown: (details) {
                            if (session.xtermViewController.selection != null) {
                              _copySelection(session);
                            } else {
                              _pasteToTerminal(session);
                            }
                          },
                          child: _AndroidTerminalDirectInput(
                            key: _getDirectInputKey(keyId),
                            terminal: session.xtermTerminal,
                            focusNode: _getFocusNode(keyId),
                            enabled: Platform.isAndroid || Platform.isIOS,
                            child: LayoutBuilder(
                              builder: (context, viewConstraints) {
                                final kbInset = widget.onlyTerminal
                                    ? MediaQuery.of(context).viewInsets.bottom
                                    : 0.0;
                                final fullHeight = viewConstraints.maxHeight + kbInset;
                                final buf = session.xtermTerminal.buffer;
                                final alignBottom = kbInset > 20 &&
                                    (session.xtermTerminal.isUsingAltBuffer ||
                                        buf.scrollBack > 0 ||
                                        buf.cursorY > (buf.viewHeight * 0.4));
                                final termView = xt.TerminalView(
                                  key: _getTerminalKey(keyId),
                                  session.xtermTerminal,
                                  controller: session.xtermViewController,
                                  focusNode: _getFocusNode(keyId),
                                  autofocus: !isMobile,
                                  hardwareKeyboardOnly: Platform.isAndroid || Platform.isIOS,
                                  onTapUp: (details, offset) {
                                    if (session.xtermViewController.selection != null) {
                                      session.xtermViewController.clearSelection();
                                      return;
                                    }

                                    final lineIndex = offset.y;
                                    final colIndex = offset.x;
                                    final buffer = session.xtermTerminal.buffer;
                                    if (lineIndex >= 0 && lineIndex < buffer.lines.length) {
                                      final lineText = buffer.lines[lineIndex].toString();
                                      final url = _findUrlAt(lineText, colIndex);
                                      if (url != null) {
                                        _showUrlDetected(url);
                                        return;
                                      }
                                    }

                                    _openTerminalKeyboard(session, isSecondary: isSecondary);
                                  },
                                  padding: const EdgeInsets.all(10),
                                  theme: theme,
                                  backgroundOpacity: 0,
                                  textStyle: xt.TerminalStyle(
                                    fontSize: terminalFontSize,
                                    fontFamily: _getFontFamily(ref.watch(settingsProvider).terminalFontFamily),
                                    fontFamilyFallback: const [
                                      'SymbolsNerdFont',
                                      'Symbols Nerd Font',
                                      'jetBrainsMono',
                                      'firaCode',
                                      'cascadia',
                                      'dejaVuSansMono',
                                      'inconsolata',
                                      'sourceCodePro',
                                      'Noto Sans Mono',
                                      'DejaVu Sans Mono',
                                      'monospace',
                                    ],
                                  ),
                                  keyboardType: TextInputType.visiblePassword,
                                  deleteDetection: true,
                                );

                                if (kbInset > 20 && fullHeight > viewConstraints.maxHeight) {
                                  return ClipRect(
                                    child: OverflowBox(
                                      minHeight: fullHeight,
                                      maxHeight: fullHeight,
                                      alignment: alignBottom
                                          ? Alignment.bottomCenter
                                          : Alignment.topCenter,
                                      child: termView,
                                    ),
                                  );
                                }
                                return termView;
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
          ],
        ),
        _buildSuggestionBox(session),
        TerminalSelectionOverlay(
          session: session,
          getViewState: () => _getTerminalKey(keyId).currentState!,
          onAskAI: (selectedText) {
            ref.read(rightChatPanelOpenProvider.notifier).state = true;
            ref.read(aiProvider.notifier).askAI(
              'Помоги разобраться с этой ошибкой/выводом из терминала:\n```\n$selectedText\n```',
            );
          },
          onSelectAll: () => _selectAllInTerminal(session),
          onPaste: () => _pasteToTerminal(session),
        ),
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
      case 'catppuccin':
        bg = const Color(0xFF1E1E2E);
        fg = const Color(0xFFCDD6F4);
        break;
      case 'nord':
        bg = const Color(0xFF2E3440);
        fg = const Color(0xFFECEFF4);
        break;
      case 'oneDark':
        bg = const Color(0xFF282C34);
        fg = const Color(0xFFABB2BF);
        break;
      case 'tokyoNight':
        bg = const Color(0xFF1A1B26);
        fg = const Color(0xFFA9B1D6);
        break;
      case 'matrix':
        bg = const Color(0xFF0D1117);
        fg = const Color(0xFF00FF66);
        break;
      case 'ubuntu':
      default:
        bg = const Color(0xFF300A24);
        fg = Colors.white;
        break;
    }

    return xt.TerminalTheme(
      cursor: fg,
      selection: const Color(0xFF264F78).withValues(alpha: 0.6),
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

    final totalErrors = allDiagnostics.values.fold<int>(
      0,
      (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.error).length,
    );
    final totalWarnings = allDiagnostics.values.fold<int>(
      0,
      (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.warning).length,
    );
    final totalHints = allDiagnostics.values.fold<int>(
      0,
      (sum, diags) => sum + diags.where((d) => d.severity == CodeDiagnosticSeverity.hint).length,
    );
    final totalProblems = totalErrors + totalWarnings + totalHints;

    final l10n = AppLocalizations.of(context)!;

    // Flatten and filter diagnostics into a sleek compact list
    final flatEntries = <MapEntry<String, CodeDiagnostic>>[];
    allDiagnostics.forEach((filePath, diags) {
      for (final d in diags) {
        if (_problemsSeverityFilter == 1 && d.severity != CodeDiagnosticSeverity.error) continue;
        if (_problemsSeverityFilter == 2 && d.severity != CodeDiagnosticSeverity.warning) continue;
        if (_problemsSeverityFilter == 3 && d.severity != CodeDiagnosticSeverity.hint) continue;
        flatEntries.add(MapEntry(filePath, d));
      }
    });

    Widget buildFilterPill(int index, String label, int count, Color color, IconData icon) {
      final isSelected = _problemsSeverityFilter == index;
      return InkWell(
        onTap: () => setState(() => _problemsSeverityFilter = index),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: isSelected ? color : Colors.white54),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final headerWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF12151E),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  buildFilterPill(0, 'Все', totalProblems, Colors.cyanAccent, LucideIcons.list_filter),
                  const SizedBox(width: 6),
                  buildFilterPill(1, 'Ошибки', totalErrors, Colors.redAccent, LucideIcons.circle_x),
                  const SizedBox(width: 6),
                  buildFilterPill(2, 'Предупр.', totalWarnings, Colors.amberAccent, LucideIcons.triangle_alert),
                  if (totalHints > 0) ...[
                    const SizedBox(width: 6),
                    buildFilterPill(3, 'Инфо', totalHints, Colors.blueAccent, LucideIcons.info),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _fixErrorsWithAI,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.sparkles, size: 12, color: Colors.white),
                  const SizedBox(width: 5),
                  Text(
                    l10n.fixWithAi,
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (flatEntries.isEmpty) {
      return Column(
        children: [
          headerWidget,
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.shield_check, color: Colors.greenAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.noErrorsFound,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        l10n.noErrorsDescription,
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ],
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
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: flatEntries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 3),
            itemBuilder: (context, index) {
              final entry = flatEntries[index];
              return _buildDiagnosticTile(entry.key, entry.value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticTile(String path, CodeDiagnostic d) {
    Color color;
    IconData icon;
    switch (d.severity) {
      case CodeDiagnosticSeverity.error:
        color = const Color(0xFFFF5555);
        icon = LucideIcons.circle_x;
        break;
      case CodeDiagnosticSeverity.warning:
        color = const Color(0xFFFFB86C);
        icon = LucideIcons.triangle_alert;
        break;
      case CodeDiagnosticSeverity.hint:
        color = const Color(0xFF58A6FF);
        icon = LucideIcons.info;
        break;
    }

    final fileName = path.split('/').last;
    final lineNum = d.range.index + 1;
    final colNum = d.range.start + 1;

    return Material(
      color: Colors.white.withValues(alpha: 0.02),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: () async {
          await ref.read(editorProvider.notifier).openFile(path);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border(
              left: BorderSide(color: color, width: 2.5),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$fileName:$lineNum:$colNum',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.cyanAccent.withValues(alpha: 0.85),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '$fileName:$lineNum:$colNum - ${d.message}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка скопирована'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(LucideIcons.copy, color: Colors.white38, size: 12),
                ),
              ),
              InkWell(
                onTap: () => _handleAiFix(path, d),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(LucideIcons.sparkles, color: Colors.cyanAccent, size: 13),
                ),
              ),
            ],
          ),
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
  void _showTerminalContextMenu(BuildContext context, Offset position, TerminalSession session, {bool fromToolbar = false}) async {
    HapticFeedback.mediumImpact();
    final isMobile = MediaQuery.of(context).size.width < 700;

    if (isMobile || fromToolbar) {
      _showMobileTerminalBottomSheet(context, session);
      return;
    }

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
      color: const Color(0xFF1E2230),
      elevation: 12,
      useRootNavigator: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      items: [
        const PopupMenuItem(
          value: 'inline_selection',
          height: 38,
          child: Row(
            children: [
              Icon(LucideIcons.mouse_pointer_click, size: 15, color: Colors.cyanAccent),
              SizedBox(width: 10),
              Text('Выделить текст в терминале', style: TextStyle(color: Colors.cyanAccent, fontSize: 13)),
            ],
          ),
        ),
        if (hasSelection)
          PopupMenuItem(
            value: 'copy',
            height: 38,
            child: Row(
              children: [
                const Icon(LucideIcons.copy, size: 15, color: Colors.white70),
                const SizedBox(width: 10),
                Text(AppLocalizations.of(context)!.copy, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy_all',
          height: 38,
          child: Row(
            children: [
              const Icon(LucideIcons.files, size: 15, color: Colors.white70),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.copyAll, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'paste',
          height: 38,
          child: Row(
            children: [
              const Icon(LucideIcons.clipboard_paste, size: 15, color: Colors.white70),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.paste, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'split',
          height: 38,
          child: Row(
            children: [
              Icon(_isTerminalSplit ? LucideIcons.square : LucideIcons.columns_2, size: 15, color: Colors.cyanAccent),
              const SizedBox(width: 10),
              Text(_isTerminalSplit ? 'Объединить экран' : 'Разделить экран', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'wakelock',
          height: 38,
          child: Row(
            children: [
              Icon(LucideIcons.coffee, size: 15, color: _isWakelockEnabled ? Colors.orangeAccent : Colors.white70),
              const SizedBox(width: 10),
              Text(_isWakelockEnabled ? 'Не гасить экран (Вкл)' : 'Не гасить экран (Wakelock)', style: TextStyle(color: _isWakelockEnabled ? Colors.orangeAccent : Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: 'ctrl_c',
          height: 38,
          child: Row(
            children: [
              Icon(LucideIcons.square, size: 15, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Прервать (Ctrl+C)', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          height: 38,
          child: Row(
            children: [
              const Icon(LucideIcons.trash_2, size: 15, color: Colors.orangeAccent),
              const SizedBox(width: 10),
              Text(AppLocalizations.of(context)!.clearTerminal, style: const TextStyle(color: Colors.orangeAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || !context.mounted) return;

    if (result == 'inline_selection') {
      _toggleInlineSelectionMode(session);
    } else if (result == 'selection_mode') {
      TerminalTextSelectionModal.show(context, session.xtermTerminal, session.title);
    } else if (result == 'copy') {
      final selectedText = session.xtermViewController.selection != null
          ? session.xtermTerminal.buffer.getText(session.xtermViewController.selection!)
          : '';
      if (selectedText.isNotEmpty) {
        final messenger = ScaffoldMessenger.of(context);
        final copiedMsg = AppLocalizations.of(context)!.copiedToClipboard;
        await Clipboard.setData(ClipboardData(text: selectedText));
        if (mounted && context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(copiedMsg),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
      session.xtermViewController.clearSelection();
    } else if (result == 'copy_all') {
      _copyTerminalOutputDirect(session);
    } else if (result == 'paste') {
      _pasteToTerminal(session);
    } else if (result == 'ctrl_c') {
      session.pty.write(Uint8List.fromList([3]));
    } else if (result == 'clear') {
      session.xtermTerminal.eraseDisplay();
      session.xtermTerminal.eraseScrollbackOnly();
    } else if (result == 'split') {
      setState(() {
        _isTerminalSplit = !_isTerminalSplit;
        final sessions = ref.read(terminalTabsProvider);
        if (_isTerminalSplit && sessions.length < 2) {
          ref.read(terminalTabsProvider.notifier).createNewSession();
        }
      });
    } else if (result == 'wakelock') {
      _toggleWakelock();
    }
  }

  void _showMobileTerminalBottomSheet(BuildContext context, TerminalSession session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: session.isExited ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        session.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 12, color: Colors.white10),
                _buildMenuTile(
                  icon: LucideIcons.mouse_pointer_click,
                  iconColor: Colors.cyanAccent,
                  title: _inlineSelectionMode ? 'Выйти из выделения в терминале' : 'Выделение прямо в терминале',
                  subtitle: 'Удобное выделение текста курсорами и копирование без лишних окон',
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleInlineSelectionMode(session);
                  },
                ),
                _buildMenuTile(
                  icon: LucideIcons.copy,
                  iconColor: Colors.greenAccent,
                  title: 'Копировать всё',
                  subtitle: 'Скопировать весь вывод терминала в буфер',
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyTerminalOutputDirect(session);
                  },
                ),
                _buildMenuTile(
                  icon: LucideIcons.clipboard_paste,
                  iconColor: Colors.blueAccent,
                  title: 'Вставить',
                  subtitle: 'Вставить текст из буфера обмена в терминал',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pasteToTerminal(session);
                  },
                ),
                _buildMenuTile(
                  icon: LucideIcons.square,
                  iconColor: Colors.redAccent,
                  title: 'Прервать процесс (Ctrl+C)',
                  subtitle: 'Отправить сигнал SIGINT активной программе',
                  onTap: () {
                    Navigator.pop(ctx);
                    session.pty.write(Uint8List.fromList([3]));
                  },
                ),
                _buildMenuTile(
                  icon: LucideIcons.trash_2,
                  iconColor: Colors.orangeAccent,
                  title: 'Очистить экран (Clear)',
                  subtitle: 'Очистить видимый экран и буфер прокрутки',
                  onTap: () {
                    Navigator.pop(ctx);
                    session.xtermTerminal.eraseDisplay();
                    session.xtermTerminal.eraseScrollbackOnly();
                  },
                ),
                _buildMenuTile(
                  icon: LucideIcons.refresh_cw,
                  iconColor: Colors.purpleAccent,
                  title: 'Перезапустить сессию',
                  subtitle: 'Перезапустить оболочку терминала',
                  onTap: () {
                    Navigator.pop(ctx);
                    final tabsNotifier = ref.read(terminalTabsProvider.notifier);
                    final idx = ref.read(terminalTabsProvider).indexOf(session);
                    if (idx != -1) {
                      tabsNotifier.restartSession(idx);
                    }
                  },
                ),
                _buildMenuTile(
                  icon: _isTerminalSplit ? LucideIcons.square : LucideIcons.columns_2,
                  iconColor: Colors.cyanAccent,
                  title: _isTerminalSplit ? 'Объединить экран' : 'Разделить экран (Split)',
                  subtitle: 'Разделить терминал на два параллельных окна',
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _isTerminalSplit = !_isTerminalSplit;
                      final sessions = ref.read(terminalTabsProvider);
                      if (_isTerminalSplit && sessions.length < 2) {
                        ref.read(terminalTabsProvider.notifier).createNewSession();
                      }
                    });
                  },
                ),
                _buildMenuTile(
                  icon: LucideIcons.coffee,
                  iconColor: _isWakelockEnabled ? Colors.orangeAccent : Colors.white60,
                  title: _isWakelockEnabled ? 'Не гасить экран (Активно)' : 'Держать экран включенным (Wakelock)',
                  subtitle: 'Предотвратить засыпание экрана и завершение сборки/терминала',
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleWakelock();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 9.5,
                      ),
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

  Widget _buildPluginCommandsBar(TerminalSession session) {
    final pluginService = ref.watch(quantumPluginServiceProvider);
    final cmds = pluginService.activeTerminalCommands;
    if (cmds.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF141721),
        border: Border(
          top: BorderSide(color: Color(0xFF262C3D), width: 0.8),
          bottom: BorderSide(color: Color(0xFF1A1F2C), width: 0.8),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        itemCount: cmds.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = cmds[index];
          return InkWell(
            onTap: () {
              session.pty.write(Uint8List.fromList(utf8.encode('${item.command}\n')));
            },
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2433),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF333B50), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.terminal, size: 11, color: Color(0xFF4FC3F7)),
                  const SizedBox(width: 4),
                  Text(
                    item.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'JetBrainsMono',
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

  Widget _buildVirtualKeys(List<TerminalSession> sessions, TerminalTabsNotifier notifier) {
    if (sessions.isEmpty || notifier.currentIndex >= sessions.length) return const SizedBox();
    final currentSession = sessions[notifier.currentIndex];
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = (bottomInset > 20) || _isMobileKeyboardActive;
    return VirtualKeysView(
      isCompact: isKeyboardOpen,
      activeKeys: {
        ..._activeModifiers,
        if (isKeyboardOpen) 'KEYB',
        if (_inlineSelectionMode) 'SEL',
        if (_inlineSelectionMode) 'inline_selection_mode',
      },
      onKeyTap: (value) => _onKeyTap(value, currentSession),
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
        return 'sourceCodePro';
      case 'inconsolata':
        return 'inconsolata';
      case 'cascadiacode':
      case 'cascadia':
        return 'cascadia';
      case 'symbolsnerdfont':
      case 'nerdfont':
      case 'symbolsnerd':
        return 'SymbolsNerdFont';
      case 'monospace':
        return 'monospace';
      default:
        try {
          return GoogleFonts.getFont(fontName).fontFamily ?? 'monospace';
        } catch (_) {
          return 'monospace';
        }
    }
  }

  Future<void> _copySelection(TerminalSession session) async {
    final selection = session.xtermViewController.selection;
    String text = '';
    bool hasSel = false;
    if (selection != null) {
      text = session.xtermTerminal.buffer.getText(selection);
      session.xtermViewController.clearSelection();
      hasSel = true;
    } else {
      text = _extractTerminalText(session.xtermTerminal);
    }
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hasSel ? AppLocalizations.of(context)!.copiedToClipboard : AppLocalizations.of(context)!.copyAll),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _pasteToTerminal(TerminalSession session) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      final sanitized = _sanitizeTerminalInput(text);
      if (session.xtermTerminal.bracketedPasteMode) {
        session.xtermTerminal.paste(sanitized);
      } else {
        session.pty.write(Uint8List.fromList(utf8.encode(sanitized)));
      }
    }
  }

  void _selectAllInTerminal(TerminalSession session) {
    final buffer = session.xtermTerminal.buffer;
    if (buffer.height == 0) return;
    final firstLine = buffer.lines[0];
    final lastLine = buffer.lines[buffer.height - 1];
    final base = xt.CellAnchor(0, owner: firstLine);
    final extent = xt.CellAnchor(lastLine.length, owner: lastLine);
    session.xtermViewController.setSelection(base, extent);
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 20;
    final maxHeight = (widget.suggestions.length * itemHeight).clamp(0.0, isKeyboardOpen ? 95.0 : 180.0);

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

/// Direct Android/iOS TextInputClient that commits every character immediately
/// without buffering IME composing regions at the VT100 cursor position.
/// This prevents Cyrillic/Gboard composing text from floating at random top/bottom/right
/// coordinates when using TUI apps like `agy`, `vim`, `htop`, or `claude`.
class _AndroidTerminalDirectInput extends StatefulWidget {
  final xt.Terminal terminal;
  final FocusNode focusNode;
  final bool enabled;
  final Widget child;

  const _AndroidTerminalDirectInput({
    super.key,
    required this.terminal,
    required this.focusNode,
    required this.enabled,
    required this.child,
  });

  @override
  State<_AndroidTerminalDirectInput> createState() => _AndroidTerminalDirectInputState();
}

class _AndroidTerminalDirectInputState extends State<_AndroidTerminalDirectInput>
    with TextInputClient {
  static const String _sentinel = '  ';
  static const TextEditingValue _initEditingState = TextEditingValue(
    text: _sentinel,
    selection: TextSelection.collapsed(offset: _sentinel.length),
  );

  TextInputConnection? _connection;
  TextEditingValue _currentEditingState = _initEditingState;

  bool get hasInputConnection => _connection != null && _connection!.attached;

  @override
  void dispose() {
    closeKeyboard();
    super.dispose();
  }

  void requestKeyboard() {
    if (!widget.enabled) return;
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }
    if (hasInputConnection) {
      _connection!.show();
      _resetState();
    } else {
      const config = TextInputConfiguration(
        inputType: TextInputType.visiblePassword,
        inputAction: TextInputAction.newline,
        keyboardAppearance: Brightness.dark,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      );
      _connection = TextInput.attach(this, config);
      _connection!.show();
      _resetState();
    }
  }

  void closeKeyboard() {
    if (_connection != null && _connection!.attached) {
      _connection!.close();
    }
    _connection = null;
  }

  void _resetState() {
    _currentEditingState = _initEditingState;
    _connection?.setEditingState(_initEditingState);
  }

  @override
  TextEditingValue? get currentTextEditingValue => _currentEditingState;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!widget.enabled) return;
    final text = value.text;
    if (text == _sentinel) {
      _currentEditingState = _initEditingState;
      if (!value.composing.isCollapsed) {
        _connection?.setEditingState(_initEditingState);
      }
      return;
    }

    if (text.length < _sentinel.length) {
      final delCount = (_sentinel.length - text.length).clamp(1, 2);
      for (int i = 0; i < delCount; i++) {
        widget.terminal.keyInput(xt.TerminalKey.backspace);
      }
      _resetState();
      return;
    }

    String delta;
    if (text.startsWith(_sentinel)) {
      delta = text.substring(_sentinel.length);
    } else if (text.startsWith(' ')) {
      delta = text.substring(1);
    } else {
      delta = text;
    }

    if (delta.isNotEmpty) {
      _sendText(delta);
    }
    _resetState();
  }

  DateTime? _lastEnterSentAt;

  void _sendText(String delta) {
    for (int i = 0; i < delta.length; i++) {
      final ch = delta[i];
      if (ch == '\n' || ch == '\r') {
        _lastEnterSentAt = DateTime.now();
        widget.terminal.keyInput(xt.TerminalKey.enter);
      } else if (ch == '\t') {
        widget.terminal.keyInput(xt.TerminalKey.tab);
      } else if (ch == '\x7f' || ch == '\b') {
        widget.terminal.keyInput(xt.TerminalKey.backspace);
      } else {
        widget.terminal.textInput(ch);
      }
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline ||
        action == TextInputAction.done ||
        action == TextInputAction.go ||
        action == TextInputAction.send ||
        action == TextInputAction.search) {
      if (_lastEnterSentAt != null &&
          DateTime.now().difference(_lastEnterSentAt!).inMilliseconds < 120) {
        return;
      }
      _lastEnterSentAt = DateTime.now();
      widget.terminal.keyInput(xt.TerminalKey.enter);
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
