import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/quantum_ai_agent_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Quantum AI Agent Chat History & Persistence Tests', () {
    late Directory tempDir;
    late RuntimeService runtime;
    late SettingsState settings;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('quantum_test_ws_');
      runtime = RuntimeService();
      settings = SettingsState(
        openrouterApiKey: 'test-key',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('ChatSession and ChatMessage JSON serialization', () {
      final msg = ChatMessage(
        id: 'msg_1',
        role: MessageRole.user,
        text: 'Привет, напиши тест!',
        timestamp: DateTime.now(),
        attachments: [
          const ChatAttachment(
            name: 'main.dart',
            path: '/path/main.dart',
            mimeType: 'text/dart',
            isImage: false,
            sizeBytes: 120,
          ),
        ],
        actions: [
          AgentAction(
            type: 'write_file',
            path: 'lib/test.dart',
            content: 'void main() {}',
          ),
        ],
      );

      final session = ChatSession(
        id: 'session_123',
        title: 'Тестовый диалог',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        modelId: 'openrouter/free',
        messages: [msg],
      );

      final json = session.toJson();
      final restored = ChatSession.fromJson(json);

      expect(restored.id, equals('session_123'));
      expect(restored.title, equals('Тестовый диалог'));
      expect(restored.messages.length, equals(1));
      expect(restored.messages.first.text, equals('Привет, напиши тест!'));
      expect(restored.messages.first.attachments.length, equals(1));
      expect(restored.messages.first.actions.length, equals(1));
      expect(restored.messages.first.actions.first.type, equals('write_file'));
    });

    test('Agent creates, auto-saves, renames, and switches sessions', () async {
      final agent = QuantumAiAgentService(
        runtime,
        () => settings,
        () => tempDir.path,
      );

      await agent.loadSessions();
      expect(agent.currentSessionTitle, equals('Новый диалог'));

      // Simulate a user message
      agent.addMessageForTesting(
        ChatMessage(
          id: 'm1',
          role: MessageRole.user,
          text: 'Как создать Flutter кнопку?',
          timestamp: DateTime.now(),
        ),
      );
      agent.addMessageForTesting(
        ChatMessage(
          id: 'm2',
          role: MessageRole.assistant,
          text: 'Используйте ElevatedButton(...)',
          timestamp: DateTime.now(),
        ),
      );

      // Save session
      await agent.saveCurrentSession();
      expect(agent.sessions.length, equals(1));

      // Verify file exists on disk
      final sessionsDir = Directory('${tempDir.path}/.quantum/chat_sessions');
      expect(sessionsDir.existsSync(), isTrue);
      final files = sessionsDir.listSync();
      expect(files.length, equals(1));

      // Rename session
      await agent.renameSession(agent.currentSessionId, 'Flutter Кнопка');
      expect(agent.currentSessionTitle, equals('Flutter Кнопка'));
      expect(agent.sessions.first.title, equals('Flutter Кнопка'));

      // Start new chat
      await agent.startNewChat();
      expect(agent.currentSessionTitle, equals('Новый диалог'));
      expect(agent.messages.length, equals(1)); // Initial greeting
      expect(
        agent.sessions.length,
        equals(1),
      ); // Previous session preserved in history

      // Switch back to previous session
      final prevId = agent.sessions.first.id;
      await agent.switchSession(prevId);
      expect(agent.currentSessionTitle, equals('Flutter Кнопка'));
      expect(agent.messages.length, equals(3));
      expect(agent.messages[1].text, equals('Как создать Flutter кнопку?'));

      // Delete session
      await agent.deleteSession(prevId);
      expect(agent.sessions.isEmpty, isTrue);
    });
  });
}
