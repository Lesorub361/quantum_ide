import 'dart:async';
import 'package:flutter_code_crafter/code_crafter.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/talker_service.dart';

/// Bridges `flutter_code_crafter`'s [AiCompletion] models with QuantumIDE's
/// [SettingsState] to provide debounced inline AI code completion.
class CodeCrafterAiService {
  const CodeCrafterAiService._();

  /// Builds an [AiCompletion] configuration from the first available API key
  /// in [settings], or returns `null` if no provider is configured.
  static AiCompletion? buildCompletionConfig(SettingsState settings) {
    final Models? model = _resolveModel(settings);
    if (model == null) return null;
    return AiCompletion(
      model: model,
      completionType: CompletionType.mixed,
      debounceTime: 1000,
      enableCompletion: settings.aiAutoCompletion,
    );
  }

  static Models? _resolveModel(SettingsState settings) {
    if (settings.geminiApiKey.trim().isNotEmpty) {
      return Gemini(
        apiKey: settings.geminiApiKey.trim(),
        model: settings.geminiModel.isNotEmpty
            ? settings.geminiModel
            : 'gemini-2.5-flash',
      );
    }
    if (settings.deepseekApiKey.trim().isNotEmpty) {
      return DeepSeek(
        apiKey: settings.deepseekApiKey.trim(),
        model: 'deepseek-chat',
      );
    }
    if (settings.openaiApiKey.trim().isNotEmpty) {
      return OpenAI(
        apiKey: settings.openaiApiKey.trim(),
        model: 'gpt-4o-mini',
      );
    }
    if (settings.anthropicApiKey.trim().isNotEmpty) {
      return Claude(
        apiKey: settings.anthropicApiKey.trim(),
        model: 'claude-3-5-haiku-latest',
      );
    }
    if (settings.openrouterApiKey.trim().isNotEmpty) {
      return OpenRouter(
        apiKey: settings.openrouterApiKey.trim(),
        model: 'qwen/qwen-2.5-coder-32b-instruct',
      );
    }
    if (settings.groqApiKey.trim().isNotEmpty) {
      return Gorq(
        apiKey: settings.groqApiKey.trim(),
        model: 'llama-3.3-70b-versatile',
      );
    }
    if (settings.xaiApiKey.trim().isNotEmpty) {
      return Grok(
        apiKey: settings.xaiApiKey.trim(),
        model: 'grok-2-latest',
      );
    }
    if (settings.mistralApiKey.trim().isNotEmpty) {
      return CustomModel(
        url: 'https://api.mistral.ai/v1/chat/completions',
        customHeaders: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.mistralApiKey.trim()}',
        },
        requestBuilder: (code, instruction) => {
          'model': 'codestral-latest',
          'messages': [
            {'role': 'system', 'content': instruction},
            {'role': 'user', 'content': code},
          ],
          'temperature': 0.2,
          'max_tokens': 256,
        },
        customParser: (res) => res['choices'][0]['message']['content'] as String,
      );
    }
    if (settings.customApiBaseUrl.trim().isNotEmpty &&
        settings.customApiModel.trim().isNotEmpty) {
      final base = settings.customApiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final key = settings.customApiKey.trim();
      return CustomModel(
        url: '$base/chat/completions',
        customHeaders: {
          'Content-Type': 'application/json',
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
        requestBuilder: (code, instruction) => {
          'model': settings.customApiModel.trim(),
          'messages': [
            {'role': 'system', 'content': instruction},
            {'role': 'user', 'content': code},
          ],
          'temperature': 0.2,
          'max_tokens': 256,
        },
        customParser: (res) => res['choices'][0]['message']['content'] as String,
      );
    }
    return null;
  }

  /// Requests an inline completion at [cursorOffset] within [text].
  /// Returns `null` if disabled, no provider is configured, or request fails.
  static Future<String?> completeAtCursor({
    required String text,
    required int cursorOffset,
    required SettingsState settings,
    String? filePath,
  }) async {
    final config = buildCompletionConfig(settings);
    if (config == null || !config.enableCompletion) return null;

    final safeOffset = cursorOffset.clamp(0, text.length);
    final start = (safeOffset - 2500).clamp(0, safeOffset);
    final end = (safeOffset + 1000).clamp(safeOffset, text.length);

    final prefix = text.substring(start, safeOffset);
    final suffix = text.substring(safeOffset, end);
    final header = filePath != null ? '// File: $filePath\n' : '';
    final promptCode = '$header$prefix<|CURSOR|>$suffix';

    try {
      final suggestion = await config.model
          .completionResponse(promptCode)
          .timeout(const Duration(seconds: 12));
      final trimmed = suggestion.trimRight();
      if (trimmed.isEmpty) return null;
      return trimmed;
    } catch (e) {
      TalkerService.warning('[CodeCrafterAI] Inline completion skipped: $e');
      return null;
    }
  }
}
