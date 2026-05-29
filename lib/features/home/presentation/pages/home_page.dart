import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/models/project_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/services/system_stats_service.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(workspaceProvider).currentPath != null) {
        ref.read(workspaceProvider.notifier).closeWorkspace();
      }
      ref.read(editorProvider.notifier).clearWorkspace();
      ref.read(terminalTabsProvider.notifier).closeAllSessions();
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
    final projects = allProjects.where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    
    final lastProject = projects.isNotEmpty 
        ? (List<Project>.from(projects)..sort((a, b) => b.lastOpened.compareTo(a.lastOpened))).first 
        : null;
        
    final otherProjects = lastProject != null && _searchQuery.isEmpty
        ? projects.where((p) => p.id != lastProject.id).toList()
        : projects;
        
    final isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      return _buildDesktopHome(context, projects, lastProject, otherProjects);
    } else {
      return _buildMobileHome(context, projects, lastProject, otherProjects);
    }
  }

  Widget _buildMobileHome(BuildContext context, List<Project> projects, Project? lastProject, List<Project> otherProjects) {
    final theme = Theme.of(context);
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
                          theme.colorScheme.primary.withValues(alpha: 0.12),
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
                          Colors.purpleAccent.withValues(alpha: 0.08),
                          Colors.purpleAccent.withValues(alpha: 0.0),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 10),
                      _buildSearchField(),
                      const SizedBox(height: 14),
                      if (lastProject != null && _searchQuery.isEmpty) ...[
                        _buildResumeCard(context, lastProject),
                      ],
                      _buildQuickActionsRow(context),
                      const SizedBox(height: 14),
                      _buildSystemMonitor(context),
                      const SizedBox(height: 20),
                      if (otherProjects.isNotEmpty) ...[
                        _buildProjectsHeader(otherProjects.length),
                        const SizedBox(height: 10),
                      ],
                    ]),
                  ),
                ),
                if (projects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.folder_search, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? AppLocalizations.of(context)!.noProjects : AppLocalizations.of(context)!.nothingFound,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 16),
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
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else if (otherProjects.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildProjectCard(context, ref, otherProjects[index]),
                        childCount: otherProjects.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProjectDialog(context, ref),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        child: const Icon(LucideIcons.plus),
      ),
    );
  }

  Widget _buildDesktopHome(BuildContext context, List<Project> projects, Project? lastProject, List<Project> otherProjects) {
    final theme = Theme.of(context);
    final stats = ref.watch(systemStatsProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.015),
              border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
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
                        child: const Icon(LucideIcons.terminal, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Quantum IDE',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
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
                        color: theme.colorScheme.secondary,
                        onTap: () async {
                          final dir = await FilePicker.getDirectoryPath();
                          if (dir != null) {
                            await ref.read(projectServiceProvider.notifier).importProject(dir);
                          }
                        },
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.terminal,
                        label: AppLocalizations.of(context)!.terminal,
                        color: theme.colorScheme.tertiary,
                        onTap: () => context.push('/terminal'),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.layout_dashboard,
                        label: AppLocalizations.of(context)!.market,
                        color: Colors.pinkAccent,
                        onTap: () => context.push('/packages'),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.server,
                        label: AppLocalizations.of(context)!.servers,
                        color: theme.colorScheme.error,
                        onTap: () => context.push('/servers'),
                      ),
                      _buildSidebarItem(
                        icon: LucideIcons.settings,
                        label: 'Настройки',
                        color: theme.colorScheme.onSurfaceVariant,
                        onTap: () => context.push('/settings'),
                      ),
                    ],
                  ),
                ),
                
                // System Telemetry
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.01),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6, height: 6,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'TELEMETRY',
                              style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white38),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('CPU', style: GoogleFonts.inter(color: Colors.white60, fontSize: 10)),
                            Text('${(stats.cpuUsage * 100).toStringAsFixed(0)}%', style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: stats.cpuUsage, minHeight: 2, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('RAM', style: GoogleFonts.inter(color: Colors.white60, fontSize: 10)),
                            Text('${stats.ramUsedGB.toStringAsFixed(1)} GB', style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(value: stats.ramUsage, minHeight: 2, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(Colors.purpleAccent)),
                      ],
                    ),
                  ),
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
                  padding: const EdgeInsets.all(32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Добро пожаловать!',
                                style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -0.5),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Выберите проект для работы или создайте новый',
                                style: GoogleFonts.inter(fontSize: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: 320,
                            child: _buildSearchField(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (lastProject != null && _searchQuery.isEmpty) ...[
                        Text(
                          'Последний активный проект',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        _buildResumeCard(context, lastProject),
                        const SizedBox(height: 24),
                      ],
                      if (projects.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.projectsHeader(projects.length),
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ]),
                  ),
                ),
                
                if (projects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.folder_search, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? AppLocalizations.of(context)!.noProjects : AppLocalizations.of(context)!.nothingFound,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 16),
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
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 320,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.4,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildDesktopProjectCard(context, ref, projects[index]),
                        childCount: projects.length,
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
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.015),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                await ref.read(workspaceProvider.notifier).setWorkspace(project.path);
                if (context.mounted) context.push('/editor');
              },
              onLongPress: () => _showProjectActions(context, ref, project),
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
                        IconButton(
                          icon: const Icon(LucideIcons.play, size: 14, color: Colors.greenAccent),
                          tooltip: 'Запустить',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            ref.read(projectServiceProvider.notifier).runProject(project);
                            context.push('/terminal');
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(LucideIcons.ellipsis_vertical, size: 14),
                          tooltip: 'Действия',
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
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          project.type.name.toUpperCase(),
                          style: GoogleFonts.inter(color: theme.colorScheme.primary.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dateStr,
                          style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4), fontSize: 10),
                        ),
                      ],
                    ),
                    if (project.platforms != null && project.platforms!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: project.platforms!.take(4).map((plat) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: project.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: project.color.withValues(alpha: 0.15)),
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
                    ]
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
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 12),
        centerTitle: false,
        title: Text(
          'Quantum IDE',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
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
          icon: LucideIcons.package,
          tooltip: 'Пакеты',
          onTap: () => context.push('/packages'),
        ),
        _buildAppActionButton(
          icon: LucideIcons.settings,
          tooltip: 'Настройки',
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
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, color: theme.colorScheme.onSurface.withValues(alpha: 0.7), size: 16),
        onPressed: onTap,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
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
              if (context.mounted) context.push('/editor');
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
          const SizedBox(height: 10),
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
                          children: [
                            const Icon(LucideIcons.cpu, size: 12, color: Colors.cyanAccent),
                            const SizedBox(width: 4),
                            Text(
                              'CPU',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Text(
                          '${(stats.cpuUsage * 100).toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
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
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.memory_stick, size: 12, color: Colors.purpleAccent),
                            const SizedBox(width: 4),
                            Text(
                              'RAM',
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Text(
                          '${stats.ramUsedGB.toStringAsFixed(1)} GB',
                          style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
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

  Widget _buildQuickActionsRow(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _buildActionItem(
          icon: LucideIcons.folder_open,
          label: AppLocalizations.of(context)!.open,
          color: theme.colorScheme.primary,
          onTap: () async {
            final dir = await FilePicker.getDirectoryPath();
            if (dir != null) {
              await ref.read(projectServiceProvider.notifier).importProject(dir);
            }
          },
        ),
        _buildActionItem(
          icon: LucideIcons.terminal,
          label: AppLocalizations.of(context)!.terminal,
          color: theme.colorScheme.secondary,
          onTap: () => context.push('/terminal'),
        ),
        _buildActionItem(
          icon: LucideIcons.layout_dashboard,
          label: AppLocalizations.of(context)!.market,
          color: theme.colorScheme.tertiary,
          onTap: () => context.push('/packages'),
        ),
        _buildActionItem(
          icon: LucideIcons.server,
          label: AppLocalizations.of(context)!.servers,
          color: theme.colorScheme.error,
          onTap: () => context.push('/servers'),
        ),
      ],
    );
  }

  Widget _buildActionItem({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 0.8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(color: theme.colorScheme.onSurface.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectsHeader(int count) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          AppLocalizations.of(context)!.projectsHeader(count),
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        Icon(LucideIcons.list_filter, size: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      ],
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
                if (context.mounted) context.push('/editor');
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
      builder: (ctx) => Container(
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
                if (context.mounted) context.push('/editor');
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


  void _showProjectDialog(BuildContext context, WidgetRef ref, {Project? project}) async {
    final isEdit = project != null;
    final nameCtrl = TextEditingController(text: project?.name);
    ProjectType selectedType = project?.type ?? ProjectType.flutter;
    final theme = Theme.of(context);

    // Flutter-specific configurations
    final sdkCtrl = TextEditingController(text: (project?.type == ProjectType.androidJava || project?.type == ProjectType.androidKotlin) ? (project?.sdkVersion ?? 'com.example.app') : '35');
    final List<String> availablePlatforms = ['android', 'ios', 'web', 'windows', 'macos', 'linux'];
    final List<String> selectedPlatforms = ['android'];

    int? selectedColorValue = project?.colorValue;
    int? selectedIconCodePoint = project?.iconCodePoint;
    String? selectedIconFontFamily = project?.iconFontFamily;
    String? selectedIconFontPackage = project?.iconFontPackage;

    final List<IconData> selectableIcons = [
      LucideIcons.folder,
      LucideIcons.folder_open,
      LucideIcons.folder_search,
      LucideIcons.folder_heart,
      LucideIcons.folder_git,
      LucideIcons.folder_code,
      LucideIcons.smartphone,
      LucideIcons.code,
      LucideIcons.terminal,
      LucideIcons.globe,
      LucideIcons.server,
      LucideIcons.database,
      LucideIcons.cpu,
      LucideIcons.palette,
      LucideIcons.layers,
      LucideIcons.puzzle,
      LucideIcons.gamepad_2,
      LucideIcons.cloud,
      LucideIcons.flame,
      LucideIcons.heart,
      LucideIcons.star,
    ];

    final List<Color> selectableColors = [
      const Color(0xFFE57373),
      const Color(0xFFF06292),
      const Color(0xFFBA68C8),
      const Color(0xFF9575CD),
      const Color(0xFF7986CB),
      const Color(0xFF64B5F6),
      const Color(0xFF4FC3F7),
      const Color(0xFF4DD0E1),
      const Color(0xFF4DB6AC),
      const Color(0xFF81C784),
      const Color(0xFFAED581),
      const Color(0xFFD4E157),
      const Color(0xFFFFD54F),
    ];
    final isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 760,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 32,
                    spreadRadius: 4,
                  )
                ],
              ),
              padding: const EdgeInsets.all(28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEdit ? AppLocalizations.of(context)!.projectSettings : AppLocalizations.of(context)!.createProject,
                          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: nameCtrl,
                                autofocus: !isEdit,
                                style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 15),
                                decoration: InputDecoration(
                                  hintText: AppLocalizations.of(context)!.projectName,
                                  hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                  filled: true,
                                  fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                              ),
                              if (!isEdit) ...[
                                const SizedBox(height: 24),
                                Text(AppLocalizations.of(context)!.projectType, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: ProjectType.values.where((type) => type != ProjectType.dart && type != ProjectType.shell && type != ProjectType.other).map((type) {
                                    final isSelected = selectedType == type;
                                    return GestureDetector(
                                      onTap: () => setState(() {
                                        final oldType = selectedType;
                                        selectedType = type;
                                        if ((type == ProjectType.androidJava || type == ProjectType.androidKotlin) && 
                                            (oldType == ProjectType.flutter || sdkCtrl.text == '35')) {
                                          sdkCtrl.text = 'com.example.${nameCtrl.text.isEmpty ? 'app' : nameCtrl.text.toLowerCase().replaceAll('-', '_')}';
                                        } else if (type == ProjectType.flutter && 
                                                   (oldType == ProjectType.androidJava || oldType == ProjectType.androidKotlin || sdkCtrl.text.contains('.'))) {
                                          sdkCtrl.text = '35';
                                        }
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: isSelected ? theme.colorScheme.primary : Colors.transparent),
                                        ),
                                        child: Text(
                                          type.name.toUpperCase(),
                                          style: GoogleFonts.inter(color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                if (selectedType == ProjectType.flutter) ...[
                                  const SizedBox(height: 24),
                                  Text(AppLocalizations.of(context)!.androidCompileSdkVersion, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: sdkCtrl,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(context)!.defaultSdkVersion,
                                      hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                      filled: true,
                                      fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(AppLocalizations.of(context)!.targetPlatforms, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: availablePlatforms.map((platform) {
                                      final isPlatSelected = selectedPlatforms.contains(platform);
                                      return GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            if (isPlatSelected) {
                                              if (selectedPlatforms.length > 1) {
                                                selectedPlatforms.remove(platform);
                                              }
                                            } else {
                                              selectedPlatforms.add(platform);
                                            }
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isPlatSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: isPlatSelected ? theme.colorScheme.primary : Colors.transparent),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isPlatSelected ? LucideIcons.circle_check : LucideIcons.circle,
                                                size: 14,
                                                color: isPlatSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                platform.toUpperCase(),
                                                style: GoogleFonts.inter(color: isPlatSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                if (selectedType == ProjectType.androidJava || selectedType == ProjectType.androidKotlin) ...[
                                  const SizedBox(height: 24),
                                  Text("PACKAGE NAME (APPLICATION ID)", style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: sdkCtrl,
                                    keyboardType: TextInputType.text,
                                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
                                    decoration: InputDecoration(
                                      hintText: "e.g. com.example.myapp",
                                      hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                      filled: true,
                                      fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        // Right column
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppLocalizations.of(context)!.accentColor, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => selectedColorValue = null),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                                        border: Border.all(
                                          color: selectedColorValue == null ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                                          width: selectedColorValue == null ? 2 : 1,
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.ban,
                                          size: 14,
                                          color: selectedColorValue == null ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...selectableColors.map((color) {
                                    final isSelected = selectedColorValue == color.toARGB32();
                                    return GestureDetector(
                                      onTap: () => setState(() => selectedColorValue = color.toARGB32()),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: color,
                                          border: Border.all(
                                            color: isSelected ? Colors.white : Colors.transparent,
                                            width: isSelected ? 2 : 0,
                                          ),
                                        ),
                                        child: isSelected ? const Center(
                                          child: Icon(LucideIcons.check, color: Colors.white, size: 14),
                                        ) : null,
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Text(AppLocalizations.of(context)!.projectIcon, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      selectedIconCodePoint = null;
                                      selectedIconFontFamily = null;
                                      selectedIconFontPackage = null;
                                    }),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                                        border: Border.all(
                                          color: selectedIconCodePoint == null ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                                          width: selectedIconCodePoint == null ? 2 : 1,
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.ban,
                                          size: 14,
                                          color: selectedIconCodePoint == null ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...selectableIcons.map((icon) {
                                    final isSelected = selectedIconCodePoint == icon.codePoint;
                                    return GestureDetector(
                                      onTap: () => setState(() {
                                        selectedIconCodePoint = icon.codePoint;
                                        selectedIconFontFamily = icon.fontFamily;
                                        selectedIconFontPackage = icon.fontPackage;
                                      }),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                                          border: Border.all(
                                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                                            width: isSelected ? 2 : 1,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            icon,
                                            size: 16,
                                            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Отмена'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            if (nameCtrl.text.isEmpty) return;
                            if (isEdit) {
                              await ref.read(projectServiceProvider.notifier).saveProject(Project(
                                id: project.id,
                                name: nameCtrl.text,
                                path: project.path,
                                type: project.type,
                                lastOpened: project.lastOpened,
                                isInternal: project.isInternal,
                                colorValue: selectedColorValue,
                                iconCodePoint: selectedIconCodePoint,
                                iconFontFamily: selectedIconFontFamily,
                                iconFontPackage: selectedIconFontPackage,
                                platforms: project.platforms,
                                sdkVersion: project.sdkVersion,
                              ));
                            } else {
                              await ref.read(projectServiceProvider.notifier).createProject(
                                name: nameCtrl.text,
                                path: '',
                                type: selectedType,
                                iconCodePoint: selectedIconCodePoint,
                                colorValue: selectedColorValue,
                                iconFontFamily: selectedIconFontFamily,
                                iconFontPackage: selectedIconFontPackage,
                                platforms: selectedType == ProjectType.flutter ? selectedPlatforms : null,
                                sdkVersion: (selectedType == ProjectType.flutter || selectedType == ProjectType.androidJava || selectedType == ProjectType.androidKotlin) ? sdkCtrl.text.trim() : null,
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(isEdit ? AppLocalizations.of(context)!.saveAction : AppLocalizations.of(context)!.createProject, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(color: theme.colorScheme.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isEdit ? AppLocalizations.of(context)!.projectSettings : AppLocalizations.of(context)!.createProject,
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameCtrl,
                    autofocus: !isEdit,
                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.projectName,
                      hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  if (!isEdit) ...[
                    const SizedBox(height: 24),
                    Text(AppLocalizations.of(context)!.projectType, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ProjectType.values.where((type) => type != ProjectType.dart && type != ProjectType.shell && type != ProjectType.other).map((type) {
                        final isSelected = selectedType == type;
                        return GestureDetector(
                          onTap: () => setState(() {
                            final oldType = selectedType;
                            selectedType = type;
                            if ((type == ProjectType.androidJava || type == ProjectType.androidKotlin) && 
                                (oldType == ProjectType.flutter || sdkCtrl.text == '35')) {
                              sdkCtrl.text = 'com.example.${nameCtrl.text.isEmpty ? 'app' : nameCtrl.text.toLowerCase().replaceAll('-', '_')}';
                            } else if (type == ProjectType.flutter && 
                                       (oldType == ProjectType.androidJava || oldType == ProjectType.androidKotlin || sdkCtrl.text.contains('.'))) {
                              sdkCtrl.text = '35';
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isSelected ? theme.colorScheme.primary : Colors.transparent),
                            ),
                            child: Text(
                              type.name.toUpperCase(),
                              style: GoogleFonts.inter(color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedType == ProjectType.flutter) ...[
                      const SizedBox(height: 24),
                      Text(AppLocalizations.of(context)!.androidCompileSdkVersion, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sdkCtrl,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.defaultSdkVersion,
                          hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(AppLocalizations.of(context)!.targetPlatforms, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: availablePlatforms.map((platform) {
                          final isPlatSelected = selectedPlatforms.contains(platform);
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isPlatSelected) {
                                  if (selectedPlatforms.length > 1) {
                                    selectedPlatforms.remove(platform);
                                  }
                                } else {
                                  selectedPlatforms.add(platform);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isPlatSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isPlatSelected ? theme.colorScheme.primary : Colors.transparent),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPlatSelected ? LucideIcons.circle_check : LucideIcons.circle,
                                    size: 14,
                                    color: isPlatSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    platform.toUpperCase(),
                                    style: GoogleFonts.inter(color: isPlatSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (selectedType == ProjectType.androidJava || selectedType == ProjectType.androidKotlin) ...[
                      const SizedBox(height: 24),
                      Text("PACKAGE NAME (APPLICATION ID)", style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: sdkCtrl,
                        keyboardType: TextInputType.text,
                        style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "e.g. com.example.myapp",
                          hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Text(AppLocalizations.of(context)!.accentColor, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: selectableColors.length + 1,
                      separatorBuilder: (context, index) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          final isSelected = selectedColorValue == null;
                          return GestureDetector(
                            onTap: () => setState(() => selectedColorValue = null),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  LucideIcons.ban,
                                  size: 16,
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }
                        final color = selectableColors[index - 1];
                        final isSelected = selectedColorValue == color.toARGB32();
                        return GestureDetector(
                          onTap: () => setState(() => selectedColorValue = color.toARGB32()),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: isSelected ? 3 : 0,
                              ),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                )
                              ] : null,
                            ),
                            child: isSelected ? const Center(
                              child: Icon(LucideIcons.check, color: Colors.white, size: 18),
                            ) : null,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(AppLocalizations.of(context)!.projectIcon, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: selectableIcons.length + 1,
                      separatorBuilder: (context, index) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          final isSelected = selectedIconCodePoint == null;
                          return GestureDetector(
                            onTap: () => setState(() {
                              selectedIconCodePoint = null;
                              selectedIconFontFamily = null;
                              selectedIconFontPackage = null;
                            }),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  LucideIcons.ban,
                                  size: 16,
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }
                        final icon = selectableIcons[index - 1];
                        final isSelected = selectedIconCodePoint == icon.codePoint;
                        return GestureDetector(
                          onTap: () => setState(() {
                            selectedIconCodePoint = icon.codePoint;
                            selectedIconFontFamily = icon.fontFamily;
                            selectedIconFontPackage = icon.fontPackage;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.colorScheme.onSurface.withValues(alpha: 0.03),
                              border: Border.all(
                                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                icon,
                                size: 20,
                                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameCtrl.text.isEmpty) return;
                        if (isEdit) {
                          await ref.read(projectServiceProvider.notifier).saveProject(Project(
                            id: project.id,
                            name: nameCtrl.text,
                            path: project.path,
                            type: project.type,
                            lastOpened: project.lastOpened,
                            isInternal: project.isInternal,
                            colorValue: selectedColorValue,
                            iconCodePoint: selectedIconCodePoint,
                            iconFontFamily: selectedIconFontFamily,
                            iconFontPackage: selectedIconFontPackage,
                            platforms: project.platforms,
                            sdkVersion: project.sdkVersion,
                          ));
                        } else {
                          await ref.read(projectServiceProvider.notifier).createProject(
                            name: nameCtrl.text,
                            path: '',
                            type: selectedType,
                            iconCodePoint: selectedIconCodePoint,
                            colorValue: selectedColorValue,
                            iconFontFamily: selectedIconFontFamily,
                            iconFontPackage: selectedIconFontPackage,
                            platforms: selectedType == ProjectType.flutter ? selectedPlatforms : null,
                            sdkVersion: (selectedType == ProjectType.flutter || selectedType == ProjectType.androidJava || selectedType == ProjectType.androidKotlin) ? sdkCtrl.text.trim() : null,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(isEdit ? AppLocalizations.of(context)!.saveAction : AppLocalizations.of(context)!.createProject, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

}
