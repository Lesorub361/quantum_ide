import re

with open("lib/features/editor/presentation/widgets/file_tree_node.dart", "r") as f:
    content = f.read()

# Let's add contextmenu import
if "import 'package:contextmenu/contextmenu.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:contextmenu/contextmenu.dart';")

# Find _buildNode and inject ContextMenuArea
build_node_def = "  Widget _buildNode(Color gitColor, bool isSelected, bool isExpanded) {"
if build_node_def in content:
    # Find child: Container(
    # We want to wrap Container in ContextMenuArea
    inkwell_start = "child: Container("
    
    context_menu_builder = """
        builder: (context) => [
          MenuItem(
            label: 'New File',
            icon: Icons.note_add,
            onSelected: () => _showCreateDialog(false),
          ),
          MenuItem(
            label: 'New Folder',
            icon: Icons.create_new_folder,
            onSelected: () => _showCreateDialog(true),
          ),
          const MenuDivider(),
          MenuItem(
            label: 'Rename',
            icon: Icons.edit,
            onSelected: () {
              setState(() {
                _isRenaming = true;
                _inlineController = TextEditingController(text: widget.name);
                _inlineFocusNode.requestFocus();
              });
            },
          ),
          MenuItem(
            label: 'Delete',
            icon: Icons.delete,
            onSelected: _deleteNode,
          ),
          const MenuDivider(),
          MenuItem(
            label: 'Copy Path',
            icon: Icons.copy,
            onSelected: () => Clipboard.setData(ClipboardData(text: widget.path)),
          ),
        ],
"""
    
    if "ContextMenuArea(" not in content:
        content = content.replace(
            "      onLongPress: () => _showBottomSheetMenu(context, ref),\n      child: Container(",
            "      onLongPress: () => _showBottomSheetMenu(context, ref),\n      child: ContextMenuArea(\n" + context_menu_builder + "        child: Container("
        )
        content = content.replace(
            "          child: Row(\n            children: [\n              ...indentGuides,",
            "          )\n          child: Row(\n            children: [\n              ...indentGuides,"
        )
        # Fix formatting of closing parenthesis
        content = content.replace(
            "          )\n          child: Row",
            "          ),\n          child: Row"
        )
        # Wait, the closing of ContextMenuArea needs to be after Container
        # Let's just use python re to do it accurately
        
with open("lib/features/editor/presentation/widgets/file_tree_node.dart", "w") as f:
    f.write(content)
