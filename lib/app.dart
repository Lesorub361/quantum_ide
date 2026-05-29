import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/services/settings_service.dart';

class QuantumApp extends ConsumerWidget {
  const QuantumApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(settingsProvider);

    final scheme = AppTheme.getScheme(settings.flexScheme);
    final customColor = settings.customPrimaryColor != null ? Color(settings.customPrimaryColor!) : null;

    return MaterialApp.router(
      title: 'QuantumIDE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(scheme, customColor: customColor),
      darkTheme: AppTheme.dark(scheme, customColor: customColor),
      themeMode: settings.themeMode,
      routerConfig: appRouter,
      locale: locale,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('ru'),
        Locale('es'),
        Locale('fr'),
      ],
    );
  }
}
