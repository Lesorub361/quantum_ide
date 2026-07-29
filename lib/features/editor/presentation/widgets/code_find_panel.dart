import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:re_editor/re_editor.dart';

const double _kFindPanelWidth = 380;
const double _kFindPanelHeight = 44;
const double _kReplacePanelHeight = _kFindPanelHeight * 2;

class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  Size get preferredSize => Size(
    double.infinity,
    controller.value == null ? 0 :
      (controller.value!.replaceMode ? _kReplacePanelHeight : _kFindPanelHeight) + 12
  );

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
      alignment: Alignment.topRight,
      height: preferredSize.height,
      child: Container(
        width: _kFindPanelWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2230).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFindRow(context, value, theme),
            if (value.replaceMode) ...[
              const SizedBox(height: 6),
              _buildReplaceRow(context, value, theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFindRow(BuildContext context, CodeFindValue value, ThemeData theme) {
    final String matchText;
    if (value.result == null || value.result!.matches.isEmpty) {
      matchText = '0/0';
    } else {
      matchText = '${value.result!.index + 1}/${value.result!.matches.length}';
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          // Find Input
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  TextField(
                    controller: controller.findInputController,
                    focusNode: controller.findInputFocusNode,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.fromLTRB(8, 6, 64, 6),
                      border: InputBorder.none,
                      hintText: 'Search...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToggleOption(
                          text: 'Aa',
                          checked: value.option.caseSensitive,
                          onTap: () => controller.toggleCaseSensitive(),
                          theme: theme,
                        ),
                        const SizedBox(width: 4),
                        _buildToggleOption(
                          text: '.*',
                          checked: value.option.regex,
                          onTap: () => controller.toggleRegex(),
                          theme: theme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Matches Count
          Text(
            matchText,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          // Navigation & Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIconButton(
                icon: LucideIcons.arrow_up,
                onPressed: value.result == null || value.result!.matches.isEmpty
                    ? null
                    : () => controller.previousMatch(),
                tooltip: 'Previous Match',
              ),
              _buildIconButton(
                icon: LucideIcons.arrow_down,
                onPressed: value.result == null || value.result!.matches.isEmpty
                    ? null
                    : () => controller.nextMatch(),
                tooltip: 'Next Match',
              ),
              _buildIconButton(
                icon: LucideIcons.replace,
                onPressed: readOnly
                    ? null
                    : () => controller.toggleMode(),
                tooltip: 'Toggle Replace',
                color: value.replaceMode ? theme.colorScheme.primary : Colors.white60,
              ),
              _buildIconButton(
                icon: LucideIcons.x,
                onPressed: () => controller.close(),
                tooltip: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplaceRow(BuildContext context, CodeFindValue value, ThemeData theme) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          // Replace Input
          Expanded(
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: controller.replaceInputController,
                focusNode: controller.replaceInputFocusNode,
                maxLines: 1,
                readOnly: readOnly,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: InputBorder.none,
                  hintText: 'Replace...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIconButton(
                icon: LucideIcons.check,
                onPressed: value.result == null || value.result!.matches.isEmpty || readOnly
                    ? null
                    : () => controller.replaceMatch(),
                tooltip: 'Replace Current',
              ),
              _buildIconButton(
                icon: LucideIcons.check_check,
                onPressed: value.result == null || value.result!.matches.isEmpty || readOnly
                    ? null
                    : () => controller.replaceAllMatches(),
                tooltip: 'Replace All',
              ),
              // Dummy spacer to match the close button layout width
              const SizedBox(width: 28),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String text,
    required bool checked,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: checked ? theme.colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: checked ? theme.colorScheme.primary.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: checked ? theme.colorScheme.primary : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    Color? color,
  }) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 16,
              color: color ?? (enabled ? Colors.white70 : Colors.white24),
            ),
          ),
        ),
      ),
    );
  }
}
