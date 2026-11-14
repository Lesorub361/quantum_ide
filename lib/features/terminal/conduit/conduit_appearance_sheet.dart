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
    'Source Code Pro' => 'Source Code Pro',
    'IBM Plex Mono' => 'IBM Plex Mono',
    'Space Mono' => 'Space Mono',
    'Roboto Mono' => 'Roboto Mono',
    'Ubuntu Mono' => 'Ubuntu Mono',
    'Inconsolata' => 'Inconsolata',
    'System mono' || 'monospace' => 'monospace',
    _ => 'AtkynsonMonoNerdFontMono',
  };
}

/// Live interactive 3-mode demonstration preview for Terminal, Code Editor & App UI.
class ConduitThemeLivePreview extends StatefulWidget {
  final AppPalette palette;
  final String fontFamily;
  final double fontSize;

  const ConduitThemeLivePreview({
    super.key,
    required this.palette,
    required this.fontFamily,
    required this.fontSize,
  });

  @override
  State<ConduitThemeLivePreview> createState() =>
      _ConduitThemeLivePreviewState();
}

class _ConduitThemeLivePreviewState extends State<ConduitThemeLivePreview> {
  int _tab = 0; // 0 = Terminal, 1 = Code, 2 = App UI

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final previewSize = widget.fontSize.clamp(10.0, 15.0);
    return Container(
      decoration: BoxDecoration(
        color: p.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.panel,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Text(
                  'Демонстрация: ${p.label}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                for (final item in const [
                  (0, 'Терминал'),
                  (1, 'Код'),
                  (2, 'Приложение'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() => _tab = item.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _tab == item.$1
                              ? p.accent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.$2,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: _tab == item.$1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _tab == item.$1 ? p.accent : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _tab == 0
                ? _buildTerminalPreview(p, previewSize)
                : (_tab == 1
                    ? _buildCodePreview(p, previewSize)
                    : _buildAppPreview(p)),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalPreview(AppPalette p, double size) {
    final style = TextStyle(
      fontFamily: resolveConduitFontFamily(widget.fontFamily),
      fontSize: size,
      height: 1.4,
      color: Colors.white.withValues(alpha: 0.9),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: style,
            children: [
              TextSpan(text: 'quantum@ide ', style: TextStyle(color: p.accent, fontWeight: FontWeight.bold)),
              const TextSpan(text: '~/app ', style: TextStyle(color: Color(0xFF38BDF8))),
              const TextSpan(text: '\$ flutter run -d linux'),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '✓ Built build/linux/x64/release/bundle (1.8s)',
          style: style.copyWith(color: const Color(0xFF4ADE80)),
        ),
        Text(
          '⚡ Hot reload ready · Theme: ${p.label}',
          style: style.copyWith(color: Colors.white60),
        ),
      ],
    );
  }

  Widget _buildCodePreview(AppPalette p, double size) {
    final style = TextStyle(
      fontFamily: resolveConduitFontFamily(widget.fontFamily),
      fontSize: size,
      height: 1.45,
      color: Colors.white.withValues(alpha: 0.9),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: style,
            children: [
              const TextSpan(text: '1  ', style: TextStyle(color: Colors.white24)),
              TextSpan(text: 'class ', style: TextStyle(color: p.accent, fontWeight: FontWeight.bold)),
              const TextSpan(text: 'QuantumIde ', style: TextStyle(color: Color(0xFFFBBF24))),
              const TextSpan(text: 'extends '),
              const TextSpan(text: 'StatelessWidget {', style: TextStyle(color: Color(0xFF38BDF8))),
            ],
          ),
        ),
        RichText(
          text: TextSpan(
            style: style,
            children: [
              const TextSpan(text: '2    ', style: TextStyle(color: Colors.white24)),
              const TextSpan(text: 'final '),
              const TextSpan(text: 'theme = ', style: TextStyle(color: Colors.white70)),
              TextSpan(text: '\'${p.label}\'', style: const TextStyle(color: Color(0xFF4ADE80))),
              const TextSpan(text: ';'),
            ],
          ),
        ),
        RichText(
          text: TextSpan(
            style: style,
            children: const [
              TextSpan(text: '3  }', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppPreview(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 46,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: p.canvas,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 4, width: 32, color: p.accent),
                const SizedBox(height: 5),
                Container(height: 3, width: 26, color: Colors.white24),
                const SizedBox(height: 4),
                Container(height: 3, width: 36, color: Colors.white24),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QuantumIDE Workspace',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'Run',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: p.canvas,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: p.border),
                      ),
                      child: const Text(
                        'AI Agent',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
      (label: 'Source Code Pro', value: 'Source Code Pro'),
      (label: 'IBM Plex Mono', value: 'IBM Plex Mono'),
      (label: 'Space Mono', value: 'Space Mono'),
      (label: 'Roboto Mono', value: 'Roboto Mono'),
      (label: 'Ubuntu Mono', value: 'Ubuntu Mono'),
      (label: 'Inconsolata', value: 'Inconsolata'),
      (label: 'System Mono', value: 'monospace'),
    ];

    const presets = [
      (name: 'Cyber Tokyo', term: 'tokyoNight', ed: 'tokyo-night', font: 'JetBrains Mono'),
      (name: 'Catppuccin Mocha', term: 'catppuccin', ed: 'catppuccin-mocha', font: 'Fira Code'),
      (name: 'Nordic Frost', term: 'nord', ed: 'nord', font: 'IBM Plex Mono'),
      (name: 'Dracula Pro', term: 'dracula', ed: 'dracula', font: 'JetBrains Mono'),
      (name: 'Matrix Forest', term: 'everforest', ed: 'monokai-sublime', font: 'Source Code Pro'),
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
              const SizedBox(height: 14),
              ConduitThemeLivePreview(
                palette: currentPalette,
                fontFamily: settings.terminalFontFamily,
                fontSize: fontSize,
              ),
              const SizedBox(height: 14),
              Text(
                'Быстрые пресеты (1 клик)',
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
                  for (final preset in presets)
                    ActionChip(
                      label: Text(preset.name),
                      backgroundColor: currentPalette.panel,
                      side: BorderSide(color: currentPalette.border),
                      onPressed: () => notifier.applyWorkspacePreset(
                        terminalTheme: preset.term,
                        editorTheme: preset.ed,
                        fontFamily: preset.font,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Единый стиль (Терминал + Редактор + IDE)',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  'Применять цвета выбранной палитры ко всему приложению и фону редактора кода',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: Colors.white60,
                  ),
                ),
                value: settings.syncAppWithTerminalPalette,
                activeThumbColor: currentPalette.accent,
                onChanged: (v) => notifier.setSyncAppWithTerminalPalette(v),
              ),
              const SizedBox(height: 12),
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
