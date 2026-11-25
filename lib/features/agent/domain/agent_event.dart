/// UI-agnostic events emitted by [AgentEngine].
/// The chat layer renders a timeline from these; the engine never touches widgets.
sealed class AgentEvent {
  const AgentEvent();
}

class AgentStatusEvent extends AgentEvent {
  const AgentStatusEvent(this.message);
  final String message;
}

class AgentTextDeltaEvent extends AgentEvent {
  const AgentTextDeltaEvent(this.text);
  final String text;
}

class AgentReasoningEvent extends AgentEvent {
  const AgentReasoningEvent(this.text);
  final String text;
}

class AgentStepEvent extends AgentEvent {
  const AgentStepEvent(this.step);
  final int step;
}

class AgentToolCallStartedEvent extends AgentEvent {
  const AgentToolCallStartedEvent(this.callId, this.name, this.args);
  final String callId;
  final String name;
  final Map<String, dynamic> args;
}

class AgentToolCallCompletedEvent extends AgentEvent {
  const AgentToolCallCompletedEvent(
    this.callId,
    this.name,
    this.output,
    this.isError,
  );
  final String callId;
  final String name;
  final String output;
  final bool isError;
}

class AgentToolCallDeniedEvent extends AgentEvent {
  const AgentToolCallDeniedEvent(this.callId, this.name);
  final String callId;
  final String name;
}

class AgentRunErrorEvent extends AgentEvent {
  const AgentRunErrorEvent(this.message);
  final String message;
}

class AgentRunFinishedEvent extends AgentEvent {
  const AgentRunFinishedEvent(this.cancelled);
  final bool cancelled;
}
