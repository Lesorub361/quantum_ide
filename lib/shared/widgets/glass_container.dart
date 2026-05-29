import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/settings_service.dart';

class GlassContainer extends ConsumerWidget {
  final Widget child;
  final double? blur;
  final double? opacity;
  final Color color;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final List<Color>? gradientColors;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur,
    this.opacity,
    this.color = Colors.white,
    this.borderRadius,
    this.border,
    this.padding,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final effectiveBlur = blur ?? settings.glassmorphismBlur;
    final effectiveOpacity = opacity ?? settings.glassmorphismOpacity;

    Widget current = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradientColors == null ? color.withValues(alpha: effectiveOpacity) : null,
        gradient: gradientColors != null 
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors!.map((c) => c.withValues(alpha: effectiveOpacity)).toList(),
            )
          : null,
        borderRadius: borderRadius,
        border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: child,
    );

    if (effectiveBlur > 0) {
      current = ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
          child: current,
        ),
      );
    } else {
      current = ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: current,
      );
    }

    return current;
  }
}

class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final double? blur;
  final double? opacity;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.blur,
    this.opacity,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final effectiveBlur = blur ?? settings.glassmorphismBlur;
    final effectiveOpacity = opacity ?? settings.glassmorphismOpacity;

    Widget appBar = AppBar(
      title: title,
      actions: actions,
      leading: leading,
      bottom: bottom,
      backgroundColor: Colors.black.withValues(alpha: effectiveOpacity),
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.02),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );

    if (effectiveBlur > 0) {
      return ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
          child: appBar,
        ),
      );
    }
    return ClipRRect(child: appBar);
  }

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );
}

