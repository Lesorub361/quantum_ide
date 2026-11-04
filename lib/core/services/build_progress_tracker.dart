import 'dart:async';

import 'package:flutter/foundation.dart';

enum BuildStage { idle, pubGet, gradle, compile, packaging, done, failed }

@immutable
class BuildProgress {
  final BuildStage stage;
  final double? fraction; // null = indeterminate
  final String message; // last meaningful line / current task
  final Duration elapsed;
  final Duration sinceLastOutput;
  final String? apkPath;
  final List<String> errors;

  const BuildProgress({
    this.stage = BuildStage.idle,
    this.fraction,
    this.message = '',
    this.elapsed = Duration.zero,
    this.sinceLastOutput = Duration.zero,
    this.apkPath,
    this.errors = const [],
  });

  bool get active =>
      stage != BuildStage.idle && stage != BuildStage.done && stage != BuildStage.failed;

  BuildProgress copyWith({
    BuildStage? stage,
    double? fraction,
    bool clearFraction = false,
    String? message,
    Duration? elapsed,
    Duration? sinceLastOutput,
    String? apkPath,
    List<String>? errors,
  }) =>
      BuildProgress(
        stage: stage ?? this.stage,
        fraction: clearFraction ? null : (fraction ?? this.fraction),
        message: message ?? this.message,
        elapsed: elapsed ?? this.elapsed,
        sinceLastOutput: sinceLastOutput ?? this.sinceLastOutput,
        apkPath: apkPath ?? this.apkPath,
        errors: errors ?? this.errors,
      );
}

/// Parses raw terminal output of `flutter build` / gradle and exposes a
/// structured progress state, so the UI can show stages, a timer and a
/// "still working" heartbeat instead of a silent terminal.
class BuildProgressTracker {
  BuildProgressTracker._();
  static final BuildProgressTracker instance = BuildProgressTracker._();

  final ValueNotifier<BuildProgress> progress = ValueNotifier(const BuildProgress());

  static final _ansi = RegExp(r'\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07');
  static final _startRe = RegExp(r'flutter build|gradlew\s+assemble|gradlew\s+bundle|flutter pub get');
  static final _gradlePct = RegExp(r'(\d{1,3})\s*%\s*(EXECUTING|CONFIGURING|INITIALIZING)?', caseSensitive: false);
  static final _gradleTask = RegExp(r'^> Task (:\S+)');
  static final _apkRe = RegExp(r'(\S+\.(?:apk|aab))');
  static final _errRe = RegExp(r'(error:|FAILURE:|Exception|BUILD FAILED|✗|Error:)');

  DateTime? _start;
  DateTime _lastOutput = DateTime.now();
  Timer? _ticker;
  String _tail = '';
  final List<String> _log = [];

  /// Last [n] cleaned lines of build output (used by the AI agent tool).
  List<String> logTail(int n) => _log.length <= n ? List.of(_log) : _log.sublist(_log.length - n);

  void start(String command) {
    _start = DateTime.now();
    _lastOutput = _start!;
    _tail = '';
    progress.value = BuildProgress(
      stage: command.contains('pub get') ? BuildStage.pubGet : BuildStage.gradle,
      message: command,
    );
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final s = _start;
    if (s == null) return;
    final now = DateTime.now();
    progress.value = progress.value.copyWith(
      elapsed: now.difference(s),
      sinceLastOutput: now.difference(_lastOutput),
    );
  }

  void _finish(BuildStage stage, {String? apk}) {
    _ticker?.cancel();
    _ticker = null;
    final s = _start;
    progress.value = progress.value.copyWith(
      stage: stage,
      fraction: stage == BuildStage.done ? 1.0 : null,
      elapsed: s != null ? DateTime.now().difference(s) : null,
      sinceLastOutput: Duration.zero,
      apkPath: apk,
    );
    _start = null;
  }

  void dismiss() {
    _ticker?.cancel();
    _start = null;
    progress.value = const BuildProgress();
  }

  /// Feed any chunk of terminal output.
  void feed(String chunk) {
    final text = (_tail + chunk).replaceAll(_ansi, '');
    final lines = text.split(RegExp(r'[\r\n]+'));
    _tail = lines.removeLast();
    for (final raw in lines.followedBy([_tail])) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (progress.value.active || line.startsWith('▶')) {
        _log.add(line.length > 400 ? line.substring(0, 400) : line);
        if (_log.length > 400) _log.removeAt(0);
      }
      _line(line);
    }
  }

  void _line(String line) {
    if (!progress.value.active) {
      if (line.startsWith('▶') && _startRe.hasMatch(line)) start(line.substring(1).trim());
      if (!progress.value.active) return;
    }
    _lastOutput = DateTime.now();
    var p = progress.value;

    if (line.contains('Running Gradle task') || line.startsWith('> Task') || line.contains('Configure project')) {
      p = p.copyWith(stage: BuildStage.gradle);
    }
    final task = _gradleTask.firstMatch(line);
    if (task != null) {
      final t = task.group(1)!;
      var stage = p.stage;
      if (t.contains('compile')) stage = BuildStage.compile;
      if (t.contains('package') || t.contains('assemble') || t.contains('sign')) stage = BuildStage.packaging;
      p = p.copyWith(stage: stage, message: 'Gradle $t');
    }
    final pct = _gradlePct.firstMatch(line);
    if (pct != null) {
      final v = int.tryParse(pct.group(1)!);
      if (v != null && v <= 100) p = p.copyWith(fraction: v / 100);
    }
    if (line.contains('Resolving dependencies') || line.contains('Got dependencies')) {
      p = p.copyWith(stage: BuildStage.pubGet, message: line);
    }
    if (line.contains('Compiling') || line.contains('Dart compile') || line.contains('Running Gradle')) {
      p = p.copyWith(message: line);
    }
    if (line.startsWith('✓') || line.contains('Built build/') || line.contains('BUILD SUCCESSFUL')) {
      progress.value = p;
      _finish(BuildStage.done, apk: _apkRe.firstMatch(line)?.group(1));
      return;
    }
    if (line.contains('BUILD FAILED') ||
        line.contains('✗ Сборка') ||
        RegExp(r'Gradle task \w+ failed').hasMatch(line)) {
      progress.value = p.copyWith(errors: [...p.errors, line]);
      _finish(BuildStage.failed);
      return;
    }
    if (_errRe.hasMatch(line) && p.errors.length < 30) {
      p = p.copyWith(errors: [...p.errors, line]);
    }
    if (p.message.isEmpty || (!line.startsWith('>') && line.length < 200)) {
      p = p.copyWith(message: line);
    }
    progress.value = p;
  }
}
