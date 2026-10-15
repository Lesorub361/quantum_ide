import 'package:quantum_ide/models/chat_message.dart';

/// Suggestion produced by [AiModeRouter] based on heuristics and context.
class AiModeSuggestion {
  final AiInteractionMode recommendedMode;
  final String reason;
  final String label;

  const AiModeSuggestion({
    required this.recommendedMode,
    required this.reason,
    required this.label,
  });
}

/// Heuristic router that detects optimal [AiInteractionMode] based on user input and workspace context.
class AiModeRouter {
  static final RegExp _crashRegex = RegExp(
    r'(exception:|renderflex\s+overflowed|stack\s*trace|assertion\s+failed|исправь\s+баг|почему\s+(падает|ошибка)|crash|failed\s+with\s+exit\s+code)',
    caseSensitive: false,
  );

  static final RegExp _planRegex = RegExp(
    r'(спроектируй|спланируй|архитектур|дизайн\s+систем|составь\s+план|plan\s+mode|decompose|design\s+system)',
    caseSensitive: false,
  );

  static final RegExp _refactorRegex = RegExp(
    r'(перепиши|отрефактори|refactor|оптимизируй|выдели\s+метод|extract\s+method|cleanup)',
    caseSensitive: false,
  );

  static final RegExp _askRegex = RegExp(
    r'(что\s+(это|делает|значит|происходит)|как\s+(это\s+|он\s+|она\s+)?(работает|устроен)|объясни|explain|поясни|расскажи|what\s+does|how\s+does)',
    caseSensitive: false,
  );

  static final RegExp _autopilotRegex = RegExp(
    r'(сделай\s+приложение|напиши\s+проект|создай\s+проект|автопилот|autopilot)',
    caseSensitive: false,
  );

  /// Analyzes the [prompt] and context, returning a suggestion if another mode is better suited.
  static AiModeSuggestion? route({
    required String prompt,
    required AiInteractionMode currentMode,
    bool hasSelection = false,
  }) {
    final text = prompt.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // 1. Diagnostics / crash / stack trace -> Debug mode
    if (_crashRegex.hasMatch(lower) || lower.contains('отлад') || lower.contains('debug')) {
      if (currentMode != AiInteractionMode.debug) {
        return const AiModeSuggestion(
          recommendedMode: AiInteractionMode.debug,
          reason: 'Обнаружен лог ошибки или запрос на диагностику',
          label: 'Debug',
        );
      }
      return null;
    }

    // 2. High-level architecture / multi-step planning -> Plan mode
    if (_planRegex.hasMatch(lower) || (lower.contains('plan') && !lower.contains('explain'))) {
      if (currentMode != AiInteractionMode.plan) {
        return const AiModeSuggestion(
          recommendedMode: AiInteractionMode.plan,
          reason: 'Запрос на проектирование или архитектурное планирование',
          label: 'Plan',
        );
      }
      return null;
    }

    // 3. Code inspection with active selection -> Ask mode
    if (hasSelection && _askRegex.hasMatch(lower)) {
      if (currentMode != AiInteractionMode.ask) {
        return const AiModeSuggestion(
          recommendedMode: AiInteractionMode.ask,
          reason: 'Выделен фрагмент кода с вопросом о его назначении',
          label: 'Ask',
        );
      }
      return null;
    }

    // 4. Code refactoring / targeted changes -> Refactor mode
    if (hasSelection || _refactorRegex.hasMatch(lower) || lower.contains('исправь') || lower.contains('fix')) {
      if (currentMode != AiInteractionMode.refactor) {
        return AiModeSuggestion(
          recommendedMode: AiInteractionMode.refactor,
          reason: hasSelection ? 'Выделен код в редакторе' : 'Запрос на изменение кода',
          label: 'Refactor',
        );
      }
      return null;
    }

    // 5. Full project building -> Autopilot mode
    if (_autopilotRegex.hasMatch(lower) || (lower.contains('build') && !lower.contains('buildrunner'))) {
      if (currentMode != AiInteractionMode.autopilot) {
        return const AiModeSuggestion(
          recommendedMode: AiInteractionMode.autopilot,
          reason: 'Запрос на сквозное создание приложения',
          label: 'Autopilot',
        );
      }
      return null;
    }

    return null;
  }
}
