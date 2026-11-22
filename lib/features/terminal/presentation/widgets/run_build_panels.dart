import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quantum_ide/core/services/shizuku_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:conduit_vt/conduit_vt.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/utils/ansi_text_parser.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/apk_signer_widget.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/build_progress_card.dart';
import 'package:quantum_ide/core/services/android_app_installer_service.dart';
import 'package:quantum_ide/core/services/android_build_diagnostics_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/project_sync_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/utils/adaptive_dialog_helper.dart';
import 'package:quantum_ide/core/services/build_resource_optimizer.dart';
import 'package:quantum_ide/core/theme/app_colors.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/build_target_dialog.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_terminal_surface.dart';
import 'package:quantum_ide/features/terminal/engine/quantum_link_detector.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';

// Project-safe: never mutate user's build.gradle.kts or AndroidManifest.xml.
const String _ktRepairCmd = '';

xt.TerminalTheme _resolveAppTerminalTheme(String themeName) {
  for (final p in AppPalette.values) {
    if (p.name == themeName) {
      return p.terminalTheme;
    }
  }
  return resolveConduitPalette(themeName).terminalTheme;
}

final _cachedProjectTypeProvider =
    FutureProvider.family<ProjectType, String>((ref, path) async {
      if (path.isEmpty) return ProjectType.other;
      final dir = Directory(path);
      if (!await dir.exists()) return ProjectType.other;
      try {
        bool hasPubspec = false;
        bool hasPackageJson = false;
        bool hasPyFile = false;
        bool hasHtmlFile = false;
        bool hasGradle = false;
        bool hasCargo = false;
        await for (final file in dir.list(followLinks: false)) {
          final name = p.basename(file.path).toLowerCase();
          if (name == 'pubspec.yaml') hasPubspec = true;
          if (name == 'package.json') hasPackageJson = true;
          if (name.endsWith('.py')) hasPyFile = true;
          if (name == 'index.html' || name.endsWith('.html')) {
            hasHtmlFile = true;
          }
          if (name == 'build.gradle' ||
              name == 'build.gradle.kts' ||
              name == 'settings.gradle' ||
              name == 'settings.gradle.kts') {
            hasGradle = true;
          }
          if (name == 'cargo.toml') hasCargo = true;
        }
        if (hasPubspec) {
          try {
            final pubspecContent = await File(
              p.join(path, 'pubspec.yaml'),
            ).readAsString();
            if (pubspecContent.contains('flutter:')) return ProjectType.flutter;
            return ProjectType.dart;
          } catch (_) {
            return ProjectType.flutter;
          }
        }
        if (hasGradle) {
          if (await File(p.join(path, 'build.gradle.kts')).exists() ||
              await File(p.join(path, 'app', 'build.gradle.kts')).exists()) {
            return ProjectType.androidKotlin;
          }
          final mainDir = Directory(p.join(path, 'app', 'src', 'main'));
          if (await mainDir.exists()) {
            try {
              bool hasJava = false;
              await for (final e in mainDir.list(
                recursive: true,
                followLinks: false,
              )) {
                if (e.path.endsWith('.kt')) return ProjectType.androidKotlin;
                if (e.path.endsWith('.java')) hasJava = true;
              }
              if (hasJava) return ProjectType.androidJava;
            } catch (_) {}
          }
          return ProjectType.androidKotlin;
        }
        if (hasCargo) return ProjectType.rust;
        if (hasPackageJson) return ProjectType.nodejs;
        if (hasPyFile) return ProjectType.python;
        if (hasHtmlFile) return ProjectType.web;
      } catch (_) {}
      return ProjectType.other;
    });

class SidebarRunPanel extends ConsumerStatefulWidget {
  final bool isActive;
  const SidebarRunPanel({super.key, this.isActive = true});

  @override
  ConsumerState<SidebarRunPanel> createState() => _SidebarRunPanelState();
}

class _SidebarRunPanelState extends ConsumerState<SidebarRunPanel> {
  bool _showBeautifulLogs = false;

  ProjectType _detectProjectType(String? path, ProjectType registeredType) {
    if (registeredType != ProjectType.other) return registeredType;
    if (path == null || path.isEmpty) return ProjectType.other;
    return ref.watch(_cachedProjectTypeProvider(path)).valueOrNull ??
        ProjectType.other;
  }

  Future<void> _runDedicatedCommand(String? workspacePath, String cmd, {String? displayCmd}) async {
    ref.read(projectSyncProvider.notifier).cancelSync();
    unawaited(ShizukuBridge.instance.boostForBuild());
    final runtime = ref.read(runtimeServiceProvider);
    final guestPath = workspacePath != null ? PathMapper.mapToGuest(workspacePath, runtime.appDirectory) : null;
    final cdCmd = guestPath != null ? 'mkdir -p "$guestPath" 2>/dev/null; cd "$guestPath"' : '';
    final label = displayCmd ?? (cmd.length > 60 ? '${cmd.substring(0, 57)}...' : cmd);
    final safeLabel = label.replaceAll('"', '\\"');
    const clearScreen = 'printf "\\033[2J\\033[H\\033[3J"';
    final banner = 'printf "\\033[1;36m▶ %s\\033[0m\\n\\033[0;34m──────────────────────────────────────────────────\\033[0m\\n" "$safeLabel"';
    final finalCmd = cdCmd.isNotEmpty ? '$clearScreen && $cdCmd && $banner && $cmd' : '$clearScreen && $banner && $cmd';
    ref.read(dedicatedTerminalProvider.notifier).sendCommand(DedicatedTerminalType.run, finalCmd, interrupt: true, clear: false);
  }

  void _sendRawKeyToDedicatedTerminal(String key) {
    ref.read(dedicatedTerminalProvider.notifier).sendRawChar(DedicatedTerminalType.run, key);
  }

  void _stopCommand() {
    _sendRawKeyToDedicatedTerminal(String.fromCharCode(3));
    ref.read(systemStatsProvider.notifier).freeBackgroundMemory(force: true);
  }

  Future<void> _installBuiltApk(String? workspacePath) async {
    if (workspacePath == null) return;

    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final diagnostics = ref.read(androidBuildDiagnosticsServiceProvider);
    final apkInfo = diagnostics.findDebugApk(workspacePath);

    if (apkInfo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu ? 'APK еще не собран. Сначала нажмите Build APK.' : 'APK is not built yet. Click Build APK first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (apkInfo.isStale && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E222D),
          title: Row(
            children: [
              const Icon(LucideIcons.triangle_alert, color: Colors.amberAccent, size: 20),
              const SizedBox(width: 8),
              Text(isRu ? 'APK устарел' : 'APK Outdated', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Text(
            isRu
                ? 'Исходные файлы проекта были изменены после последней сборки APK (${apkInfo.fileName}).\n\nРекомендуется пересобрать проект. Установить имеющийся файл прямо сейчас?'
                : 'Project files were modified since the last APK build (${apkInfo.fileName}).\n\nRebuilding is recommended. Install existing APK anyway?',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isRu ? 'Отмена' : 'Cancel', style: const TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isRu ? 'Все равно установить' : 'Install anyway', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRu ? 'Установка ${apkInfo.fileName} (${apkInfo.formattedSize}) без ADB...' : 'Installing ${apkInfo.fileName} (${apkInfo.formattedSize}) without ADB...'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }

    final installer = ref.read(androidAppInstallerServiceProvider);
    final res = await installer.installApk(apkInfo.path, launchAfterInstall: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.success
              ? (isRu ? 'Установка запущена нативно (${res.method ?? "PackageInstaller"})' : 'Installation started natively (${res.method ?? "PackageInstaller"})')
              : (isRu ? 'Ошибка установки: ${res.message}' : 'Installation error: ${res.message}')),
          backgroundColor: res.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dedicatedState = ref.watch(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[DedicatedTerminalType.run];
    final workspaceState = ref.watch(workspaceProvider);
    final allProjects = ref.watch(projectServiceProvider);
    final l10n = AppLocalizations.of(context)!;

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
        final autoHotReload = ref.watch(flutterAutoHotReloadProvider);
        final isRu = Localizations.localeOf(context).languageCode == 'ru';
        if (Platform.isAndroid) {
          actions.addAll([
            _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, () {
              ref.read(serverRunningProvider.notifier).state = true;
              ref.read(floatingPreviewUrlProvider.notifier).state = 'http://127.0.0.1:8080';
              ref.read(floatingPreviewVisibleProvider.notifier).state = true;
              ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
              ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
              _runDedicatedCommand(
                workspaceState.currentPath,
                'flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1',
              );
            }),
            _buildActionButton(
              isRu ? 'Web (Статик)' : 'Web (Static)',
              LucideIcons.globe,
              Colors.tealAccent,
              () {
                ref.read(serverRunningProvider.notifier).state = true;
                ref.read(floatingPreviewUrlProvider.notifier).state = 'http://127.0.0.1:8080';
                ref.read(floatingPreviewVisibleProvider.notifier).state = true;
                ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
                ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
                _runDedicatedCommand(
                  workspaceState.currentPath,
                  'flutter build web --no-tree-shake-icons && python3 -m http.server 8080 -d build/web',
                  displayCmd: 'flutter build web + http.server :8080',
                );
              },
            ),
            _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.cyanAccent,
                () => _installBuiltApk(workspaceState.currentPath)),
            _buildActionButton('Reload (r)', LucideIcons.zap, Colors.yellow,
                () => _sendRawKeyToDedicatedTerminal('r')),
            _buildActionButton('Restart (R)', LucideIcons.rotate_cw, Colors.orangeAccent, () {
              _sendRawKeyToDedicatedTerminal('R');
              Future.delayed(const Duration(milliseconds: 1800), () {
                if (mounted) {
                  ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
                }
              });
            }),
            _buildActionButton(
              isRu ? 'Авто-Reload' : 'Auto-Reload',
              autoHotReload ? LucideIcons.sparkles : LucideIcons.circle_pause,
              autoHotReload ? Colors.greenAccent : Colors.white54,
              () => ref.read(flutterAutoHotReloadProvider.notifier).state = !autoHotReload,
            ),
            _buildActionButton(
              isRu ? 'Браузер' : 'Preview',
              LucideIcons.monitor,
              Colors.lightBlueAccent,
              () {
                ref.read(floatingPreviewVisibleProvider.notifier).state = true;
                ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
                ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
              },
            ),
            _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, () {
              _sendRawKeyToDedicatedTerminal('q');
              ref.read(serverRunningProvider.notifier).state = false;
            }),
          ]);
        } else {
          actions.addAll([
            _buildActionButton(l10n.runPC, LucideIcons.laptop, Colors.cyanAccent,
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d linux')),
            _buildActionButton(l10n.runMob, LucideIcons.smartphone, Colors.greenAccent,
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d android')),
            _buildActionButton('Web', LucideIcons.globe, Colors.tealAccent, () {
              ref.read(serverRunningProvider.notifier).state = true;
              ref.read(floatingPreviewUrlProvider.notifier).state = 'http://127.0.0.1:8080';
              ref.read(floatingPreviewVisibleProvider.notifier).state = true;
              ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
              ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
              _runDedicatedCommand(
                workspaceState.currentPath,
                'flutter run -d web-server --web-port 8080 --web-hostname 127.0.0.1',
              );
            }),
            _buildActionButton('Reload (r)', LucideIcons.zap, Colors.yellow,
                () => _sendRawKeyToDedicatedTerminal('r')),
            _buildActionButton('Restart (R)', LucideIcons.rotate_cw, Colors.orangeAccent, () {
              _sendRawKeyToDedicatedTerminal('R');
              Future.delayed(const Duration(milliseconds: 1800), () {
                if (mounted) {
                  ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
                }
              });
            }),
            _buildActionButton(
              isRu ? 'Авто-Reload' : 'Auto-Reload',
              autoHotReload ? LucideIcons.sparkles : LucideIcons.circle_pause,
              autoHotReload ? Colors.greenAccent : Colors.white54,
              () => ref.read(flutterAutoHotReloadProvider.notifier).state = !autoHotReload,
            ),
            _buildActionButton(
              isRu ? 'Браузер' : 'Preview',
              LucideIcons.monitor,
              Colors.lightBlueAccent,
              () {
                ref.read(floatingPreviewVisibleProvider.notifier).state = true;
                ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
                ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
              },
            ),
            _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, () {
              _sendRawKeyToDedicatedTerminal('q');
              ref.read(serverRunningProvider.notifier).state = false;
            }),
          ]);
        }
        break;
      case ProjectType.python:
        title = l10n.pythonProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'python3 main.py || python3 app.py || (py_file=\$(find . -maxdepth 2 -name "*.py" | head -n 1); if [ -n "\$py_file" ]; then python3 "\$py_file"; else echo "No python file found. Please create main.py"; fi)')),
          _buildActionButton('Server', LucideIcons.server, Colors.cyanAccent, () {
            ref.read(serverRunningProvider.notifier).state = true;
            ref.read(floatingPreviewUrlProvider.notifier).state = 'http://127.0.0.1:8080';
            ref.read(floatingPreviewVisibleProvider.notifier).state = true;
            ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
            ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
            _runDedicatedCommand(workspaceState.currentPath,
                'python3 -m flask run --host=0.0.0.0 2>/dev/null || python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 2>/dev/null || python3 -m http.server 8080');
          }),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, () {
            _stopCommand();
            ref.read(serverRunningProvider.notifier).state = false;
          }),
        ]);
        break;
      case ProjectType.nodejs:
        title = l10n.nodejsProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'npm start || node index.js || node server.js || node app.js || (js_file=\$(find . -maxdepth 2 -name "*.js" ! -path "*/node_modules/*" | head -n 1); if [ -n "\$js_file" ]; then node "\$js_file"; else echo "No JS file found. Please create index.js or package.json"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent,
              () => _stopCommand()),
        ]);
        break;
      case ProjectType.dart:
        title = l10n.dartProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'dart run || dart bin/main.dart || dart main.dart || (dart_file=\$(find . -maxdepth 2 -name "*.dart" | head -n 1); if [ -n "\$dart_file" ]; then dart "\$dart_file"; else echo "No Dart file found. Please create bin/main.dart"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent,
              () => _stopCommand()),
        ]);
        break;
      case ProjectType.web:
        title = l10n.webProject;
        actions.addAll([
          _buildActionButton(l10n.startServer, LucideIcons.play, Colors.greenAccent, () {
            ref.read(serverRunningProvider.notifier).state = true;
            ref.read(floatingPreviewUrlProvider.notifier).state = 'http://127.0.0.1:8080';
            ref.read(floatingPreviewVisibleProvider.notifier).state = true;
            ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
            ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
            _runDedicatedCommand(workspaceState.currentPath,
                'python3 -m http.server 8080 || npx http-server -p 8080 || npx serve -p 8080');
          }),
          _buildActionButton('Браузер', LucideIcons.monitor, Colors.lightBlueAccent, () {
            ref.read(floatingPreviewVisibleProvider.notifier).state = true;
            ref.read(floatingPreviewMinimizedProvider.notifier).state = false;
            ref.read(floatingPreviewReloadTokenProvider.notifier).state++;
          }),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, () {
            _stopCommand();
            ref.read(serverRunningProvider.notifier).state = false;
          }),
        ]);
        break;
      case ProjectType.androidKotlin:
        title = 'Android (Kotlin)';
        actions.addAll([
          _buildActionButton('Build Debug (KT)', LucideIcons.bug, Colors.yellow, 
              () => _runDedicatedCommand(workspaceState.currentPath, '$_ktRepairCmd(mkdir -p ~/.gradle 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"', displayCmd: './gradlew assembleDebug')),
          _buildActionButton(Platform.isAndroid ? l10n.installApk : l10n.install, LucideIcons.smartphone, Colors.cyanAccent, 
              () => Platform.isAndroid 
                  ? _installBuiltApk(workspaceState.currentPath) 
                  : _runDedicatedCommand(workspaceState.currentPath, 'chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 installDebug', displayCmd: './gradlew installDebug')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _stopCommand()),
        ]);
        break;
      case ProjectType.androidJava:
        title = 'Android (Java)';
        actions.addAll([
          _buildActionButton('Build Debug (Java)', LucideIcons.bug, Colors.yellow, 
              () => _runDedicatedCommand(workspaceState.currentPath, '(mkdir -p ~/.gradle 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"', displayCmd: './gradlew assembleDebug')),
          _buildActionButton(Platform.isAndroid ? l10n.installApk : l10n.install, LucideIcons.smartphone, Colors.cyanAccent, 
              () => Platform.isAndroid 
                  ? _installBuiltApk(workspaceState.currentPath) 
                  : _runDedicatedCommand(workspaceState.currentPath, 'chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 installDebug', displayCmd: './gradlew installDebug')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _stopCommand()),
        ]);
        break;
      case ProjectType.rust:
        title = 'Rust Project';
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo run')),
          _buildActionButton('Test', LucideIcons.flask_conical, Colors.cyanAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo test')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _stopCommand()),
        ]);
        break;
      default:
        title = l10n.genericProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run || npm start || python3 main.py')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _stopCommand()),
        ]);
    }

    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _resolveAppTerminalTheme(terminalThemeName);

    return Column(
      children: [
        // Unified top bar: Project Type badge + Terminal/Logs segmented toggle + Copy
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.08),
            border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.10),
                  borderRadius: AppBorderRadius.small,
                  border: Border.all(
                    color: AppColors.accentGreen.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: AppColors.accentGreen,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: AppBorderRadius.medium,
                  border: Border.all(color: AppColors.glassBorderLight, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogModeButton(
                      label: 'Terminal',
                      isActive: !_showBeautifulLogs,
                      onTap: () => setState(() => _showBeautifulLogs = false),
                      icon: LucideIcons.terminal,
                    ),
                    _buildLogModeButton(
                      label: 'Logs',
                      isActive: _showBeautifulLogs,
                      onTap: () => setState(() => _showBeautifulLogs = true),
                      icon: LucideIcons.file_text,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: l10n.copy,
                child: InkWell(
                  onTap: () => _copyTerminalOutput(session, l10n),
                  borderRadius: AppBorderRadius.small,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.glassBackgroundLight,
                      borderRadius: AppBorderRadius.small,
                      border: Border.all(color: AppColors.glassBorderLight, width: 0.8),
                    ),
                    child: const Icon(LucideIcons.copy, size: 13, color: AppColors.textWhite70),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Clean action strip
        _buildActionHeader(actions),
        const BuildProgressCard(),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: AppBorderRadius.large,
              border: Border.all(color: AppColors.glassBorderLight),
            ),
            clipBehavior: Clip.antiAlias,
            child: session != null
                ? (_showBeautifulLogs
                    ? BeautifulLogsViewer(session: session)
                    : ConduitTerminalSurface(
                        terminal: session.xtermTerminal,
                        controller: session.xtermViewController,
                        autofocus: !(Platform.isAndroid || Platform.isIOS),
                        autoResize: widget.isActive,
                        palette: resolveConduitPalette(
                          ref.watch(settingsProvider).terminalTheme,
                        ),
                        brightness: Brightness.dark,
                        customTheme: theme,
                        fontFamily: 'jetBrainsMono',
                        fontSize: terminalFontSize,
                        onFontSizeChanged: (newSize) {
                          ref
                              .read(settingsProvider.notifier)
                              .setTerminalFontSize(newSize.clamp(8.0, 26.0));
                        },
                        onTapUp: (details, offset) {
                          final link = QuantumLinkDetector.findLinkInBuffer(
                            session.xtermTerminal.buffer,
                            offset.y,
                            offset.x,
                          );
                          if (link != null) {
                            QuantumLinkDetector.handleLinkTap(
                              context,
                              ref,
                              link,
                            );
                          }
                        },
                      ))
                : Center(child: Text(l10n.startTheProject, style: const TextStyle(color: Colors.white38))),
          ),
        ),
      ],
    );
  }

  Widget _buildActionHeader(List<Widget> actions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: actions,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.32), width: 0.9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13.5, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogModeButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? Colors.cyanAccent.withValues(alpha: 0.2) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: isActive ? Colors.cyanAccent : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                color: isActive ? Colors.white : Colors.white38,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyTerminalOutput(TerminalSession? session, AppLocalizations l10n) async {
    if (session == null) return;
    final buffer = session.xtermTerminal.buffer;
    final lines = <String>[];
    for (var i = 0; i < buffer.lines.length; i++) {
      lines.add(buffer.lines[i].toString());
    }
    final text = lines.join('\n');
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.outputCopied), duration: const Duration(seconds: 1)),
        );
      }
    }
  }
}

// Standalone Sidebar Build Panel
class SidebarBuildPanel extends ConsumerStatefulWidget {
  final bool isActive;
  const SidebarBuildPanel({super.key, this.isActive = true});

  @override
  ConsumerState<SidebarBuildPanel> createState() => _SidebarBuildPanelState();
}

class _SidebarBuildPanelState extends ConsumerState<SidebarBuildPanel> {
  int _buildSubTab = 0;
  String _buildProfile = 'auto'; // 'auto' | 'turbo' | 'safe'

  void _stopCommand() {
    ref.read(dedicatedTerminalProvider.notifier).stopBuildProcess();
    ref.read(systemStatsProvider.notifier).freeBackgroundMemory(force: true);
  }

  String _buildProfileEnvPrefix() {
    switch (_buildProfile) {
      case 'turbo':
        return 'export QUANTUM_BUILD_PROFILE=turbo; ';
      case 'safe':
        return 'export QUANTUM_BUILD_PROFILE=safe GRADLE_WORKERS_OVERRIDE=1 BOX64_DYNAREC=0 MALLOC_CHECK_=0 MALLOC_ARENA_MAX=1; ';
      default:
        return 'export QUANTUM_BUILD_PROFILE=auto; ';
    }
  }

  Future<void> _runBuildDoctor(String? workspacePath) async {
    const cmd =
        'echo "🩺 Запуск Доктора сборки (SDK / AAPT2 / Box64 / Gradle)..." && '
        '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && '
        '(/usr/local/bin/quantum-heal-x64 --doctor 2>/dev/null || true) && '
        'echo "--- Статус инструментов ---" && '
        'echo "AAPT2: \$(/usr/bin/aapt2 version 2>&1 | head -n 1)" && '
        'echo "ccache: \$(command -v ccache >/dev/null 2>&1 && echo "✓ установлен" || echo "✗ не установлен")" && '
        'echo "mold: \$(command -v mold >/dev/null 2>&1 && echo "✓ установлен" || echo "✗ не установлен")" && '
        'echo "Box64: \$(command -v box64 >/dev/null 2>&1 && box64 -v 2>&1 | head -n 1 || echo "нет")" && '
        'echo "✓ Диагностика завершена."';
    await _runDedicatedCommand(workspacePath, cmd, displayCmd: 'Build Doctor (SDK / AAPT2 / Cache)');
  }

  Future<void> _installBuildAccelerators(String? workspacePath) async {
    const cmd =
        'echo "⚡ Установка ускорителей сборки (mold, ccache, Box64, AAPT2)..." && '
        'export DEBIAN_FRONTEND=noninteractive && '
        '(apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || true) && '
        '(apt-get install -y --no-install-recommends ccache mold unzip curl 2>/dev/null || true) && '
        'mkdir -p /root/.ccache 2>/dev/null || true && '
        '(curl -k -fsSL --connect-timeout 8 --max-time 60 "https://github.com/Lesorub361/quantum_ide/releases/download/native-tools-latest/box64-arm64" -o /tmp/box64-new && chmod +x /tmp/box64-new && /tmp/box64-new -v >/dev/null 2>&1 && mv -f /tmp/box64-new /usr/local/bin/box64 && ([ ! -e /usr/bin/box64 ] || cp -f /usr/local/bin/box64 /usr/bin/box64 2>/dev/null || true) && echo "✓ Обновлён Box64 до актуальной сборки" || rm -f /tmp/box64-new) && '
        '(curl -k -fsSL --connect-timeout 8 --max-time 60 "https://github.com/Lesorub361/quantum_ide/releases/download/native-tools-latest/aapt2-arm64" -o /tmp/aapt2-new && chmod +x /tmp/aapt2-new && (/tmp/aapt2-new compile --help 2>&1 | grep -q -- "--source-path") && mv -f /tmp/aapt2-new /usr/bin/aapt2 && cp -f /usr/bin/aapt2 /usr/local/bin/aapt2-arm64 2>/dev/null || true && echo "✓ Обновлён AAPT2 до актуальной сборки" || rm -f /tmp/aapt2-new) && '
        'hash -r 2>/dev/null || true && '
        '(/usr/local/bin/quantum-heal-x64 --doctor 2>/dev/null || true) && '
        'echo "--- Версии ускорителей ---" && '
        'echo "Box64: \$(box64 -v 2>&1 | tail -n 1)" && '
        'echo "AAPT2: \$(/usr/bin/aapt2 version 2>&1 | head -n 1)" && '
        'echo "ccache: \$(ccache --version 2>&1 | head -n 1)" && '
        'echo "mold: \$(mold --version 2>&1 | head -n 1)" && '
        'echo "✓ Ускорители готовы (mold + ccache + AAPT2 + Box64 + QEMU fallback)."';
    await _runDedicatedCommand(workspacePath, cmd, displayCmd: 'Install Build Accelerators (mold + ccache + Box64 + AAPT2)');
  }

  Future<void> _runDedicatedCommand(String? workspacePath, String cmd, {String? displayCmd}) async {
    ref.read(projectSyncProvider.notifier).cancelSync();
    unawaited(ShizukuBridge.instance.boostForBuild());
    unawaited(ref.read(systemStatsProvider.notifier).freeBackgroundMemory(force: false));
    final runtime = ref.read(runtimeServiceProvider);
    final guestPath = workspacePath != null ? PathMapper.mapToGuest(workspacePath, runtime.appDirectory) : null;
    final cdCmd = guestPath != null ? 'mkdir -p "$guestPath" 2>/dev/null; cd "$guestPath"' : '';
    final label = displayCmd ?? (cmd.length > 60 ? '${cmd.substring(0, 57)}...' : cmd);
    final safeLabel = label.replaceAll('"', '\\"');
    const clearScreen = 'printf "\\033[2J\\033[H\\033[3J"';
    final banner = 'printf "\\033[1;36m▶ %s\\033[0m\\n\\033[0;34m──────────────────────────────────────────────────\\033[0m\\n" "$safeLabel"';
    const restoreTty = '; (stty sane 2>/dev/null || true); printf "\\r\\n"';
    final isGradleOnly = cmd.contains('gradlew') && !cmd.contains('flutter');
    final killExtra = isGradleOnly
        ? '(pkill -9 -f flutter_tools 2>/dev/null || true); (pkill -9 -f analysis_server 2>/dev/null || true); '
        : '';
    const killZombiesAndPrepMem =
        '(pkill -9 -f aapt2 2>/dev/null || true); '
        '(pkill -9 -f GradleDaemon 2>/dev/null || true); '
        '(pkill -9 -f KotlinCompileDaemon 2>/dev/null || true); '
        '(mkdir -p ~/.gradle 2>/dev/null || true); '
        '(sed -i "/extra-gen-snapshot-options/d" ~/.gradle/gradle.properties 2>/dev/null || true); ';
    final profilePrefix = _buildProfileEnvPrefix();
    final finalCmd = cdCmd.isNotEmpty
        ? '$clearScreen && $killZombiesAndPrepMem$killExtra$profilePrefix$cdCmd && $banner && ($cmd)$restoreTty'
        : '$clearScreen && $killZombiesAndPrepMem$killExtra$profilePrefix$banner && ($cmd)$restoreTty';
    ref.read(dedicatedTerminalProvider.notifier).sendCommand(DedicatedTerminalType.build, finalCmd, interrupt: true, clear: false);
  }

  Future<void> _installBuiltApk(String? workspacePath) async {
    if (workspacePath == null) return;
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final diagnostics = ref.read(androidBuildDiagnosticsServiceProvider);
    final apkInfo = diagnostics.findDebugApk(workspacePath);
    if (apkInfo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu ? 'APK еще не собран. Сначала нажмите кнопку сборки APK.' : 'APK is not built yet. Click Build APK first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isRu ? 'Установка ${apkInfo.fileName} (${apkInfo.formattedSize})...' : 'Installing ${apkInfo.fileName} (${apkInfo.formattedSize})...'),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }

    final installer = ref.read(androidAppInstallerServiceProvider);
    final res = await installer.installApk(apkInfo.path, launchAfterInstall: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.success
              ? (isRu ? 'Установка запущена (${res.method ?? "PackageInstaller"})' : 'Installation started (${res.method ?? "PackageInstaller"})')
              : (isRu ? 'Ошибка установки: ${res.message}' : 'Installation error: ${res.message}')),
          backgroundColor: res.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _buildWebApkInDedicatedTerminal(String? workspacePath, String projectName) async {
    if (workspacePath == null || workspacePath.isEmpty) return;
    await ref.read(projectServiceProvider.notifier).prepareWebApkWrapper(workspacePath, projectName);
    final cmd = [
      'if [ -f package.json ] && grep -q "\\"build\\"" package.json; then npm run build || true; fi',
      'mkdir -p .quantum_android_apk/app/src/main/assets/www',
      'if [ -d dist ]; then cp -r dist/* .quantum_android_apk/app/src/main/assets/www/ 2>/dev/null || true; '
          'elif [ -d build ]; then cp -r build/* .quantum_android_apk/app/src/main/assets/www/ 2>/dev/null || true; '
          'else find . -maxdepth 2 \\( -name "*.html" -o -name "*.css" -o -name "*.js" -o -name "*.json" -o -name "*.png" -o -name "*.svg" -o -name "*.jpg" \\) ! -path "./.quantum_android_apk/*" ! -path "./node_modules/*" -exec cp --parents {} .quantum_android_apk/app/src/main/assets/www/ \\; 2>/dev/null || true; fi',
      'cd .quantum_android_apk && chmod +x ./gradlew 2>/dev/null || true',
      'bash ./gradlew --no-daemon --max-workers=2 assembleDebug',
      'cp app/build/outputs/apk/debug/app-debug.apk ../app-debug.apk && echo "✓ Web APK успешно собран: ./app-debug.apk"',
    ].join(' && ');
    _runDedicatedCommand(workspacePath, cmd);
  }

  void _openBuildDialog(String? workspacePath) {
    final projectName = workspacePath != null ? p.basename(workspacePath) : null;
    AdaptiveDialogHelper.showAdaptiveSheet(
      context: context,
      desktopMaxWidth: 560,
      desktopMaxHeight: 680,
      builder: (ctx) => BuildTargetDialog(
        initialProjectName: projectName,
        onStartBuild: (command, displayCmd, target) {
          _runDedicatedCommand(workspacePath, command, displayCmd: displayCmd);
        },
      ),
    );
  }

  ProjectType _detectProjectType(String? path, ProjectType registeredType) {
    if (registeredType != ProjectType.other) return registeredType;
    if (path == null || path.isEmpty) return ProjectType.other;
    return ref.watch(_cachedProjectTypeProvider(path)).valueOrNull ??
        ProjectType.other;
  }

  @override
  Widget build(BuildContext context) {
    final dedicatedState = ref.watch(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[DedicatedTerminalType.build];
    final workspaceState = ref.watch(workspaceProvider);
    final allProjects = ref.watch(projectServiceProvider);
    final l10n = AppLocalizations.of(context)!;

    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _resolveAppTerminalTheme(terminalThemeName);

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

    // Build actions depending on project type
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    List<Widget> buildActions = [];
    switch (projectType) {
      case ProjectType.flutter:
        buildActions = [
          _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true) && flutter build apk --debug --no-pub --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk',
                  displayCmd: 'flutter build apk --debug')),
          _buildActionButton('APK (D8 · без R8)', LucideIcons.zap, const Color(0xFF10B981),
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true) && QUANTUM_DISABLE_R8=1 flutter build apk --release --no-pub --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation && (cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./app-release.apk 2>/dev/null || true)',
                  displayCmd: 'flutter build apk --release (D8 · без R8)')),
          _buildActionButton('${l10n.buildAPK} (R8)', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true) && flutter build apk --release --no-pub --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation && (cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./app-release.apk 2>/dev/null || true)',
                  displayCmd: 'flutter build apk --release (R8)')),
          _buildActionButton('AAB с D8 (без R8)', LucideIcons.zap, Colors.tealAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true) && QUANTUM_DISABLE_R8=1 flutter build appbundle --release --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation && (cp -f build/app/outputs/bundle/release/app-release.aab ./app-release.aab 2>/dev/null || true) && echo "✓ Google Play Bundle (AAB · D8 без R8): ./app-release.aab"',
                  displayCmd: 'flutter build appbundle --release (D8 · без R8)')),
          _buildActionButton('AAB с R8 (Google Play)', LucideIcons.rocket, Colors.purpleAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true) && flutter build appbundle --release --no-pub --no-tree-shake-icons --android-skip-build-dependency-validation && (cp -f build/app/outputs/bundle/release/app-release.aab ./app-release.aab 2>/dev/null || true) && echo "✓ Google Play Bundle (AAB · R8): ./app-release.aab"',
                  displayCmd: 'flutter build appbundle --release (R8)')),
          _buildActionButton('Split APKs', LucideIcons.boxes, Colors.amberAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && ([ ! -s .dart_tool/package_config.json ] && flutter pub get || true) && flutter build apk --release --no-pub --split-per-abi --no-tree-shake-icons --android-skip-build-dependency-validation && (for apk in build/app/outputs/flutter-apk/*.apk; do cp -f "\$apk" ./ 2>/dev/null; done) && echo "✓ Split APKs (v7/v8/x64) ready in project root"',
                  displayCmd: 'flutter build apk --release --split-per-abi')),
          _buildActionButton('Web-сервер', LucideIcons.globe, const Color(0xFF38BDF8),
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0',
                  displayCmd: 'Web-сервер (localhost:8080)')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get',
                  displayCmd: 'flutter pub get')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean', displayCmd: 'flutter clean')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent,
              () => _stopCommand()),
          _buildActionButton('Deep Clean', LucideIcons.eraser, Colors.redAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'rm -rf .dart_tool/flutter_build build/app/intermediates build/app/outputs ~/.gradle/caches/build-cache-* 2>/dev/null ; flutter clean && flutter pub get',
                  displayCmd: 'Deep Clean (Reset Caches & Flutter)')),
        ];
        break;

      case ProjectType.androidKotlin:
        buildActions = [
          _buildActionButton('Debug APK (KT)', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; gradlew assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"',
                  displayCmd: './gradlew assembleDebug')),
          _buildActionButton('Release APK (KT)', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; gradlew assembleRelease && (cp app/build/outputs/apk/release/app-release-unsigned.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/app-release.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/*.apk ./app-release.apk 2>/dev/null || true) && echo "✓ Release APK: ./app-release.apk"',
                  displayCmd: './gradlew assembleRelease')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Clean (KT)', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; gradlew clean && rm -f ./app-release.apk ./app-debug.apk',
                  displayCmd: './gradlew clean')),
          _buildActionButton('Sync (KT)', LucideIcons.refresh_cw, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; gradlew dependencies',
                  displayCmd: './gradlew dependencies')),
        ];
        break;

      case ProjectType.androidJava:
        buildActions = [
          _buildActionButton('Debug APK (Java)', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; gradlew assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"',
                  displayCmd: './gradlew assembleDebug')),
          _buildActionButton('Release APK (Java)', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; gradlew assembleRelease && (cp app/build/outputs/apk/release/app-release-unsigned.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/app-release.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/*.apk ./app-release.apk 2>/dev/null || true) && echo "✓ Release APK: ./app-release.apk"',
                  displayCmd: './gradlew assembleRelease')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Clean (Java)', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; gradlew clean && rm -f ./app-release.apk ./app-debug.apk',
                  displayCmd: './gradlew clean')),
          _buildActionButton('Sync (Java)', LucideIcons.refresh_cw, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; gradlew dependencies',
                  displayCmd: './gradlew dependencies')),
        ];
        break;

      case ProjectType.web:
        buildActions = [
          _buildActionButton(isRu ? 'Собрать APK (Web→APK)' : 'Build APK (Web→APK)', LucideIcons.package, Colors.orange,
              () => _buildWebApkInDedicatedTerminal(workspaceState.currentPath, currentProject.name)),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
        ];
        break;

      case ProjectType.rust:
        buildActions = [
          _buildActionButton('Cargo Build', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo build')),
          _buildActionButton('Release', LucideIcons.box, Colors.greenAccent,
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo build --release')),
          _buildActionButton('Check', LucideIcons.circle_check, Colors.cyanAccent,
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo check')),
          _buildActionButton('Test', LucideIcons.flask_conical, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo test')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'cargo clean')),
        ];
        break;

      case ProjectType.dart:
        buildActions = [
          _buildActionButton('Compile Exe', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath, 'dart compile exe bin/main.dart')),
          _buildActionButton('Analyze', LucideIcons.circle_check, Colors.cyanAccent,
              () => _runDedicatedCommand(workspaceState.currentPath, 'dart analyze')),
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, 'dart pub get')),
        ];
        break;

      case ProjectType.python:
        buildActions = [
          _buildActionButton('Install deps', LucideIcons.download, Colors.purple,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'pip3 install -r requirements.txt 2>/dev/null || pip install -r requirements.txt 2>/dev/null || echo "No requirements.txt found"')),
          _buildActionButton('Build APK (Flet)', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'flet build apk 2>/dev/null || buildozer android debug 2>/dev/null || echo "${isRu ? "Установите flet (pip3 install flet) для сборки Python-приложения в APK" : "Install flet (pip3 install flet) to build Python app to APK"}"')),
          _buildActionButton('Freeze', LucideIcons.file_text, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'pip3 freeze > requirements.txt && echo "requirements.txt updated"')),
        ];
        break;

      case ProjectType.nodejs:
        buildActions = [
          _buildActionButton(isRu ? 'Собрать APK (Web→APK)' : 'Build APK (Web→APK)', LucideIcons.package, Colors.orange,
              () => _buildWebApkInDedicatedTerminal(workspaceState.currentPath, currentProject.name)),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('npm install', LucideIcons.download, Colors.cyanAccent,
              () => _runDedicatedCommand(workspaceState.currentPath, 'npm install')),
          _buildActionButton('npm build', LucideIcons.hammer, Colors.amber,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'npm run build 2>/dev/null || npx tsc 2>/dev/null || echo "No build script found"')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'rm -rf node_modules && echo "node_modules removed"')),
        ];
        break;

      default:
        buildActions = [
          _buildActionButton('⚡ Выбор сборки...', LucideIcons.sliders_horizontal, const Color(0xFF10B981),
              () => _openBuildDialog(workspaceState.currentPath)),
          _buildActionButton('APK 64-бит (D8 · без R8)', LucideIcons.zap, const Color(0xFF10B981),
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.arm64D8),
                  displayCmd: 'flutter build apk --release (ARM64 · D8 без R8)')),
          _buildActionButton('APK 64-бит (R8)', LucideIcons.package, Colors.amber,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.arm64),
                  displayCmd: 'flutter build apk --release (ARM64 · R8)')),
          _buildActionButton('APK 32-бит (arm)', LucideIcons.smartphone, Colors.blueAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.arm32),
                  displayCmd: 'flutter build apk --release (ARMv7 32-бит)')),
          _buildActionButton('APK x86_64', LucideIcons.monitor, Colors.cyanAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.x86_64),
                  displayCmd: 'flutter build apk --release (x86_64)')),
          _buildActionButton('AAB с D8 (без R8)', LucideIcons.zap, Colors.tealAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.aabD8),
                  displayCmd: 'flutter build appbundle --release (D8 · без R8)')),
          _buildActionButton('AAB с R8 (Google Play)', LucideIcons.rocket, Colors.purpleAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.aab),
                  displayCmd: 'flutter build appbundle --release (R8)')),
          _buildActionButton('Split APKs', LucideIcons.boxes, Colors.orangeAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.split),
                  displayCmd: 'flutter build apk --release --split-per-abi')),
          _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  BuildResourceOptimizer.generateBuildCommand(target: BuildTargetType.debug),
                  displayCmd: 'flutter build apk --debug')),
          _buildActionButton('Web-сервер', LucideIcons.globe, const Color(0xFF38BDF8),
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0',
                  displayCmd: 'Web-сервер (localhost:8080)')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get',
                  displayCmd: 'flutter pub get')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean', displayCmd: 'flutter clean')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent,
              () => _stopCommand()),
        ];
    }

    buildActions.addAll([
      _buildActionButton(
        isRu ? 'Доктор SDK' : 'Build Doctor',
        LucideIcons.shield_check,
        Colors.tealAccent,
        () => _runBuildDoctor(workspaceState.currentPath),
      ),
      _buildActionButton(
        isRu ? 'Ускорители' : 'Accelerators',
        LucideIcons.zap,
        Colors.cyanAccent,
        () => _installBuildAccelerators(workspaceState.currentPath),
      ),
    ]);

    return Column(
      children: [
        // Unified top toolbar: [Консоль | Подпись APK] + [Profile] + [Pipeline | Terminal] + [Copy]
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.08),
            border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: AppBorderRadius.medium,
                  border: Border.all(color: AppColors.glassBorderLight, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSubTabButton(0, l10n.console, LucideIcons.terminal),
                    _buildSubTabButton(1, l10n.signApk, LucideIcons.pen_tool),
                  ],
                ),
              ),
              const Spacer(),
              if (_buildSubTab == 0) ...[
                _buildProfileDropdown(isRu),
                const SizedBox(width: 6),
                Tooltip(
                  message: l10n.copy,
                  child: InkWell(
                    onTap: () => _copyTerminalOutput(session, l10n),
                    borderRadius: AppBorderRadius.small,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.glassBackgroundLight,
                        borderRadius: AppBorderRadius.small,
                        border: Border.all(color: AppColors.glassBorderLight, width: 0.8),
                      ),
                      child: const Icon(LucideIcons.copy, size: 13, color: AppColors.textWhite70),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const BuildProgressCard(),
        Expanded(
          child: _buildSubTab == 0
              ? Column(
                  children: [
                    _buildActionHeader([
                      _buildActionButton(
                        isRu ? 'Выбрать сборку ▾' : 'Build Commands ▾',
                        LucideIcons.layers,
                        AppColors.accentOrange,
                        () => _showBuildCommandsSheet(context, buildActions, isRu),
                      ),
                      _buildActionButton(
                        l10n.installApk,
                        LucideIcons.smartphone,
                        AppColors.accentGreen,
                        () => _installBuiltApk(workspaceState.currentPath),
                      ),
                      _buildActionButton(
                        l10n.stop,
                        LucideIcons.square,
                        Colors.redAccent,
                        _stopCommand,
                      ),
                    ]),
                    Expanded(
                      child: session != null
                          ? Container(
                              margin: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                              decoration: BoxDecoration(
                                color: theme.background,
                                borderRadius: AppBorderRadius.large,
                                border: Border.all(color: AppColors.glassBorderLight),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ConduitTerminalSurface(
                                terminal: session.xtermTerminal,
                                controller: session.xtermViewController,
                                autofocus: !(Platform.isAndroid || Platform.isIOS),
                                autoResize: widget.isActive,
                                palette: resolveConduitPalette(
                                  ref.watch(settingsProvider).terminalTheme,
                                ),
                                brightness: Brightness.dark,
                                customTheme: theme,
                                fontFamily: 'jetBrainsMono',
                                fontSize: terminalFontSize,
                                onFontSizeChanged: (newSize) {
                                  ref
                                      .read(settingsProvider.notifier)
                                      .setTerminalFontSize(
                                        newSize.clamp(8.0, 26.0),
                                      );
                                },
                                onTapUp: (details, offset) {
                                  final link =
                                      QuantumLinkDetector.findLinkInBuffer(
                                        session.xtermTerminal.buffer,
                                        offset.y,
                                        offset.x,
                                      );
                                  if (link != null) {
                                    QuantumLinkDetector.handleLinkTap(
                                      context,
                                      ref,
                                      link,
                                    );
                                  }
                                },
                              ),
                            )
                          : Center(child: Text(l10n.buildLogs, style: const TextStyle(color: Colors.white38))),
                    ),
                  ],
                )
              : const ApkSignerWidget(),
        ),
      ],
    );
  }

  void _showBuildCommandsSheet(BuildContext context, List<Widget> actions, bool isRu) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.hammer, size: 16, color: AppColors.accentOrange),
                  const SizedBox(width: 8),
                  Text(
                    isRu ? 'Команды сборки' : 'Build Commands',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 16, color: Colors.white54),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 8,
                children: actions.map((w) {
                  return Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerUp: (_) => Future.microtask(() {
                      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    }),
                    child: w,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDropdown(bool isRu) {
    final (label, icon, accent) = switch (_buildProfile) {
      'turbo' => (isRu ? 'Турбо' : 'Turbo', LucideIcons.zap, AppColors.accentOrange),
      'safe' => (isRu ? 'Безоп.' : 'Safe', LucideIcons.shield, AppColors.accentGreen),
      _ => (isRu ? 'Авто' : 'Auto', LucideIcons.cpu, AppColors.accentBlue),
    };
    return PopupMenuButton<String>(
      tooltip: isRu ? 'Профиль сборки' : 'Build profile',
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      onSelected: (val) => setState(() => _buildProfile = val),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'auto',
          child: Row(
            children: [
              const Icon(LucideIcons.cpu, size: 14, color: AppColors.accentBlue),
              const SizedBox(width: 8),
              Text(isRu ? 'Авто' : 'Auto', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'turbo',
          child: Row(
            children: [
              const Icon(LucideIcons.zap, size: 14, color: AppColors.accentOrange),
              const SizedBox(width: 8),
              Text(isRu ? 'Турбо (ccache+mold)' : 'Turbo', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'safe',
          child: Row(
            children: [
              const Icon(LucideIcons.shield, size: 14, color: AppColors.accentGreen),
              const SizedBox(width: 8),
              Text(isRu ? 'Безопасный (Anti-Crash)' : 'Safe', style: GoogleFonts.inter(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: AppBorderRadius.medium,
          border: Border.all(color: accent.withValues(alpha: 0.32), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(LucideIcons.chevron_down, size: 11, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabButton(int index, String label, IconData icon) {
    final isActive = _buildSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _buildSubTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentOrange.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: AppBorderRadius.small,
          border: Border.all(
            color: isActive ? AppColors.accentOrange.withValues(alpha: 0.32) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? AppColors.accentOrange : AppColors.textWhite38),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: isActive ? Colors.white : AppColors.textWhite54,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionHeader(List<Widget> actions) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: actions,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.32), width: 0.9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13.5, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyTerminalOutput(TerminalSession? session, AppLocalizations l10n) async {
    if (session == null) return;
    final buffer = session.xtermTerminal.buffer;
    final lines = <String>[];
    for (var i = 0; i < buffer.lines.length; i++) {
      lines.add(buffer.lines[i].toString());
    }
    final text = lines.join('\n');
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.outputCopied), duration: const Duration(seconds: 1)),
        );
      }
    }
  }
}

// Beautiful Log Viewer Widget
class BeautifulLogsViewer extends StatefulWidget {
  final TerminalSession session;
  const BeautifulLogsViewer({super.key, required this.session});

  @override
  State<BeautifulLogsViewer> createState() => _BeautifulLogsViewerState();
}

class _BeautifulLogsViewerState extends State<BeautifulLogsViewer> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterType = 'all'; // 'all', 'error', 'warning'
  Timer? _throttleTimer;
  bool _pendingRefresh = false;

  bool _cacheDirty = true;
  List<_LogItem> _cachedParsedLines = const [];
  int _cachedErrorCount = 0;
  int _cachedWarningCount = 0;
  List<AndroidBuildIssue> _cachedIssues = const [];

  @override
  void initState() {
    super.initState();
    widget.session.xtermTerminal.addListener(_onTerminalChanged);
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(BeautifulLogsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.xtermTerminal.removeListener(_onTerminalChanged);
      widget.session.xtermTerminal.addListener(_onTerminalChanged);
      _cacheDirty = true;
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    widget.session.xtermTerminal.removeListener(_onTerminalChanged);
    _throttleTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTerminalChanged() {
    if (!mounted) return;
    _cacheDirty = true;
    if (_throttleTimer?.isActive ?? false) {
      _pendingRefresh = true;
      return;
    }
    setState(() {});
    _scrollToBottom();
    _throttleTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_pendingRefresh) {
        _pendingRefresh = false;
        _cacheDirty = true;
        setState(() {});
        _scrollToBottom();
      }
    });
  }

  void _rebuildLogCacheIfNeeded() {
    if (!_cacheDirty) return;
    _cacheDirty = false;
    final buffer = widget.session.xtermTerminal.buffer;
    final lines = <String>[];
    for (var i = 0; i < buffer.lines.length; i++) {
      final lineStr = buffer.lines[i].toString().trimRight();
      if (lineStr.isNotEmpty) {
        lines.add(lineStr);
      }
    }

    final parsedLines = <_LogItem>[];
    int errorCount = 0;
    int warningCount = 0;
    final queryLower = _searchQuery.toLowerCase();

    for (final text in lines) {
      final type = _detectLogType(text);
      if (type == LogType.error) errorCount++;
      if (type == LogType.warning) warningCount++;

      if (queryLower.isNotEmpty && !text.toLowerCase().contains(queryLower)) {
        continue;
      }

      if (_filterType == 'error' && type != LogType.error) continue;
      if (_filterType == 'warning' && type != LogType.warning) continue;

      parsedLines.add(_LogItem(text, type));
    }

    _cachedParsedLines = parsedLines;
    _cachedErrorCount = errorCount;
    _cachedWarningCount = warningCount;
    _cachedIssues = errorCount > 0
        ? AndroidBuildDiagnosticsService().parseBuildIssues(lines.join('\n'), '')
        : const [];
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _rebuildLogCacheIfNeeded();
    final parsedLines = _cachedParsedLines;
    final errorCount = _cachedErrorCount;
    final warningCount = _cachedWarningCount;
    final issues = _cachedIssues;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'Search logs...',
                      hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                      border: InputBorder.none,
                      prefixIcon: const Icon(LucideIcons.search, size: 12, color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _cacheDirty = true;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildFilterBadge('All', 'all', parsedLines.length, Colors.blueAccent),
              const SizedBox(width: 4),
              _buildFilterBadge('Errors', 'error', errorCount, Colors.redAccent),
              const SizedBox(width: 4),
              _buildFilterBadge('Warnings', 'warning', warningCount, Colors.amberAccent),
            ],
          ),
        ),
        if (errorCount > 0 && issues.isNotEmpty)
          Builder(builder: (context) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.circle_alert, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Text(
                        'Диагностика ошибок (${issues.length})',
                        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final issue in issues.take(2)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        '• ${issue.filePath != null ? "${issue.filePath}${issue.line != null ? ":${issue.line}" : ""} — " : ""}${issue.detail}',
                        style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (issue.suggestion != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10.0, top: 1.0),
                        child: Text(
                          '💡 Совет: ${issue.suggestion}',
                          style: GoogleFonts.inter(color: Colors.amberAccent, fontSize: 9.5),
                        ),
                      ),
                  ],
                ],
              ),
            );
          }),
        Expanded(
          child: parsedLines.isEmpty
              ? Center(
                  child: Text(
                    'Logs are empty or do not match the filter',
                    style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: parsedLines.length,
                  itemBuilder: (context, index) {
                    final item = parsedLines[index];
                    return _buildLogLineTile(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBadge(String label, String type, int count, Color activeColor) {
    final isSelected = _filterType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _filterType = type;
          _cacheDirty = true;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : Colors.white38,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.jetBrainsMono(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogLineTile(_LogItem item) {
    Color textColor;
    IconData icon;
    Color iconColor;

    switch (item.type) {
      case LogType.error:
        textColor = Colors.redAccent.shade100;
        icon = LucideIcons.circle_alert;
        iconColor = Colors.redAccent;
        break;
      case LogType.warning:
        textColor = Colors.amberAccent.shade100;
        icon = LucideIcons.triangle_alert;
        iconColor = Colors.amberAccent;
        break;
      case LogType.success:
        textColor = Colors.greenAccent.shade100;
        icon = LucideIcons.circle_check;
        iconColor = Colors.greenAccent;
        break;
      case LogType.info:
        textColor = Colors.white.withValues(alpha: 0.85);
        icon = LucideIcons.info;
        iconColor = Colors.white38;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3.0, right: 6.0),
            child: Icon(icon, size: 11, color: iconColor),
          ),
          Expanded(
            child: SelectableText.rich(
              AnsiTextParser.parse(
                item.text,
                baseStyle: GoogleFonts.jetBrainsMono(
                  color: textColor,
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LogType _detectLogType(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('exit code') ||
        lower.contains('❌') ||
        lower.contains('err:') ||
        lower.contains('fatal') ||
        lower.contains('exception')) {
      return LogType.error;
    }
    if (lower.contains('warning') || lower.contains('warn') || lower.contains('⚠️') || lower.contains('warn:')) {
      return LogType.warning;
    }
    if (lower.contains('success') || lower.contains('✓') || lower.contains('successfully') || lower.contains('completed')) {
      return LogType.success;
    }
    return LogType.info;
  }
}

class _LogItem {
  final String text;
  final LogType type;
  _LogItem(this.text, this.type);
}

enum LogType { info, warning, error, success }
