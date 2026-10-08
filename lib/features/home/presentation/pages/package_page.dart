import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/models/optional_package.dart';
import 'package:quantum_ide/core/services/pub_package_service.dart';
import 'package:quantum_ide/models/pub_package.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/features/home/presentation/widgets/package_install_dialog.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/services/cli_installer_service.dart';

class PackagePage extends ConsumerStatefulWidget {
  const PackagePage({super.key});

  @override
  ConsumerState<PackagePage> createState() => _PackagePageState();
}

class _PackagePageState extends ConsumerState<PackagePage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _searchQuery = '';
        _searchController.clear();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildPackageList(BuildContext context, WidgetRef ref, String tabType) {
    final allPackages = ref.watch(packageServiceProvider);
    
    final filtered = allPackages.where((pkg) {
      final matchesSearch = pkg.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            pkg.description.toLowerCase().contains(_searchQuery.toLowerCase());
      
      bool matchesTab;
      switch (tabType) {
        case 'all':
          matchesTab = true;
          break;
        case 'installed':
          matchesTab = pkg.isInstalled;
          break;
        case 'languages_ai':
          matchesTab = pkg.category == 'Languages' || pkg.category == 'AI Tools';
          break;
        case 'tools':
          matchesTab = pkg.category == 'Tools' || pkg.category == 'Frameworks' || pkg.category == 'Web';
          break;
        case 'build_system':
          matchesTab = pkg.category == 'System' || pkg.category == 'Build Tools';
          break;
        case 'sdk_platforms':
          matchesTab = pkg.category == 'SDK Platforms';
          break;
        default:
          matchesTab = true;
      }
      return matchesSearch && matchesTab;
    }).toList();

    final theme = Theme.of(context);
    
    final showCliAgentsHero = (tabType == 'all' || tabType == 'languages_ai') && _searchQuery.isEmpty;
    final showSdkHero = (tabType == 'all' || tabType == 'build_system') && 
        allPackages.any((p) => p.id == 'android-sdk' && !p.isInstalled) &&
        _searchQuery.isEmpty;
    final showFixHero = (tabType == 'all' || tabType == 'build_system') &&
        _searchQuery.isEmpty;

    final List<Widget> headers = [];
    if (showCliAgentsHero) {
      headers.add(_buildCliAgentsHeroCard(context, ref));
    }
    if (showSdkHero) {
      headers.add(_buildSDKHeroCard(context, ref));
    }
    if (showFixHero) {
      headers.add(_buildBuildFixHeroCard(context, ref));
    }

    if (filtered.isEmpty && headers.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.02),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.search_code, 
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppLocalizations.of(context)!.nothingFound,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                AppLocalizations.of(context)!.tryChangingSearchQuery,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(packageServiceProvider.notifier).checkActualInstallation();
      },
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        itemCount: filtered.length + headers.length,
        itemBuilder: (context, index) {
          if (index < headers.length) {
            return Column(
              children: [
                headers[index],
                const SizedBox(height: 16),
              ],
            );
          }
          final pkg = filtered[index - headers.length];
          return _buildPackageCard(context, ref, pkg);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background decorative gradients for rich premium look
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    blurRadius: 100,
                    spreadRadius: 50,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withValues(alpha: 0.06),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.04),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App Bar / Title Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                          child: IconButton(
                            icon: Icon(LucideIcons.arrow_left, color: theme.colorScheme.onSurface, size: 20),
                            tooltip: AppLocalizations.of(context)!.back,
                            onPressed: () => context.go('/'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            AppLocalizations.of(context)!.extensionsAndTools,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                          child: IconButton(
                            icon: Icon(LucideIcons.refresh_cw, color: theme.colorScheme.primary, size: 18),
                            tooltip: 'Проверить обновления пакетов',
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  content: Text(
                                    'Проверка наличия обновлений для пакетов и CLI-агентов...',
                                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              await ref.read(packageServiceProvider.notifier).checkActualInstallation();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    content: Text(
                                      'Список пакетов проверен и обновлен.',
                                      style: GoogleFonts.inter(color: Colors.greenAccent),
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    height: 52,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.search, size: 18, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) {
                              setState(() => _searchQuery = v);
                              if (_tabController.index != 6) {
                                // Filtering local is handled in UI builder via _searchQuery
                              }
                            },
                            onSubmitted: (v) {
                              if (_tabController.index == 6) {
                                ref.read(pubPackageServiceProvider.notifier).search(v);
                              }
                            },
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: _tabController.index == 6
                                  ? AppLocalizations.of(context)!.searchPubdevHint
                                  : AppLocalizations.of(context)!.searchExtensionsHint,
                              hintStyle: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Custom sliding premium TabBar
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                    ),
                  ),
                  labelColor: theme.colorScheme.onPrimary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                  unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  tabs: [
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabAll))),
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabInstalled))),
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabLanguagesAndAi))),
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabTools))),
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabBuild))),
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabSdkPlatforms))),
                    Tab(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(AppLocalizations.of(context)!.tabPubLibraries))),
                  ],
                ),

                const SizedBox(height: 8),

                // TabBarView content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildPackageList(context, ref, 'all'),
                      _buildPackageList(context, ref, 'installed'),
                      _buildPackageList(context, ref, 'languages_ai'),
                      _buildPackageList(context, ref, 'tools'),
                      _buildPackageList(context, ref, 'build_system'),
                      _buildPackageList(context, ref, 'sdk_platforms'),
                      _buildPubMarketplaceTab(context, ref),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCliAgentsHeroCard(BuildContext context, WidgetRef ref) {
    final allPackages = ref.watch(packageServiceProvider);
    final cliInstaller = ref.watch(cliInstallerProvider);

    final agyPkg = allPackages.where((p) => p.id == 'antigravity-cli').firstOrNull ??
        defaultPackages.firstWhere((p) => p.id == 'antigravity-cli');
    final claudePkg = allPackages.where((p) => p.id == 'claude-code').firstOrNull ??
        defaultPackages.firstWhere((p) => p.id == 'claude-code');
    final dshPkg = allPackages.where((p) => p.id == 'deepseek-harness').firstOrNull ??
        defaultPackages.firstWhere((p) => p.id == 'deepseek-harness');

    final agents = [
      (pkg: agyPkg, kind: AgentKind.antigravity),
      (pkg: claudePkg, kind: AgentKind.claudeCode),
      (pkg: dshPkg, kind: AgentKind.deepseekHarness),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1035), Color(0xFF101C38)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.purpleAccent.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                ),
                child: const Icon(LucideIcons.bot, color: Colors.purpleAccent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'CLI-Агенты разработки',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            'Mobile-Harness',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Автономные терминальные агенты Antigravity CLI, Claude Code и DeepSeek Harness',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: cliInstaller.isCheckingUpdates
                    ? null
                    : () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Проверка официальных обновлений для CLI агентов...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        await ref.read(cliInstallerProvider.notifier).checkCliUpdates();
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cliInstaller.isCheckingUpdates)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent),
                        )
                      else
                        const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.purpleAccent),
                      const SizedBox(width: 6),
                      Text(
                        cliInstaller.isCheckingUpdates ? 'Проверка...' : 'Обновления',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...agents.map((item) {
            final agent = item.pkg;
            final kind = item.kind;
            final installedVersion = cliInstaller.installedVersions[kind];
            final isInstalled = agent.isInstalled || (installedVersion != null && installedVersion.isNotEmpty);
            final updateInfo = cliInstaller.availableUpdates[kind];
            final hasUpdate = updateInfo?.hasUpdate ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasUpdate
                      ? Colors.amberAccent.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    agent.icon,
                    size: 18,
                    color: agent.id == 'antigravity-cli'
                        ? Colors.purpleAccent
                        : agent.id == 'claude-code'
                            ? Colors.amberAccent
                            : Colors.cyanAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              agent.name,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (installedVersion != null && installedVersion.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v$installedVersion',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 9.5,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasUpdate
                              ? 'Доступна новая версия v${updateInfo!.latestVersion}! Нажмите для обновления'
                              : agent.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: hasUpdate ? Colors.amberAccent : Colors.white60,
                            fontWeight: hasUpdate ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isInstalled)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasUpdate)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.sparkles, size: 11, color: Colors.amberAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Обновить',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(LucideIcons.check, size: 12, color: Colors.greenAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Актуален',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            hasUpdate ? LucideIcons.arrow_up : LucideIcons.refresh_cw,
                            size: 15,
                            color: hasUpdate ? Colors.amberAccent : Colors.cyanAccent,
                          ),
                          tooltip: hasUpdate ? 'Обновить до v${updateInfo!.latestVersion}' : 'Обновить или переустановить',
                          onPressed: () => PackageInstallDialog.show(context, agent, isUpdate: true),
                        ),
                      ],
                    )
                  else
                    ElevatedButton(
                      onPressed: () => PackageInstallDialog.show(context, agent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Установить',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSDKHeroCard(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allPackages = ref.watch(packageServiceProvider);
    // Safe lookup for the SDK package
    OptionalPackage? sdkPkg;
    try {
      sdkPkg = allPackages.firstWhere((p) => p.id == 'android-sdk');
    } catch (_) {
      try {
        sdkPkg = defaultPackages.firstWhere((p) => p.id == 'android-sdk');
      } catch (_) {
        sdkPkg = null;
      }
    }
    
    if (sdkPkg == null || sdkPkg.isInstalled) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.onPrimary.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(LucideIcons.settings_2, color: theme.colorScheme.onPrimary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.readyToBuildApk,
                      style: GoogleFonts.outfit(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.installAndroidSdkJava,
                      style: GoogleFonts.inter(
                        color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            AppLocalizations.of(context)!.sdkSetupDescription,
            style: GoogleFonts.inter(
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(packageServiceProvider.notifier).installPackage(sdkPkg!);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    content: Text(
                      AppLocalizations.of(context)!.initializingDevEnvironment,
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
                    ),
                    action: SnackBarAction(
                      label: AppLocalizations.of(context)!.viewAction,
                      textColor: theme.colorScheme.primary,
                      onPressed: () => context.push('/terminal'),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.onPrimary,
                foregroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                AppLocalizations.of(context)!.startSdkSetup,
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuildFixHeroCard(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allPackages = ref.watch(packageServiceProvider);
    OptionalPackage? fixPkg;
    try {
      fixPkg = allPackages.firstWhere((p) => p.id == 'build-fix');
    } catch (_) {
      try {
        fixPkg = defaultPackages.firstWhere((p) => p.id == 'build-fix');
      } catch (_) {
        fixPkg = null;
      }
    }

    if (fixPkg == null) return const SizedBox.shrink();

    // Use tertiary or error color for the warning/fix card to look distinct
    final cardColor = theme.colorScheme.tertiaryContainer;
    final onCardColor = theme.colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: onCardColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.25),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: onCardColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(LucideIcons.wrench, color: onCardColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.buildIssues,
                      style: GoogleFonts.outfit(
                        color: onCardColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.restoreAndroidGradleEnv,
                      style: GoogleFonts.inter(
                        color: onCardColor.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            AppLocalizations.of(context)!.wrenchFixDescription,
            style: GoogleFonts.inter(
              color: onCardColor.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                ref.read(packageServiceProvider.notifier).installPackage(fixPkg!);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    content: Text(
                      AppLocalizations.of(context)!.runningWrenchFix,
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
                    ),
                    action: SnackBarAction(
                      label: AppLocalizations.of(context)!.viewAction,
                      textColor: theme.colorScheme.primary,
                      onPressed: () => context.push('/terminal'),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: onCardColor,
                foregroundColor: cardColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                AppLocalizations.of(context)!.startWrenchFix,
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(BuildContext context, WidgetRef ref, OptionalPackage pkg) {
    final theme = Theme.of(context);
    final Color accentColor = pkg.isInstalled ? const Color(0xFF10B981) : theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111520),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: pkg.isInstalled
              ? const Color(0xFF10B981).withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withValues(alpha: 0.18),
                          accentColor.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(pkg.icon, color: accentColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                pkg.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (pkg.isInstalled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.badge_check, color: Color(0xFF10B981), size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      AppLocalizations.of(context)!.statusInstalledCaps,
                                      style: GoogleFonts.inter(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          pkg.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildInstallButton(context, ref, pkg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallButton(BuildContext context, WidgetRef ref, OptionalPackage pkg) {
    final theme = Theme.of(context);
    if (pkg.isInstalled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.check, size: 12, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  'Установлен',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(LucideIcons.refresh_cw, color: theme.colorScheme.primary, size: 15),
            tooltip: 'Обновить или переустановить',
            onPressed: () => PackageInstallDialog.show(context, pkg, isUpdate: true),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
        ),
      ),
      child: ElevatedButton(
        onPressed: () => PackageInstallDialog.show(context, pkg),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          AppLocalizations.of(context)!.installAction,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPubMarketplaceTab(BuildContext context, WidgetRef ref) {
    final packagesAsync = ref.watch(pubPackageServiceProvider);
    final theme = Theme.of(context);

    return packagesAsync.when(
      data: (packages) {
        if (packages.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.package_search, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.searchPubdevTitle,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.searchPubdevDescription,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: packages.length,
          itemBuilder: (context, index) {
            final pkg = packages[index];
            return _buildPubPackageCard(context, ref, pkg);
          },
        );
      },
      loading: () => Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      error: (err, _) => Center(
        child: Text(
          AppLocalizations.of(context)!.loadError(err.toString()),
          style: GoogleFonts.inter(color: theme.colorScheme.error, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildPubPackageCard(BuildContext context, WidgetRef ref, PubPackage pkg) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.15)),
                  ),
                  child: Icon(LucideIcons.package, color: theme.colorScheme.secondary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg.name,
                        style: GoogleFonts.inter(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${pkg.version}',
                        style: GoogleFonts.inter(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildPubInstallButton(context, ref, pkg),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              pkg.description,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildMetric(LucideIcons.thumbs_up, pkg.likes.toString()),
                const SizedBox(width: 16),
                _buildMetric(LucideIcons.zap, pkg.pubPoints.toString()),
                const SizedBox(width: 16),
                _buildMetric(LucideIcons.trending_up, '${(pkg.popularity * 100).toInt()}%'),
                const Spacer(),
                Wrap(
                  spacing: 4,
                  children: pkg.platforms.take(3).map((p) => _buildPlatformTag(p)).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPubInstallButton(BuildContext context, WidgetRef ref, PubPackage pkg) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => _installPubPackage(pkg),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: theme.colorScheme.onPrimary,
          shadowColor: Colors.transparent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(80, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          AppLocalizations.of(context)!.addAction,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _installPubPackage(PubPackage pkg) {
    final theme = Theme.of(context);
    final workspace = ref.read(workspaceProvider);
    if (workspace.currentPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.openProjectToInstallLibraries),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ref.read(terminalTabsProvider.notifier).sendCommand(
      'flutter pub add ${pkg.name}',
      createNewTab: true,
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.installingLibrary(pkg.name)),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: AppLocalizations.of(context)!.viewAction,
          textColor: theme.colorScheme.onPrimary,
          onPressed: () => context.push('/terminal'),
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) context.push('/terminal');
    });
  }

  Widget _buildMetric(IconData icon, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 12)),
      ],
    );
  }

  Widget _buildPlatformTag(String platform) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        platform.toUpperCase(),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }
}
