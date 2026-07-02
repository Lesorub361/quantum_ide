import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

enum DependencyStatus { upToDate, outdated, vulnerable }

class DependencyInfo {
  final String name;
  final String currentVersion;
  final String? latestVersion;
  final DependencyStatus status;

  const DependencyInfo({
    required this.name,
    required this.currentVersion,
    this.latestVersion,
    required this.status,
  });
}

class DependencyCheckerState {
  final List<DependencyInfo> dependencies;
  final bool isLoading;
  final int outdatedCount;

  const DependencyCheckerState({
    this.dependencies = const [],
    this.isLoading = false,
    this.outdatedCount = 0,
  });

  DependencyCheckerState copyWith({
    List<DependencyInfo>? dependencies,
    bool? isLoading,
    int? outdatedCount,
  }) {
    return DependencyCheckerState(
      dependencies: dependencies ?? this.dependencies,
      isLoading: isLoading ?? this.isLoading,
      outdatedCount: outdatedCount ?? this.outdatedCount,
    );
  }
}

class DependencyCheckerNotifier extends StateNotifier<DependencyCheckerState> {
  final Ref _ref;

  DependencyCheckerNotifier(this._ref) : super(const DependencyCheckerState());

  Future<void> check() async {
    final workspacePath = _ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    state = state.copyWith(isLoading: true);

    final pubspecFile = File(p.join(workspacePath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      state = state.copyWith(isLoading: false, dependencies: []);
      return;
    }

    try {
      final content = await pubspecFile.readAsString();
      final deps = <DependencyInfo>[];
      bool inDeps = false;
      bool inDevDeps = false;

      for (final line in content.split('\n')) {
        final trimmed = line.trim();

        if (trimmed == 'dependencies:') {
          inDeps = true;
          inDevDeps = false;
          continue;
        }
        if (trimmed == 'dev_dependencies:') {
          inDeps = false;
          inDevDeps = true;
          continue;
        }
        if (trimmed.startsWith('flutter:') || trimmed.startsWith('sdk:') || trimmed.isEmpty) {
          if (trimmed.isNotEmpty && !trimmed.startsWith(' ')) {
            inDeps = false;
            inDevDeps = false;
          }
        }

        if ((inDeps || inDevDeps) && trimmed.contains(':') && !trimmed.startsWith('#')) {
          final parts = trimmed.split(':');
          if (parts.length >= 2) {
            final name = parts[0].trim();
            final version = parts[1].trim().replaceAll('^', '').replaceAll('"', '');

            if (name == 'flutter' || name == 'sdk' || name == 'dev_dependencies' || name == 'dependencies') continue;

            deps.add(DependencyInfo(
              name: name,
              currentVersion: version,
              status: DependencyStatus.upToDate,
            ));
          }
        }
      }

      final outdatedCount = deps.where((d) => d.status == DependencyStatus.outdated).length;

      state = state.copyWith(
        dependencies: deps,
        isLoading: false,
        outdatedCount: outdatedCount,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, dependencies: []);
    }
  }
}

final dependencyCheckerProvider = StateNotifierProvider<DependencyCheckerNotifier, DependencyCheckerState>((ref) {
  return DependencyCheckerNotifier(ref);
});
