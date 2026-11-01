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
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E17),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.6,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: parts.length,
        separatorBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(
            LucideIcons.chevron_right,
            size: 11,
            color: Colors.cyanAccent.withValues(alpha: 0.35),
          ),
        ),
        itemBuilder: (context, index) {
          final isLast = index == parts.length - 1;
          final name = parts[index];
          final iconInfo = isLast 
              ? FileIconHelper.getIconInfo(name, false)
              : const FileIconInfo(LucideIcons.folder, Color(0xFFFFB800));

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isLast
                    ? Colors.cyanAccent.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isLast
                      ? Colors.cyanAccent.withValues(alpha: 0.25)
                      : Colors.transparent,
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconInfo.icon,
                    size: 12,
                    color: isLast ? iconInfo.color : const Color(0xFFFFB800).withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    name,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: isLast ? Colors.white : Colors.white60,
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: -0.2,
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
