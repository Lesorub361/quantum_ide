import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xterm/xterm.dart' as xt;
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/apk_signer_widget.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

// Standalone Sidebar Run Panel
class SidebarRunPanel extends ConsumerStatefulWidget {
  const SidebarRunPanel({super.key});

  @override
  ConsumerState<SidebarRunPanel> createState() => _SidebarRunPanelState();
}

class _SidebarRunPanelState extends ConsumerState<SidebarRunPanel> {
  bool _showBeautifulLogs = true;

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

  void _runDedicatedCommand(String? workspacePath, String cmd) {
    final finalCmd = workspacePath != null ? 'cd "$workspacePath" && clear && $cmd' : 'clear && $cmd';
    ref.read(dedicatedTerminalProvider.notifier).sendCommand(DedicatedTerminalType.run, finalCmd, interrupt: true, clear: false);
  }

  void _sendRawKeyToDedicatedTerminal(String key) {
    ref.read(dedicatedTerminalProvider.notifier).sendRawChar(DedicatedTerminalType.run, key);
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
      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        title = l10n.androidProject;
        actions.addAll([
          _buildActionButton(l10n.buildAPK, LucideIcons.box, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'chmod +x gradlew && ./gradlew assembleDebug')),
          _buildActionButton(l10n.install, LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'chmod +x gradlew && ./gradlew installDebug')),
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
  bool _showBeautifulLogs = true;

  void _runDedicatedCommand(String? workspacePath, String cmd) {
    final finalCmd = workspacePath != null ? 'cd "$workspacePath" && clear && $cmd' : 'clear && $cmd';
    ref.read(dedicatedTerminalProvider.notifier).sendCommand(DedicatedTerminalType.build, finalCmd, interrupt: true, clear: false);
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
      }
      if (hasPubspec) return ProjectType.flutter;
      if (hasGradle) return ProjectType.androidKotlin;
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
    List<Widget> buildActions = [];
    switch (projectType) {
      case ProjectType.flutter:
        buildActions = [
          if (Platform.isAndroid) ...[
            _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --debug --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk')),
            _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
          ] else ...[
            _buildActionButton(l10n.buildPC, LucideIcons.laptop, Colors.cyanAccent,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build linux --release')),
            _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --debug --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk')),
            _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
          ],
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean')),
        ];
        break;

      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        buildActions = [
          _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x gradlew && ./gradlew assembleDebug && echo "✓ Debug APK: app/build/outputs/apk/debug/app-debug.apk"')),
          _buildActionButton('Release APK', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x gradlew && ./gradlew assembleRelease && echo "✓ Release APK: app/build/outputs/apk/release/"')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x gradlew && ./gradlew clean')),
          _buildActionButton('Sync', LucideIcons.refresh_cw, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'chmod +x gradlew && ./gradlew dependencies')),
        ];
        break;

      case ProjectType.python:
        buildActions = [
          _buildActionButton('Install deps', LucideIcons.download, Colors.purple,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'pip3 install -r requirements.txt 2>/dev/null || pip install -r requirements.txt 2>/dev/null || echo "No requirements.txt found"')),
          _buildActionButton('Freeze', LucideIcons.file_text, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'pip3 freeze > requirements.txt && echo "requirements.txt updated"')),
        ];
        break;

      case ProjectType.nodejs:
        buildActions = [
          _buildActionButton('npm install', LucideIcons.download, Colors.green,
              () => _runDedicatedCommand(workspaceState.currentPath, 'npm install')),
          _buildActionButton('npm build', LucideIcons.package, Colors.orange,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'npm run build 2>/dev/null || npx tsc 2>/dev/null || echo "No build script found"')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath,
                  'rm -rf node_modules && echo "node_modules removed"')),
        ];
        break;

      default:
        // Fallback — Flutter build (old behaviour for undetected projects)
        buildActions = [
          if (Platform.isAndroid) ...[
            _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --debug --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk')),
            _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
          ] else ...[
            _buildActionButton(l10n.buildPC, LucideIcons.laptop, Colors.cyanAccent,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build linux --release')),
            _buildActionButton('Debug APK', LucideIcons.bug, Colors.yellow,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --debug --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-debug.apk ./app-debug.apk')),
            _buildActionButton(l10n.buildAPK, LucideIcons.package, Colors.orange,
                () => _runDedicatedCommand(workspaceState.currentPath,
                    'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
          ],
          _buildActionButton('Pub Get', LucideIcons.download, Colors.blue,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get')),
          _buildActionButton('Clean', LucideIcons.trash_2, Colors.red,
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean')),
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
