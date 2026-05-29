import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

class VirtualKey {
  final String label;
  final String? value;
  final IconData? icon;
  final bool isToggle;
  final bool isCommand;

  VirtualKey({
    required this.label,
    this.value,
    this.icon,
    this.isToggle = false,
    this.isCommand = false,
  });
}

class VirtualKeysView extends ConsumerStatefulWidget {
  final Function(String) onKeyTap;
  final Set<String> activeKeys;

  const VirtualKeysView({
    super.key,
    required this.onKeyTap,
    this.activeKeys = const {},
  });

  @override
  ConsumerState<VirtualKeysView> createState() => _VirtualKeysViewState();
}

class _VirtualKeysViewState extends ConsumerState<VirtualKeysView> {
  @override
  Widget build(BuildContext context) {
    final row1 = [
      VirtualKey(label: 'ESC', value: '\x1b'),
      VirtualKey(label: 'TAB', value: '\t', icon: LucideIcons.arrow_right_to_line),
      VirtualKey(label: 'CTRL', value: 'ctrl', isToggle: true),
      VirtualKey(label: 'ALT', value: 'ALT', isToggle: true),
      VirtualKey(label: '↑', value: '\x1b[A', icon: LucideIcons.arrow_up),
      VirtualKey(label: '↓', value: '\x1b[B', icon: LucideIcons.arrow_down),
      VirtualKey(label: '←', value: '\x1b[D', icon: LucideIcons.arrow_left),
      VirtualKey(label: '→', value: '\x1b[C', icon: LucideIcons.arrow_right),
    ];

    final row2 = [
      VirtualKey(label: '/', value: '/'),
      VirtualKey(label: '|', value: '|'),
      VirtualKey(label: '_', value: '_'),
      VirtualKey(label: '\$', value: '\$'),
      VirtualKey(label: 'Ctrl+C', value: 'ctrl+c'),
      VirtualKey(label: 'Ctrl+L', value: 'ctrl+l'),
      VirtualKey(label: 'Paste', value: 'paste', icon: LucideIcons.clipboard_paste),
      // HOME = \x1b[H, END = \x1b[F (standard ANSI, works in bash/vim/zsh)
      VirtualKey(label: 'HOME', value: '\x1b[H'),
      VirtualKey(label: 'END', value: '\x1b[F'),
      VirtualKey(label: '⌫', value: '\x7f', icon: LucideIcons.delete),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildKeyRow(row1),
            const SizedBox(height: 4),
            _buildKeyRow(row2),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<VirtualKey> keys) {
    return Row(
      children: keys.map((key) {
        final isActive = widget.activeKeys.contains(key.label);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _VirtualKeyButton(
              keyData: key,
              isActive: isActive,
              onTap: () => widget.onKeyTap(key.value ?? key.label),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VirtualKeyButton extends StatelessWidget {
  final VirtualKey keyData;
  final bool isActive;
  final VoidCallback onTap;

  const _VirtualKeyButton({
    required this.keyData,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color buttonColor = Colors.white.withValues(alpha: 0.05);
    Color borderColor = Colors.white.withValues(alpha: 0.03);
    Color themeColor = Colors.white70;

    if (isActive) {
      buttonColor = Colors.cyanAccent.withValues(alpha: 0.2);
      borderColor = Colors.cyanAccent.withValues(alpha: 0.3);
      themeColor = Colors.cyanAccent;
    } else if (keyData.value == 'ctrl+c') {
      buttonColor = Colors.redAccent.withValues(alpha: 0.1);
      borderColor = Colors.redAccent.withValues(alpha: 0.2);
      themeColor = Colors.redAccent;
    } else if (keyData.value == 'paste') {
      buttonColor = Colors.purpleAccent.withValues(alpha: 0.1);
      borderColor = Colors.purpleAccent.withValues(alpha: 0.2);
      themeColor = Colors.purpleAccent;
    }

    return Material(
      color: buttonColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: keyData.icon != null
              ? Icon(keyData.icon, size: 14, color: themeColor)
              : Text(
                  keyData.label,
                  style: GoogleFonts.jetBrainsMono(
                    color: themeColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
