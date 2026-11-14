import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';

/// Shared theme tokens for all Git panels, modals, dialogs, and pages.
///
/// Mirrors the active [AppPalette] when `syncAppWithTerminalPalette` is enabled
/// and falls back cleanly to the app's Material [ColorScheme] otherwise.
class GitThemeColors {
  final Brightness brightness;
  final Color canvas;
  final Color panel;
  final Color card;
  final Color inputFill;
  final Color border;
  final Color hairline;
  final Color foreground;
  final Color mutedForeground;
  final Color subtleForeground;
  final Color accent;
  final Color accentSecondary;
  final Color accentForeground;
  final Color accentSecondaryForeground;
  final Color success;
  final Color warning;
  final Color danger;

  const GitThemeColors({
    required this.brightness,
    required this.canvas,
    required this.panel,
    required this.card,
    required this.inputFill,
    required this.border,
    required this.hairline,
    required this.foreground,
    required this.mutedForeground,
    required this.subtleForeground,
    required this.accent,
    required this.accentSecondary,
    required this.accentForeground,
    required this.accentSecondaryForeground,
    required this.success,
    required this.warning,
    required this.danger,
  });

  bool get isLight => brightness == Brightness.light;

  static Color contrastOn(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF0A0F14);
  }

  /// Resolves Git colors reactively via [ref.watch] or safely from context.
  static GitThemeColors resolve(BuildContext context, [WidgetRef? ref]) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;

    final AppSettings settings = ref != null
        ? ref.watch(settingsProvider)
        : ProviderScope.containerOf(context, listen: false)
            .read(settingsProvider);

    final AppPalette? palette = settings.syncAppWithTerminalPalette
        ? resolveConduitPalette(settings.terminalTheme)
        : null;

    if (palette != null) {
      final canvas = palette.canvasFor(brightness);
      final panel = palette.panelFor(brightness);
      final card = palette.panelElevatedFor(brightness);
      final inputFill = brightness == Brightness.light
          ? Colors.white
          : (Color.lerp(canvas, Colors.black, 0.18) ?? canvas);
      final accent = palette.accent;
      final accentSecondary = palette.accentSecondary;

      return GitThemeColors(
        brightness: brightness,
        canvas: canvas,
        panel: panel,
        card: card,
        inputFill: inputFill,
        border: palette.borderFor(brightness),
        hairline: palette.hairlineFor(brightness),
        foreground: palette.foregroundFor(brightness),
        mutedForeground: palette.mutedForegroundFor(brightness),
        subtleForeground: palette.subtleForegroundFor(brightness),
        accent: accent,
        accentSecondary: accentSecondary,
        accentForeground: contrastOn(accent),
        accentSecondaryForeground: contrastOn(accentSecondary),
        success: palette.success,
        warning: palette.warning,
        danger: palette.danger,
      );
    }

    final canvas = colorScheme.surface;
    final panel = colorScheme.surfaceContainerLow;
    final card = colorScheme.surfaceContainer;
    final inputFill = brightness == Brightness.light
        ? Colors.white
        : colorScheme.surfaceContainerLowest;
    final accent = colorScheme.primary;
    final accentSecondary = colorScheme.secondary;

    return GitThemeColors(
      brightness: brightness,
      canvas: canvas,
      panel: panel,
      card: card,
      inputFill: inputFill,
      border: colorScheme.outlineVariant,
      hairline: colorScheme.outlineVariant.withValues(alpha: 0.45),
      foreground: colorScheme.onSurface,
      mutedForeground: colorScheme.onSurfaceVariant,
      subtleForeground: colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
      accent: accent,
      accentSecondary: accentSecondary,
      accentForeground: colorScheme.onPrimary,
      accentSecondaryForeground: colorScheme.onSecondary,
      success: brightness == Brightness.light
          ? const Color(0xFF16A34A)
          : const Color(0xFF4ADE80),
      warning: brightness == Brightness.light
          ? const Color(0xFFD97706)
          : const Color(0xFFFBBF24),
      danger: colorScheme.error,
    );
  }
}
