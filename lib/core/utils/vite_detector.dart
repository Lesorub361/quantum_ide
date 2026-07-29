import 'dart:io';
import 'package:path/path.dart' as p;

class ViteProjectDetector {
  static bool isViteProject(String projectPath) {
    final packageJson = File(p.join(projectPath, 'package.json'));
    if (packageJson.existsSync()) {
      final content = packageJson.readAsStringSync();
      if (content.contains('"vite"')) return true;
    }

    final viteConfig = _findViteConfig(projectPath);
    if (viteConfig != null) return true;

    return false;
  }

  static String? _findViteConfig(String projectPath) {
    final configs = [
      'vite.config.js',
      'vite.config.ts',
      'vite.config.mjs',
      'vite.config.mts',
      'vite.config.cjs',
    ];
    for (final config in configs) {
      final file = File(p.join(projectPath, config));
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  static String? detectDevCommand(String projectPath) {
    final packageJson = File(p.join(projectPath, 'package.json'));
    if (packageJson.existsSync()) {
      try {
        final content = packageJson.readAsStringSync();
        if (content.contains('"dev"')) return 'npm run dev';
        if (content.contains('"start"')) return 'npm start';
      } catch (_) {}
    }
    return 'npx vite';
  }

  static int detectDefaultPort(String projectPath) {
    return 5173;
  }
}
