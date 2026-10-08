import 'dart:async';

enum BuildErrorSeverity { error, warning, info }

class BuildDiagnostic {
  final String file;
  final int? line;
  final int? column;
  final String message;
  final BuildErrorSeverity severity;
  final String? suggestion;
  final String? code;

  BuildDiagnostic({
    required this.file,
    required this.line,
    required this.column,
    required this.message,
    required this.severity,
    this.suggestion,
    this.code,
  });
}

class BuildDiagnosticsService {
  final StreamController<BuildDiagnostic> _diagnosticsController = StreamController.broadcast();
  final List<BuildDiagnostic> _diagnostics = [];

  Stream<BuildDiagnostic> get diagnosticsStream => _diagnosticsController.stream;
  List<BuildDiagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Parse gradle/flutter build output and extract diagnostics
  void parseGradleOutput(String output) {
    final lines = output.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // Parse gradle error format
      if (line.contains('error:')) {
        final parts = _parseGradleError(line);
        if (parts != null) {
          final diagnostic = BuildDiagnostic(
            file: parts['file'] as String,
            line: parts['line'] as int?,
            column: parts['column'] as int?,
            message: parts['message'] as String,
            severity: BuildErrorSeverity.error,
            code: 'GRADLE_ERROR',
          );
          _addDiagnostic(diagnostic);
        }
      }
      
      // Parse gradle warning format
      if (line.contains('warning:')) {
        final parts = _parseGradleWarning(line);
        if (parts != null) {
          final diagnostic = BuildDiagnostic(
            file: parts['file'] as String,
            line: parts['line'] as int?,
            column: parts['column'] as int?,
            message: parts['message'] as String,
            severity: BuildErrorSeverity.warning,
            code: 'GRADLE_WARNING',
          );
          _addDiagnostic(diagnostic);
        }
      }

      // Parse Flutter specific errors
      if (line.contains('FAILURE')) {
        final suggestion = _suggestFixForError(line, i, lines);
        final diagnostic = BuildDiagnostic(
          file: 'BUILD',
          line: null,
          column: null,
          message: line,
          severity: BuildErrorSeverity.error,
          suggestion: suggestion,
          code: 'FLUTTER_BUILD_FAILURE',
        );
        _addDiagnostic(diagnostic);
      }
    }
  }

  Map<String, dynamic>? _parseGradleError(String line) {
    // Example: "/path/to/file.java:10:5: error: cannot find symbol"
    final regex = RegExp(r'(\S+):(\d+):(\d+):\s*error:\s*(.+)');
    final match = regex.firstMatch(line);
    
    if (match != null) {
      return {
        'file': match.group(1),
        'line': int.tryParse(match.group(2) ?? '0'),
        'column': int.tryParse(match.group(3) ?? '0'),
        'message': match.group(4),
      };
    }
    return null;
  }

  Map<String, dynamic>? _parseGradleWarning(String line) {
    final regex = RegExp(r'(\S+):(\d+):(\d+):\s*warning:\s*(.+)');
    final match = regex.firstMatch(line);
    
    if (match != null) {
      return {
        'file': match.group(1),
        'line': int.tryParse(match.group(2) ?? '0'),
        'column': int.tryParse(match.group(3) ?? '0'),
        'message': match.group(4),
      };
    }
    return null;
  }

  String? _suggestFixForError(String line, int lineIndex, List<String> allLines) {
    if (line.contains('AAPT2')) {
      return 'Try running: flutter clean && flutter pub get && flutter build apk';
    }
    if (line.contains('gradle')) {
      return 'Check gradle.properties and build.gradle files. Ensure AGP is compatible.';
    }
    if (line.contains('Java')) {
      return 'Ensure JDK 11+ is installed. Set JAVA_HOME correctly.';
    }
    if (line.contains('SDK')) {
      return 'Verify Android SDK is properly installed and ANDROID_SDK_ROOT is set.';
    }
    if (line.contains('NDK')) {
      return 'Verify Android NDK is installed or use --no-c-option in build command.';
    }
    return null;
  }

  void _addDiagnostic(BuildDiagnostic diagnostic) {
    // Avoid duplicates
    if (!_diagnostics.any((d) => 
        d.file == diagnostic.file && 
        d.line == diagnostic.line && 
        d.message == diagnostic.message)) {
      _diagnostics.add(diagnostic);
      _diagnosticsController.add(diagnostic);
    }
  }

  void clearDiagnostics() {
    _diagnostics.clear();
  }

  void dispose() {
    _diagnosticsController.close();
  }
}
