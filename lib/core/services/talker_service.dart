import 'package:flutter/foundation.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Centralized logging and diagnostics service powered by Talker.
class TalkerService {
  static final Talker talker = TalkerFlutter.init(
    settings: TalkerSettings(
      maxHistoryItems: 200,
      useConsoleLogs: kDebugMode,
    ),
  );

  static void info(String message) {
    talker.info(message);
    LogService.recordFromTalker('INFO', message);
  }

  static void warning(String message) {
    talker.warning(message);
    LogService.recordFromTalker('WARN', message);
  }

  static void error(dynamic message, [dynamic exception, StackTrace? stackTrace]) {
    talker.error(message, exception, stackTrace);
    final details = exception != null ? '$message | $exception' : '$message';
    LogService.recordFromTalker('ERR', details);
  }

  static void handle(dynamic exception, [StackTrace? stackTrace, String? message]) {
    talker.handle(exception, stackTrace, message);
    final prefix = (message != null && message.isNotEmpty) ? '$message: ' : '';
    LogService.recordFromTalker('ERR', '$prefix$exception');
  }
}
