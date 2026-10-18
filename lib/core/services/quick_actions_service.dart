import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:quantum_ide/core/router/app_router.dart';

/// Service managing home screen quick actions (App Shortcuts) for mobile platforms.
class QuickActionsService {
  static final QuickActionsService instance = QuickActionsService._();
  QuickActionsService._();

  final QuickActions _quickActions = const QuickActions();
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    _initialized = true;

    try {
      _quickActions.initialize((shortcutType) {
        debugPrint('Quick action selected: $shortcutType');
        switch (shortcutType) {
          case 'action_terminal':
            appRouter.go('/terminal');
            break;
          case 'action_editor':
            appRouter.go('/editor');
            break;
          case 'action_settings':
            appRouter.go('/settings');
            break;
        }
      });

      _quickActions.setShortcutItems(const <ShortcutItem>[
        ShortcutItem(
          type: 'action_terminal',
          localizedTitle: 'Терминал',
          icon: 'ic_launcher',
        ),
        ShortcutItem(
          type: 'action_editor',
          localizedTitle: 'Редактор кода',
          icon: 'ic_launcher',
        ),
        ShortcutItem(
          type: 'action_settings',
          localizedTitle: 'Настройки',
          icon: 'ic_launcher',
        ),
      ]);
    } catch (e) {
      debugPrint('QuickActions init failed: $e');
    }
  }
}
