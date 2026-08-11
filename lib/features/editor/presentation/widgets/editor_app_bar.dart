import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/core/utils/file_icon_helper.dart';
import 'package:path/path.dart' as p;

class EditorAppBarTitle extends ConsumerWidget {
  const EditorAppBarTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeFile = ref.watch(editorProvider.select((s) {
      if (s.openFiles.isEmpty) return null;
      int idx = s.activeTabIndex;
      if (idx < 0 || idx >= s.openFiles.length) {
        idx = s.openFiles.length - 1;
      }
      return s.openFiles[idx];
    }));

    if (activeFile == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkles, size: 12, color: Colors.cyanAccent),
                const SizedBox(width: 6),
                Text(
                  'QuantumIDE',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.cyanAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final iconInfo = FileIconHelper.getIconInfo(activeFile.name, false);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconInfo.icon, size: 14, color: iconInfo.color),
        const SizedBox(width: 8),
        Text(
          activeFile.name,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        if (activeFile.isModified) ...[
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.amberAccent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Строка Вкладок Редактора (Redesigned) ──────────────────────────────────

class EditorTabBar extends ConsumerWidget {
  const EditorTabBar({super.key});

  void _showTabContextMenu(BuildContext context, WidgetRef ref, int index, Offset globalPosition) async {
    final notifier = ref.read(editorProvider.notifier);
    final openFiles = ref.read(editorProvider).openFiles;
    final file = openFiles[index];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      color: const Color(0xFF131722),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'close',
          child: Row(
            children: [
              Icon(LucideIcons.x, size: 14, color: Colors.white70),
              SizedBox(width: 8),
              Text('Закрыть', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'close_others',
          child: Row(
            children: [
              Icon(LucideIcons.circle_minus, size: 14, color: Colors.white70),
              SizedBox(width: 8),
              Text('Закрыть другие', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'close_right',
          child: Row(
            children: [
              Icon(LucideIcons.arrow_right, size: 14, color: Colors.white70),
              SizedBox(width: 8),
              Text('Закрыть справа', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(LucideIcons.copy, size: 14, color: Colors.white70),
              SizedBox(width: 8),
              Text('Копировать путь', style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      ],
    );

    if (result == 'close') {
      notifier.closeTab(index);
    } else if (result == 'close_others') {
      final currentOpen = [...ref.read(editorProvider).openFiles];
      for (int i = currentOpen.length - 1; i >= 0; i--) {
        if (i != index) notifier.closeTab(i);
      }
    } else if (result == 'close_right') {
      final currentOpen = [...ref.read(editorProvider).openFiles];
      for (int i = currentOpen.length - 1; i > index; i--) {
        notifier.closeTab(i);
      }
    } else if (result == 'copy_path') {
      await Clipboard.setData(ClipboardData(text: file.path));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Путь скопирован: ${p.basename(file.path)}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E2230),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openFiles = ref.watch(editorProvider.select((s) => s.openFiles));
    final activeTabIndex = ref.watch(editorProvider.select((s) => s.activeTabIndex));
    final notifier = ref.read(editorProvider.notifier);

    if (openFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1017),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        itemCount: openFiles.length,
        itemBuilder: (context, index) {
          final file = openFiles[index];
          final isActive = index == activeTabIndex;
          final iconInfo = FileIconHelper.getIconInfo(file.name, false);

          return Listener(
            onPointerDown: (event) {
              if (event.buttons == 4) { // Middle click
                notifier.closeTab(index);
              }
            },
            child: GestureDetector(
              onTap: () => notifier.setActiveTab(index),
              onSecondaryTapDown: (details) => _showTabContextMenu(context, ref, index, details.globalPosition),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(right: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF181C28) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive 
                        ? Colors.cyanAccent.withValues(alpha: 0.3) 
                        : Colors.transparent,
                    width: 0.6,
                  ),
                  boxShadow: isActive ? [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.04),
                      blurRadius: 4,
                      spreadRadius: 0.5,
                    )
                  ] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      iconInfo.icon,
                      size: 11,
                      color: isActive ? iconInfo.color : iconInfo.color.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      file.name,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive ? Colors.white : Colors.white60,
                      ),
                    ),
                    const SizedBox(width: 5),
                    if (file.isModified)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: const BoxDecoration(
                          color: Colors.amberAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => notifier.closeTab(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          LucideIcons.x,
                          size: 10,
                          color: isActive ? Colors.white70 : Colors.white30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
