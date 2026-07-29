import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';

class MobileBottomNav extends ConsumerWidget {
  final VoidCallback? onTerminalToggle;
  final VoidCallback? onAiToggle;
  final VoidCallback? onExplorerToggle;

  const MobileBottomNav({
    super.key,
    this.onTerminalToggle,
    this.onAiToggle,
    this.onExplorerToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorProvider);
    final openFilesCount = editorState.openFiles.length;
    final hasOpenFiles = openFilesCount > 0;
    final panelState = ref.watch(panelProvider);
    final isTerminalOpen = panelState.isOpened && panelState.selectedTab == PanelTab.terminal;
    final isAiOpen = ref.watch(rightChatPanelOpenProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavButton(
                icon: LucideIcons.folder,
                label: 'Files',
                isActive: false,
                onTap: () {
                  Scaffold.of(context).openDrawer();
                },
              ),
              _NavButton(
                icon: LucideIcons.file_code,
                label: 'Editor',
                isActive: hasOpenFiles,
                badge: openFilesCount > 0 ? openFilesCount : 0,
                onTap: () {
                  if (!hasOpenFiles) {
                    Scaffold.of(context).openDrawer();
                  }
                },
              ),
              _NavButton(
                icon: LucideIcons.terminal,
                label: 'Terminal',
                isActive: isTerminalOpen,
                onTap: () {
                  final panelNotifier = ref.read(panelProvider.notifier);
                  if (isTerminalOpen) {
                    panelNotifier.closePanel();
                  } else {
                    panelNotifier.selectTab(PanelTab.terminal);
                    panelNotifier.openPanel();
                  }
                },
              ),
              _NavButton(
                icon: LucideIcons.message_square,
                label: 'AI',
                isActive: isAiOpen,
                onTap: () {
                  ref.read(rightChatPanelOpenProvider.notifier).update((v) => !v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int badge;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
                ),
                if (badge > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF6C63FF),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
