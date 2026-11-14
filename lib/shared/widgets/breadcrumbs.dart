import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/utils/file_icon_helper.dart';

class Breadcrumbs extends StatelessWidget {
  final String path;
  final String? workspacePath;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? accentColor;
  final Color? textColor;

  const Breadcrumbs({
    super.key,
    required this.path,
    this.workspacePath,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBg = backgroundColor ?? theme.colorScheme.surface;
    final effectiveBorder =
        borderColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.06);
    final effectiveAccent = accentColor ?? Colors.cyanAccent;
    final effectiveFg = textColor ?? theme.colorScheme.onSurface;

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
        color: effectiveBg,
        border: Border(
          bottom: BorderSide(
            color: effectiveBorder,
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
            color: effectiveAccent.withValues(alpha: 0.45),
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
                    ? effectiveAccent.withValues(alpha: 0.10)
                    : effectiveFg.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isLast
                      ? effectiveAccent.withValues(alpha: 0.28)
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
                      color: isLast
                          ? effectiveFg
                          : effectiveFg.withValues(alpha: 0.65),
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
