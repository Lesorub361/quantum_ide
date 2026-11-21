// ignore_for_file: non_const_argument_for_const_parameter
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
  androidKotlin,
  rust
}

class Project {
  final String id;
  final String name;
  final String path;
  final ProjectType type;
  final DateTime lastOpened;
  final bool isInternal;
  final List<String>? platforms;
  final String? sdkVersion;

  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.lastOpened,
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
    'isInternal': isInternal,
    'platforms': platforms,
    'sdkVersion': sdkVersion,
  };

  factory Project.fromJson(Map<String, dynamic> json) {
    final typeIdx = (json['type'] as num?)?.toInt() ?? 0;
    final safeType = (typeIdx >= 0 && typeIdx < ProjectType.values.length)
        ? ProjectType.values[typeIdx]
        : ProjectType.other;
    return Project(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      type: safeType,
      lastOpened:
          DateTime.tryParse(json['lastOpened']?.toString() ?? '') ??
          DateTime.now(),
      isInternal: json['isInternal'] == true,
      platforms: json['platforms'] != null
          ? List<String>.from(json['platforms'])
          : null,
      sdkVersion: json['sdkVersion']?.toString(),
    );
  }

  IconData get icon {
    switch (type) {
      case ProjectType.flutter:
        return LucideIcons.smartphone;
      case ProjectType.androidKotlin:
      case ProjectType.androidJava:
        return LucideIcons.layers;
      case ProjectType.web:
        return LucideIcons.globe;
      case ProjectType.nodejs:
        return LucideIcons.server;
      case ProjectType.python:
      case ProjectType.shell:
        return LucideIcons.terminal;
      case ProjectType.rust:
        return LucideIcons.cpu;
      case ProjectType.dart:
        return LucideIcons.code;
      case ProjectType.other:
        return LucideIcons.folder;
    }
  }

  Color get color {
    switch (type) {
      case ProjectType.flutter:
        return const Color(0xFF38BDF8);
      case ProjectType.androidKotlin:
        return const Color(0xFF7F52FF);
      case ProjectType.androidJava:
        return const Color(0xFFF89820);
      case ProjectType.web:
        return const Color(0xFF00D8FF);
      case ProjectType.nodejs:
        return const Color(0xFF68A063);
      case ProjectType.python:
        return const Color(0xFFFFD43B);
      case ProjectType.rust:
        return const Color(0xFFDEA584);
      case ProjectType.dart:
        return const Color(0xFF0175C2);
      case ProjectType.shell:
        return const Color(0xFF10B981);
      case ProjectType.other:
        return const Color(0xFF94A3B8);
    }
  }

  String? get appIconPath {
    if (path.isEmpty) return null;

    // 1. Check pubspec.yaml for flutter_launcher_icons / flutter_icons image_path
    try {
      final pubspec = File('$path/pubspec.yaml');
      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        final match = RegExp(
          r'^\s*(?:image_path_android|image_path)\s*:\s*["\x27]?([^\n"\x27#]+)["\x27]?',
          multiLine: true,
        ).firstMatch(content);
        if (match != null) {
          final rel = match.group(1)?.trim() ?? '';
          if (rel.isNotEmpty) {
            final full = rel.startsWith('/') ? rel : '$path/$rel';
            if (File(full).existsSync()) return full;
          }
        }
      }
    } catch (_) {}

    // 2. Android res/ (both Flutter android/app/ and native Android app/)
    const resRoots = ['android/app/src/main/res', 'app/src/main/res'];
    const buckets = [
      'mipmap-xxxhdpi',
      'mipmap-xxhdpi',
      'mipmap-xhdpi',
      'mipmap-hdpi',
      'mipmap-mdpi',
      'drawable-xxxhdpi',
      'drawable-xxhdpi',
      'drawable-xhdpi',
      'drawable-hdpi',
      'drawable',
    ];
    const fileNames = [
      'ic_launcher.png',
      'ic_launcher.webp',
      'ic_launcher_round.png',
      'ic_launcher_round.webp',
      'ic_launcher_foreground.png',
      'ic_launcher_foreground.webp',
      'app_icon.png',
    ];
    for (final root in resRoots) {
      for (final bucket in buckets) {
        for (final name in fileNames) {
          final full = '$path/$root/$bucket/$name';
          if (File(full).existsSync()) return full;
        }
      }
    }

    // 3. Common assets, web, and macOS icon locations
    const fallbackPaths = [
      'assets/icon/icon.png',
      'assets/icon.png',
      'assets/icons/icon.png',
      'assets/icons/app_icon.png',
      'assets/images/icon.png',
      'assets/images/logo.png',
      'assets/app_icon.png',
      'assets/logo.png',
      'web/icons/Icon-192.png',
      'web/icons/Icon-512.png',
      'web/favicon.png',
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
    ];
    for (final relPath in fallbackPaths) {
      final fullPath = '$path/$relPath';
      if (File(fullPath).existsSync()) {
        return fullPath;
      }
    }

    return null;
  }
}
