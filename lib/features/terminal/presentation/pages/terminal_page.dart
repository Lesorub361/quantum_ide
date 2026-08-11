import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/features/terminal/presentation/widgets/terminal_panel_content.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class TerminalPage extends ConsumerWidget {
  const TerminalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final workspacePath = ref.watch(workspaceProvider).currentPath;
    final targetRoute = workspacePath == null ? '/' : '/editor';

    final terminalThemeName = ref.watch(settingsProvider).terminalTheme;
    Color bg;
    switch (terminalThemeName) {
      case 'dracula':
        bg = const Color(0xFF282A36);
        break;
      case 'monokai':
        bg = const Color(0xFF272822);
        break;
      case 'dark':
        bg = const Color(0xFF0D0F14);
        break;
      case 'ubuntu':
      default:
        bg = const Color(0xFF300A24);
        break;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isKeyboardOpen) {
          FocusManager.instance.primaryFocus?.unfocus();
        } else {
          context.go(targetRoute);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: GlassAppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.arrow_left, size: 20, color: Colors.cyanAccent),
            onPressed: () => context.go(targetRoute),
          ),
          title: Text(
            AppLocalizations.of(context)!.terminal,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.refresh_cw, size: 20, color: Colors.amberAccent),
              tooltip: 'Restart Shell',
              onPressed: () {
                final notifier = ref.read(terminalTabsProvider.notifier);
                notifier.restartSession(notifier.currentIndex);
              },
            ),
            IconButton(
              icon: const Icon(LucideIcons.house, size: 20, color: Colors.white70),
              onPressed: () async {
                await ref.read(workspaceProvider.notifier).closeWorkspace();
                if (context.mounted) {
                  context.go('/');
                }
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: const TerminalPanelContent(onlyTerminal: true),
      ),
    );
  }
}
