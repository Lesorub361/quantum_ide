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
import 'terminal_tabs_notifier.dart';

enum DedicatedTerminalType { run, build, appLogs }

class DedicatedTerminalState {
  final Map<DedicatedTerminalType, TerminalSession?> sessions;

  DedicatedTerminalState({this.sessions = const {}});

  DedicatedTerminalState copyWith({
    Map<DedicatedTerminalType, TerminalSession?>? sessions,
  }) {
    return DedicatedTerminalState(sessions: sessions ?? this.sessions);
  }
}

class DedicatedTerminalNotifier extends StateNotifier<DedicatedTerminalState> {
  final Ref _ref;

  DedicatedTerminalNotifier(this._ref) : super(DedicatedTerminalState());

  void sendCommand(
    DedicatedTerminalType type,
    String command, {
    bool interrupt = false,
    bool clear = true,
  }) {
    var session = state.sessions[type];

    if (session == null || session.isExited) {
      _createSession(type);
      // Wait more for session to initialize (init-host takes time)
      Future.delayed(const Duration(seconds: 2), () {
        _sendToSession(
          type,
          command,
          false,
          clear: clear,
        ); // No interrupt on first command
      });
    } else {
      _sendToSession(type, command, interrupt, clear: clear);
    }
  }

  void sendRawChar(DedicatedTerminalType type, String char) {
    final session = state.sessions[type];
    if (session == null || session.isExited) return;

    session.pty.write(Uint8List.fromList(utf8.encode(char)));
  }

  void _sendToSession(
    DedicatedTerminalType type,
    String command,
    bool interrupt, {
    bool clear = false,
  }) {
    final session = state.sessions[type];
    if (session == null) return;

    if (clear) {
      clearTerminal(type);
    }

    final runtime = _ref.read(runtimeServiceProvider);
    String translatedCommand = command;
    if (Platform.isAndroid || Platform.isIOS) {
      final hostProjectsPath = p.join(runtime.appDirectory, 'projects');
      if (translatedCommand.contains(hostProjectsPath)) {
        translatedCommand = translatedCommand.replaceAll(
          hostProjectsPath,
          '/root/projects',
        );
      }
      if (translatedCommand.contains('/storage/emulated/0')) {
        translatedCommand = translatedCommand.replaceAll(
          '/storage/emulated/0',
          '/sdcard',
        );
      }
    }

    if (interrupt) {
      session.pty.write(Uint8List.fromList([3]));
      Future.delayed(const Duration(milliseconds: 100), () {
        session.pty.write(
          Uint8List.fromList(utf8.encode('$translatedCommand\n')),
        );
      });
    } else {
      session.pty.write(
        Uint8List.fromList(utf8.encode('$translatedCommand\n')),
      );
    }
  }

  void _createSession(DedicatedTerminalType type) {
    final runtime = _ref.read(runtimeServiceProvider);
    final workspace = _ref.read(workspaceProvider);

    final id = const Uuid().v4();
    final title = type.toString().split('.').last.toUpperCase();

    try {
      String dir = workspace.currentPath ?? runtime.workingDirectory;
      if ((Platform.isAndroid || Platform.isIOS) && dir.contains('/storage/emulated/0')) {
        dir = dir.replaceAll('/storage/emulated/0', '/sdcard');
      }
      final env = Map<String, String>.from(runtime.env);

      final sessionTmpDir = p.join(
        runtime.appDirectory,
        'runtime',
        'tmp',
        'dedicated_${type.index}_$id',
      );
      if (Directory(sessionTmpDir).existsSync()) {
        Directory(sessionTmpDir).deleteSync(recursive: true);
      }
      Directory(sessionTmpDir).createSync(recursive: true);

      env['PROOT_TMP_DIR'] = sessionTmpDir;
      env['PWD'] = dir;

      final shell = Platform.isAndroid
          ? '/system/bin/sh'
          : (Platform.isWindows ? 'cmd.exe' : 'bash');
      final List<String> args = Platform.isAndroid
          ? [runtime.prootCommand, runtime.appDirectory]
          : [];

      final pty = Pty.start(
        shell,
        arguments: args,
        environment: env,
        workingDirectory: Platform.isAndroid ? dir : dir,
      );

      final xtermVc = xt.TerminalController();
      final xtermTerm = xt.Terminal(
        maxLines: 2000,
        platform: xt.TerminalTargetPlatform.android,
        onOutput: (data) {
          pty.write(Uint8List.fromList(utf8.encode(data)));
        },
        onResize: (cols, rows, int pixelWidth, int pixelHeight) {
          pty.resize(rows, cols);
        },
      );

      final sub = pty.output.listen(
        (data) {
          xtermTerm.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: () {
          _markAsExited(type);
          xtermTerm.write('\r\n\x1b[1;31m[Process exited]\x1b[0m\r\n');
        },
      );

      final session = TerminalSession(
        id: id,
        title: title,
        pty: pty,
        workingDir: dir,
        xtermTerminal: xtermTerm,
        xtermViewController: xtermVc,
        ptyOutSubscription: sub,
      );

      final newSessions = Map<DedicatedTerminalType, TerminalSession?>.from(
        state.sessions,
      );
      newSessions[type] = session;
      state = state.copyWith(sessions: newSessions);
    } catch (e) {
      debugPrint('Failed to start dedicated terminal $type: $e');
    }
  }

  void _markAsExited(DedicatedTerminalType type) {
    final session = state.sessions[type];
    if (session == null) return;

    final newSessions = Map<DedicatedTerminalType, TerminalSession?>.from(
      state.sessions,
    );
    newSessions[type] = TerminalSession(
      id: session.id,
      title: session.title,
      pty: session.pty,
      workingDir: session.workingDir,
      xtermTerminal: session.xtermTerminal,
      xtermViewController: session.xtermViewController,
      ptyOutSubscription: session.ptyOutSubscription,
      isExited: true,
    );
    state = state.copyWith(sessions: newSessions);
  }

  void clearTerminal(DedicatedTerminalType type) {
    final session = state.sessions[type];
    if (session == null) return;

    session.xtermTerminal.eraseDisplay();
    session.xtermTerminal.eraseScrollbackOnly();
  }

  @override
  void dispose() {
    for (final session in state.sessions.values) {
      session?.ptyOutSubscription?.cancel();
      try {
        session?.pty.kill();
      } catch (_) {}
    }
    super.dispose();
  }
}

final dedicatedTerminalProvider =
    StateNotifierProvider<DedicatedTerminalNotifier, DedicatedTerminalState>((
      ref,
    ) {
      return DedicatedTerminalNotifier(ref);
    });
