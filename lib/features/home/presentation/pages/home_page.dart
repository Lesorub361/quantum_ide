import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/utils/platform_utils.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/app_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/models/optional_package.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStackFilter = 'all';
  bool _sortByName = false;
  bool _isExportingAllToSd = false;
  final Set<String> _exportingProjectIds = {};
  String? _dismissedUpdateTag;
  bool _dismissedPackagesBanner = false;
  bool _checkedPackagesPrompt = false;

  Future<void> _exportAllToSdCard() async {
    if (_isExportingAllToSd) return;
    setState(() => _isExportingAllToSd = true);
    try {
      final result = await ref
          .read(projectServiceProvider.notifier)
          .exportAllProjectsToSdCard();
      if (!mounted) return;
      _showSdExportSnackBar(result);
    } finally {
      if (mounted) {
        setState(() => _isExportingAllToSd = false);
      }
    }
  }

  Future<void> _exportSingleProjectToSdCard(Project project) async {
    if (_exportingProjectIds.contains(project.id)) return;
    setState(() => _exportingProjectIds.add(project.id));
    try {
      final result = await ref
          .read(projectServiceProvider.notifier)
          .exportProjectToSdCard(project);
      if (!mounted) return;
      _showSdExportSnackBar(result, projectName: project.name);
    } finally {
      if (mounted) {
        setState(() => _exportingProjectIds.remove(project.id));
      }
    }
  }

  void _showSdExportSnackBar(SdCardExportResult result, {String? projectName}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final String text;
    if (!result.isSuccess) {
      text = result.errorMessage ?? 'Ошибка экспорта на SD-карту';
    } else if (projectName != null) {
      final apkPart =
          result.copiedApks > 0 ? ', APK: ${result.copiedApks}' : '';
      text =
          'Проект «$projectName» обновлён на SD: ${result.copiedFiles} файлов$apkPart (${result.destinationPath})';
    } else {
      final apkPart =
          result.copiedApks > 0 ? ', APK: ${result.copiedApks}' : '';
      text =
          'Обновлено на SD: ${result.projectCount} проектов, ${result.copiedFiles} файлов$apkPart (${result.destinationPath})';
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor:
            result.isSuccess ? const Color(0xFF10B981) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _importAndOpenProject(BuildContext context, WidgetRef ref) async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    final imported =
        await ref.read(projectServiceProvider.notifier).importProject(dir);
    await ref.read(workspaceProvider.notifier).setWorkspace(imported.path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Проект открыт: ${imported.path}'),
        duration: const Duration(seconds: 2),
      ),
    );
    context.go('/editor');
  }

  bool _matchesStackFilter(Project p) {
    switch (_selectedStackFilter) {
      case 'flutter':
        return p.type == ProjectType.flutter || p.type == ProjectType.dart;
      case 'android':
        return p.type == ProjectType.androidKotlin || p.type == ProjectType.androidJava;
      case 'web':
        return p.type == ProjectType.web || p.type == ProjectType.nodejs;
      case 'python':
        return p.type == ProjectType.python;
      case 'other':
        return p.type == ProjectType.rust || p.type == ProjectType.shell || p.type == ProjectType.other;
      case 'all':
      default:
        return true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(workspaceProvider).currentPath != null) {
        ref.read(workspaceProvider.notifier).closeWorkspace();
      }
      ref.read(editorProvider.notifier).clearWorkspace();
      ref.read(terminalTabsProvider.notifier).closeAllSessions();
      ref.read(runtimeServiceProvider).init();
      ref.read(appUpdateServiceProvider.notifier).checkForUpdates(silent: true);
      _checkAndPromptEssentialPackages();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allProjects = ref.watch(projectServiceProvider);
    final projects = allProjects
        .where((p) =>
            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) &&
            _matchesStackFilter(p))
        .toList();

    if (_sortByName) {
      projects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      projects.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    }

    final lastProject = allProjects.isNotEmpty
        ? (List<Project>.from(allProjects)..sort((a, b) => b.lastOpened.compareTo(a.lastOpened))).first
        : null;

    final otherProjects = lastProject != null && _searchQuery.isEmpty && _selectedStackFilter == 'all'
        ? projects.where((p) => p.id != lastProject.id).toList()
        : projects;

    final width = MediaQuery.of(context).size.width;

    if (width >= 1024) {
      return _buildDesktopHome(context, allProjects, projects, lastProject, otherProjects);
    } else if (width >= 600) {
      return _buildTabletHome(context, allProjects, projects, lastProject, otherProjects);
    } else {
      return _buildMobileHome(context, allProjects, projects, lastProject, otherProjects);
    }
  }

  Widget _buildEmptyStateSliver(BuildContext context, ThemeData theme) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.folder_search, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? AppLocalizations.of(context)!.noProjects : AppLocalizations.of(context)!.nothingFound,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 16),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _showProjectDialog(context, ref),
                icon: const Icon(LucideIcons.plus, size: 18),
                label: Text(AppLocalizations.of(context)!.createFirstProject),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRailItem({required IconData icon, required String tooltip, required Color color, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletHome(
    BuildContext context,
    List<Project> allProjects,
    List<Project> projects,
    Project? lastProject,
    List<Project> otherProjects,
  ) {
    final theme = Theme.of(context);
    final showResume = lastProject != null && _searchQuery.isEmpty && _selectedStackFilter == 'all';
    final displayedProjects = showResume ? otherProjects : projects;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          // Tablet Navigation Rail
          Container(
            width: 68,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4))),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.terminal, color: theme.colorScheme.onPrimary, size: 20),
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildRailItem(
                        icon: LucideIcons.plus,
                        tooltip: AppLocalizations.of(context)!.createProject,
                        color: theme.colorScheme.primary,
                        onTap: () => _showProjectDialog(context, ref),
                      ),
                      _buildRailItem(
                        icon: LucideIcons.folder_open,
                        tooltip: AppLocalizations.of(context)!.open,
                        color: Colors.cyanAccent,
                        onTap: () => _importAndOpenProject(context, ref),
                      ),
                      _buildRailItem(
                        icon: LucideIcons.git_branch,
                        tooltip: 'Git и GitHub (Клонирование / Репозитории)',
                        color: Colors.purpleAccent,
                        onTap: () => context.push('/github'),
                      ),
                      _buildRailItem(
                        icon: LucideIcons.terminal,
                        tooltip: AppLocalizations.of(context)!.terminal,
                        color: const Color(0xFF10B981),
                        onTap: () => context.push('/terminal'),
                      ),
                      _buildRailItem(
                        icon: LucideIcons.package,
                        tooltip: 'Пакеты и SDK',
                        color: Colors.amberAccent,
                        onTap: () => context.push('/packages'),
                      ),
                      _buildRailItem(
                        icon: LucideIcons.blocks,
                        tooltip: 'Инструменты разработчика (SQLite, SFTP, Серверы, DevTools)',
                        color: const Color(0xFF00E5FF),
                        onTap: () => _showDeveloperToolsSheet(context),
                      ),
                      _buildRailItem(
                        icon: LucideIcons.settings,
                        tooltip: AppLocalizations.of(context)!.settings,
                        color: theme.colorScheme.onSurfaceVariant,
                        onTap: () => context.push('/settings'),
                      ),
                    ],
                  ),
                ),
                // Telemetry summary indicator
                Consumer(
                  builder: (context, ref, _) {
                    final stats = ref.watch(systemStatsProvider);
                    return Tooltip(
                      message: 'CPU: ${(stats.cpuUsage * 100).toStringAsFixed(0)}% • GPU: ${(stats.gpuUsage * 100).toStringAsFixed(0)}% • App RAM: ${stats.appRamFormatted}',
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          width: 44,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
                                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final searchWidth = (constraints.maxWidth * 0.38).clamp(200.0, 280.0);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            AppLocalizations.of(context)!.welcomeTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              color: theme.colorScheme.onSurface,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        _buildVersionChip(context),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppLocalizations.of(context)!.welcomeSubtitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: searchWidth,
                                child: _buildSearchField(),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildAppUpdateBanner(context),
                      _buildPackagesRecommendationBanner(context),
                      if (showResume) ...[
                        _buildResumeCard(context, lastProject),
                        const SizedBox(height: 16),
                      ],
                      _buildStackFilterChips(context),
                      const SizedBox(height: 14),
                      if (displayedProjects.isNotEmpty || (Platform.isAndroid && allProjects.isNotEmpty)) ...[
                        _buildProjectsHeader(
                          displayedProjects.length,
                          hasAnyProjects: allProjects.isNotEmpty,
                        ),
                        const SizedBox(height: 14),
                      ],
                    ]),
                  ),
                ),
                if (projects.isEmpty)
                  _buildEmptyStateSliver(context, theme)
                else if (displayedProjects.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 340,
                        mainAxisExtent: 184,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildDesktopProjectCard(context, ref, displayedProjects[index]),
                        childCount: displayedProjects.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHome(
    BuildContext context,
    List<Project> allProjects,
    List<Project> projects,
    Project? lastProject,
    List<Project> otherProjects,
  ) {
    final theme = Theme.of(context);
    final isLandscapeMobile = MediaQuery.of(context).orientation == Orientation.landscape;
    final showResume = lastProject != null && _searchQuery.isEmpty && _selectedStackFilter == 'all';
    final displayedProjects = showResume ? otherProjects : projects;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background ambient glows - Wrapped in RepaintBoundary for performance
          RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: -150,
                  left: -150,
                  child: Container(
                    width: 350,
                    height: 350,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.1),
                          theme.colorScheme.primary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 250,
                  right: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          theme.colorScheme.secondary.withValues(alpha: 0.07),
                          theme.colorScheme.secondary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildSliverAppBar(context),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 8),
                      _buildSearchField(),
                      const SizedBox(height: 12),
                      _buildAppUpdateBanner(context),
                      _buildPackagesRecommendationBanner(context),
                      if (showResume) ...[
                        _buildResumeCard(context, lastProject),
                        const SizedBox(height: 12),
                      ],
                      _buildMobileQuickActionsBar(context),
                      const SizedBox(height: 12),
                      _buildCompactSystemMonitorChip(context),
                      const SizedBox(height: 14),
                      _buildStackFilterChips(context),
                      const SizedBox(height: 14),
                      if (displayedProjects.isNotEmpty || (Platform.isAndroid && allProjects.isNotEmpty)) ...[
                        _buildProjectsHeader(
                          displayedProjects.length,
                          hasAnyProjects: allProjects.isNotEmpty,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ]),
                  ),
                ),
                if (projects.isEmpty)
                  _buildEmptyStateSliver(context, theme)
                else if (displayedProjects.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: isLandscapeMobile
                        ? SliverGrid(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 360,
                              mainAxisExtent: 116,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildProjectCard(context, ref, displayedProjects[index]),
                              childCount: displayedProjects.length,
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildProjectCard(context, ref, displayedProjects[index]),
                              ),
                              childCount: displayedProjects.length,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHome(
    BuildContext context,
    List<Project> allProjects,
    List<Project> projects,
    Project? lastProject,
    List<Project> otherProjects,
  ) {
    final theme = Theme.of(context);
    final showResume = lastProject != null && _searchQuery.isEmpty && _selectedStackFilter == 'all';
    final displayedProjects = showResume ? otherProjects : projects;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branding
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(LucideIcons.terminal, color: theme.colorScheme.onPrimary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Quantum IDE',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildVersionChip(context),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 16),

                // Navigation items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSidebarItem(
                        icon: LucideIcons.plus,
                        label: AppLocalizations.of(context)!.createProject,
                        color: theme.colorScheme.primary,
                        onTap: () => _showProjectDialog(context, ref),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.folder_open,
                        label: AppLocalizations.of(context)!.open,
                        color: Colors.cyanAccent,
                        onTap: () => _importAndOpenProject(context, ref),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.git_branch,
                        label: 'Git и GitHub',
                        color: Colors.purpleAccent,
                        onTap: () => context.push('/github'),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.terminal,
                        label: AppLocalizations.of(context)!.terminal,
                        color: const Color(0xFF10B981),
                        onTap: () => context.push('/terminal'),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.package,
                        label: 'Пакеты и SDK',
                        color: Colors.amberAccent,
                        onTap: () => context.push('/packages'),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.blocks,
                        label: 'Инструменты разработчика',
                        color: const Color(0xFF00E5FF),
                        onTap: () => _showDeveloperToolsSheet(context),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.settings,
                        label: AppLocalizations.of(context)!.settings,
                        color: theme.colorScheme.onSurfaceVariant,
                        onTap: () => context.push('/settings'),
                      ),
                    ],
                  ),
                ),

                // System Telemetry
                Consumer(
                  builder: (context, ref, _) {
                    final stats = ref.watch(systemStatsProvider);
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'TELEMETRY',
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('CPU', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
                                Text(
                                  '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
                                  style: GoogleFonts.inter(color: theme.colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: stats.cpuUsage,
                              minHeight: 3,
                              backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                              valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('App RAM', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
                                Text(
                                  stats.appRamFormatted,
                                  style: GoogleFonts.inter(color: theme.colorScheme.secondary, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: stats.ramUsage,
                              minHeight: 3,
                              backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                              valueColor: AlwaysStoppedAnimation(theme.colorScheme.secondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1360),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context)!.welcomeTitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: theme.colorScheme.onSurface,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppLocalizations.of(context)!.welcomeSubtitle,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              SizedBox(
                                width: 320,
                                child: _buildSearchField(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildAppUpdateBanner(context),
                          _buildPackagesRecommendationBanner(context),
                          if (showResume) ...[
                            Text(
                              AppLocalizations.of(context)!.lastActiveProject,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 680),
                                child: _buildResumeCard(context, lastProject),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          _buildStackFilterChips(context),
                          const SizedBox(height: 16),
                          if (displayedProjects.isNotEmpty || (Platform.isAndroid && allProjects.isNotEmpty)) ...[
                            _buildProjectsHeader(
                              displayedProjects.length,
                              hasAnyProjects: allProjects.isNotEmpty,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ]),
                      ),
                    ),
                    if (projects.isEmpty)
                      _buildEmptyStateSliver(context, theme)
                    else if (displayedProjects.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 340,
                            mainAxisExtent: 184,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildDesktopProjectCard(context, ref, displayedProjects[index]),
                            childCount: displayedProjects.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopProjectCard(BuildContext context, WidgetRef ref, Project project) {
    final lastModified = project.lastOpened;
    final dateStr = '${lastModified.day}.${lastModified.month}.${lastModified.year}';
    final theme = Theme.of(context);
    final isExporting = _exportingProjectIds.contains(project.id);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await ref.read(workspaceProvider.notifier).setWorkspace(project.path);
                if (context.mounted) context.go('/editor');
              },
              onLongPress: () => _showProjectActions(context, ref, project),
              onSecondaryTap: () => _showProjectActions(context, ref, project),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                project.color.withValues(alpha: 0.2),
                                project.color.withValues(alpha: 0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: project.color.withValues(alpha: 0.3)),
                          ),
                          child: project.appIconPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(project.appIconPath!),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Icon(project.icon, color: project.color, size: 20),
                                  ),
                                )
                              : Icon(project.icon, color: project.color, size: 20),
                        ),
                        const Spacer(),
                        if (Platform.isAndroid) ...[
                          IconButton(
                            icon: isExporting
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    LucideIcons.hard_drive_upload,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                            tooltip: 'Обновить на SD',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: isExporting ? null : () => _exportSingleProjectToSdCard(project),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (PlatformUtils.isDesktop) ...[
                          IconButton(
                            icon: const Icon(LucideIcons.folder_open, size: 14, color: Colors.cyanAccent),
                            tooltip: 'Открыть папку в файловом менеджере (${project.path})',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => PlatformUtils.openInFileManager(project.path),
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          icon: const Icon(LucideIcons.play, size: 14, color: Color(0xFF10B981)),
                          tooltip: AppLocalizations.of(context)!.runTooltip,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            ref.read(projectServiceProvider.notifier).runProject(project);
                            context.push('/terminal');
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(LucideIcons.ellipsis_vertical, size: 14, color: theme.colorScheme.onSurfaceVariant),
                          tooltip: AppLocalizations.of(context)!.actionsTooltip,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showProjectActions(context, ref, project),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      project.name,
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: project.path,
                      child: Text(
                        project.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          project.type.name.toUpperCase(),
                          style: GoogleFonts.inter(color: theme.colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dateStr,
                          style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65), fontSize: 10),
                        ),
                      ],
                    ),
                    if (project.platforms != null && project.platforms!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: project.platforms!.take(4).map((plat) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: project.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: project.color.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              plat.toUpperCase(),
                              style: GoogleFonts.inter(
                                color: project.color,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      expandedHeight: 68,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
        centerTitle: false,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Quantum IDE',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              _buildVersionChip(context),
            ],
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.scaffoldBackgroundColor,
                theme.scaffoldBackgroundColor.withValues(alpha: 0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      actions: [
        _buildAppActionButton(
          icon: LucideIcons.blocks,
          tooltip: 'Инструменты разработчика',
          onTap: () => _showDeveloperToolsSheet(context),
        ),
        _buildAppActionButton(
          icon: LucideIcons.settings,
          tooltip: AppLocalizations.of(context)!.settings,
          onTap: () => context.push('/settings'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildAppActionButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: IconButton(
        icon: Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 16),
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  Widget _buildVersionChip(BuildContext context) {
    final updateState = ref.watch(appUpdateServiceProvider);
    final theme = Theme.of(context);
    final hasUpdate = updateState.hasUpdate;

    return InkWell(
      onTap: () async {
        if (hasUpdate && updateState.updateInfo != null) {
          _showUpdateDialog(context, updateState.updateInfo!);
          return;
        }

        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 10),
                Text('Проверка обновлений QuantumIDE...'),
              ],
            ),
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );

        final info = await ref.read(appUpdateServiceProvider.notifier).checkForUpdates();
        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();

        if (info != null) {
          _showUpdateDialog(context, info);
        } else {
          final latestState = ref.read(appUpdateServiceProvider);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                latestState.errorMessage ??
                    'QuantumIDE v${latestState.currentVersion} • Установлена актуальная версия',
              ),
              backgroundColor: latestState.errorMessage != null ? Colors.redAccent : null,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: hasUpdate
              ? Colors.amber.withValues(alpha: 0.15)
              : theme.colorScheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasUpdate
                ? Colors.amber.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasUpdate) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              'v${updateState.currentVersion}',
              style: GoogleFonts.firaCode(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: hasUpdate ? Colors.amber : theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            if (hasUpdate) ...[
              const SizedBox(width: 4),
              const Icon(LucideIcons.arrow_up, size: 12, color: Colors.amber),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAppUpdateBanner(BuildContext context) {
    final updateState = ref.watch(appUpdateServiceProvider);
    if (!updateState.hasUpdate) return const SizedBox.shrink();

    final info = updateState.updateInfo!;
    if (_dismissedUpdateTag == info.versionName) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            Colors.purpleAccent.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.sparkles, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Доступно обновление',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'v${info.versionName}',
                            style: GoogleFonts.firaCode(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Текущая версия: v${updateState.currentVersion} • Обновление в 1 клик',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16),
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () {
                  setState(() {
                    _dismissedUpdateTag = info.versionName;
                  });
                },
                tooltip: 'Скрыть',
              ),
            ],
          ),
          if (updateState.isDownloading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: updateState.downloadProgress > 0 ? updateState.downloadProgress : null,
                minHeight: 8,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  updateState.statusMessage ?? 'Загрузка...',
                  style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  '${(updateState.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.firaCode(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ] else ...[
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.notes.length > 200 ? '${info.notes.substring(0, 200)}...' : info.notes,
                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => ref.read(appUpdateServiceProvider.notifier).downloadAndInstallUpdate(info),
                  icon: const Icon(LucideIcons.download, size: 16),
                  label: const Text('Обновить приложение'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _showUpdateDialog(context, info),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Подробнее'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkAndPromptEssentialPackages() async {
    if (_checkedPackagesPrompt || !mounted) return;
    _checkedPackagesPrompt = true;

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final hasDismissed = prefs.getBool('essential_packages_prompt_dismissed') ?? false;
    if (hasDismissed) return;

    final allPackages = ref.read(packageServiceProvider);
    const essentialIds = ['vulkan-graphics', 'box64-emulator', 'build-fix', 'apk-signing-tools'];
    final uninstalled = allPackages.where((p) => essentialIds.contains(p.id) && !p.isInstalled).toList();

    if (uninstalled.isEmpty) return;
    if (!mounted) return;

    _showEssentialPackagesDialog(context, uninstalled);
  }

  void _showEssentialPackagesDialog(BuildContext context, List<OptionalPackage> uninstalled) {
    final theme = Theme.of(context);
    bool doNotShowAgain = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                width: 1.2,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.zap, color: Colors.amber, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Рекомендуемые компоненты',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Vulkan 3D, Box64 & Сборка APK',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Для максимальной скорости, аппаратного 3D-ускорения Vulkan, эмуляции x86_64 и надежной сборки APK рекомендуется установить следующие пакеты:',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: uninstalled.map((pkg) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white10,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(pkg.icon, color: Colors.cyanAccent, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pkg.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        pkg.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Требуется',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: doNotShowAgain,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (val) {
                          setDialogState(() {
                            doNotShowAgain = val ?? false;
                          });
                        },
                      ),
                      Text(
                        'Больше не показывать при запуске',
                        style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (doNotShowAgain) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('essential_packages_prompt_dismissed', true);
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Text('Позже', style: GoogleFonts.inter(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(LucideIcons.package, size: 16),
                label: Text('Открыть Менеджер пакетов', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  if (doNotShowAgain) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('essential_packages_prompt_dismissed', true);
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) context.push('/packages');
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPackagesRecommendationBanner(BuildContext context) {
    if (!Platform.isAndroid || _dismissedPackagesBanner) {
      return const SizedBox.shrink();
    }

    final allPackages = ref.watch(packageServiceProvider);
    const essentialIds = ['vulkan-graphics', 'box64-emulator', 'build-fix', 'apk-signing-tools'];
    final uninstalled = allPackages.where((p) => essentialIds.contains(p.id) && !p.isInstalled).toList();

    if (uninstalled.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withValues(alpha: 0.15),
            Colors.deepPurpleAccent.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.cyanAccent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(LucideIcons.zap, color: Colors.cyanAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Рекомендуемые компоненты окружения',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${uninstalled.length} доступно',
                            style: GoogleFonts.firaCode(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vulkan 3D, Box64, Build Environment Fix и инструменты подписи APK для работы на Android.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(LucideIcons.x, size: 18, color: theme.colorScheme.onSurfaceVariant),
                onPressed: () {
                  setState(() {
                    _dismissedPackagesBanner = true;
                  });
                },
                tooltip: 'Скрыть',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _dismissedPackagesBanner = true;
                  });
                },
                child: Text(
                  'Позже',
                  style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(LucideIcons.package, size: 16),
                label: Text(
                  'Настроить пакеты',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  context.push('/packages');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    final theme = Theme.of(context);
    final sizeMb = info.sizeBytes > 0 ? ' • ${(info.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB' : '';

    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(appUpdateServiceProvider);
          return AlertDialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(LucideIcons.sparkles, color: Colors.amber, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Обновление QuantumIDE',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Версия: v${info.versionName}$sizeMb',
                        style: GoogleFonts.firaCode(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (info.notes.isNotEmpty) ...[
                      Text(
                        'Что нового:',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Text(
                          info.notes,
                          style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (state.isDownloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: state.downloadProgress > 0 ? state.downloadProgress : null,
                          minHeight: 8,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.statusMessage ?? 'Загрузка...',
                        style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Закрыть'),
              ),
              if (!state.isDownloading)
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(appUpdateServiceProvider.notifier).downloadAndInstallUpdate(info);
                  },
                  icon: const Icon(LucideIcons.download, size: 16),
                  label: const Text('Скачать и установить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResumeCard(BuildContext context, Project project) {
    final lastModified = project.lastOpened;
    final dateStr = '${lastModified.day}.${lastModified.month}.${lastModified.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            project.color.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: project.color.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: project.color.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 1,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await ref.read(workspaceProvider.notifier).setWorkspace(project.path);
              if (context.mounted) context.go('/editor');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: project.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'RESUME PROJECT',
                            style: GoogleFonts.inter(
                              color: project.color,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          project.name,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${project.type.name.toUpperCase()} • Last active: $dateStr',
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: project.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: project.color.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(
                      LucideIcons.play,
                      color: project.color,
                      size: 16,
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

  Widget _buildSystemMonitor(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final stats = ref.watch(systemStatsProvider);

        return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF10B981),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF10B981),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SYSTEM TELEMETRY',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white38,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Text(
                'ACTIVE',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Colors.cyanAccent,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${stats.socName} • ${stats.gpuName}',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.cpu, size: 12, color: Colors.cyanAccent),
                            const SizedBox(width: 4),
                            Text(
                              'CPU',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
                            style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: stats.cpuUsage,
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.zap, size: 12, color: Colors.greenAccent),
                            const SizedBox(width: 4),
                            Text(
                              'GPU',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            '${(stats.gpuUsage * 100).toStringAsFixed(0)}%',
                            style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: stats.gpuUsage,
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.memory_stick, size: 12, color: Colors.purpleAccent),
                            const SizedBox(width: 4),
                            Text(
                              'RAM',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            stats.appRamFormatted,
                            style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: stats.ramUsage,
                        minHeight: 3,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.purpleAccent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.searchProjects,
          hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 13),
          prefixIcon: Icon(LucideIcons.search, color: theme.colorScheme.primary.withValues(alpha: 0.7), size: 16),
          suffixIcon: _searchQuery.isNotEmpty 
              ? IconButton(
                  icon: Icon(LucideIcons.x, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), size: 14),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildStackFilterChips(BuildContext context) {
    final filters = [
      (id: 'all', label: 'Все проекты', icon: LucideIcons.layers),
      (id: 'flutter', label: 'Flutter / Dart', icon: LucideIcons.smartphone),
      (id: 'android', label: 'Android (Kotlin/Java)', icon: LucideIcons.cpu),
      (id: 'web', label: 'Web / Node.js', icon: LucideIcons.globe),
      (id: 'python', label: 'Python', icon: LucideIcons.terminal),
      (id: 'other', label: 'Rust / Скрипты', icon: LucideIcons.code),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final f = filters[index];
          final isSelected = _selectedStackFilter == f.id;
          return InkWell(
            onTap: () => setState(() => _selectedStackFilter = f.id),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.cyanAccent.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? Colors.cyanAccent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    f.icon,
                    size: 13,
                    color: isSelected ? Colors.cyanAccent : Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    f.label,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.cyanAccent : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeveloperToolsSheet(BuildContext context) {
    final theme = Theme.of(context);
    final tools = [
      (
        icon: LucideIcons.package,
        title: 'Пакеты и SDK (Market)',
        subtitle: 'Установка компиляторов, библиотек и инструментов Linux',
        color: Colors.pinkAccent,
        onTap: () {
          Navigator.pop(context);
          context.push('/packages');
        },
      ),
      (
        icon: LucideIcons.server,
        title: 'Локальные серверы',
        subtitle: 'Управление запущенными веб-серверами и портами',
        color: theme.colorScheme.error,
        onTap: () {
          Navigator.pop(context);
          context.push('/servers');
        },
      ),
      (
        icon: LucideIcons.database,
        title: 'Инспектор баз данных (SQLite)',
        subtitle: 'Просмотр таблиц и выполнение SQL-запросов',
        color: const Color(0xFF10B981),
        onTap: () {
          Navigator.pop(context);
          context.push('/database-viewer');
        },
      ),
      (
        icon: LucideIcons.globe,
        title: 'Удалённый доступ (SFTP / SSH)',
        subtitle: 'Подключение к внешним серверам и передача файлов',
        color: const Color(0xFFFF9100),
        onTap: () {
          Navigator.pop(context);
          context.push('/sftp-explorer');
        },
      ),
      (
        icon: LucideIcons.wrench,
        title: 'Инженерные утилиты (DevTools)',
        subtitle: 'Форматирование JSON, проверка Regex, генератор хэшей и цветов',
        color: const Color(0xFF00E5FF),
        onTap: () {
          Navigator.pop(context);
          context.push('/devtools');
        },
      ),
      (
        icon: LucideIcons.send,
        title: 'REST API Клиент',
        subtitle: 'Отправка HTTP-запросов (GET/POST/PUT/DELETE) и просмотр ответов',
        color: const Color(0xFF818CF8),
        onTap: () {
          Navigator.pop(context);
          context.push('/rest-client');
        },
      ),
      (
        icon: LucideIcons.activity,
        title: 'Сетевой инспектор (Network)',
        subtitle: 'Мониторинг HTTP/API-запросов, статусов, заголовков и задержек',
        color: const Color(0xFF34D399),
        onTap: () {
          Navigator.pop(context);
          context.push('/network-inspector');
        },
      ),
      (
        icon: LucideIcons.folder_search,
        title: 'Проводник файлов',
        subtitle: 'Обзор директорий и быстрый доступ к файлам устройства',
        color: const Color(0xFFFBBF24),
        onTap: () {
          Navigator.pop(context);
          context.push('/explorer');
        },
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12151E),
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(LucideIcons.blocks, size: 18, color: Colors.cyanAccent),
                  const SizedBox(width: 10),
                  Text(
                    'Инструменты разработчика',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Дополнительные утилиты вынесены сюда, чтобы рабочий стол оставался чистым и удобным.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 14),
              ...tools.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: t.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: t.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(t.icon, color: t.color, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.subtitle,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(LucideIcons.chevron_right, size: 15, color: Colors.white38),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsAdaptive(BuildContext context) {
    final theme = Theme.of(context);
    final primaryActions = [
      (
        icon: LucideIcons.plus,
        label: AppLocalizations.of(context)!.createProject,
        subtitle: 'Flutter, Android, Web, Python',
        color: theme.colorScheme.primary,
        onTap: () => _showProjectDialog(context, ref),
      ),
      (
        icon: LucideIcons.folder_open,
        label: AppLocalizations.of(context)!.open,
        subtitle: 'Открыть готовую папку',
        color: Colors.cyanAccent,
        onTap: () => _importAndOpenProject(context, ref),
      ),
      (
        icon: LucideIcons.git_branch,
        label: 'Git и GitHub',
        subtitle: 'Клонировать репозиторий',
        color: Colors.purpleAccent,
        onTap: () => context.push('/github'),
      ),
      (
        icon: LucideIcons.terminal,
        label: AppLocalizations.of(context)!.terminal,
        subtitle: 'Консоль Linux и сборка',
        color: const Color(0xFF10B981),
        onTap: () => context.push('/terminal'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 680 ? 4 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: primaryActions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 68,
              ),
              itemBuilder: (context, index) {
                final item = primaryActions[index];
                return InkWell(
                  onTap: item.onTap,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.025),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: item.color.withValues(alpha: 0.22), width: 0.9),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(item.icon, color: item.color, size: 19),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showDeveloperToolsSheet(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.015),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.blocks, size: 14, color: Colors.cyanAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Дополнительные инструменты: Пакеты и SDK, SQLite, SFTP, Серверы, DevTools, ИИ-песочница',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
                  ),
                ),
                const Icon(LucideIcons.chevron_right, size: 14, color: Colors.white38),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectsHeader(int count, {bool hasAnyProjects = true}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Text(
            AppLocalizations.of(context)!.projectsHeader(count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (Platform.isAndroid && hasAnyProjects)
          _isExportingAllToSd
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Обновить проекты на SD-карте',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.hard_drive_upload, size: 18, color: muted),
                  onPressed: _exportAllToSdCard,
                ),
        IconButton(
          tooltip: _sortByName ? 'Сортировка: по имени' : 'Сортировка: по дате',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            _sortByName ? LucideIcons.arrow_down_a_z : LucideIcons.list_filter,
            size: 18,
            color: muted,
          ),
          onPressed: () => setState(() => _sortByName = !_sortByName),
        ),
      ],
    );
  }

  Widget _buildMobileQuickActionsBar(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final actions = <({IconData icon, String label, Color color, VoidCallback onTap})>[
      (
        icon: LucideIcons.plus,
        label: l10n.createProject,
        color: theme.colorScheme.primary,
        onTap: () => _showProjectDialog(context, ref),
      ),
      (
        icon: LucideIcons.folder_open,
        label: l10n.open,
        color: Colors.cyanAccent,
        onTap: () => _importAndOpenProject(context, ref),
      ),
      (
        icon: LucideIcons.git_branch,
        label: 'Git',
        color: Colors.purpleAccent,
        onTap: () => context.push('/github'),
      ),
      (
        icon: LucideIcons.terminal,
        label: l10n.terminal,
        color: const Color(0xFF10B981),
        onTap: () => context.push('/terminal'),
      ),
      (
        icon: LucideIcons.blocks,
        label: 'Ещё',
        color: theme.colorScheme.onSurfaceVariant,
        onTap: () => _showDeveloperToolsSheet(context),
      ),
    ];
    return Row(
      children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(a.icon, color: a.color, size: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompactSystemMonitorChip(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final stats = ref.watch(systemStatsProvider);
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.activity, size: 14, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'CPU ${stats.cpuUsage.toStringAsFixed(0)}%  ·  RAM ${stats.ramUsage.toStringAsFixed(0)}%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectCard(BuildContext context, WidgetRef ref, Project project) {
    final lastModified = project.lastOpened;
    final dateStr = '${lastModified.day}.${lastModified.month}.${lastModified.year}';
    final theme = Theme.of(context);

    return Dismissible(
      key: Key(project.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(LucideIcons.trash_2, color: Colors.redAccent),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref, project),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await ref.read(workspaceProvider.notifier).setWorkspace(project.path);
                if (context.mounted) context.go('/editor');
              },
              onLongPress: () => _showProjectActions(context, ref, project),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            project.color.withValues(alpha: 0.2),
                            project.color.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: project.color.withValues(alpha: 0.3)),
                      ),
                      child: project.appIconPath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(project.appIconPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(project.icon, color: project.color, size: 18),
                              ),
                            )
                          : Icon(project.icon, color: project.color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${project.type.name.toUpperCase()} • $dateStr',
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            project.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                              fontSize: 9.5,
                            ),
                          ),
                          if (project.platforms != null && project.platforms!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 3,
                              runSpacing: 3,
                              children: project.platforms!.map((plat) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: project.color.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: project.color.withValues(alpha: 0.15)),
                                  ),
                                  child: Text(
                                    plat.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      color: project.color,
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ]
                        ],
                      ),
                    ),
                    if (PlatformUtils.isDesktop)
                      IconButton(
                        tooltip: 'Открыть папку в файловом менеджере',
                        icon: Icon(
                          LucideIcons.folder_open,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                        ),
                        onPressed: () => PlatformUtils.openInFileManager(project.path),
                      ),
                    Icon(LucideIcons.chevron_right, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 14),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Показывает меню действий для проекта (долгое нажатие).
  void _showProjectActions(BuildContext context, WidgetRef ref, Project project) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            // Project title
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: project.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: project.color.withValues(alpha: 0.3)),
                  ),
                  child: project.appIconPath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(
                            File(project.appIconPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Icon(project.icon, color: project.color, size: 22),
                          ),
                        )
                      : Icon(project.icon, color: project.color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.name,
                        style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                      Row(
                        children: [
                          Text(project.type.name.toUpperCase(),
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                          if (project.platforms != null && project.platforms!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text('•', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                project.platforms!.join(', ').toUpperCase(),
                                style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        project.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.1), height: 1),
            const SizedBox(height: 12),

            // Action: Open
            _buildActionTile(
              icon: LucideIcons.folder_open,
              label: AppLocalizations.of(context)!.open,
              color: theme.colorScheme.primary,
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(workspaceProvider.notifier).setWorkspace(project.path);
                if (context.mounted) context.go('/editor');
              },
            ),

            if (PlatformUtils.isDesktop)
              _buildActionTile(
                icon: LucideIcons.external_link,
                label: 'Показать в файловом менеджере',
                sublabel: project.path,
                color: Colors.cyanAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  PlatformUtils.openInFileManager(project.path);
                },
              ),

            // Action: Fix Android Build (only for Flutter)
            if (project.type == ProjectType.flutter) ...[
              _buildActionTile(
                icon: LucideIcons.wrench,
                label: AppLocalizations.of(context)!.fixAndroidBuild,
                sublabel: AppLocalizations.of(context)!.patchAndroidBuildDescription,
                color: Colors.orangeAccent,
                onTap: () async {
                  Navigator.pop(ctx);
                  // Patch build files via Dart
                  await ref.read(projectServiceProvider.notifier).patchExistingProject(project);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.apkBuildFixed(project.name),
                          style: GoogleFonts.inter()),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                },
              ),

              // Action: Build APK
              _buildActionTile(
                icon: LucideIcons.package,
                label: AppLocalizations.of(context)!.buildApk,
                sublabel: AppLocalizations.of(context)!.buildApkDescription,
                color: Colors.tealAccent,
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(projectServiceProvider.notifier).buildProject(project);
                  context.push('/terminal');
                },
              ),
            ],

            // Action: Settings/Rename
            _buildActionTile(
              icon: LucideIcons.settings_2,
              label: AppLocalizations.of(context)!.settings,
              color: theme.colorScheme.onSurfaceVariant,
              onTap: () {
                Navigator.pop(ctx);
                _showProjectDialog(context, ref, project: project);
              },
            ),

            // Action: Delete
            _buildActionTile(
              icon: LucideIcons.trash_2,
              label: AppLocalizations.of(context)!.delete,
              color: Colors.redAccent,
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await _confirmDelete(context, ref, project);
                if (confirmed == true && context.mounted) {
                  // Already handled inside _confirmDelete
                }
              },
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    String? sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
                  if (sublabel != null)
                    Text(sublabel, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref, Project project) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(context)!.confirmDeleteTitle(project.name), style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Text(AppLocalizations.of(context)!.confirmDeleteMessage, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () { ref.read(projectServiceProvider.notifier).removeProject(project.id, deleteFiles: false); Navigator.pop(ctx, true); },
            child: Text(AppLocalizations.of(context)!.deleteFromListOnly),
          ),
          ElevatedButton(
            onPressed: () { ref.read(projectServiceProvider.notifier).removeProject(project.id, deleteFiles: true); Navigator.pop(ctx, true); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.2), foregroundColor: Colors.redAccent),
            child: Text(AppLocalizations.of(context)!.deleteFromDisk),
          ),
        ],
      ),
    );
  }


  String _sanitizePackageSegment(String raw) {
    var s = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9_]+"), "_")
        .replaceAll(RegExp(r"_+"), "_")
        .replaceAll(RegExp(r"^_+|_+\$"), "");
    if (s.isEmpty) return "app";
    if (RegExp(r"^[0-9]").hasMatch(s)) s = "app_\$s";
    return s;
  }

  void _showProjectDialog(BuildContext context, WidgetRef ref, {Project? project}) async {
    final isEdit = project != null;
    final nameCtrl = TextEditingController(text: project?.name ?? "");
    final orgCtrl = TextEditingController(text: "com.example");
    final initialPkg = (project != null)
        ? "\${orgCtrl.text}.\${_sanitizePackageSegment(project.name)}"
        : "com.example.app";
    final packageCtrl = TextEditingController(text: initialPkg);
    final locationCtrl = TextEditingController(
      text: project != null ? p.dirname(project.path) : PlatformUtils.defaultDesktopProjectsDir,
    );
    ProjectType selectedType = project?.type ?? ProjectType.flutter;
    String selectedCompileSdk =
        (project?.sdkVersion != null && int.tryParse(project!.sdkVersion!) != null)
            ? project.sdkVersion!
            : "35";
    String selectedMinSdk = "24";
    const availablePlatforms = ["android", "ios", "web", "windows", "macos", "linux"];
    final List<String> selectedPlatforms = List<String>.from(
      (project?.platforms != null && project!.platforms!.isNotEmpty)
          ? project.platforms!
          : const ["android"],
    );
    bool packageEditedManually = false;
    bool isCreating = false;
    String? creationError;

    void syncPackageFromNameAndOrg() {
      if (packageEditedManually) return;
      final org = orgCtrl.text
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r"[^a-z0-9._]"), "")
          .replaceAll(RegExp(r"^\.+|\.+\$"), "");
      final baseOrg = org.isEmpty ? "com.example" : org;
      final seg = _sanitizePackageSegment(nameCtrl.text);
      packageCtrl.text = "\$baseOrg.\$seg";
    }

    final projectTemplates = [
      (
        type: ProjectType.flutter,
        title: "Flutter App",
        subtitle: "Android, iOS, Web и Desktop на Dart",
        icon: LucideIcons.smartphone,
        color: const Color(0xFF38BDF8),
        badge: "Flutter",
      ),
      (
        type: ProjectType.androidKotlin,
        title: "Android (Kotlin)",
        subtitle: "Нативное Android-приложение (Kotlin + Gradle)",
        icon: LucideIcons.layers,
        color: const Color(0xFF7F52FF),
        badge: "Kotlin",
      ),
      (
        type: ProjectType.androidJava,
        title: "Android (Java)",
        subtitle: "Нативное Android-приложение (Java + Gradle)",
        icon: LucideIcons.coffee,
        color: const Color(0xFFF89820),
        badge: "Java",
      ),
      (
        type: ProjectType.web,
        title: "Web / Frontend",
        subtitle: "HTML5, CSS3, JavaScript / Vite",
        icon: LucideIcons.globe,
        color: const Color(0xFF00D8FF),
        badge: "Web",
      ),
      (
        type: ProjectType.nodejs,
        title: "Node.js Backend",
        subtitle: "REST API, Express и npm",
        icon: LucideIcons.server,
        color: const Color(0xFF68A063),
        badge: "Node",
      ),
      (
        type: ProjectType.python,
        title: "Python Project",
        subtitle: "Скрипты, FastAPI, автоматизация и AI",
        icon: LucideIcons.terminal,
        color: const Color(0xFFFFD43B),
        badge: "Python",
      ),
      (
        type: ProjectType.rust,
        title: "Rust Binary",
        subtitle: "Системный код на Cargo / Rust",
        icon: LucideIcons.cpu,
        color: const Color(0xFFDEA584),
        badge: "Rust",
      ),
    ];

    Widget buildForm(BuildContext ctx, StateSetter setState, {required bool isWide}) {
      final theme = Theme.of(ctx);
      final l10n = AppLocalizations.of(ctx)!;
      final isMobileTemplate = selectedType == ProjectType.flutter ||
          selectedType == ProjectType.androidKotlin ||
          selectedType == ProjectType.androidJava;
      final isNativeAndroid = selectedType == ProjectType.androidKotlin ||
          selectedType == ProjectType.androidJava;

      InputDecoration fieldDeco(String hint, {Widget? prefixIcon}) => InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 13.5,
            ),
            prefixIcon: prefixIcon,
            filled: true,
            fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.045),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            isDense: true,
          );

      Widget sectionLabel(String text) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
          );

      Future<void> handleSubmit() async {
        final rawName = nameCtrl.text.trim();
        if (rawName.isEmpty) {
          setState(() => creationError = "Введите название проекта");
          return;
        }
        setState(() {
          isCreating = true;
          creationError = null;
        });
        try {
          if (isEdit) {
            await ref.read(projectServiceProvider.notifier).saveProject(
                  Project(
                    id: project.id,
                    name: rawName,
                    path: project.path,
                    type: project.type,
                    lastOpened: project.lastOpened,
                    isInternal: project.isInternal,
                    platforms: project.platforms,
                    sdkVersion: project.sdkVersion,
                  ),
                );
          } else {
            final newProj = await ref.read(projectServiceProvider.notifier).createProject(
                  name: rawName,
                  path: PlatformUtils.isDesktop ? locationCtrl.text.trim() : "",
                  type: selectedType,
                  platforms: selectedType == ProjectType.flutter ? selectedPlatforms : null,
                  sdkVersion: isMobileTemplate ? selectedCompileSdk : null,
                  packageName: isMobileTemplate ? packageCtrl.text.trim() : null,
                  minSdk: isNativeAndroid ? selectedMinSdk : null,
                );
            await ref.read(workspaceProvider.notifier).setWorkspace(newProj.path);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) context.go("/editor");
            return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
        } catch (e) {
          setState(() {
            isCreating = false;
            creationError = e.toString();
          });
        }
      }

      final templateColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionLabel("ТИП ПРОЕКТА"),
          ...projectTemplates.map((t) {
            final isSel = selectedType == t.type;
            return InkWell(
              onTap: isEdit ? null : () => setState(() => selectedType = t.type),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSel
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSel
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                    width: isSel ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: t.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(t.icon, size: 17, color: t.color),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  t.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: t.color.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  t.badge,
                                  style: GoogleFonts.inter(
                                    color: t.color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isSel ? LucideIcons.circle_check : LucideIcons.circle,
                      size: 17,
                      color: isSel
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      );

      final paramsColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionLabel("НАЗВАНИЕ ПРОЕКТА"),
          TextField(
            controller: nameCtrl,
            autofocus: !isEdit,
            onChanged: (_) {
              syncPackageFromNameAndOrg();
              setState(() => creationError = null);
            },
            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14.5),
            decoration: fieldDeco(
              l10n.projectName,
              prefixIcon: Icon(LucideIcons.folder_plus, size: 17, color: theme.colorScheme.primary),
            ),
          ),
          if (!isEdit && PlatformUtils.isDesktop) ...[
            const SizedBox(height: 14),
            sectionLabel("ПАПКА РАСПОЛОЖЕНИЯ"),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: locationCtrl,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.jetBrainsMono(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                    ),
                    decoration: fieldDeco(PlatformUtils.defaultDesktopProjectsDir),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: "Выбрать папку",
                  onPressed: () async {
                    final picked = await FilePicker.getDirectoryPath(
                      initialDirectory: locationCtrl.text.trim(),
                    );
                    if (picked != null) {
                      setState(() => locationCtrl.text = picked);
                    }
                  },
                  icon: const Icon(LucideIcons.folder_open, size: 17),
                ),
              ],
            ),
          ],
          if (!isEdit && isMobileTemplate) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionLabel("ДОМЕН (ORG)"),
                      TextField(
                        controller: orgCtrl,
                        onChanged: (_) {
                          syncPackageFromNameAndOrg();
                          setState(() {});
                        },
                        style: GoogleFonts.jetBrainsMono(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12.5,
                        ),
                        decoration: fieldDeco("com.example"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionLabel("APPLICATION ID / PACKAGE"),
                      TextField(
                        controller: packageCtrl,
                        onChanged: (_) {
                          packageEditedManually = true;
                          setState(() {});
                        },
                        style: GoogleFonts.jetBrainsMono(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12.5,
                        ),
                        decoration: fieldDeco("com.example.app"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionLabel("COMPILE SDK"),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ["34", "35", "36"].map((sdk) {
                          final sel = selectedCompileSdk == sdk;
                          return ChoiceChip(
                            label: Text("API \$sdk", style: const TextStyle(fontSize: 11.5)),
                            selected: sel,
                            onSelected: (_) => setState(() => selectedCompileSdk = sdk),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                if (isNativeAndroid) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionLabel("MIN SDK"),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: ["21", "24", "26"].map((sdk) {
                            final sel = selectedMinSdk == sdk;
                            return ChoiceChip(
                              label: Text("API \$sdk", style: const TextStyle(fontSize: 11.5)),
                              selected: sel,
                              onSelected: (_) => setState(() => selectedMinSdk = sdk),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (!isEdit && selectedType == ProjectType.flutter) ...[
            const SizedBox(height: 14),
            sectionLabel("ЦЕЛЕВЫЕ ПЛАТФОРМЫ"),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: availablePlatforms.map((plat) {
                final isSel = selectedPlatforms.contains(plat);
                return FilterChip(
                  label: Text(plat.toUpperCase(), style: const TextStyle(fontSize: 11)),
                  selected: isSel,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        if (!selectedPlatforms.contains(plat)) selectedPlatforms.add(plat);
                      } else if (selectedPlatforms.length > 1) {
                        selectedPlatforms.remove(plat);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
          if (creationError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Text(
                creationError!,
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ],
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isEdit ? l10n.projectSettings : l10n.createProject,
                  style: GoogleFonts.inter(
                    fontSize: isWide ? 20 : 18,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: paramsColumn),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: templateColumn),
              ],
            )
          else ...[
            paramsColumn,
            if (!isEdit) ...[
              const SizedBox(height: 18),
              templateColumn,
            ],
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: isCreating ? null : handleSubmit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isEdit ? l10n.saveAction : l10n.createProject,
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 720;
    final theme = Theme.of(context);
    if (isWide) {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Dialog(
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: buildForm(ctx, setState, isWide: true),
              ),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: buildForm(ctx, setState, isWide: false),
            ),
          ),
        ),
      );
    }
  }
}
