import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/features/terminal/conduit/conduit_appearance_sheet.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_panel_content.dart';

class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key});

  void _navigateBack(BuildContext context, String? workspacePath) {
    if (context.canPop()) {
      context.pop();
    } else if (workspacePath != null && workspacePath.isNotEmpty) {
      context.go('/editor');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final workspacePath = ref.watch(workspaceProvider).currentPath;

    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    final bg = resolveConduitPalette(terminalThemeName).canvas;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isKeyboardOpen) {
          FocusManager.instance.primaryFocus?.unfocus();
        } else {
          _navigateBack(context, workspacePath);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: TerminalPanelContent(
            onlyTerminal: true,
            onBack: () => _navigateBack(context, workspacePath),
          ),
        ),
      ),
    );
  }
}
