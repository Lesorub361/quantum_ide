import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/pub_package_service.dart';
import 'package:quantum_ide/models/pub_package.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(pubPackageServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrow_left, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Pub.dev Marketplace',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search packages (e.g. dio, provider...)',
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                prefixIcon: Icon(LucideIcons.search, color: theme.colorScheme.primary),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onSubmitted: (val) => ref.read(pubPackageServiceProvider.notifier).search(val),
            ),
          ),
          Expanded(
            child: packagesAsync.when(
              data: (packages) {
                if (packages.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: packages.length,
                  itemBuilder: (context, index) => _buildPackageCard(packages[index]),
                );
              },
              loading: () => Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
              error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: theme.colorScheme.error))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.package_search, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'Search for Flutter packages',
            style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(PubPackage pkg) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg.name,
                        style: GoogleFonts.inter(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'v${pkg.version}',
                        style: GoogleFonts.inter(color: theme.colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                _buildInstallButton(pkg),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              pkg.description,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
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
                  children: pkg.platforms.map((p) => _buildPlatformTag(p)).toList(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

  Widget _buildInstallButton(PubPackage pkg) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: () => _installPackage(pkg),
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: const Text('Add to Project', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  void _installPackage(PubPackage pkg) {
    final theme = Theme.of(context);
    final workspace = ref.read(workspaceProvider);
    if (workspace.currentPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please open a project first to add plugins.'),
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
        content: Text('Installing ${pkg.name}...'),
        backgroundColor: theme.colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'View',
          textColor: theme.colorScheme.onPrimary,
          onPressed: () => context.push('/terminal'),
        ),
      ),
    );

    // Auto-navigate to terminal after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) context.push('/terminal');
    });
  }
}
