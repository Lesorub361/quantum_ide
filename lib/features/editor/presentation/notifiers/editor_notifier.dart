import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart' as xt;
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/features/ai_assistant/presentation/notifiers/ai_notifier.dart';
import 'package:quantum_ide/models/chat_message.dart';

import '../../../../core/services/diff_service.dart';
import '../../../../core/services/lsp_service.dart';
import '../../../../core/services/analysis_service.dart';
import '../../../../core/services/project_service.dart';
import '../../../../core/services/workspace_service.dart';
import '../../../git/presentation/notifiers/git_notifier.dart';
import 'package:quantum_ide/core/services/symbol_indexer_service.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

class EditorFile {
  final String path;
  final String name;
  final CodeLineEditingController controller;
  final String originalContent;
  final List<DiffMarker> diffMarkers;
  final List<CodeDiagnostic> diagnostics;
  final bool isModified;
  final bool isImage;

  EditorFile({
    required this.path,
    required this.name,
    required this.controller,
    required this.originalContent,
    this.diffMarkers = const [],
    this.diagnostics = const [],
    this.isModified = false,
    this.isImage = false,
  });

  EditorFile copyWith({
    bool? isModified,
    CodeLineEditingController? controller,
    List<DiffMarker>? diffMarkers,
    List<CodeDiagnostic>? diagnostics,
    String? originalContent,
    bool? isImage,
  }) {
    return EditorFile(
      path: path,
      name: name,
      controller: controller ?? this.controller,
      isModified: isModified ?? this.isModified,
      originalContent: originalContent ?? this.originalContent,
      diffMarkers: diffMarkers ?? this.diffMarkers,
      diagnostics: diagnostics ?? this.diagnostics,
      isImage: isImage ?? this.isImage,
    );
  }
}

class EditorState {
  final List<EditorFile> openFiles;
  final int activeTabIndex;
  final bool isAIPanelOpen;
  final xt.Terminal? aiXtermTerminal;
  final xt.TerminalController? aiXtermViewController;
  final bool isAgentRunning;
  final Map<String, List<CodeDiagnostic>> allDiagnostics;

  EditorState({
    this.openFiles = const [],
    this.activeTabIndex = 0,
    this.isAIPanelOpen = false,
    this.aiXtermTerminal,
    this.aiXtermViewController,
    this.isAgentRunning = false,
    this.allDiagnostics = const {},
  });

  String? get activeFilePath => openFiles.isEmpty || activeTabIndex >= openFiles.length 
    ? null : openFiles[activeTabIndex].path;

  EditorState copyWith({
    List<EditorFile>? openFiles,
    int? activeTabIndex,
    bool? isAIPanelOpen,
    xt.Terminal? aiXtermTerminal,
    xt.TerminalController? aiXtermViewController,
    bool? isAgentRunning,
    Map<String, List<CodeDiagnostic>>? allDiagnostics,
  }) {
    return EditorState(
      openFiles: openFiles ?? this.openFiles,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      isAIPanelOpen: isAIPanelOpen ?? this.isAIPanelOpen,
      aiXtermTerminal: aiXtermTerminal ?? this.aiXtermTerminal,
      aiXtermViewController: aiXtermViewController ?? this.aiXtermViewController,
      isAgentRunning: isAgentRunning ?? this.isAgentRunning,
      allDiagnostics: allDiagnostics ?? this.allDiagnostics,
    );
  }
}

final editorProvider = StateNotifierProvider<EditorNotifier, EditorState>((ref) {
  return EditorNotifier(ref);
});

class EditorNotifier extends StateNotifier<EditorState> {
  final Ref ref;
  late final LspService _lspService;
  Timer? _diffTimer;
  final Map<String, Timer> _autoSaveTimers = {};
  final DiffService _diffService = DiffService();

  Pty? _agentPty;
  StreamSubscription<Uint8List>? _agentPtySubscription;
  StreamSubscription<FileSystemEvent>? _workspaceWatcherSubscription;

  EditorNotifier(this.ref) : super(EditorState()) {
    _init();
    
    // Listen for workspace changes
    ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      final prevPath = previous?.currentPath;
      final nextPath = next.currentPath;
      if (prevPath != nextPath) {
        _workspaceWatcherSubscription?.cancel();
        _workspaceWatcherSubscription = null;
        if (nextPath != null) {
          _startWorkspaceWatcher(nextPath);
        }
      }

      if (next.currentPath == null) {
        clearWorkspace();
      } else if (previous?.currentPath != next.currentPath) {
        loadWorkspaceFiles(next.currentPath!);
      }
    });
  }

  void _init() {
    try {
      final terminal = xt.Terminal(maxLines: 5000);
      final controller = xt.TerminalController();
      state = state.copyWith(
        aiXtermTerminal: terminal,
        aiXtermViewController: controller,
      );
    } catch (e) {
      debugPrint('Failed to initialize AI Terminal Controller: $e');
    }
    
    // Initialize LSP
    _lspService = ref.read(lspServiceProvider);
    
    // Listen to diagnostics
    _lspService.diagnosticsStream.listen((fileDiagnostics) {
      updateDiagnostics(fileDiagnostics.path, fileDiagnostics.diagnostics);
    });

    // Load saved files if a workspace is already active
    final activeWorkspace = ref.read(workspaceProvider).currentPath;
    if (activeWorkspace != null) {
      _startWorkspaceWatcher(activeWorkspace);
      loadWorkspaceFiles(activeWorkspace);
    }
  }


  Future<void> openFile(String path, {int? line, int? column}) async {
    final existingIndex = state.openFiles.indexWhere((f) => f.path == path);
    if (existingIndex != -1) {
      state = state.copyWith(activeTabIndex: existingIndex);
      if (line != null && column != null) {
        final controller = state.openFiles[existingIndex].controller;
        controller.selection = CodeLineSelection.fromPosition(position: CodeLinePosition(index: line, offset: column));
      }
      
      // Load proposed AI change into controller if not already loaded
      final aiState = ref.read(aiProvider);
      final pendingActions = aiState.proposedActions.where((a) => a.path == path && (a.type == 'edit' || a.type == 'create')).toList();
      if (pendingActions.isNotEmpty) {
        final action = pendingActions.first;
        final file = state.openFiles[existingIndex];
        if (file.controller.text != action.content) {
          file.controller.text = action.content;
          _updateDiff(path);
        }
      }

      _persistWorkspaceFiles();
      return;
    }

    if (path.toLowerCase().endsWith('.apk')) {
      try {
        await OpenFilex.open(path);
        return;
      } catch (e) {
        debugPrint('Error opening APK: $e');
      }
    }

    final lowerPath = path.toLowerCase();
    final isImg = lowerPath.endsWith('.png') ||
        lowerPath.endsWith('.jpg') ||
        lowerPath.endsWith('.jpeg') ||
        lowerPath.endsWith('.gif') ||
        lowerPath.endsWith('.webp') ||
        lowerPath.endsWith('.bmp') ||
        lowerPath.endsWith('.ico');

    if (isImg) {
      final controller = CodeLineEditingController(
        codeLines: CodeLines.fromText(''),
      );
      final newFile = EditorFile(
        path: path,
        name: path.split(Platform.pathSeparator).last,
        controller: controller,
        originalContent: '',
        isImage: true,
      );
      final newList = [...state.openFiles, newFile];
      state = state.copyWith(
        openFiles: newList,
        activeTabIndex: newList.length - 1,
      );
      _persistWorkspaceFiles();
      return;
    }

    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('File does not exist: $path');
        return;
      }
      final bytes = await file.readAsBytes();
      
      bool isBinary = false;
      final checkLimit = bytes.length < 8192 ? bytes.length : 8192;
      for (int i = 0; i < checkLimit; i++) {
        if (bytes[i] == 0) {
          isBinary = true;
          break;
        }
      }

      if (isBinary) {
        debugPrint('File $path is binary, attempting to open with system handler.');
        await OpenFilex.open(path);
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      
      // Load proposed AI content or original content
      final aiState = ref.read(aiProvider);
      final pendingActions = aiState.proposedActions.where((a) => a.path == path && (a.type == 'edit' || a.type == 'create')).toList();
      final hasProposed = pendingActions.isNotEmpty;
      final initialContent = hasProposed ? pendingActions.first.content : content;

      final controller = CodeLineEditingController(
        codeLines: CodeLines.fromText(initialContent),
      );

      if (line != null && column != null) {
        controller.selection = CodeLineSelection.fromPosition(position: CodeLinePosition(index: line, offset: column));
      }
 
      final newFile = EditorFile(
        path: path,
        name: path.split(Platform.pathSeparator).last,
        controller: controller,
        originalContent: content,
      );

      controller.addListener(() {
        _handleContentChange(path);
      });

      final newList = [...state.openFiles, newFile];
      state = state.copyWith(
        openFiles: newList,
        activeTabIndex: newList.length - 1,
      );

      _persistWorkspaceFiles();

      // Handle LSP open
      _lspService.onFileOpened(path, content);
      
      // Calculate diff immediately if there are proposed AI changes
      if (hasProposed) {
        _updateDiff(path);
      }
      
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  void _handleContentChange(String path, {bool triggerAutoSave = true}) {
    final index = state.openFiles.indexWhere((f) => f.path == path);
    if (index == -1) return;

    final file = state.openFiles[index];
    final isModified = file.controller.text != file.originalContent;

    // Synchronous update only when isModified flag actually changes —
    // avoids rebuilding the whole UI on every single keystroke.
    if (file.isModified != isModified) {
      if (!mounted) return;
      final newOpenFiles = List<EditorFile>.from(state.openFiles);
      newOpenFiles[index] = file.copyWith(isModified: isModified);
      state = state.copyWith(openFiles: newOpenFiles);
    }

    _diffTimer?.cancel();
    _diffTimer = Timer(const Duration(milliseconds: 1500), () {
      _updateDiff(path);
      // Re-read text at timer fire time to avoid stale closure
      final latestIdx = state.openFiles.indexWhere((f) => f.path == path);
      if (latestIdx != -1) {
        _lspService.onFileChanged(path, state.openFiles[latestIdx].controller.text);
      }
      ref.read(analysisServiceProvider).triggerAnalysis();
    });

    if (triggerAutoSave) {
      _autoSaveTimers[path]?.cancel();
      _autoSaveTimers[path] = Timer(const Duration(seconds: 3), () {
        saveFileByPath(path);
        _autoSaveTimers.remove(path);
      });
    }
  }

  void _updateDiff(String path) async {
    final index = state.openFiles.indexWhere((f) => f.path == path);
    if (index == -1) return;

    final file = state.openFiles[index];
    final markers = await _diffService.calculateDiff(file.originalContent, file.controller.text);

    if (!mounted) return;
    final newOpenFiles = [...state.openFiles];
    final latestIndex = newOpenFiles.indexWhere((f) => f.path == path);
    if (latestIndex == -1) return;

    newOpenFiles[latestIndex] = file.copyWith(diffMarkers: markers);
    state = state.copyWith(openFiles: newOpenFiles);
  }

  void updateFileContentFromAI(String filePath, String newContent) {
    final index = state.openFiles.indexWhere((f) => f.path == filePath);
    if (index == -1) return;

    final file = state.openFiles[index];
    file.controller.text = newContent;

    _updateDiff(filePath);
    _handleContentChange(filePath, triggerAutoSave: false);

    _autoSaveTimers[filePath]?.cancel();
    _autoSaveTimers.remove(filePath);
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.openFiles.length) return;
    final path = state.openFiles[index].path;
    _autoSaveTimers[path]?.cancel();
    _autoSaveTimers.remove(path);

    final newList = List<EditorFile>.from(state.openFiles);
    newList.removeAt(index);
    
    int newActiveIndex = state.activeTabIndex;
    if (newActiveIndex >= newList.length) {
      newActiveIndex = newList.isEmpty ? 0 : newList.length - 1;
    }

    state = state.copyWith(
      openFiles: newList,
      activeTabIndex: newActiveIndex,
    );
    _persistWorkspaceFiles();
  }

  Future<void> saveFile(int index) async {
    if (index < 0 || index >= state.openFiles.length) return;
    final path = state.openFiles[index].path;
    await saveFileByPath(path);
  }

  Future<void> saveFileByPath(String path) async {
    final index = state.openFiles.indexWhere((f) => f.path == path);
    if (index == -1) return;

    final file = state.openFiles[index];
    final content = file.controller.text;

    try {
      await File(path).writeAsString(content);
      
      // Mirror to external storage
      await ref.read(projectServiceProvider.notifier).mirrorEntity(path);

      // Re-verify index after await
      final currentIndex = state.openFiles.indexWhere((f) => f.path == path);
      if (currentIndex == -1) return;

      final currentFile = state.openFiles[currentIndex];
      final newOpenFiles = List<EditorFile>.from(state.openFiles);
      newOpenFiles[currentIndex] = currentFile.copyWith(
        originalContent: content,
        diffMarkers: const [],
        isModified: false,
      );
      state = state.copyWith(openFiles: newOpenFiles);

      // Trigger immediate analysis on save
      ref.read(analysisServiceProvider).triggerAnalysis(immediate: true);
      ref.read(gitProvider.notifier).refreshStatus();
      ref.read(symbolIndexerProvider.notifier).indexFile(path);
    } catch (e) {
      debugPrint('Error saving file $path: $e');
    }
  }

  void setActiveTab(int index) {
    if (index < 0 || index >= state.openFiles.length && state.openFiles.isNotEmpty) return;
    state = state.copyWith(activeTabIndex: index);
    ref.read(gitProvider.notifier).refreshStatus();
    _persistWorkspaceFiles();
  }

  void updateDiagnostics(String path, List<CodeDiagnostic> diagnostics) {
    // Only accept diagnostics for files that are within the current workspace path
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null || !path.startsWith(workspacePath)) {
      return;
    }

    // Early exit: skip rebuild if both old and new are empty
    final existing = state.allDiagnostics[path];
    if (existing != null && existing.isEmpty && diagnostics.isEmpty) return;

    final newAllDiagnostics = Map<String, List<CodeDiagnostic>>.from(state.allDiagnostics);
    newAllDiagnostics[path] = diagnostics;

    // Check if file is currently open before building a new openFiles list
    final openFileIndex = state.openFiles.indexWhere((f) => f.path == path);

    Future.microtask(() {
      if (!mounted) return;
      if (openFileIndex == -1) {
        // File is not open — only update diagnostics map, skip openFiles rebuild
        state = state.copyWith(allDiagnostics: newAllDiagnostics);
        return;
      }
      final newOpenFiles = List<EditorFile>.from(state.openFiles);
      final latestIndex = newOpenFiles.indexWhere((f) => f.path == path);
      if (latestIndex == -1) {
        state = state.copyWith(allDiagnostics: newAllDiagnostics);
        return;
      }
      newOpenFiles[latestIndex] = newOpenFiles[latestIndex].copyWith(diagnostics: diagnostics);
      state = state.copyWith(
        allDiagnostics: newAllDiagnostics,
        openFiles: newOpenFiles,
      );
    });
  }

  void clearDiagnostics() {
    final newOpenFiles = state.openFiles
        .map((file) => file.copyWith(diagnostics: const []))
        .toList();
    state = state.copyWith(allDiagnostics: {}, openFiles: newOpenFiles);
  }

  Future<void> _persistWorkspaceFiles() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = state.openFiles.map((f) => f.path).toList();
      final keyPaths = 'open_files_$workspacePath';
      final keyActive = 'active_tab_$workspacePath';
      
      int activeIndex = state.activeTabIndex;
      if (activeIndex < 0) activeIndex = 0;
      
      await prefs.setStringList(keyPaths, paths);
      await prefs.setInt(keyActive, activeIndex);
    } catch (e) {
      debugPrint('Error persisting workspace files: $e');
    }
  }

  Future<void> loadWorkspaceFiles(String workspacePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyPaths = 'open_files_$workspacePath';
      final keyActive = 'active_tab_$workspacePath';
      final paths = prefs.getStringList(keyPaths) ?? [];
      final activeIndex = prefs.getInt(keyActive) ?? 0;
      
      final validPaths = paths.where((p) => File(p).existsSync()).toList();
      if (validPaths.isEmpty) return;
      
      clearWorkspace();
      
      // Load active file first for better perceived performance
      int targetIndex = activeIndex < validPaths.length ? activeIndex : 0;
      if (targetIndex < 0) targetIndex = 0;
      
      final activePath = validPaths[targetIndex];
      final activeFile = await _loadSingleFile(activePath);
      
      if (activeFile != null) {
        state = state.copyWith(
          openFiles: [activeFile],
          activeTabIndex: 0,
        );
      }

      // Load remaining files in background
      Future.microtask(() async {
        final List<EditorFile> otherFiles = [];
        for (int i = 0; i < validPaths.length; i++) {
          if (i == targetIndex) continue;
          final file = await _loadSingleFile(validPaths[i]);
          if (file != null) otherFiles.add(file);
          // Yield to UI thread between files
          await Future.delayed(Duration.zero);
        }
        
        if (mounted) {
          final List<EditorFile?> orderedFiles = List.filled(validPaths.length, null);
          orderedFiles[targetIndex] = activeFile;
          
          int otherIdx = 0;
          for(int i=0; i<validPaths.length; i++) {
            if (i == targetIndex) continue;
            if (otherIdx < otherFiles.length) {
               orderedFiles[i] = otherFiles[otherIdx++];
            }
          }
          
          final nonNullFiles = orderedFiles.whereType<EditorFile>().toList();
          state = state.copyWith(
            openFiles: nonNullFiles,
            activeTabIndex: activeFile != null ? nonNullFiles.indexOf(activeFile) : 0,
          );
        }
      });
    } catch (e) {
      debugPrint('Error loading workspace files: $e');
    }
  }

  Future<EditorFile?> _loadSingleFile(String path) async {
    try {
      final file = File(path);
      final lowerPath = path.toLowerCase();
      final isImg = lowerPath.endsWith('.png') ||
          lowerPath.endsWith('.jpg') ||
          lowerPath.endsWith('.jpeg') ||
          lowerPath.endsWith('.gif') ||
          lowerPath.endsWith('.webp') ||
          lowerPath.endsWith('.bmp') ||
          lowerPath.endsWith('.ico');

      if (isImg) {
        return EditorFile(
          path: path,
          name: path.split(Platform.pathSeparator).last,
          controller: CodeLineEditingController(codeLines: CodeLines.fromText('')),
          originalContent: '',
          isImage: true,
        );
      }

      final bytes = await file.readAsBytes();
      bool isBinary = false;
      final checkLimit = bytes.length < 8192 ? bytes.length : 8192;
      for (int i = 0; i < checkLimit; i++) {
        if (bytes[i] == 0) {
          isBinary = true;
          break;
        }
      }
      if (isBinary) return null;
      
      final content = utf8.decode(bytes, allowMalformed: true);
      
      final aiState = ref.read(aiProvider);
      final pendingActions = aiState.proposedActions.where((a) => a.path == path && (a.type == 'edit' || a.type == 'create')).toList();
      final hasProposed = pendingActions.isNotEmpty;
      final initialContent = hasProposed ? pendingActions.first.content : content;

      final controller = CodeLineEditingController(
        codeLines: CodeLines.fromText(initialContent),
      );
      controller.addListener(() {
        _handleContentChange(path);
      });
      
      final editorFile = EditorFile(
        path: path,
        name: path.split(Platform.pathSeparator).last,
        controller: controller,
        originalContent: content,
      );
      
      // Handle LSP open and diagnostics in background
      _lspService.onFileOpened(path, content).then((_) {
        _lspService.getDiagnostics(path).then((diagnostics) {
          updateDiagnostics(path, diagnostics);
        });
      });

      if (hasProposed) {
        Future.microtask(() => _updateDiff(path));
      }
      
      return editorFile;
    } catch (e) {
      debugPrint('Error loading file $path: $e');
      return null;
    }
  }

  void clearWorkspace() {
    _workspaceWatcherSubscription?.cancel();
    _workspaceWatcherSubscription = null;
    stopAgent();
    for (final timer in _autoSaveTimers.values) {
      timer.cancel();
    }
    _autoSaveTimers.clear();
    state = EditorState();
  }

  void _startWorkspaceWatcher(String workspacePath) {
    _workspaceWatcherSubscription?.cancel();
    try {
      _workspaceWatcherSubscription = Directory(workspacePath).watch(recursive: true).listen(
        (event) {
          _handleExternalFileChange(event.path);
        },
        onError: (e) {
          debugPrint('Workspace watcher error: $e');
        },
      );
    } catch (e) {
      debugPrint('Failed to start workspace watcher: $e');
    }
  }

  void _handleExternalFileChange(String path) async {
    final normalisedPath = p.normalize(path);
    final index = state.openFiles.indexWhere((f) => p.normalize(f.path) == normalisedPath);
    if (index == -1) return;

    try {
      final file = File(normalisedPath);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      bool isBinary = false;
      final checkLimit = bytes.length < 8192 ? bytes.length : 8192;
      for (int i = 0; i < checkLimit; i++) {
        if (bytes[i] == 0) {
          isBinary = true;
          break;
        }
      }
      if (isBinary) return;

      final content = utf8.decode(bytes, allowMalformed: true);
      final openFile = state.openFiles[index];
      
      if (openFile.controller.text != content) {
        openFile.controller.text = content;
        
        final updatedFile = openFile.copyWith(
          originalContent: content,
          isModified: false,
        );
        final newOpenFiles = List<EditorFile>.from(state.openFiles);
        newOpenFiles[index] = updatedFile;
        state = state.copyWith(openFiles: newOpenFiles);
        _updateDiff(normalisedPath);
      }
    } catch (e) {
      debugPrint('Error reloading changed file: $e');
    }
  }

  void runAgentCommand(String command) async {
    debugPrint('Running agent command: $command');
    
    // Stop any existing agent session
    stopAgent();
    
    final runtime = ref.read(runtimeServiceProvider);
    final workspace = ref.read(workspaceProvider);
    
    String dir = workspace.currentPath ?? runtime.workingDirectory;
    dir = PathMapper.mapToGuest(dir, runtime.appDirectory);
    
    final env = Map<String, String>.from(runtime.env);
    
    final shell = Platform.isAndroid
        ? '/system/bin/sh'
        : (Platform.isWindows ? 'cmd.exe' : 'bash');
        
    final List<String> args = Platform.isAndroid
        ? [
            runtime.prootCommand,
            runtime.appDirectory,
            dir,
          ]
        : Platform.isWindows
        ? []
        : ['-i'];

    if (!Platform.isAndroid && !Platform.isWindows) {
      env['TERM'] = 'xterm-256color';
      env['COLORTERM'] = 'truecolor';
      env['LANG'] = env['LANG'] ?? 'en_US.UTF-8';
      env['HOME'] = env['HOME'] ?? Platform.environment['HOME'] ?? '/root';
      env['PWD'] = dir;
    }

    try {
      _agentPty = Pty.start(
        shell,
        arguments: args,
        environment: env,
        workingDirectory: Platform.isAndroid ? runtime.appDirectory : dir,
      );

      final terminal = state.aiXtermTerminal;
      if (terminal != null) {
        terminal.eraseScrollbackOnly();
        terminal.eraseDisplay();
        
        terminal.onOutput = (data) {
          _agentPty?.write(Uint8List.fromList(utf8.encode(data)));
        };
        terminal.onResize = (cols, rows, int pixelWidth, int pixelHeight) {
          _agentPty?.resize(rows, cols);
        };
        
        final decoder = const Utf8Decoder(allowMalformed: true);
        _agentPtySubscription = _agentPty!.output.listen(
          (data) {
            terminal.write(decoder.convert(data));
          },
          onDone: () {
            stopAgent();
            terminal.write('\r\n\x1b[1;31m[Agent process exited]\x1b[0m\r\n');
          },
          onError: (e) {
            terminal.write('\r\n\x1b[1;31m[Error: $e]\r\n');
          },
        );
        
        state = state.copyWith(isAgentRunning: true);
        
        // Give it a brief moment to warm up, then execute command
        await Future.delayed(const Duration(milliseconds: 200));
        _agentPty?.write(Uint8List.fromList(utf8.encode('$command\n')));
      }
    } catch (e) {
      debugPrint('Failed to start agent command process: $e');
    }
  }

  void stopAgent() {
    debugPrint('Stopping agent');
    _agentPtySubscription?.cancel();
    _agentPtySubscription = null;
    try {
      _agentPty?.kill();
    } catch (_) {}
    _agentPty = null;
    state = state.copyWith(isAgentRunning: false);
  }

  @override
  void dispose() {
    _workspaceWatcherSubscription?.cancel();
    _diffTimer?.cancel();
    for (final timer in _autoSaveTimers.values) {
      timer.cancel();
    }
    _agentPtySubscription?.cancel();
    try {
      _agentPty?.kill();
    } catch (_) {}
    super.dispose();
  }

  Future<void> goToDefinition() async {
    final path = state.activeFilePath;
    if (path == null) return;
    
    final file = state.openFiles[state.activeTabIndex];
    final cursor = file.controller.selection.extent;
    
    final locations = await _lspService.getDefinition(path, cursor.index, cursor.offset);
    if (locations.isNotEmpty) {
      final loc = locations.first;
      final targetUri = Uri.parse(loc.uri);
      if (targetUri.scheme == 'file') {
        final targetPath = targetUri.toFilePath();
        await openFile(targetPath, line: loc.range.start.line, column: loc.range.start.character);
      }
    }
  }

  Future<Hover?> getHover() async {
    final path = state.activeFilePath;
    if (path == null) return null;
    
    final file = state.openFiles[state.activeTabIndex];
    final cursor = file.controller.selection.extent;
    
    return await _lspService.getHover(path, cursor.index, cursor.offset);
  }

  Future<List<Location>> getReferences() async {
    final path = state.activeFilePath;
    if (path == null) return [];
    
    final file = state.openFiles[state.activeTabIndex];
    final cursor = file.controller.selection.extent;
    
    return await _lspService.getReferences(path, cursor.index, cursor.offset);
  }

  Future<void> rename(String newName) async {
    final path = state.activeFilePath;
    if (path == null) return;
    
    final file = state.openFiles[state.activeTabIndex];
    final cursor = file.controller.selection.extent;
    
    await _lspService.rename(path, cursor.index, cursor.offset, newName);
  }

  Future<void> formatActiveFile() async {
    final path = state.activeFilePath;
    if (path == null) return;
    await _lspService.format(path);
  }

  void applyLSPEdits(String filePath, List<dynamic> edits) {
    final index = state.openFiles.indexWhere((f) => f.path == filePath);
    if (index == -1) return;

    final file = state.openFiles[index];
    final controller = file.controller;
    
    // Sort edits by range (reverse order to not mess up positions)
    final sortedEdits = List.from(edits);
    sortedEdits.sort((a, b) {
      final aStart = a['range']['start'] as Map;
      final bStart = b['range']['start'] as Map;
      final aLine = aStart['line'] as int;
      final bLine = bStart['line'] as int;
      if (aLine != bLine) return bLine.compareTo(aLine);
      return (bStart['character'] as int).compareTo(aStart['character'] as int);
    });

    // Get the current text
    String currentText = controller.text;

    for (final edit in sortedEdits) {
      try {
        final range = edit['range'] as Map<String, dynamic>;
        final start = range['start'] as Map<String, dynamic>;
        final end = range['end'] as Map<String, dynamic>;
        final newText = edit['newText'] as String;

        final startLine = start['line'] as int;
        final startChar = start['character'] as int;
        final endLine = end['line'] as int;
        final endChar = end['character'] as int;

        // Calculate absolute positions in the text
        final lines = currentText.split('\n');
        if (startLine >= lines.length || endLine >= lines.length) continue;

        int startOffset = 0;
        for (int i = 0; i < startLine; i++) {
          startOffset += lines[i].length + 1; // +1 for newline
        }
        startOffset += startChar;

        int endOffset = 0;
        for (int i = 0; i < endLine; i++) {
          endOffset += lines[i].length + 1;
        }
        endOffset += endChar;

        // Apply the replacement
        if (startOffset >= 0 && endOffset >= startOffset && endOffset <= currentText.length) {
          currentText = currentText.replaceRange(startOffset, endOffset, newText);
        }
      } catch (e) {
        debugPrint('Error applying LSP edit: $e');
      }
    }

    // Update the controller with new text
    controller.text = currentText;

    // Update the file's original content if we're applying LSP edits
    _handleContentChange(filePath);
  }

  Future<void> acceptProposedChanges(String path, AIAction action) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(action.content);

      final index = state.openFiles.indexWhere((f) => f.path == path);
      if (index != -1) {
        final currentFile = state.openFiles[index];
        final newOpenFiles = List<EditorFile>.from(state.openFiles);
        newOpenFiles[index] = currentFile.copyWith(
          originalContent: action.content,
          diffMarkers: const [],
          isModified: false,
        );
        state = state.copyWith(openFiles: newOpenFiles);
      }

      ref.read(aiProvider.notifier).removeAction(action);
      ref.read(analysisServiceProvider).triggerAnalysis(immediate: true);
      ref.read(gitProvider.notifier).refreshStatus();
    } catch (e) {
      debugPrint('Error accepting proposed changes: $e');
    }
  }

  Future<void> revertProposedChanges(String path, AIAction action) async {
    try {
      final file = File(path);
      String content = '';
      if (await file.exists()) {
        content = await file.readAsString();
      }

      final index = state.openFiles.indexWhere((f) => f.path == path);
      if (index != -1) {
        final currentFile = state.openFiles[index];
        currentFile.controller.text = content;
        
        final newOpenFiles = List<EditorFile>.from(state.openFiles);
        newOpenFiles[index] = currentFile.copyWith(
          originalContent: content,
          diffMarkers: const [],
          isModified: false,
        );
        state = state.copyWith(openFiles: newOpenFiles);
      }

      ref.read(aiProvider.notifier).removeAction(action);
      ref.read(analysisServiceProvider).triggerAnalysis(immediate: true);
    } catch (e) {
      debugPrint('Error reverting proposed changes: $e');
    }
  }

  void applyHunkAction(String filePath, int hunkIndex, bool keep) {
    final index = state.openFiles.indexWhere((f) => f.path == filePath);
    if (index == -1) return;
    
    final file = state.openFiles[index];
    final original = file.originalContent;
    final current = file.controller.text;
    
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(original, current);
    dmp.diffCleanupSemantic(diffs);
    
    // Filter non-equal diff blocks which correspond to hunks
    final editDiffIndices = <int>[];
    for (int i = 0; i < diffs.length; i++) {
      if (diffs[i].operation != DIFF_EQUAL) {
        editDiffIndices.add(i);
      }
    }
    
    if (hunkIndex < 0 || hunkIndex >= editDiffIndices.length) return;
    
    final targetDiffIndex = editDiffIndices[hunkIndex];
    final targetDiff = diffs[targetDiffIndex];
    
    if (keep) {
      // Keep the change:
      if (targetDiff.operation == DIFF_INSERT) {
        // Change INSERT to EQUAL so it becomes part of originalContent
        diffs[targetDiffIndex] = Diff(DIFF_EQUAL, targetDiff.text);
      } else if (targetDiff.operation == DIFF_DELETE) {
        // Remove the DELETE block completely so it is removed from originalContent
        diffs.removeAt(targetDiffIndex);
      }
    } else {
      // Reject the change (Undo):
      if (targetDiff.operation == DIFF_INSERT) {
        // Remove the INSERT block completely so it is removed from currentText
        diffs.removeAt(targetDiffIndex);
      } else if (targetDiff.operation == DIFF_DELETE) {
        // Change DELETE to EQUAL so it is restored in currentText
        diffs[targetDiffIndex] = Diff(DIFF_EQUAL, targetDiff.text);
      }
    }
    
    // Rebuild original and current text from the modified diffs list
    final newOriginal = StringBuffer();
    final newCurrent = StringBuffer();
    
    for (final d in diffs) {
      if (d.operation == DIFF_EQUAL) {
        newOriginal.write(d.text);
        newCurrent.write(d.text);
      } else if (d.operation == DIFF_INSERT) {
        newCurrent.write(d.text);
      } else if (d.operation == DIFF_DELETE) {
        newOriginal.write(d.text);
      }
    }
    
    final updatedOriginal = newOriginal.toString();
    final updatedCurrent = newCurrent.toString();
    
    // Update the controller and state
    file.controller.text = updatedCurrent;
    final newOpenFiles = List<EditorFile>.from(state.openFiles);
    newOpenFiles[index] = file.copyWith(
      originalContent: updatedOriginal,
    );
    state = state.copyWith(openFiles: newOpenFiles);
    
    _updateDiff(filePath);
    _handleContentChange(filePath);
  }
}
