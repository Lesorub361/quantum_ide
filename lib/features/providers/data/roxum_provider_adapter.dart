import 'dart:convert';

import '../../../core/models/chat_models.dart';
import '../../ai_assistant/roxum/roxum_ai_client.dart';
import '../domain/ai_provider.dart';
import '../domain/provider_types.dart';

/// Thin [AIProvider] adapter so PocketStrike's AgentEngine can drive our
/// existing RoxumAiClient (OpenAI-compatible / Anthropic / Gemini / local).
class RoxumProviderAdapter implements AIProvider {
  RoxumProviderAdapter({
    required this.client,
    required this.model,
    this.type = ProviderType.custom,
  });

  final RoxumAiClient client;
  final RoxumModelOption model;
  final ProviderType type;

  @override
  String get configId => type.id;

  @override
  String get displayName => model.name.isNotEmpty ? model.name : model.model;

  @override
  bool get supportsTools => true;

  @override
  bool get supportsVision => false;

  @override
  Future<List<String>> listModels() async => [model.model];

  @override
  Stream<ChatStreamEvent> streamMessage(ChatRequest request) async* {
    final messages = request.messages.map((m) {
      final Map<String, dynamic> map = {
        'role': switch (m.role) {
          MessageRole.system => 'system',
          MessageRole.user => 'user',
          MessageRole.assistant => 'assistant',
          MessageRole.tool => 'tool',
        },
        'content': m.content,
      };
      if (m.toolCallId != null) map['tool_call_id'] = m.toolCallId;
      if (m.toolName != null) map['name'] = m.toolName;
      if (m.toolCalls.isNotEmpty) {
        map['tool_calls'] = m.toolCalls
            .map(
              (c) => {
                'id': c.id,
                'type': 'function',
                'function': {
                  'name': c.name,
                  'arguments': c.argumentsJson,
                },
              },
            )
            .toList();
      }
      return map;
    }).toList();

    final specs = request.tools
        .map(
          (t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          },
        )
        .toList();

    final buffer = StringBuffer();
    try {
      final turn = await client.streamTurnForAgent(
        model: model,
        messages: messages,
        toolSpecs: specs,
        onText: buffer.write,
        onReasoning: (_) {},
        isCancelled: () => request.cancelToken?.isCancelled ?? false,
      );

      if (buffer.isNotEmpty) yield TextDeltaEvent(buffer.toString());
      if (turn.toolCalls.isNotEmpty) {
        yield ToolCallsEvent(
          turn.toolCalls
              .map(
                (c) => ToolCallInfo(
                  id: c.id,
                  name: c.name,
                  argumentsJson: jsonEncode(c.args),
                ),
              )
              .toList(),
        );
      }
      yield const StreamDoneEvent();
    } catch (e) {
      yield StreamErrorEvent(e.toString());
    }
  }
}
