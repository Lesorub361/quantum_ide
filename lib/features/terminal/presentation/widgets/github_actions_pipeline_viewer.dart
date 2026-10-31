import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/android_app_installer_service.dart';
import 'package:quantum_ide/core/services/android_build_diagnostics_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

// ─── GitHub Design Tokens ─────────────────────────────────────────────────────

class _GhTokens {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const border = Color(0xFF30363D);
  static const borderMuted = Color(0xFF21262D);
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted = Color(0xFF6E7681);
  static const green = Color(0xFF238636);
  static const greenBright = Color(0xFF3FB950);
  static const yellow = Color(0xFFD29922);
  static const yellowBright = Color(0xFFE3B341);
  static const red = Color(0xFFDA3633);
  static const blue = Color(0xFF2F81F7);
}

// ─── Pipeline Step Model ──────────────────────────────────────────────────────

enum PipelineStepStatus { pending, inProgress, success, failure }

class _PipelineStep {
  final String id;
  final String title;
  PipelineStepStatus status;
  Duration? duration;
  final List<String> logs;
  bool isExpanded;
  DateTime? startTime;

  _PipelineStep({
    required this.id,
    required this.title,
    this.status = PipelineStepStatus.pending,
    this.duration,
    List<String>? logs,
    this.isExpanded = false,
    this.startTime,
  }) : logs = logs ?? [];
}

// ─── GitHub Actions Pipeline Viewer Widget ────────────────────────────────────

class GithubActionsPipelineViewer extends ConsumerStatefulWidget {
  final TerminalSession session;
  final VoidCallback? onRebuild;
  final VoidCallback? onSwitchToTerminal;

  const GithubActionsPipelineViewer({
    super.key,
    required this.session,
    this.onRebuild,
    this.onSwitchToTerminal,
  });

  @override
  ConsumerState<GithubActionsPipelineViewer> createState() =>
      _GithubActionsPipelineViewerState();
}

class _GithubActionsPipelineViewerState
    extends ConsumerState<GithubActionsPipelineViewer>
    with SingleTickerProviderStateMixin {
  late List<_PipelineStep> _steps;
  int _activeStepIndex = 0;
  Timer? _tickerTimer;
  DateTime _jobStartTime = DateTime.now();
  Duration _totalJobDuration = Duration.zero;
  bool _isBuildFinished = false;
  bool _isBuildSuccess = false;
  String _searchFilter = '';
  int _lastParsedBufferLine = 0;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initSteps();
    widget.session.xtermTerminal.addListener(_onTerminalOutput);
    _parseInitialBuffer();

    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          if (!_isBuildFinished) {
            _totalJobDuration = DateTime.now().difference(_jobStartTime);
            if (_activeStepIndex < _steps.length &&
                _steps[_activeStepIndex].status ==
                    PipelineStepStatus.inProgress &&
                _steps[_activeStepIndex].startTime != null) {
              _steps[_activeStepIndex].duration = DateTime.now()
                  .difference(_steps[_activeStepIndex].startTime!);
            }
          }
        });
      }
    });
  }

  void _initSteps() {
    _steps = [
      _PipelineStep(
        id: 'env',
        title: 'Set up job & Environment (Java 17 & JVM args)',
        status: PipelineStepStatus.inProgress,
        startTime: DateTime.now(),
        isExpanded: true,
      ),
      _PipelineStep(
        id: 'deps',
        title: 'Get dependencies (flutter pub get)',
      ),
      _PipelineStep(
        id: 'ndk',
        title: 'Ensure Android NDK and CMake',
      ),
      _PipelineStep(
        id: 'compile',
        title: 'Build release APK (Universal & Split ABIs)',
      ),
      _PipelineStep(
        id: 'package',
        title: 'Package & Verify APK (app-release.apk)',
      ),
      _PipelineStep(
        id: 'finalize',
        title: 'Complete & Ready to Install',
      ),
    ];
    _activeStepIndex = 0;
    _jobStartTime = DateTime.now();
    _lastParsedBufferLine = 0;
    _isBuildFinished = false;
    _isBuildSuccess = false;
  }

  @override
  void didUpdateWidget(GithubActionsPipelineViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.xtermTerminal.removeListener(_onTerminalOutput);
      widget.session.xtermTerminal.addListener(_onTerminalOutput);
      _initSteps();
      _parseInitialBuffer();
    }
  }

  @override
  void dispose() {
    widget.session.xtermTerminal.removeListener(_onTerminalOutput);
    _tickerTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTerminalOutput() {
    if (!mounted) return;
    _parseNewBufferLines();
  }

  void _parseInitialBuffer() {
    final buffer = widget.session.xtermTerminal.buffer;
    _parseLinesFrom(0, buffer.lines.length);
  }

  void _parseNewBufferLines() {
    final buffer = widget.session.xtermTerminal.buffer;
    if (buffer.lines.length > _lastParsedBufferLine) {
      _parseLinesFrom(_lastParsedBufferLine, buffer.lines.length);
    }
  }

  void _advanceToStep(int targetIndex) {
    if (targetIndex <= _activeStepIndex) return;

    // Complete previous steps
    for (int i = 0; i < targetIndex; i++) {
      if (_steps[i].status != PipelineStepStatus.success) {
        _steps[i].status = PipelineStepStatus.success;
        _steps[i].isExpanded = false;
        _steps[i].duration ??= const Duration(seconds: 4);
      }
    }

    _activeStepIndex = targetIndex;
    if (_activeStepIndex < _steps.length) {
      _steps[_activeStepIndex].status = PipelineStepStatus.inProgress;
      _steps[_activeStepIndex].startTime ??= DateTime.now();
      _steps[_activeStepIndex].isExpanded = true;
    }
  }

  void _parseLinesFrom(int start, int end) {
    final buffer = widget.session.xtermTerminal.buffer;
    for (int i = start; i < end; i++) {
      final lineStr = buffer.lines[i].toString().trimRight();
      if (lineStr.isEmpty) continue;

      final lower = lineStr.toLowerCase();

      // Trigger detection
      if (lower.contains('resolving dependencies') ||
          lower.contains('flutter pub get') ||
          lower.contains('running "flutter pub get"')) {
        _advanceToStep(1); // deps
      } else if (lower.contains('quantum-patch-ndk') ||
          lower.contains('ndk') ||
          lower.contains('cmake') ||
          lower.contains('patching ndk')) {
        _advanceToStep(2); // ndk
      } else if (lower.contains('flutter build apk') ||
          lower.contains('running gradle task') ||
          lower.contains('compiling') ||
          lower.contains('assemble') ||
          lower.contains('building apk')) {
        _advanceToStep(3); // compile
      } else if (lower.contains('built build/app/outputs') ||
          lower.contains('app-release.apk') ||
          lower.contains('app-debug.apk') ||
          lower.contains('build successful')) {
        _advanceToStep(4); // package
      } else if (lower.contains('apk готов') ||
          lower.contains('готовый web apk собран') ||
          lower.contains('готово к установке')) {
        _advanceToStep(5); // finalize
      }

      // Record logs to current step
      if (_activeStepIndex < _steps.length) {
        _steps[_activeStepIndex].logs.add(lineStr);
      }

      // Check success / failure
      if (lower.contains('✓ built') ||
          lower.contains('build successful') ||
          lower.contains('apk собран')) {
        _isBuildFinished = true;
        _isBuildSuccess = true;
        for (final s in _steps) {
          if (s.status == PipelineStepStatus.inProgress ||
              s.status == PipelineStepStatus.pending) {
            s.status = PipelineStepStatus.success;
            s.duration ??= const Duration(seconds: 2);
          }
        }
      } else if (lower.contains('failure: build failed') ||
          lower.contains('gradle build failed') ||
          (lower.contains('error:') && lower.contains('target'))) {
        _isBuildFinished = true;
        _isBuildSuccess = false;
        if (_activeStepIndex < _steps.length) {
          _steps[_activeStepIndex].status = PipelineStepStatus.failure;
          _steps[_activeStepIndex].isExpanded = true;
        }
      }
    }

    _lastParsedBufferLine = end;
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '0s';
    if (d.inMinutes > 0) {
      final secs = d.inSeconds % 60;
      return '${d.inMinutes} мин ${secs} с';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(workspaceProvider);
    final wsPath = workspaceState.currentPath;
    final apkInfo = wsPath != null ? apkDiagnostics.findDebugApk(wsPath) : null;

    return Container(
      color: _GhTokens.bg,
      child: Column(
        children: [
          // ─── Header: Job summary (GitHub Actions Style) ───────────────────
          _buildJobHeader(),

          // ─── Optional Success/Failure Banner ──────────────────────────────
          if (_isBuildFinished && _isBuildSuccess)
            _buildSuccessCard(apkInfo)
          else if (_isBuildFinished && !_isBuildSuccess)
            _buildFailureCard(),

          // ─── Steps List (GitHub Style Pipeline) ───────────────────────────
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: _steps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final step = _steps[index];
                return _buildStepCard(step, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Job Header ───────────────────────────────────────────────────────────

  Widget _buildJobHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: _GhTokens.surface,
        border: Border(bottom: BorderSide(color: _GhTokens.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildOverallStatusIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'build (Release APK & Split ABIs)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _GhTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isBuildFinished
                          ? (_isBuildSuccess
                              ? 'Завершено успешно за ${_formatDuration(_totalJobDuration)}'
                              : 'Завершилось с ошибкой')
                          : 'Началось ${_formatDuration(_totalJobDuration)} назад · Выполняется...',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _GhTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onSwitchToTerminal != null)
                IconButton(
                  tooltip: 'Открыть терминал xterm',
                  icon: const Icon(LucideIcons.terminal,
                      size: 15, color: _GhTokens.textSecondary),
                  onPressed: widget.onSwitchToTerminal,
                ),
              if (widget.onRebuild != null)
                IconButton(
                  tooltip: 'Пересобрать APK',
                  icon: const Icon(LucideIcons.rotate_cw,
                      size: 15, color: _GhTokens.yellowBright),
                  onPressed: widget.onRebuild,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Search Logs Input
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: _GhTokens.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _GhTokens.border),
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchFilter = val),
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 11, color: _GhTokens.textPrimary),
              decoration: InputDecoration(
                hintText: 'Журналы поиска (grep / filter)...',
                hintStyle: GoogleFonts.inter(
                    fontSize: 11, color: _GhTokens.textMuted),
                prefixIcon: const Icon(LucideIcons.search,
                    size: 13, color: _GhTokens.textMuted),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 28, minHeight: 0),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallStatusIcon() {
    if (_isBuildFinished) {
      if (_isBuildSuccess) {
        return Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: _GhTokens.green,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 14, color: Colors.white),
        );
      } else {
        return Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: _GhTokens.red,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 14, color: Colors.white),
        );
      }
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _GhTokens.yellowBright.withValues(
                  alpha: 0.5 + (_pulseController.value * 0.5)),
              width: 2.2,
            ),
          ),
          child: const Center(
            child: SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: _GhTokens.yellowBright,
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Step Card (GitHub Style) ─────────────────────────────────────────────

  Widget _buildStepCard(_PipelineStep step, int index) {
    return Container(
      decoration: BoxDecoration(
        color: _GhTokens.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: step.isExpanded
              ? _GhTokens.border
              : _GhTokens.borderMuted,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Step Header
          InkWell(
            onTap: () {
              setState(() => step.isExpanded = !step.isExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    step.isExpanded
                        ? LucideIcons.chevron_down
                        : LucideIcons.chevron_right,
                    size: 14,
                    color: _GhTokens.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  _buildStepStatusIcon(step.status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.title,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: step.status == PipelineStepStatus.inProgress
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: step.status == PipelineStepStatus.inProgress
                            ? Colors.white
                            : (step.status == PipelineStepStatus.pending
                                ? _GhTokens.textMuted
                                : _GhTokens.textPrimary),
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(step.duration),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      color: step.status == PipelineStepStatus.inProgress
                          ? _GhTokens.yellowBright
                          : _GhTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Step Body (Console Logs)
          if (step.isExpanded) _buildStepConsole(step),
        ],
      ),
    );
  }

  Widget _buildStepStatusIcon(PipelineStepStatus status) {
    switch (status) {
      case PipelineStepStatus.success:
        return const Icon(Icons.check_circle, size: 16, color: _GhTokens.greenBright);
      case PipelineStepStatus.inProgress:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _GhTokens.yellowBright,
          ),
        );
      case PipelineStepStatus.failure:
        return const Icon(Icons.cancel, size: 16, color: _GhTokens.red);
      case PipelineStepStatus.pending:
        return Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _GhTokens.textMuted, width: 1.5),
          ),
        );
    }
  }

  Widget _buildStepConsole(_PipelineStep step) {
    final filtered = _searchFilter.isEmpty
        ? step.logs
        : step.logs
            .where((l) =>
                l.toLowerCase().contains(_searchFilter.toLowerCase()))
            .toList();

    return Container(
      width: double.infinity,
      color: _GhTokens.bg,
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _GhTokens.borderMuted)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${filtered.length} строк лога',
                style: GoogleFonts.inter(fontSize: 10, color: _GhTokens.textMuted),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: step.logs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Логи шага скопированы'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.copy, size: 11, color: _GhTokens.textSecondary),
                      const SizedBox(width: 4),
                      Text('Копировать',
                          style: GoogleFonts.inter(
                              fontSize: 10, color: _GhTokens.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                step.status == PipelineStepStatus.pending
                    ? 'Ожидание выполнения шага...'
                    : 'Вывод отсутствует или отфильтрован.',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 11, color: _GhTokens.textMuted),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, idx) {
                  final line = filtered[idx];
                  final isErr = line.toLowerCase().contains('error') ||
                      line.toLowerCase().contains('failed');
                  final isWarn = line.toLowerCase().contains('warning') ||
                      line.toLowerCase().contains('warn');

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${idx + 1}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: _GhTokens.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            line,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: isErr
                                  ? _GhTokens.red
                                  : (isWarn
                                      ? _GhTokens.yellowBright
                                      : _GhTokens.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ─── Success Banner with 1-Tap APK Installation ───────────────────────────

  Widget _buildSuccessCard(dynamic apkInfo) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _GhTokens.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _GhTokens.greenBright.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.sparkles, color: _GhTokens.greenBright, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎉 APK успешно собран!',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  apkInfo != null
                      ? '${apkInfo.fileName} (${apkInfo.formattedSize})'
                      : 'app-release.apk готов к установке',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: _GhTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (apkInfo != null) {
                final installer = ref.read(androidAppInstallerServiceProvider);
                await installer.installApk(apkInfo.path, launchAfterInstall: true);
              }
            },
            icon: const Icon(LucideIcons.download, size: 13),
            label: const Text('Установить', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _GhTokens.greenBright,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _GhTokens.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _GhTokens.red.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.circle_alert, color: _GhTokens.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Сборка завершилась с ошибкой. Откройте красный шаг выше для просмотра логов.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
