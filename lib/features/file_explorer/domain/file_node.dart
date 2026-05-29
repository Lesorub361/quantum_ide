import 'dart:io';

class FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  final List<FileNode> children;
  bool isExpanded;
  final int size;
  final DateTime modified;

  FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
    this.isExpanded = false,
    required this.size,
    required this.modified,
  });

  factory FileNode.fromEntity(FileSystemEntity entity) {
    int size = 0;
    DateTime modified = DateTime.now();
    try {
      final stat = entity.statSync();
      size = stat.size;
      modified = stat.modified;
    } catch (e) {
      // Ignore errors for unreadable files
    }

    return FileNode(
      name: entity.path.split(Platform.pathSeparator).last,
      path: entity.path,
      isDirectory: entity is Directory,
      size: size,
      modified: modified,
    );
  }
}
