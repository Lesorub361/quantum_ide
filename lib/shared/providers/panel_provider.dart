import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PanelTab { terminal, console, run, buildLogs, appLogs, aiAgent, servers, packages, problems, git }

class PanelState {
  final PanelTab selectedTab;
  final bool isOpened;
  final bool isMaximized;
  final double position;
  final double panelHeight;

  PanelState({
    this.selectedTab = PanelTab.terminal,
    this.isOpened = false,
    this.isMaximized = false,
    this.position = 0.0,
    this.panelHeight = 280.0,
  });

  PanelState copyWith({
    PanelTab? selectedTab,
    bool? isOpened,
    bool? isMaximized,
    double? position,
    double? panelHeight,
  }) {
    return PanelState(
      selectedTab: selectedTab ?? this.selectedTab,
      isOpened: isOpened ?? this.isOpened,
      isMaximized: isMaximized ?? this.isMaximized,
      position: position ?? this.position,
      panelHeight: panelHeight ?? this.panelHeight,
    );
  }
}

class PanelNotifier extends StateNotifier<PanelState> {
  PanelNotifier() : super(PanelState());



  void selectTab(PanelTab tab, {bool silent = false}) {
    state = state.copyWith(
      selectedTab: tab,
      isOpened: silent ? state.isOpened : true,
      position: silent ? state.position : 1.0,
    );
  }

  void updatePosition(double pos) {
    state = state.copyWith(
      position: pos,
      isOpened: pos > 0.05,
    );
  }

  void updateHeight(double height) {
    state = state.copyWith(panelHeight: height);
  }

  void toggle() {
    final nextOpened = !state.isOpened;
    state = state.copyWith(
      isOpened: nextOpened,
      position: nextOpened ? 1.0 : 0.0,
    );
  }

  void toggleMaximized() {
    state = state.copyWith(isMaximized: !state.isMaximized);
  }

  void closePanel() {
    state = state.copyWith(
      isOpened: false,
      position: 0.0,
    );
  }

  void openPanel() {
    state = state.copyWith(
      isOpened: true,
      position: 1.0,
    );
  }
}

final panelProvider = StateNotifierProvider<PanelNotifier, PanelState>((ref) {
  return PanelNotifier();
});

final serverRunningProvider = StateProvider<bool>((ref) => false);
