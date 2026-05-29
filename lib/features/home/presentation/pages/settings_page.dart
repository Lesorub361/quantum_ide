import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:quantum_ide/core/providers/locale_provider.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/features/home/presentation/pages/ai_settings_page.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final sn = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Ambient glow
          Positioned(top: -60, right: -60,
            child: Container(width: 250, height: 250,
              decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: RadialGradient(colors: [theme.colorScheme.primary.withValues(alpha: 0.12), Colors.transparent])))),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(LucideIcons.arrow_left, color: theme.colorScheme.onSurface),
                  onPressed: () => context.go('/'),
                ),
                title: ShaderMask(
                  shaderCallback: (b) => LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]).createShader(b),
                  child: Text(AppLocalizations.of(context)!.settings, style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.white)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  // ─── Основное ───────────────────────────────
                  _sectionHeader(context, AppLocalizations.of(context)!.interfaceAndLocalization),
                  _settingsGroup(context, [
                    _tile(context, icon: LucideIcons.languages, title: AppLocalizations.of(context)!.language, subtitle: Localizations.localeOf(context).languageCode == 'ru' ? 'Русский' : 'English',
                      trailing: _badge(context, Localizations.localeOf(context).languageCode.toUpperCase(), theme.colorScheme.primary),
                      onTap: () => ref.read(localeProvider.notifier).toggleLocale()),
                    _tile(context, icon: LucideIcons.palette, title: AppLocalizations.of(context)!.theme, subtitle: s.themeMode == ThemeMode.dark ? AppLocalizations.of(context)!.darkTheme : AppLocalizations.of(context)!.lightTheme,
                      trailing: Icon(s.themeMode == ThemeMode.dark ? LucideIcons.moon : LucideIcons.sun, size: 18, color: theme.colorScheme.primary),
                      onTap: () => sn.setThemeMode(s.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark)),
                    _tile(
                      context,
                      icon: LucideIcons.sparkles, 
                      title: AppLocalizations.of(context)!.colorPalette, 
                      subtitle: s.customPrimaryColor != null ? AppLocalizations.of(context)!.customColor : s.flexScheme,
                      onTap: () => _showSchemeDialog(context, s.flexScheme, sn.setFlexScheme),
                    ),
                    _tile(
                      context,
                      icon: LucideIcons.pipette, 
                      title: AppLocalizations.of(context)!.accentColor, 
                      subtitle: s.customPrimaryColor != null ? '#${s.customPrimaryColor!.toRadixString(16).toUpperCase().substring(2)}' : AppLocalizations.of(context)!.defaultAccent,
                      trailing: Container(
                        width: 16, height: 16, 
                        decoration: BoxDecoration(
                          color: s.customPrimaryColor != null ? Color(s.customPrimaryColor!) : theme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      onTap: () => _showColorPickerDialog(context, s.customPrimaryColor != null ? Color(s.customPrimaryColor!) : null, sn.setCustomPrimaryColor),
                    ),
                  ]),

                  const SizedBox(height: 24),
                  // ─── Эффекты Стекла (Glassmorphism) ─────────────
                  _sectionHeader(context, isRu ? 'Эффекты стекла (Glassmorphism)' : 'Glassmorphism Effects'),
                  _settingsGroup(context, [
                    _tile(context, icon: LucideIcons.layers, title: isRu ? 'Прозрачность эффекта' : 'Glass Opacity', subtitle: '${(s.glassmorphismOpacity * 100).toInt()}%',
                      onTap: () => _showSliderDialog(context, isRu ? 'Прозрачность эффекта' : 'Glass Opacity', s.glassmorphismOpacity, 0.05, 0.60, sn.setGlassmorphismOpacity, isPercentage: true, divisions: 11)),
                    _tile(context, icon: LucideIcons.blend, title: isRu ? 'Размытие фона (Blur)' : 'Backdrop Blur', subtitle: '${s.glassmorphismBlur.toInt()} px',
                      onTap: () => _showSliderDialog(context, isRu ? 'Размытие фона (Blur)' : 'Backdrop Blur', s.glassmorphismBlur, 0.0, 30.0, sn.setGlassmorphismBlur)),
                  ]),

                  const SizedBox(height: 24),
                  // ─── Редактор ─────────────────────────────────
                  _sectionHeader(context, AppLocalizations.of(context)!.codeEditor),
                  _settingsGroup(context, [
                    _tile(context, icon: LucideIcons.type, title: AppLocalizations.of(context)!.editorFontSize, subtitle: '${s.fontSize.toInt()} px',
                      onTap: () => _showSliderDialog(context, AppLocalizations.of(context)!.editorFontSize, s.fontSize, 8, 32, sn.setFontSize)),
                    _tile(context, icon: LucideIcons.code, title: isRu ? 'Шрифт редактора' : 'Editor Font Family', subtitle: s.editorFontFamily,
                      onTap: () => _showFontFamilyDialog(context, s.editorFontFamily, sn.setEditorFontFamily)),
                    _switchTile(context, title: isRu ? 'Лигатуры шрифта' : 'Font Ligatures', subtitle: isRu ? 'Включить лигатуры в коде (например, -> или !=)' : 'Enable font ligatures in code', value: s.editorFontLigatures, onChanged: sn.setEditorFontLigatures),
                    _switchTile(context, title: AppLocalizations.of(context)!.autoCompletion, subtitle: AppLocalizations.of(context)!.showCodeHints, value: s.autoCompletion, onChanged: sn.setAutoCompletion),
                    _switchTile(context, title: AppLocalizations.of(context)!.aiAutoCompletion, subtitle: AppLocalizations.of(context)!.geminiCodeGeneration, value: s.aiAutoCompletion, onChanged: sn.setAiAutoCompletion),
                    _switchTile(context, title: AppLocalizations.of(context)!.wordWrap, subtitle: AppLocalizations.of(context)!.wordWrapDescription, value: s.wordWrap, onChanged: sn.setWordWrap),
                    _switchTile(context, title: AppLocalizations.of(context)!.lineNumbers, subtitle: AppLocalizations.of(context)!.showLineNumbers, value: s.lineNumbers, onChanged: sn.setLineNumbers),
                    _switchTile(context, title: AppLocalizations.of(context)!.minimap, subtitle: AppLocalizations.of(context)!.showMinimap, value: s.minimap, onChanged: sn.setMinimap),
                    _switchTile(context, title: AppLocalizations.of(context)!.autoSave, subtitle: AppLocalizations.of(context)!.autoSaveDescription, value: s.autoSave, onChanged: sn.setAutoSave),
                  ]),

                  const SizedBox(height: 24),
                  // ─── Терминал ─────────────────────────────────
                  _sectionHeader(context, AppLocalizations.of(context)!.terminal),
                  _settingsGroup(context, [
                    _tile(context, icon: LucideIcons.terminal, title: AppLocalizations.of(context)!.terminalFontSize, subtitle: '${s.terminalFontSize.toInt()} px',
                      onTap: () => _showSliderDialog(context, AppLocalizations.of(context)!.terminalFontSize, s.terminalFontSize, 8, 24, sn.setTerminalFontSize)),
                    _tile(context, icon: LucideIcons.palette, title: AppLocalizations.of(context)!.terminalTheme, subtitle: _terminalThemeName(context, s.terminalTheme),
                      onTap: () => _showTerminalThemeDialog(context, s.terminalTheme, sn.setTerminalTheme)),
                  ]),

                  const SizedBox(height: 24),
                  // ─── Инструменты ──────────────────────────────
                  _sectionHeader(context, AppLocalizations.of(context)!.toolsAndAi),
                  _settingsGroup(context, [
                    _tile(
                      context,
                      icon: LucideIcons.bot,
                      title: AppLocalizations.of(context)!.aiProviders,
                      subtitle: AppLocalizations.of(context)!.aiProvidersSubtitle,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiSettingsPage())),
                    ),
                    _tile(context, icon: LucideIcons.package, title: AppLocalizations.of(context)!.ubuntuPackages, subtitle: AppLocalizations.of(context)!.manageCliTools,
                      onTap: () => context.push('/packages')),
                    _tile(context, icon: LucideIcons.server, title: AppLocalizations.of(context)!.servers, subtitle: AppLocalizations.of(context)!.localRemoteHosts,
                      onTap: () => context.push('/servers')),
                  ]),

                  const SizedBox(height: 24),
                  // ─── Система ──────────────────────────────────
                  _sectionHeader(context, AppLocalizations.of(context)!.system),
                  _settingsGroup(context, [
                    _switchTile(context, title: AppLocalizations.of(context)!.showHiddenFiles, subtitle: AppLocalizations.of(context)!.showHiddenFilesDescription, value: s.showHiddenFiles, onChanged: sn.setShowHiddenFiles),
                    _switchTile(context, title: AppLocalizations.of(context)!.vibration, subtitle: AppLocalizations.of(context)!.hapticFeedback, value: s.hapticFeedback, onChanged: sn.setHapticFeedback),
                    _tile(context, icon: LucideIcons.info, title: AppLocalizations.of(context)!.aboutApp, subtitle: AppLocalizations.of(context)!.aboutAppSubtitle,
                      onTap: () => _showAbout(context)),
                  ]),
                  const SizedBox(height: 40),
                ])),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _settingsGroup(BuildContext context, List<Widget> children) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: children.asMap().entries.map((e) {
          final isLast = e.key == children.length - 1;
          return Column(
            children: [
              e.value,
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(color: theme.colorScheme.onSurface.withValues(alpha: 0.05), height: 1),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _badge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  Widget _tile(BuildContext context, {required IconData icon, required String title, required String subtitle, Widget? trailing, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: theme.colorScheme.primary.withValues(alpha: 0.7), size: 20),
      title: Text(title, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
      trailing: trailing ?? Icon(LucideIcons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }

  Widget _switchTile(BuildContext context, {required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(title, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: theme.colorScheme.primary,
        inactiveThumbColor: theme.colorScheme.outline.withValues(alpha: 0.5),
        inactiveTrackColor: theme.colorScheme.surfaceContainerHighest,
      ),
    );
  }

  void _showAbout(BuildContext context) {
    final theme = Theme.of(context);
    showAboutDialog(
      context: context,
      applicationName: 'Quantum IDE',
      applicationVersion: '1.0.0',
      applicationIcon: Icon(LucideIcons.zap, color: theme.colorScheme.primary, size: 48),
      children: [
        Text(AppLocalizations.of(context)!.aboutDialogContent),
      ],
    );
  }

  String _terminalThemeName(BuildContext context, String theme) {
    switch (theme) {
      case 'ubuntu': return AppLocalizations.of(context)!.ubuntuDarkPurple;
      case 'dracula': return 'Dracula';
      case 'monokai': return 'Monokai';
      case 'dark': return AppLocalizations.of(context)!.pureDark;
      default: return theme;
    }
  }

  void _showSliderDialog(BuildContext context, String title, double current, double min, double max, ValueChanged<double> onChanged, {bool isPercentage = false, int? divisions}) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: StatefulBuilder(builder: (ctx, setState) {
          double v = current;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ShaderMask(
              shaderCallback: (b) => LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]).createShader(b),
              child: Text(
                isPercentage ? '${(v * 100).toInt()}%' : '${v.toInt()} px',
                style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(ctx).copyWith(
                activeTrackColor: theme.colorScheme.primary,
                thumbColor: theme.colorScheme.primary,
                inactiveTrackColor: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                overlayColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: v,
                min: min,
                max: max,
                divisions: divisions ?? (max - min).toInt(),
                onChanged: (nv) {
                  setState(() => v = nv);
                  onChanged(nv);
                },
              ),
            ),
          ]);
        }),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.close, style: TextStyle(color: theme.colorScheme.primary)))],
      ),
    );
  }

  void _showFontFamilyDialog(BuildContext context, String current, ValueChanged<String> onChanged) {
    final theme = Theme.of(context);
    final fonts = [
      'JetBrains Mono',
      'Fira Code',
      'Source Code Pro',
      'Inconsolata',
      'Anonymous Pro',
      'Monospace',
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          Localizations.localeOf(context).languageCode == 'ru' ? 'Выберите шрифт' : 'Select Font Family',
          style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: fonts.length,
            itemBuilder: (ctx, i) {
              final font = fonts[i];
              final isSel = current.toLowerCase().replaceAll(' ', '') == font.toLowerCase().replaceAll(' ', '');
              TextStyle textStyle;
              try {
                if (font == 'Monospace') {
                  textStyle = const TextStyle(fontFamily: 'monospace');
                } else {
                  textStyle = GoogleFonts.getFont(font);
                }
              } catch (_) {
                textStyle = const TextStyle(fontFamily: 'monospace');
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSel ? theme.colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isSel ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(font, style: textStyle.copyWith(color: theme.colorScheme.onSurface, fontSize: 14)),
                  trailing: isSel ? Icon(LucideIcons.check, color: theme.colorScheme.primary, size: 16) : null,
                  onTap: () {
                    onChanged(font);
                    Navigator.pop(ctx);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showSchemeDialog(BuildContext context, String current, ValueChanged<String> onChanged) {
    final theme = Theme.of(context);
    final schemes = [
      ['mandyRed', 'Mandy Red'],
      ['deepBlue', 'Deep Blue'],
      ['emerald', 'Emerald Green'],
      ['vesuviusBurn', 'Vesuvius Burn'],
      ['gold', 'Gold'],
      ['greyLaw', 'Grey Law'],
      ['ebonyClay', 'Ebony Clay'],
      ['outerSpace', 'Outer Space'],
      ['mallardGreen', 'Mallard Green'],
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(context)!.selectPalette, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: schemes.length,
            itemBuilder: (ctx, i) {
              final id = schemes[i][0];
              final name = schemes[i][1];
              final isSel = current == id;
              return ListTile(
                title: Text(name, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 14)),
                trailing: isSel ? Icon(LucideIcons.check, color: theme.colorScheme.primary, size: 16) : null,
                onTap: () { onChanged(id); Navigator.pop(ctx); },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showColorPickerDialog(BuildContext context, Color? current, ValueChanged<Color?> onChanged) {
    final theme = Theme.of(context);
    final colors = [
      Colors.blueAccent,
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.redAccent,
      Colors.purpleAccent,
      Colors.pinkAccent,
      Colors.amberAccent,
      Colors.tealAccent,
      const Color(0xFF6C63FF),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(context)!.accentColor, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: colors.map((c) => GestureDetector(
                onTap: () { onChanged(c); Navigator.pop(ctx); },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: current?.toARGB32() == c.toARGB32() ? theme.colorScheme.onSurface : Colors.transparent, width: 3)),
                ),
              )).toList(),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () { onChanged(null); Navigator.pop(ctx); },
              child: Text(AppLocalizations.of(context)!.resetToDefault, style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  void _showTerminalThemeDialog(BuildContext context, String current, ValueChanged<String> onChanged) {
    final theme = Theme.of(context);
    final themes = [
      ['ubuntu', 'Ubuntu Dark Purple', const Color(0xFF300A24)],
      ['dracula', 'Dracula', const Color(0xFF282A36)],
      ['monokai', 'Monokai', const Color(0xFF272822)],
      ['dark', 'Pure Dark', const Color(0xFF0D0F14)],
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppLocalizations.of(context)!.terminalTheme, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: themes.map((t) {
          final id = t[0] as String;
          final name = id == 'ubuntu'
              ? AppLocalizations.of(context)!.ubuntuDarkPurple
              : (id == 'dark' ? AppLocalizations.of(context)!.pureDark : t[1] as String);
          final color = t[2] as Color;
          final isSel = current == id;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSel ? theme.colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSel ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.08)),
            ),
            child: ListTile(
              dense: true,
              leading: Container(width: 24, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6), border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)))),
              title: Text(name, style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13)),
              trailing: isSel ? Icon(LucideIcons.check, color: theme.colorScheme.primary, size: 16) : null,
              onTap: () { onChanged(id); Navigator.pop(ctx); },
            ),
          );
        }).toList()),
      ),
    );
  }
}
