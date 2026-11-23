import 'dart:io';

/// Represents a modular Agent Skill (`SKILL.md` or built-in best-practice recipe)
/// loaded dynamically into Roxum's system prompt only when relevant to the turn.
class RoxumSkill {
  final String id;
  final String name;
  final String description;
  final List<String> keywords;
  final String instructions;
  final String? sourcePath;

  const RoxumSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.keywords,
    required this.instructions,
    this.sourcePath,
  });
}

/// Discovers project-level `SKILL.md` files (`.agents/skills/*/SKILL.md` and
/// `.quantum/skills/*/SKILL.md`) and combines them with compact built-in
/// Flutter/Dart 2026 & Genkit Dart recipes. Only matching skills (max 2) are
/// injected per turn to avoid bloating the base system prompt.
class RoxumSkillLoader {
  static const List<RoxumSkill> builtinSkills = [
    RoxumSkill(
      id: 'flutter-widget-previews',
      name: 'Flutter Widget Previews (@Preview)',
      description:
          'Creates standalone @Preview widgets (Flutter 3.47+) using package:flutter/widget_previews.dart.',
      keywords: [
        'preview',
        '@preview',
        'widget_previews',
        'widget preview',
        'превью',
        'предпросмотр',
      ],
      instructions:
          '- Import `package:flutter/widget_previews.dart` and annotate a top-level function or static method returning `Widget` with `@Preview(name: \'...\')`.\n'
          '- Preview functions must take NO required arguments and wrap widgets cleanly in a `MaterialApp` / `Theme` if needed.\n'
          '- Because Widget Previews run on Flutter Web, avoid direct `dart:io` or `dart:ffi` calls inside previewed widgets (guard with `kIsWeb` or inject mock data).\n'
          '- Launch via `flutter widget-preview start --no-web-browser --web-port=5175` or the editor `@Preview` button.',
    ),
    RoxumSkill(
      id: 'flutter-ui-layout',
      name: 'Flutter Material 3 & Responsive Layout',
      description:
          'Prevents RenderFlex overflows, ensures mounted safety, and follows Material 3 best practices.',
      keywords: [
        'widget',
        'layout',
        'overflow',
        'ui',
        'экран',
        'кнопк',
        'верстк',
        'дизайн',
        'flutter',
        'material',
        'theme',
        'responsive',
      ],
      instructions:
          '- Always wrap flexible children inside `Row`/`Column` with `Expanded` or `Flexible` and add `overflow: TextOverflow.ellipsis` on dynamic `Text` to avoid RenderFlex overflow.\n'
          '- Use `LayoutBuilder` or `MediaQuery.sizeOf(context)` for responsive phone/tablet layouts.\n'
          '- Check `if (!mounted) return;` / `if (!context.mounted) return;` after every `await` before touching `context` or `setState`.\n'
          '- Prefer `const` constructors, `Color.withValues(alpha: ...)` (avoid deprecated `withOpacity`), and single-file targeted `editFile` patches.',
    ),
    RoxumSkill(
      id: 'flutter-testing-verification',
      name: 'Flutter & Dart Testing + Package Management',
      description:
          'Writes unit/widget tests and safely manages dependencies with flutter pub add.',
      keywords: [
        'test',
        'тест',
        'pubspec',
        'package',
        'пакет',
        'dependenc',
        'analyze',
        'ошибк',
        'fix',
        'исправ',
      ],
      instructions:
          '- Always add packages via `flutter pub add <pkg>` (or `dart pub add <pkg>`) instead of manually editing `pubspec.yaml`.\n'
          '- After editing Dart files, run `mcp__quantum_token_saver__smart_analyze_errors` (or `dart mcp-server` if enabled) and fix all errors with `editFile`.\n'
          '- Write fast, deterministic tests using `flutter_test` (`WidgetTester`) or `package:test` and verify with `mcp__quantum_token_saver__run_tests`.',
    ),
    RoxumSkill(
      id: 'genkit-dart-ai-flows',
      name: 'Genkit Dart & AI Agent Flows',
      description:
          'Builds type-safe AI flows, structured outputs, and MCP integrations in Dart/Flutter.',
      keywords: [
        'genkit',
        'ai flow',
        'genui',
        'structured output',
        'mcp',
        'mcp-server',
        'агент',
        'gemini',
        'llm',
      ],
      instructions:
          '- For Dart/Flutter AI workflows, prefer strongly-typed request/response schemas and streaming responses.\n'
          '- When `dart mcp-server` is enabled in MCP settings, prefer its native Dart Analysis Server / DTD tools for `pub.dev` search, `pubspec.yaml` edits, hot reload, and runtime error inspection.\n'
          '- Keep prompts modular: store project-specific workflows in `.agents/skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`).',
    ),
  ];

  /// Loads project-local skills from `.agents/skills/*/SKILL.md` and
  /// `.quantum/skills/*/SKILL.md`.
  static List<RoxumSkill> loadWorkspaceSkills(String workspace) {
    if (workspace.trim().isEmpty) return const [];
    final results = <RoxumSkill>[];
    final seenIds = <String>{};
    final roots = [
      Directory('$workspace${Platform.pathSeparator}.agents${Platform.pathSeparator}skills'),
      Directory('$workspace${Platform.pathSeparator}.quantum${Platform.pathSeparator}skills'),
    ];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      try {
        for (final entity in root.listSync()) {
          if (entity is! Directory) continue;
          final skillFile = File('${entity.path}${Platform.pathSeparator}SKILL.md');
          if (!skillFile.existsSync()) continue;
          final parsed = _parseSkillMarkdown(skillFile);
          if (parsed != null && seenIds.add(parsed.id)) {
            results.add(parsed);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  static RoxumSkill? _parseSkillMarkdown(File file) {
    try {
      final raw = file.readAsStringSync().trim();
      if (raw.isEmpty) return null;
      final folderName = file.parent.path.split(RegExp(r'[/\\]')).last;
      var name = folderName;
      var description = '';
      var body = raw;

      if (raw.startsWith('---')) {
        final endIdx = raw.indexOf('\n---', 3);
        if (endIdx != -1) {
          final fm = raw.substring(3, endIdx);
          body = raw.substring(endIdx + 4).trim();
          final nameMatch = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(fm);
          final descMatch = RegExp(r'^description:\s*(.+)$', multiLine: true).firstMatch(fm);
          if (nameMatch != null) {
            name = nameMatch.group(1)!.trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), '');
          }
          if (descMatch != null) {
            description = descMatch.group(1)!.trim().replaceAll(RegExp(r'^["\x27]|["\x27]$'), '');
          }
        }
      }

      final keywords = <String>{
        ...name.toLowerCase().split(RegExp(r'[^a-zа-яё0-9]+')).where((w) => w.length >= 3),
        ...description.toLowerCase().split(RegExp(r'[^a-zа-яё0-9]+')).where((w) => w.length >= 4),
      }.take(12).toList();

      final clippedBody = body.length > 1100 ? '${body.substring(0, 1100)}\n...' : body;
      return RoxumSkill(
        id: folderName,
        name: name,
        description: description,
        keywords: keywords,
        instructions: clippedBody,
        sourcePath: file.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Selects up to [maxSkills] most relevant skills for the current user prompt
  /// and active editor file, formatting a compact prompt block.
  static String buildMatchedSkillsBlock({
    required String workspace,
    required String userPrompt,
    String? activeFilePath,
    int maxSkills = 2,
  }) {
    final query = '${userPrompt.toLowerCase()} ${(activeFilePath ?? '').toLowerCase()}';
    if (query.trim().isEmpty) return '';

    final allSkills = <RoxumSkill>[
      ...loadWorkspaceSkills(workspace),
      ...builtinSkills,
    ];

    final scored = <({RoxumSkill skill, int score})>[];
    for (final skill in allSkills) {
      var score = 0;
      if (query.contains(skill.id.toLowerCase()) ||
          query.contains(skill.name.toLowerCase())) {
        score += 5;
      }
      for (final kw in skill.keywords) {
        if (kw.isNotEmpty && query.contains(kw.toLowerCase())) {
          score += skill.sourcePath != null ? 2 : 1;
        }
      }
      if (score > 0) {
        scored.add((skill: skill, score: score));
      }
    }

    if (scored.isEmpty) return '';
    scored.sort((a, b) => b.score.compareTo(a.score));

    final selected = scored.take(maxSkills).map((e) => e.skill).toList();
    final buf = StringBuffer('\n[ACTIVE AGENT SKILLS (loaded on demand)]:\n');
    for (final s in selected) {
      buf.writeln('### ${s.name}${s.sourcePath != null ? ' (workspace SKILL.md)' : ''}');
      buf.writeln(s.instructions);
    }
    return buf.toString();
  }
}
