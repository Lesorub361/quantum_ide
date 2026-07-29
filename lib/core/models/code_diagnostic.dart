import 'package:re_editor/re_editor.dart';

enum CodeDiagnosticSeverity {
  error,
  warning,
  hint,
}

class CodeDiagnostic {
  final CodeLineRange range;
  final String message;
  final CodeDiagnosticSeverity severity;

  CodeDiagnostic({
    required this.range,
    required this.message,
    required this.severity,
  });
}
