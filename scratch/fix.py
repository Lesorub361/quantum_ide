import re

path = "lib/features/editor/presentation/widgets/file_tree_node.dart"
with open(path, "r") as f:
    content = f.read()

content = content.replace("_handleDelete(context, ref);", "_confirmDelete(context, ref);")

# We need to find the specific pattern where ContextMenuArea was inserted.
# In our previous script, we did:
#     content = content.replace(
#         "          ),\n        ],\n      ),\n    ),\n  );\n}",
#         "          ),\n        ],\n      ),\n    ),\n    ),\n  );\n}"
#     )
# But it seems it didn't match anything.
# Let's search for:
#           ],
#         ),
#       ),
#     );
#
#     return Column(

content = content.replace(
    "          ],\n        ),\n      ),\n    );\n\n    return Column(",
    "          ],\n        ),\n      ),\n      ),\n    );\n\n    return Column("
)

with open(path, "w") as f:
    f.write(content)
