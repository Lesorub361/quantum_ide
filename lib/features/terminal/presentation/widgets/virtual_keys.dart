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
    final keys = [
      VirtualKey(label: 'ESC', value: '\x1b'),
      VirtualKey(label: 'TAB', value: '\t'),
      VirtualKey(label: 'CTRL', value: 'ctrl', isToggle: true),
      VirtualKey(label: 'ALT', value: 'ALT', isToggle: true),
      VirtualKey(label: 'SHIFT', value: 'SHIFT', isToggle: true),
      VirtualKey(label: '↑', value: '\x1b[A', icon: LucideIcons.arrow_up),
      VirtualKey(label: '↓', value: '\x1b[B', icon: LucideIcons.arrow_down),
      VirtualKey(label: '←', value: '\x1b[D', icon: LucideIcons.arrow_left),
      VirtualKey(label: '→', value: '\x1b[C', icon: LucideIcons.arrow_right),
      VirtualKey(label: 'COPY', value: 'copy', icon: LucideIcons.copy),
      VirtualKey(label: 'PASTE', value: 'paste', icon: LucideIcons.clipboard_paste),
      VirtualKey(label: 'SEL', value: 'select_all'),
      VirtualKey(label: 'C-C', value: 'ctrl+c'),
      VirtualKey(label: 'C-D', value: 'ctrl+d'),
      VirtualKey(label: 'C-Z', value: 'ctrl+z'),
      VirtualKey(label: 'CLR', value: 'ctrl+l'),
      VirtualKey(label: '/', value: '/'),
      VirtualKey(label: '-', value: '-'),
      VirtualKey(label: '_', value: '_'),
      VirtualKey(label: '~', value: '~'),
      VirtualKey(label: '|', value: '|'),
      VirtualKey(label: '>', value: '>'),
      VirtualKey(label: '<', value: '<'),
      VirtualKey(label: '\$', value: '\$'),
    ];

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14).withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: keys.length,
        separatorBuilder: (context, index) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final key = keys[index];
          final isActive = widget.activeKeys.contains(key.label);
          return _VirtualKeyButton(
            keyData: key,
            isActive: isActive,
            onTap: () => widget.onKeyTap(key.value ?? key.label),
          );
        },
      ),
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
    Color buttonColor = Colors.white.withValues(alpha: 0.06);
    Color borderColor = Colors.white.withValues(alpha: 0.08);
    Color themeColor = Colors.white70;

    if (isActive) {
      buttonColor = Colors.cyanAccent.withValues(alpha: 0.25);
      borderColor = Colors.cyanAccent.withValues(alpha: 0.5);
      themeColor = Colors.cyanAccent;
    } else if (keyData.value == 'ctrl+c' || keyData.value == 'ctrl+z') {
      buttonColor = Colors.redAccent.withValues(alpha: 0.12);
      borderColor = Colors.redAccent.withValues(alpha: 0.25);
      themeColor = const Color(0xFFFF6B6B);
    } else if (keyData.value == 'copy' || keyData.value == 'paste' || keyData.value == 'select_all') {
      buttonColor = const Color(0xFF8B5CF6).withValues(alpha: 0.15);
      borderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.3);
      themeColor = const Color(0xFFC084FC);
    }

    return Material(
      color: buttonColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (keyData.icon != null) ...[
                Icon(keyData.icon, size: 14, color: themeColor),
                if (keyData.label.isNotEmpty && keyData.label != '↑' && keyData.label != '↓' && keyData.label != '←' && keyData.label != '→')
                  const SizedBox(width: 4),
              ],
              if (keyData.icon == null || (keyData.label.isNotEmpty && keyData.label != '↑' && keyData.label != '↓' && keyData.label != '←' && keyData.label != '→'))
                Text(
                  keyData.label,
                  style: GoogleFonts.jetBrainsMono(
                    color: themeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
