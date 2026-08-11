import 'package:flutter_riverpod/flutter_riverpod.dart';

class FoldableLayoutState {
  final bool isFolded;
  final double foldAngle;
  final bool splitEnabled;
  
  FoldableLayoutState({
    this.isFolded = false,
    this.foldAngle = 180.0,
    this.splitEnabled = false,
  });
  
  FoldableLayoutState copyWith({
    bool? isFolded,
    double? foldAngle,
    bool? splitEnabled,
  }) {
    return FoldableLayoutState(
      isFolded: isFolded ?? this.isFolded,
      foldAngle: foldAngle ?? this.foldAngle,
      splitEnabled: splitEnabled ?? this.splitEnabled,
    );
  }
}

class FoldableSplitManager extends StateNotifier<FoldableLayoutState> {
  FoldableSplitManager() : super(FoldableLayoutState());
  
  void updateFoldMetrics({
    required bool isFolded,
    required double foldAngle,
  }) {
    state = state.copyWith(
      isFolded: isFolded,
      foldAngle: foldAngle,
      splitEnabled: isFolded && foldAngle < 150.0, // Enable split when partially folded
    );
  }
}

final foldableSplitManagerProvider = StateNotifierProvider<FoldableSplitManager, FoldableLayoutState>((ref) {
  return FoldableSplitManager();
});
