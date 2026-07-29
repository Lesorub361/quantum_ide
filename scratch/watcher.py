import re

path = "lib/features/editor/presentation/widgets/file_tree_node.dart"
with open(path, "r") as f:
    content = f.read()

# Add watcher import if not present
if "import 'package:watcher/watcher.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:watcher/watcher.dart';")

# Find: _watcherSubscription = Directory(widget.path).watch().listen((event) {
# Replace with: _watcherSubscription = DirectoryWatcher(widget.path).events.listen((event) {

content = content.replace(
    "_watcherSubscription = Directory(widget.path).watch().listen((event) {",
    "_watcherSubscription = DirectoryWatcher(widget.path).events.listen((event) {"
)

with open(path, "w") as f:
    f.write(content)
