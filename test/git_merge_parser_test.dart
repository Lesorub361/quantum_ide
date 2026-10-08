import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/features/git/presentation/pages/git_merge_conflict_page.dart';

void main() {
  group('Git Merge Conflict Parser Tests', () {
    test('Parse file without conflicts', () {
      const content = '''
void main() {
  print("Hello, World!");
}
''';
      final chunks = parseMergeConflicts(content);
      expect(chunks.length, equals(1));
      expect(chunks[0], isA<TextChunk>());
      expect((chunks[0] as TextChunk).text, contains('Hello, World!'));
    });

    test('Parse file with single conflict (standard style)', () {
      const content = '''
before
<<<<<<< HEAD
our change
=======
their change
>>>>>>> main
after
''';
      final chunks = parseMergeConflicts(content);
      expect(chunks.length, equals(3));
      
      expect(chunks[0], isA<TextChunk>());
      expect((chunks[0] as TextChunk).text.trim(), equals('before'));
      
      expect(chunks[1], isA<ConflictChunk>());
      final conflict = chunks[1] as ConflictChunk;
      expect(conflict.ourContent.trim(), equals('our change'));
      expect(conflict.theirContent.trim(), equals('their change'));
      expect(conflict.branchName, equals('main'));
      
      expect(chunks[2], isA<TextChunk>());
      expect((chunks[2] as TextChunk).text.trim(), equals('after'));
    });

    test('Parse file with diff3 style conflict', () {
      const content = '''
prefix
<<<<<<< HEAD
our block
||||||| merged common ancestors
base block
=======
their block
>>>>>>> feature-branch
suffix
''';
      final chunks = parseMergeConflicts(content);
      expect(chunks.length, equals(3));
      
      expect(chunks[0], isA<TextChunk>());
      expect((chunks[0] as TextChunk).text.trim(), equals('prefix'));
      
      expect(chunks[1], isA<ConflictChunk>());
      final conflict = chunks[1] as ConflictChunk;
      expect(conflict.ourContent.trim(), equals('our block'));
      expect(conflict.baseContent.trim(), equals('base block'));
      expect(conflict.theirContent.trim(), equals('their block'));
      expect(conflict.branchName, equals('feature-branch'));
      
      expect(chunks[2], isA<TextChunk>());
      expect((chunks[2] as TextChunk).text.trim(), equals('suffix'));
    });

    test('Multiple conflicts and trailing empty lines', () {
      const content = '''
start
<<<<<<< HEAD
first our
=======
first their
>>>>>>> branch-a
middle
<<<<<<< HEAD
second our
=======
second their
>>>>>>> branch-b
end
''';
      final chunks = parseMergeConflicts(content);
      expect(chunks.length, equals(5));
      
      expect(chunks[0], isA<TextChunk>());
      expect((chunks[0] as TextChunk).text.trim(), equals('start'));
      
      expect(chunks[1], isA<ConflictChunk>());
      expect((chunks[1] as ConflictChunk).ourContent.trim(), equals('first our'));
      
      expect(chunks[2], isA<TextChunk>());
      expect((chunks[2] as TextChunk).text.trim(), equals('middle'));
      
      expect(chunks[3], isA<ConflictChunk>());
      expect((chunks[3] as ConflictChunk).ourContent.trim(), equals('second our'));
      
      expect(chunks[4], isA<TextChunk>());
      expect((chunks[4] as TextChunk).text.trim(), equals('end'));
    });
  });
}
