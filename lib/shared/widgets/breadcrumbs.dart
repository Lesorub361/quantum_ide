import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/utils/file_icon_helper.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F17),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: parts.length,
        separatorBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(LucideIcons.chevron_right, size: 11, color: Colors.white.withValues(alpha: 0.2)),
        ),
        itemBuilder: (context, index) {
          final isLast = index == parts.length - 1;
          final name = parts[index];
          final iconInfo = isLast 
              ? FileIconHelper.getIconInfo(name, false)
              : const FileIconInfo(LucideIcons.folder, Colors.amberAccent);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isLast ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconInfo.icon,
                    size: 12,
                    color: isLast ? iconInfo.color : Colors.white30,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isLast ? Colors.white : Colors.white38,
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
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
}
