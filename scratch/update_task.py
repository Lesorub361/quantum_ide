import sys

def update_task():
    path = "/home/lesorub/.gemini/antigravity-ide/brain/71d3bc3a-085f-4db9-bdd5-828409371e4e/task.md"
    with open(path, "r") as f:
        content = f.read()

    # Update task.md
    content = content.replace("- `[ ]` Update EditorPage layout to use `MultiSplitView`", "- `[x]` Update EditorPage layout to use `MultiSplitView`")

    with open(path, "w") as f:
        f.write(content)
    print("Done")

update_task()
