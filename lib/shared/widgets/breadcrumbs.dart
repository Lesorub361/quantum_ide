import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;

class Breadcrumbs extends StatelessWidget {
  final String path;
  final String? workspacePath;

  const Breadcrumbs({super.key, required this.path, this.workspacePath});

  @override
  Widget build(BuildContext context) {
    String relativePath = path;
    if (workspacePath != null && path.startsWith(workspacePath!)) {
      relativePath = path.substring(workspacePath!.length);
      if (relativePath.startsWith(p.separator)) {
        relativePath = relativePath.substring(1);
      }
    }

    final parts = relativePath.split(p.separator);
    
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: parts.length,
        separatorBuilder: (context, index) => const Icon(LucideIcons.chevron_right, size: 12, color: Colors.white10),
        itemBuilder: (context, index) {
          final isLast = index == parts.length - 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isLast)
                   const Icon(LucideIcons.folder, size: 12, color: Colors.white24)
                else
                   const Icon(LucideIcons.file_text, size: 12, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Text(
                  parts[index],
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isLast ? Colors.white70 : Colors.white38,
                    fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
