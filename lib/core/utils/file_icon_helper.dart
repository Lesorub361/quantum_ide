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

      if (segment == '.dart_tool') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_cog,
          const Color(0xFF00B4AB), // Dart tool teal
        );
      }
      if (segment == 'linux') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFFFCC624), // Linux yellow
        );
      }
      if (segment == 'macos' || segment == 'darwin') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFFA2AAAD), // Apple silver
        );
      }
      if (segment == 'windows') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFF0078D7), // Windows blue
        );
      }
      if (segment == 'fonts' || segment == 'font') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder,
          const Color(0xFFE91E63), // Pink
        );
      }
      if (segment == 'images' || segment == 'img' || segment == 'icons' || segment == 'pics') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_heart,
          const Color(0xFFAB47BC), // Purple
        );
      }
      if (segment == 'scripts' || segment == 'bin') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_code,
          const Color(0xFF4CAF50), // Green
        );
      }
      if (segment == 'docs' || segment == 'doc') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_input,
          const Color(0xFF26A69A), // Teal
        );
      }
      if (segment == 'config' || segment == 'configs' || segment == 'settings') {
        return FileIconInfo(
          isExpanded ? LucideIcons.folder_open : LucideIcons.folder_cog,
          const Color(0xFF78909C), // Blue grey
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
    if (lowerName.endsWith('.aab')) {
      return const FileIconInfo(
        LucideIcons.package,
        Color(0xFF3DDC84), // Android Green
      );
    }
    if (lowerName == '.env' || lowerName.startsWith('.env.')) {
      return const FileIconInfo(
        LucideIcons.key_round,
        Color(0xFFFFB300), // Amber
      );
    }
    if (lowerName == 'dockerfile' || lowerName.startsWith('dockerfile.')) {
      return const FileIconInfo(
        LucideIcons.container,
        Color(0xFF2496ED), // Docker Blue
      );
    }
    if (lowerName == '.gitignore' || lowerName == '.gitattributes' || lowerName == '.gitmodules') {
      return const FileIconInfo(
        LucideIcons.git_branch,
        Color(0xFFF05032), // Git Orange
      );
    }
    if (lowerName.endsWith('.gradle') || lowerName.endsWith('.gradle.kts')) {
      return const FileIconInfo(
        LucideIcons.settings_2,
        Color(0xFF02303A), // Gradle Dark Slate
      );
    }
    if (lowerName.endsWith('.toml')) {
      return const FileIconInfo(
        LucideIcons.file_cog,
        Color(0xFF9C27B0), // Purple
      );
    }
    if (lowerName.endsWith('.sqlite') || lowerName.endsWith('.sqlite3') || lowerName.endsWith('.db')) {
      return const FileIconInfo(
        LucideIcons.database,
        Color(0xFF4DB6AC), // Teal
      );
    }
    if (lowerName.endsWith('.lock')) {
      return const FileIconInfo(
        LucideIcons.lock,
        Color(0xFF90A4AE), // Grey
      );
    }
    if (lowerName.endsWith('.svg')) {
      return const FileIconInfo(
        LucideIcons.file_code,
        Color(0xFFFFB300), // Amber
      );
    }
    if (lowerName.endsWith('.png') || lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.gif') || lowerName.endsWith('.webp') || lowerName.endsWith('.ico')) {
      return const FileIconInfo(
        LucideIcons.image,
        Color(0xFFAB47BC), // Purple
      );
    }
    if (lowerName.endsWith('.mp3') || lowerName.endsWith('.wav') || lowerName.endsWith('.ogg') || lowerName.endsWith('.m4a')) {
      return const FileIconInfo(
        LucideIcons.music,
        Color(0xFFE91E63), // Pink
      );
    }
    if (lowerName.endsWith('.mp4') || lowerName.endsWith('.mkv') || lowerName.endsWith('.mov') || lowerName.endsWith('.webm')) {
      return const FileIconInfo(
        LucideIcons.video,
        Color(0xFFFF5722), // Deep Orange
      );
    }
    if (lowerName.endsWith('.zip') || lowerName.endsWith('.tar') || lowerName.endsWith('.gz') || lowerName.endsWith('.7z') || lowerName.endsWith('.rar')) {
      return const FileIconInfo(
        LucideIcons.archive,
        Color(0xFFFFB74D), // Light Orange
      );
    }
    if (lowerName.endsWith('.pdf')) {
      return const FileIconInfo(
        LucideIcons.file_text,
        Color(0xFFE53935), // Red
      );
    }
    if (lowerName.endsWith('.log')) {
      return const FileIconInfo(
        LucideIcons.file_text,
        Color(0xFF78909C), // Blue grey
      );
    }
    if (lowerName.endsWith('.sh') || lowerName.endsWith('.bash') || lowerName.endsWith('.zsh')) {
      return const FileIconInfo(
        LucideIcons.terminal,
        Color(0xFF4CAF50), // Green
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
        // ignore: non_const_argument_for_const_parameter
        meta.codePoint,
        fontFamily: 'Seti',
        fontPackage: 'file_icon',
      ),
      Color(meta.color),
    );
  }
}
