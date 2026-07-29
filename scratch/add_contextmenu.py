import re

path = "lib/features/editor/presentation/widgets/file_tree_node.dart"
with open(path, "r") as f:
    content = f.read()

# Let's add contextmenu import
if "import 'package:contextmenu/contextmenu.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:contextmenu/contextmenu.dart';")

# Replace child: Container( with ContextMenuArea wrapping it.
# We will use simple ListTile items for context menu.

context_menu = """      child: ContextMenuArea(
        builder: (context) => [
          ListTile(
            leading: const Icon(LucideIcons.file_plus, size: 16),
            title: const Text('New File', style: TextStyle(fontSize: 14)),
            dense: true,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _inlineController = TextEditingController();
                _isCreatingFile = true;
                _isCreatingFolder = false;
                _inlineFocusNode.requestFocus();
              });
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.folder_plus, size: 16),
            title: const Text('New Folder', style: TextStyle(fontSize: 14)),
            dense: true,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _inlineController = TextEditingController();
                _isCreatingFolder = true;
                _isCreatingFile = false;
                _inlineFocusNode.requestFocus();
              });
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(LucideIcons.pencil, size: 16),
            title: const Text('Rename', style: TextStyle(fontSize: 14)),
            dense: true,
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _inlineController = TextEditingController(text: widget.name);
                _isRenaming = true;
                _inlineFocusNode.requestFocus();
              });
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.trash_2, size: 16, color: Colors.redAccent),
            title: const Text('Delete', style: TextStyle(fontSize: 14, color: Colors.redAccent)),
            dense: true,
            onTap: () {
              Navigator.pop(context);
              _handleDelete(context, ref);
            },
          ),
        ],
        child: Container("""

# In file_tree_node.dart, we have:
#       onLongPress: () => _showBottomSheetMenu(context, ref),
#       child: Container(
#         decoration: isSelected
if "child: ContextMenuArea(" not in content:
    content = content.replace(
        "      onLongPress: () => _showBottomSheetMenu(context, ref),\n      child: Container(",
        "      onLongPress: () => _showBottomSheetMenu(context, ref),\n" + context_menu
    )
    
    # Now we need to close the ContextMenuArea parentheses at the end of InkWell
    # Looking for:
    #           ),
    #         ],
    #       ),
    #     ),
    #   );
    
    content = content.replace(
        "          ),\n        ],\n      ),\n    ),\n  );\n}",
        "          ),\n        ],\n      ),\n    ),\n    ),\n  );\n}"
    )

with open(path, "w") as f:
    f.write(content)

