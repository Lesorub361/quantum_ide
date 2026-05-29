import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart' as xt;

import '../../../../core/services/runtime_service.dart';
import '../../../../core/services/workspace_service.dart';
import '../../../../core/utils/path_mapper.dart';
import '../../../git/presentation/notifiers/git_notifier.dart';

class TerminalSession {
  final String id;
  final String title;
  final Pty pty;
  final String workingDir;
  bool isExited;

  final xt.Terminal xtermTerminal;
  final xt.TerminalController xtermViewController;

  StreamSubscription<Uint8List>? ptyOutSubscription;
  final Utf8Decoder utf8decoder = const Utf8Decoder(allowMalformed: true);

  TerminalSession({
    required this.id,
    required this.title,
    required this.pty,
    required this.workingDir,
    this.isExited = false,
    required this.xtermTerminal,
    required this.xtermViewController,
    this.ptyOutSubscription,
  });
}

class TerminalTabsNotifier extends StateNotifier<List<TerminalSession>> {
  final Ref _ref;
  int _currentIndex = 0;

  TerminalTabsNotifier(this._ref) : super([]) {
    // We don't create a session immediately in constructor because
    // RuntimeService might not be initialized yet.

    _ref.listen<RuntimeService>(runtimeServiceProvider, (previous, next) {
      if (next.isInitialized && (previous == null || !previous.isInitialized)) {
        if (state.isEmpty) {
          createNewSession();
        }
      }
    }, fireImmediately: true);

    _ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
      final prevPath = previous?.currentPath;
      final nextPath = next.currentPath;

      if (prevPath != nextPath) {
        if (nextPath != null) {
          // User entered a project/workspace.
          // Let's check if we already have a session in this directory.
          final guestDir = PathMapper.mapToGuest(
            nextPath,
            _ref.read(runtimeServiceProvider).appDirectory,
          );
          final index = state.indexWhere((s) => s.workingDir == guestDir);
          if (index != -1) {
            _currentIndex = index;
            state = [...state];
          } else {
            // Create a new session in this directory
            createNewSession(workingDir: nextPath);
          }
        } else {
          // User closed the workspace (environment).
          closeAllSessions();
        }
      }
    });
  }

  int get currentIndex => _currentIndex;

  set currentIndex(int index) {
    if (index >= 0 && index < state.length) {
      _currentIndex = index;
      state = [...state];
    }
  }

  Future<void> createNewSession({
    String? title,
    String? workingDir,
    List<String>? initialArgs,
  }) async {
    final runtime = _ref.read(runtimeServiceProvider);
    final workspace = _ref.read(workspaceProvider);

    final id = const Uuid().v4();

    try {
      // Ensure scripts are up to date with latest fixes
      await runtime.updateScripts();

      String dir =
          workingDir ?? workspace.currentPath ?? runtime.workingDirectory;
      dir = PathMapper.mapToGuest(dir, runtime.appDirectory);

      final String dirName = p.basename(dir);
      final sessionTitle = title ?? (dirName == 'root' ? 'Home' : dirName);

      final env = Map<String, String>.from(runtime.env);

      final sessionTmpDir = p.join(
        runtime.appDirectory,
        'runtime',
        'tmp',
        'session_$id',
      );
      Directory(sessionTmpDir).createSync(recursive: true);

      env['PROOT_TMP_DIR'] = sessionTmpDir;
      env['PWD'] = dir;

      if (workspace.currentPath != null) {
        env['WEBIDE_PROJECT_DIR'] = workspace.currentPath!;
      }

      final shell = Platform.isAndroid
          ? '/system/bin/sh'
          : (Platform.isWindows ? 'cmd.exe' : 'bash');

      // Desktop Linux: run bash in interactive login mode so .bashrc/.bash_profile are loaded
      // Android: args are handled by the PRoot wrapper script
      final List<String> args = Platform.isAndroid
          ? [
              runtime.prootCommand,
              runtime.appDirectory,
              dir,
              ...(initialArgs ?? []),
            ]
          : Platform.isWindows
          ? []
          : ['-i']; // -i = interactive (loads .bashrc, enables readline)

      // Add proper env vars for Desktop Linux terminal experience
      if (!Platform.isAndroid && !Platform.isWindows) {
        env['TERM'] = 'xterm-256color';
        env['COLORTERM'] = 'truecolor';
        env['LANG'] = env['LANG'] ?? 'en_US.UTF-8';
        env['HOME'] = env['HOME'] ?? Platform.environment['HOME'] ?? '/root';
        // Ensure PWD is actual host dir for Desktop
        env['PWD'] = dir;
      }

      final pty = Pty.start(
        shell,
        arguments: args,
        environment: env,
        workingDirectory: Platform.isAndroid ? runtime.appDirectory : dir,
      );

      final xtermVc = xt.TerminalController();
      final xtermTerm = xt.Terminal(
        maxLines: 5000,
        platform: Platform.isAndroid
            ? xt.TerminalTargetPlatform.android
            : xt.TerminalTargetPlatform.linux,
        onOutput: (data) {
          pty.write(Uint8List.fromList(utf8.encode(data)));
        },
        onResize: (cols, rows, int pixelWidth, int pixelHeight) {
          pty.resize(rows, cols);
        },
      );


      final session = TerminalSession(
        id: id,
        title: sessionTitle,
        pty: pty,
        workingDir: dir,
        xtermTerminal: xtermTerm,
        xtermViewController: xtermVc,
      );

      Timer? gitRefreshDebounceTimer;
      final sub = pty.output.listen(
        (data) {
          xtermTerm.write(session.utf8decoder.convert(data));

          gitRefreshDebounceTimer?.cancel();
          gitRefreshDebounceTimer = Timer(
            const Duration(milliseconds: 800),
            () {
              try {
                _ref.read(gitProvider.notifier).refreshStatus();
              } catch (_) {}
            },
          );
        },
        onDone: () {
          gitRefreshDebounceTimer?.cancel();
          _markSessionAsExited(id);
          xtermTerm.write('\r\n\x1b[1;31m[Process exited]\x1b[0m\r\n');
          try {
            _ref.read(gitProvider.notifier).refreshStatus();
          } catch (_) {}
        },
        onError: (e) {
          gitRefreshDebounceTimer?.cancel();
          xtermTerm.write('\r\n\x1b[1;31m[Error: $e]\r\n');
        },
      );

      session.ptyOutSubscription = sub;

      state = [...state, session];
      _currentIndex = state.length - 1;

      // Initialize session with Ubuntu-style prompt and greeting
      _initializeUbuntuSession(session);
    } catch (e) {
      debugPrint('Failed to start terminal: $e');
    }
  }

  void _initializeUbuntuSession(TerminalSession session) {
    // Initialization is now handled via .bashrc for stability
  }

  void _markSessionAsExited(String id) {
    state = [
      for (final s in state)
        if (s.id == id)
          TerminalSession(
            id: s.id,
            title: s.title,
            pty: s.pty,
            workingDir: s.workingDir,
            xtermTerminal: s.xtermTerminal,
            xtermViewController: s.xtermViewController,
            ptyOutSubscription: s.ptyOutSubscription,
            isExited: true,
          )
        else
          s,
    ];
  }

  Future<void> restartSession(int index) async {
    if (index < 0 || index >= state.length) return;
    final oldSession = state[index];

    oldSession.ptyOutSubscription?.cancel();
    try {
      oldSession.pty.kill();
    } catch (_) {}

    final runtime = _ref.read(runtimeServiceProvider);
    final workspace = _ref.read(workspaceProvider);

    try {
      final dir = oldSession.workingDir;
      final env = Map<String, String>.from(runtime.env);
      env['PWD'] = dir;

      final sessionTmpDir = p.join(
        runtime.appDirectory,
        'runtime',
        'tmp',
        'session_${oldSession.id}',
      );
      Directory(sessionTmpDir).createSync(recursive: true);
      env['PROOT_TMP_DIR'] = sessionTmpDir;

      if (workspace.currentPath != null) {
        env['WEBIDE_PROJECT_DIR'] = workspace.currentPath!;
      }

      final shell = Platform.isAndroid
          ? '/system/bin/sh'
          : (Platform.isWindows ? 'cmd.exe' : 'bash');
      final List<String> args = Platform.isAndroid
          ? [runtime.prootCommand, runtime.appDirectory, dir]
          : [];

      final newPty = Pty.start(
        shell,
        arguments: args,
        environment: env,
        workingDirectory: Platform.isAndroid ? runtime.appDirectory : dir,
      );

      final term = oldSession.xtermTerminal;
      final xVc = oldSession.xtermViewController;
      term.eraseScrollbackOnly();
      term.eraseDisplay();

      term.onOutput = (data) {
        newPty.write(Uint8List.fromList(utf8.encode(data)));
      };
      term.onResize = (cols, rows, int pixelWidth, int pixelHeight) {
        newPty.resize(rows, cols);
      };

      // Set initial size
      newPty.resize(term.viewHeight, term.viewWidth);

      final sub = newPty.output.listen(
        (data) {
          term.write(oldSession.utf8decoder.convert(data));
        },
        onDone: () => _markSessionAsExited(oldSession.id),
        onError: (_) {},
      );

      state[index] = TerminalSession(
        id: oldSession.id,
        title: oldSession.title,
        pty: newPty,
        workingDir: oldSession.workingDir,
        xtermTerminal: term,
        xtermViewController: xVc,
        ptyOutSubscription: sub,
        isExited: false,
      );

      state = [...state];
      // Give it a moment to initialize
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      oldSession.xtermTerminal.write('Restart failed: $e\r\n');
    }
  }

  void closeSession(int index) {
    if (state.isEmpty) return;

    final session = state[index];
    session.ptyOutSubscription?.cancel();
    try {
      session.pty.kill();
    } catch (_) {}

    // Cleanup temp dir
    final runtime = _ref.read(runtimeServiceProvider);
    final sessionTmpDir = p.join(
      runtime.appDirectory,
      'runtime',
      'tmp',
      'session_${session.id}',
    );
    if (Directory(sessionTmpDir).existsSync()) {
      try {
        Directory(sessionTmpDir).deleteSync(recursive: true);
      } catch (_) {}
    }

    final newState = List<TerminalSession>.from(state);
    newState.removeAt(index);

    if (newState.isEmpty) {
      _currentIndex = 0;
      state = [];
      // Only auto-create if there is an active workspace; otherwise the
      // workspaceProvider listener will create a session when one opens.
      final workspace = _ref.read(workspaceProvider).currentPath;
      if (workspace != null) {
        createNewSession(workingDir: workspace);
      }
    } else {
      if (_currentIndex >= newState.length) {
        _currentIndex = newState.length - 1;
      }
      state = newState;
    }
  }

  void closeAllSessions() {
    for (final session in state) {
      session.ptyOutSubscription?.cancel();
      try {
        session.pty.kill();
      } catch (_) {}

      final runtime = _ref.read(runtimeServiceProvider);
      final sessionTmpDir = p.join(
        runtime.appDirectory,
        'runtime',
        'tmp',
        'session_${session.id}',
      );
      if (Directory(sessionTmpDir).existsSync()) {
        try {
          Directory(sessionTmpDir).deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    _currentIndex = 0;
    state = [];
    // Do NOT auto-create a session here. When the next workspace opens,
    // the workspaceProvider listener will create one automatically.
  }

  Future<void> sendCommand(
    String command, {
    bool interrupt = false,
    bool createNewTab = false,
  }) async {
    if (state.isEmpty || createNewTab) {
      await createNewSession(
        title: command.split(' ').take(3).join(' '),
        initialArgs: [command],
      );
      return; // Command is handled via initialArgs
    }

    // Защита от выхода за границы
    if (state.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= state.length) {
      _currentIndex = state.length - 1;
    }

    var session = state[_currentIndex];
    if (session.isExited && !createNewTab) {
      await restartSession(_currentIndex);
      if (_currentIndex < 0 || _currentIndex >= state.length) return;
      session = state[_currentIndex];
    }

    final runtime = _ref.read(runtimeServiceProvider);
    String translatedCommand = PathMapper.mapToGuest(
      command,
      runtime.appDirectory,
    );

    if (interrupt) {
      session.pty.write(Uint8List.fromList([3]));
      await Future.delayed(const Duration(milliseconds: 200));
    }

    session.pty.write(Uint8List.fromList(utf8.encode('$translatedCommand\n')));
  }

  void selectGeneralSession() {
    final runtime = _ref.read(runtimeServiceProvider);
    final guestHome = PathMapper.mapToGuest(
      runtime.workingDirectory,
      runtime.appDirectory,
    );

    final index = state.indexWhere((s) => s.workingDir == guestHome);
    if (index != -1) {
      _currentIndex = index;
      state = [...state]; // trigger update
    } else {
      createNewSession(workingDir: runtime.workingDirectory);
    }
  }

  @override
  void dispose() {
    for (final session in state) {
      session.ptyOutSubscription?.cancel();
      try {
        session.pty.kill();
      } catch (_) {}

      // Cleanup temp dir
      final runtime = _ref.read(runtimeServiceProvider);
      final sessionTmpDir = p.join(
        runtime.appDirectory,
        'runtime',
        'tmp',
        'session_${session.id}',
      );
      if (Directory(sessionTmpDir).existsSync()) {
        try {
          Directory(sessionTmpDir).deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    super.dispose();
  }
}

final terminalTabsProvider =
    StateNotifierProvider<TerminalTabsNotifier, List<TerminalSession>>((ref) {
      return TerminalTabsNotifier(ref);
    });
