import re

path = "lib/features/editor/presentation/widgets/file_tree_node.dart"
with open(path, "r") as f:
    content = f.read()

content = content.replace("StreamSubscription<FileSystemEvent>? _watcherSubscription;", "StreamSubscription? _watcherSubscription;")

with open(path, "w") as f:
    f.write(content)
