import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
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
  HttpServer? _localOpenAiServer;
  final Map<String, CancelToken> _downloadTokens = {};

  static const String _prefProvider = 'q_agent_provider_v3';
  static const String _prefModel = 'q_agent_model_v3';
  static const String _prefKeyPrefix = 'q_agent_key_';
  static const String _prefVaultPrefix = 'q_agent_vault_';
  static const String _prefDiscoveredPrefix = 'q_agent_disc_';
  static const String _sharedDir = '/storage/emulated/0/QuantumIDE';
  static const String _modelsDir = '/storage/emulated/0/QuantumIDE/models';

  QuantumAgentNotifier(this._ref) : super(const QuantumAgentState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString(_prefProvider) ?? 'antigravity_doctor';
    final preset = QuantumAgentProviderPreset.byId(providerId);
    final savedModel = prefs.getString(_prefModel);
    final modelId = (savedModel != null && savedModel.isNotEmpty)
        ? savedModel
        : preset.models.first;
    final apiKey = prefs.getString('$_prefKeyPrefix$providerId') ?? '';

    final inferenceMode = prefs.getString('q_inference_mode') ?? 'cloud';
    final selectedHarness = prefs.getString('q_selected_harness') ?? 'native';
    final antigravityEffort = prefs.getString('q_agy_effort') ?? 'high';
    final temperature = prefs.getDouble('q_temperature') ?? 0.2;
    final maxTokens = prefs.getInt('q_max_tokens') ?? 2048;
    final contextSize = prefs.getInt('q_context_size') ?? 8192;
    final performanceMode = prefs.getString('q_perf_mode') ?? 'auto_fast';
    final systemPromptPreset = prefs.getString('q_sys_preset') ?? 'agent';
    final customSystemPrompt = prefs.getString('q_sys_custom') ?? '';
    final stopSeqRaw = prefs.getStringList('q_stop_seq') ?? const [];
    final openRouterOrder = prefs.getString('q_or_order') ?? '';
    final openRouterFallback = prefs.getBool('q_or_fallback') ?? true;
    final freeFirst = prefs.getBool('q_free_first') ?? true;
    final customBaseUrl = prefs.getString('q_custom_url') ?? '';
    final customProtocol = prefs.getString('q_custom_proto') ?? 'openai-completions';
    final activeLocalModel = prefs.getString('q_active_local_model') ?? 'lfm2.5-1.2b-instruct-q4_k_m.gguf';
    final serverPort = prefs.getInt('q_srv_port') ?? 8080;
    final serverAllowNet = prefs.getBool('q_srv_net') ?? false;
    final serverReqKey = prefs.getBool('q_srv_req_key') ?? false;
    final serverApiKey = prefs.getString('q_srv_api_key') ?? 'qide-${Random().nextInt(899999) + 100000}';

    // Загружаем сохранённые мульти-ключи (Vault из Mobile-Harness)
    final vaultMap = <String, List<SavedApiKeyEntry>>{};
    final discMap = <String, List<String>>{};
    for (final pPreset in QuantumAgentProviderPreset.presets) {
      final rawVault = prefs.getString('$_prefVaultPrefix${pPreset.id}');
      if (rawVault != null && rawVault.isNotEmpty) {
        try {
          final list = (jsonDecode(rawVault) as List)
              .map((e) => SavedApiKeyEntry.fromJson((e as Map).cast<String, dynamic>()))
              .toList();
          vaultMap[pPreset.id] = list;
        } catch (_) {}
      }
      final rawDisc = prefs.getStringList('$_prefDiscoveredPrefix${pPreset.id}');
      if (rawDisc != null && rawDisc.isNotEmpty) {
        discMap[pPreset.id] = rawDisc;
      } else {
        discMap[pPreset.id] = List.of(pPreset.models);
      }
    }

    state = state.copyWith(
      inferenceMode: inferenceMode,
      providerId: providerId,
      modelId: modelId,
      apiKey: apiKey,
      selectedHarness: selectedHarness,
      antigravityEffort: antigravityEffort,
      temperature: temperature,
      maxTokens: maxTokens,
      contextSize: contextSize,
      performanceMode: performanceMode,
      systemPromptPreset: systemPromptPreset,
      customSystemPrompt: customSystemPrompt,
      stopSequences: stopSeqRaw,
      openRouterProviderOrder: openRouterOrder,
      openRouterAllowFallbacks: openRouterFallback,
      freeModelsFirst: freeFirst,
      customBaseUrl: customBaseUrl,
      customProtocol: customProtocol,
      activeLocalModel: activeLocalModel,
      savedKeysByProvider: vaultMap,
      discoveredModelsByProvider: discMap,
      localServerPort: serverPort,
      localServerAllowNetwork: serverAllowNet,
      localServerRequireKey: serverReqKey,
      localServerApiKey: serverApiKey,
      messages: [
        AgentChatMessage(
          id: 'welcome',
          role: 'assistant',
          content: 'Привет! Я **Quantum Agent** — единый ИИ-центр (`PrivateLM` + `Mobile Harness` + `Antigravity`).\n\n'
              '• **Чат & Код**: пишу и правлю файлы с авто-чекпоинтами и построчным Diff (`Changes`)\n'
              '• **Модели**: 11 облачных провайдеров + каталог из 19 локальных моделей (`GGUF` / `LiteRT-LM` / `SD 1.5`)\n'
              '• **Харнессы**: `Native Autopilot`, `Antigravity CLI`, `Claude Code`, `DeepSeek Harness`\n'
              '• **OpenAI Server**: локальный сервер `/v1/chat/completions` прямо на телефоне!',
          timestamp: DateTime.now(),
        ),
      ],
    );

    await refreshLocalModels();
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
          final parsed = _parseThought(reply);
          final msg = AgentChatMessage(
            id: msgId,
            role: 'assistant',
            content: parsed.cleanContent,
            thinking: data['thinking']?.toString() ?? parsed.thinking,
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
    _localOpenAiServer?.close(force: true);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // УПРАВЛЕНИЕ НАСТРОЙКАМИ, МОДЕЛЯМИ, МУЛЬТИ-КЛЮЧАМИ И СЕРВЕРОМ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> updateConfig({
    required String providerId,
    required String modelId,
    required String apiKey,
    String? inferenceMode,
    String? selectedHarness,
    String? antigravityEffort,
    String? customBaseUrl,
    String? customProtocol,
    String? openRouterProviderOrder,
    bool? openRouterAllowFallbacks,
    bool? freeModelsFirst,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefProvider, providerId);
    await prefs.setString(_prefModel, modelId);
    await prefs.setString('$_prefKeyPrefix$providerId', apiKey.trim());
    if (inferenceMode != null) await prefs.setString('q_inference_mode', inferenceMode);
    if (selectedHarness != null) await prefs.setString('q_selected_harness', selectedHarness);
    if (antigravityEffort != null) await prefs.setString('q_agy_effort', antigravityEffort);
    if (customBaseUrl != null) await prefs.setString('q_custom_url', customBaseUrl);
    if (customProtocol != null) await prefs.setString('q_custom_proto', customProtocol);
    if (openRouterProviderOrder != null) await prefs.setString('q_or_order', openRouterProviderOrder);
    if (openRouterAllowFallbacks != null) await prefs.setBool('q_or_fallback', openRouterAllowFallbacks);
    if (freeModelsFirst != null) await prefs.setBool('q_free_first', freeModelsFirst);

    state = state.copyWith(
      providerId: providerId,
      modelId: modelId,
      apiKey: apiKey.trim(),
      inferenceMode: inferenceMode ?? state.inferenceMode,
      selectedHarness: selectedHarness ?? state.selectedHarness,
      antigravityEffort: antigravityEffort ?? state.antigravityEffort,
      customBaseUrl: customBaseUrl ?? state.customBaseUrl,
      customProtocol: customProtocol ?? state.customProtocol,
      openRouterProviderOrder: openRouterProviderOrder ?? state.openRouterProviderOrder,
      openRouterAllowFallbacks: openRouterAllowFallbacks ?? state.openRouterAllowFallbacks,
      freeModelsFirst: freeModelsFirst ?? state.freeModelsFirst,
    );
  }

  Future<void> updateGenerationParams({
    double? temperature,
    int? maxTokens,
    int? contextSize,
    String? performanceMode,
    String? systemPromptPreset,
    String? customSystemPrompt,
    List<String>? stopSequences,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (temperature != null) await prefs.setDouble('q_temperature', temperature);
    if (maxTokens != null) await prefs.setInt('q_max_tokens', maxTokens);
    if (contextSize != null) await prefs.setInt('q_context_size', contextSize);
    if (performanceMode != null) await prefs.setString('q_perf_mode', performanceMode);
    if (systemPromptPreset != null) await prefs.setString('q_sys_preset', systemPromptPreset);
    if (customSystemPrompt != null) await prefs.setString('q_sys_custom', customSystemPrompt);
    if (stopSequences != null) await prefs.setStringList('q_stop_seq', stopSequences);

    state = state.copyWith(
      temperature: temperature ?? state.temperature,
      maxTokens: maxTokens ?? state.maxTokens,
      contextSize: contextSize ?? state.contextSize,
      performanceMode: performanceMode ?? state.performanceMode,
      systemPromptPreset: systemPromptPreset ?? state.systemPromptPreset,
      customSystemPrompt: customSystemPrompt ?? state.customSystemPrompt,
      stopSequences: stopSequences ?? state.stopSequences,
    );
  }

  Future<String> getSavedKeyForProvider(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefKeyPrefix$providerId') ?? '';
  }

  // ─── Multi-Key API Vault (из Mobile-Harness ApiKeyVault.kt) ────────────────

  Future<void> addVaultKey(String providerId, String name, String key) async {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) return;
    final label = name.trim().isEmpty ? 'Key ${(state.savedKeysByProvider[providerId]?.length ?? 0) + 1}' : name.trim();
    final existing = List<SavedApiKeyEntry>.from(state.savedKeysByProvider[providerId] ?? const []);
    final updated = existing.map((e) => e.copyWith(isActive: false)).toList()
      ..add(SavedApiKeyEntry(name: label, key: cleanKey, isActive: true));

    final map = Map<String, List<SavedApiKeyEntry>>.from(state.savedKeysByProvider);
    map[providerId] = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefVaultPrefix$providerId', jsonEncode(updated.map((e) => e.toJson()).toList()));
    await prefs.setString('$_prefKeyPrefix$providerId', cleanKey);

    state = state.copyWith(
      savedKeysByProvider: map,
      apiKey: providerId == state.providerId ? cleanKey : state.apiKey,
    );
  }

  Future<void> activateVaultKey(String providerId, String keyName) async {
    final existing = List<SavedApiKeyEntry>.from(state.savedKeysByProvider[providerId] ?? const []);
    String activeSecret = '';
    final updated = existing.map((e) {
      final match = e.name == keyName;
      if (match) activeSecret = e.key;
      return e.copyWith(isActive: match);
    }).toList();

    final map = Map<String, List<SavedApiKeyEntry>>.from(state.savedKeysByProvider);
    map[providerId] = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefVaultPrefix$providerId', jsonEncode(updated.map((e) => e.toJson()).toList()));
    if (activeSecret.isNotEmpty) {
      await prefs.setString('$_prefKeyPrefix$providerId', activeSecret);
    }

    state = state.copyWith(
      savedKeysByProvider: map,
      apiKey: (providerId == state.providerId && activeSecret.isNotEmpty) ? activeSecret : state.apiKey,
    );
  }

  Future<void> removeVaultKey(String providerId, String keyName) async {
    final existing = List<SavedApiKeyEntry>.from(state.savedKeysByProvider[providerId] ?? const []);
    existing.removeWhere((e) => e.name == keyName);
    final map = Map<String, List<SavedApiKeyEntry>>.from(state.savedKeysByProvider);
    map[providerId] = existing;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefVaultPrefix$providerId', jsonEncode(existing.map((e) => e.toJson()).toList()));
    state = state.copyWith(savedKeysByProvider: map);
  }

  // ─── Авто-обнаружение моделей и проверка соединения (Verify & Discover) ───

  Future<void> discoverModelsForProvider(String providerId) async {
    final preset = QuantumAgentProviderPreset.byId(providerId);
    if (preset.modelsUrl.isEmpty && providerId != 'custom') return;
    state = state.copyWith(isDiscoveringModels: true);

    try {
      final key = providerId == state.providerId
          ? state.apiKey
          : await getSavedKeyForProvider(providerId);
      String url = preset.modelsUrl;
      if (providerId == 'custom' && state.customBaseUrl.isNotEmpty) {
        final base = state.customBaseUrl.replaceAll(RegExp(r'/chat/completions/?$'), '');
        url = '$base/models';
      }
      if (providerId == 'gemini' && key.isNotEmpty) {
        url = 'https://generativelanguage.googleapis.com/v1beta/models?key=$key';
      }

      final headers = <String, String>{'Accept': 'application/json'};
      if (key.isNotEmpty && providerId != 'gemini') {
        if (providerId == 'anthropic') {
          headers['x-api-key'] = key;
          headers['anthropic-version'] = '2023-06-01';
        } else {
          headers['Authorization'] = 'Bearer $key';
        }
      }

      final sw = Stopwatch()..start();
      final res = await _dio.get(url, options: Options(headers: headers));
      sw.stop();

      final list = <String>[];
      final data = res.data;
      if (data is Map) {
        final rawList = (data['data'] ?? data['models']) as List?;
        if (rawList != null) {
          for (final item in rawList) {
            if (item is Map) {
              final id = (item['id'] ?? item['name'])?.toString() ?? '';
              if (id.isNotEmpty) {
                list.add(id.replaceFirst('models/', ''));
              }
            }
          }
        }
      }

      if (list.isNotEmpty) {
        final map = Map<String, List<String>>.from(state.discoveredModelsByProvider);
        map[providerId] = list;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('$_prefDiscoveredPrefix$providerId', list.take(200).toList());
        state = state.copyWith(
          discoveredModelsByProvider: map,
          isDiscoveringModels: false,
          connectionVerified: true,
          connectionStatusText: 'Загружено ${list.length} моделей (${sw.elapsedMilliseconds} мс)',
        );
      } else {
        state = state.copyWith(
          isDiscoveringModels: false,
          connectionVerified: true,
          connectionStatusText: 'Подключено (${sw.elapsedMilliseconds} мс)',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isDiscoveringModels: false,
        connectionVerified: false,
        connectionStatusText: 'Ошибка запроса моделей: $e',
      );
    }
  }

  Future<void> verifyProviderConnection() async {
    final preset = QuantumAgentProviderPreset.byId(state.providerId);
    if (!preset.requiresKey) {
      state = state.copyWith(
        connectionVerified: true,
        connectionStatusText: 'Встроенный мост активен (0 мс)',
      );
      return;
    }
    state = state.copyWith(isVerifyingConnection: true, connectionStatusText: 'Проверка ключа...');
    await discoverModelsForProvider(state.providerId);
    state = state.copyWith(isVerifyingConnection: false);
  }

  // ─── Локальные модели GGUF / LiteRT / SD (из cross-platform-llm-client) ────

  Future<void> refreshLocalModels() async {
    try {
      final dir = Directory(_modelsDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final files = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.endsWith('.gguf') || name.endsWith('.litertlm') || name.endsWith('.safetensors')) {
            files.add(name);
          }
        }
      }
      state = state.copyWith(downloadedLocalModels: files);
    } catch (_) {}
  }

  void setLocalModelFilter(String filter) {
    state = state.copyWith(localModelFilter: filter);
  }

  Future<void> selectActiveLocalModel(String filename) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('q_active_local_model', filename);
    state = state.copyWith(
      activeLocalModel: filename,
      inferenceMode: 'local',
      providerId: 'local_gguf',
      modelId: filename,
    );
  }

  Future<void> downloadLocalModel(LocalAiModel model) async {
    if (_downloadTokens.containsKey(model.filename)) return;
    final token = CancelToken();
    _downloadTokens[model.filename] = token;

    final prog = Map<String, double>.from(state.downloadProgressByFile);
    prog[model.filename] = 0.01;
    state = state.copyWith(downloadProgressByFile: prog);

    try {
      final dir = Directory(_modelsDir);
      await dir.create(recursive: true);
      final targetPath = p.join(_modelsDir, model.filename);
      await _dio.download(
        model.url,
        targetPath,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final nextProg = Map<String, double>.from(state.downloadProgressByFile);
            nextProg[model.filename] = (received / total).clamp(0.01, 1.0);
            state = state.copyWith(downloadProgressByFile: nextProg);
          }
        },
      );
      _downloadTokens.remove(model.filename);
      final doneProg = Map<String, double>.from(state.downloadProgressByFile)..remove(model.filename);
      state = state.copyWith(downloadProgressByFile: doneProg);
      await refreshLocalModels();
      await selectActiveLocalModel(model.filename);
    } catch (_) {
      _downloadTokens.remove(model.filename);
      final doneProg = Map<String, double>.from(state.downloadProgressByFile)..remove(model.filename);
      state = state.copyWith(downloadProgressByFile: doneProg);
    }
  }

  void cancelLocalDownload(String filename) {
    _downloadTokens.remove(filename)?.cancel();
    final doneProg = Map<String, double>.from(state.downloadProgressByFile)..remove(filename);
    state = state.copyWith(downloadProgressByFile: doneProg);
  }

  Future<void> deleteLocalModel(String filename) async {
    try {
      final f = File(p.join(_modelsDir, filename));
      if (await f.exists()) await f.delete();
      await refreshLocalModels();
    } catch (_) {}
  }

  Future<void> importLocalModelFromStorage() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      final dir = Directory(_modelsDir);
      await dir.create(recursive: true);
      final name = p.basename(path);
      await File(path).copy(p.join(_modelsDir, name));
      await refreshLocalModels();
      await selectActiveLocalModel(name);
    } catch (_) {}
  }

  // ─── Локальный OpenAI API Сервер (из cross-platform-llm-client ServerView) ─

  Future<void> toggleLocalOpenAiServer(bool enable) async {
    if (!enable) {
      await _localOpenAiServer?.close(force: true);
      _localOpenAiServer = null;
      state = state.copyWith(isLocalServerRunning: false);
      return;
    }

    try {
      await _localOpenAiServer?.close(force: true);
      final host = state.localServerAllowNetwork ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4;
      final server = await HttpServer.bind(host, state.localServerPort, shared: true);
      _localOpenAiServer = server;
      state = state.copyWith(isLocalServerRunning: true);

      server.listen((HttpRequest req) async {
        req.response.headers.set('Access-Control-Allow-Origin', '*');
        req.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        if (req.method == 'OPTIONS') {
          req.response.statusCode = 204;
          await req.response.close();
          return;
        }

        if (state.localServerRequireKey) {
          final auth = req.headers.value('authorization') ?? '';
          if (auth != 'Bearer ${state.localServerApiKey}') {
            req.response.statusCode = 401;
            req.response.write(jsonEncode({'error': 'Unauthorized: invalid Bearer key'}));
            await req.response.close();
            return;
          }
        }

        state = state.copyWith(localServerRequestsCount: state.localServerRequestsCount + 1);
        final path = req.uri.path;

        if (path == '/health' || path == '/v1/health') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'status': 'ok',
            'model': state.modelId,
            'provider': state.providerId,
          }));
          await req.response.close();
          return;
        }

        if (path == '/v1/models') {
          req.response.headers.contentType = ContentType.json;
          final models = state.discoveredModelsByProvider[state.providerId] ?? [state.modelId];
          req.response.write(jsonEncode({
            'object': 'list',
            'data': models.map((m) => {'id': m, 'object': 'model', 'owned_by': 'quantum-ide'}).toList(),
          }));
          await req.response.close();
          return;
        }

        if (path == '/v1/chat/completions' && req.method == 'POST') {
          final bodyStr = await utf8.decoder.bind(req).join();
          final body = jsonDecode(bodyStr) as Map<String, dynamic>? ?? {};
          final msgs = (body['messages'] as List?) ?? const [];
          final lastUser = msgs.isNotEmpty ? (msgs.last['content']?.toString() ?? '') : '';
          final reply = await quickComplete(lastUser);
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
            'object': 'chat.completion',
            'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'model': state.modelId,
            'choices': [
              {
                'index': 0,
                'message': {
                  'role': 'assistant',
                  'content': reply.isEmpty
                      ? 'QuantumIDE Local OpenAI Server (${state.modelId}) обработал запрос: "$lastUser"'
                      : reply,
                },
                'finish_reason': 'stop',
              }
            ],
          }));
          await req.response.close();
          return;
        }

        req.response.statusCode = 404;
        req.response.write(jsonEncode({'error': 'Not found'}));
        await req.response.close();
      });
    } catch (_) {
      state = state.copyWith(isLocalServerRunning: false);
    }
  }

  Future<void> updateServerConfig({
    bool? allowNetwork,
    bool? requireKey,
    String? apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (allowNetwork != null) await prefs.setBool('q_srv_net', allowNetwork);
    if (requireKey != null) await prefs.setBool('q_srv_req_key', requireKey);
    if (apiKey != null) await prefs.setString('q_srv_api_key', apiKey);
    state = state.copyWith(
      localServerAllowNetwork: allowNetwork ?? state.localServerAllowNetwork,
      localServerRequireKey: requireKey ?? state.localServerRequireKey,
      localServerApiKey: apiKey ?? state.localServerApiKey,
    );
    if (state.isLocalServerRunning) {
      await toggleLocalOpenAiServer(true);
    }
  }

  Future<void> generateNewServerKey() async {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    final key = 'qide-${List.generate(20, (_) => chars[rnd.nextInt(chars.length)]).join()}';
    await updateServerConfig(apiKey: key);
  }

  // ─── Чекпоинты и построчный Diff (из Mobile-Harness WorkspaceCheckpoints) ──

  void _recordCheckpointDiff(String ws, String fullPath, String beforeContent, String afterContent) {
    final rel = p.relative(fullPath, from: ws);
    final beforeLines = beforeContent.isEmpty ? <String>[] : beforeContent.split('\n');
    final afterLines = afterContent.isEmpty ? <String>[] : afterContent.split('\n');

    final existingIdx = state.pendingChanges.indexWhere((c) => c.relativePath == rel);
    final baseline = existingIdx >= 0 ? state.pendingChanges[existingIdx].beforeContent : beforeContent;
    final baseLines = baseline.isEmpty ? <String>[] : baseline.split('\n');

    int additions = 0;
    int deletions = 0;
    final diffLines = <AgentDiffLine>[];

    final maxLen = max(baseLines.length, afterLines.length);
    for (int i = 0; i < maxLen && diffLines.length < 220; i++) {
      final oldL = i < baseLines.length ? baseLines[i] : null;
      final newL = i < afterLines.length ? afterLines[i] : null;
      if (oldL == newL && oldL != null) {
        diffLines.add(AgentDiffLine(
          type: AgentDiffLineType.context,
          text: oldL,
          oldLine: i + 1,
          newLine: i + 1,
        ));
      } else {
        if (oldL != null) {
          deletions++;
          diffLines.add(AgentDiffLine(
            type: AgentDiffLineType.deletion,
            text: oldL,
            oldLine: i + 1,
          ));
        }
        if (newL != null) {
          additions++;
          diffLines.add(AgentDiffLine(
            type: AgentDiffLineType.addition,
            text: newL,
            newLine: i + 1,
          ));
        }
      }
    }

    final item = WorkspaceChangeItem(
      relativePath: rel,
      beforeContent: baseline,
      afterContent: afterContent,
      additions: additions,
      deletions: deletions,
      diffLines: diffLines,
      timestamp: DateTime.now(),
    );

    final updated = List<WorkspaceChangeItem>.from(state.pendingChanges);
    if (existingIdx >= 0) {
      updated[existingIdx] = item;
    } else {
      updated.insert(0, item);
    }
    state = state.copyWith(pendingChanges: updated);
  }

  void acceptChange(String relativePath) {
    final updated = state.pendingChanges.where((c) => c.relativePath != relativePath).toList();
    state = state.copyWith(pendingChanges: updated);
  }

  Future<void> undoChange(String relativePath) async {
    final ws = _ref.read(workspaceProvider).currentPath;
    if (ws == null) return;
    final idx = state.pendingChanges.indexWhere((c) => c.relativePath == relativePath);
    if (idx < 0) return;
    final item = state.pendingChanges[idx];
    final fullPath = p.join(ws, item.relativePath);
    try {
      final file = File(fullPath);
      if (item.beforeContent.isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(item.beforeContent, flush: true);
        await _mirrorAndReloadInIde(ws, fullPath, item.beforeContent, []);
      }
    } catch (_) {}
    final updated = List<WorkspaceChangeItem>.from(state.pendingChanges)..removeAt(idx);
    state = state.copyWith(pendingChanges: updated);
  }

  void acceptAllChanges() {
    state = state.copyWith(pendingChanges: const []);
  }

  Future<void> undoAllChanges() async {
    for (final item in List<WorkspaceChangeItem>.from(state.pendingChanges)) {
      await undoChange(item.relativePath);
    }
  }

  // ─── Разбор <think>...</think> (из cross-platform-llm-client ThoughtParser) ─

  ({String cleanContent, String? thinking}) _parseThought(String raw) {
    final thinkRegex = RegExp(r'<think>([\s\S]*?)</think>', caseSensitive: false);
    final match = thinkRegex.firstMatch(raw);
    if (match != null) {
      final thought = match.group(1)?.trim();
      final cleaned = raw.replaceAll(thinkRegex, '').trim();
      return (cleanContent: cleaned, thinking: (thought != null && thought.isNotEmpty) ? thought : null);
    }
    return (cleanContent: raw, thinking: null);
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

  /// Быстрая генерация текста (например, для сообщения коммита в GitPanel или локального сервера)
  Future<String> quickComplete(String prompt) async {
    if (state.apiKey.isEmpty || state.providerId == 'antigravity_doctor') {
      return '';
    }
    try {
      final preset = QuantumAgentProviderPreset.byId(state.providerId);
      final targetUrl = (state.providerId == 'custom' && state.customBaseUrl.isNotEmpty)
          ? state.customBaseUrl
          : preset.baseUrl;
      final res = await _dio.post(
        targetUrl,
        options: Options(headers: {
          'Authorization': 'Bearer ${state.apiKey}',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': state.modelId,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': state.temperature,
          'max_tokens': 250,
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
      thinking: 'Анализирую задачу и рабочее пространство (${state.modelId})...',
      isStreaming: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, placeholder],
      isWorking: true,
      statusText: 'Анализ проекта...',
    );

    _writeBridgeInbox(clean);

    try {
      final preset = QuantumAgentProviderPreset.byId(state.providerId);
      if (preset.id == 'antigravity_doctor' || (preset.requiresKey && state.apiKey.trim().isEmpty)) {
        await _runAutonomousDoctorAndBridge(assistantMsgId, clean);
      } else {
        await _runLlmAgentLoop(assistantMsgId, clean, preset);
      }
    } catch (e) {
      _updateAssistantMessage(
        assistantMsgId,
        content: '⚠️ Произошла ошибка при обращении к API: `$e`\n\nЗапускаю встроенный локальный Авто-Доктор...',
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
        'provider': state.providerId,
        'model': state.modelId,
        'harness': state.selectedHarness,
        'effort': state.antigravityEffort,
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
    int? thinkingDurationMs,
    List<AgentToolCall>? toolCalls,
    List<String>? modifiedFiles,
    bool? isStreaming,
  }) {
    final updated = state.messages.map((m) {
      if (m.id != id) return m;
      return m.copyWith(
        content: content ?? m.content,
        thinking: thinking ?? m.thinking,
        thinkingDurationMs: thinkingDurationMs ?? m.thinkingDurationMs,
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
    final sw = Stopwatch()..start();
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
      sw.stop();
      _updateAssistantMessage(
        msgId,
        thinking: 'Синхронизация и запуск сборщика выполнены (${state.modelId}, effort=${state.antigravityEffort}).',
        thinkingDurationMs: sw.elapsedMilliseconds,
        content: '🚀 **Сборка APK запущена в терминале сборки!**\n\n'
            '• Перед стартом синхронизированы все файлы из `/storage/emulated/0/QuantumIDE/${p.basename(ws)}`.\n'
            '• Вывод компиляции в реальном времени записывается в `LiveTelemetryService`.\n'
            '• Если возникнет ошибка компиляции — нажмите **«🔧 Исправить ошибки»**, и я сразу разберу лог!',
        modifiedFiles: modified,
        isStreaming: false,
      );
      return;
    }

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
    sw.stop();

    final buffer = StringBuffer();
    if (appendMode) {
      buffer.writeln('---');
    }
    buffer.writeln('### ⚡ Отчёт Quantum Agent по проекту `${p.basename(ws)}`\n');
    buffer.writeln('🤖 **Активный движок:** `${state.selectedHarness}` · **Модель:** `${state.modelId}`\n');

    if (syncedFiles.isNotEmpty) {
      buffer.writeln('✅ **Синхронизировано и восстановлено из `/storage/emulated/0/QuantumIDE/${p.basename(ws)}`:**');
      for (final f in syncedFiles.take(10)) {
        buffer.writeln('- `$f`');
      }
      buffer.writeln();
    } else {
      buffer.writeln('✅ **Синхронизация файлов:** Все файлы во внутренней памяти и `/storage/emulated/0/QuantumIDE/${p.basename(ws)}` полностью идентичны (0-байтовых файлов нет).\n');
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

    _updateAssistantMessage(
      msgId,
      thinking: 'Диагностика, синхронизация и проверка сборщика завершены (${sw.elapsedMilliseconds} мс).',
      thinkingDurationMs: sw.elapsedMilliseconds,
      content: buffer.toString(),
      modifiedFiles: modified,
      isStreaming: false,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ПОЛНЫЙ АВТОНОМНЫЙ ЦИКЛ LLM-АГЕНТА (ReAct + Tool Calling + OpenRouter)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _runLlmAgentLoop(
    String msgId,
    String userPrompt,
    QuantumAgentProviderPreset preset,
  ) async {
    final sw = Stopwatch()..start();
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

    final extraSystem = state.systemPromptPreset == 'custom' && state.customSystemPrompt.trim().isNotEmpty
        ? '\nДОПОЛНИТЕЛЬНАЯ ИНСТРУКЦИЯ ПОЛЬЗОВАТЕЛЯ:\n${state.customSystemPrompt.trim()}\n'
        : state.systemPromptPreset == 'uncensored'
            ? '\nРежим: Uncensored (отвечай прямо и без лишних дисклеймеров).\n'
            : '';

    final systemPrompt = '''
Ты — Quantum Agent (PrivateLM + Mobile Harness), автономный ИИ-инженер внутри мобильной среды разработки Quantum IDE.
Текущий проект: $ws (зеркало во внешней памяти: /storage/emulated/0/QuantumIDE/${p.basename(ws)}).
Открытый файл в редакторе: ${activeFile != null ? p.relative(activeFile.path, from: ws) : 'нет'}.
Статус последней сборки: ${LiveTelemetryService.instance.currentBuildStatus}.$extraSystem

ТВОИ ИНСТРУМЕНТЫ (вызывай через XML блок <tool_call>):
<tool_call>
{"name": "ИМЯ_ИНСТРУМЕНТА", "arguments": {...}}
</tool_call>

Доступные инструменты:
1. "list_files": {"subdir": "опциональная подпапка, например lib"} — список файлов проекта.
2. "search_code": {"query": "строка поиска", "subdir": "lib"} — поиск текста по файлам проекта.
3. "read_file": {"path": "относительный путь, например lib/main.dart", "start_line": 1, "end_line": 200} — чтение файла с номерами строк.
4. "edit_file": {"path": "относительный путь", "target": "точный фрагмент старого кода", "replacement": "новый код"} — точечная замена кода в файле.
5. "write_file": {"path": "относительный путь", "content": "полный текст файла"} — создание или перезапись файла.
6. "run_command": {"command": "команда bash/flutter", "in_terminal": false} — запуск команды в проекте.
7. "get_diagnostics": {} — получить все текущие ошибки синтаксиса Dart и последние строки лога сборки APK.

ПРАВИЛА РАБОТЫ:
- Всегда сначала проверяй файлы через read_file или get_diagnostics перед редактированием.
- Когда исправляешь код через edit_file или write_file, пиши полный рабочий код без заглушек.
- Отвечай кратко, по делу, на русском языке.
''';

    final conversation = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    final history = state.messages.where((m) => m.id != msgId && m.id != 'welcome').toList();
    for (final h in history.skip(history.length > 6 ? history.length - 6 : 0)) {
      conversation.add({
        'role': h.role,
        'content': h.content,
      });
    }

    String finalAnswer = '';
    const maxSteps = 8;
    final targetUrl = (state.providerId == 'custom' && state.customBaseUrl.isNotEmpty)
        ? state.customBaseUrl
        : preset.baseUrl;

    for (int step = 1; step <= maxSteps; step++) {
      if (_cancelRequested) break;
      state = state.copyWith(statusText: 'Шаг $step: размышление (${state.modelId})...');

      final payload = <String, dynamic>{
        'model': state.modelId,
        'messages': conversation,
        'temperature': state.temperature,
        'max_tokens': state.maxTokens,
        if (state.stopSequences.isNotEmpty) 'stop': state.stopSequences,
      };

      // OpenRouter Routing Gateway (из Mobile-Harness OpenRouterRoutingGateway.kt)
      if (preset.id == 'openrouter' && state.openRouterProviderOrder.trim().isNotEmpty) {
        final order = state.openRouterProviderOrder
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (order.isNotEmpty) {
          payload['provider'] = {
            'order': order,
            'allow_fallbacks': state.openRouterAllowFallbacks,
          };
        }
      }

      final response = await _dio.post(
        targetUrl,
        options: Options(headers: {
          if (state.apiKey.isNotEmpty) 'Authorization': 'Bearer ${state.apiKey}',
          'Content-Type': 'application/json',
          if (preset.id == 'openrouter') 'HTTP-Referer': 'https://github.com/Lesorub361/quantum_ide',
          if (preset.id == 'openrouter') 'X-Title': 'QuantumIDE Agent',
        }),
        data: payload,
      );

      final choices = response.data['choices'] as List?;
      if (choices == null || choices.isEmpty) break;
      final msgObj = choices.first['message'] as Map<String, dynamic>? ?? {};
      final rawContent = msgObj['content']?.toString() ?? '';
      final reasoning = msgObj['reasoning_content']?.toString();

      final thoughtParsed = _parseThought(rawContent);
      final parsedCalls = _extractXmlToolCalls(thoughtParsed.cleanContent);
      final cleanText = thoughtParsed.cleanContent
          .replaceAll(RegExp(r'<tool_call>[\s\S]*?</tool_call>'), '')
          .trim();

      final combinedThinking = (reasoning != null && reasoning.isNotEmpty)
          ? reasoning
          : thoughtParsed.thinking;

      if (combinedThinking != null && combinedThinking.isNotEmpty) {
        _updateAssistantMessage(
          msgId,
          thinking: combinedThinking,
          thinkingDurationMs: sw.elapsedMilliseconds,
        );
      }

      if (cleanText.isNotEmpty) {
        finalAnswer = cleanText;
        _updateAssistantMessage(msgId, content: finalAnswer);
      }

      if (parsedCalls.isEmpty) {
        break;
      }

      conversation.add({'role': 'assistant', 'content': rawContent});

      final toolResultsText = StringBuffer();
      for (final callSpec in parsedCalls) {
        if (_cancelRequested) break;
        final name = callSpec['name']?.toString() ?? '';
        final args = (callSpec['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
        final tcId = 'tc_${DateTime.now().millisecondsSinceEpoch}_${toolCallsUi.length}';
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

    sw.stop();
    _updateAssistantMessage(
      msgId,
      content: finalAnswer.isEmpty ? '✅ Задача выполнена.' : finalAnswer,
      thinkingDurationMs: sw.elapsedMilliseconds,
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
  // 3. РЕАЛИЗАЦИЯ ИНСТРУМЕНТОВ АГЕНТА + ЧЕКПОИНТЫ DIFF
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
          _recordCheckpointDiff(ws, fullPath, content, newContent);
          await file.writeAsString(newContent, flush: true);
          await _mirrorAndReloadInIde(ws, fullPath, newContent, modifiedFiles);
          final syntaxDiags = FastSyntaxEngine.instance.analyze(fullPath, newContent);
          final errs = syntaxDiags.where((d) => d.severity == CodeDiagnosticSeverity.error).toList();
          if (errs.isNotEmpty) {
            return 'Файл $reqPath обновлён, но анализатор нашёл синтаксические ошибки:\n'
                '${errs.map((e) => "Строка ${e.range.index + 1}: ${e.message}").join("\n")}';
          }
          return 'SUCCESS: Файл $reqPath успешно обновлён, добавлен в Changes (Diff) и синхронизирован.';
        }

        case 'write_file': {
          final reqPath = args['path']?.toString() ?? '';
          final content = args['content']?.toString() ?? '';
          if (reqPath.isEmpty || content.isEmpty) {
            return 'ERROR: Для write_file требуются непустые path и content';
          }
          final fullPath = p.isAbsolute(reqPath) ? reqPath : p.join(ws, reqPath);
          final file = File(fullPath);
          final oldContent = await file.exists() ? await file.readAsString() : '';
          await file.parent.create(recursive: true);
          _recordCheckpointDiff(ws, fullPath, oldContent, content);
          await file.writeAsString(content, flush: true);
          await _mirrorAndReloadInIde(ws, fullPath, content, modifiedFiles);
          return 'SUCCESS: Файл $reqPath записан (${content.length} байт), сохранён в Changes (Diff) и синхронизирован.';
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
      final oldContent = content;
      bool changed = false;

      if (!content.contains('org.gradle.jvmargs=-Xmx1280m') && !content.contains('org.gradle.jvmargs=-Xmx1536m')) {
        content = content.replaceAll(RegExp(r'org\.gradle\.jvmargs=.*'), '');
        content = '${content.trim()}\norg.gradle.jvmargs=-Xmx1280m -XX:MaxMetaspaceSize=384m\n';
        changed = true;
      }
      if (!content.contains('org.gradle.daemon=false')) {
        content = '${content.trim()}\norg.gradle.daemon=false\norg.gradle.workers.max=1\norg.gradle.parallel=false\nkotlin.compiler.execution.strategy=in-process\n';
        changed = true;
      }
      if (!content.contains('android.aapt2FromMaven=false')) {
        content = '${content.trim()}\nandroid.aapt2FromMaven=false\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\nandroid.aapt2.daemon=false\n';
        changed = true;
      }

      if (changed) {
        _recordCheckpointDiff(ws, gpFile.path, oldContent, content);
        await gpFile.writeAsString(content, flush: true);
        await _mirrorAndReloadInIde(ws, gpFile.path, content, modified);
        return 'Оптимизированы флаги памяти (-Xmx1280m, in-process Kotlin, daemon=false) в android/gradle.properties.';
      }
      return 'android/gradle.properties уже оптимален (-Xmx1280m, daemon=false, native aapt2).';
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
