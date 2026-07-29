import 'package:flutter/material.dart';

/// Shared color constants for the QuantumIDE theme
/// Eliminates hardcoded hex colors across 20+ files
class AppColors {
  AppColors._();

  // ─── Background Colors ──────────────────────────────────────
  static const panelBackground = Color(0xFF1E2230);
  static const darkBackground = Color(0xFF0D0F14);
  static const deepDarkBackground = Color(0xFF090B0F);
  static const tabBarBackground = Color(0xFF13151D);
  static const editorBackground = Color(0xFF0F111A);
  
  // ─── Accent Colors ──────────────────────────────────────────
  static const accentRed = Color(0xFFFF3C3C);
  static const accentCyan = Colors.cyanAccent;
  static const accentPurple = Colors.purpleAccent;
  static const accentGreen = Colors.greenAccent;
  static const accentOrange = Colors.orangeAccent;
  static const accentBlue = Colors.blueAccent;
  
  // ─── Glass Morphism Colors ──────────────────────────────────
  static final glassBackground = Colors.white.withValues(alpha: 0.02);
  static final glassBorder = Colors.white.withValues(alpha: 0.05);
  static final glassBackgroundLight = Colors.white.withValues(alpha: 0.04);
  static final glassBorderLight = Colors.white.withValues(alpha: 0.08);
  
  // ─── Text Colors ────────────────────────────────────────────
  static const textWhite = Colors.white;
  static const textWhite70 = Colors.white70;
  static const textWhite54 = Colors.white54;
  static const textWhite38 = Colors.white38;
  static const textWhite24 = Colors.white24;
}

/// Common border radius values
class AppBorderRadius {
  AppBorderRadius._();
  
  static final small = BorderRadius.circular(6);
  static final medium = BorderRadius.circular(8);
  static final large = BorderRadius.circular(12);
  static final extraLarge = BorderRadius.circular(16);
  static final full = BorderRadius.circular(999);
}

/// Common padding values
class AppPadding {
  AppPadding._();
  
  static const extraSmall = EdgeInsets.all(4);
  static const small = EdgeInsets.all(8);
  static const medium = EdgeInsets.all(12);
  static const large = EdgeInsets.all(16);
  static const extraLarge = EdgeInsets.all(24);
  
  static const horizontalSmall = EdgeInsets.symmetric(horizontal: 8);
  static const horizontalMedium = EdgeInsets.symmetric(horizontal: 12);
  static const horizontalLarge = EdgeInsets.symmetric(horizontal: 16);
  
  static const verticalSmall = EdgeInsets.symmetric(vertical: 4);
  static const verticalMedium = EdgeInsets.symmetric(vertical: 8);
  static const verticalLarge = EdgeInsets.symmetric(vertical: 12);
}

/// Responsive breakpoint constants
class Responsive {
  Responsive._();
  
  static const double desktopBreakpoint = 800;
  static const double tabletBreakpoint = 600;
  
  static bool isDesktop(BuildContext context) => 
      MediaQuery.of(context).size.width > desktopBreakpoint;
  
  static bool isTablet(BuildContext context) => 
      MediaQuery.of(context).size.width > tabletBreakpoint &&
      MediaQuery.of(context).size.width <= desktopBreakpoint;
}
