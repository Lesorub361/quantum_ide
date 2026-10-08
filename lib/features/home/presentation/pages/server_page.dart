import 'package:quantum_ide/core/utils/path_mapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/project_detector.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final _serverProjectTypeProvider = FutureProvider<ProjectType>((ref) async {
  final workspace = ref.watch(workspaceProvider);
  final path = workspace.currentPath;
  if (path == null) return ProjectType.other;
  return ProjectDetector.detect(path);
});

final _serverRunningProvider = StateProvider<bool>((ref) => false);


// ─── Main Page ────────────────────────────────────────────────────────────────

class ServerPage extends ConsumerStatefulWidget {
  const ServerPage({super.key});

  @override
  ConsumerState<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends ConsumerState<ServerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Converts host path → proot guest path
  String _toGuestPath(String hostPath) {
    final runtime = ref.read(runtimeServiceProvider);
    return PathMapper.mapToGuest(hostPath, runtime.appDirectory);
  }

  void _runCommand(String command) {
    final terminal = ref.read(terminalTabsProvider.notifier);
    terminal.sendCommand(command);
  }

  @override
  @override
  Widget build(BuildContext context) {
    final workspacePath = ref.watch(workspaceProvider).currentPath;
    final projectTypeAsync = ref.watch(_serverProjectTypeProvider);
    final isRunning = ref.watch(_serverRunningProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: projectTypeAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
        error: (_, e) => _noProjectView(),
        data: (type) {
          if (workspacePath == null) return _noProjectView();
          final guestPath = _toGuestPath(workspacePath);
          final config = ProjectDetector.runConfig(type, guestPath);
          return _buildMain(workspacePath, type, config, isRunning);
        },
      ),
    );
  }

  Widget _buildMain(
    String path,
    ProjectType type,
    RunConfig config,
    bool isRunning,
  ) {
    return Column(
      children: [
        _buildHeader(path, type, config, isRunning),
        Expanded(
          child: _showPreview && config.supportsPreview
              ? _buildWebPreview(config.port ?? 8080)
              : _buildCommandsPanel(type, config, isRunning),
        ),
      ],
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(
    String path,
    ProjectType type,
    RunConfig config,
    bool isRunning,
  ) {
    final typeColor = Color(config.color);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project type badge + name
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: typeColor.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(config.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  ProjectDetector.typeLabel(type),
                  style: GoogleFonts.inter(
                    color: typeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ]),
            ),
            const Spacer(),
            // Preview toggle (only for web/flutter)
            if (config.supportsPreview)
              GestureDetector(
                onTap: () => setState(() => _showPreview = !_showPreview),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _showPreview
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _showPreview
                          ? theme.colorScheme.primary.withValues(alpha: 0.5)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _showPreview ? LucideIcons.eye_off : LucideIcons.globe,
                      size: 14,
                      color: _showPreview ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _showPreview ? AppLocalizations.of(context)!.code : AppLocalizations.of(context)!.preview,
                      style: GoogleFonts.inter(
                        color: _showPreview ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              ),
          ]),

          const SizedBox(height: 16),
          Text(
            p.basename(path),
            style: GoogleFonts.inter(
              color: theme.colorScheme.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            path,
            style: GoogleFonts.jetBrainsMono(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 16),

          // Primary run button
          _runButton(config, isRunning),
        ],
      ),
    );
  }

  Widget _runButton(RunConfig config, bool isRunning) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        _runCommand(config.command);
        ref.read(_serverRunningProvider.notifier).state = true;
        if (config.supportsPreview) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _showPreview = true);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isRunning
              ? LinearGradient(colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.7),
                ])
              : LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.secondary]),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: isRunning
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRunning ? LucideIcons.circle_dot : LucideIcons.play,
              color: theme.colorScheme.onPrimary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              isRunning ? '▶  ${AppLocalizations.of(context)!.running}' : '▶  ${config.label}',
              style: GoogleFonts.inter(
                color: theme.colorScheme.onPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Commands Panel ────────────────────────────────────────────────────────
  Widget _buildCommandsPanel(
      ProjectType type, RunConfig config, bool isRunning) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Port info
        if (config.port != null) _portCard(config.port!),
        if (config.port != null) const SizedBox(height: 12),

        // Extra commands
        if (config.extraCommands.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(AppLocalizations.of(context)!.fastCommands,
                style: GoogleFonts.inter(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                )),
          ),
          ...config.extraCommands.map((cmd) => _commandTile(cmd)),
          const SizedBox(height: 16),
        ],

        // Stop button
        if (isRunning) _stopButton(),

        const SizedBox(height: 16),

        // Raw command display
        _rawCommandCard(config.command),
      ],
    );
  }

  Widget _portCard(int port) {
    final theme = Theme.of(context);
    final url = 'http://localhost:$port';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(LucideIcons.globe, color: theme.colorScheme.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(context)!.serverAddress,
                  style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(url,
                  style: GoogleFonts.jetBrainsMono(
                      color: theme.colorScheme.primary, fontSize: 14)),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.copied(url)),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
            ));
          },
          icon: Icon(LucideIcons.copy, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 16),
        ),
      ]),
    );
  }

  Widget _commandTile(RunCommand cmd) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _runCommand(cmd.command);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('▶ ${cmd.label}'),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
            ));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
            ),
            child: Row(children: [
              Icon(LucideIcons.terminal,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cmd.label,
                  style: GoogleFonts.inter(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(LucideIcons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3), size: 16),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stopButton() {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        _runCommand(''); // sends Ctrl+C via terminal
        ref.read(terminalTabsProvider.notifier).sendCommand('', interrupt: true);
        ref.read(_serverRunningProvider.notifier).state = false;
        setState(() => _showPreview = false);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(LucideIcons.square, color: theme.colorScheme.error, size: 16),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.stopServer,
              style: GoogleFonts.inter(
                  color: theme.colorScheme.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _rawCommandCard(String command) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppLocalizations.of(context)!.command,
            style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(command,
            style: GoogleFonts.jetBrainsMono(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
      ]),
    );
  }

  // ─── Web Preview ───────────────────────────────────────────────────────────
  Widget _buildWebPreview(int port) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(children: [
        // Address bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerLow,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.lock,
                  color: theme.colorScheme.primary, size: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'http://localhost:$port',
                  style: GoogleFonts.jetBrainsMono(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(LucideIcons.refresh_cw,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 16),
              onPressed: () => setState(() {}),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ]),
        ),

        // Preview note
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                  ),
                  child: Column(children: [
                    Icon(LucideIcons.globe,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 40),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.serverStarted,
                      style: GoogleFonts.inter(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'http://localhost:$port',
                      style: GoogleFonts.jetBrainsMono(
                          color: theme.colorScheme.primary, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.openAddressInBrowser,
                      style: GoogleFonts.inter(
                          color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(
                            text: 'http://localhost:$port'));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(AppLocalizations.of(context)!.copied('http://localhost:$port')),
                          backgroundColor: theme.colorScheme.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(seconds: 1),
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                             horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.copy,
                                  color: theme.colorScheme.primary, size: 14),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(context)!.copyUrl,
                                  style: GoogleFonts.inter(
                                      color: theme.colorScheme.primary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ─── No Project ────────────────────────────────────────────────────────────
  Widget _noProjectView() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              shape: BoxShape.circle,
              border:
                  Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
            ),
            child: Icon(LucideIcons.folder_open,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), size: 40),
          ),
          const SizedBox(height: 20),
          Text(AppLocalizations.of(context)!.projectNotOpened,
              style: GoogleFonts.inter(
                  color: theme.colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(AppLocalizations.of(context)!.openProjectToSeeCommands,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
