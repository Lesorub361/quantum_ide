import 'package:flutter/material.dart';

class AdaptiveDialogHelper {
  /// Displays [builder] content as a centered Glassmorphic Modal Dialog on Desktop/Tablet (width > 800)
  /// or as a Bottom Sheet on Mobile (width <= 800).
  static Future<T?> showAdaptiveSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double desktopMaxWidth = 580,
    double desktopMaxHeight = 650,
    Color backgroundColor = const Color(0xFF13151D),
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(20)),
    bool isScrollControlled = true,
  }) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    if (isDesktop) {
      return showDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: desktopMaxWidth,
                maxHeight: desktopMaxHeight,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: borderRadius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: builder(context),
            ),
          );
        },
      );
    } else {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: isScrollControlled,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.vertical(top: borderRadius.topLeft),
            ),
            clipBehavior: Clip.antiAlias,
            child: builder(context),
          );
        },
      );
    }
  }
}
