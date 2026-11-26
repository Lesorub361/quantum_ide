import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/runtime/system_junk_cleaner.dart';

void main() {
  group('SystemJunkCleaner', () {
    test('defaultCategories includes project_build only when path provided', () {
      final withoutProject = SystemJunkCleaner.defaultCategories();
      expect(withoutProject.any((c) => c.id == 'project_build'), isFalse);

      final withProject = SystemJunkCleaner.defaultCategories(
        activeProjectGuestPath: '/root/projects/demo',
      );
      final proj = withProject.firstWhere((c) => c.id == 'project_build');
      expect(proj.paths, ['/root/projects/demo/build']);
    });

    test('applyScanOutput maps du output to categories and buildCleanPlan sums freedKb', () {
      final cats = SystemJunkCleaner.defaultCategories();
      final scanned = SystemJunkCleaner.applyScanOutput(
        cats,
        'gradle_caches=1024\napt_cache=512\nunknown=999\n',
      );

      final plan = SystemJunkCleaner.buildCleanPlan(scanned);
      expect(plan.freedKb, 1536);
      expect(plan.commands.length, 2);
      expect(plan.commands[1], contains('apt-get clean'));
    });
  });
}
