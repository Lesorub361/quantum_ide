import 'package:test/test.dart';
import 'package:quantum_ide/features/agent/data/agent_engine.dart';
import 'package:quantum_ide/features/agent/domain/agent_event.dart';
import 'package:quantum_ide/features/agent/domain/agent_tool.dart';

void main() {
  AgentTool tool(String name, ToolRisk risk, List<String> log) => AgentTool(
        name: name,
        description: 'test tool',
        inputSchema: const {'type': 'object', 'properties': {}},
        risk: risk,
        run: (args) async {
          log.add(name);
          return 'ok:$name';
        },
      );

  test('final answer without tool calls', () async {
    var turns = 0;
    final engine = AgentEngine();
    final events = engine.run(
      runTurn: ({required messages, required toolSpecs, required onText,
          required onReasoning, required isCancelled}) async {
        turns++;
        onText('hello');
        return const AgentTurnResult(text: 'hello');
      },
      history: const [
        {'role': 'user', 'content': 'hi'}
      ],
      tools: const [],
      policy: ConfirmationPolicy.autonomous,
      requestConfirmation: (_, __) async => ConfirmResult.allow,
      isCancelled: () => false,
    );

    final seen = <String>[];
    await for (final e in events) {
      if (e is AgentTextDeltaEvent) seen.add(e.text);
    }
    expect(turns, 1);
    expect(seen, ['hello']);
  });

  test('tool call is executed and summarized', () async {
    final log = <String>[];
    var turn = 0;
    final engine = AgentEngine();
    final events = engine.run(
      runTurn: ({required messages, required toolSpecs, required onText,
          required onReasoning, required isCancelled}) async {
        turn++;
        if (turn == 1) {
          return AgentTurnResult(
            text: '',
            toolCalls: [
              (id: 'c1', name: 'readFile', args: const {'path': 'a.dart'})
            ],
          );
        }
        onText('done');
        return const AgentTurnResult(text: 'done');
      },
      history: const [
        {'role': 'user', 'content': 'read a.dart'}
      ],
      tools: [tool('readFile', ToolRisk.safe, log)],
      policy: ConfirmationPolicy.autonomous,
      requestConfirmation: (_, __) async => ConfirmResult.allow,
      isCancelled: () => false,
    );

    final completed = <String>[];
    await for (final e in events) {
      if (e is AgentToolCallCompletedEvent) completed.add(e.name);
    }
    expect(log, ['readFile']);
    expect(completed, ['readFile']);
    expect(turn, 2);
  });

  test('denied tool is not executed', () async {
    final log = <String>[];
    var turn = 0;
    final events = AgentEngine().run(
      runTurn: ({required messages, required toolSpecs, required onText,
          required onReasoning, required isCancelled}) async {
        turn++;
        if (turn == 1) {
          return AgentTurnResult(
            text: '',
            toolCalls: [
              (id: 'c2', name: 'deleteFile', args: const {'path': 'a.dart'})
            ],
          );
        }
        return const AgentTurnResult(text: 'cannot do that');
      },
      history: const [
        {'role': 'user', 'content': 'delete a.dart'}
      ],
      tools: [tool('deleteFile', ToolRisk.destructive, log)],
      policy: ConfirmationPolicy.destructiveOnly,
      requestConfirmation: (_, __) async => ConfirmResult.deny,
      isCancelled: () => false,
    );

    await events.drain();
    expect(log, isEmpty);
  });
}
