import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

enum AiProvider {
  deepseek('DeepSeek', 'deepseek-chat'),
  deepseekR1('DeepSeek R1', 'deepseek-reasoner'),
  openrouterClaude('Claude 3.5 Sonnet', 'anthropic/claude-3.5-sonnet'),
  openrouterGpt4o('GPT-4o (OpenRouter)', 'openai/gpt-4o'),
  openrouterQwen('Qwen 2.5 Coder 32B', 'qwen/qwen-2.5-coder-32b-instruct'),
  openrouterGemini('Gemini 2.0 Flash', 'google/gemini-2.0-flash-001'),
  openai('OpenAI GPT-4o', 'gpt-4o'),
  anthropic('Anthropic Claude', 'claude-3-5-sonnet-20241022'),
  custom('Локальный / Custom API', 'default');

  final String label;
  final String defaultModel;
  const AiProvider(this.label, this.defaultModel);
}

enum MessageRole { user, assistant, system }

class AgentAction {
  final String type; // 'write_file', 'read_file', 'run_command', 'diff'
  final String path;
  final String? content;
  final String? command;
  bool isExecuted;

  AgentAction({
    required this.type,
    required this.path,
    this.content,
    this.command,
    this.isExecuted = false,
  });
}

class ChatMessage {
  final String id;
  final MessageRole role;
  String text;
  String? thinking;
  bool isThinking;
  bool isStreaming;
  final DateTime timestamp;
  final List<AgentAction> actions;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.thinking,
    this.isThinking = false,
    this.isStreaming = false,
    required this.timestamp,
    List<AgentAction>? actions,
  }) : actions = actions ?? [];
}

class QuantumAiAgentService extends ChangeNotifier {
  final RuntimeService _runtime;
  final SettingsState Function() _getSettings;
  final String? Function() _getWorkspacePath;

  QuantumAiAgentService(this._runtime, this._getSettings, this._getWorkspacePath) {
    // Умный повтор сетевых запросов при сбоях связи (dio_smart_retry)
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        logPrint: (msg) => debugPrint('[QuantumAI-Retry] $msg'),
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
        ],
      ),
    );
    _initDefaultGreeting();
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
  ));

  CancelToken? _currentCancelToken;
  AiProvider _selectedProvider = AiProvider.deepseek;
  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  String _statusMessage = 'Готов к работе';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  String get statusMessage => _statusMessage;
  AiProvider get selectedProvider => _selectedProvider;

  void selectProvider(AiProvider provider) {
    _selectedProvider = provider;
    notifyListeners();
  }

  void clearChat() {
    _messages.clear();
    _initDefaultGreeting();
    notifyListeners();
  }

  void _initDefaultGreeting() {
    _messages.add(
      ChatMessage(
        id: 'msg_welcome',
        role: MessageRole.assistant,
        text: 'Привет! Я встроенный Quantum AI Агент. Я подключен напрямую к твоему проекту, могу анализировать файлы, писать код, находить ошибки и предлагать готовые изменения с кнопкой применения прямо в редактор.\n\nЧем могу помочь?',
        timestamp: DateTime.now(),
      ),
    );
  }

  void stopGeneration() {
    _currentCancelToken?.cancel('Пользователь остановил генерацию');
    _currentCancelToken = null;
    _isGenerating = false;
    _statusMessage = 'Остановлено';
    if (_messages.isNotEmpty && _messages.last.isStreaming) {
      _messages.last.isStreaming = false;
      _messages.last.isThinking = false;
    }
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isGenerating) return;

    // Проверка наличия сети через connectivity_plus
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.isNotEmpty &&
          connectivityResults.every((r) => r == ConnectivityResult.none)) {
        _statusMessage = 'Ошибка: нет подключения к сети';
        _messages.add(
          ChatMessage(
            id: 'msg_offline_${DateTime.now().millisecondsSinceEpoch}',
            role: MessageRole.assistant,
            text: '⚠️ Нет активного подключения к интернету. Проверьте соединение с Wi-Fi или мобильной сетью для отправки запросов к ИИ.',
            timestamp: DateTime.now(),
          ),
        );
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[QuantumAI] Connectivity check error: $e');
    }

    final userMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      text: query,
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);

    final assistantMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch + 1}',
      role: MessageRole.assistant,
      text: '',
      isStreaming: true,
      timestamp: DateTime.now(),
    );
    _messages.add(assistantMsg);
    _isGenerating = true;
    _statusMessage = 'Генерация ответа...';
    notifyListeners();

    _currentCancelToken = CancelToken();

    try {
      final settings = _getSettings();
      final wsPath = _getWorkspacePath();
      final systemPrompt = _buildSystemPrompt(wsPath);

      // Формируем историю сообщений
      final apiMessages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
      ];

      for (final m in _messages.take(_messages.length - 1)) {
        if (m.role == MessageRole.user) {
          apiMessages.add({'role': 'user', 'content': m.text});
        } else if (m.role == MessageRole.assistant) {
          apiMessages.add({'role': 'assistant', 'content': m.text});
        }
      }

      await _streamCompletion(
        messages: apiMessages,
        settings: settings,
        targetMsg: assistantMsg,
      );

      // После завершения парсим действия (action tags)
      _parseActions(assistantMsg);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        _statusMessage = 'Остановлено пользователем';
      } else {
        assistantMsg.text += '\n\n⚠️ **Ошибка генерации:** $e';
        _statusMessage = 'Ошибка: $e';
      }
    } finally {
      assistantMsg.isStreaming = false;
      assistantMsg.isThinking = false;
      _isGenerating = false;
      _currentCancelToken = null;
      notifyListeners();
    }
  }

  String _buildSystemPrompt(String? wsPath) {
    return '''Ты — ведущий ИИ-разработчик и ассистент Quantum IDE.
Ты работаешь непосредственно с проектом пользователя.
Текущая рабочая директория: ${wsPath ?? 'корень проекта'}.

ПРАВИЛА И ИНСТРУМЕНТЫ:
1. Пиши чистый, современный, структурированный код.
2. Когда ты создаёшь или модифицируешь файл, оборачивай код в специальный блок действия:
<action type="write_file" path="относительный_путь/к/файлу">
содержимое файла
</action>

3. Для вывода команд терминала:
<action type="run_command">
команда_bash
</action>

4. Объясняй изменения кратко и по делу. Поддерживай формулы KaTeX и Markdown.
''';
  }

  Future<void> _streamCompletion({
    required List<Map<String, String>> messages,
    required SettingsState settings,
    required ChatMessage targetMsg,
  }) async {
    String endpoint;
    String apiKey;
    String model;

    switch (_selectedProvider) {
      case AiProvider.deepseek:
        endpoint = 'https://api.deepseek.com/chat/completions';
        apiKey = settings.deepseekApiKey;
        model = 'deepseek-chat';
        break;
      case AiProvider.deepseekR1:
        endpoint = 'https://api.deepseek.com/chat/completions';
        apiKey = settings.deepseekApiKey;
        model = 'deepseek-reasoner';
        break;
      case AiProvider.openrouterClaude:
      case AiProvider.openrouterGpt4o:
      case AiProvider.openrouterQwen:
      case AiProvider.openrouterGemini:
        endpoint = 'https://openrouter.ai/api/v1/chat/completions';
        apiKey = settings.openrouterApiKey;
        model = _selectedProvider.defaultModel;
        break;
      case AiProvider.openai:
        endpoint = 'https://api.openai.com/v1/chat/completions';
        apiKey = settings.openaiApiKey;
        model = 'gpt-4o';
        break;
      case AiProvider.anthropic:
        endpoint = 'https://api.anthropic.com/v1/messages';
        apiKey = settings.anthropicApiKey;
        model = 'claude-3-5-sonnet-20241022';
        break;
      case AiProvider.custom:
        endpoint = 'http://127.0.0.1:11434/v1/chat/completions';
        apiKey = settings.deepseekApiKey;
        model = 'default';
        break;
    }

    if (apiKey.isEmpty && _selectedProvider != AiProvider.custom) {
      throw Exception('Не указан API ключ для ${_selectedProvider.label}. Нажмите на иконку настроек ⚙️ вверху, чтобы ввести ключ.');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    if (_selectedProvider.label.contains('OpenRouter')) {
      headers['HTTP-Referer'] = 'https://github.com/Lesorub361/quantum_ide';
      headers['X-Title'] = 'Quantum IDE';
    }

    final body = {
      'model': model,
      'messages': messages,
      'stream': true,
      'temperature': 0.3,
    };

    final response = await _dio.post<ResponseBody>(
      endpoint,
      data: jsonEncode(body),
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
      ),
      cancelToken: _currentCancelToken,
    );

    final stream = response.data?.stream;
    if (stream == null) throw Exception('Пустой поток ответа от сервера');

    final buffer = StringBuffer();
    final thinkBuffer = StringBuffer();
    bool insideThink = false;

    await for (final chunk in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final line = chunk.trim();
      if (line.isEmpty || line == 'data: [DONE]') continue;
      if (!line.startsWith('data: ')) continue;

      final jsonStr = line.substring(6).trim();
      try {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final choices = decoded['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        if (delta == null) continue;

        // 1. Проверяем reasoning_content (DeepSeek R1 / o3-mini)
        final reasoning = delta['reasoning_content'] as String?;
        if (reasoning != null && reasoning.isNotEmpty) {
          thinkBuffer.write(reasoning);
          targetMsg.thinking = thinkBuffer.toString();
          targetMsg.isThinking = true;
          notifyListeners();
          continue;
        }

        // 2. Обычный контент
        final content = delta['content'] as String?;
        if (content != null && content.isNotEmpty) {
          // Проверяем теги <think> и </think> в обычном контенте
          if (content.contains('<think>')) {
            insideThink = true;
            targetMsg.isThinking = true;
          }

          if (insideThink) {
            if (content.contains('</think>')) {
              insideThink = false;
              targetMsg.isThinking = false;
              final parts = content.split('</think>');
              thinkBuffer.write(parts[0].replaceAll('<think>', ''));
              targetMsg.thinking = thinkBuffer.toString();
              if (parts.length > 1) {
                buffer.write(parts[1]);
                targetMsg.text = buffer.toString();
              }
            } else {
              thinkBuffer.write(content.replaceAll('<think>', ''));
              targetMsg.thinking = thinkBuffer.toString();
            }
          } else {
            buffer.write(content);
            targetMsg.text = buffer.toString();
          }
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  void _parseActions(ChatMessage msg) {
    final text = msg.text;
    final writeRegExp = RegExp(r'<action\s+type="write_file"\s+path="([^"]+)">([\s\S]*?)<\/action>');
    final matches = writeRegExp.allMatches(text);

    for (final match in matches) {
      final path = match.group(1)?.trim() ?? '';
      final content = match.group(2)?.trim() ?? '';
      if (path.isNotEmpty) {
        msg.actions.add(
          AgentAction(
            type: 'write_file',
            path: path,
            content: content,
          ),
        );
      }
    }

    final cmdRegExp = RegExp(r'<action\s+type="run_command">([\s\S]*?)<\/action>');
    final cmdMatches = cmdRegExp.allMatches(text);
    for (final match in cmdMatches) {
      final cmd = match.group(1)?.trim() ?? '';
      if (cmd.isNotEmpty) {
        msg.actions.add(
          AgentAction(
            type: 'run_command',
            path: '',
            command: cmd,
          ),
        );
      }
    }
    notifyListeners();
  }

  /// Применяет действие агента (записывает файл в проект)
  Future<bool> executeWriteAction(AgentAction action) async {
    final ws = _getWorkspacePath();
    if (ws == null || action.content == null) return false;

    try {
      final fullPath = p.isAbsolute(action.path) ? action.path : p.join(ws, action.path);
      final file = File(fullPath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(action.content!);
      action.isExecuted = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[QuantumAiAgent] Write error: $e');
      return false;
    }
  }

  /// Запускает команду терминала
  Future<void> executeCommandAction(AgentAction action) async {
    final ws = _getWorkspacePath();
    if (action.command == null) return;
    try {
      await _runtime.runCommand(action.command!, workingDirectory: ws);
      action.isExecuted = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[QuantumAiAgent] Command error: $e');
    }
  }
}

final quantumAiAgentServiceProvider = ChangeNotifierProvider<QuantumAiAgentService>((ref) {
  final runtime = ref.watch(runtimeServiceProvider);
  final settings = () => ref.read(settingsProvider);
  final ws = () => ref.read(workspaceProvider).currentPath;
  return QuantumAiAgentService(runtime, settings, ws);
});
