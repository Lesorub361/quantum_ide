import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

enum ProjectType {
  flutter,
  python,
  nodejs,
  dart,
  web,
  shell,
  other,
  androidJava,
  androidKotlin
}

class Project {
  final String id;
  final String name;
  final String path;
  final ProjectType type;
  final DateTime lastOpened;
  final int? iconCodePoint;
  final int? colorValue;
  final String? iconFontFamily;
  final String? iconFontPackage;
  final bool isInternal;
  final List<String>? platforms;
  final String? sdkVersion;

  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.lastOpened,
    this.iconCodePoint,
    this.colorValue,
    this.iconFontFamily,
    this.iconFontPackage,
    this.isInternal = false,
    this.platforms,
    this.sdkVersion,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'type': type.index,
    'lastOpened': lastOpened.toIso8601String(),
    'iconCodePoint': iconCodePoint,
    'colorValue': colorValue,
    'iconFontFamily': iconFontFamily,
    'iconFontPackage': iconFontPackage,
    'isInternal': isInternal,
    'platforms': platforms,
    'sdkVersion': sdkVersion,
  };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'],
    name: json['name'],
    path: json['path'],
    type: ProjectType.values[json['type'] ?? 0],
    lastOpened: DateTime.parse(json['lastOpened']),
    iconCodePoint: json['iconCodePoint'],
    colorValue: json['colorValue'],
    iconFontFamily: json['iconFontFamily'],
    iconFontPackage: json['iconFontPackage'],
    isInternal: json['isInternal'] ?? false,
    platforms: json['platforms'] != null ? List<String>.from(json['platforms']) : null,
    sdkVersion: json['sdkVersion'],
  );

  IconData get icon {
    if (iconCodePoint != null) {
      return IconData(
        iconCodePoint!, 
        fontFamily: iconFontFamily ?? 'LucideIcons', 
        fontPackage: iconFontPackage ?? 'flutter_lucide',
      );
    }
    return LucideIcons.folder;
  }

  Color get color {
    if (colorValue != null) {
      return Color(colorValue!);
    }
    final colors = [
      const Color(0xFFE57373),
      const Color(0xFFF06292),
      const Color(0xFFBA68C8),
      const Color(0xFF9575CD),
      const Color(0xFF7986CB),
      const Color(0xFF64B5F6),
      const Color(0xFF4FC3F7),
      const Color(0xFF4DD0E1),
      const Color(0xFF4DB6AC),
      const Color(0xFF81C784),
      const Color(0xFFAED581),
      const Color(0xFFD4E157),
      const Color(0xFFFFD54F),
      const Color(0xFFFFB74D),
      const Color(0xFFFF8A65),
    ];
    final hash = name.codeUnits.fold<int>(0, (prev, element) => prev + element);
    return colors[hash % colors.length];
  }

  String? get appIconPath {
    if (path.isEmpty) return null;
    
    final androidPaths = [
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    ];
    for (final relPath in androidPaths) {
      final fullPath = '$path/$relPath';
      if (File(fullPath).existsSync()) {
        return fullPath;
      }
    }
    
    final webPaths = [
      'web/favicon.png',
      'web/favicon.ico',
      'web/icons/Icon-192.png',
    ];
    for (final relPath in webPaths) {
      final fullPath = '$path/$relPath';
      if (File(fullPath).existsSync()) {
        return fullPath;
      }
    }

    return null;
  }
}
