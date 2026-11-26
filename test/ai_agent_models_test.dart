import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/models/ai_agent_models.dart';

void main() {
  group('ai_agent_models', () {
    test('ChatSession JSON round-trip preserves messages and actions', () {
      final now = DateTime.utc(2026, 11, 26, 19, 0, 0);
      final session = ChatSession(
        id: 's1',
        title: 'Refactor',
        createdAt: now,
        updatedAt: now,
        modelId: 'openrouter/free',
        messages: [
          ChatMessage(
            id: 'm1',
            role: MessageRole.user,
            text: 'Check lsp framing',
            timestamp: now,
          ),
          ChatMessage(
            id: 'm2',
            role: MessageRole.assistant,
            text: 'Done',
            timestamp: now,
            actions: [
              AgentAction(
                type: 'write_file',
                path: 'lib/foo.dart',
                content: 'void main() {}',
                isExecuted: true,
              ),
            ],
          ),
        ],
      );

      final restored = ChatSession.fromJson(session.toJson());
      expect(restored.id, 's1');
      expect(restored.userMessageCount, 1);
      expect(restored.preview, 'Check lsp framing');
      expect(restored.messages.length, 2);
      expect(restored.messages[1].actions.single.isExecuted, isTrue);
    });
  });
}
