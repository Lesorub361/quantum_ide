import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  final ThemeMode themeMode;
  final double fontSize;
  final bool autoCompletion;
  final bool aiAutoCompletion;
  final bool wordWrap;
  final bool lineNumbers;
  final bool minimap;
  final bool autoSave;
  final double terminalFontSize;
  final String terminalTheme;
  final bool hapticFeedback;
  final bool showHiddenFiles;
  final String geminiModel;
  final String flexScheme;
  final int? customPrimaryColor;
  final String editorFontFamily;
  final bool editorFontLigatures;
  final double glassmorphismOpacity;
  final double glassmorphismBlur;
  final String hotkeysJson;
  final bool isInitialized;

  SettingsState({
    this.themeMode = ThemeMode.dark,
    this.fontSize = 14.0,
    this.autoCompletion = true,
    this.aiAutoCompletion = true,
    this.wordWrap = false,
    this.lineNumbers = true,
    this.minimap = true,
    this.autoSave = true,
    this.terminalFontSize = 13.0,
    this.terminalTheme = 'ubuntu',
    this.hapticFeedback = true,
    this.showHiddenFiles = false,
    this.geminiModel = 'gemini-2.5-flash',
    this.flexScheme = 'mandyRed',
    this.customPrimaryColor,
    this.editorFontFamily = 'Fira Code',
    this.editorFontLigatures = true,
    this.glassmorphismOpacity = 0.15,
    this.glassmorphismBlur = 16.0,
    this.hotkeysJson = '{}',
    this.isInitialized = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    double? fontSize,
    bool? autoCompletion,
    bool? aiAutoCompletion,
    bool? wordWrap,
    bool? lineNumbers,
    bool? minimap,
    bool? autoSave,
    double? terminalFontSize,
    String? terminalTheme,
    bool? hapticFeedback,
    bool? showHiddenFiles,
    String? geminiModel,
    String? flexScheme,
    int? customPrimaryColor,
    bool clearCustomColor = false,
    String? editorFontFamily,
    bool? editorFontLigatures,
    double? glassmorphismOpacity,
    double? glassmorphismBlur,
    String? hotkeysJson,
    bool? isInitialized,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      autoCompletion: autoCompletion ?? this.autoCompletion,
      aiAutoCompletion: aiAutoCompletion ?? this.aiAutoCompletion,
      wordWrap: wordWrap ?? this.wordWrap,
      lineNumbers: lineNumbers ?? this.lineNumbers,
      minimap: minimap ?? this.minimap,
      autoSave: autoSave ?? this.autoSave,
      terminalFontSize: terminalFontSize ?? this.terminalFontSize,
      terminalTheme: terminalTheme ?? this.terminalTheme,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      geminiModel: geminiModel ?? this.geminiModel,
      flexScheme: flexScheme ?? this.flexScheme,
      customPrimaryColor: clearCustomColor ? null : (customPrimaryColor ?? this.customPrimaryColor),
      editorFontFamily: editorFontFamily ?? this.editorFontFamily,
      editorFontLigatures: editorFontLigatures ?? this.editorFontLigatures,
      glassmorphismOpacity: glassmorphismOpacity ?? this.glassmorphismOpacity,
      glassmorphismBlur: glassmorphismBlur ?? this.glassmorphismBlur,
      hotkeysJson: hotkeysJson ?? this.hotkeysJson,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

class SettingsService extends StateNotifier<SettingsState> {
  SettingsService() : super(SettingsState()) {
    _loadSettings();
  }

  static const _keyTheme = 'settings_theme';
  static const _keyFontSize = 'settings_font_size';
  static const _keyAutoCompletion = 'settings_auto_completion';
  static const _keyAiAutoCompletion = 'settings_ai_auto_completion';
  static const _keyWordWrap = 'settings_word_wrap';
  static const _keyLineNumbers = 'settings_line_numbers';
  static const _keyMinimap = 'settings_minimap';
  static const _keyAutoSave = 'settings_auto_save';
  static const _keyTerminalFontSize = 'settings_terminal_font_size';
  static const _keyTerminalTheme = 'settings_terminal_theme';
  static const _keyHapticFeedback = 'settings_haptic_feedback';
  static const _keyShowHiddenFiles = 'settings_show_hidden_files';
  static const _keyGeminiModel = 'settings_gemini_model';
  static const _keyFlexScheme = 'settings_flex_scheme';
  static const _keyCustomColor = 'settings_custom_color';
  static const _keyEditorFontFamily = 'settings_editor_font_family';
  static const _keyEditorFontLigatures = 'settings_editor_font_ligatures';
  static const _keyGlassmorphismOpacity = 'settings_glassmorphism_opacity';
  static const _keyGlassmorphismBlur = 'settings_glassmorphism_blur';
  static const _keyHotkeys = 'settings_hotkeys';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      themeMode: ThemeMode.values[prefs.getInt(_keyTheme) ?? ThemeMode.dark.index],
      fontSize: prefs.getDouble(_keyFontSize) ?? 14.0,
      autoCompletion: prefs.getBool(_keyAutoCompletion) ?? true,
      aiAutoCompletion: prefs.getBool(_keyAiAutoCompletion) ?? true,
      wordWrap: prefs.getBool(_keyWordWrap) ?? false,
      lineNumbers: prefs.getBool(_keyLineNumbers) ?? true,
      minimap: prefs.getBool(_keyMinimap) ?? true,
      autoSave: prefs.getBool(_keyAutoSave) ?? true,
      terminalFontSize: prefs.getDouble(_keyTerminalFontSize) ?? 13.0,
      terminalTheme: prefs.getString(_keyTerminalTheme) ?? 'ubuntu',
      hapticFeedback: prefs.getBool(_keyHapticFeedback) ?? true,
      showHiddenFiles: prefs.getBool(_keyShowHiddenFiles) ?? false,
      geminiModel: (prefs.getString(_keyGeminiModel) == 'gemini-2.0-flash'
          ? 'gemini-2.5-flash'
          : (prefs.getString(_keyGeminiModel) ?? 'gemini-2.5-flash')),
      flexScheme: prefs.getString(_keyFlexScheme) ?? 'mandyRed',
      customPrimaryColor: prefs.getInt(_keyCustomColor),
      editorFontFamily: prefs.getString(_keyEditorFontFamily) ?? 'Fira Code',
      editorFontLigatures: prefs.getBool(_keyEditorFontLigatures) ?? true,
      glassmorphismOpacity: prefs.getDouble(_keyGlassmorphismOpacity) ?? 0.15,
      glassmorphismBlur: prefs.getDouble(_keyGlassmorphismBlur) ?? 16.0,
      hotkeysJson: prefs.getString(_keyHotkeys) ?? '{}',
      isInitialized: true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, mode.index);
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, size);
  }

  Future<void> setAutoCompletion(bool v) async {
    state = state.copyWith(autoCompletion: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCompletion, v);
  }

  Future<void> setAiAutoCompletion(bool v) async {
    state = state.copyWith(aiAutoCompletion: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAiAutoCompletion, v);
  }

  Future<void> setWordWrap(bool v) async {
    state = state.copyWith(wordWrap: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWordWrap, v);
  }

  Future<void> setLineNumbers(bool v) async {
    state = state.copyWith(lineNumbers: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLineNumbers, v);
  }

  Future<void> setMinimap(bool v) async {
    state = state.copyWith(minimap: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMinimap, v);
  }

  Future<void> setAutoSave(bool v) async {
    state = state.copyWith(autoSave: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSave, v);
  }

  Future<void> setTerminalFontSize(double size) async {
    state = state.copyWith(terminalFontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTerminalFontSize, size);
  }

  Future<void> setTerminalTheme(String theme) async {
    state = state.copyWith(terminalTheme: theme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTerminalTheme, theme);
  }

  Future<void> setHapticFeedback(bool v) async {
    state = state.copyWith(hapticFeedback: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHapticFeedback, v);
  }

  Future<void> setShowHiddenFiles(bool v) async {
    state = state.copyWith(showHiddenFiles: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowHiddenFiles, v);
  }

  Future<void> setGeminiModel(String model) async {
    state = state.copyWith(geminiModel: model);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGeminiModel, model);
  }

  Future<void> setFlexScheme(String scheme) async {
    state = state.copyWith(flexScheme: scheme, clearCustomColor: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFlexScheme, scheme);
    await prefs.remove(_keyCustomColor);
  }

  Future<void> setCustomPrimaryColor(Color? color) async {
    if (color == null) {
      state = state.copyWith(clearCustomColor: true);
    } else {
      state = state.copyWith(customPrimaryColor: color.toARGB32());
    }
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt(_keyCustomColor, color.toARGB32());
    } else {
      await prefs.remove(_keyCustomColor);
    }
  }

  Future<void> setEditorFontFamily(String family) async {
    state = state.copyWith(editorFontFamily: family);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEditorFontFamily, family);
  }

  Future<void> setEditorFontLigatures(bool v) async {
    state = state.copyWith(editorFontLigatures: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEditorFontLigatures, v);
  }

  Future<void> setGlassmorphismOpacity(double v) async {
    state = state.copyWith(glassmorphismOpacity: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyGlassmorphismOpacity, v);
  }

  Future<void> setGlassmorphismBlur(double v) async {
    state = state.copyWith(glassmorphismBlur: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyGlassmorphismBlur, v);
  }

  Future<void> setHotkeysJson(String json) async {
    state = state.copyWith(hotkeysJson: json);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHotkeys, json);
  }
}

final settingsProvider = StateNotifierProvider<SettingsService, SettingsState>((ref) {
  return SettingsService();
});
