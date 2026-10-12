import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
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
        color: const Color(0xFF090B10),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavButton(
                icon: LucideIcons.folder_tree,
                label: 'Files',
                isActive: false,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Scaffold.of(context).openDrawer();
                },
              ),
              _NavButton(
                icon: LucideIcons.file_code,
                label: 'Editor',
                isActive: hasOpenFiles,
                badge: openFilesCount > 0 ? openFilesCount : 0,
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (!hasOpenFiles) {
                    Scaffold.of(context).openDrawer();
                  }
                },
              ),
              _NavButton(
                icon: LucideIcons.terminal,
                label: 'Terminal',
                isActive: isTerminalOpen,
                activeColor: const Color(0xFF00E5FF),
                onTap: () {
                  HapticFeedback.lightImpact();
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
                icon: LucideIcons.sparkles,
                label: 'AI Chat',
                isActive: isAiOpen,
                activeColor: const Color(0xFFB388FF),
                onTap: () {
                  HapticFeedback.lightImpact();
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
  final Color activeColor;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badge = 0,
    this.activeColor = const Color(0xFF6C63FF),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      splashColor: activeColor.withValues(alpha: 0.12),
      highlightColor: activeColor.withValues(alpha: 0.06),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(
                  color: activeColor.withValues(alpha: 0.3),
                  width: 0.8,
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: isActive ? activeColor : Colors.white54,
                ),
                if (badge > 0)
                  Positioned(
                    right: -9,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9.5,
                color: isActive ? activeColor : Colors.white54,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
