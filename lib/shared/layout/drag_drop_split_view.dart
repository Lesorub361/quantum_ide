import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplitPanel {
  final String id;
  final List<String> tabIds;
  final String? activeTabId;
  final double widthRatio;

  SplitPanel({
    required this.id,
    this.tabIds = const [],
    this.activeTabId,
    this.widthRatio = 1.0,
  });

  SplitPanel copyWith({
    List<String>? tabIds,
    String? activeTabId,
    double? widthRatio,
  }) {
    return SplitPanel(
      id: id,
      tabIds: tabIds ?? this.tabIds,
      activeTabId: activeTabId ?? this.activeTabId,
      widthRatio: widthRatio ?? this.widthRatio,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tabIds': tabIds,
    'activeTabId': activeTabId,
    'widthRatio': widthRatio,
  };

  factory SplitPanel.fromJson(Map<String, dynamic> json) => SplitPanel(
    id: json['id'] ?? '',
    tabIds: (json['tabIds'] as List?)?.cast<String>() ?? [],
    activeTabId: json['activeTabId'],
    widthRatio: (json['widthRatio'] as num?)?.toDouble() ?? 1.0,
  );
}

class DragDropSplitState {
  final List<SplitPanel> panels;
  final int activePanelIndex;
  final int columnCount;
  final bool isDragging;
  final String? draggedTabId;
  final double? dragOverX;

  DragDropSplitState({
    this.panels = const [],
    this.activePanelIndex = 0,
    this.columnCount = 1,
    this.isDragging = false,
    this.draggedTabId,
    this.dragOverX,
  });

  DragDropSplitState copyWith({
    List<SplitPanel>? panels,
    int? activePanelIndex,
    int? columnCount,
    bool? isDragging,
    String? draggedTabId,
    double? dragOverX,
  }) {
    return DragDropSplitState(
      panels: panels ?? this.panels,
      activePanelIndex: activePanelIndex ?? this.activePanelIndex,
      columnCount: columnCount ?? this.columnCount,
      isDragging: isDragging ?? this.isDragging,
      draggedTabId: draggedTabId,
      dragOverX: dragOverX,
    );
  }

  Map<String, dynamic> toJson() => {
    'panels': panels.map((p) => p.toJson()).toList(),
    'activePanelIndex': activePanelIndex,
    'columnCount': columnCount,
  };

  factory DragDropSplitState.fromJson(Map<String, dynamic> json) => DragDropSplitState(
    panels: (json['panels'] as List?)?.map((e) => SplitPanel.fromJson(e)).toList() ?? [],
    activePanelIndex: json['activePanelIndex'] ?? 0,
    columnCount: json['columnCount'] ?? 1,
  );
}

class DragDropSplitController extends StateNotifier<DragDropSplitState> {
  static const _prefKey = 'drag_drop_layout';
  static const _dividerWidth = 4.0;

  DragDropSplitController() : super(DragDropSplitState(panels: [SplitPanel(id: 'panel-0')])) {
    _loadLayout();
  }

  Future<void> _loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefKey);
    if (json != null) {
      try {
        final parsed = DragDropSplitState.fromJson(
          Map<String, dynamic>.from(_decodeJson(json) as Map),
        );
        if (parsed.panels.isNotEmpty) {
          state = parsed;
          return;
        }
      } catch (_) {}
    }
  }

  dynamic _decodeJson(String json) {
    return Map<String, dynamic>.from(
      (jsonDecode(json) as Map).map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(state.toJson()));
  }

  void setColumnCount(int count) {
    final clamped = count.clamp(1, 3);
    if (clamped == state.columnCount) return;

    final panels = List<SplitPanel>.from(state.panels);
    while (panels.length < clamped) {
      panels.add(SplitPanel(id: 'panel-${panels.length}'));
    }
    while (panels.length > clamped) {
      panels.removeLast();
    }

    final ratio = 1.0 / clamped;
    state = state.copyWith(
      columnCount: clamped,
      panels: panels.map((p) => p.copyWith(widthRatio: ratio)).toList(),
      activePanelIndex: state.activePanelIndex.clamp(0, clamped - 1),
    );
    _saveLayout();
  }

  void setActivePanel(int index) {
    state = state.copyWith(activePanelIndex: index.clamp(0, state.panels.length - 1));
  }

  void updatePanelWidth(int panelIndex, double ratio) {
    final panels = List<SplitPanel>.from(state.panels);
    if (panelIndex < 0 || panelIndex >= panels.length) return;
    panels[panelIndex] = panels[panelIndex].copyWith(
      widthRatio: ratio.clamp(0.15, 0.7),
    );
    state = state.copyWith(panels: panels);
    _saveLayout();
  }

  void addTabToPanel(int panelIndex, String tabId) {
    final panels = List<SplitPanel>.from(state.panels);
    if (panelIndex < 0 || panelIndex >= panels.length) return;
    final panel = panels[panelIndex];
    if (panel.tabIds.contains(tabId)) return;
    panels[panelIndex] = panel.copyWith(
      tabIds: [...panel.tabIds, tabId],
      activeTabId: tabId,
    );
    state = state.copyWith(panels: panels, activePanelIndex: panelIndex);
    _saveLayout();
  }

  void removeTabFromPanel(int panelIndex, String tabId) {
    final panels = List<SplitPanel>.from(state.panels);
    if (panelIndex < 0 || panelIndex >= panels.length) return;
    final panel = panels[panelIndex];
    final newTabs = panel.tabIds.where((t) => t != tabId).toList();
    panels[panelIndex] = panel.copyWith(
      tabIds: newTabs,
      activeTabId: panel.activeTabId == tabId
          ? (newTabs.isNotEmpty ? newTabs.last : null)
          : panel.activeTabId,
    );
    state = state.copyWith(panels: panels);
    _saveLayout();
  }

  void moveTabToPanel(String tabId, int fromPanel, int toPanel) {
    if (fromPanel == toPanel) return;
    removeTabFromPanel(fromPanel, tabId);
    addTabToPanel(toPanel, tabId);
  }

  void setActiveTab(int panelIndex, String tabId) {
    final panels = List<SplitPanel>.from(state.panels);
    if (panelIndex < 0 || panelIndex >= panels.length) return;
    panels[panelIndex] = panels[panelIndex].copyWith(activeTabId: tabId);
    state = state.copyWith(panels: panels);
  }

  void startDrag(String tabId) {
    state = state.copyWith(isDragging: true, draggedTabId: tabId);
  }

  void endDrag() {
    state = state.copyWith(isDragging: false, draggedTabId: null, dragOverX: null);
  }

  void updateDragPosition(double x) {
    state = state.copyWith(dragOverX: x);
  }

  int getTargetPanel(double dragX, double totalWidth) {
    double accumulated = 0;
    for (int i = 0; i < state.panels.length; i++) {
      accumulated += state.panels[i].widthRatio * totalWidth;
      if (dragX <= accumulated) return i;
    }
    return state.panels.length - 1;
  }

  static double get dividerWidth => _dividerWidth;
}

final dragDropSplitProvider =
    StateNotifierProvider<DragDropSplitController, DragDropSplitState>((ref) {
  return DragDropSplitController();
});

class DragDropSplitView extends ConsumerStatefulWidget {
  final Widget Function(int panelIndex, String tabId) tabBuilder;
  final Widget Function(int panelIndex) panelHeaderBuilder;
  final Widget? Function(int panelIndex)? emptyPanelBuilder;

  const DragDropSplitView({
    super.key,
    required this.tabBuilder,
    required this.panelHeaderBuilder,
    this.emptyPanelBuilder,
  });

  @override
  ConsumerState<DragDropSplitView> createState() => _DragDropSplitViewState();
}

class _DragDropSplitViewState extends ConsumerState<DragDropSplitView> {
  final List<double> _panelWidths = [];

  @override
  Widget build(BuildContext context) {
    final splitState = ref.watch(dragDropSplitProvider);
    final controller = ref.read(dragDropSplitProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final dividerTotal = DragDropSplitController.dividerWidth * (splitState.columnCount - 1);
        final availableWidth = totalWidth - dividerTotal;

        _panelWidths.clear();
        for (final panel in splitState.panels) {
          _panelWidths.add(availableWidth * panel.widthRatio);
        }

        return Row(
          children: [
            for (int i = 0; i < splitState.panels.length; i++) ...[
              Expanded(
                flex: (splitState.panels[i].widthRatio * 1000).toInt(),
                child: _buildPanel(splitState, i),
              ),
              if (i < splitState.panels.length - 1)
                _buildDivider(i, controller),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPanel(DragDropSplitState splitState, int panelIndex) {
    final panel = splitState.panels[panelIndex];
    final isActive = panelIndex == splitState.activePanelIndex;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        ref.read(dragDropSplitProvider.notifier).setActivePanel(panelIndex);
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (details) {
          final fromPanel = _findPanelWithTab(details.data);
          if (fromPanel != null) {
            ref.read(dragDropSplitProvider.notifier).moveTabToPanel(
              details.data,
              fromPanel,
              panelIndex,
            );
          }
        },
        builder: (context, candidateData, rejectedData) {
          final isDragOver = candidateData.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: isActive
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.surfaceContainerLow,
              border: isDragOver
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            child: Column(
              children: [
                widget.panelHeaderBuilder(panelIndex),
                Expanded(
                  child: panel.tabIds.isEmpty
                      ? (widget.emptyPanelBuilder?.call(panelIndex) ??
                          Center(
                            child: Text(
                              'Drag tabs here',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                              ),
                            ),
                          ))
                      : _buildTabContent(panel),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent(SplitPanel panel) {
    final activeTabId = panel.activeTabId ?? (panel.tabIds.isNotEmpty ? panel.tabIds.first : null);
    if (activeTabId == null) {
      return const Center(child: Text('No tabs'));
    }
    return widget.tabBuilder(
      ref.read(dragDropSplitProvider).panels.indexOf(panel),
      activeTabId,
    );
  }

  Widget _buildDivider(int panelIndex, DragDropSplitController controller) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final state = ref.read(dragDropSplitProvider);
        if (panelIndex >= state.panels.length - 1) return;
        final totalRatio = state.panels[panelIndex].widthRatio +
            state.panels[panelIndex + 1].widthRatio;
        final delta = details.delta.dx;
        final newRatio = (state.panels[panelIndex].widthRatio + delta * 0.002).clamp(0.15, totalRatio - 0.15);
        controller.updatePanelWidth(panelIndex, newRatio);
        controller.updatePanelWidth(panelIndex + 1, totalRatio - newRatio);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: DragDropSplitController.dividerWidth,
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(100),
        ),
      ),
    );
  }

  int? _findPanelWithTab(String tabId) {
    final panels = ref.read(dragDropSplitProvider).panels;
    for (int i = 0; i < panels.length; i++) {
      if (panels[i].tabIds.contains(tabId)) return i;
    }
    return null;
  }
}

class DragDropTab extends StatelessWidget {
  final String tabId;
  final String label;
  final Widget child;
  final VoidCallback? onClose;

  const DragDropTab({
    super.key,
    required this.tabId,
    required this.label,
    required this.child,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Draggable<String>(
      data: tabId,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: child,
      ),
      child: child,
    );
  }
}
