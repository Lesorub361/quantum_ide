import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

class PlanService {
  final Ref ref;

  PlanService(this.ref);

  Future<String?> savePlan(String planContent, {String? title}) async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return null;

    final plansDir = Directory(p.join(workspacePath, '.quantum', 'plans'));
    if (!await plansDir.exists()) {
      await plansDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeTitle = title != null && title.isNotEmpty
        ? title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_')
        : 'plan';
    final fileName = '${timestamp}_$safeTitle.md';
    final filePath = p.join(plansDir.path, fileName);

    final file = File(filePath);
    final header = '# Plan: ${title ?? 'Implementation Plan'}\n\n'
        '> Generated: ${DateTime.now().toLocal()}\n'
        '> Mode: Plan → Build\n\n---\n\n';
    await file.writeAsString(header + planContent);

    return filePath;
  }

  Future<List<String>> listPlans() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return [];

    final plansDir = Directory(p.join(workspacePath, '.quantum', 'plans'));
    if (!await plansDir.exists()) return [];

    final files = plansDir.listSync().whereType<File>().toList();
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files.map((f) => f.path).toList();
  }
}

final planServiceProvider = Provider<PlanService>((ref) {
  return PlanService(ref);
});
