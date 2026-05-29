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
    
    final showSdkHero = (tabType == 'all' || tabType == 'build_system') && 
        allPackages.any((p) => p.id == 'android-sdk' && !p.isInstalled) &&
        _searchQuery.isEmpty;
    
    final showFixHero = (tabType == 'all' || tabType == 'build_system') &&
        _searchQuery.isEmpty;

    if (filtered.isEmpty && !showSdkHero && !showFixHero) {
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
                'Ничего не найдено',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Попробуйте изменить запрос поиска',
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
      itemCount: filtered.length + (showSdkHero ? 1 : 0) + (showFixHero ? 1 : 0),
      itemBuilder: (context, index) {
        int adjustedIndex = index;
        if (showSdkHero) {
          if (index == 0) {
            return Column(
              children: [
                _buildSDKHeroCard(context, ref),
                const SizedBox(height: 16),
              ],
            );
          }
          adjustedIndex--;
        }
        if (showFixHero) {
          if ((showSdkHero && index == 1) || (!showSdkHero && index == 0)) {
            return Column(
              children: [
                _buildBuildFixHeroCard(context, ref),
                const SizedBox(height: 16),
              ],
            );
          }
          adjustedIndex--;
        }
        
        final pkg = filtered[adjustedIndex];
        return _buildPackageCard(context, ref, pkg);
      },
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
                            tooltip: 'Назад',
                            onPressed: () => context.go('/'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Расширения & Инструменты',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: theme.colorScheme.onSurface,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48), // Spacer to balance leading button
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
                                  ? 'Поиск библиотек на pub.dev (например, dio)...'
                                  : 'Поиск расширений...',
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
                  tabs: const [
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Все'))),
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Установленные'))),
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Языки и ИИ'))),
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Инструменты'))),
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Сборка'))),
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Платформы SDK'))),
                    Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Библиотеки Pub'))),
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
                      'Готовы к сборке APK?',
                      style: GoogleFonts.outfit(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Установите Android SDK & Java 17',
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
            'Это настроит SDK, компиляторы, утилиты zipalign, apksigner, оптимизирует настройки сети Gradle и подготовит ваше окружение к компиляции проектов.',
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
                      'Инициализация среды разработки...',
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
                    ),
                    action: SnackBarAction(
                      label: 'Посмотреть',
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
                'Начать настройку окружения',
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
                      'Проблемы со сборкой?',
                      style: GoogleFonts.outfit(
                        color: onCardColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Восстановление окружения Android & Gradle',
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
            'Автоматически исправляет ошибки AAPT2 daemon, выставляет правильные разрешения для проектов, восстанавливает бинарник компилятора ресурсов и настраивает потоки Gradle.',
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
                      'Запуск исправления окружения сборки...',
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500),
                    ),
                    action: SnackBarAction(
                      label: 'Посмотреть',
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
                'Запустить исправление (Wrench Fix)',
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
    // Determine gradient for icon background depending on package status
    final Color accentColor = pkg.isInstalled ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
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
                      color: accentColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor.withValues(alpha: 0.15)),
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
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (pkg.isInstalled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.badge_check, color: theme.colorScheme.primary, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      'УСТАНОВЛЕНО',
                                      style: GoogleFonts.inter(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        color: theme.colorScheme.primary,
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
                            color: theme.colorScheme.onSurfaceVariant,
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
          IconButton(
            icon: Icon(LucideIcons.refresh_cw, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 16),
            tooltip: 'Переустановить / Обновить',
            onPressed: () {
              ref.read(packageServiceProvider.notifier).installPackage(pkg);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  content: Text(
                    'Обновление ${pkg.name}...',
                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface),
                  ),
                  action: SnackBarAction(
                    label: 'Посмотреть',
                    textColor: theme.colorScheme.primary,
                    onPressed: () => context.push('/terminal'),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

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
        onPressed: () {
          ref.read(packageServiceProvider.notifier).installPackage(pkg);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Установка ${pkg.name}...',
                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'Посмотреть',
                textColor: theme.colorScheme.primary,
                onPressed: () => context.push('/terminal'),
              ),
            ),
          );
        },
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
          'Установить',
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
                    'Поиск Flutter-библиотек',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Введите название библиотеки (например: dio, bloc, riverpod) в поиск выше и нажмите Enter',
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
          'Ошибка загрузки: $err',
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
          'Добавить',
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
          content: const Text('Сначала откройте проект, чтобы добавлять библиотеки.'),
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
        content: Text('Установка библиотеки ${pkg.name}...'),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Посмотреть',
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
