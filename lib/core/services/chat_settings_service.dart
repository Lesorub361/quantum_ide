import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatSettings {
  final double temperature;
  final int maxTokens;
  final int contextSize;
  final String systemPrompt;
  final bool useLocalModel;
  final String selectedModelId;

  // New settings for CPU/GPU/AUTO and Image generation
  final String liteRtPerformanceMode; // 'auto_fast', 'gpu_fast', 'cpu_safe'
  final bool imageGenForceCpu;
  final int imageGenGpuGuardMb;

  const ChatSettings({
    this.temperature = 0.7,
    this.maxTokens = 1024,
    this.contextSize = 4096,
    this.systemPrompt = 'You are a helpful assistant. Be concise and accurate.',
    this.useLocalModel = false,
    this.selectedModelId = '',
    this.liteRtPerformanceMode = 'auto_fast',
    this.imageGenForceCpu = false,
    this.imageGenGpuGuardMb = 2048,
  });

  ChatSettings copyWith({
    double? temperature,
    int? maxTokens,
    int? contextSize,
    String? systemPrompt,
    bool? useLocalModel,
    String? selectedModelId,
    String? liteRtPerformanceMode,
    bool? imageGenForceCpu,
    int? imageGenGpuGuardMb,
  }) {
    return ChatSettings(
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      contextSize: contextSize ?? this.contextSize,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      useLocalModel: useLocalModel ?? this.useLocalModel,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      liteRtPerformanceMode: liteRtPerformanceMode ?? this.liteRtPerformanceMode,
      imageGenForceCpu: imageGenForceCpu ?? this.imageGenForceCpu,
      imageGenGpuGuardMb: imageGenGpuGuardMb ?? this.imageGenGpuGuardMb,
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
  static const _keyLiteRtPerformanceMode = 'litert_performance_mode';
  static const _keyImageGenForceCpu = 'image_gen_force_cpu';
  static const _keyImageGenGpuGuardMb = 'image_gen_gpu_guard_mb';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ChatSettings(
      temperature: prefs.getDouble(_keyTemperature) ?? 0.7,
      maxTokens: prefs.getInt(_keyMaxTokens) ?? 1024,
      contextSize: prefs.getInt(_keyContextSize) ?? 4096,
      systemPrompt: prefs.getString(_keySystemPrompt) ?? 'You are a helpful assistant. Be concise and accurate.',
      useLocalModel: prefs.getBool(_keyUseLocalModel) ?? false,
      selectedModelId: prefs.getString(_keySelectedModelId) ?? '',
      liteRtPerformanceMode: prefs.getString(_keyLiteRtPerformanceMode) ?? 'auto_fast',
      imageGenForceCpu: prefs.getBool(_keyImageGenForceCpu) ?? false,
      imageGenGpuGuardMb: prefs.getInt(_keyImageGenGpuGuardMb) ?? 2048,
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

  Future<void> setLiteRtPerformanceMode(String mode) async {
    state = state.copyWith(liteRtPerformanceMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLiteRtPerformanceMode, mode);
  }

  Future<void> setImageGenForceCpu(bool forceCpu) async {
    state = state.copyWith(imageGenForceCpu: forceCpu);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyImageGenForceCpu, forceCpu);
  }

  Future<void> setImageGenGpuGuardMb(int sizeMb) async {
    state = state.copyWith(imageGenGpuGuardMb: sizeMb);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyImageGenGpuGuardMb, sizeMb);
  }
}

final chatSettingsProvider = StateNotifierProvider<ChatSettingsNotifier, ChatSettings>((ref) {
  return ChatSettingsNotifier();
});
