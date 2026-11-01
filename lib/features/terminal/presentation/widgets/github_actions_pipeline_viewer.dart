import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/models/project_model.dart';
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
  final String defaultSummary;
  PipelineStepStatus status;
  Duration? duration;
  final List<String> logs;
  bool isExpanded;
  DateTime? startTime;

  _PipelineStep({
    required this.id,
    required this.title,
    required this.defaultSummary,
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
  final ProjectType projectType;
  final VoidCallback? onRebuild;
  final VoidCallback? onSwitchToTerminal;

  const GithubActionsPipelineViewer({
    super.key,
    required this.session,
    this.projectType = ProjectType.flutter,
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
  late ProjectType _effectiveProjectType;
  int _activeStepIndex = 0;
  Timer? _tickerTimer;
  DateTime _jobStartTime = DateTime.now();
  Duration _totalJobDuration = Duration.zero;
  Duration? _parsedTotalDuration;
  bool _isBuildFinished = false;
  bool _isBuildSuccess = false;
  bool _hasStartedAnyCommand = false;
  String _searchFilter = '';
  int _lastParsedBufferLine = 0;
  late AnimationController _pulseController;

  static final RegExp _brailleOnlyRegex = RegExp(
    r'^[\s\u2800-\u28FF⏳⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]+(\d+(\.\d+)?s)?\s*$',
  );
  static final RegExp _trailingBrailleRegex = RegExp(
    r'\s+[\u2800-\u28FF⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]+(\s+\d+(\.\d+)?s)?\s*$',
  );
  static final RegExp _secondsDurationRegex = RegExp(r'(\d+(?:\.\d+)?)s\b');
  static final RegExp _gradleDurationRegex = RegExp(
    r'in\s+(?:(\d+)m\s+)?(\d+)s\b',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _effectiveProjectType = widget.projectType;
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
          if (!_isBuildFinished && _hasStartedAnyCommand) {
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

  String _getJobTitle() {
    switch (_effectiveProjectType) {
      case ProjectType.androidKotlin:
        return 'build-kotlin (Android Kotlin · Gradle APK)';
      case ProjectType.androidJava:
        return 'build-java (Android Java · Gradle APK)';
      case ProjectType.web:
      case ProjectType.nodejs:
        return 'build-web (Web / Node.js → Android APK)';
      case ProjectType.python:
        return 'build-python (Python / Flet Build)';
      case ProjectType.rust:
        return 'build-rust (Rust Cargo Build)';
      case ProjectType.dart:
        return 'build-dart (Dart Native Compile)';
      case ProjectType.flutter:
      case ProjectType.other:
        return 'build-flutter (Flutter · ARM64 APK)';
    }
  }

  List<_PipelineStep> _buildStepsForType(ProjectType type) {
    switch (type) {
      case ProjectType.androidKotlin:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Java 17, Android SDK & Gradle JVM)',
            defaultSummary: '✓ Окружение Java 17, Android SDK и флаги памяти Gradle настроены',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Разрешение зависимостей (Gradle & Kotlin libraries)',
            defaultSummary: '✓ Зависимости Gradle и плагины Kotlin проверены',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Компиляция ресурсов и нативный AAPT2 / NDK',
            defaultSummary: '✓ Ресурсы Android и нативный ARM64 AAPT2 готовы',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Компиляция Kotlin & Java (:app:compileKotlin / DEX)',
            defaultSummary: '✓ Исходный код Kotlin и Java скомпилирован в DEX',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Сборка и выравнивание APK (:app:packageApk)',
            defaultSummary: '✓ APK-пакет сформирован и выровнен',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки и готовность к установке APK',
            defaultSummary: '✓ Сборка Android (Kotlin) успешно завершена',
          ),
        ];
      case ProjectType.androidJava:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Java 17, Android SDK & Gradle JVM)',
            defaultSummary: '✓ Окружение Java 17, Android SDK и параметры JVM настроены',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Разрешение зависимостей (Gradle Maven / AndroidX)',
            defaultSummary: '✓ Библиотеки проекта и зависимости Gradle проверены',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Обработка ресурсов AAPT2 & генерация R.java',
            defaultSummary: '✓ Ресурсы приложения обработаны нативным AAPT2',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Компиляция Java (:app:compileJavaWithJavac & D8 DEX)',
            defaultSummary: '✓ Классы Java скомпилированы и упакованы в DEX',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Сборка и упаковка APK (:app:packageApk)',
            defaultSummary: '✓ APK-файл собран в app/build/outputs/apk/',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки и готовность к установке APK',
            defaultSummary: '✓ Сборка Android (Java) успешно завершена',
          ),
        ];
      case ProjectType.web:
      case ProjectType.nodejs:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Node.js, Android SDK & AAPT2)',
            defaultSummary: '✓ Инструменты сборки Web→APK инициализированы',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Проверка зависимостей и веб-ресурсов (npm / assets)',
            defaultSummary: '✓ Файлы веб-приложения подготовлены к упаковке',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Генерация Android WebView-контейнера и AndroidManifest',
            defaultSummary: '✓ Шаблон Android WebView и ресурсы сгенерированы',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Компиляция Java-обёртки и DEX-байткода',
            defaultSummary: '✓ Классы контейнера скомпилированы в classes.dex',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Упаковка и подпись APK (zipalign & apksigner)',
            defaultSummary: '✓ APK подписан ключом и выровнен',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки и готовность к установке APK',
            defaultSummary: '✓ Web APK готов к установке',
          ),
        ];
      case ProjectType.python:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Python 3 & pip)',
            defaultSummary: '✓ Окружение Python 3 инициализировано',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Установка и проверка пакетов (requirements.txt)',
            defaultSummary: '✓ Пакеты Python проверены',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Проверка конфигурации сборки (Flet / Buildozer)',
            defaultSummary: '✓ Конфигурация Python-проекта проверена',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Упаковка Python-модулей и зависимостей',
            defaultSummary: '✓ Модули приложения упакованы',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Формирование выходного пакета приложения',
            defaultSummary: '✓ Выходной артефакт сформирован',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки',
            defaultSummary: '✓ Команда выполнена успешно',
          ),
        ];
      case ProjectType.rust:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Rustc & Cargo ARM64)',
            defaultSummary: '✓ Toolchain Rust ARM64 готов',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Разрешение зависимостей (Cargo.toml / crates.io)',
            defaultSummary: '✓ Зависимости Cargo разрешены',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Проверка типов и заимствований (cargo check)',
            defaultSummary: '✓ Статическая проверка типов пройдена',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Компиляция крейтов (cargo build)',
            defaultSummary: '✓ Целевые крейты скомпилированы',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Линковка бинарного файла',
            defaultSummary: '✓ Исполняемый файл слинкован',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки',
            defaultSummary: '✓ Сборка Rust завершена',
          ),
        ];
      case ProjectType.dart:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Dart SDK ARM64)',
            defaultSummary: '✓ Окружение Dart SDK готово',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Получение пакетов (dart pub get)',
            defaultSummary: '✓ Пакеты pubspec.yaml проверены',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Статический анализ (dart analyze)',
            defaultSummary: '✓ Анализ кода завершён',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Компиляция исполняемого файла (dart compile exe)',
            defaultSummary: '✓ Нативный бинарный файл скомпилирован',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Проверка выходного бинарного файла',
            defaultSummary: '✓ Артефакт проверен',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки',
            defaultSummary: '✓ Сборка Dart завершена',
          ),
        ];
      case ProjectType.flutter:
      case ProjectType.other:
        return [
          _PipelineStep(
            id: 'env',
            title: 'Подготовка окружения (Java 17, Flutter SDK & защита памяти)',
            defaultSummary: '✓ Окружение Java 17, лимиты памяти JVM и нативный AAPT2 настроены',
          ),
          _PipelineStep(
            id: 'deps',
            title: 'Получение зависимостей (flutter pub get)',
            defaultSummary: '✓ Зависимости pubspec.yaml разрешены (использован кэш .dart_tool)',
          ),
          _PipelineStep(
            id: 'ndk',
            title: 'Проверка Android NDK, CMake и нативного AAPT2',
            defaultSummary: '✓ Тулчейн Android SDK, NDK и Bionic/glibc проверены',
          ),
          _PipelineStep(
            id: 'compile',
            title: 'Сборка APK (Gradle assemble & компиляция ARM64)',
            defaultSummary: '✓ Задача Gradle assemble выполнена успешно',
          ),
          _PipelineStep(
            id: 'package',
            title: 'Упаковка и проверка APK (app-release.apk / app-debug.apk)',
            defaultSummary: '✓ APK-файл упакован в build/app/outputs/flutter-apk/',
          ),
          _PipelineStep(
            id: 'finalize',
            title: 'Завершение сборки и готовность к установке APK',
            defaultSummary: '✓ APK скопирован в корень проекта и готов к установке',
          ),
        ];
    }
  }

  void _initSteps({ProjectType? overrideType}) {
    if (overrideType != null) {
      _effectiveProjectType = overrideType;
    } else {
      _effectiveProjectType = widget.projectType;
    }
    _steps = _buildStepsForType(_effectiveProjectType);
    _activeStepIndex = 0;
    _jobStartTime = DateTime.now();
    _totalJobDuration = Duration.zero;
    _parsedTotalDuration = null;
    _lastParsedBufferLine = 0;
    _isBuildFinished = false;
    _isBuildSuccess = false;
    _hasStartedAnyCommand = false;
  }

  @override
  void didUpdateWidget(GithubActionsPipelineViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.xtermTerminal.removeListener(_onTerminalOutput);
      widget.session.xtermTerminal.addListener(_onTerminalOutput);
      _initSteps();
      _parseInitialBuffer();
    } else if (oldWidget.projectType != widget.projectType) {
      _effectiveProjectType = widget.projectType;
      final newTemplates = _buildStepsForType(_effectiveProjectType);
      for (int i = 0; i < _steps.length && i < newTemplates.length; i++) {
        _steps[i] = _PipelineStep(
          id: newTemplates[i].id,
          title: newTemplates[i].title,
          defaultSummary: newTemplates[i].defaultSummary,
          status: _steps[i].status,
          duration: _steps[i].duration,
          logs: List<String>.from(_steps[i].logs),
          isExpanded: _steps[i].isExpanded,
          startTime: _steps[i].startTime,
        );
      }
      setState(() {});
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
    if (buffer.lines.length < _lastParsedBufferLine) {
      // Terminal was cleared for a new build run
      _initSteps();
      _parseLinesFrom(0, buffer.lines.length);
      return;
    }
    if (buffer.lines.length > _lastParsedBufferLine) {
      _parseLinesFrom(_lastParsedBufferLine, buffer.lines.length);
    }
  }

  void _ensureStepHasLogs(_PipelineStep step) {
    if (step.logs.isEmpty) {
      step.logs.add(step.defaultSummary);
    }
  }

  void _advanceToStep(int targetIndex) {
    if (targetIndex < _activeStepIndex) return;
    if (targetIndex == _activeStepIndex) {
      if (_steps[_activeStepIndex].status == PipelineStepStatus.pending) {
        _steps[_activeStepIndex].status = PipelineStepStatus.inProgress;
        _steps[_activeStepIndex].startTime ??= DateTime.now();
        _steps[_activeStepIndex].isExpanded = true;
      }
      return;
    }

    final now = DateTime.now();
    // Complete previous steps
    for (int i = 0; i < targetIndex; i++) {
      if (_steps[i].status != PipelineStepStatus.success) {
        _steps[i].status = PipelineStepStatus.success;
        _steps[i].isExpanded = false;
        if (_steps[i].duration == null) {
          if (_steps[i].startTime != null) {
            final diff = now.difference(_steps[i].startTime!);
            _steps[i].duration =
                diff.inSeconds > 0 ? diff : const Duration(seconds: 1);
          } else {
            _steps[i].duration = const Duration(seconds: 1);
          }
        }
        _ensureStepHasLogs(_steps[i]);
      }
    }

    _activeStepIndex = targetIndex;
    if (_activeStepIndex < _steps.length) {
      _steps[_activeStepIndex].status = PipelineStepStatus.inProgress;
      _steps[_activeStepIndex].startTime ??= now;
      _steps[_activeStepIndex].isExpanded = true;
    }
  }

  Duration _computeEffectiveTotalDuration() {
    if (_parsedTotalDuration != null && _parsedTotalDuration!.inSeconds > 0) {
      return _parsedTotalDuration!;
    }
    int sumSecs = 0;
    for (final s in _steps) {
      if (s.duration != null) {
        sumSecs += s.duration!.inSeconds;
      }
    }
    if (_totalJobDuration.inSeconds > sumSecs) {
      return _totalJobDuration;
    }
    return Duration(seconds: sumSecs > 0 ? sumSecs : 1);
  }

  void _parseLinesFrom(int start, int end) {
    final buffer = widget.session.xtermTerminal.buffer;
    for (int i = start; i < end; i++) {
      String lineStr = buffer.lines[i].toString().trimRight();
      if (lineStr.isEmpty) continue;

      // Filter out pure braille spinner lines (e.g. " ⠁ 1437.9s" or "   ⠂")
      if (_brailleOnlyRegex.hasMatch(lineStr)) {
        final durMatch = _secondsDurationRegex.firstMatch(lineStr);
        if (durMatch != null) {
          final secs = double.tryParse(durMatch.group(1) ?? '');
          if (secs != null && secs > 0 && _activeStepIndex < _steps.length) {
            final d = Duration(milliseconds: (secs * 1000).round());
            _steps[_activeStepIndex].duration = d;
            if (_parsedTotalDuration == null || d > _parsedTotalDuration!) {
              _parsedTotalDuration = d;
            }
          }
        }
        continue;
      }

      // Clean trailing braille spinner from status lines
      final trailingMatch = _trailingBrailleRegex.firstMatch(lineStr);
      if (trailingMatch != null) {
        final durMatch = _secondsDurationRegex.firstMatch(
          trailingMatch.group(0) ?? '',
        );
        if (durMatch != null) {
          final secs = double.tryParse(durMatch.group(1) ?? '');
          if (secs != null && secs > 0 && _activeStepIndex < _steps.length) {
            final d = Duration(milliseconds: (secs * 1000).round());
            _steps[_activeStepIndex].duration = d;
            if (_parsedTotalDuration == null || d > _parsedTotalDuration!) {
              _parsedTotalDuration = d;
            }
          }
        }
        lineStr = lineStr.substring(0, trailingMatch.start).trimRight();
        if (lineStr.isEmpty) continue;
      }

      final trimmedLeft = lineStr.trimLeft();
      // Skip interactive shell prompts or session restart notices
      if (trimmedLeft.startsWith('boss@ubuntu') ||
          trimmedLeft.startsWith('root@') ||
          trimmedLeft.startsWith('➜ ') ||
          trimmedLeft.contains('[Сессия терминала перезапущена')) {
        continue;
      }

      final lower = trimmedLeft.toLowerCase();

      // Command banner: "▶ ..." starts or restarts the pipeline at Step 0 (env)
      if (trimmedLeft.startsWith('▶')) {
        ProjectType? detectedFromCmd;
        if (lower.contains('gradlew')) {
          if (_effectiveProjectType != ProjectType.androidJava &&
              _effectiveProjectType != ProjectType.androidKotlin) {
            detectedFromCmd = ProjectType.androidKotlin;
          }
        } else if (lower.contains('flutter ')) {
          detectedFromCmd = ProjectType.flutter;
        } else if (lower.contains('cargo ')) {
          detectedFromCmd = ProjectType.rust;
        } else if (lower.contains('npm ') || lower.contains('web')) {
          detectedFromCmd = ProjectType.nodejs;
        } else if (lower.contains('pip') || lower.contains('flet')) {
          detectedFromCmd = ProjectType.python;
        } else if (lower.contains('dart ')) {
          detectedFromCmd = ProjectType.dart;
        }

        if (_isBuildFinished || _activeStepIndex > 0) {
          _initSteps(overrideType: detectedFromCmd ?? _effectiveProjectType);
          _lastParsedBufferLine = i;
        } else if (detectedFromCmd != null &&
            detectedFromCmd != _effectiveProjectType) {
          _initSteps(overrideType: detectedFromCmd);
        }

        _hasStartedAnyCommand = true;
        _advanceToStep(0);
        _steps[0].logs.add(trimmedLeft);
        continue;
      }

      if (trimmedLeft.startsWith('────────')) {
        continue;
      }

      _hasStartedAnyCommand = true;

      // Parse step durations like "(8.3s)" or "1437.9s" or "in 1m 24s"
      final gradleDur = _gradleDurationRegex.firstMatch(trimmedLeft);
      if (gradleDur != null) {
        final mins = int.tryParse(gradleDur.group(1) ?? '0') ?? 0;
        final secs = int.tryParse(gradleDur.group(2) ?? '0') ?? 0;
        final total = Duration(minutes: mins, seconds: secs);
        if (total.inSeconds > 0) {
          _parsedTotalDuration = total;
        }
      } else {
        final secMatch = _secondsDurationRegex.firstMatch(trimmedLeft);
        if (secMatch != null) {
          final secs = double.tryParse(secMatch.group(1) ?? '');
          if (secs != null && secs >= 0.5 && _activeStepIndex < _steps.length) {
            final d = Duration(milliseconds: (secs * 1000).round());
            _steps[_activeStepIndex].duration = d;
            if (secs > 15 &&
                (_parsedTotalDuration == null || d > _parsedTotalDuration!)) {
              _parsedTotalDuration = d;
            }
          }
        }
      }

      // Trigger step transitions in strict lifecycle order
      if (lower.contains('apk готов') ||
          lower.contains('debug apk:') ||
          lower.contains('release apk:') ||
          lower.contains('appbundle готов') ||
          lower.contains('готовый web apk собран') ||
          lower.contains('готово к установке')) {
        _advanceToStep(5); // finalize
      } else if (lower.contains('✓ built ') ||
          lower.contains('built build/app/outputs') ||
          lower.contains('build successful') ||
          lower.contains('> task :app:package') ||
          lower.contains('> task :app:assemble') ||
          lower.contains('подписываем apk')) {
        _advanceToStep(4); // package
      } else if (lower.contains('running gradle task') ||
          lower.contains('> task :app:compile') ||
          lower.contains('> task :app:dex') ||
          lower.contains('> task :app:merge') ||
          lower.contains('compiling ') ||
          lower.contains('компиляция ') ||
          lower.contains('cargo build') ||
          lower.contains('dart compile')) {
        _advanceToStep(3); // compile
      } else if (lower.contains('quantum-patch-ndk') ||
          lower.contains('checking the license') ||
          lower.contains('> task :app:check') ||
          lower.contains('> task :app:process') ||
          lower.contains('> task :app:generate') ||
          lower.contains('> task :app:map') ||
          lower.contains('aapt2') ||
          lower.contains('cmake')) {
        _advanceToStep(2); // ndk / resources
      } else if (lower.contains('resolving dependencies') ||
          lower.contains('downloading packages') ||
          lower.contains('got dependencies') ||
          lower.contains('flutter pub get') ||
          lower.contains('> configure project') ||
          lower.contains('> task :app:prebuild') ||
          lower.contains('npm install') ||
          lower.contains('collecting ')) {
        _advanceToStep(1); // deps
      } else if (lower.contains('[quantum-heal-x64]') ||
          lower.contains('quantumide engine:') ||
          lower.contains('starting a gradle daemon') ||
          lower.contains('to honour the jvm settings')) {
        if (_activeStepIndex == 0) {
          _advanceToStep(0);
        }
      }

      // Record logs to current active step (avoid consecutive duplicate lines)
      if (_activeStepIndex < _steps.length) {
        final stepLogs = _steps[_activeStepIndex].logs;
        if (stepLogs.isEmpty || stepLogs.last != trimmedLeft) {
          stepLogs.add(trimmedLeft);
        }
      }

      // Check overall build completion (success / failure)
      if (lower.contains('✓ built') ||
          lower.contains('✓ apk готов') ||
          lower.contains('✓ debug apk') ||
          lower.contains('✓ release apk') ||
          lower.contains('✓ appbundle готов') ||
          lower.contains('build successful') ||
          lower.contains('apk собран')) {
        _isBuildFinished = true;
        _isBuildSuccess = true;
        for (int sIdx = 0; sIdx < _steps.length; sIdx++) {
          final s = _steps[sIdx];
          if (s.status == PipelineStepStatus.inProgress ||
              s.status == PipelineStepStatus.pending) {
            s.status = PipelineStepStatus.success;
            s.duration ??= const Duration(seconds: 1);
          }
          if (sIdx < _steps.length - 1) {
            s.isExpanded = false;
          } else {
            s.isExpanded = true;
          }
          _ensureStepHasLogs(s);
        }
        _totalJobDuration = _computeEffectiveTotalDuration();
      } else if (lower.contains('failure: build failed') ||
          lower.contains('build failed') ||
          lower.contains('gradle task assemble') && lower.contains('failed') ||
          lower.contains('✗ сборка завершилась с кодом') ||
          (lower.contains('error:') && lower.contains('target'))) {
        _isBuildFinished = true;
        _isBuildSuccess = false;
        if (_activeStepIndex < _steps.length) {
          _steps[_activeStepIndex].status = PipelineStepStatus.failure;
          _steps[_activeStepIndex].isExpanded = true;
        }
        _totalJobDuration = _computeEffectiveTotalDuration();
      }
    }

    _lastParsedBufferLine = end;
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '0s';
    if (d.inMinutes > 0) {
      final secs = d.inSeconds % 60;
      return '${d.inMinutes} мин $secs с';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = ref.watch(workspaceProvider);
    final wsPath = workspaceState.currentPath;
    final apkDiagnostics = ref.read(androidBuildDiagnosticsServiceProvider);
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
    final effectiveDuration = _isBuildFinished
        ? _computeEffectiveTotalDuration()
        : _totalJobDuration;

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
                      _getJobTitle(),
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _GhTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isBuildFinished
                          ? (_isBuildSuccess
                              ? 'Завершено успешно за ${_formatDuration(effectiveDuration)}'
                              : 'Завершилось с ошибкой (${_formatDuration(effectiveDuration)})')
                          : (_hasStartedAnyCommand
                              ? 'Выполняется · ${_formatDuration(effectiveDuration)}'
                              : 'Готов к запуску сборки · Нажмите кнопку APK выше'),
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
                  tooltip: 'Пересобрать проект',
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

    if (!_hasStartedAnyCommand) {
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _GhTokens.textMuted, width: 1.8),
        ),
        child: const Icon(LucideIcons.play, size: 11, color: _GhTokens.textSecondary),
      );
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
    final displayLogs = step.logs.isEmpty &&
            step.status == PipelineStepStatus.success
        ? <String>[step.defaultSummary]
        : step.logs;

    final filtered = _searchFilter.isEmpty
        ? displayLogs
        : displayLogs
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
                  Clipboard.setData(ClipboardData(text: displayLogs.join('\n')));
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
                    : 'Совпадений по фильтру не найдено.',
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
    final isNonApkTarget = _effectiveProjectType == ProjectType.rust ||
        _effectiveProjectType == ProjectType.dart ||
        (_effectiveProjectType == ProjectType.python && apkInfo == null);

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
                  isNonApkTarget
                      ? '🎉 Сборка успешно завершена!'
                      : '🎉 APK успешно собран!',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  apkInfo != null
                      ? '${apkInfo.fileName} (${apkInfo.formattedSize})'
                      : (isNonApkTarget
                          ? 'Все шаги сборки выполнены без ошибок'
                          : 'APK готов к установке на устройство'),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: _GhTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (apkInfo != null)
            ElevatedButton.icon(
              onPressed: () async {
                final installer = ref.read(androidAppInstallerServiceProvider);
                await installer.installApk(apkInfo.path, launchAfterInstall: true);
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
