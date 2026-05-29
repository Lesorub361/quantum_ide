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

// Standalone Sidebar Run Panel
class SidebarRunPanel extends ConsumerStatefulWidget {
  const SidebarRunPanel({super.key});

  @override
  ConsumerState<SidebarRunPanel> createState() => _SidebarRunPanelState();
}

class _SidebarRunPanelState extends ConsumerState<SidebarRunPanel> {
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
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

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
        title = isRu ? 'Flutter Проект' : 'Flutter Project';
        if (Platform.isAndroid) {
          actions.addAll([
            _buildActionButton(isRu ? 'Запуск' : 'Run', LucideIcons.play, Colors.greenAccent, 
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d web-server --web-port 8080')),
            _buildActionButton('Hot Reload', LucideIcons.zap, Colors.yellow, 
                () => _sendRawKeyToDedicatedTerminal('r')),
            _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
                () => _sendRawKeyToDedicatedTerminal('q')),
          ]);
        } else {
          actions.addAll([
            _buildActionButton(isRu ? 'Запуск (ПК)' : 'Run (PC)', LucideIcons.laptop, Colors.cyanAccent, 
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d linux')),
            _buildActionButton(isRu ? 'Запуск (Тел.)' : 'Run (Mob)', LucideIcons.smartphone, Colors.greenAccent, 
                () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run -d android')),
            _buildActionButton('Hot Reload', LucideIcons.zap, Colors.yellow, 
                () => _sendRawKeyToDedicatedTerminal('r')),
            _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
                () => _sendRawKeyToDedicatedTerminal('q')),
          ]);
        }
        break;
      case ProjectType.python:
        title = isRu ? 'Python Проект' : 'Python Project';
        actions.addAll([
          _buildActionButton(isRu ? 'Запуск' : 'Run', LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'python3 main.py || python3 app.py || (py_file=\$(find . -maxdepth 2 -name "*.py" | head -n 1); if [ -n "\$py_file" ]; then python3 "\$py_file"; else echo "No python file found. Please create main.py"; fi)')),
          _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.nodejs:
        title = isRu ? 'Node.js Проект' : 'Node.js Project';
        actions.addAll([
          _buildActionButton(isRu ? 'Запуск' : 'Run', LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'npm start || node index.js || node server.js || node app.js || (js_file=\$(find . -maxdepth 2 -name "*.js" ! -path "*/node_modules/*" | head -n 1); if [ -n "\$js_file" ]; then node "\$js_file"; else echo "No JS file found. Please create index.js or package.json"; fi)')),
          _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.dart:
        title = isRu ? 'Dart Проект' : 'Dart Project';
        actions.addAll([
          _buildActionButton(isRu ? 'Запуск' : 'Run', LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'dart run || dart bin/main.dart || dart main.dart || (dart_file=\$(find . -maxdepth 2 -name "*.dart" | head -n 1); if [ -n "\$dart_file" ]; then dart "\$dart_file"; else echo "No Dart file found. Please create bin/main.dart"; fi)')),
          _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.web:
        title = isRu ? 'Web Проект' : 'Web Project';
        actions.addAll([
          _buildActionButton(isRu ? 'Старт Сервера' : 'Start Server', LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 
                  'python3 -m http.server 8080 || npx http-server -p 8080 || npx serve -p 8080')),
          _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      case ProjectType.androidJava:
      case ProjectType.androidKotlin:
        title = isRu ? 'Android Проект' : 'Android Project';
        actions.addAll([
          _buildActionButton(isRu ? 'Сборка APK' : 'Build APK', LucideIcons.box, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'chmod +x gradlew && ./gradlew assembleDebug')),
          _buildActionButton(isRu ? 'Установка' : 'Install', LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'chmod +x gradlew && ./gradlew installDebug')),
          _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
        break;
      default:
        title = isRu ? 'Проект' : 'Project';
        actions.addAll([
          _buildActionButton(isRu ? 'Запуск' : 'Run', LucideIcons.play, Colors.greenAccent, 
              () => _runDedicatedCommand(workspaceState.currentPath, 'flutter run || npm start || python3 main.py')),
          _buildActionButton(isRu ? 'Стоп' : 'Stop', LucideIcons.square, Colors.redAccent, 
              () => _sendRawKeyToDedicatedTerminal(String.fromCharCode(3))), // Ctrl+C
        ]);
    }

    actions.add(_buildActionButton(isRu ? 'Копировать' : 'Copy', LucideIcons.copy, Colors.white60, () => _copyTerminalOutput(session)));

    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _getTerminalTheme(terminalThemeName);

    return Column(
      children: [
        _buildActionHeader(title, actions),
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
                ? xt.TerminalView(
                    session.xtermTerminal,
                    controller: session.xtermViewController,
                    autofocus: true,
                    theme: theme,
                    backgroundOpacity: 0,
                    textStyle: xt.TerminalStyle(
                      fontSize: terminalFontSize * 0.9,
                      fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
                    ),
                    keyboardType: TextInputType.visiblePassword,
                    deleteDetection: true,
                  )
                : Center(child: Text(isRu ? 'Запустите проект' : 'Start the project', style: const TextStyle(color: Colors.white38))),
          ),
        ),
      ],
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
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.greenAccent,
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
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 14, color: color.withValues(alpha: 0.9)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyTerminalOutput(TerminalSession? session) async {
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
          SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ru' ? 'Вывод скопирован' : 'Output copied'), duration: const Duration(seconds: 1)),
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

  @override
  Widget build(BuildContext context) {
    final dedicatedState = ref.watch(dedicatedTerminalProvider);
    final session = dedicatedState.sessions[DedicatedTerminalType.build];
    final workspaceState = ref.watch(workspaceProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    final terminalFontSize = ref.watch(settingsProvider).terminalFontSize;
    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final theme = _getTerminalTheme(terminalThemeName);

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
              _buildSubTabButton(0, isRu ? 'Консоль' : 'Console', LucideIcons.terminal),
              const SizedBox(width: 8),
              _buildSubTabButton(1, isRu ? 'Подпись APK' : 'Sign APK', LucideIcons.pen_tool),
            ],
          ),
        ),
        Expanded(
          child: _buildSubTab == 0
              ? Column(
                  children: [
                    _buildActionHeader(isRu ? 'Сборка' : 'Build', [
                      if (Platform.isAndroid) ...[
                        _buildActionButton(isRu ? 'Собрать APK' : 'Build APK', LucideIcons.package, Colors.orange, 
                            () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
                      ] else ...[
                        _buildActionButton(isRu ? 'Сборка (ПК)' : 'Build (PC)', LucideIcons.laptop, Colors.cyanAccent, 
                            () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get && flutter build linux --release')),
                        _buildActionButton(isRu ? 'Сборка (APK)' : 'Build (APK)', LucideIcons.package, Colors.orange, 
                            () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get && flutter build apk --release --no-tree-shake-icons && cp build/app/outputs/flutter-apk/app-release.apk ./app-release.apk')),
                      ],
                      _buildActionButton('Pub Get', LucideIcons.download, Colors.blue, 
                          () => _runDedicatedCommand(workspaceState.currentPath, 'flutter pub get')),
                      _buildActionButton('Clean', LucideIcons.trash_2, Colors.red, 
                          () => _runDedicatedCommand(workspaceState.currentPath, 'flutter clean')),
                      _buildActionButton(isRu ? 'Копировать' : 'Copy', LucideIcons.copy, Colors.white60, 
                          () => _copyTerminalOutput(session)),
                    ]),
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
                            ? xt.TerminalView(
                                session.xtermTerminal,
                                controller: session.xtermViewController,
                                autofocus: true,
                                theme: theme,
                                backgroundOpacity: 0,
                                textStyle: xt.TerminalStyle(
                                  fontSize: terminalFontSize * 0.9,
                                  fontFamily: GoogleFonts.jetBrainsMono().fontFamily ?? 'monospace',
                                ),
                                keyboardType: TextInputType.visiblePassword,
                                deleteDetection: true,
                              )
                            : Center(child: Text(isRu ? 'Логи сборки' : 'Build logs', style: const TextStyle(color: Colors.white38))),
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
      padding: const EdgeInsets.only(left: 6),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 14, color: color.withValues(alpha: 0.9)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyTerminalOutput(TerminalSession? session) async {
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
          SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'ru' ? 'Вывод скопирован' : 'Output copied'), duration: const Duration(seconds: 1)),
        );
      }
    }
  }
}
