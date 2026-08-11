import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData light(FlexScheme scheme, {Color? customColor}) => FlexThemeData.light(
        scheme: customColor == null ? scheme : null,
        colorScheme: customColor != null ? ColorScheme.fromSeed(seedColor: customColor, brightness: Brightness.light) : null,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          blendOnColors: false,
          useMaterial3Typography: true,
          useM2StyleDividerInM3: true,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        swapLegacyOnMaterial3: true,
        fontFamily: GoogleFonts.outfit().fontFamily,
      ).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          interactive: true,
          thickness: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
              return 10.0;
            }
            return 6.0;
          }),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            final baseColor = customColor ?? const Color(0xFF6C63FF);
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
              return baseColor.withValues(alpha: 0.85);
            }
            return baseColor.withValues(alpha: 0.45);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.black.withValues(alpha: 0.05);
            }
            return Colors.transparent;
          }),
          radius: const Radius.circular(8.0),
          thumbVisibility: WidgetStateProperty.all(true),
          trackVisibility: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return true;
            }
            return false;
          }),
        ),
      );

  static ThemeData dark(FlexScheme scheme, {Color? customColor}) => FlexThemeData.dark(
        scheme: customColor == null ? scheme : null,
        colorScheme: customColor != null ? ColorScheme.fromSeed(seedColor: customColor, brightness: Brightness.dark) : null,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 13,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useMaterial3Typography: true,
          useM2StyleDividerInM3: true,
          alignedDropdown: true,
          useInputDecoratorThemeInDialogs: true,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        swapLegacyOnMaterial3: true,
        fontFamily: GoogleFonts.outfit().fontFamily,
      ).copyWith(
        scrollbarTheme: ScrollbarThemeData(
          interactive: true,
          thickness: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
              return 10.0;
            }
            return 6.0;
          }),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            final baseColor = customColor ?? const Color(0xFF6C63FF);
            if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
              return baseColor.withValues(alpha: 0.85);
            }
            return baseColor.withValues(alpha: 0.45);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
          radius: const Radius.circular(8.0),
          thumbVisibility: WidgetStateProperty.all(true),
          trackVisibility: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return true;
            }
            return false;
          }),
        ),
      );
  static FlexScheme getScheme(String name) {
    return FlexScheme.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FlexScheme.mandyRed,
    );
  }
}
