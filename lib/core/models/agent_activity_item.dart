import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

enum AgentKind {
  native(
    'native',
    'Встроенный Автопилот',
    'Работает прямо в приложении · Не требует установки сторонних CLI',
    '0 MB (Встроен)',
  ),
  antigravity(
    'antigravity',
    'Antigravity CLI',
    'Google\'s official coding agent · Google account',
    '39.9 MB',
  ),
  claudeCode(
    'claude-code',
    'Claude Code',
    'Anthropic\'s coding agent · broad provider support',
    '71.8 MB',
  ),
  deepseekHarness(
    'deepseek-harness',
    'DeepSeek Harness',
    'Official DeepSeek coding agent · API-key providers',
    '26.5 MB',
  );

  final String stableId;
  final String title;
  final String subtitle;
  final String downloadNote;

  const AgentKind(this.stableId, this.title, this.subtitle, this.downloadNote);

  static AgentKind fromStored(String? value) {
    return AgentKind.values.firstWhere(
      (e) => e.stableId == value || e.name == value,
      orElse: () => AgentKind.native,
    );
  }
}

extension AgentKindUI on AgentKind {
  IconData get icon {
    switch (this) {
      case AgentKind.native:
        return LucideIcons.sparkles;
      case AgentKind.antigravity:
        return LucideIcons.wand;
      case AgentKind.claudeCode:
        return LucideIcons.bot;
      case AgentKind.deepseekHarness:
        return LucideIcons.brain_circuit;
    }
  }

  Color get brandColor {
    switch (this) {
      case AgentKind.native:
        return const Color(0xFF8B5CF6);
      case AgentKind.antigravity:
        return const Color(0xFF9C27B0);
      case AgentKind.claudeCode:
        return const Color(0xFFD97706);
      case AgentKind.deepseekHarness:
        return const Color(0xFF0284C7);
    }
  }

  String get command {
    switch (this) {
      case AgentKind.native:
        return 'native';
      case AgentKind.antigravity:
        return 'agy';
      case AgentKind.claudeCode:
        return 'claude';
      case AgentKind.deepseekHarness:
        return 'dsh';
    }
  }
}

enum DevStack {
  web(
    'Web (JavaScript / TypeScript)',
    'Websites and web apps with HTML, CSS, and JS frameworks.',
    'Node.js and npm (already included)',
    ['node', 'npm', 'git'],
  ),
  python(
    'Python',
    'Scripts, automation, data work, and Python backends.',
    'python3, pip, venv, and build tools',
    ['python3', 'python3-pip', 'python3-venv'],
  ),
  android(
    'Android (Java / Kotlin / Flutter)',
    'Build Android app projects and install them directly on device.',
    'JDK 17, ARM64 Android SDK, Gradle, and Flutter',
    ['openjdk-17-jdk', 'gradle', 'flutter'],
  ),
  cpp(
    'C / C++',
    'Fast compiled programs, algorithms, and systems code.',
    'gcc, g++, make, cmake, gdb',
    ['gcc', 'g++', 'make', 'cmake', 'gdb'],
  ),
  php(
    'PHP',
    'Websites and apps with PHP — classic sites and Laravel projects.',
    'php-cli, common extensions, and Composer',
    ['php-cli', 'composer'],
  );

  final String label;
  final String description;
  final String installsSummary;
  final List<String> packages;

  const DevStack(this.label, this.description, this.installsSummary, this.packages);
}

class ActivityItem {
  final String title;
  final String detail;
  final bool isComplete;
  final bool isCommand;
  final int durationMillis;
  final String? targetFile;
  final String? instruction;
  final String? targetContent;
  final String? replacementContent;
  final String? output;

  const ActivityItem({
    required this.title,
    required this.detail,
    this.isComplete = true,
    this.isCommand = false,
    this.durationMillis = 0,
    this.targetFile,
    this.instruction,
    this.targetContent,
    this.replacementContent,
    this.output,
  });

  ActivityItem copyWith({
    String? title,
    String? detail,
    bool? isComplete,
    bool? isCommand,
    int? durationMillis,
    String? targetFile,
    String? instruction,
    String? targetContent,
    String? replacementContent,
    String? output,
  }) {
    return ActivityItem(
      title: title ?? this.title,
      detail: detail ?? this.detail,
      isComplete: isComplete ?? this.isComplete,
      isCommand: isCommand ?? this.isCommand,
      durationMillis: durationMillis ?? this.durationMillis,
      targetFile: targetFile ?? this.targetFile,
      instruction: instruction ?? this.instruction,
      targetContent: targetContent ?? this.targetContent,
      replacementContent: replacementContent ?? this.replacementContent,
      output: output ?? this.output,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'detail': detail,
    'isComplete': isComplete,
    'isCommand': isCommand,
    'durationMillis': durationMillis,
    if (targetFile != null) 'targetFile': targetFile,
    if (instruction != null) 'instruction': instruction,
    if (targetContent != null) 'targetContent': targetContent,
    if (replacementContent != null) 'replacementContent': replacementContent,
    if (output != null) 'output': output,
  };

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    title: json['title'] ?? '',
    detail: json['detail'] ?? '',
    isComplete: json['isComplete'] ?? true,
    isCommand: json['isCommand'] ?? false,
    durationMillis: json['durationMillis'] ?? 0,
    targetFile: json['targetFile'] as String?,
    instruction: json['instruction'] as String?,
    targetContent: json['targetContent'] as String?,
    replacementContent: json['replacementContent'] as String?,
    output: json['output'] as String?,
  );
}

class QuickChatIdentity {
  final String displayName;
  final String slug;

  const QuickChatIdentity(this.displayName, this.slug);
}

QuickChatIdentity generateQuickChatIdentity(Set<String> usedSlugs) {
  final random = Random();
  final adjectives = [
    'bright', 'calm', 'clever', 'curious', 'gentle',
    'nimble', 'quiet', 'swift', 'wise', 'bold', 'brave', 'sharp',
  ];
  final pioneers = [
    'turing', 'lovelace', 'hopper', 'tesla', 'curie',
    'ramanujan', 'bose', 'kalam', 'faraday', 'darwin', 'knuth', 'neumann',
  ];

  for (int i = 0; i < 20; i++) {
    final adj = adjectives[random.nextInt(adjectives.length)];
    final pion = pioneers[random.nextInt(pioneers.length)];
    final base = '$adj-$pion';
    if (!usedSlugs.contains(base)) {
      final displayName = '$adj $pion'.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
      return QuickChatIdentity(displayName, base);
    }
  }

  final adj = adjectives[random.nextInt(adjectives.length)];
  final pion = pioneers[random.nextInt(pioneers.length)];
  final base = '$adj-$pion-${random.nextInt(999)}';
  final displayName = base.split('-').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  return QuickChatIdentity(displayName, base);
}
