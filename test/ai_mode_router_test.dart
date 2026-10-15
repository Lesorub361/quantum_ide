import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/ai_mode_router.dart';
import 'package:quantum_ide/models/chat_message.dart';

void main() {
  group('AiModeRouter Tests', () {
    test('routes stack traces and errors to Debug mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'Exception: Null check operator used on a null value in user_profile.dart:42',
        currentMode: AiInteractionMode.chat,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.recommendedMode, equals(AiInteractionMode.debug));
    });

    test('routes RenderFlex overflow logs to Debug mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'A RenderFlex overflowed by 24 pixels on the right in bottom bar',
        currentMode: AiInteractionMode.chat,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.recommendedMode, equals(AiInteractionMode.debug));
    });

    test('routes architecture and planning queries to Plan mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'Спроектируй архитектуру модуля оффлайн-кэширования',
        currentMode: AiInteractionMode.chat,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.recommendedMode, equals(AiInteractionMode.plan));
    });

    test('routes active selection with explanation question to Ask mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'Что делает этот метод и как он работает?',
        currentMode: AiInteractionMode.chat,
        hasSelection: true,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.recommendedMode, equals(AiInteractionMode.ask));
    });

    test('routes refactoring requests to Refactor mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'Перепиши этот метод на async/await и выдели класс',
        currentMode: AiInteractionMode.chat,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.recommendedMode, equals(AiInteractionMode.refactor));
    });

    test('routes full project requests to Autopilot mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'Сделай приложение калькулятор с историей вычислений',
        currentMode: AiInteractionMode.chat,
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.recommendedMode, equals(AiInteractionMode.autopilot));
    });

    test('does not suggest switching if already in that mode', () {
      final suggestion = AiModeRouter.route(
        prompt: 'Exception: Crash in runLoop',
        currentMode: AiInteractionMode.debug,
      );
      expect(suggestion, isNull);
    });
  });
}
