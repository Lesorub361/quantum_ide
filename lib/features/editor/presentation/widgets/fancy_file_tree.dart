import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_fancy_tree_view/flutter_fancy_tree_view.dart';
import 'package:quantum_ide/features/file_explorer/domain/file_node.dart';

class FancyFileTree extends ConsumerStatefulWidget {
  final String rootPath;
  const FancyFileTree({super.key, required this.rootPath});

  @override
  ConsumerState<FancyFileTree> createState() => _FancyFileTreeState();
}

class _FancyFileTreeState extends ConsumerState<FancyFileTree> {
  late TreeController<FileNode> treeController;
  late List<FileNode> roots = [];

  @override
  void initState() {
    super.initState();
    treeController = TreeController<FileNode>(
      roots: roots,
      childrenProvider: (FileNode node) => node.children,
    );
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    final dir = Directory(widget.rootPath);
    if (!await dir.exists()) return;
    
    final entities = await dir.list().toList();
    setState(() {
      roots = entities.map((e) => FileNode.fromEntity(e)).toList();
      treeController.roots = roots;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TreeView<FileNode>(
      treeController: treeController,
      nodeBuilder: (BuildContext context, TreeEntry<FileNode> entry) {
        return InkWell(
          onTap: () {
            treeController.toggleExpansion(entry.node);
          },
          child: TreeIndentation(
            entry: entry,
            child: Row(
              children: [
                if (entry.node.isDirectory)
                  Icon(
                    entry.isExpanded ? Icons.folder_open : Icons.folder,
                    size: 16,
                  )
                else
                  const Icon(Icons.insert_drive_file, size: 16),
                const SizedBox(width: 8),
                Text(entry.node.name),
              ],
            ),
          ),
        );
      },
    );
  }
}
