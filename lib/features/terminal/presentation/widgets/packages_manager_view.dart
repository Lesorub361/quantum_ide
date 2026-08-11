import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class PackagesManagerView extends ConsumerStatefulWidget {
  const PackagesManagerView({super.key});

  @override
  ConsumerState<PackagesManagerView> createState() => _PackagesManagerViewState();
}

class _PackagesManagerViewState extends ConsumerState<PackagesManagerView> {
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(packageServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final installedCount = packages.where((p) => p.isInstalled).length;

    // Get unique categories
    final categories = ['All', ...packages.map((p) => p.category).toSet()];

    // Filter packages
    final filteredPackages = packages.where((pkg) {
      final matchesSearch = pkg.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          pkg.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'All' || pkg.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return Column(
      children: [
        // Packages Count Stats Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.toy_brick, size: 13, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                l10n.packagesAndEnv,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                l10n.packagesInstalledCount(installedCount, packages.length),
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),

        // Search and Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: TextField(
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search packages...',
                hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11.5),
                prefixIcon: const Icon(LucideIcons.search, size: 13, color: Colors.white38),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
        ),

        // Category Filter Chips
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            itemCount: categories.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.cyanAccent.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? Colors.cyanAccent.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.05),
                        width: 0.8,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: GoogleFonts.inter(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Packages List
        Expanded(
          child: filteredPackages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.package_open, size: 30, color: Colors.white12),
                      const SizedBox(height: 8),
                      Text(
                        'No packages found',
                        style: GoogleFonts.inter(color: Colors.white30, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: filteredPackages.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final pkg = filteredPackages[index];
                    final categoryColor = _getCategoryColor(pkg.category);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        leading: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: categoryColor.withValues(alpha: 0.2), width: 0.5),
                          ),
                          child: Icon(pkg.icon, color: categoryColor, size: 14),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pkg.name,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                pkg.category,
                                style: GoogleFonts.inter(
                                  color: categoryColor,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3.0),
                          child: Text(
                            pkg.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 10,
                              height: 1.3,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pkg.isInstalled) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.circle_check, color: Colors.greenAccent, size: 10),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Ready',
                                      style: GoogleFonts.inter(
                                        color: Colors.greenAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(LucideIcons.refresh_cw, size: 11, color: Colors.white38),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: () {
                                  ref.read(packageServiceProvider.notifier).installPackage(pkg);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.updatingPackage(pkg.name)),
                                    ),
                                  );
                                },
                              ),
                            ] else
                              ElevatedButton(
                                onPressed: () {
                                  ref.read(packageServiceProvider.notifier).installPackage(pkg);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.installingPackage(pkg.name)),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                                  foregroundColor: Colors.cyanAccent,
                                  elevation: 0,
                                  side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.25)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  l10n.installAction,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'AI Tools':
        return Colors.purpleAccent;
      case 'Languages':
        return Colors.greenAccent;
      case 'Web':
        return Colors.blueAccent;
      case 'Build Tools':
        return Colors.orangeAccent;
      case 'SDK Platforms':
        return Colors.amberAccent;
      case 'System':
        return Colors.redAccent;
      default:
        return Colors.cyanAccent;
    }
  }
}
