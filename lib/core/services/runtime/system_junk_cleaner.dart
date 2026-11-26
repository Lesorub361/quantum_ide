import 'package:quantum_ide/core/services/runtime/cleanup_category.dart';

/// Builds, parses, and cleans cache/temp categories inside the guest Linux environment.
abstract final class SystemJunkCleaner {
  /// Returns the default list of cleanable cache categories.
  static List<CleanupCategory> defaultCategories({
    String? activeProjectGuestPath,
  }) {
    return [
      const CleanupCategory(
        id: 'gradle_caches',
        title: 'Кэш сборок Gradle',
        subtitle: '~/.gradle/caches, ~/.gradle/.tmp (перекачается при сборке)',
        paths: [
          '/root/.gradle/caches',
          '/root/.gradle/.tmp',
          '/root/.gradle/daemon',
        ],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'gradle_wrapper',
        title: 'Дистрибутивы Gradle Wrapper',
        subtitle: '~/.gradle/wrapper (старые версии Gradle)',
        paths: ['/root/.gradle/wrapper'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'dart_server',
        title: 'Кэш анализатора Dart',
        subtitle: '~/.dartServer (пересоздаётся автоматически)',
        paths: ['/root/.dartServer'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'npm_cache',
        title: 'Кэш npm / Node.js',
        subtitle: '~/.npm',
        paths: ['/root/.npm'],
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'apt_cache',
        title: 'Архивы пакетов APT',
        subtitle: '/var/cache/apt/archives (*.deb)',
        paths: ['/var/cache/apt/archives'],
        isAptClean: true,
        defaultSelected: true,
      ),
      const CleanupCategory(
        id: 'tmp_junk',
        title: 'Временные файлы и остатки сборок',
        subtitle: '/tmp/*, ~/rootfs-build, ~/.cache',
        paths: ['/root/rootfs-build', '/root/.cache'],
        isTmpClean: true,
        defaultSelected: true,
      ),
      if (activeProjectGuestPath != null && activeProjectGuestPath.isNotEmpty)
        CleanupCategory(
          id: 'project_build',
          title: 'Артефакты сборки проекта (build/)',
          subtitle: '$activeProjectGuestPath/build',
          paths: ['$activeProjectGuestPath/build'],
          defaultSelected: true,
        ),
      const CleanupCategory(
        id: 'pub_cache',
        title: 'Кэш пакетов Dart / Flutter (.pub-cache)',
        subtitle: '~/.pub-cache (потребуется flutter pub get)',
        paths: ['/root/.pub-cache'],
        defaultSelected: false,
      ),
    ];
  }

  /// Builds a shell command that prints `<id>=<size_in_kb>` lines for [categories].
  static String buildScanScript(List<CleanupCategory> categories) {
    final scriptLines = <String>[];
    for (final cat in categories) {
      if (cat.isTmpClean) {
        scriptLines.add(
          'KB_${cat.id}=\$(du -sk /tmp /root/rootfs-build /root/.cache 2>/dev/null | awk \'{s+=\$1} END {print s+0}\'); '
          'echo "${cat.id}=\$KB_${cat.id}"',
        );
      } else {
        final quoted = cat.paths.map((p) => '"$p"').join(' ');
        scriptLines.add(
          'KB_${cat.id}=\$(du -sk $quoted 2>/dev/null | awk \'{s+=\$1} END {print s+0}\'); '
          'echo "${cat.id}=\$KB_${cat.id}"',
        );
      }
    }
    return scriptLines.join('; ');
  }

  /// Parses `<id>=<kb>` lines from [output] and attaches sizes to [categories].
  static List<CleanupCategory> applyScanOutput(
    List<CleanupCategory> categories,
    String output,
  ) {
    final sizes = <String, int>{};
    for (final line in output.split('\n')) {
      final parts = line.trim().split('=');
      if (parts.length == 2) {
        sizes[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    return categories
        .map((c) => c.copyWith(sizeKb: sizes[c.id] ?? 0))
        .toList();
  }

  /// Builds the shell cleanup commands and returns total expected freed KB.
  static ({List<String> commands, int freedKb}) buildCleanPlan(
    List<CleanupCategory> selected,
  ) {
    var freedKb = 0;
    final cmds = <String>[];

    for (final cat in selected) {
      if (cat.sizeKb <= 0) continue;
      freedKb += cat.sizeKb;
      if (cat.isAptClean) {
        cmds.add(
          'apt-get clean 2>/dev/null || rm -rf /var/cache/apt/archives/*.deb',
        );
      } else if (cat.isTmpClean) {
        cmds.add(
          'rm -rf /root/rootfs-build /root/.cache '
          '/tmp/box64 /tmp/llama.cpp /tmp/yandex_* /tmp/.bun-* '
          '/tmp/flutter_tools.* /tmp/kotlin-daemon.* /tmp/kotlin-compiler-* '
          '/tmp/dsh-spill-* /tmp/preserved_home /tmp/pubspec*.bak '
          '/tmp/dart_analyze_output*.txt /tmp/analyze.txt /tmp/q_frame_*.png '
          '/tmp/tmp.* /tmp/aapt2 /tmp/gradle_shadow /tmp/opencode /tmp/kilo '
          '/tmp/node-compile-cache /tmp/v8-compile-cache-0 2>/dev/null || true',
        );
      } else {
        final quoted = cat.paths.map((p) => '"$p"').join(' ');
        cmds.add('rm -rf $quoted 2>/dev/null || true');
      }
    }

    return (commands: cmds, freedKb: freedKb);
  }
}
