import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/models/code_diagnostic.dart';
import 'package:quantum_ide/core/services/fast_syntax_engine.dart';
import 'package:quantum_ide/core/services/live_telemetry_service.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/agent/domain/quantum_agent_models.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/terminal/presentation/notifiers/dedicated_terminal_notifier.dart';

final quantumAgentProvider = StateNotifierProvider<QuantumAgentNotifier, QuantumAgentState>((ref) {
  return QuantumAgentNotifier(ref);
});

class QuantumAgentNotifier extends StateNotifier<QuantumAgentState> {
  final Ref _ref;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(seconds: 90),
  ));
  bool _cancelRequested = false;
  Timer? _outboxTimer;
  String _lastOutboxId = '';

  static const String _prefProvider = 'q_agent_provider_v2';
  static const String _prefModel = 'q_agent_model_v2';
  static const String _prefKeyPrefix = 'q_agent_key_';
  static const String _sharedDir = '/storage/emulated/0/QuantumIDE';

  QuantumAgentNotifier(this._ref) : super(const QuantumAgentState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString(_prefProvider) ?? 'antigravity_doctor';
    final preset = QuantumAgentProviderPreset.byId(providerId);
    final savedModel = prefs.getString(_prefModel);
    final modelId = (savedModel != null && preset.models.contains(savedModel))
        ? savedModel
        : preset.models.first;
    final apiKey = prefs.getString('$_prefKeyPrefix$providerId') ?? '';

    state = state.copyWith(
      providerId: providerId,
      modelId: modelId,
      apiKey: apiKey,
      messages: [
        AgentChatMessage(
          id: 'welcome',
          role: 'assistant',
          content: 'Привет! Я **Quantum Agent** — автономный ИИ-разработчик в стиле Antigravity / Cline.\n\n'
              'Я умею:\n'
              '• **Читать и редактировать файлы** проекта с мгновенной синхронизацией в редакторе и `/storage/emulated/0/QuantumIDE`\n'
              '• **Анализировать и чинить ошибки сборки APK** в реальном времени\n'
              '• **Запускать команды в терминале** (`flutter pub get`, `flutter build apk`, `git`)\n\n'
              'Выберите быстрое действие ниже или напишите любую задачу!',
          timestamp: DateTime.now(),
        ),
      ],
    );

    _startOutboxWatcher();
  }

  void _startOutboxWatcher() {
    _outboxTimer?.cancel();
    _outboxTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final outboxFile = File(p.join(_sharedDir, 'agent_outbox.json'));
        if (!await outboxFile.exists()) return;
        final raw = await outboxFile.readAsString();
        if (raw.trim().isEmpty) return;
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final msgId = data['id']?.toString() ?? '';
        if (msgId.isEmpty || msgId == _lastOutboxId) return;
        _lastOutboxId = msgId;

        final reply = data['content']?.toString() ?? '';
        if (reply.isNotEmpty) {
          await _ref.read(editorProvider.notifier).syncExternalNow(reloadAllTabs: true);
          final msg = AgentChatMessage(
            id: msgId,
            role: 'assistant',
            content: reply,
            thinking: data['thinking']?.toString(),
            modifiedFiles: (data['modifiedFiles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
            timestamp: DateTime.now(),
          );
          state = state.copyWith(messages: [...state.messages, msg]);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _outboxTimer?.cancel();
    super.dispose();
  }

  Future<void> updateConfig({
    required String providerId,
    required String modelId,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProvider, providerId);
    await prefs.setString(_prefModel, modelId);
    await prefs.setString('$_prefKeyPrefix$providerId', apiKey.trim());
    state = state.copyWith(
      providerId: providerId,
      modelId: modelId,
      apiKey: apiKey.trim(),
    );
  }

  Future<String> getSavedKeyForProvider(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefKeyPrefix$providerId') ?? '';
  }

  void clearHistory() {
    state = state.copyWith(
      messages: [
        AgentChatMessage(
          id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: 'История очищена. Готов к работе над проектом!',
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  void stopGeneration() {
    _cancelRequested = true;
    state = state.copyWith(isWorking: false, statusText: 'Остановлено');
  }

  /// Быстрая генерация текста (например, для сообщения коммита в GitPanel)
  Future<String> quickComplete(String prompt) async {
    if (state.apiKey.isEmpty || state.providerId == 'antigravity_doctor') {
      return '';
    }
    try {
      final preset = QuantumAgentProviderPreset.byId(state.providerId);
      final res = await _dio.post(
        preset.baseUrl,
        options: Options(headers: {
          'Authorization': 'Bearer ${state.apiKey}',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': state.modelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.2,
          'max_tokens': 200,
        },
      );
      final choices = res.data['choices'] as List?;
      if (choices != null && choices.isNotEmpty) {
        return choices.first['message']?['content']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<void> sendUserMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || state.isWorking) return;

    _cancelRequested = false;
    final userMsg = AgentChatMessage(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: clean,
      timestamp: DateTime.now(),
    );

    final assistantMsgId = 'a_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = AgentChatMessage(
      id: assistantMsgId,
      role: 'assistant',
      content: '',
      thinking: 'Анализирую задачу и рабочее пространство...',
      isStreaming: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, placeholder],
      isWorking: true,
      statusText: 'Анализ проекта...',
    );

    // Save request to /storage/emulated/0/QuantumIDE/agent_inbox.json for Antigravity bridge
    _writeBridgeInbox(clean);

    try {
      final preset = QuantumAgentProviderPreset.byId(state.providerId);
      if (preset.id == 'antigravity_doctor' || state.apiKey.trim().isEmpty) {
        await _runAutonomousDoctorAndBridge(assistantMsgId, clean);
      } else {
        await _runLlmAgentLoop(assistantMsgId, clean, preset);
      }
    } catch (e) {
      _updateAssistantMessage(
        assistantMsgId,
        content: '⚠️ Произошла ошибка при выполнении: `$e`\n\nЗапускаю встроенный локальный Авто-Доктор...',
        isStreaming: false,
      );
      await _runAutonomousDoctorAndBridge(assistantMsgId, clean, appendMode: true);
    } finally {
      state = state.copyWith(isWorking: false, statusText: '');
    }
  }

  Future<void> _writeBridgeInbox(String prompt) async {
    try {
      final ws = _ref.read(workspaceProvider).currentPath;
      final inbox = File(p.join(_sharedDir, 'agent_inbox.json'));
      await inbox.parent.create(recursive: true);
      final payload = {
        'id': 'req_${DateTime.now().millisecondsSinceEpoch}',
        'timestamp': DateTime.now().toIso8601String(),
        'workspace': ws,
        'prompt': prompt,
        'buildStatus': LiveTelemetryService.instance.currentBuildStatus,
      };
      await inbox.writeAsString(const JsonEncoder.withIndent('  ').convert(payload), flush: true);
      LiveTelemetryService.instance.logEvent('Agent request: $prompt');
    } catch (_) {}
  }

  void _updateAssistantMessage(
    String id, {
    String? content,
    String? thinking,
    List<AgentToolCall>? toolCalls,
    List<String>? modifiedFiles,
    bool? isStreaming,
  }) {
    final updated = state.messages.map((m) {
      if (m.id != id) return m;
      return m.copyWith(
        content: content ?? m.content,
        thinking: thinking ?? m.thinking,
        toolCalls: toolCalls ?? m.toolCalls,
        modifiedFiles: modifiedFiles ?? m.modifiedFiles,
        isStreaming: isStreaming ?? m.isStreaming,
      );
    }).toList();
    state = state.copyWith(messages: updated);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. ВСТРОЕННЫЙ АВТОНОМНЫЙ ДОКТОР И МОСТ ANTIGRAVITY (РАБОТАЕТ БЕЗ API КЛЮЧА)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _runAutonomousDoctorAndBridge(
    String msgId,
    String userPrompt, {
    bool appendMode = false,
  }) async {
    final ws = _ref.read(workspaceProvider).currentPath;
    if (ws == null || ws.isEmpty) {
      _updateAssistantMessage(
        msgId,
        content: '❌ Проект сейчас не открыт. Откройте папку проекта в проводнике, чтобы я мог работать с кодом.',
        thinking: null,
        isStreaming: false,
      );
      return;
    }

    final toolCalls = <AgentToolCall>[];
    final modified = <String>[];
    final lower = userPrompt.toLowerCase();

    void addOrUpdateTool(AgentToolCall call) {
      final idx = toolCalls.indexWhere((t) => t.id == call.id);
      if (idx >= 0) {
        toolCalls[idx] = call;
      } else {
        toolCalls.add(call);
      }
      _updateAssistantMessage(msgId, toolCalls: List.of(toolCalls));
    }

    // Шаг 1: Мгновенная синхронизация внешнего хранилища /storage/emulated/0/QuantumIDE/<project>
    state = state.copyWith(statusText: 'Синхронизация файлов проекта...');
    final syncCall = AgentToolCall(
      id: 'tc_sync',
      toolName: 'sync_workspace',
      title: 'Двусторонняя синхронизация с /storage/emulated/0/QuantumIDE/${p.basename(ws)}',
      arguments: {'workspace': ws},
      isRunning: true,
    );
    addOrUpdateTool(syncCall);

    final syncedFiles = await _ref.read(projectServiceProvider.notifier).syncExternalIntoWorkspace(ws);
    await _ref.read(editorProvider.notifier).syncExternalNow(reloadAllTabs: true);
    modified.addAll(syncedFiles);

    addOrUpdateTool(syncCall.copyWith(
      isRunning: false,
      result: syncedFiles.isEmpty
          ? 'Все файлы актуальны, пустых (0 байт) файлов не обнаружено.'
          : 'Обновлено/восстановлено файлов: ${syncedFiles.length} (${syncedFiles.join(", ")})',
    ));

    // Если пользователь просит запустить сборку APK
    if (lower.contains('собрать apk') || lower.contains('сборка apk') || lower == 'build apk') {
      final buildCall = AgentToolCall(
        id: 'tc_build_apk',
        toolName: 'run_command',
        title: 'Запуск сборки APK (flutter build apk --release)',
        arguments: {'command': 'flutter build apk --release'},
        isRunning: true,
      );
      addOrUpdateTool(buildCall);

      final buildRes = await _executeTool('run_command', {
        'command': 'flutter build apk --release',
        'in_terminal': true,
      }, ws, modified);

      addOrUpdateTool(buildCall.copyWith(isRunning: false, result: buildRes));
      _updateAssistantMessage(
        msgId,
        thinking: 'Синхронизация и запуск сборщика выполнены.',
        content: '🚀 **Сборка APK запущена в терминале сборки!**\n\n'
            '• Перед стартом я синхронизировал все файлы из `/storage/emulated/0/QuantumIDE/${p.basename(ws)}`.\n'
            '• Вывод компиляции в реальном времени записывается в `LiveTelemetryService`.\n'
            '• Если возникнет ошибка компиляции — нажмите **«🔧 Исправить ошибки сборки»**, и я сразу разберу лог!',
        modifiedFiles: modified,
        isStreaming: false,
      );
      return;
    }

    // Шаг 2: Диагностика синтаксиса всех Dart-файлов и логов сборки
    state = state.copyWith(statusText: 'Проверка синтаксиса и логов сборки...');
    final diagCall = AgentToolCall(
      id: 'tc_diag',
      toolName: 'get_diagnostics',
      title: 'Сканирование синтаксиса Dart и логов сборки APK',
      arguments: {'workspace': p.basename(ws)},
      isRunning: true,
    );
    addOrUpdateTool(diagCall);

    final diagReport = await _scanWorkspaceDiagnosticsAndHeal(ws, modified);
    addOrUpdateTool(diagCall.copyWith(
      isRunning: false,
      result: diagReport.summaryShort,
    ));

    // Шаг 3: Проверка и лечение конфигурации Gradle / памяти для стабильной сборки
    state = state.copyWith(statusText: 'Проверка конфигурации Android/Gradle...');
    final gradleCall = AgentToolCall(
      id: 'tc_gradle',
      toolName: 'edit_file',
      title: 'Проверка и оптимизация android/gradle.properties (RAM & AAPT2)',
      arguments: {'path': 'android/gradle.properties'},
      isRunning: true,
    );
    addOrUpdateTool(gradleCall);

    final gradleStatus = await _ensureOptimalGradleProperties(ws, modified);
    addOrUpdateTool(gradleCall.copyWith(
      isRunning: false,
      result: gradleStatus,
    ));

    final telemetry = LiveTelemetryService.instance;
    final buildTail = await _readLastBuildErrorLines();

    final buffer = StringBuffer();
    if (appendMode) {
      buffer.writeln('---');
    }
    buffer.writeln('### ⚡ Отчёт Quantum Agent по проекту `${p.basename(ws)}`\n');

    if (syncedFiles.isNotEmpty) {
      buffer.writeln('✅ **Синхронизировано и восстановлено из `/storage/emulated/0/QuantumIDE/${p.basename(ws)}`:**');
      for (final f in syncedFiles.take(10)) {
        buffer.writeln('- `$f`');
      }
      buffer.writeln();
    } else {
      buffer.writeln('✅ **Синхронизация файлов:** Все файлы во внутренней памяти и `/storage/emulated/0/QuantumIDE/${p.basename(ws)}` полностью идентичны (пустых файлов 0 байт нет).\n');
    }

    buffer.writeln('🔍 **Проверка кода (`FastSyntaxEngine`):**');
    buffer.writeln('- Проверено `.dart` файлов: **${diagReport.totalDartFiles}**');
    if (diagReport.errors.isEmpty) {
      buffer.writeln('- Синтаксических ошибок в `lib/`: **0 (всё чисто!)**');
    } else {
      buffer.writeln('- Найдено проблем: **${diagReport.errors.length}**:');
      for (final err in diagReport.errors.take(8)) {
        buffer.writeln('  - `$err`');
      }
    }
    buffer.writeln();

    buffer.writeln('📊 **Состояние системы и памяти:**');
    buffer.writeln('- Свободно RAM: **${telemetry.deviceRamFreeGB.toStringAsFixed(2)} ГБ** из ${telemetry.deviceRamTotalGB.toStringAsFixed(1)} ГБ (IDE: ${telemetry.appRamMB} МБ)');
    buffer.writeln('- Статус последней сборки: **${telemetry.currentBuildStatus}**');
    if (buildTail.isNotEmpty) {
      buffer.writeln('\n📋 **Последние строки сборщика:**\n```text\n$buildTail\n```');
    }

    buffer.writeln('\n💡 *Ваш запрос также сохранён в мост Antigravity (`/storage/emulated/0/QuantumIDE/agent_inbox.json`). '
        'Чтобы включить генерацию любого нового кода прямо внутри этого окна через облачные ИИ (DeepSeek / Qwen / Gemini / Llama 3.3), нажмите на шестерёнку ⚙️ вверху панели чата и выберите провайдера.*');

    _updateAssistantMessage(
      msgId,
      thinking: 'Диагностика, синхронизация и проверка сборщика завершены.',
      content: buffer.toString(),
      modifiedFiles: modified,
      isStreaming: false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ПОЛНЫЙ АВТОНОМНЫЙ ЦИКЛ LLM-АГЕНТА (ReAct + Tool Calling как в Cline/AGY)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _runLlmAgentLoop(
    String msgId,
    String userPrompt,
    QuantumAgentProviderPreset preset,
  ) async {
    final ws = _ref.read(workspaceProvider).currentPath;
    if (ws == null || ws.isEmpty) {
      _updateAssistantMessage(
        msgId,
        content: '❌ Откройте проект, чтобы я мог читать и редактировать файлы.',
        thinking: null,
        isStreaming: false,
      );
      return;
    }

    // Сначала синхронизируем внешние изменения
    await _ref.read(editorProvider.notifier).syncExternalNow(reloadAllTabs: true);

    final toolCallsUi = <AgentToolCall>[];
    final modifiedFiles = <String>[];

    void addOrUpdateToolUi(AgentToolCall call) {
      final idx = toolCallsUi.indexWhere((t) => t.id == call.id);
      if (idx >= 0) {
        toolCallsUi[idx] = call;
      } else {
        toolCallsUi.add(call);
      }
      _updateAssistantMessage(msgId, toolCalls: List.of(toolCallsUi), modifiedFiles: List.of(modifiedFiles));
    }

    final activeFile = _ref.read(editorProvider).let((s) {
      if (s.openFiles.isEmpty || s.activeTabIndex < 0 || s.activeTabIndex >= s.openFiles.length) {
        return null;
      }
      return s.openFiles[s.activeTabIndex];
    });

    final systemPrompt = '''
Ты — Quantum Agent, автономный ИИ-инженер внутри мобильной среды разработки Quantum IDE (построен по архитектуре Antigravity / Cline).
Текущий проект: $ws (зеркало во внешней памяти: /storage/emulated/0/QuantumIDE/${p.basename(ws)}).
Открытый файл в редакторе: ${activeFile != null ? p.relative(activeFile.path, from: ws) : 'нет'}.
Статус последней сборки: ${LiveTelemetryService.instance.currentBuildStatus}.

ТВОИ ИНСТРУМЕНТЫ (вызывай через XML блок <tool_call> или стандартный JSON tool_calls):
Чтобы вызвать инструмент, выведи блок:
<tool_call>
{"name": "ИМЯ_ИНСТРУМЕНТА", "arguments": {...}}
</tool_call>

Доступные инструменты:
1. "list_files": {"subdir": "опциональная подпапка, например lib"} — список файлов проекта.
2. "search_code": {"query": "строка или regex поиска", "subdir": "lib"} — поиск текста по файлам проекта.
3. "read_file": {"path": "относительный путь, например lib/main.dart", "start_line": 1, "end_line": 200} — чтение файла с номерами строк.
4. "edit_file": {"path": "относительный путь", "target": "точный фрагмент старого кода", "replacement": "новый код"} — точечная замена кода в файле.
5. "write_file": {"path": "относительный путь", "content": "полный текст файла"} — создание или перезапись файла.
6. "run_command": {"command": "команда bash/flutter", "in_terminal": false} — запуск команды в проекте (если in_terminal=true — отправит команду в терминал сборки IDE).
7. "get_diagnostics": {} — получить все текущие ошибки синтаксиса Dart и последние строки лога сборки APK.

ПРАВИЛА РАБОТЫ:
- Всегда сначала проверяй файлы через read_file или get_diagnostics перед редактированием.
- Когда исправляешь код через edit_file или write_file, пиши полный рабочий код без заглушек.
- Отвечай кратко, по делу, на русском языке.
''';

    final conversation = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    // Добавляем последние сообщения из истории
    final history = state.messages.where((m) => m.id != msgId && m.id != 'welcome').toList();
    for (final h in history.skip(history.length > 6 ? history.length - 6 : 0)) {
      conversation.add({
        'role': h.role,
        'content': h.content,
      });
    }

    String finalAnswer = '';
    const maxSteps = 8;

    for (int step = 1; step <= maxSteps; step++) {
      if (_cancelRequested) break;
      state = state.copyWith(statusText: 'Шаг $step: размышление (${state.modelId})...');

      final response = await _dio.post(
        preset.baseUrl,
        options: Options(headers: {
          'Authorization': 'Bearer ${state.apiKey}',
          'Content-Type': 'application/json',
          if (preset.id == 'openrouter') 'HTTP-Referer': 'https://github.com/Lesorub361/quantum_ide',
          if (preset.id == 'openrouter') 'X-Title': 'QuantumIDE Agent',
        }),
        data: {
          'model': state.modelId,
          'messages': conversation,
          'temperature': 0.15,
        },
      );

      final choices = response.data['choices'] as List?;
      if (choices == null || choices.isEmpty) break;
      final msgObj = choices.first['message'] as Map<String, dynamic>? ?? {};
      final rawContent = msgObj['content']?.toString() ?? '';
      final reasoning = msgObj['reasoning_content']?.toString();

      // Извлекаем все вызовы <tool_call>...</tool_call>
      final parsedCalls = _extractXmlToolCalls(rawContent);
      final cleanText = rawContent
          .replaceAll(RegExp(r'<tool_call>[\s\S]*?</tool_call>'), '')
          .trim();

      if (reasoning != null && reasoning.isNotEmpty) {
        _updateAssistantMessage(msgId, thinking: reasoning);
      }

      if (cleanText.isNotEmpty) {
        finalAnswer = cleanText;
        _updateAssistantMessage(msgId, content: finalAnswer);
      }

      if (parsedCalls.isEmpty) {
        // Агент завершил работу и дал финальный ответ
        break;
      }

      conversation.add({'role': 'assistant', 'content': rawContent});

      final toolResultsText = StringBuffer();
      for (final callSpec in parsedCalls) {
        if (_cancelRequested) break;
        final name = callSpec['name']?.toString() ?? '';
        final args = (callSpec['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
        final tcId = 'tc_${DateTime.now().millisecondsSinceEpoch}_${ toolCallsUi.length}';
        final title = _formatToolTitle(name, args);

        state = state.copyWith(statusText: title);
        final uiCall = AgentToolCall(
          id: tcId,
          toolName: name,
          title: title,
          arguments: args,
          isRunning: true,
        );
        addOrUpdateToolUi(uiCall);

        final result = await _executeTool(name, args, ws, modifiedFiles);
        final isErr = result.startsWith('ERROR:');
        addOrUpdateToolUi(uiCall.copyWith(
          isRunning: false,
          result: result.length > 1500 ? '${result.substring(0, 1500)}\n...[truncated]' : result,
          isError: isErr,
        ));

        toolResultsText.writeln('<tool_result name="$name">\n$result\n</tool_result>');
      }

      conversation.add({
        'role': 'user',
        'content': toolResultsText.toString(),
      });
    }

    _updateAssistantMessage(
      msgId,
      content: finalAnswer.isEmpty ? '✅ Задача выполнена.' : finalAnswer,
      modifiedFiles: modifiedFiles,
      isStreaming: false,
    );
  }

  List<Map<String, dynamic>> _extractXmlToolCalls(String text) {
    final results = <Map<String, dynamic>>[];
    final regex = RegExp(r'<tool_call>\s*([\s\S]*?)\s*</tool_call>');
    for (final match in regex.allMatches(text)) {
      final body = match.group(1)?.trim() ?? '';
      if (body.isEmpty) continue;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded.containsKey('name')) {
          results.add(decoded);
        }
      } catch (_) {}
    }
    return results;
  }

  String _formatToolTitle(String name, Map<String, dynamic> args) {
    final path = args['path']?.toString() ?? args['subdir']?.toString() ?? '';
    switch (name) {
      case 'list_files':
        return 'Просмотр структуры файлов ${path.isNotEmpty ? "($path)" : ""}';
      case 'search_code':
        return 'Поиск в коде: "${args['query'] ?? ''}"';
      case 'read_file':
        return 'Чтение файла $path';
      case 'edit_file':
        return 'Редактирование файла $path';
      case 'write_file':
        return 'Запись файла $path';
      case 'run_command':
        return 'Выполнение: ${args['command'] ?? ''}';
      case 'get_diagnostics':
        return 'Проверка ошибок синтаксиса и сборки';
      default:
        return 'Инструмент: $name';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. РЕАЛИЗАЦИЯ ИНСТРУМЕНТОВ АГЕНТА (ФАЙЛЫ, ПОИСК, ТЕРМИНАЛ, ДИАГНОСТИКА)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<String> _executeTool(
    String name,
    Map<String, dynamic> args,
    String ws,
    List<String> modifiedFiles,
  ) async {
    try {
      switch (name) {
        case 'list_files': {
          final subdir = args['subdir']?.toString() ?? '';
          final targetDir = subdir.isEmpty ? Directory(ws) : Directory(p.join(ws, subdir));
          if (!await targetDir.exists()) return 'ERROR: Папка не найдена: $subdir';
          final items = <String>[];
          await for (final entity in targetDir.list(recursive: true, followLinks: false)) {
            final rel = p.relative(entity.path, from: ws);
            final parts = p.split(rel);
            if (parts.any((seg) =>
                seg == '.git' ||
                seg == 'build' ||
                seg == '.dart_tool' ||
                seg == 'local_plugins' ||
                seg == 'node_modules' ||
                seg == '.gradle')) {
              continue;
            }
            if (entity is File) {
              final len = await entity.length();
              items.add('$rel ($len bytes)');
              if (items.length >= 200) break;
            }
          }
          items.sort();
          return items.isEmpty ? 'Файлы не найдены.' : items.join('\n');
        }

        case 'search_code': {
          final query = args['query']?.toString() ?? '';
          if (query.isEmpty) return 'ERROR: Пустой поисковый запрос';
          final subdir = args['subdir']?.toString() ?? 'lib';
          final dir = Directory(p.join(ws, subdir));
          final searchRoot = await dir.exists() ? dir : Directory(ws);
          final matches = <String>[];
          final pattern = RegExp(RegExp.escape(query), caseSensitive: false);

          await for (final entity in searchRoot.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final rel = p.relative(entity.path, from: ws);
            if (rel.startsWith('.git') || rel.startsWith('build') || rel.startsWith('.dart_tool') || rel.startsWith('local_plugins')) {
              continue;
            }
            if (!rel.endsWith('.dart') && !rel.endsWith('.yaml') && !rel.endsWith('.gradle') && !rel.endsWith('.kts') && !rel.endsWith('.xml') && !rel.endsWith('.json')) {
              continue;
            }
            try {
              final lines = await entity.readAsLines();
              for (int i = 0; i < lines.length; i++) {
                if (pattern.hasMatch(lines[i])) {
                  matches.add('$rel:${i + 1}: ${lines[i].trim()}');
                  if (matches.length >= 60) break;
                }
              }
            } catch (_) {}
            if (matches.length >= 60) break;
          }
          return matches.isEmpty ? 'Совпадений не найдено.' : matches.join('\n');
        }

        case 'read_file': {
          final reqPath = args['path']?.toString() ?? '';
          if (reqPath.isEmpty) return 'ERROR: Не указан path';
          final fullPath = p.isAbsolute(reqPath) ? reqPath : p.join(ws, reqPath);
          final file = File(fullPath);
          if (!await file.exists()) return 'ERROR: Файл не найден: $reqPath';
          final lines = await file.readAsLines();
          final start = ((args['start_line'] as num?)?.toInt() ?? 1).clamp(1, lines.isEmpty ? 1 : lines.length);
          final end = ((args['end_line'] as num?)?.toInt() ?? (start + 220)).clamp(start, lines.length);
          final buf = StringBuffer();
          for (int i = start; i <= end; i++) {
            buf.writeln('$i: ${lines[i - 1]}');
          }
          return buf.toString();
        }

        case 'edit_file': {
          final reqPath = args['path']?.toString() ?? '';
          final target = args['target']?.toString() ?? '';
          final replacement = args['replacement']?.toString() ?? '';
          if (reqPath.isEmpty || target.isEmpty) {
            return 'ERROR: Для edit_file требуются path и target';
          }
          final fullPath = p.isAbsolute(reqPath) ? reqPath : p.join(ws, reqPath);
          final file = File(fullPath);
          if (!await file.exists()) return 'ERROR: Файл не существует: $reqPath';
          final content = await file.readAsString();
          if (!content.contains(target)) {
            return 'ERROR: Точный блок target не найден в файле $reqPath. Сначала прочитайте актуальный файл через read_file.';
          }
          final newContent = content.replaceFirst(target, replacement);
          if (newContent.trim().isEmpty && content.trim().isNotEmpty) {
            return 'ERROR: Защита от пустых файлов (0 байт) заблокировала очистку файла.';
          }
          await file.writeAsString(newContent, flush: true);
          await _mirrorAndReloadInIde(ws, fullPath, newContent, modifiedFiles);
          final syntaxDiags = FastSyntaxEngine.instance.analyze(fullPath, newContent);
          final errs = syntaxDiags.where((d) => d.severity == CodeDiagnosticSeverity.error).toList();
          if (errs.isNotEmpty) {
            return 'Файл $reqPath обновлён, но анализатор нашёл синтаксические ошибки:\n'
                '${errs.map((e) => "Строка ${e.range.index + 1}: ${e.message}").join("\n")}';
          }
          return 'SUCCESS: Файл $reqPath успешно обновлён и синхронизирован (ошибок синтаксиса: 0).';
        }

        case 'write_file': {
          final reqPath = args['path']?.toString() ?? '';
          final content = args['content']?.toString() ?? '';
          if (reqPath.isEmpty || content.isEmpty) {
            return 'ERROR: Для write_file требуются непустые path и content';
          }
          final fullPath = p.isAbsolute(reqPath) ? reqPath : p.join(ws, reqPath);
          final file = File(fullPath);
          await file.parent.create(recursive: true);
          await file.writeAsString(content, flush: true);
          await _mirrorAndReloadInIde(ws, fullPath, content, modifiedFiles);
          return 'SUCCESS: Файл $reqPath записан (${content.length} байт) и синхронизирован.';
        }

        case 'run_command': {
          final cmd = args['command']?.toString() ?? '';
          final inTerminal = args['in_terminal'] == true;
          if (cmd.isEmpty) return 'ERROR: Пустая команда';
          if (inTerminal || cmd.contains('flutter build')) {
            await _ref.read(editorProvider.notifier).syncExternalNow(reloadAllTabs: true);
            _ref.read(dedicatedTerminalProvider.notifier).sendCommand(
              DedicatedTerminalType.build,
              'cd "/root/projects/${p.basename(ws)}" 2>/dev/null; $cmd',
              interrupt: true,
              clear: false,
            );
            return 'Команда "$cmd" отправлена в терминал сборки IDE.';
          }
          final res = await Process.run(
            '/system/bin/sh',
            ['-c', cmd],
            workingDirectory: ws,
          ).timeout(const Duration(seconds: 20));
          return 'Exit code: ${res.exitCode}\nStdout:\n${res.stdout}\nStderr:\n${res.stderr}'.trim();
        }

        case 'get_diagnostics': {
          final report = await _scanWorkspaceDiagnosticsAndHeal(ws, modifiedFiles);
          final buildTail = await _readLastBuildErrorLines();
          return '${report.summaryDetailed}\n\nBuild status: ${LiveTelemetryService.instance.currentBuildStatus}\n$buildTail';
        }

        default:
          return 'ERROR: Неизвестный инструмент $name';
      }
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  Future<void> _mirrorAndReloadInIde(
    String ws,
    String fullPath,
    String content,
    List<String> modifiedFiles,
  ) async {
    final rel = p.relative(fullPath, from: ws);
    if (!modifiedFiles.contains(rel)) {
      modifiedFiles.add(rel);
    }
    try {
      final extFile = File(p.join(_sharedDir, p.basename(ws), rel));
      await extFile.parent.create(recursive: true);
      await extFile.writeAsString(content, flush: true);
    } catch (_) {}
    await _ref.read(editorProvider.notifier).reloadFileFromDisk(fullPath);
  }

  Future<({int totalDartFiles, List<String> errors, String summaryShort, String summaryDetailed})>
      _scanWorkspaceDiagnosticsAndHeal(String ws, List<String> modified) async {
    int dartCount = 0;
    final errors = <String>[];
    final libDir = Directory(p.join(ws, 'lib'));
    final scanRoot = await libDir.exists() ? libDir : Directory(ws);

    if (await scanRoot.exists()) {
      await for (final entity in scanRoot.list(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = p.relative(entity.path, from: ws);
        if (rel.startsWith('local_plugins') || rel.startsWith('.dart_tool') || rel.startsWith('build')) {
          continue;
        }
        dartCount++;
        try {
          final content = await entity.readAsString();
          final diags = FastSyntaxEngine.instance.analyze(entity.path, content);
          for (final d in diags) {
            if (d.severity == CodeDiagnosticSeverity.error) {
              errors.add('$rel:${d.range.index + 1}: ${d.message}');
            }
          }
        } catch (_) {}
      }
    }

    final shortStr = errors.isEmpty
        ? 'Проверено $dartCount .dart файлов — 0 синтаксических ошибок!'
        : 'Проверено $dartCount файлов, найдено ошибок: ${errors.length}';
    final detailedStr = errors.isEmpty
        ? shortStr
        : '$shortStr:\n${errors.take(15).join("\n")}';

    return (
      totalDartFiles: dartCount,
      errors: errors,
      summaryShort: shortStr,
      summaryDetailed: detailedStr,
    );
  }

  Future<String> _ensureOptimalGradleProperties(String ws, List<String> modified) async {
    try {
      final androidDir = Directory(p.join(ws, 'android'));
      if (!await androidDir.exists()) {
        return 'Папка android/ отсутствует (не Android-проект).';
      }
      final gpFile = File(p.join(androidDir.path, 'gradle.properties'));
      String content = await gpFile.exists() ? await gpFile.readAsString() : '';
      bool changed = false;

      if (!content.contains('org.gradle.jvmargs=-Xmx2048m')) {
        content = content.replaceAll(RegExp(r'org\.gradle\.jvmargs=.*'), '');
        content = '${content.trim()}\norg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m\n';
        changed = true;
      }
      if (!content.contains('org.gradle.daemon=false')) {
        content = '${content.trim()}\norg.gradle.daemon=false\norg.gradle.workers.max=1\norg.gradle.parallel=false\n';
        changed = true;
      }
      if (!content.contains('android.aapt2FromMaven=false')) {
        content = '${content.trim()}\nandroid.aapt2FromMaven=false\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\nandroid.aapt2.daemon=false\n';
        changed = true;
      }

      if (changed) {
        await gpFile.writeAsString(content, flush: true);
        await _mirrorAndReloadInIde(ws, gpFile.path, content, modified);
        return 'Оптимизированы флаги памяти (-Xmx2048m, daemon=false, native aapt2) в android/gradle.properties.';
      }
      return 'android/gradle.properties уже оптимален (-Xmx2048m, daemon=false, native aapt2).';
    } catch (e) {
      return 'Проверка gradle.properties: $e';
    }
  }

  Future<String> _readLastBuildErrorLines() async {
    try {
      final logFile = File(p.join(_sharedDir, 'build_output.log'));
      if (!await logFile.exists()) return '';
      final lines = await logFile.readAsLines();
      if (lines.isEmpty) return '';
      final errLines = lines.where((l) =>
          l.contains('Error:') ||
          l.contains('FAILURE:') ||
          l.contains('Exception') ||
          l.contains('BUILD FAILED') ||
          l.contains('BUILD SUCCESSFUL') ||
          l.contains('✓ APK готов')).toList();
      if (errLines.isNotEmpty) {
        return errLines.length > 12
            ? errLines.sublist(errLines.length - 12).join('\n')
            : errLines.join('\n');
      }
      return lines.length > 10 ? lines.sublist(lines.length - 10).join('\n') : lines.join('\n');
    } catch (_) {
      return '';
    }
  }
}

extension _LetExt<T> on T {
  R let<R>(R Function(T self) block) => block(this);
}
