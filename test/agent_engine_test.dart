import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/models/chat_models.dart';
import 'package:quantum_ide/features/agent/data/agent_engine.dart';
import 'package:quantum_ide/features/agent/domain/agent_event.dart';
import 'package:quantum_ide/features/agent/domain/agent_tool.dart';
import 'package:quantum_ide/features/providers/data/openai_compatible_provider.dart';
import 'package:quantum_ide/features/providers/domain/ai_provider.dart';
import 'package:quantum_ide/features/providers/domain/provider_types.dart';
import 'package:quantum_ide/shared/widgets/confirm_action_sheet.dart';

class _FakeProvider implements AIProvider {
  _FakeProvider(this.onRequest);

  final List<ChatStreamEvent> Function(int callIndex, ChatRequest req) onRequest;
  int _callCount = 0;
  final List<ChatRequest> capturedRequests = [];

  @override
  String get configId => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  bool get supportsTools => true;

  @override
  bool get supportsVision => false;

  @override
  Future<List<String>> listModels() async => const ['fake-model'];

  @override
  Stream<ChatStreamEvent> streamMessage(ChatRequest request) async* {
    capturedRequests.add(request);
    final events = onRequest(_callCount++, request);
    for (final e in events) {
      yield e;
    }
  }
}

void main() {
  test('AgentEngine executes tool calls and compacts long observations', () async {
    final longOutput = 'X' * 5000;
    final provider = _FakeProvider((idx, req) {
      if (idx == 0) {
        return const [
          ToolCallsEvent([
            ToolCallInfo(id: 'c1', name: 'readFile', argumentsJson: '{"filePath":"a.dart"}'),
          ]),
          StreamDoneEvent(),
        ];
      }
      if (idx < 7) {
        return [
          ToolCallsEvent([
            ToolCallInfo(
              id: 'c_${idx + 1}',
              name: 'readFile',
              argumentsJson: '{"filePath":"file_$idx.dart"}',
            ),
          ]),
          const StreamDoneEvent(),
        ];
      }
      return const [
        TextDeltaEvent('All '),
        TextDeltaEvent('done!'),
        UsageEvent(UsageInfo(promptTokens: 100, completionTokens: 20)),
        StreamDoneEvent(),
      ];
    });

    final tool = AgentTool(
      name: 'readFile',
      description: 'Read a file',
      inputSchema: const {'type': 'object', 'properties': {}},
      risk: ToolRisk.safe,
      run: (args) async => longOutput,
    );

    final events = await AgentEngine(maxSteps: 12)
        .run(
          provider: provider,
          history: [
            ChatMessage(
              id: 'u1',
              role: MessageRole.user,
              content: 'Inspect files',
            ),
          ],
          model: 'fake-model',
          params: const GenerationParams(),
          tools: [tool],
          policy: ConfirmationPolicy.autonomous,
          requestConfirmation: (_, __) async => ConfirmResult.allow,
        )
        .toList();

    final finalMsg = events.whereType<AgentAssistantMessageEvent>().single;
    expect(finalMsg.message.content, 'All done!');

    // By the last request, earlier tool outputs (>1200 chars) must be compacted.
    final lastReqMessages = provider.capturedRequests.last.messages;
    final compactedTools = lastReqMessages
        .where((m) =>
            m.role == MessageRole.tool &&
            m.content.contains('compacted') &&
            m.content.length < 1200)
        .toList();
    expect(compactedTools, isNotEmpty);

    // OpenAI wire conversion preserves valid tool_call_id fields.
    final wire = OpenAiCompatibleProvider.convertMessages(lastReqMessages);
    expect(wire.any((m) => m['role'] == 'tool' && m['tool_call_id'] != null), isTrue);
  });
}
