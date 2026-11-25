import 'dart:convert';

import '../domain/agent_event.dart';
import '../domain/agent_tool.dart';

/// One tool call requested by the model in a single turn.
typedef AgentToolCall = ({String id, String name, Map<String, dynamic> args});

/// Result of one provider turn (text + tool calls).
class AgentTurnResult {
  const AgentTurnResult({
    required this.text,
    this.reasoning = '',
    this.toolCalls = const [],
  });

  final String text;
  final String reasoning;
  final List<AgentToolCall> toolCalls;
}

/// Provider adapter. Our existing RoxumAiClient supplies this closure.
typedef AgentTurnRunner = Future<AgentTurnResult> Function({
  required List<Map<String, dynamic>> messages,
  required List<Map<String, dynamic>> toolSpecs,
  required void Function(String text) onText,
  required void Function(String reasoning) onReasoning,
  required bool Function() isCancelled,
});

/// PocketStrike-style ReAct loop: think → act → observe → repeat.
///
/// UI-agnostic: confirmations are requested through [requestConfirmation]
/// and progress is streamed as [AgentEvent]s. No widget, no provider, no IDE
/// specific heuristics live here — that is what makes it testable.
class AgentEngine {
  AgentEngine({this.maxSteps = 50});

  final int maxSteps;

  Stream<AgentEvent> run({
    required AgentTurnRunner runTurn,
    required List<Map<String, dynamic>> history,
    required List<AgentTool> tools,
    required ConfirmationPolicy policy,
    required Future<ConfirmResult> Function(AgentTool tool, AgentToolCall call)
        requestConfirmation,
    Set<String> sessionApproved = const {},
    Set<String> forceConfirm = const {},
    required bool Function() isCancelled,
  }) async* {
    final messages = List<Map<String, dynamic>>.from(history);
    final approved = <String>{...sessionApproved};
    final toolSpecs = tools.map((t) => t.toSpec()).toList();
    var cancelled = false;

    for (var step = 0; step < maxSteps; step++) {
      if (isCancelled()) {
        cancelled = true;
        break;
      }
      yield AgentStepEvent(step);
      yield const AgentStatusEvent('Thinking…');

      final textBuffer = StringBuffer();
      AgentTurnResult turn;

      try {
        turn = await runTurn(
          messages: messages,
          toolSpecs: toolSpecs,
          onText: (chunk) {
            textBuffer.write(chunk);
          },
          onReasoning: (chunk) {},
          isCancelled: isCancelled,
        );
      } catch (e) {
        yield AgentRunErrorEvent(e.toString());
        break;
      }

      if (isCancelled()) {
        cancelled = true;
        break;
      }

      if (turn.reasoning.isNotEmpty) {
        yield AgentReasoningEvent(turn.reasoning);
      }
      if (textBuffer.isNotEmpty) {
        yield AgentTextDeltaEvent(textBuffer.toString());
      }

      final assistantMessage = <String, dynamic>{
        'role': 'assistant',
        'content': turn.text,
        if (turn.toolCalls.isNotEmpty)
          'tool_calls': turn.toolCalls
              .map(
                (c) => {
                  'id': c.id,
                  'type': 'function',
                  'function': {
                    'name': c.name,
                    'arguments': jsonEncode(c.args),
                  },
                },
              )
              .toList(),
      };
      messages.add(assistantMessage);

      if (turn.toolCalls.isEmpty) {
        break; // Final answer.
      }

      yield AgentStatusEvent(
        'Executing ${turn.toolCalls.length} tool call(s)…',
      );

      for (final call in turn.toolCalls) {
        if (isCancelled()) {
          cancelled = true;
          break;
        }

        // MCP names are namespaced: mcp__<server>__<tool>.
        final tool = tools.where((t) {
          return t.name == call.name ||
              t.name.endsWith('__${call.name}') ||
              call.name.endsWith('__${t.name}');
        }).firstOrNull;

        yield AgentToolCallStartedEvent(call.name, call.args);

        String observation;
        var isError = false;

        if (tool == null) {
          observation = 'Error: unknown tool "${call.name}".';
          isError = true;
        } else {
          final needsConfirm = !approved.contains(tool.name) &&
              (forceConfirm.contains(tool.name) ||
                  switch (policy) {
                    ConfirmationPolicy.alwaysAsk => true,
                    ConfirmationPolicy.destructiveOnly =>
                      tool.risk != ToolRisk.safe,
                    ConfirmationPolicy.autonomous => false,
                  });

          if (needsConfirm) {
            final decision = await requestConfirmation(tool, call);
            switch (decision) {
              case ConfirmResult.allowAlways:
                approved.add(tool.name);
              case ConfirmResult.allow:
                break;
              case ConfirmResult.deny:
                observation =
                    'The user denied permission to run "${tool.name}". '
                    'Do not retry; explain the limitation instead.';
                isError = true;
                messages.add({
                  'role': 'tool',
                  'tool_call_id': call.id,
                  'name': call.name,
                  'content': observation,
                });
                yield AgentToolCallDeniedEvent(call.name);
                yield AgentToolCallCompletedEvent(call.name, observation, true);
                continue;
            }
          }

          try {
            observation = await tool.run(call.args);
          } catch (e) {
            observation = 'Error running ${tool.name}: $e';
            isError = true;
          }
        }

        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'name': call.name,
          'content': observation,
        });
        yield AgentToolCallCompletedEvent(call.name, observation, isError);
      }

      if (cancelled) break;
    }

    // Never finish silently on a bare tool result: ask the model for a summary
    // with tools disabled (PocketStrike's final synthesis step).
    if (!cancelled &&
        messages.isNotEmpty &&
        messages.last['role'] == 'tool') {
      yield const AgentStatusEvent('Summarizing actions…');
      final summary = StringBuffer();
      try {
        final result = await runTurn(
          messages: messages,
          toolSpecs: const [],
          onText: summary.write,
          onReasoning: (_) {},
          isCancelled: isCancelled,
        );
        if (summary.isNotEmpty || result.text.isNotEmpty) {
          yield AgentTextDeltaEvent(
            summary.isNotEmpty ? summary.toString() : result.text,
          );
        }
      } catch (_) {}
    }

    yield AgentRunFinishedEvent(cancelled);
  }
}
