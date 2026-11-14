import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/theme/conduit_palette.dart';
import 'package:quantum_ide/core/theme/conduit_terminal_appearance.dart';

/// Resolves an [AppPalette] from QuantumIDE's `terminalTheme` setting name.
AppPalette resolveConduitPalette(String themeName) {
  for (final p in AppPalette.values) {
    if (p.name == themeName) return p;
  }
  return switch (themeName) {
    'ubuntu' => AppPalette.rosePine,
    'matrix' => AppPalette.everforest,
    'dark' => AppPalette.tokyoNight,
    _ => AppPalette.catppuccin,
  };
}

/// Resolves a font family string for `conduit_vt` `TerminalStyle`.
String resolveConduitFontFamily(String fontName) {
  return switch (fontName) {
    'Nerd Font' || 'AtkynsonMonoNerdFontMono' => 'AtkynsonMonoNerdFontMono',
    'JetBrains Mono' || 'jetBrainsMono' => 'jetBrainsMono',
    'Fira Code' || 'firaCode' => 'firaCode',
    'Cascadia Code' || 'cascadia' => 'cascadia',
    'Hack' || 'hack' => 'hack',
    'System mono' || 'monospace' => 'monospace',
    _ => 'AtkynsonMonoNerdFontMono',
  };
}

/// Shows Conduit's terminal appearance & palette switcher bottom sheet.
Future<void> showConduitAppearanceSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14161F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ConduitAppearanceSheet(),
  );
}

class _ConduitAppearanceSheet extends ConsumerWidget {
  const _ConduitAppearanceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final currentPalette = resolveConduitPalette(settings.terminalTheme);
    final fontSize = clampTerminalFontSize(settings.terminalFontSize);

    const fonts = [
      (label: 'Nerd Font (Conduit)', value: 'AtkynsonMonoNerdFontMono'),
      (label: 'JetBrains Mono', value: 'JetBrains Mono'),
      (label: 'Fira Code', value: 'Fira Code'),
      (label: 'System Mono', value: 'monospace'),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return SafeArea(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Оформление терминала (Conduit)',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите палитру фона, шрифт и размер текста. Поддерживается также щипок двумя пальцами.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 18),
              Text(
                'Размер шрифта: ${fontSize.toStringAsFixed(1)}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Slider(
                value: fontSize,
                min: 8.0,
                max: 24.0,
                divisions: 32,
                activeColor: currentPalette.accent,
                onChanged: (v) => notifier.setTerminalFontSize(v),
              ),
              const SizedBox(height: 10),
              Text(
                'Шрифт',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in fonts)
                    ChoiceChip(
                      label: Text(f.label),
                      selected:
                          resolveConduitFontFamily(settings.terminalFontFamily) ==
                              resolveConduitFontFamily(f.value),
                      selectedColor: currentPalette.accent.withValues(alpha: 0.25),
                      onSelected: (_) => notifier.setTerminalFontFamily(f.value),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Физическая клавиатура (скрывать экранную)',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  'Для USB / Bluetooth клавиатур: не поднимать виртуальную клавиатуру Android при тапе',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: Colors.white60,
                  ),
                ),
                value: settings.hardwareKeyboardMode,
                activeThumbColor: currentPalette.accent,
                onChanged: (v) => notifier.setHardwareKeyboardMode(v),
              ),
              const SizedBox(height: 14),
              Text(
                'Палитра и фон терминала (${AppPalette.values.length})',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.55,
                ),
                itemCount: AppPalette.values.length,
                itemBuilder: (context, index) {
                  final palette = AppPalette.values[index];
                  final selected =
                      settings.terminalTheme == palette.name ||
                      (currentPalette == palette &&
                          !AppPalette.values.any(
                            (p) => p.name == settings.terminalTheme,
                          ));

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => notifier.setTerminalTheme(palette.name),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: palette.canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? palette.accent : palette.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  palette.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: palette.foreground,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: palette.accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            palette.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: palette.mutedForeground,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _dot(palette.terminalTheme.red),
                              _dot(palette.terminalTheme.green),
                              _dot(palette.terminalTheme.yellow),
                              _dot(palette.terminalTheme.blue),
                              _dot(palette.terminalTheme.magenta),
                              _dot(palette.terminalTheme.cyan),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
