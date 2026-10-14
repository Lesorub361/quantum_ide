/// Shared models for Debug Adapter Protocol (DAP) implementations.
library;

enum StepType { over, into, out, continue_ }

class DapBreakpoint {
  final String filePath;
  final int line;
  final int? column;
  final bool verified;
  final int? id;

  const DapBreakpoint({
    String? filePath,
    String? fileUri,
    required this.line,
    this.column,
    this.verified = false,
    this.id,
  }) : filePath = filePath ?? fileUri ?? '';

  String get fileUri => filePath;

  DapBreakpoint copyWith({bool? verified, int? id}) {
    return DapBreakpoint(
      filePath: filePath,
      line: line,
      column: column,
      verified: verified ?? this.verified,
      id: id ?? this.id,
    );
  }
}

class DapStackFrame {
  final int id;
  final String name;
  final String source;
  final int line;
  final int column;
  final String? moduleId;

  const DapStackFrame({
    required this.id,
    required this.name,
    required this.source,
    required this.line,
    required this.column,
    this.moduleId,
  });
}

class DapVariable {
  final int? variablesReference;
  final String name;
  final String value;
  final String type;
  final List<DapVariable>? children;

  const DapVariable({
    this.variablesReference,
    required this.name,
    required this.value,
    required this.type,
    this.children,
  });
}

class DapException {
  final String description;
  final int? code;
  final String? details;

  const DapException({
    required this.description,
    this.code,
    this.details,
  });
}

class DapEvent {
  final String type;
  final dynamic body;

  const DapEvent({required this.type, required this.body});
}

// Backwards compatibility aliases
typedef DapDebuggerBreakpoint = DapBreakpoint;
typedef DapDebuggerStackFrame = DapStackFrame;
typedef DapDebuggerVariable = DapVariable;
typedef DapDebuggerException = DapException;
typedef DapDebuggerEvent = DapEvent;
