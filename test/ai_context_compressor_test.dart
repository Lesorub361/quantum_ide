import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/ai_context_compressor.dart';

void main() {
  group('AiContextCompressor Tests', () {
    late Directory tempDir;
    late AiContextCompressor compressor;

    setUp(() async {
      // Create a temporary test workspace inside the user's workspace test directory
      final baseDir = Directory.current.path;
      tempDir = Directory(p.join(baseDir, 'test_temp_workspace'));
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);
      
      compressor = AiContextCompressor();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('First run displays full file structure, subsequent runs use delta mode', () async {
      // 1. Setup initial files
      final fileA = File(p.join(tempDir.path, 'file_a.dart'));
      await fileA.writeAsString('// File A');

      final fileB = File(p.join(tempDir.path, 'file_b.dart'));
      await fileB.writeAsString('// File B');

      // 2. First call (should show full file structure)
      final context1 = await compressor.getCompressedContext(
        workspaceRoot: tempDir.path,
        openFiles: ['file_a.dart'],
        activeFile: 'file_a.dart',
        diagnostics: {},
      );

      expect(context1, contains('Структура файлов проекта (Project Files Structure):'));
      expect(context1, contains('- file_a.dart'));
      expect(context1, contains('- file_b.dart'));
      expect(context1, isNot(contains('Префиксная память: Структура файлов кэширована')));

      // 3. Second call with no changes (should show delta cache notification and no file additions)
      final context2 = await compressor.getCompressedContext(
        workspaceRoot: tempDir.path,
        openFiles: ['file_a.dart'],
        activeFile: 'file_a.dart',
        diagnostics: {},
      );

      expect(context2, contains('Префиксная память: Структура файлов кэширована в контексте'));
      expect(context2, isNot(contains('Добавленные файлы')));
      expect(context2, isNot(contains('Удаленные файлы')));

      // 4. Third call after adding and removing a file
      await fileB.delete();
      final fileC = File(p.join(tempDir.path, 'file_c.dart'));
      await fileC.writeAsString('// File C');

      final context3 = await compressor.getCompressedContext(
        workspaceRoot: tempDir.path,
        openFiles: ['file_a.dart'],
        activeFile: 'file_a.dart',
        diagnostics: {},
      );

      expect(context3, contains('Префиксная память: Структура файлов кэширована в контексте'));
      expect(context3, contains('Добавленные файлы (Added files since last turn):'));
      expect(context3, contains('+ file_c.dart'));
      expect(context3, contains('Удаленные файлы (Removed files since last turn):'));
      expect(context3, contains('- file_b.dart'));

      // 5. Reset forces full structure again
      compressor.reset();
      final context4 = await compressor.getCompressedContext(
        workspaceRoot: tempDir.path,
        openFiles: ['file_a.dart'],
        activeFile: 'file_a.dart',
        diagnostics: {},
      );
      expect(context4, contains('Структура файлов проекта (Project Files Structure):'));
      expect(context4, contains('- file_a.dart'));
      expect(context4, contains('- file_c.dart'));
    });
  });
}
