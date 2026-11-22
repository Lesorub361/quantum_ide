import 'dart:io';

import 'package:path/path.dart' as p;

/// Converts paths reported by the Android host, the PRoot guest and the IDE
/// into one canonical workspace path.  Keep this class free of Flutter state so
/// every tool and MCP adapter can use the same security rules.
class WorkspacePathException implements Exception {
  final String message;
  const WorkspacePathException(this.message);
  @override
  String toString() => message;
}

class WorkspacePathResolver {
  final String workspace;
  final String? androidFilesDir;

  WorkspacePathResolver(String workspace, {this.androidFilesDir})
    : workspace = p.normalize(Directory(workspace).absolute.path);

  String toHostPath(String inputPath, {bool enforceSandbox = true}) {
    final input = inputPath.trim();
    if (input.isEmpty || input == '.') return workspace;
    final guest = p.normalize(input);
    String candidate;
    final root = p.normalize(workspace);
    final files = androidFilesDir == null
        ? null
        : p.normalize(Directory(androidFilesDir!).absolute.path);

    if (p.isAbsolute(guest)) {
      if (p.isWithin('/root/projects', guest) || guest == '/root/projects') {
        final rel = guest == '/root/projects'
            ? ''
            : p.relative(guest, from: '/root/projects');
        candidate = _fromGuestProjects(root, rel);
      } else if (files != null &&
          (guest == p.join(files, 'projects') ||
              p.isWithin(p.join(files, 'projects'), guest))) {
        candidate = p.join(
          p.dirname(root),
          p.relative(guest, from: p.join(files, 'projects')),
        );
      } else {
        candidate = guest;
      }
    } else {
      candidate = p.join(root, guest);
    }
    candidate = p.normalize(candidate);
    if (enforceSandbox && !_inside(root, candidate)) {
      throw WorkspacePathException(
        'Path is outside the workspace: "$inputPath". Use a path inside "$root".',
      );
    }
    return candidate;
  }

  String toProotPath(String inputPath) {
    final relative = toRelativePath(inputPath);
    return relative == '.'
        ? '/root/projects/${p.basename(workspace)}'
        : '/root/projects/${p.basename(workspace)}/$relative';
  }

  String toRelativePath(String inputPath) {
    final host = toHostPath(inputPath);
    return host == workspace ? '.' : p.relative(host, from: workspace);
  }

  bool _inside(String root, String value) =>
      value == root || p.isWithin(root, value);

  String _fromGuestProjects(String current, String relative) {
    if (relative.isEmpty) return p.dirname(current);
    final parts = p.split(relative);
    if (parts.first == p.basename(current)) {
      return p.joinAll([current, ...parts.skip(1)]);
    }
    return p.joinAll([p.dirname(current), ...parts]);
  }
}
