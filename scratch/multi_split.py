import sys

def modify_editor_page():
    path = "lib/features/editor/presentation/pages/editor_page.dart"
    with open(path, "r") as f:
        content = f.read()

    # We need to replace the _buildDesktopMultiSplit helper

    old_helper = """
  Widget _buildDesktopMultiSplit(Widget mainContent, bool leftOpen, bool rightOpen) {
    if (!leftOpen && !rightOpen) return mainContent;

    final children = <Widget>[];
    final weights = <double>[];
    
    if (leftOpen) {
      children.add(const FileDrawer(isInline: true));
      weights.add(0.2);
    }
    
    children.add(mainContent);
    weights.add(leftOpen && rightOpen ? 0.5 : (leftOpen || rightOpen ? 0.8 : 1.0));
    
    if (rightOpen) {
      children.add(const RightChatPanel(isInline: true));
      weights.add(0.3);
    }

    final controller = MultiSplitViewController(
      areas: [
        for (int i = 0; i < children.length; i++)
          Area(weight: weights[i], minimalSize: 150),
      ],
    );

    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerPainter: DividerPainters.grooved1(
          color: Colors.white12,
          highlightedColor: Colors.cyan.withOpacity(0.5),
        ),
      ),
      child: MultiSplitView(
        controller: controller,
        children: children,
      ),
    );
  }
"""

    new_helper = """
  Widget _buildDesktopMultiSplit(Widget mainContent, bool leftOpen, bool rightOpen) {
    if (!leftOpen && !rightOpen) return mainContent;

    final areas = <Area>[];
    
    if (leftOpen) {
      areas.add(Area(
        flex: 0.2, 
        min: 150, 
        builder: (context, area) => const FileDrawer(isInline: true)
      ));
    }
    
    areas.add(Area(
      flex: leftOpen && rightOpen ? 0.5 : (leftOpen || rightOpen ? 0.8 : 1.0),
      min: 200,
      builder: (context, area) => mainContent
    ));
    
    if (rightOpen) {
      areas.add(Area(
        flex: 0.3,
        min: 150,
        builder: (context, area) => const RightChatPanel(isInline: true)
      ));
    }

    final controller = MultiSplitViewController(areas: areas);

    return MultiSplitViewTheme(
      data: MultiSplitViewThemeData(
        dividerPainter: DividerPainters.grooved1(
          color: Colors.white12,
          highlightedColor: Colors.cyan.withValues(alpha: 0.5),
        ),
      ),
      child: MultiSplitView(
        controller: controller,
      ),
    );
  }
"""

    content = content.replace(old_helper, new_helper)

    with open(path, "w") as f:
        f.write(content)
    
    print("Done editing editor_page.dart")

if __name__ == "__main__":
    modify_editor_page()
