class AgentSessionState {
  final String sessionId;
  AgentSessionStatus status;
  final int currentStep;
  final int maxSteps;
  final String? currentError;
  final DateTime startedAt;
  DateTime? finishedAt;

  AgentSessionState({
    required this.sessionId,
    this.status = AgentSessionStatus.idle,
    this.currentStep = 0,
    this.maxSteps = 50,
    this.currentError,
    required this.startedAt,
    this.finishedAt,
  });

  AgentSessionState copyWith({
    String? sessionId,
    AgentSessionStatus? status,
    int? currentStep,
    int? maxSteps,
    String? currentError,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    return AgentSessionState(
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      maxSteps: maxSteps ?? this.maxSteps,
      currentError: currentError ?? this.currentError,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

enum AgentSessionStatus { idle, running, waiting, completed, failed, interrupted }
