import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/apk_signer_widget.dart';
import 'package:quantum_ide/core/services/android_app_installer_service.dart';
import 'package:quantum_ide/core/services/android_build_diagnostics_service.dart';
import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/project_sync_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

// Standalone Sidebar Run Panel
const String _ktRepairCmd =
    '(if [ -f app/build.gradle.kts ] && grep -q "kotlinOptions" app/build.gradle.kts 2>/dev/null; then python3 -c "import re; p=\'app/build.gradle.kts\'; c=open(p).read(); c=re.sub(r\'[ \\t]*kotlinOptions\\s*[{][^}]*[}]\', \'\\n\', c); c+=\'\\ntasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {\\n    compilerOptions {\\n        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)\\n    }\\n}\\n\' if \'compilerOptions\' not in c else \'\'; open(p,\'w\').write(c)" 2>/dev/null || true; fi) && ';

class SidebarRunPanel extends ConsumerStatefulWidget {
  const SidebarRunPanel({super.key});

  @override
  ConsumerState<SidebarRunPanel> createState() => _SidebarRunPanelState();
}

class _SidebarRunPanelState extends ConsumerState<SidebarRunPanel> {
  bool _showBeautifulLogs = false;

  ProjectType _detectProjectType(String? path, ProjectType registeredType) {
    if (registeredType != ProjectType.other) return registeredType;
    if (path == null) return ProjectType.other;
    final dir = Directory(path);
    if (!dir.existsSync()) return ProjectType.other;
    try {
      final files = dir.listSync();
      bool hasPubspec = false;
      bool hasPackageJson = false;
      bool hasPyFile = false;
      bool hasHtmlFile = false;
      bool hasGradle = false;
      bool hasCargo = false;
      for (final file in files) {
        final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
        if (name == 'pubspec.yaml') hasPubspec = true;
        if (name == 'package.json') hasPackageJson = true;
        if (name.endsWith('.py')) hasPyFile = true;
        if (name == 'index.html' || name.endsWith('.html')) hasHtmlFile = true;
        if (name == 'build.gradle' || name == 'build.gradle.kts' ||
            name == 'settings.gradle' || name == 'settings.gradle.kts') {
          hasGradle = true;
        }
        if (name == 'cargo.toml') hasCargo = true;
      }
      if (hasPubspec) {
        try {
          final pubspecContent = File('$path${Platform.pathSeparator}pubspec.yaml').readAsStringSync();
          if (pubspecContent.contains('flutter:')) return ProjectType.flutter;
          return ProjectType.dart;
        } catch (_) {
          return ProjectType.flutter;
        }
      }
      if (hasGradle) {
        final mainDir = Directory(p.join(path, 'app', 'src', 'main'));
        if (mainDir.existsSync()) {
          try {
            final entities = mainDir.listSync(recursive: true);
            if (entities.any((e) => e.path.endsWith('.kt'))) return ProjectType.androidKotlin;
            if (entities.any((e) => e.path.endsWith('.java'))) return ProjectType.androidJava;
          } catch (_) {}
        }
        if (File(p.join(path, 'build.gradle.kts')).existsSync() ||
            File(p.join(path, 'app', 'build.gradle.kts')).existsSync()) {
          return ProjectType.androidKotlin;
        }
        return ProjectType.androidKotlin;
      }
      if (hasCargo) return ProjectType.rust;
      if (hasPackageJson) return ProjectType.nodejs;
      if (hasPyFile) return ProjectType.python;
      if (hasHtmlFile) return ProjectType.web;
    } catch (_) {}
    return ProjectType.other;
  }

  void _runDedicatedCommand(String? workspacePath, String cmd, {String? displayCmd}) {
    ref.read(projectSyncProvider.notifier).cancelSync();
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
        if (Platform.isAndroid) {
          actions.addAll([
            _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d web-server --web-port 8080')),
            _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.cyanAccent, 
                () => _installBuiltApk(workspaceState.currentPath)),
            _buildActionButton('Hot Reload', LucideIcons.zap, Colors.yellow, 
                () => _sendRawKeyToDedicatedTerminal('r')),
            _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
                () => _sendRawKeyToDedicatedTerminal('q')),
          ]);
        } else {
          actions.addAll([
            _buildActionButton(l10n.runPC, LucideIcons.laptop, Colors.cyanAccent, 
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d linux')),
            _buildActionButton(l10n.runMob, LucideIcons.smartphone, Colors.greenAccent, 
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d android')),
            _buildActionButton('Hot Reload', LucideIcons.zap, Colors.yellow, 
                () => _sendRawKeyToDedicatedTerminal('r')),
            _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
                () => _sendRawKeyToDedicatedTerminal('q')),
          ]);
        }
        break;
      case ProjectType.python:
        title = l10n.pythonProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'python3 main.py || python3 app.py || (py_file=\$(find . -maxdepth 2 -name "*.py" | head -n 1); if [ -n "\$py_file" ]; then python3 "\$py_file"; else echo "No python file found. Please create main.py"; fi)')),
          _buildActionButton('Server', LucideIcons.server, Colors.cyanAccent,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'python3 -m flask run --host=0.0.0.0 2>/dev/null || python3 -m uvicorn main:app --host 0.0.0.0 --port 8080 2>/dev/null || python3 -m http.server 8080')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.nodejs:
        title = l10n.nodejsProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'npm start || node index.js || node server.js || node app.js || (js_file=\$(find . -maxdepth 2 -name "*.js" ! -path "*/node_modules/*" | head -n 1); if [ -n "\$js_file" ]; then node "\$js_file"; else echo "No JS file found. Please create index.js or package.json"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.dart:
        title = l10n.dartProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'dart run || dart bin/main.dart || dart main.dart || (dart_file=\$(find . -maxdepth 2 -name "*.dart" | head -n 1); if [ -n "\$dart_file" ]; then dart "\$dart_file"; else echo "No Dart file found. Please create bin/main.dart"; fi)')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.web:
        title = l10n.webProject;
        actions.addAll([
          _buildActionButton(l10n.startServer, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'python3 -m http.server 8080 || npx http-server -p 8080 || npx serve -p 8080')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
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
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
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
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
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
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      default:
        title = l10n.genericProject;
        actions.addAll([
          _buildActionButton(l10n.run, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run || npm start || python3 main.py')),
          _buildActionButton(l10n.stop, LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
    }

    actions.add(_buildActionButton(l10n.copy, LucideIcons.copy, Colors.white60, () => _copyTerminalOutput(session, l10n)));

    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _getTerminalTheme(terminalThemeName);

    return Column(
      children: [
        _buildActionHeader(title, actions),
        // Toggle Console vs Beautiful Logs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          color: Colors.black.withValues(alpha: 0.05),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildLogModeButton(
                label: 'Logs',
                isActive: _showBeautifulLogs,
                onTap: () => setState(() => _showBeautifulLogs = true),
                icon: LucideIcons.file_text,
              ),
              const SizedBox(width: 8),
              _buildLogModeButton(
                label: 'Terminal',
                isActive: !_showBeautifulLogs,
                onTap: () => setState(() => _showBeautifulLogs = false),
                icon: LucideIcons.terminal,
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            clipBehavior: Clip.antiAlias,
            child: session != null
                ? (_showBeautifulLogs
                    ? BeautifulLogsViewer(session: session)
                    : xt.TerminalView(
                        session.xtermTerminal,
                        controller: session.xtermViewController,
                        autofocus: true,
                        theme: theme,
                        backgroundOpacity: 0,
                        textStyle: xt.TerminalStyle(
                          fontSize: terminalFontSize * 0.9,
                          fontFamily: 'jetBrainsMono',
                          fontFamilyFallback: const [
                            'SymbolsNerdFont',
                            'Symbols Nerd Font',
                            'cascadia',
                            'dejaVuSansMono',
                            'firaCode',
                            'Noto Sans Mono',
                            'DejaVu Sans Mono',
                            'monospace',
                          ],
                        ),
                        keyboardType: TextInputType.visiblePassword,
                        deleteDetection: true,
                      ))
                : Center(child: Text(l10n.startTheProject, style: const TextStyle(color: Colors.white38))),
          ),
        ),
      ],
    );
  }

  Widget _buildActionHeader(String title, List<Widget> actions) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.greenAccent,
                fontSize: 8,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 6),
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
      padding: const EdgeInsets.only(left: 3),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: color.withValues(alpha: 0.2), width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: color.withValues(alpha: 0.9)),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 9,
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
  const SidebarBuildPanel({super.key});

  @override
  ConsumerState<SidebarBuildPanel> createState() => _SidebarBuildPanelState();
}

class _SidebarBuildPanelState extends ConsumerState<SidebarBuildPanel> {
  int _buildSubTab = 0;
  bool _showBeautifulLogs = false;

  void _runDedicatedCommand(String? workspacePath, String cmd, {String? displayCmd}) {
    ref.read(projectSyncProvider.notifier).cancelSync();
    final runtime = ref.read(runtimeServiceProvider);
    final guestPath = workspacePath != null ? PathMapper.mapToGuest(workspacePath, runtime.appDirectory) : null;
    final cdCmd = guestPath != null ? 'mkdir -p "$guestPath" 2>/dev/null; cd "$guestPath"' : '';
    final label = displayCmd ?? (cmd.length > 60 ? '${cmd.substring(0, 57)}...' : cmd);
    final safeLabel = label.replaceAll('"', '\\"');
    const clearScreen = 'printf "\\033[2J\\033[H\\033[3J"';
    final banner = 'printf "\\033[1;36m▶ %s\\033[0m\\n\\033[0;34m──────────────────────────────────────────────────\\033[0m\\n" "$safeLabel"';
    final finalCmd = cdCmd.isNotEmpty ? '$clearScreen && $cdCmd && $banner && $cmd' : '$clearScreen && $banner && $cmd';
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

  ProjectType _detectProjectType(String? path, ProjectType registeredType) {
    if (registeredType != ProjectType.other) return registeredType;
    if (path == null) return ProjectType.other;
    final dir = Directory(path);
    if (!dir.existsSync()) return ProjectType.other;
    try {
      final files = dir.listSync();
      bool hasPubspec = false;
      bool hasPackageJson = false;
      bool hasPyFile = false;
      bool hasHtmlFile = false;
      bool hasGradle = false;
      bool hasCargo = false;
      for (final file in files) {
        final name = file.path.split(Platform.pathSeparator).last.toLowerCase();
        if (name == 'pubspec.yaml') hasPubspec = true;
        if (name == 'package.json') hasPackageJson = true;
        if (name.endsWith('.py')) hasPyFile = true;
        if (name == 'index.html' || name.endsWith('.html')) hasHtmlFile = true;
        if (name == 'build.gradle' || name == 'build.gradle.kts' ||
            name == 'settings.gradle' || name == 'settings.gradle.kts') {
          hasGradle = true;
        }
        if (name == 'cargo.toml') hasCargo = true;
      }
      if (hasPubspec) {
        try {
          final pubspecContent = File('$path${Platform.pathSeparator}pubspec.yaml').readAsStringSync();
          if (pubspecContent.contains('flutter:')) return ProjectType.flutter;
          return ProjectType.dart;
        } catch (_) {
          return ProjectType.flutter;
        }
      }
      if (hasGradle) {
        final mainDir = Directory(p.join(path, 'app', 'src', 'main'));
        if (mainDir.existsSync()) {
          try {
            final entities = mainDir.listSync(recursive: true);
            if (entities.any((e) => e.path.endsWith('.kt'))) return ProjectType.androidKotlin;
            if (entities.any((e) => e.path.endsWith('.java'))) return ProjectType.androidJava;
          } catch (_) {}
        }
        if (File(p.join(path, 'build.gradle.kts')).existsSync() ||
            File(p.join(path, 'app', 'build.gradle.kts')).existsSync()) {
          return ProjectType.androidKotlin;
        }
        return ProjectType.androidKotlin;
      }
      if (hasCargo) return ProjectType.rust;
      if (hasPackageJson) return ProjectType.nodejs;
      if (hasPyFile) return ProjectType.python;
      if (hasHtmlFile) return ProjectType.web;
    } catch (_) {}
    return ProjectType.other;
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
    final theme = _getTerminalTheme(terminalThemeName);

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
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && (mkdir -p android ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" android/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> android/gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && flutter pub get && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && flutter build apk --debug --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation -Pandroid.aapt2FromMaven=false -Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2 -Pandroid.aapt2.daemon=false -Pandroid.enableJetifier=false && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk',
                  displayCmd: 'flutter build apk --debug')),
          _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && (mkdir -p android ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" android/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> android/gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && flutter pub get && (sed -i "/extra-gen-snapshot-options/d" android/gradle.properties ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && (/usr/local/bin/quantum-heal-x64 2>/dev/null || true) && ([ -x /root/setup-arm64.sh ] && /root/setup-arm64.sh 2>/dev/null || true) && flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation -Pandroid.aapt2FromMaven=false -Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2 -Pandroid.aapt2.daemon=false -Pandroid.enableJetifier=false && (cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./app-release.apk 2>/dev/null || true)',
                  displayCmd: 'flutter build apk --release')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && flutter pub get',
                  displayCmd: 'flutter pub get')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean', displayCmd: 'flutter clean')),
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
                  '$_ktRepairCmd(mkdir -p ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"',
                  displayCmd: './gradlew assembleDebug')),
          _buildActionButton('Release APK (KT)', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '$_ktRepairCmd(mkdir -p ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 assembleRelease && (cp app/build/outputs/apk/release/app-release-unsigned.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/app-release.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/*.apk ./app-release.apk 2>/dev/null || true) && echo "✓ Release APK: ./app-release.apk"',
                  displayCmd: './gradlew assembleRelease')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Clean (KT)', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon clean && rm -f ./app-release.apk ./app-debug.apk',
                  displayCmd: './gradlew clean')),
          _buildActionButton('Sync (KT)', LucideIcons.refresh_cw, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon dependencies',
                  displayCmd: './gradlew dependencies')),
        ];
        break;

      case ProjectType.androidJava:
        buildActions = [
          _buildActionButton('Debug APK (Java)', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(mkdir -p ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 assembleDebug && (cp app/build/outputs/apk/debug/app-debug.apk ./app-debug.apk 2>/dev/null || true) && echo "✓ Debug APK: ./app-debug.apk"',
                  displayCmd: './gradlew assembleDebug')),
          _buildActionButton('Release APK (Java)', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(mkdir -p ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon --max-workers=1 assembleRelease && (cp app/build/outputs/apk/release/app-release-unsigned.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/app-release.apk ./app-release.apk 2>/dev/null || cp app/build/outputs/apk/release/*.apk ./app-release.apk 2>/dev/null || true) && echo "✓ Release APK: ./app-release.apk"',
                  displayCmd: './gradlew assembleRelease')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Clean (Java)', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon clean && rm -f ./app-release.apk ./app-debug.apk',
                  displayCmd: './gradlew clean')),
          _buildActionButton('Sync (Java)', LucideIcons.refresh_cw, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x ./gradlew 2>/dev/null; bash ./gradlew --no-daemon dependencies',
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
          _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && (mkdir -p android ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" android/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\norg.gradle.parallel=false\\n" >> android/gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\norg.gradle.parallel=false\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && flutter pub get && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && flutter build apk --debug --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation -Pandroid.aapt2FromMaven=false -Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2 -Pandroid.aapt2.daemon=false -Pandroid.enableJetifier=false -Porg.gradle.workers.max=1 -Porg.gradle.parallel=false && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk ; (pkill -9 -f aapt2 2>/dev/null || true)',
                  displayCmd: 'flutter build apk --debug')),
          _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && (mkdir -p android ~/.gradle 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" android/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\norg.gradle.parallel=false\\n" >> android/gradle.properties 2>/dev/null || true) && (grep -q "org.gradle.jvmargs" ~/.gradle/gradle.properties 2>/dev/null || printf "\\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\\nandroid.enableJetifier=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\nandroid.aapt2.daemon=false\\norg.gradle.daemon=false\\norg.gradle.workers.max=1\\norg.gradle.parallel=false\\n" >> ~/.gradle/gradle.properties 2>/dev/null || true) && flutter pub get && (sed -i "/extra-gen-snapshot-options/d" android/gradle.properties ~/.gradle/gradle.properties 2>/dev/null || true) && (/usr/local/bin/quantum-patch-ndk 2>/dev/null || true) && flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation -Pandroid.aapt2FromMaven=false -Pandroid.aapt2FromMavenOverride=/usr/bin/aapt2 -Pandroid.aapt2.daemon=false -Pandroid.enableJetifier=false -Porg.gradle.workers.max=1 -Porg.gradle.parallel=false && (cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk 2>/dev/null || cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ./app-release.apk 2>/dev/null || true) ; (pkill -9 -f aapt2 2>/dev/null || true)',
                  displayCmd: 'flutter build apk --release')),
          _buildActionButton(l10n.installApk, LucideIcons.smartphone, Colors.greenAccent,
              () => _installBuiltApk(workspaceState.currentPath)),
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, '(if [ -f pubspec.yaml ] && ! (grep -q "3.1[3-9]" /root/flutter/bin/cache/dart-sdk/version 2>/dev/null || grep -q "3.4[7-9]" /root/flutter/version 2>/dev/null); then sed -i -E "s/sdk:.*3\\.1[3-9].*/sdk: \\x27>=3.12.0 <4.0.0\\x27/g" pubspec.yaml 2>/dev/null || true; fi) && flutter pub get',
                  displayCmd: 'flutter pub get')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean', displayCmd: 'flutter clean')),
        ];
    }

    buildActions.add(_buildActionButton(l10n.copy, LucideIcons.copy, Colors.white60,
        () => _copyTerminalOutput(session, l10n)));

    return Column(
      children: [
        // Sub-tabs header (Console vs Sign APK)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
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
                    _buildActionHeader(l10n.build, buildActions),
                    // Toggle Console vs Beautiful Logs
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      color: Colors.black.withValues(alpha: 0.05),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildLogModeButton(
                            label: 'Logs',
                            isActive: _showBeautifulLogs,
                            onTap: () => setState(() => _showBeautifulLogs = true),
                            icon: LucideIcons.file_text,
                          ),
                          const SizedBox(width: 8),
                          _buildLogModeButton(
                            label: 'Terminal',
                            isActive: !_showBeautifulLogs,
                            onTap: () => setState(() => _showBeautifulLogs = false),
                            icon: LucideIcons.terminal,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: session != null
                            ? (_showBeautifulLogs
                                ? BeautifulLogsViewer(session: session)
                                : xt.TerminalView(
                                    session.xtermTerminal,
                                    controller: session.xtermViewController,
                                    autofocus: true,
                                    theme: theme,
                                    backgroundOpacity: 0,
                                    textStyle: xt.TerminalStyle(
                                      fontSize: terminalFontSize * 0.9,
                                      fontFamily: 'jetBrainsMono',
                                      fontFamilyFallback: const [
                                        'SymbolsNerdFont',
                                        'Symbols Nerd Font',
                                        'cascadia',
                                        'dejaVuSansMono',
                                        'firaCode',
                                        'Noto Sans Mono',
                                        'DejaVu Sans Mono',
                                        'monospace',
                                      ],
                                    ),
                                    keyboardType: TextInputType.visiblePassword,
                                    deleteDetection: true,
                                  ))
                            : Center(child: Text(l10n.buildLogs, style: const TextStyle(color: Colors.white38))),
                      ),
                    ),
                  ],
                )
              : const ApkSignerWidget(),
        ),
      ],
    );
  }

  Widget _buildSubTabButton(int index, String label, IconData icon) {
    final isActive = _buildSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _buildSubTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? Colors.orangeAccent.withValues(alpha: 0.2) : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: isActive ? Colors.orangeAccent : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                color: isActive ? Colors.white : Colors.white38,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionHeader(String title, List<Widget> actions) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.orangeAccent,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
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
      padding: const EdgeInsets.only(left: 3),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: color.withValues(alpha: 0.2), width: 0.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 11, color: color.withValues(alpha: 0.9)),
                  const SizedBox(width: 3),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 9,
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
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    widget.session.xtermTerminal.removeListener(_onTerminalChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTerminalChanged() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
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

    for (final text in lines) {
      final type = _detectLogType(text);
      if (type == LogType.error) errorCount++;
      if (type == LogType.warning) warningCount++;

      if (_searchQuery.isNotEmpty && !text.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }

      if (_filterType == 'error' && type != LogType.error) continue;
      if (_filterType == 'warning' && type != LogType.warning) continue;

      parsedLines.add(_LogItem(text, type));
    }

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
        if (errorCount > 0)
          Builder(builder: (context) {
            final issues = AndroidBuildDiagnosticsService().parseBuildIssues(lines.join('\n'), '');
            if (issues.isEmpty) return const SizedBox.shrink();
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
            child: SelectableText(
              item.text,
              style: GoogleFonts.jetBrainsMono(
                color: textColor,
                fontSize: 10.5,
                height: 1.45,
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
