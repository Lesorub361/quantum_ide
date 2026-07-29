import 'dart:async';
import 'dart:convert';
import 'package:riverpod/riverpod.dart';
import '../ai_service.dart';
import '../mcp_service.dart';
import 'agent_tool.dart';
import 'agent_tool_output_store.dart';
import 'agent_tool_registry.dart';
import 'agent_session_state.dart';
import 'agent_max_steps.dart';

class AgentRunFailure {
  final String message;
  AgentRunFailure(this.message);
}

class AgentContext {
  final List<Map<String, String>> history;
  final String? systemInstruction;
  final Map<String, dynamic>? toolMaterialization;
  final String sessionId;

  AgentContext({
    required this.history,
    this.systemInstruction,
    this.toolMaterialization,
    required this.sessionId,
  });
}

class AgentRunner {
  final Ref ref;
  final AIService aiService;
  final McpService mcpService;
  final AgentToolRegistry toolRegistry;
  final AgentToolOutputStore outputStore;

  AgentRunner(this.ref, this.aiService, this.mcpService, this.toolRegistry, this.outputStore);

  AgentSessionState? _currentSession;

  AgentSessionState? get currentSession => _currentSession;

  Stream<AgentRunEvent> runSession({
    required String sessionId,
    required String prompt,
    required String model,
    required String? systemInstruction,
    required int maxSteps,
  }) async* {
    var state = AgentSessionState(
      sessionId: sessionId,
      maxSteps: maxSteps,
      startedAt: DateTime.now(),
    );
    _currentSession = state;
    final history = <Map<String, String>>[];

    yield AgentRunEvent.statusChanged(state.copyWith(status: AgentSessionStatus.running));

    while (state.currentStep < maxSteps) {
      final ChatResponse response;
      try {
        response = await aiService.sendChatMessage(prompt, []);
      } catch (e) {
        yield AgentRunEvent.error(AgentRunFailure('Provider error: $e'));
        break;
      }

      if (response.text.isEmpty) {
        yield AgentRunEvent.error(AgentRunFailure('Empty provider response'));
        break;
      }

      yield AgentRunEvent.providerResponse(response.text, response.tokenUsage);

      final actions = _extractActions(response.text);
      if (actions.isEmpty) {
        yield AgentRunEvent.textDelta(response.text);
        yield AgentRunEvent.completed();
        break;
      }

      final settlements = <AgentToolSettlement>[];
      for (final action in actions) {
        if (state.currentStep >= maxSteps) break;
        state = state.copyWith(currentStep: state.currentStep + 1);
        yield AgentRunEvent.stepAdvanced(state.currentStep, maxSteps);

        final settlement = await _settleToolCall(action);
        settlements.add(settlement);
        yield AgentRunEvent.toolResult(action.type, settlement.result);
      }

      final turnResult = AgentTurnResult(
        assistantText: response.text,
        settlements: settlements,
      );

      history.add({'role': 'user', 'content': _buildToolResultContext(settlements)});

      if (!turnResult.needsContinuation) {
        yield AgentRunEvent.completed();
        break;
      }
    }

    if (state.currentStep >= maxSteps) {
      yield AgentRunEvent.maxStepsReached(maxStepsPrompt);
    }

    _currentSession = null;
  }

  Future<AgentToolSettlement> _settleToolCall(dynamic action) async {
    final name = action.type;
    final args = Map<String, dynamic>.from(action.arguments ?? {});

    if (!toolRegistry.contains(name)) {
      return AgentToolSettlement(result: 'Unknown tool: $name');
    }

    try {
      return await toolRegistry.settle(
        name: name,
        arguments: args,
        sessionId: _currentSession?.sessionId ?? 'unknown',
        outputStore: outputStore,
      );
    } catch (e) {
      return AgentToolSettlement(result: 'Error executing $name: $e');
    }
  }

  String _buildToolResultContext(List<AgentToolSettlement> settlements) {
    final buffer = StringBuffer();
    for (final s in settlements) {
      buffer.writeln('[Tool Result]\n${s.result}\n');
    }
    return buffer.toString().trim();
  }

  List<dynamic> _extractActions(String text) {
    final actions = <dynamic>[];
    final regExp = RegExp(r'<actions>([\s\S]*?)</actions>', caseSensitive: false);
    final match = regExp.firstMatch(text);
    if (match != null) {
      try {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is List) actions.addAll(decoded);
      } catch (_) {}
    }
    return actions;
  }
}

class AgentTurnResult {
  final String assistantText;
  final List<AgentToolSettlement> settlements;
  bool needsContinuation;

  AgentTurnResult({
    required this.assistantText,
    required this.settlements,
    this.needsContinuation = true,
  });
}

class AgentStepSettlement {
  final int step;
  final AgentStepFinish finish;
  final int tokens;
  final List<String> files;

  AgentStepSettlement({required this.step, required this.finish, required this.tokens, required this.files});
}

enum AgentStepFinish { text, tool, error }

sealed class AgentRunEvent {
  final AgentSessionState? state;
  AgentRunEvent(this.state);

  factory AgentRunEvent.statusChanged(AgentSessionState state) = AgentRunStatusChanged;
  factory AgentRunEvent.stepAdvanced(int step, int maxSteps) = AgentRunStepAdvanced;
  factory AgentRunEvent.providerResponse(String text, TokenUsage? usage) = AgentRunProviderResponse;
  factory AgentRunEvent.toolResult(String type, String result) = AgentRunToolResult;
  factory AgentRunEvent.textDelta(String delta) = AgentRunTextDelta;
  factory AgentRunEvent.maxStepsReached(String prompt) = AgentRunMaxStepsReached;
  factory AgentRunEvent.error(AgentRunFailure error) = AgentRunErrorEvent;
  factory AgentRunEvent.completed() = AgentRunCompleted;
}

class AgentRunStatusChanged extends AgentRunEvent {
  AgentRunStatusChanged(super.state);
}

class AgentRunStepAdvanced extends AgentRunEvent {
  final int step;
  final int maxSteps;
  AgentRunStepAdvanced(this.step, this.maxSteps) : super(null);
}

class AgentRunProviderResponse extends AgentRunEvent {
  final String text;
  final TokenUsage? usage;
  AgentRunProviderResponse(this.text, this.usage) : super(null);
}

class AgentRunToolResult extends AgentRunEvent {
  final String type;
  final String result;
  AgentRunToolResult(this.type, this.result) : super(null);
}

class AgentRunTextDelta extends AgentRunEvent {
  final String delta;
  AgentRunTextDelta(this.delta) : super(null);
}

class AgentRunMaxStepsReached extends AgentRunEvent {
  final String prompt;
  AgentRunMaxStepsReached(this.prompt) : super(null);
}

class AgentRunErrorEvent extends AgentRunEvent {
  final AgentRunFailure error;
  AgentRunErrorEvent(this.error) : super(null);
}

class AgentRunCompleted extends AgentRunEvent {
  AgentRunCompleted() : super(null);
}
