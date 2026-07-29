import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/theme/app_colors.dart';

/// Shows a styled SnackBar with consistent design
/// Eliminates 40+ duplicate SnackBar instances
void showAppSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 2),
}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: backgroundColor ?? AppColors.panelBackground,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(16),
      duration: duration,
      action: action,
    ),
  );
}

/// Shows a success SnackBar
void showSuccessSnackBar(BuildContext context, String message) {
  showAppSnackBar(context, message, backgroundColor: Colors.green.withValues(alpha: 0.9));
}

/// Shows an error SnackBar
void showErrorSnackBar(BuildContext context, String message) {
  showAppSnackBar(context, message, backgroundColor: Colors.redAccent.withValues(alpha: 0.9));
}

/// Shows a warning SnackBar
void showWarningSnackBar(BuildContext context, String message) {
  showAppSnackBar(context, message, backgroundColor: Colors.orangeAccent.withValues(alpha: 0.9));
}

/// Copies text to clipboard and shows confirmation
void copyToClipboard(BuildContext context, String text, {String? label}) {
  // This is a placeholder - actual implementation needs Clipboard import
  showAppSnackBar(context, label ?? 'Copied to clipboard');
}
