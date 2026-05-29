import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/package_service.dart';


class SidebarPackagesPanel extends ConsumerWidget {
  const SidebarPackagesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packages = ref.watch(packageServiceProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Column(
      children: [
        // Packages Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.toy_brick, size: 14, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              Text(
                isRu ? 'Пакеты и окружение' : 'Packages & Env',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                isRu 
                    ? 'Установлено: ${packages.where((p) => p.isInstalled).length}/${packages.length}'
                    : 'Installed: ${packages.where((p) => p.isInstalled).length}/${packages.length}',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        // Packages List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: packages.length,
            itemBuilder: (context, index) {
              final pkg = packages[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(pkg.icon, color: Colors.cyanAccent, size: 15),
                  ),
                  title: Text(
                    pkg.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    pkg.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white38,
                      fontSize: 10.5,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (pkg.isInstalled) ...[
                        const Icon(LucideIcons.circle_check_big, color: Colors.greenAccent, size: 15),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.white38),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () {
                            ref.read(packageServiceProvider.notifier).installPackage(pkg);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isRu ? 'Обновление пакета ${pkg.name}...' : 'Updating package ${pkg.name}...'),
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
                                content: Text(isRu ? 'Установка пакета ${pkg.name}...' : 'Installing package ${pkg.name}...'),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
                            foregroundColor: Colors.cyanAccent,
                            elevation: 0,
                            side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.2)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(isRu ? 'Установить' : 'Install', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
}
