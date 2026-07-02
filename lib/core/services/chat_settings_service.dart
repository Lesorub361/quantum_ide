import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatSettings {
  final double temperature;
  final int maxTokens;
  final int contextSize;
  final String systemPrompt;
  final bool useLocalModel;
  final String selectedModelId;

  const ChatSettings({
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.contextSize = 2048,
    this.systemPrompt = 'You are a helpful assistant. Be concise and accurate.',
    this.useLocalModel = false,
    this.selectedModelId = '',
  });

  ChatSettings copyWith({
    double? temperature,
    int? maxTokens,
    int? contextSize,
    String? systemPrompt,
    bool? useLocalModel,
    String? selectedModelId,
  }) {
    return ChatSettings(
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      contextSize: contextSize ?? this.contextSize,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      useLocalModel: useLocalModel ?? this.useLocalModel,
      selectedModelId: selectedModelId ?? this.selectedModelId,
    );
  }
}

class ChatSettingsNotifier extends StateNotifier<ChatSettings> {
  ChatSettingsNotifier() : super(const ChatSettings()) {
    _load();
  }

  static const _keyTemperature = 'chat_temperature';
  static const _keyMaxTokens = 'chat_max_tokens';
  static const _keyContextSize = 'chat_context_size';
  static const _keySystemPrompt = 'chat_system_prompt';
  static const _keyUseLocalModel = 'chat_use_local_model';
  static const _keySelectedModelId = 'chat_selected_model_id';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ChatSettings(
      temperature: prefs.getDouble(_keyTemperature) ?? 0.7,
      maxTokens: prefs.getInt(_keyMaxTokens) ?? 1024,
      contextSize: prefs.getInt(_keyContextSize) ?? 2048,
      systemPrompt: prefs.getString(_keySystemPrompt) ?? 'You are a helpful assistant. Be concise and accurate.',
      useLocalModel: prefs.getBool(_keyUseLocalModel) ?? false,
      selectedModelId: prefs.getString(_keySelectedModelId) ?? '',
    );
  }

  Future<void> setTemperature(double value) async {
    state = state.copyWith(temperature: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTemperature, value);
  }

  Future<void> setMaxTokens(int value) async {
    state = state.copyWith(maxTokens: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxTokens, value);
  }

  Future<void> setContextSize(int value) async {
    state = state.copyWith(contextSize: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyContextSize, value);
  }

  Future<void> setSystemPrompt(String value) async {
    state = state.copyWith(systemPrompt: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySystemPrompt, value);
  }

  Future<void> setUseLocalModel(bool value) async {
    state = state.copyWith(useLocalModel: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseLocalModel, value);
  }

  Future<void> setSelectedModelId(String value) async {
    state = state.copyWith(selectedModelId: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedModelId, value);
  }
}

final chatSettingsProvider = StateNotifierProvider<ChatSettingsNotifier, ChatSettings>((ref) {
  return ChatSettingsNotifier();
});
