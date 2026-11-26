import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/models/ai_agent_models.dart';
import 'package:quantum_ide/core/services/ai/chat_session_store.dart';

void main() {
  group('ChatSessionStore', () {
    late Directory tempDir;
    late ChatSessionStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('quantum_session_test_');
      store = const ChatSessionStore();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves, loads, sorts by updatedAt, and deletes sessions', () async {
      final older = ChatSession(
        id: 's-old',
        title: 'Older',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        messages: [
          ChatMessage(
            id: 'm1',
            role: MessageRole.user,
            text: 'hi',
            timestamp: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final newer = ChatSession(
        id: 's-new',
        title: 'Newer',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
        messages: [
          ChatMessage(
            id: 'm2',
            role: MessageRole.user,
            text: 'hello',
            timestamp: DateTime.utc(2026, 1, 2),
          ),
        ],
      );

      await store.save(tempDir.path, older);
      await store.save(tempDir.path, newer);

      final loaded = await store.loadAll(tempDir.path);
      expect(loaded.map((s) => s.id), ['s-new', 's-old']);

      final fetched = await store.loadById(tempDir.path, 's-old');
      expect(fetched?.title, 'Older');

      await store.deleteById(tempDir.path, 's-old');
      expect(await store.loadById(tempDir.path, 's-old'), isNull);
    });

    test('migrates legacy chat_history.json into chat_sessions', () async {
      final legacyDir = Directory(p.join(tempDir.path, '.quantum'));
      await legacyDir.create(recursive: true);
      final legacyFile = File(p.join(legacyDir.path, 'chat_history.json'));
      await legacyFile.writeAsString(jsonEncode([
        {
          'id': 'legacy-1',
          'title': 'Legacy',
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
          'messages': [
            {
              'id': 'm1',
              'role': 'user',
              'text': 'from legacy',
              'timestamp': '2026-01-01T00:00:00Z',
            }
          ],
        }
      ]));

      final loaded = await store.loadAll(tempDir.path);
      expect(loaded.map((s) => s.id), ['legacy-1']);
      expect(
        File(p.join(legacyDir.path, 'chat_sessions', 'legacy-1.json'))
            .existsSync(),
        isTrue,
      );
    });
  });
}
