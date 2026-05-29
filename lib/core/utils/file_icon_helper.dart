import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
// ignore: implementation_imports
import 'package:file_icon/src/data.dart';

class FileIconInfo {
  final IconData icon;
  final Color color;
  const FileIconInfo(this.icon, this.color);
}

class FileIconHelper {
  static FileIconInfo getIconInfo(String name, bool isDirectory, [bool isExpanded = false]) {
    final lowerName = name.toLowerCase();

    if (isDirectory) {
      final segment = lowerName.contains('/') ? lowerName.split('/').first : lowerName;

      if (segment == '.git' || segment == '.github') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_git_2,
          const Color(0xFFF05032), // Git orange
        );
      }
      if (segment == 'android') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFF3DDC84), // Android green
        );
      }
      if (segment == 'ios') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder,
          const Color(0xFF8E8E93), // iOS Grey
        );
      }
      if (segment == 'lib' || segment == 'src' || segment == 'source' || segment == 'sources') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFFFF9800), // Orange
        );
      }
      if (segment == 'java') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFFF89820), // Java orange
        );
      }
      if (segment == 'kotlin' || segment == '.kotlin' || segment == 'kt') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFF7F52FF), // Kotlin purple
        );
      }
      if (segment == 'test' || segment == 'tests' || segment == 'spec' || segment == 'specs') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_heart,
          const Color(0xFF4CAF50), // Test green
        );
      }
      if (segment == 'build' || segment == 'dist' || segment == 'out' || segment == 'bin') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_archive,
          const Color(0xFFEF5350), // Build red
        );
      }
      if (segment == 'gradle') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_cog,
          const Color(0xFF607D8B), // Gradle blue-grey
        );
      }
      if (segment == 'res' || segment == 'resources' || segment == 'assets') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_input,
          const Color(0xFFEC407A), // Resources pink
        );
      }
      if (segment == 'values' || segment.startsWith('values-')) {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder,
          const Color(0xFFFFB300), // Values amber
        );
      }
      if (segment == 'layout' || segment.startsWith('layout-')) {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder,
          const Color(0xFF29B6F6), // Layout light blue
        );
      }
      if (segment == 'drawable' || segment.startsWith('drawable-') || segment == 'mipmap' || segment.startsWith('mipmap-')) {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder,
          const Color(0xFF66BB6A), // Drawable green
        );
      }
      if (segment == 'web' || segment == 'html' || segment == 'public') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFF2196F3), // Web blue
        );
      }
      if (segment == '.idea' || segment == '.vscode') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_cog,
          const Color(0xFF90A4AE), // Config grey
        );
      }
      if (segment == 'node_modules') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_archive,
          const Color(0xFF4CAF50), // NPM green
        );
      }
      if (segment == 'app') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFFAB47BC), // App purple
        );
      }

      // Default folder
      return FileIconInfo(
        isExpanded ? LucideIcons.folder_open : LucideIcons.folder,
        const Color(0xFFFFCA28), // Default Amber 400
      );
    }

    // Custom file overrides
    if (lowerName.endsWith('.apk')) {
      return const FileIconInfo(
        LucideIcons.smartphone,
        Color(0xFF3DDC84), // Android Green
      );
    }

    // File icon lookup from file_icon's iconSetMap
    String? key;
    if (iconSetMap.containsKey(lowerName)) {
      key = lowerName;
    } else {
      var temp = lowerName;
      while (temp.contains('.')) {
        final idx = temp.indexOf('.');
        temp = temp.substring(idx + 1);
        final dotExt = '.$temp';
        if (iconSetMap.containsKey(dotExt)) {
          key = dotExt;
          break;
        }
      }
    }

    key ??= '.txt';

    final meta = iconSetMap[key]!;
    return FileIconInfo(
      IconData(
        meta.codePoint,
        fontFamily: 'Seti',
        fontPackage: 'file_icon',
      ),
      Color(meta.color),
    );
  }
}
