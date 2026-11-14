import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'core/providers/locale_provider.dart';
import 'core/services/settings_service.dart';

import 'core/services/ghost_qa_service.dart';
import 'core/theme/conduit_palette.dart';
import 'features/terminal/conduit/conduit_appearance_sheet.dart';

class QuantumApp extends ConsumerWidget {
  const QuantumApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(settingsProvider);

    final scheme = AppTheme.getScheme(settings.flexScheme);
    final customColor = settings.customPrimaryColor != null
        ? Color(settings.customPrimaryColor!)
        : null;
    final palette = resolveConduitPalette(settings.terminalTheme);
    final baseDark = AppTheme.dark(scheme, customColor: customColor);
    final baseLight = AppTheme.light(scheme, customColor: customColor);
    final effectiveDark = settings.syncAppWithTerminalPalette
        ? baseDark.copyWith(
            scaffoldBackgroundColor: palette.canvas,
            canvasColor: palette.canvas,
            cardColor: palette.panel,
            colorScheme: baseDark.colorScheme.copyWith(
              primary: palette.accent,
              secondary: palette.accent,
              surface: palette.panel,
            ),
          )
        : baseDark;
    final effectiveLight = settings.syncAppWithTerminalPalette
        ? baseLight.copyWith(
            colorScheme: baseLight.colorScheme.copyWith(
              primary: palette.accent,
              secondary: palette.accent,
            ),
          )
        : baseLight;

    return MaterialApp.router(
      title: 'QuantumIDE',
      debugShowCheckedModeBanner: false,
      theme: effectiveLight,
      darkTheme: effectiveDark,
      themeMode: settings.themeMode,
      routerConfig: appRouter,
      builder: (context, child) {
        return ValueListenableBuilder<Size?>(
          valueListenable: GhostQAService.instance.simulatedViewport,
          builder: (context, viewport, _) {
            Widget content = child ?? const SizedBox.shrink();
            if (viewport != null) {
              final mq = MediaQuery.of(context);
              content = Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: viewport.width,
                  height: viewport.height,
                  child: MediaQuery(
                    data: mq.copyWith(size: viewport),
                    child: content,
                  ),
                ),
              );
            }
            // Small screens (phones / small tablets): tighter widgets so more
            // content fits and controls don't swallow the whole screen.
            final width = viewport?.width ?? MediaQuery.sizeOf(context).width;
            if (width < 700) {
              final base = Theme.of(context);
              content = Theme(
                data: base.copyWith(
                  visualDensity: width < 420 ? VisualDensity.compact : const VisualDensity(horizontal: -2, vertical: -2),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  listTileTheme: base.listTileTheme.copyWith(dense: true, minVerticalPadding: 0),
                ),
                child: content,
              );
            }
            return RepaintBoundary(
              key: GhostQAService.repaintKey,
              child: content,
            );
          },
        );
      },
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
        Locale('zh'),
      ],
    );
  }
}
