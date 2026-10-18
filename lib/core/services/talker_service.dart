import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Centralized logging and diagnostics service powered by Talker.
class TalkerService {
  static final Talker talker = TalkerFlutter.init(
    settings: TalkerSettings(
      maxHistoryItems: 1000,
      useConsoleLogs: kDebugMode,
    ),
  );

  static void info(String message) {
    talker.info(message);
  }

  static void warning(String message) {
    talker.warning(message);
  }

  static void error(dynamic message, [dynamic exception, StackTrace? stackTrace]) {
    talker.error(message, exception, stackTrace);
  }

  static void handle(dynamic exception, [StackTrace? stackTrace, String? message]) {
    talker.handle(exception, stackTrace, message);
  }
}
